# Kalki — Build Roadmap

A phased plan for building the Kalki GUI framework on the Megapad-64.
Each phase produces usable, testable output.  Later phases depend on
earlier ones but are scoped so work can pause at any phase boundary.

---

## Phase 0: Foundation & Fixes  ✅ COMPLETE

**Goal:** Solid low-level graphics before building anything on top.

**Depends on:** `graphics.f` in megapad repo, framebuffer device working.

### 0.1 — Fix graphics.f Bugs

- [x] Rewrite `GFX-BLIT` → `GFX-BLIT2` — variable-based, CMOVE per row
- [x] Complete `GFX-SCROLL-UP` → `GFX-SCROLL-UP2` — clears bottom rows
- [x] Fix `GFX-HLINE` → `FAST-HLINE` — FILL-based (not pixel-by-pixel)
- [x] Fix `GFX-RECT` → `FAST-RECT` — FAST-HLINE per row

### 0.2 — Add Missing Primitives

- [x] `FAST-HLINE ( color x y len -- )` — row-address + FILL
- [x] `FAST-VLINE ( color x y len -- )` — column drawing
- [x] `FAST-RECT ( color x y w h -- )` — FAST-HLINE per row
- [x] `FAST-BOX ( color x y w h -- )` — outlined rectangle
- [x] `CLIP-SET / CLIP-RESET` — global clipping rectangle
- [x] `CL-HLINE / CL-VLINE / CL-RECT / CL-BOX` — clipped variants
- [x] `GFX-BLIT2 ( src x y w h -- )` — variable-based CMOVE per row

### 0.3 — Double Buffering

- [x] `FB-INIT-DOUBLE` — allocate front/back buffers in HBW
- [x] `FB-SWAP` — swap via `FB-BASE!`
- [x] Verified in emulator `--display` mode

### 0.4 — Testing

- [x] `KALKI-GFX-TEST` — visual smoke test (rects, boxes, clip, blit, scroll)
- [x] Headless smoke test via `./boot.sh --test`
- [x] Visual output verified via screenshot

**Deliverable:** `kalki-gfx.f` — 314 lines Forth (est. was 150).

---

## Phase 1: Color System & Palette  ✅ COMPLETE

**Goal:** Consistent, theme-able color management.

### 1.1 — GUI Palette

- [x] 25 system color constants (CLR-BLACK through CLR-WARN, indices 0–24)
- [x] `KALKI-PAL-INIT` — programs palette entries 0–24
- [x] Colors stored as VARIABLEs (CLR-TABLE), not constants — theme-switchable

### 1.2 — Theme Support

- [x] `THEME-CLASSIC` / `THEME-DARK` / `THEME-OCEAN` / `THEME-MODERN` — CREATE tables
- [x] `THEME-LOAD ( theme-addr -- )` — converts 24-bit RGB → RGB565 CLR-TABLE
- [x] `THEME-MODERN` — VS Code-inspired dark flat theme (default)
- [x] `KALKI-COLOR-TEST` — visual test drawing color swatches for 2 themes
- [x] Fixed `RGB24>565` — extracts top 5/6/5 bits (not bottom bits)

**Deliverable:** `kalki-color.f` — 241 lines Forth (est. was 60).

---

## Phase 2: Widget Core  ✅ COMPLETE

**Goal:** Generic widget descriptor, tree structure, focus model.

### 2.1 — Widget Descriptor

- [x] 96-byte widget struct with fields: type, flags, x, y, w, h,
      parent, first-child, next-sibling, render-xt, key-xt, data
- [x] `WG-ALLOC ( type -- widget )` — heap-allocate a widget
- [x] `WG-FREE ( widget -- )` — free widget and its data
- [x] Field accessors: `WG.TYPE`, `WG.FLAGS`, `WG.X`, ..., `WG.DATA`

### 2.2 — Widget Tree

- [x] `WG-ADD-CHILD ( child parent -- )` — append to sibling list
- [x] `WG-REMOVE ( widget -- )` — unlink from parent
- [x] `WG-WALK ( xt root -- )` — depth-first traversal
- [x] `WG-WALK-REV` — reverse traversal (for hit-testing)

### 2.3 — Focus & Key Dispatch

- [x] `FOCUS-WIDGET` variable
- [x] `FOCUS ( widget -- )` — set focus, mark old/new dirty
- [x] `DELIVER-KEY ( key -- consumed? )` — send key to focused widget,
      bubble up to parent if unhandled
