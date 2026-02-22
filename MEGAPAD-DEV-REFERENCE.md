# Megapad-64 Developer Reference for Kalki

Everything you need to know to write applications — specifically a GUI
framework — for the Megapad-64 platform.  This is a distillation of the
megapad repo docs, not a copy.  Go to `emu/docs/` for exhaustive detail.

---

## 1. System Overview

Megapad-64 is a fantasy computer with a **64-bit CPU**, a **64-byte SIMD
tile engine**, and a **Forth BIOS + KDOS operating system** — all running
in a Python emulator (with optional C++ accelerator).

The software stack:

```
┌──────────────────────────────────────┐
│  User Programs / Loadable Modules    │  ← graphics.f, tools.f, Kalki
├──────────────────────────────────────┤
│  KDOS v1.1  (10,225 lines Forth)     │  ← buffers, kernels, scheduler,
│  ~1,361 entities (871 defs + 490 var)│    filesystem, TUI, network, etc.
├──────────────────────────────────────┤
│  BIOS v1.0  (12,162 lines ASM)      │  ← 346 Forth words, subroutine-
│                                      │    threaded interpreter/compiler
├──────────────────────────────────────┤
│  Hardware / Emulator                 │  ← megapad64.py + devices.py
└──────────────────────────────────────┘
```

**Key principle:** The BIOS Forth never exits.  KDOS extends it.  User
modules extend KDOS.  Everything is Forth words — there is no process
model, no binary loader, no ELF.

---

## 2. Memory Map

| Address Range | Size | Content |
|---|---|---|
| `0x0000_0000` – `0x000F_FFFF` | 1 MiB | **Bank 0** — BIOS + KDOS dictionary + buffers + stacks |
| `0x0010_0000` – `0x010F_FFFF` | 16 MiB | **External Memory** — userland dictionary (modules load here) |
| `0xFFD0_0000` – `0xFFFF_FFFF` | 3 MiB | **Banks 1–3 (HBW)** — tile/SIMD working memory, framebuffer |
| `0xFFFF_FF00_0000_0000`+ | MMIO | **Peripheral registers** |

### Important for GUI work

- **Framebuffer lives in HBW**, specifically Bank 3 (`HBW-BASE + 0x200000`).
  At 640×480×8bpp that's 300 KiB — fits comfortably.
- **External memory** (`EXT-MEM-BASE`, `EXT-MEM-SIZE`) can also host the
  framebuffer if preferred; `GFX-INIT` picks ext mem first, HBW second.
- The dictionary grows upward from `HERE`; the data stack grows downward
  from the top of Bank 0.  Don't allocate big buffers in the dictionary
  — use HBW or ext mem.
- A cell is 8 bytes.  Tiles are 64-byte-aligned.

---

## 3. MMIO Peripherals Relevant to a GUI

| Device | Offset | What It Does for a GUI |
|---|---|---|
| **Framebuffer** | `+0x0A00` | Scanout controller — points at a RAM region, configures resolution/mode/palette, provides vsync |
| **UART** | `+0x0000` | Keyboard input (`KEY`, `KEY?`), serial output (`EMIT`) |
| **Timer** | `+0x0100` | Animation timing, preemptive scheduling |
| **RTC** | `+0x0B00` | Wall-clock time for clock widgets, timestamps |
| **Storage** | `+0x0200` | Loading/saving files (fonts, images, config) |
| **NIC** | `+0x0400` | Network data (if building a browser or network-aware widgets) |

### Framebuffer Registers

| Register | Offset | Description |
|---|---|---|
| `FB_BASE` | `+0x00` | 64-bit start address of pixel data in RAM |
| `FB_WIDTH` | `+0x08` | Active width in pixels (32-bit) |
| `FB_HEIGHT` | `+0x10` | Active height in pixels (32-bit) |
| `FB_STRIDE` | `+0x18` | Bytes per scanline (32-bit) |
| `FB_MODE` | `+0x20` | Pixel format: 0=8bpp indexed, 1=RGB565, 2=FP16, 3=RGBA8888 |
| `FB_ENABLE` | `+0x28` | bit 0: scanout on, bit 1: vsync IRQ |
| `FB_VSYNC` | `+0x30` | Frame counter (read) / ack (write 1) |
| `FB_PAL_IDX` | `+0x38` | Palette index for next write |
| `FB_PAL_DATA` | `+0x40` | 24-bit RGB palette entry (0x00RRGGBB) |
| `FB_STATUS` | `+0x48` | bit 0: enabled, bit 1: in-vblank |

