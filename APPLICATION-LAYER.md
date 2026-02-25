# Kalki Application Layer — Design & Execution Plan

## Problem Statement

Today, the desktop shell (`kalki-desktop.f`) hardcodes two "apps":
a file manager and an editor.  They share the same widget tree, the same
variables, and the same memory.  Closing the editor tears down widgets
that the desktop expects to still exist, corrupting state.  There is no
isolation or lifecycle management.

Worse: if both apps `REQUIRE kalki-menu.f`, there's one `_MN-SEL`
variable.  Two apps using menus simultaneously stomp each other's state.
Forth's dictionary is a single linked list — `VARIABLE FOO` creates
one `FOO`, period.  No namespaces, no scoping.

The application layer fixes this with **true process isolation**.
Each app runs in its own process with:
- Its own **dictionary** (separate `LATEST` and `HERE`)
- Its own **memory region** (XMEM zone for code + data)
- Its own **arena** (bulk data allocation)
- Its own **PROVIDED registry** (independent REQUIRE tracking)
- **CATCH/THROW** error containment
- Clean teardown — kill process, all memory gone

---

## How Dictionary Isolation Works

The Megapad-64 dictionary is a singly-linked list anchored at `var_latest`.
`FIND` walks from `LATEST` backwards through link pointers to link=0.

```
LATEST → wordN → wordN-1 → ... → word1 → (BIOS words) → 0
```

**Per-process dictionaries** work by forking the chain:

```
System boot:   LATEST → SYS-LAST → ... → BIOS-FIRST → 0

Process A:     A-LATEST → A-wordN → ... → A-word1 → SYS-LAST → ... → 0
Process B:     B-LATEST → B-wordM → ... → B-word1 → SYS-LAST → ... → 0
```

Each process's words link back to the system dictionary tail.
Swapping `var_latest` between A-LATEST and B-LATEST switches
which process's words are visible.  System words (KDOS, BIOS,
shared Kalki infrastructure) are always reachable — they're at
the tail of every chain.

**Context switch saves/restores:**

| Register | What | Mechanism |
|----------|------|-----------|
| `var_here` | Dictionary pointer | Already done by ENTER-USERLAND |
| `var_latest` | Most recent word | New: `LATEST!` (KDOS already provides this) |
| `_MOD-HT` pointer | PROVIDED registry | New: per-process hash table |
| Arena handle | Current arena for AALLOT | `ARENA-PUSH` / `ARENA-POP` |

**Memory layout** (dynamic allocation from system memory):

```
Dict zones:  1 MiB default per process, allocated on demand
             via XMEM-ALLOT, freed on APP-KILL.
Arenas:      256 KiB default per process (heap-backed).
Table:       256 slots × 96 bytes = 24 KiB in system dict.
```

Each process gets a 1 MiB dict zone by default.  On a real PC
with gigabytes of RAM this is trivial — 256 simultaneous
processes use 256 MiB for dict zones alone, well within range.

---

## KDOS Primitives Used