- [x] Tab key: advance focus to next sibling
- [x] Escape key: move focus to parent
- [x] `FOCUS-NEXT`, `FOCUS-PREV`, `FOCUS-CHILD`, `FOCUS-PARENT`

### 2.4 — Dirty Tracking & Render

- [x] `WG-DIRTY ( widget -- )` — set WGF-DIRTY flag
- [x] `RENDER-TREE ( root -- )` — walk tree, render dirty widgets
      with clipping to parent bounds (clip stack, push/pop)
- [x] `MARK-ALL-DIRTY ( root -- )` — force full repaint
- [x] `RENDER-SUBTREE` — recursive render with per-widget clipping

**Deliverable:** `kalki-widget.f` — 501 lines Forth (est. was 200).

---

## Phase 3: Basic Widgets  ✅ COMPLETE

**Goal:** Label, button, panel — enough for simple dialogs.

### 3.1 — Label

- [x] `LABEL ( x y text-addr text-len parent -- widget )`
- [x] Render: draw text at position in CLR-TEXT
- [x] No key handler (labels are passive)

### 3.2 — Button

- [x] `BUTTON ( x y w h label-addr label-len action-xt parent -- widget )`
- [x] Render: flat dark face + centered label (modern style)
- [x] Key handler: Enter/Space → execute action-xt
- [x] Visual feedback: focused buttons get accent-colored outline

### 3.3 — Panel

- [x] `PANEL ( x y w h label-addr label-len parent -- widget )`
- [x] Render: border + title at top + render all children
- [x] Child clipping: children clipped by RENDER-SUBTREE

### 3.4 — Separator / Horizontal Rule

- [x] `HSEP ( x y w parent -- widget )`
- [x] Render: single-pixel line in CLR-BTN-SHADOW

### 3.5 — Testing

- [x] Smoke test: 6 widgets (root, panel, 2 labels, button, hsep, panel2)
- [x] Button action fires on Enter (click count 1→2)
- [x] Full tree render with clipping
- [x] Headless via `./boot.sh --test`

**Deliverable:** `kalki-basic.f` — 271 lines Forth (est. was 250).

---

## Phase 4: Window  ✅ COMPLETE

**Goal:** Windowed containers with title bars.

### 4.1 — Window Widget

- [x] `WINDOW ( x y w h title-addr title-len parent -- widget )`
- [x] Render: borderless flat window with accent-blue title bar (28px)
- [x] Title text in CLR-TITLE-FG (vertically centered, left-padded 12px)
- [x] Close button glyph (x) in title bar (decorative, shown when close-xt set)
- [x] Active window: title bar in CLR-TITLE-BG; inactive: CLR-TITLE-INACTIVE
- [x] `WIN-SET-CLOSE ( xt window -- )` — set close action
- [x] `WIN-CLIENT-Y` (28), `WIN-CLIENT-X` (0) — child positioning constants

### 4.2 — Window Manager

- [x] `WIN-TABLE` — flat array, up to 16 windows
- [x] `WIN-REGISTER / WIN-UNREGISTER` — auto-register in WINDOW factory
- [x] `WIN-ACTIVE` / `WIN-GET-ACTIVE` — currently active window tracking
- [x] `WIN-CYCLE` — cycle to next window (Ctrl-N = K-WINCYCLE)
- [x] `WIN-ACTIVATE ( index -- )` — switch active, mark dirty, focus first child
- [x] `WIN-DELIVER-KEY ( key -- consumed? )` — wraps DELIVER-KEY + Ctrl-N
- [x] Tiled layout only (no overlap for v1)

### 4.3 — Dialog Boxes

- [x] `DIALOG ( w h title-addr title-len -- widget )` — centered window
- [x] Modal: `MSG-BOX` / `CONFIRM` capture input with blocking KEY loop
- [x] `MSG-BOX ( text-addr text-len title-addr title-len -- )` — OK dialog
- [x] `CONFIRM ( text-addr text-len -- flag )` — Yes/No dialog with Tab toggle
- [x] Scene save/restore via `_DLG-SAVE-SCENE` / `_DLG-CLOSE` (ALLOCATE buffer)

### 4.4 — Testing