**BIOS words:** `FB-BASE!`, `FB-WIDTH!`, `FB-HEIGHT!`, `FB-STRIDE!`,
`FB-MODE!`, `FB-ENABLE`, `FB-DISABLE`, `FB-VSYNC@`, `FB-VSYNC-ACK`,
`FB-PAL!`, `FB-STATUS@`.

### Pixel Modes and Tile Alignment

| Mode | BPP | Tile Lanes | Framebuffer Size (640×480) |
|---|---|---|---|
| 0 (indexed) | 8 | 64 pixels/tile | 300 KiB |
| 1 (RGB565) | 16 | 32 pixels/tile | 600 KiB |
| 3 (RGBA8888) | 32 | 16 pixels/tile | 1.2 MiB |

**Mode 0 (8bpp indexed) is the sweet spot** — maximum tile lanes, fits in
HBW, 256-color palette is plenty for a GUI.

---

## 4. The Tile Engine (SIMD Accelerator)

The tile engine processes 64-byte tiles via CSR-controlled SIMD operations.
This is **the primary rendering accelerator** — there is no GPU.

### Key CSRs

| CSR | Forth Word | Purpose |
|---|---|---|
| `TSRC0` | `TSRC0!` | Source tile 0 address |
| `TSRC1` | `TSRC1!` | Source tile 1 address |
| `TDST` | `TDST!` | Destination tile address |
| `TMODE` | `TMODE!` | Element width + signed + saturate + rounding |
| `TCTRL` | `TCTRL!` | Accumulator control (ACC_ZERO, ACC_ACC) |
| `ACC0-ACC3` | `ACC@` etc. | 256-bit accumulator readback |

### Operations Available

| Category | Operations | Notes |
|---|---|---|
| **ALU** (TALU) | ADD, SUB, AND, OR, XOR, MIN, MAX, ABS | Element-wise src0 × src1 → dst |
| **Multiply** (TMUL) | MUL, DOT | Element-wise multiply, dot product → ACC |
| **Reduction** (TRED) | SUM, MIN, MAX, POPCNT, L1 | Reduce tile → ACC |
| **System** (TSYS) | TRANS, ZERO, LOADC, MOVBANK, TFILL | Transpose, zero, cursor load, bank move, fill |
| **Extended** | VSHR, VSHL, VCLZ, FMA, WIDENMUL, LOAD2D, STORE2D | Shifts, 2D strided access |

### Source Selection Modes

| Mode | Description | GUI Use |
|---|---|---|
| Tile × Tile | Two independent tiles → dst | Blending, compositing |
| Broadcast | One tile + register splatted to all lanes | Color fill, scaling |
| Imm8 Splat | Add small constant to all elements | Brightness adjust |
| In-Place | Destination is also source A | In-place transforms |

### 2D Strided Access (Critical for GUI)

The tile engine can load/store non-contiguous data from a 2D image:

| CSR | Forth Word | Purpose |
|---|---|---|
| `TSTRIDE_R` | `TSTRIDE-R!` | Row stride in bytes |
| `TTILE_H` | `TTILE-H!` | Rows to load (1–8) |
| `TTILE_W` | `TTILE-W!` | Columns per row in bytes |

This means you can load an 8×8 glyph from a 640-byte-wide framebuffer
in one `LOAD2D` instruction + tile op + `STORE2D`.  Essential for
fast blitting into non-tile-aligned framebuffer regions.

---

## 5. Forth Essentials for GUI Development

### The Module System

```forth
REQUIRE graphics.f    \ Load if not already loaded
PROVIDED kalki.f      \ Mark this module as loaded
```

Modules are MP64FS files loaded via `FSLOAD` and tracked by a bitmap.
`REQUIRE` is idempotent.

### Memory Allocation

| Mechanism | Words | Lifetime | GUI Use |
|---|---|---|---|
| Dictionary | `HERE`, `,`, `ALLOT` | Permanent | Widget descriptors, static data |
| Heap | `ALLOCATE`, `FREE`, `RESIZE` | Manual | Dynamic window/panel allocations |
| HBW Bump | `HBW-ALLOT`, `HBW-BUFFER` | Until `HBW-RESET` | Framebuffer, sprite buffers |
| XMEM Bump | `XMEM-ALLOT` | Until `XMEM-RESET` | Font data, large UI resources |
| Arena (planned) | `ARENA-NEW`, `ARENA-ALLOT`, `ARENA-RESET` | Scoped | Per-frame scratch, undo buffers |

### Input

- `KEY` — blocks until a byte arrives from UART
- `KEY?` — non-blocking check (returns flag)
- Arrow keys arrive as CSI escape sequences: `ESC [ A/B/C/D`
- Mouse: **not yet implemented** as a peripheral

### Timer & Animation

