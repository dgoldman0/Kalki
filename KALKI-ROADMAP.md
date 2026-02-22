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
- [x] `GFX-PAL-DEFAULT` — programs entries 0–15 with default palette
- [x] Entries 25–31 reserved, 32–255 free for apps

### 1.2 — Theme Support

- [x] `THEME-CLASSIC` / `THEME-DARK` / `THEME-OCEAN` — CREATE tables
- [x] `THEME-LOAD ( theme-addr -- )` — loops #GUI-COLORS, calls FB-PAL!
- [x] `KALKI-COLOR-TEST` — visual test drawing color swatches for 2 themes

**Deliverable:** `kalki-color.f` — 213 lines Forth (est. was 60).

---

## Phase 2: Widget Core

**Goal:** Generic widget descriptor, tree structure, focus model.

### 2.1 — Widget Descriptor

- [ ] 96-byte widget struct with fields: type, flags, x, y, w, h,
      parent, first-child, next-sibling, render-xt, key-xt, data
- [ ] `WG-ALLOC ( type -- widget )` — heap-allocate a widget
- [ ] `WG-FREE ( widget -- )` — free widget and its data
- [ ] `WG@` / `WG!` — field accessors

### 2.2 — Widget Tree

- [ ] `WG-ADD-CHILD ( child parent -- )` — append to sibling list
- [ ] `WG-REMOVE ( widget -- )` — unlink from parent
- [ ] `WG-WALK ( xt root -- )` — depth-first traversal

### 2.3 — Focus & Key Dispatch

- [ ] `FOCUS-WIDGET` variable
- [ ] `FOCUS ( widget -- )` — set focus, mark old/new dirty
- [ ] `DELIVER-KEY ( key -- )` — send key to focused widget, bubble
      up to parent if unhandled
- [ ] Tab key: advance focus to next sibling
- [ ] Escape key: move focus to parent

### 2.4 — Dirty Tracking & Render

- [ ] `MARK-DIRTY ( widget -- )` — set WGF-DIRTY flag
- [ ] `RENDER-TREE ( root -- )` — walk tree, render dirty widgets
      with clipping to parent bounds
- [ ] `MARK-ALL-DIRTY ( root -- )` — force full repaint

**Deliverable:** `kalki-widget.f` module (~200 lines).

---

## Phase 3: Basic Widgets

**Goal:** Label, button, panel — enough for simple dialogs.

### 3.1 — Label

- [ ] `LABEL ( x y text-addr text-len parent -- widget )`
- [ ] Render: draw text at position in CLR-TEXT
- [ ] No key handler (labels are passive)

### 3.2 — Button

- [ ] `BUTTON ( x y w h label-addr label-len action-xt parent -- widget )`
- [ ] Render: 3D raised border + centered label
- [ ] Key handler: Enter/Space → execute action-xt, briefly draw sunken
- [ ] Visual feedback: focused buttons get a dotted inner border

### 3.3 — Panel

- [ ] `PANEL ( x y w h label-addr label-len parent -- widget )`
- [ ] Render: border + label at top + render all children
- [ ] Child clipping: children don't draw outside panel bounds

### 3.4 — Separator / Horizontal Rule

- [ ] `HSEP ( x y w parent -- widget )`
- [ ] Render: single-pixel line in CLR-BTN-SHADOW

### 3.5 — Testing

- [ ] Test label rendering: correct text at correct position
- [ ] Test button: action-xt fires on Enter key
- [ ] Test panel: children clipped to panel bounds
- [ ] Test focus: Tab cycles through buttons, Enter activates

**Deliverable:** `kalki-basic.f` module (~250 lines).

---

## Phase 4: Window

**Goal:** Windowed containers with title bars.

### 4.1 — Window Widget

- [ ] `WINDOW ( x y w h title-addr title-len -- widget )`
- [ ] Render: title bar (16px, CLR-TITLE-BG) + client area (CLR-WIN-BG)
      + border (CLR-WIN-BORDER)
- [ ] Title text in CLR-TITLE-FG
- [ ] Close button glyph (×) in title bar (optional, via flag)
- [ ] Focused window: title bar in CLR-TITLE-BG; unfocused: CLR-TITLE-INACTIVE

### 4.2 — Window Manager

- [ ] `WIN-TABLE` — flat array, up to 16 windows
- [ ] `WIN-REGISTER / WIN-UNREGISTER`
- [ ] `WIN-FOCUS` — currently focused window
- [ ] Tab between windows (Alt-Tab or F-key)
- [ ] Tiled layout only (no overlap for v1)

### 4.3 — Dialog Boxes

- [ ] `DIALOG ( w h title-addr title-len -- widget )` — centered window
- [ ] Modal: captures all input until dismissed
- [ ] `MSG-BOX ( text-addr text-len title-addr title-len -- )` — simple
      OK dialog