- [x] Test window rendering: title bar, client area, border
- [x] Test focus switching between windows (WIN-CYCLE)
- [x] Test DIALOG structure: type, size, centered position
- [x] Headless via `./boot.sh --test`

**Deliverable:** `kalki-window.f` — 440 lines Forth (est. was 300).

---

## Phase 5: Menu System

**Goal:** Menu bars and dropdown menus.

### 5.1 — Menu Items

- [ ] Menu item struct: label + action-xt + enabled flag
- [ ] `MENU ( nitems parent -- widget )`
- [ ] `MENU-ADD ( label-addr label-len xt menu -- )`
- [ ] Render: vertical list with selection highlight
- [ ] Key handler: Up/Down to navigate, Enter to select, Esc to close

### 5.2 — Menu Bar

- [ ] `MENU-BAR ( window -- widget )` — horizontal bar at top of window
- [ ] Contains named menu triggers ("File", "Edit", "View")
- [ ] Left/Right arrow switches between menus
- [ ] Enter/Down opens dropdown
- [ ] Keyboard accelerators (Alt+letter, future)

### 5.3 — Context Menu

- [ ] `CONTEXT-MENU ( x y nitems -- widget )` — popup at cursor position
- [ ] Auto-dismiss on selection or Escape

**Deliverable:** `kalki-menu.f` module (~250 lines).

---

## Phase 6: Scrollable Containers  ✅ COMPLETE

**Goal:** Scrollbars and scrollable content areas.

### 6.1 — Scrollbar Widget

- [x] `SCROLLBAR ( x y w h parent -- widget )` — vertical scrollbar
- [x] Render: track (CLR-SCROLL-BG) + thumb (CLR-SCROLL-FG)
- [x] Thumb size proportional to visible/total ratio
- [x] `SB-UPDATE ( total visible pos scrollbar -- )` — update state

### 6.2 — List Widget

- [x] `LISTBOX ( x y w h parent -- widget )` — scrollable list
- [x] Auto-creates scrollbar child at right edge
- [x] Selection highlight (CLR-HIGHLIGHT)
- [x] Key handler: Up/Down/PgUp/PgDn/Home/End/Enter
- [x] `_LB-ENSURE-VISIBLE` — auto-scroll to keep selection visible
- [x] `_LB-SYNC-SB` — sync scrollbar to listbox state
- [x] `LB-SET-ITEMS ( count widget -- )` — set item count
- [x] `LB-SET-RENDER ( xt widget -- )` — set item render callback
- [x] `LB-SET-ACTION ( xt widget -- )` — set Enter action
- [x] `LB-SELECTED ( widget -- idx )` — get selected index
- [x] `LB-SCROLL ( widget -- scroll )` — get scroll offset
- [x] Default item renderer draws index number

**Deliverable:** `kalki-scroll.f` — ~440 lines Forth.

---

## Phase 7: Text Editor  ✅ COMPLETE

**Goal:** A graphical text editor widget — the showcase feature.

### 7.1 — Gap Buffer

- [x] Gap buffer data structure: buf, gap_start, gap_end, dirty, cached line count
- [x] `GAP-INSERT ( char gb -- )` — insert at cursor
- [x] `GAP-DELETE ( gb -- )` — backspace
- [x] `GAP-DELETE-FWD ( gb -- )` — delete forward
- [x] `GAP-MOVE ( pos gb -- )` — move gap to position
- [x] `GAP-CHAR@ ( pos gb -- char )` — read logical position
- [x] `_GAP-GROW` — auto-double buffer when full
- [x] Cached line count: O(1) `_GB-COUNT-LINES`

### 7.2 — Editor Widget

- [x] `EDITOR ( x y w h parent -- widget )`
- [x] Render: dark background + light text + cursor + dim line numbers
- [x] Cursor: 2px-wide bright blue bar, full LINE-H height
- [x] `_BUILD-LINE-STARTS` — O(N) single-pass line-start table + cursor tracking
- [x] `_LST-GET` — O(1) table lookup per visible line
- [x] LINE-H=11 line spacing (3px interline leading)
- [x] Accent-colored status bar (SBAR-H=16) with filename, L#:C#, [modified]
- [x] Seamless gutter (same bg as editor)

### 7.3 — Editor Key Handling