```forth
TIMER!         ( n -- )      \ Set compare-match value
TIMER-CTRL!    ( n -- )      \ Enable timer, IRQ, auto-reload
TIMER-ACK      ( -- )        \ Clear interrupt flag
EI!            ( -- )        \ Enable interrupts
ISR!           ( xt slot -- ) \ Install ISR at IVT slot
```

For animation loops, use `KEY?` polling + timer-based frame pacing:

```forth
: FRAME-LOOP
    BEGIN
        RENDER-FRAME
        GFX-SYNC          \ Wait for vsync
        KEY? IF KEY HANDLE-INPUT THEN
    DONE? UNTIL ;
```

### String Handling

```forth
S" hello"       ( -- addr len )    \ Compile-time string literal
." hello"                          \ Print immediately
TYPE            ( addr len -- )    \ Print string
COMPARE         ( a1 l1 a2 l2 -- n ) \ String comparison
WORD            ( delim -- addr )  \ Parse next word from input
```

### Execution Tokens & Callbacks

```forth
' my-word       ( -- xt )          \ Get execution token
EXECUTE         ( xt -- )          \ Call it
['] my-word     ( -- xt )          \ Compile-time tick (inside : def)
```

This is how the WVEC widget dispatch works — store xts in a table,
call via `EXECUTE`.

### Error Handling

```forth
['] risky-word CATCH   ( -- error-code | 0 )
                       \ 0 = success, non-zero = exception
n THROW                \ Raise exception n
```

---

## 6. Existing Graphics Infrastructure (graphics.f)

The current `graphics.f` provides low-level framebuffer drawing:

### Core State

```forth
GFX-W, GFX-H       \ Current resolution
GFX-BPP             \ Bytes per pixel
GFX-STR             \ Stride in bytes
GFX-FB              \ Framebuffer base address
GFX-CX, GFX-CY     \ Text cursor position
GFX-CLR             \ Current drawing color
```

### Initialization

```forth
320 240 0 GFX-INIT       \ Width×Height, mode 0 (8bpp indexed)
640 480 0 GFX-INIT-HBW   \ Force framebuffer into HBW Bank 3
```

### Drawing Primitives

| Word | Stack Effect | Description |
|---|---|---|
| `GFX-PIXEL!` | `( color x y -- )` | Set one pixel |
| `GFX-PIXEL@` | `( x y -- color )` | Read one pixel |
| `GFX-HLINE` | `( color x y len -- )` | Horizontal line |
| `GFX-VLINE` | `( color x y len -- )` | Vertical line |
| `GFX-RECT` | `( color x y w h -- )` | Filled rectangle |
| `GFX-BOX` | `( color x y w h -- )` | Rectangle outline |
| `GFX-BLIT` | `( src x y w h -- )` | Copy pixel data to screen |
| `GFX-CLEAR` | `( color -- )` | Clear entire screen (tile-accelerated) |
| `GFX-SYNC` | `( -- )` | Wait for vsync |
| `GFX-SCROLL-UP` | `( nrows -- )` | Scroll screen (incomplete) |

### Text Rendering

| Word | Stack Effect | Description |
|---|---|---|
| `GFX-CHAR` | `( char x y color -- )` | Render 8×8 glyph |
| `GFX-TYPE` | `( addr len color -- )` | Render string at cursor |
| `GFX-CR` | `( -- )` | Newline (advance cursor) |

- Built-in 8×8 bitmap font covering ASCII 32–127 (768 bytes)
- Text cursor maintained in `GFX-CX` / `GFX-CY`

### Palette

| Word | Stack Effect | Description |
|---|---|---|
| `GFX-PAL-DEFAULT` | `( -- )` | Load 16-color CGA palette |
| `GFX-PAL-GRAY` | `( -- )` | Load 256-level grayscale |
| `GFX-PAL-SET` | `( r g b idx -- )` | Set one palette entry |

---

## 7. Existing KDOS Screen/Widget System (TUI)

KDOS already has a **text-mode screen system** with a widget abstraction
layer.  This is relevant because Kalki should integrate with or replace it.

### Screen Registry

```forth
REGISTER-SCREEN   ( xt-render xt-label flags -- id | -1 )
UNREGISTER-SCREEN ( id -- )
SWITCH-SCREEN     ( id -- )
MAX-SCREENS       \ 16 slots
```

### Widget Vocabulary (WVEC dispatch)

The existing widgets dispatch through a vector table (`WVEC`), making
them renderer-swappable:

| Widget | Stack Effect | Purpose |
|---|---|---|
| `W.TITLE` | `( addr len -- )` | Bold title |
| `W.SECTION` | `( addr len -- )` | Sub-heading |
| `W.LINE` | `( addr len -- )` | Text line |
| `W.KV` | `( n addr len -- )` | Key-value (numeric) |
| `W.FLAG` | `( flag addr len -- )` | On/off indicator |
| `W.HBAR` | `( -- )` | Horizontal rule |
| `W.LIST` | `( count item-xt -- )` | Scrollable list |
| `W.DETAIL` | `( count xt -- )` | Detail pane |
| `W.INPUT` | `( buf maxlen prompt-a prompt-n -- len )` | Text input |

The TUI renderer (`INSTALL-TUI`) emits ANSI escape sequences.  A GUI
renderer would replace these xts with framebuffer-drawing equivalents.

### Event Loop

```forth
SCREEN-LOOP
    BEGIN
        KEY? IF KEY HANDLE-KEY THEN
        \ auto-refresh logic
    SCREEN-RUN @ 0= UNTIL
```

This polls `KEY?` and dispatches to per-screen key handlers.

---

## 8. File System (MP64FS)

Module files, fonts, images, and config can be stored in the on-disk
filesystem:

| Layout | Sectors | Content |
|---|---|---|
| Sector 0 | 1 | Superblock (magic "MP64") |
| Sector 1 | 1 | Allocation bitmap |
| Sectors 2–5 | 4 | Directory (64 entries × 32 bytes) |
| Sectors 6+ | ~2042 | Data area |

### File Types

| Code | Type | Use |
|---|---|---|
| 0 | free | — |
| 1 | raw | Binary data |
| 2 | text | Plain text |
| 3 | forth | Forth source (loadable via `FSLOAD`) |
| 4 | doc | Documentation |
| 5 | data | Structured data |
| 6 | tut | Tutorial |
| 7 | bundle | Pipeline bundle |

### Key Words

```forth
OPEN         ( "name" -- fdesc )
FREAD        ( addr len fdesc -- actual )
FWRITE       ( addr len fdesc -- )
FSEEK        ( pos fdesc -- )
FREWIND      ( fdesc -- )
FSIZE        ( fdesc -- n )
DIR          ( -- )              \ List all files
MKFILE       ( "name" type nsectors -- )
FSLOAD       ( "name" -- )       \ Load + evaluate Forth file
REQUIRE      ( "name" -- )       \ Idempotent FSLOAD
```

---

## 9. Boot Sequence

1. BIOS initializes from `bios.rom` (address 0)
2. If disk attached: `FSLOAD autoexec.f`
3. `autoexec.f`: network setup → enter userland → `REQUIRE tools.f`
4. The boot chain can be extended: `autoexec.f` can `REQUIRE kalki.f`
5. User lands at Forth REPL (or TUI if `SCREENS` is called)

### Userland Memory

When `ENTER-USERLAND` is called, `HERE` switches from Bank 0 to ext mem.
All subsequent definitions compile into ext mem, preserving system
dictionary space.  Kalki should load in userland.

---

## 10. Display System (Emulator Side)

The emulator has an optional `--display` flag that opens a pygame window:

- Reads pixel data from the framebuffer RAM region
- Applies palette (mode 0) or direct decode
- Renders at configurable scale (`--display-scale N`)
- Targets 30 FPS by default (`--display-fps N`)

This means Kalki's framebuffer rendering is immediately visible in a
window when using `--display`.

---

## 11. Constraints & Gotchas

1. **No mouse yet** — input is keyboard-only via UART.  Mouse would be
   a new MMIO peripheral.
2. **Stack depth** — Forth's data stack is the only "register file" —
   deep stack manipulation gets ugly fast.  Use variables and structures.
3. **No floating point** — the CPU has FP16/BF16 in the tile engine, but
   no scalar FPU.  GUI math is all integer.
4. **Single-threaded UI** — the event loop runs on one core.  Background
   tasks can run on other cores but must not touch framebuffer directly.
5. **ANSI TUI vs. Framebuffer** — these are separate output paths.  The
   UART console (ANSI TUI) and the framebuffer display are independent.
   Kalki targets the framebuffer, not the UART.
6. **Font is 8×8 only** — a richer GUI will want multiple font sizes.
   Proportional fonts require a glyph-width table.
7. **No alpha blending in tile engine** — compositing with transparency
   requires manual per-pixel work or clever palette tricks.
8. **`GFX-BLIT` is incomplete** — the current implementation has source
   pointer arithmetic issues.  Needs rewriting.
9. **`GFX-SCROLL-UP` is incomplete** — only clears the bottom, doesn't
   properly scroll.
10. **No double-buffering** — but achievable by allocating two FB regions
    and swapping `FB-BASE!` on vsync.