| Primitive | What it gives us | Status |
|-----------|-----------------|--------|
| `var_latest` / `LATEST!` | Dictionary chain head — swap per process | **Ready** |
| `var_here` / `ALLOT` | Dictionary pointer — swap per process | **Ready** |
| `ARENA-NEW / ARENA-DESTROY` | Per-process data memory, bulk-free on kill | **Ready** |
| `ARENA-PUSH / ARENA-POP` | Scoped arena for AALLOT | **Ready** |
| `CATCH / THROW` | Exception containment — app crash ≠ desktop crash | **Ready** |
| `ALLOCATE / FREE` | Heap alloc for widgets (shared heap) | **Ready** |
| `HASHTABLE / HT-PUT / HT-GET` | Per-process PROVIDED registry | **Ready** |
| `XMEM-ALLOT` | XMEM region for per-process dict zones | **Ready** |
| `CL-MPU-SETUP` | Hardware memory fencing (future: multi-core) | **Ready** |
| `CORE-DISPATCH` | Run process on micro-core (future) | **Ready** |
| `RING-PUSH / RING-POP` | IPC event queues (future: multi-core) | **Ready** |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  App Processes                                          │
│    Each has: dictionary, arena, widgets, event handler  │
│    ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│    │ File Mgr │  │  Editor  │  │ (future) │            │
│    │ own dict │  │ own dict │  │ own dict │            │
│    │ own vars │  │ own vars │  │ own vars │            │
│    └────┬─────┘  └────┬─────┘  └────┬─────┘            │
│         │              │              │                  │
├─────────┴──────────────┴──────────────┴──────────────────┤
│  kalki-app.f — Process Manager                          │
│    Dictionary context switch (LATEST + HERE + MOD-HT)   │
│    APP-LAUNCH / APP-KILL / APP-SWITCH / APP-DELIVER     │
│    CATCH wrapping, XMEM region management               │
├─────────────────────────────────────────────────────────┤
│  kalki-desktop.f — Desktop Shell                        │
│    Root surface, taskbar, process list, event routing    │
│    NO app-specific code — just process management       │
├─────────────────────────────────────────────────────────┤
│  System Dictionary (shared, loaded once at boot)        │
│    kalki-gfx.f  kalki-color.f  kalki-widget.f           │
│    kalki-basic.f  kalki-window.f  kalki-app.f           │
│    kalki-desktop.f                                      │
│    (Stateless or global-by-nature: drawing, themes,     │
│     widget tree, window manager, focus)                  │
├─────────────────────────────────────────────────────────┤
│  KDOS + BIOS + Hardware                                 │
└─────────────────────────────────────────────────────────┘
```

**System dictionary** (loaded once, shared by all processes):
- KDOS, BIOS, graphics.f, tools.f
- kalki-gfx.f, kalki-color.f — drawing primitives, stateless
- kalki-widget.f — widget tree, focus management (global state OK:
  there's one focused widget at a time, one widget tree)
- kalki-basic.f — label/button factories (thin wrappers)
- kalki-window.f — window manager (global WIN-TABLE is correct:
  one window manager for the whole desktop)
- kalki-app.f — process manager itself
- kalki-desktop.f — desktop shell

**Per-process dictionary** (loaded fresh per app):
- kalki-menu.f — per-dropdown state (_MN-SEL, _MN-MENU, etc.)
- kalki-scroll.f — per-scrollbar state
- kalki-editor.f — per-editor state (gap buffer, _EK-* variables)
- App-specific code (kalki-app-filemgr.f, kalki-app-editor.f)

Each process `REQUIRE`s the libraries it needs.  Because each process
has its own `LATEST` chain and its own `_MOD-HT`, each gets its own
copy of every VARIABLE, every CREATE'd buffer, every word definition.
Two editors open simultaneously → two independent `_MN-SEL` variables,
two gap buffers, two sets of editor state.  Zero conflicts.

---

## Process Descriptor

Process table: 256 × 96-byte descriptors in system dictionary space.

```
Offset  Size  Field          Description
──────  ────  ─────          ───────────
  +0    cell  AP.STATE       0=free, 1=running, 2=suspended
  +8    cell  AP.ARENA       arena handle (for bulk data)
  +16   cell  AP.ROOT        root widget (window) of this app
  +24   cell  AP.ONKEY       XT of app's key handler ( key -- consumed? )
  +32   cell  AP.CLEANUP     XT of app's cleanup word (or 0)
  +40   cell  AP.LATEST      saved var_latest for this process
  +48   cell  AP.HERE        saved var_here for this process
  +56   cell  AP.MODHT       per-process _MOD-HT address
  +64   cell  AP.DICT-BASE   start of this process's XMEM dict zone
  +72   cell  AP.DICT-SIZE   size of dict zone (default 1 MiB)
  +80   16B   AP.NAME        app name string (null-padded)
────────────────────────────────────────────────
  96 bytes per slot  ×  256 slots  =  24 KiB total