- [x] Printable chars → insert
- [x] Backspace / Delete → delete
- [x] Arrow keys → move cursor
- [x] Home / End → start/end of line
- [x] Page Up / Down → scroll
- [x] Ctrl-S → save to MP64FS file
- [x] EKEY: VT100 escape sequence decoder for arrow/nav keys

### 7.4 — File Integration

- [x] `EDIT ( "filename" -- )` — open file in editor window
- [x] Load file content into gap buffer
- [x] Save gap buffer content back to file
- [x] New file creation

### 7.5 — Performance Optimization

- [x] `FB-COPY-BACK` — partial redraws (only editor widget dirty per keystroke)
- [x] Line-start table eliminates O(N²) scanning
- [x] Cursor line/col piggybacked into same O(N) pass
- [x] Window client-area fill removed (children paint own bg)

### 7.6 — Testing

- [x] Test gap buffer: insert, delete, move, boundary conditions
- [x] Test cursor movement: arrow keys, home/end
- [x] Test rendering: correct text at correct positions
- [x] Test file round-trip: load → edit → save → reload matches
- [x] Headless via `./boot.sh --test`

**Deliverable:** `kalki-editor.f` — 953 lines Forth (est. was 400).

---

## Phase 8: Desktop & Integration

**Goal:** Complete desktop experience with taskbar.

### 8.1 — Desktop

- [ ] Root widget: fills screen, renders CLR-DESKTOP background
- [ ] Children: taskbar + window area
- [ ] `KALKI` command: initializes framebuffer, palette, desktop,
      enters event loop

### 8.2 — Taskbar

- [ ] Fixed 24px bar at bottom of screen
- [ ] Window list: one button per open window
- [ ] Click (Enter on focused button) switches to that window
- [ ] Clock widget at right edge (reads RTC)

### 8.3 — WVEC Bridge

- [ ] `INSTALL-GUI` — replace all 15 WVEC slots with Kalki renderers
- [ ] Existing KDOS screens (Dashboard, Buffers, etc.) render in a
      Kalki window automatically
- [ ] `INSTALL-TUI` to revert to ANSI mode

### 8.4 — App Launcher

- [ ] Menu or dialog listing available "apps" (really words/modules)
- [ ] Built-in: Editor, Dashboard, File Manager, Forth REPL
- [ ] Extensible: new apps registered via a simple API

### 8.5 — File Manager

- [ ] Window showing MP64FS directory listing
- [ ] File type icons (text indicators — no bitmap icons yet)
- [ ] Enter to open file (in editor or appropriate viewer)
- [ ] Delete key to remove file (with confirmation dialog)

**Deliverable:** `kalki-desktop.f` module (~350 lines).

---

## Phase 9: Font System

**Goal:** Multiple font sizes for comfortable readability.

### 9.1 — 2× Scaled Font

- [ ] `GFX-CHAR-2X ( char x y color -- )` — render 8×8 font at 16×16
- [ ] `GFX-TYPE-2X ( addr len color -- )` — string rendering at 2×
- [ ] Use for window titles and headings

### 9.2 — Proportional Width Table

- [ ] `GFX-FONT-WIDTH` — 96-byte table of glyph widths (3–8 px each)
- [ ] `GFX-TYPE-PROP ( addr len color -- )` — proportional text
- [ ] `TEXT-WIDTH ( addr len -- pixels )` — measure string width

### 9.3 — External Fonts (Future)

- [ ] Font file format: header (char range, height, glyph count) +
      width table + glyph data
- [ ] `LOAD-FONT ( "filename" -- font-id )`
- [ ] `SET-FONT ( font-id -- )`
- [ ] Store fonts in XMEM

**Deliverable:** `kalki-font.f` module (~150 lines for 9.1–9.2).

---

## Phase 10: Polish & Advanced Features

**Goal:** Quality-of-life improvements.

### 10.1 — Animations

- [ ] Button press animation (brief sunken state)
- [ ] Menu open/close slide (1–2 frame transition)
- [ ] Window focus transition (title bar color blend)

### 10.2 — Clipboard

- [ ] Global clipboard buffer (text only)
- [ ] Ctrl-C / Ctrl-V in editor and text fields
- [ ] Implemented as a simple text buffer in ext mem

### 10.3 — Undo/Redo (Editor)

- [ ] Undo ring buffer (N operations)
- [ ] Each operation: type (insert/delete) + position + data
- [ ] Ctrl-Z / Ctrl-Y