- [ ] `CONFIRM ( text-addr text-len -- flag )` — Yes/No dialog

### 4.4 — Testing

- [ ] Test window rendering: title bar, client area, border
- [ ] Test focus switching between windows
- [ ] Test dialog: modal capture and dismissal

**Deliverable:** `kalki-window.f` module (~300 lines).

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

## Phase 6: Scrollable Containers

**Goal:** Scrollbars and scrollable content areas.

### 6.1 — Scrollbar Widget

- [ ] `SCROLLBAR ( orientation parent -- widget )` — vertical or horizontal
- [ ] Render: track (CLR-SCROLL-BG) + thumb (CLR-SCROLL-FG)
- [ ] Thumb size proportional to visible/total ratio
- [ ] Key handler: arrow keys move thumb, page keys jump

### 6.2 — Scroll View

- [ ] `SCROLL-VIEW ( x y w h parent -- widget )` — container with
      scrollbar that clips child content
- [ ] Manages scroll offset, renders visible portion only
- [ ] Scrollbar auto-hides when content fits

### 6.3 — List Widget

- [ ] `LISTBOX ( x y w h nitems item-render-xt parent -- widget )`
- [ ] Scrollable list of items
- [ ] Selection highlight
- [ ] Enter triggers action on selected item

**Deliverable:** `kalki-scroll.f` module (~200 lines).

---

## Phase 7: Text Editor

**Goal:** A graphical text editor widget — the showcase feature.

### 7.1 — Gap Buffer

- [ ] Gap buffer data structure: buf, gap_start, gap_end
- [ ] `GAP-INSERT ( char ed -- )` — insert at cursor
- [ ] `GAP-DELETE ( ed -- )` — backspace
- [ ] `GAP-MOVE ( pos ed -- )` — move gap to position
- [ ] `GAP-CHAR@ ( pos ed -- char )` — read logical position

### 7.2 — Editor Widget

- [ ] `EDITOR ( x y w h parent -- widget )`
- [ ] Render: white background + text + cursor + line numbers
- [ ] Cursor blink via timer toggle
- [ ] Visible line range calculation from scroll offset
- [ ] Horizontal scroll (or line wrapping — pick one)

### 7.3 — Editor Key Handling

- [ ] Printable chars → insert
- [ ] Backspace / Delete → delete
- [ ] Arrow keys → move cursor
- [ ] Home / End → start/end of line
- [ ] Page Up / Down → scroll
- [ ] Ctrl-S → save to MP64FS file
- [ ] Ctrl-Z → undo (if undo buffer implemented)

### 7.4 — File Integration

- [ ] `EDIT ( "filename" -- )` — open file in editor widget
- [ ] Load file content into gap buffer
- [ ] Save gap buffer content back to file
- [ ] New file creation

### 7.5 — Testing

- [ ] Test gap buffer: insert, delete, move, boundary conditions
- [ ] Test cursor movement: arrow keys, home/end
- [ ] Test rendering: correct text at correct positions
- [ ] Test file round-trip: load → edit → save → reload matches

**Deliverable:** `kalki-editor.f` module (~400 lines).

---

## Phase 8: Desktop & Integration

**Goal:** Complete desktop experience with taskbar.

### 8.1 — Desktop

- [ ] Root widget: fills screen, renders CLR-DESKTOP background
- [ ] Children: taskbar + window area
- [ ] `KALKI` command: initializes framebuffer, palette, desktop,
      enters event loop

### 8.2 — Taskbar

- [ ] Fixed 20px bar at bottom of screen
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
| Phase 0: GFX fixes | `kalki-gfx.f` | ~~150~~ 314 ✅ |
| Phase 1: Colors | `kalki-color.f` | ~~60~~ 213 ✅ |
| Phase 2: Widget core | `kalki-widget.f` | 200 |
| Phase 3: Basic widgets | `kalki-basic.f` | 250 |
| Phase 4: Windows | `kalki-window.f` | 300 |
| Phase 5: Menus | `kalki-menu.f` | 250 |
| Phase 6: Scrolling | `kalki-scroll.f` | 200 |
| Phase 7: Text editor | `kalki-editor.f` | 400 |
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
| **M2: Widgets** | 2–3 | Labels, buttons, panels — simple interactive forms |
| **M3: Windows** | 4–5 | Windowed apps with menus — functional desktop shell |
| **M4: Editor** | 6–7 | Scrollable text editor — the killer app |
| **M5: Desktop** | 8–9 | Full desktop experience with taskbar, launcher, fonts |
| **M6: Polish** | 10 | Animations, clipboard, undo, tabs |

**M1 should be achievable quickly** — it's mostly fixing existing code
and adding FILL-based fast paths.  M2–M3 are the core framework.
M4 is the payoff.  M5–M6 are polish.