```

---

## App Lifecycle

### Launch

```forth
APP-LAUNCH  ( entry-xt name-addr name-len -- pid | -1 )
  1. Find free slot in process table (scan AP.STATE = 0)
  2. Allocate XMEM region for process dictionary (1 MiB default)
  3. ARENA-NEW ( 65536 0 ) — 64 KiB arena for bulk data
  4. Allocate per-process _MOD-HT (HASHTABLE in system dict)
  5. Record name, entry XT in descriptor
  ── Context switch INTO new process ──
  6. Save desktop's LATEST, HERE, _MOD-HT → desktop context
  7. Set HERE → process's XMEM dict zone base
  8. Set LATEST → system LATEST (fork point — process chain
     starts here, linked to all system words)
  9. Set _MOD-HT → process's hash table
  10. ARENA-PUSH (process's arena becomes current)
  ── Load app code ──
  11. [CATCH] EXECUTE entry-xt
      entry-xt:
        - REQUIRE kalki-menu.f, kalki-editor.f, etc. as needed
          (each loads fresh into THIS process's dict zone)
        - Create window, widgets
        - Store root widget via APP-SET-ROOT
        - Set key handler via APP-SET-ONKEY
        - Return normally (do NOT enter event loop)
  12. If THROW → save state, context-switch back, APP-KILL, return -1
  ── Context switch BACK to desktop ──
  13. Save process's LATEST, HERE → AP.LATEST, AP.HERE
  14. Restore desktop's LATEST, HERE, _MOD-HT
  15. ARENA-POP
  16. Set AP.STATE = 1 (running)
  17. Focus this app
  18. Return pid (0–7)
```

### Kill

```forth
APP-KILL  ( pid -- )
  1. Unfocus if this was the focused app
  2. WG-FREE-SUBTREE on AP.ROOT (frees all widget memory from heap)
  3. WIN-UNREGISTER the app's window
  4. Context-switch to process (restore LATEST/HERE) briefly:
     - AP.CLEANUP @ EXECUTE if non-zero (app-specific teardown)
  5. Context-switch back to desktop
  6. ARENA-DESTROY (bulk-free all arena data)
  7. Free the XMEM dict region (XMEM-FREE-BLOCK)
  8. Free per-process _MOD-HT
  9. Zero the entire process table slot (AP.STATE = 0)
  10. Switch focus to next running app or desktop
  11. Mark desktop dirty for full repaint
```

### Event Dispatch

```forth
APP-DELIVER  ( key pid -- consumed? )
  1. AP.STATE @ 1 <> IF 2DROP 0 EXIT THEN
  ── Context switch to process ──
  2. Save desktop LATEST/HERE/_MOD-HT
  3. Restore process LATEST/HERE/_MOD-HT from descriptor
  ── Dispatch key ──
  4. AP.ONKEY @ ( key xt )
  5. [CATCH] EXECUTE
  6. If THROW → print error, context-switch back, APP-KILL pid, return 0
  ── Context switch back to desktop ──
  7. Save process LATEST/HERE → descriptor
  8. Restore desktop LATEST/HERE/_MOD-HT
  9. Return consumed flag
```

Why context-switch for every key?  Because the app's ONKEY handler
may call words defined in the process's dictionary (its copy of
`_MN-MODAL`, its menu state, its editor words).  FIND must see
the process's dictionary chain, not the desktop's.

### Switch (Alt-Tab)

```forth
APP-SWITCH  ( pid -- )
  1. Current app: WGF-VISIBLE WG-CLR-FLAG on AP.ROOT
  2. Update APP-FOCUSED to new pid
  3. New app: WGF-VISIBLE WG-SET-FLAG on AP.ROOT
  4. Focus new app's root widget
  5. Mark all dirty for full repaint
```

No context switch needed — just visibility flags and focus.
Context switch happens on next key delivery.

---

## Desktop Event Loop (refactored)

```forth
: _DK-LOOP  ( -- )
    -1 DK-RUNNING !
    \ Initial render
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE  FB-SWAP
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE  FB-SWAP
    BEGIN
        \ Clock
        ...update clock, dirty clock label...
        \ Render
        DK-ROOT @ RENDER-TREE  FB-SWAP
        IDLE
        \ Input
        KEY? IF
            EKEY
            \ Desktop-level shortcuts (always handled, never forwarded)
            DUP K-CTRL-N = IF DROP APP-NEXT          ELSE
            DUP K-CTRL-Q = IF DROP APP-KILL-CURRENT  ELSE
            \ Forward to focused app
            APP-FOCUSED @ DUP 0< IF
                DROP _DK-HANDLE-KEY      \ no app focused
            ELSE
                APP-DELIVER              \ ( key pid -- consumed? )
                0= IF _DK-HANDLE-KEY THEN  \ unhandled → desktop
            THEN THEN THEN
        THEN
        DK-RUNNING @ 0=
    UNTIL ;
```

No hardcoded editor routing, no file-manager key handling.
The desktop is ~150 lines: root render, taskbar, clock, event loop.

---

## System vs Per-Process Library Split

| Library | Loaded Where | Why |
|---------|-------------|-----|
| KDOS, BIOS | System (Bank 0) | Core OS, always needed |
| graphics.f, tools.f | System dict | Stateless drawing primitives |
| kalki-gfx.f | System dict | Stateless (BLIT hooks, FAST-RECT) |
| kalki-color.f | System dict | Theme constants, no mutable state |
| kalki-widget.f | System dict | Widget tree is global (one tree) |
| kalki-basic.f | System dict | Label/button factories |
| kalki-window.f | System dict | Window manager is global |
| kalki-app.f | System dict | Process manager itself |
| kalki-desktop.f | System dict | Desktop shell |
| kalki-font.f | System dict | Font bridge (shared cache) |
| kalki-menu.f | **Per-process** | Has _MN-SEL, _MN-MENU — per-dropdown state |
| kalki-scroll.f | **Per-process** | Has per-scrollbar state |
| kalki-editor.f | **Per-process** | Has gap buffer, _EK-* state |
| App code | **Per-process** | App-specific init, key handler |

---

## Multi-Core Path (Future)

The architecture is designed to extend to multi-core without restructuring:

**Core 0 (today)**: All processes run cooperatively.  Context switch
at event delivery boundaries.  No preemption.  Desktop owns the
event loop.

**Micro-cores (future)**: A process can be dispatched to a micro-core
via `CORE-DISPATCH`.  The micro-core has its own dictionary/stacks
natively — no software context switching needed.  Communication:
- **Events to app**: `RING-PUSH` on a per-process event queue
- **Render requests**: App writes to a shared render request ring;
  desktop on core 0 processes render queue each frame
- **MPU fencing**: `CL-MPU-SETUP` restricts micro-core to its arena

The process descriptor is the same either way.  `APP-DELIVER` on
core 0 does a context switch + direct call.  On a micro-core it
does a RING-PUSH + interrupt.  The app's code is identical.

**Multiple processes per core**: On core 0, this is cooperative
multitasking (context switch at event boundaries).  On a micro-core,
single-process-per-core is the natural model (hardware isolation).

---

## Execution Stages

### Stage 1: Process Infrastructure (`kalki-app.f`)

**New file**: `kalki-app.f` (~200 lines)
**Touches**: nothing existing

Build the process manager as a standalone module with smoke test:

- Process table (8 × 96 bytes, in system dict)
- XMEM region allocator (dynamic, 128 KiB default per process)
- Per-process `_MOD-HT` creation
- Context switch: save/restore `var_latest`, `var_here`, `_MOD-HT` ptr
- `APP-LAUNCH` — full lifecycle: allocate slot, create dict zone,
  fork LATEST chain, CATCH-execute entry XT, context-switch back
- `APP-KILL` — teardown: WG-FREE-SUBTREE, WIN-UNREGISTER, cleanup XT,
  ARENA-DESTROY, XMEM-FREE-BLOCK, zero slot
- `APP-DELIVER` — context-switch to process, CATCH-execute ONKEY,
  context-switch back
- `APP-SWITCH` — visibility toggle, focus change
- `APP-CURRENT` / `APP-NEXT` / `APP-LIST`
- Helper words: `APP-SET-ROOT`, `APP-SET-ONKEY`, `APP-SET-CLEANUP`
  (called from inside entry-xt to configure the process descriptor)
- `KALKI-APP-TEST` — smoke test: launch a tiny test app, deliver
  a key, kill it, verify clean state

**Deliverable**: `KALKI-APP-TEST` passes.  Boot test still passes.
No existing behavior changes.

### Stage 2: File Manager as App

**New file**: `kalki-app-filemgr.f` (~120 lines)
**Modifies**: `kalki-desktop.f`, `kalki-autoexec.f`, `boot.sh`

- Move `_FM-SCAN`, `FM-NAMES`, `FM-COUNT`, `FM-SELECTED`,
  `_FM-ITEM-LEN`, `_FM-LIST-RENDER`, `_FM-LIST-KEY` into
  `kalki-app-filemgr.f`
- Add `FILEMGR-INIT` (creates window + file list widget,
  calls `APP-SET-ROOT` and `APP-SET-ONKEY`)
- Add `FILEMGR-KEY` (handles Up/Down/Enter; Enter launches editor app)
- Desktop calls `['] FILEMGR-INIT S" Files" APP-LAUNCH` at startup
- Remove all `_FM-*` and `DK-FILE-*` code from `kalki-desktop.f`
- Update `boot.sh` to inject new file, update `kalki-autoexec.f`

**Deliverable**: File manager works as before, but runs as a process.
`APP-LIST` shows it.  Desktop code is shorter.

### Stage 3: Editor as App

**New file**: `kalki-app-editor.f` (~80 lines)
**Modifies**: `kalki-desktop.f`

- Move `_DKE-*` variables, `_DKE-DO-SAVE`, `_DKE-DO-CLOSE`,
  `_DK-OPEN-FILE`, editor key routing into `kalki-app-editor.f`
- Add `EDITOR-APP-INIT` (creates editor window + menu bar + editor
  widget, loads file, calls `APP-SET-ROOT`/`APP-SET-ONKEY`)
- Add `EDITOR-APP-KEY` (routes keys between menu bar and editor,
  handles Tab switching)
- Editor's Close menu calls `APP-KILL-SELF` — the process manager
  handles teardown cleanly because the process descriptor knows
  the root widget, arena, dict zone, etc.
- File manager's Enter key calls `APP-LAUNCH` with editor
- Remove all `_DKE-*` code from `kalki-desktop.f`

**Deliverable**: Open file → editor launches as process.  Close →
editor killed, file manager still running.  The core bug is FIXED.

### Stage 4: Desktop Refactor

**Modifies**: `kalki-desktop.f`

- Replace the 80-line key routing block with generic `APP-DELIVER`
- Remove `_DK-HANDLE-KEY` ESC-closes-editor logic (process manager
  handles this now)
- Add Ctrl-N app cycling (calls `APP-NEXT`)
- Taskbar shows running app names (walk process table, render names)
- Desktop becomes ~150–200 lines (down from 462)
- `_DK-BUILD` just creates root, taskbar, clock — no file manager
  window (that's an app now)

**Deliverable**: Clean desktop shell.  Alt-tab between apps.
Open multiple editors simultaneously — each has its own dictionary,
its own menu state, its own gap buffer.

### Stage 5: Harden & Polish

- **Stack depth check**: verify SP before/after every `APP-DELIVER`
  — detect stack corruption, kill offending app
- **Arena overflow**: check within `APP-DELIVER` CATCH handler
- **Ctrl-Q kill confirmation**: optional dialog before killing app
- **Process zombie cleanup**: if app init fails, ensure no leaked
  widgets or memory
- **Test matrix**:
  - Launch editor, close it → file manager still works
  - Launch editor, THROW inside it → desktop survives
  - Launch two editors → separate menu/editor state
  - Kill app while dropdown is open → no crash
  - Exhaust XMEM → APP-LAUNCH returns -1

---

## Boot Chain After Refactor

```
autoexec.f loads (into system dictionary):
  graphics.f → tools.f →
  kalki-gfx.f → kalki-color.f → kalki-font.f →
  kalki-widget.f → kalki-basic.f → kalki-window.f →
  kalki-app.f (NEW — process manager) →
  kalki-desktop.f

Per-process (loaded inside APP-LAUNCH, into process dict):
  kalki-app-filemgr.f → REQUIRE kalki-scroll.f etc. as needed
  kalki-app-editor.f  → REQUIRE kalki-editor.f kalki-menu.f
```

Note: `kalki-editor.f`, `kalki-menu.f`, `kalki-scroll.f` are still
on the disk image but are NOT loaded at boot.  They're loaded
per-process when an app REQUIREs them.

---

## Key Design Decisions

1. **Dictionary context switch** — swap `var_latest` + `var_here` +
   `_MOD-HT` per process.  Each process sees its own words first,
   then falls through to shared system words.  True isolation.

2. **Per-process REQUIRE** — each process has its own PROVIDED hash
   table.  Two editors loading `kalki-menu.f` get separate copies
   of all menu variables.  Zero conflicts.

3. **Single event loop, cooperative** — desktop owns the loop, apps
   are callbacks (ONKEY handler).  Context switch happens at event
   delivery boundaries.  No coroutines, no preemption.

4. **Heap for widgets, arena for data** — widget structs use
   ALLOCATE/FREE (so WG-FREE-SUBTREE works).  App bulk data
   (gap buffer, file lists) uses arena for O(1) cleanup.

5. **Multi-core ready** — process descriptor and lifecycle are the
   same whether the app runs on core 0 or a micro-core.  Today
   it's all core 0 with software context switching.  Tomorrow
   a process can be dispatched to a micro-core with hardware
   isolation — same APP-LAUNCH, same APP-KILL.

6. **1 MiB per process (default)** — 30 KiB actual usage for full Kalki
   library stack.  On a real PC with GBs of RAM, 256 processes
   at 1 MiB each = 256 MiB — trivial.  For the emulator's 16 MiB
   XMEM, processes still fit comfortably during development.