### 10.4 — Status Bar

- [ ] Per-window status bar at bottom
- [ ] Shows context info (cursor position in editor, file size, etc.)

### 10.5 — Tab Widget

- [ ] Tabbed container — multiple panels sharing the same space
- [ ] Tab bar at top with tab labels
- [ ] Switch tabs with number keys or left/right arrows

---

## Size Estimates

| Module | File | Est. Lines |
|---|---|---|
| Phase 0: GFX fixes | `kalki-gfx.f` | ~~150~~ 396 ✅ |
| Phase 1: Colors | `kalki-color.f` | ~~60~~ 241 ✅ |
| Phase 2: Widget core | `kalki-widget.f` | ~~200~~ 545 ✅ |
| Phase 3: Basic widgets | `kalki-basic.f` | ~~250~~ 261 ✅ |
| Phase 4: Windows | `kalki-window.f` | ~~300~~ 442 ✅ |
| Phase 5: Menus | `kalki-menu.f` | 250 |
| Phase 6: Scrolling | `kalki-scroll.f` | 440 |
| Phase 7: Text editor | `kalki-editor.f` | ~~400~~ 953 ✅ |
| Phase 8: Desktop | `kalki-desktop.f` | 350 |
| Phase 9: Fonts | `kalki-font.f` | 150 |
| Main entry point | `kalki.f` | 50 |
| **Total** | | **~2,360** |

Plus test file(s): ~500–800 lines Python.

---

## Module Load Order

```forth
\ kalki.f — Main entry point
PROVIDED kalki.f

REQUIRE graphics.f       \ Low-level framebuffer primitives + font
REQUIRE kalki-gfx.f      \ Fixed/fast primitives, clipping, double buffer
REQUIRE kalki-color.f    \ Palette + themes
REQUIRE kalki-widget.f   \ Widget core: descriptors, tree, focus, render
REQUIRE kalki-basic.f    \ Label, button, panel, separator
REQUIRE kalki-window.f   \ Window, window manager, dialogs
REQUIRE kalki-menu.f     \ Menu, menu bar, context menu
REQUIRE kalki-scroll.f   \ Scrollbar, scroll view, list
REQUIRE kalki-editor.f   \ Gap buffer, text editor widget
REQUIRE kalki-font.f     \ Scaled fonts, proportional metrics
REQUIRE kalki-desktop.f  \ Desktop, taskbar, WVEC bridge, launcher

: KALKI  ( -- )
    640 480 0 GFX-INIT-HBW    \ Initialize framebuffer in HBW
    KALKI-PAL-INIT             \ Load GUI palette
    FB-INIT-DOUBLE             \ Set up double buffering
    INSTALL-GUI                \ Replace WVEC with GUI renderers
    DESKTOP-INIT               \ Create desktop + taskbar
    KALKI-LOOP ;               \ Enter event loop
```

---

## Dependency Graph

```
graphics.f ──→ kalki-gfx.f ──→ kalki-color.f ──→ kalki-widget.f
                                                       │
                           ┌───────────────────────────┤
                           ▼                           ▼
                     kalki-basic.f               kalki-window.f
                           │                           │
                           ▼                           ▼
                     kalki-menu.f              kalki-scroll.f
                                                       │
                                                       ▼
                                               kalki-editor.f
                                                       │
                     kalki-font.f ─────────────────────┤
                                                       ▼
                                              kalki-desktop.f
                                                       │
                                                       ▼
                                                   kalki.f
```

---

## Milestones

| Milestone | Phases | What You Can Do |
|---|---|---|
| **M1: Primitives** ✅ | 0–1 | Fast rects, fills, clipping, palette — test card visible |
| **M2: Widgets** ✅ | 2–3 | Labels, buttons, panels — simple interactive forms |
| **M3: Windows** | 4–5 | Windowed apps with menus — functional desktop shell (4 ✅) |
| **M4: Editor** ✅ | 6–7 | Scrollable text editor — the killer app (7 done, 6 skipped) |
| **M5: Desktop** | 8–9 | Full desktop experience with taskbar, launcher, fonts |
| **M6: Polish** | 10 | Animations, clipboard, undo, tabs |

**M1 should be achievable quickly** — it's mostly fixing existing code
and adding FILL-based fast paths.  M2–M3 are the core framework.
M4 is the payoff.  M5–M6 are polish.
