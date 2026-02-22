# Kalki — GUI Framework Ideas & Code Scrap

**Kalki** is a framebuffer-first GUI framework for the Megapad-64,
written entirely in Forth.  It builds **window**, **panel**, **menu**,
and **text editor** as words — the same way Forth builds everything else.

---

## 1. Design Philosophy

### Framebuffer-First

The KDOS TUI emits ANSI escape sequences to UART — it's a text-mode
overlay.  Kalki is different: it **owns the framebuffer** and draws
pixels.  The UART becomes a debug/fallback console, not the primary UI.

Expose as primitives:
- **pixel** — `GFX-PIXEL!` / `GFX-PIXEL@` (already in graphics.f)
- **line** — `GFX-HLINE` / `GFX-VLINE` (already in graphics.f)
- **rect** — `GFX-RECT` / `GFX-BOX` (already in graphics.f)
- **blit** — `GFX-BLIT` (needs rewrite — current version is broken)
- **glyph** — `GFX-CHAR` (already in graphics.f, 8×8 bitmap font)

Then build as compound words:
- **window** — title bar + border + client area + close/resize glyphs
- **panel** — lightweight rect with label + child layout
- **menu** — list of selectable items with highlight
- **text editor** — scrollable text buffer with cursor + line numbers

This mirrors how Forth builds everything: primitives → compounds → systems.

### Relationship to graphics.f

Two options:

| Option | Pros | Cons |
|---|---|---|
| **A. REQUIRE graphics.f, build on top** | Reuse existing primitives, font, palette | Inherit bugs (blit, scroll), some words are inefficient (pixel-by-pixel hline) |
| **B. Build fresh, cherry-pick** | Clean slate, optimize for GUI from the start | Duplicate some basic code |

**Recommendation: Option A with fixes.** `REQUIRE graphics.f` for the
font data, palette helpers, and init.  Rewrite `GFX-BLIT`, `GFX-HLINE`,
and `GFX-SCROLL-UP`.  Add new primitives (fast fill, clipping, etc.)
in Kalki's own vocabulary.

### Relationship to KDOS WVEC

KDOS already has a widget vector table (`WVEC`) that dispatches
`W.TITLE`, `W.SECTION`, `W.LIST`, etc. through swappable xts.  The
TUI renderer emits ANSI; a GUI renderer would draw to the framebuffer.

**Strategy:** Write a `INSTALL-GUI` word that replaces the WVEC xts with
Kalki's framebuffer renderers.  This way, existing KDOS screens
(Dashboard, Buffers, Kernels, etc.) automatically render on the
framebuffer without rewriting their screen definitions.

Then build Kalki's own higher-level widgets (windows, menus, etc.)
independently — WVEC is too simple for a real windowing system.

---

## 2. Color & Palette

### Default GUI Palette (mode 0, 8bpp indexed)

Reserve palette entries 0–31 for the GUI chrome.  Leave 32–255 for
app-specific use.

```forth
\ Proposed GUI palette (0-31)
\ Inspired by classic desktop UIs — flat, clean, functional

\ ── System colors ──
 0 CONSTANT CLR-BLACK        \ 0x000000
 1 CONSTANT CLR-DESKTOP      \ 0x3A6EA5  (steel blue desktop background)
 2 CONSTANT CLR-WIN-BG       \ 0xD4D0C8  (warm gray window fill)
 3 CONSTANT CLR-WIN-BORDER   \ 0x808080  (gray window border)
 4 CONSTANT CLR-TITLE-BG     \ 0x0A246A  (dark blue title bar)
 5 CONSTANT CLR-TITLE-FG     \ 0xFFFFFF  (white title text)
 6 CONSTANT CLR-TITLE-INACTIVE  \ 0x808080
 7 CONSTANT CLR-TEXT         \ 0x000000  (black text)
 8 CONSTANT CLR-TEXT-DIM     \ 0x808080  (gray secondary text)
 9 CONSTANT CLR-HIGHLIGHT    \ 0x0A246A  (selection highlight bg)
10 CONSTANT CLR-HILITE-FG   \ 0xFFFFFF  (selection highlight text)
11 CONSTANT CLR-BTN-FACE    \ 0xD4D0C8  (button face)
12 CONSTANT CLR-BTN-LIGHT   \ 0xFFFFFF  (button top/left 3D edge)
13 CONSTANT CLR-BTN-SHADOW  \ 0x808080  (button bottom/right 3D edge)
14 CONSTANT CLR-BTN-DARK    \ 0x404040  (button outer shadow)
15 CONSTANT CLR-MENU-BG     \ 0xF0F0F0  (menu background)
16 CONSTANT CLR-MENU-SEL    \ 0x0A246A  (menu selection bar)
17 CONSTANT CLR-SCROLL-BG   \ 0xC0C0C0  (scrollbar track)
18 CONSTANT CLR-SCROLL-FG   \ 0x808080  (scrollbar thumb)
19 CONSTANT CLR-EDIT-BG     \ 0xFFFFFF  (text input background)
20 CONSTANT CLR-EDIT-FG     \ 0x000000  (text input foreground)
21 CONSTANT CLR-CURSOR       \ 0x000000  (text cursor)
22 CONSTANT CLR-ERROR        \ 0xFF0000  (red for errors)
23 CONSTANT CLR-SUCCESS      \ 0x008000  (green for success)
24 CONSTANT CLR-WARN         \ 0xFFA500  (orange for warnings)
\ 25-31 reserved

: KALKI-PAL-INIT  ( -- )
    0x000000  0 FB-PAL!
    0x3A6EA5  1 FB-PAL!
    0xD4D0C8  2 FB-PAL!
    0x808080  3 FB-PAL!
    0x0A246A  4 FB-PAL!
    0xFFFFFF  5 FB-PAL!
    0x808080  6 FB-PAL!
    0x000000  7 FB-PAL!
    0x808080  8 FB-PAL!
    0x0A246A  9 FB-PAL!
    0xFFFFFF 10 FB-PAL!
    0xD4D0C8 11 FB-PAL!
    0xFFFFFF 12 FB-PAL!
    0x808080 13 FB-PAL!
    0x404040 14 FB-PAL!
    0xF0F0F0 15 FB-PAL!
    0x0A246A 16 FB-PAL!
    0xC0C0C0 17 FB-PAL!
    0x808080 18 FB-PAL!
    0xFFFFFF 19 FB-PAL!
    0x000000 20 FB-PAL!
    0x000000 21 FB-PAL!
    0xFF0000 22 FB-PAL!
    0x008000 23 FB-PAL!
    0xFFA500 24 FB-PAL! ;
```

---

## 3. Improved Drawing Primitives

### Fast Horizontal Line (tile-accelerated)

The existing `GFX-HLINE` draws pixel-by-pixel.  For a GUI that fills
lots of rectangles, this is too slow.  Use `FILL` for aligned runs:

```forth
\ Fast hline: compute row address, FILL the bytes directly.
\ For 8bpp, each pixel = 1 byte, so FILL is ideal.
: FAST-HLINE  ( color x y len -- )
    >R                          ( color x y  R: len )
    GFX-ADDR                    ( color addr )
    R> ROT                      ( addr len color )
    FILL ;

\ Fast filled rect: call FAST-HLINE for each row.
: FAST-RECT  ( color x y w h -- )
    0 DO                        ( color x y w )
        3 PICK 3 PICK 2 PICK I + 2 PICK
        FAST-HLINE
    LOOP
    2DROP 2DROP ;
```

### Tile-Accelerated Clear and Fill

For large regions (>= 64 bytes), use `TFILL` to zero/fill tiles:

```forth
\ Fill a rectangular region at tile speed.
\ Precondition: region is tile-aligned in width (multiple of 64 bytes).
: TILE-FILL-REGION  ( color addr nbytes -- )
    64 / 0 DO                   ( color addr )
        2DUP TFILL               \ TFILL ( addr byte -- )
        64 +
    LOOP 2DROP ;
```

### Clipping

Every drawing operation needs clipping against the visible area.
Global clip rect:

```forth
VARIABLE CLIP-X0  VARIABLE CLIP-Y0
VARIABLE CLIP-X1  VARIABLE CLIP-Y1

: CLIP-SET  ( x0 y0 x1 y1 -- )
    CLIP-Y1 ! CLIP-X1 ! CLIP-Y0 ! CLIP-X0 ! ;

: CLIP-RESET  ( -- )
    0 CLIP-X0 !  0 CLIP-Y0 !
    GFX-W @ CLIP-X1 !  GFX-H @ CLIP-Y1 ! ;

\ Clip a horizontal span to the clip rect.
\ Returns clipped x, len.  If fully outside, len = 0.
: CLIP-HSPAN  ( x y len -- x' len' | 0 0 )
    >R SWAP                     ( y x  R: len )
    \ Check y in range
    OVER CLIP-Y0 @ < IF 2DROP R> DROP 0 0 EXIT THEN
    OVER CLIP-Y1 @ >= IF 2DROP R> DROP 0 0 EXIT THEN
    \ Clip x to [CLIP-X0, CLIP-X1)
    DUP CLIP-X0 @ MAX           ( y x x' )
    SWAP R> +                   ( y x' x+len )
    CLIP-X1 @ MIN               ( y x' right )
    OVER -                      ( y x' len' )
    DUP 0<= IF 2DROP DROP 0 0 EXIT THEN
    ROT DROP ;                  ( x' len' )
```

### Rewritten GFX-BLIT

The current `GFX-BLIT` in graphics.f is broken (stack management is
"unwieldy" per the source comment).  Rewrite using variables:

```forth
VARIABLE BLIT-SRC  VARIABLE BLIT-W  VARIABLE BLIT-H
VARIABLE BLIT-X    VARIABLE BLIT-Y

: GFX-BLIT2  ( src x y w h -- )
    BLIT-H ! BLIT-W ! BLIT-Y ! BLIT-X ! BLIT-SRC !
    BLIT-H @ 0 DO
        BLIT-SRC @ I BLIT-W @ GFX-BPP @ * * +   \ src row
        BLIT-X @ BLIT-Y @ I + GFX-ADDR            \ dst addr
        BLIT-W @ GFX-BPP @ *                      \ nbytes
        CMOVE
    LOOP ;
```

---

## 4. Widget Data Structures

### Universal Widget Descriptor

Every widget shares a common header.  Use a flat struct in dictionary
memory:

```forth
\ Widget descriptor layout (cells):
\   +0   type       ( 0=window 1=panel 2=button 3=label 4=menu
\                      5=textfield 6=editor 7=list 8=scrollbar )
\   +8   flags      ( bit 0: visible, bit 1: focused, bit 2: dirty,
\                      bit 3: disabled )
\   +16  x          ( position relative to parent )
\   +24  y
\   +32  w          ( width in pixels )
\   +40  h          ( height in pixels )
\   +48  parent     ( descriptor address of parent, 0 = root )
\   +56  first-child ( linked list of children, 0 = none )
\   +64  next-sibling ( linked list, 0 = last )
\   +72  render-xt  ( xt for drawing this widget )
\   +80  key-xt     ( xt for handling keyboard input, 0 = none )
\   +88  data       ( widget-specific data pointer )

\ Field offsets
 0 CONSTANT WG-TYPE
 8 CONSTANT WG-FLAGS
16 CONSTANT WG-X
24 CONSTANT WG-Y
32 CONSTANT WG-W
40 CONSTANT WG-H
48 CONSTANT WG-PARENT
56 CONSTANT WG-CHILD
64 CONSTANT WG-SIBLING
72 CONSTANT WG-RENDER
80 CONSTANT WG-KEY
88 CONSTANT WG-DATA

96 CONSTANT WG-SIZE   \ bytes per widget descriptor

\ Flag bits
1 CONSTANT WGF-VISIBLE
2 CONSTANT WGF-FOCUSED
4 CONSTANT WGF-DIRTY
8 CONSTANT WGF-DISABLED

\ Accessors
: WG@    ( widget field -- value )  + @ ;
: WG!    ( value widget field -- )  + ! ;
```

### Widget Allocation

```forth
\ Allocate a widget from the heap
: WG-ALLOC  ( type -- widget )
    WG-SIZE ALLOCATE DROP       ( type widget )
    DUP WG-SIZE 0 FILL          \ zero-initialize
    TUCK WG-TYPE WG!             \ set type
    WGF-VISIBLE OVER WG-FLAGS WG! ; \ visible by default

\ Add child to parent's child list
: WG-ADD-CHILD  ( child parent -- )
    2DUP WG-PARENT WG!          \ child.parent = parent
    DUP WG-CHILD WG@            ( child parent first )
    DUP 0= IF                   \ no children yet
        DROP WG-CHILD WG!       \ parent.child = child
    ELSE                        \ walk to end of sibling list
        BEGIN DUP WG-SIBLING WG@ DUP WHILE
            NIP
        REPEAT
        DROP WG-SIBLING WG!     \ last.sibling = child
    THEN ;
```

---

## 5. Window

A window is the primary container.  It has:
- Title bar (height = 16px: 8px padding top + 8px font)
- 1px border
- Client area (fill or child layout)
- Optional close button (8×8 glyph in title bar)

```forth
\ Window-specific data
\   +0   title-addr   ( pointer to title string )
\   +8   title-len    ( title string length )
\  +16   win-flags    ( bit 0: closeable, bit 1: moveable )

 0 CONSTANT WD-TITLE-ADDR
 8 CONSTANT WD-TITLE-LEN
16 CONSTANT WD-WIN-FLAGS
24 CONSTANT WD-WIN-SIZE

: WIN-DATA  ( widget -- data )  WG-DATA WG@ ;

: WINDOW  ( x y w h title-addr title-len -- widget )
    >R >R                        ( x y w h  R: len addr )
    0 WG-ALLOC                   ( x y w h widget )
    >R                           ( x y w h  R: len addr widget )
    R@ WG-H WG!
    R@ WG-W WG!
    R@ WG-Y WG!
    R@ WG-X WG!
    \ Allocate window data
    WD-WIN-SIZE ALLOCATE DROP    ( wdata  R: len addr widget )
    DUP WD-WIN-SIZE 0 FILL
    R> OVER >R ROT              \ juggle to store data
    \ simplified: use variables for sanity
    R> R> R>                     ( wdata widget len addr )
    \ ... store title and data pointer ...
    ;

\ Render a window
: RENDER-WINDOW  ( widget -- )
    DUP WG-X WG@ SWAP DUP WG-Y WG@ SWAP
    DUP WG-W WG@ SWAP WG-H WG@  ( x y w h )
    \ Draw window background
    CLR-WIN-BG -ROT 2OVER 2OVER FAST-RECT
    \ Draw border
    CLR-WIN-BORDER -ROT 2OVER 2OVER GFX-BOX
    \ Draw title bar
    CLR-TITLE-BG -ROT SWAP 1+ SWAP 1+ 2 PICK 2 - 16
    FAST-RECT
    \ Draw title text
    \ ... render title string at (x+4, y+4) in CLR-TITLE-FG ...
    ;
```

### Window Manager (Flat List)

No overlapping windows for v1.  Tiled layout:

```forth
16 CONSTANT MAX-WINDOWS
CREATE WIN-TABLE  MAX-WINDOWS CELLS ALLOT
VARIABLE WIN-COUNT
VARIABLE WIN-FOCUS   \ index of focused window

: WIN-REGISTER  ( widget -- id )
    WIN-COUNT @ MAX-WINDOWS >= IF DROP -1 EXIT THEN
    WIN-COUNT @ CELLS WIN-TABLE + !
    WIN-COUNT @ DUP 1+ WIN-COUNT ! ;

: WIN-GET  ( id -- widget )  CELLS WIN-TABLE + @ ;

: WIN-RENDER-ALL  ( -- )
    WIN-COUNT @ 0 DO
        I WIN-GET DUP WG-FLAGS WG@ WGF-VISIBLE AND IF
            WG-RENDER WG@ EXECUTE
        ELSE DROP THEN
    LOOP ;
```

---

## 6. Panel

A panel is a lightweight container — a labeled rectangle with children.

```forth
: PANEL  ( x y w h label-addr label-len parent -- widget )
    >R                            ( x y w h la ll  R: parent )
    1 WG-ALLOC                    ( x y w h la ll widget )
    \ ... set position, size, label data ...
    R> OVER WG-ADD-CHILD          ( attach to parent )
    ;

: RENDER-PANEL  ( widget -- )
    \ Draw border
    DUP WG-X WG@ OVER WG-Y WG@ 2OVER
    WG-W WG@ SWAP WG-H WG@
    CLR-WIN-BORDER SWAP GFX-BOX
    \ Draw label at top-left corner
    \ ... render label text at (x+4, y-4) or (x+4, y+2) ...
    \ Render children
    DUP WG-CHILD WG@ BEGIN
        DUP WHILE
        DUP WG-RENDER WG@ EXECUTE
        WG-SIBLING WG@
    REPEAT DROP DROP ;
```

---

## 7. Menu

A menu is a vertical list of items.  Each item has a label and an xt
to execute when selected.

```forth
\ Menu item: 3 cells
\   +0   label-addr
\   +8   label-len
\  +16   action-xt

0 CONSTANT MI-LABEL
8 CONSTANT MI-LEN
16 CONSTANT MI-ACTION
24 CONSTANT MI-SIZE

\ Menu-specific data:
\   +0   items-addr    ( pointer to array of menu items )
\   +8   item-count
\  +16   selected      ( currently highlighted index )
\  +24   item-height   ( pixels per item, default 12 )

: MENU  ( nitems parent -- widget )
    >R                            ( nitems  R: parent )
    4 WG-ALLOC                    ( nitems widget )
    SWAP                          ( widget nitems )
    \ Allocate item array
    DUP MI-SIZE * ALLOCATE DROP   ( widget nitems items )
    \ store items-addr, item-count in widget data
    \ ...
    R> OVER WG-ADD-CHILD ;

: MENU-ADD-ITEM  ( label-addr label-len xt menu -- )
    \ append to item array at current count
    ;

: RENDER-MENU  ( widget -- )
    \ For each item:
    \   If selected: draw CLR-MENU-SEL background, CLR-HILITE-FG text
    \   Else: draw CLR-MENU-BG background, CLR-TEXT text
    ;

: MENU-KEY  ( key widget -- )
    \ Up arrow: selected--
    \ Down arrow: selected++
    \ Enter: execute selected item's action-xt
    ;
```

### Menu Bar

```forth
: MENU-BAR  ( parent -- widget )
    \ Horizontal bar across top of window
    \ Contains multiple dropdown menus
    \ Tab / arrow keys switch between menus
    \ Enter opens/selects, Escape closes
    ;
```

---

## 8. Text Editor Widget

This is the crown jewel.  A buffer-backed text editor with:
- Line-oriented storage (like ED, but graphical)
- Cursor with blink animation
- Scrolling (vertical)
- Line numbers (optional)
- Syntax-aware highlighting (future)

### Buffer Layout

```forth
\ Editor data:
\   +0   buf-addr     ( pointer to text buffer )
\   +8   buf-size     ( allocated size in bytes )
\  +16   gap-start    ( gap buffer: start of gap )
\  +24   gap-end      ( gap buffer: end of gap )
\  +32   cursor       ( logical cursor position in text )
\  +40   scroll-y     ( first visible line number )
\  +48   total-lines  ( cached line count )
\  +56   mark         ( selection start, -1 = no selection )
\  +64   dirty        ( modification flag )
\  +72   filename     ( pointer to filename string, 0 = untitled )
\  +80   fn-len       ( filename length )

: ED-ALLOC-BUF  ( size -- editor-data )
    DUP ALLOCATE DROP           ( size buf )
    DUP ROT 0 FILL              ( buf )
    88 ALLOCATE DROP             ( buf edata )
    TUCK !                       \ edata.buf-addr = buf
    ;
```

### Gap Buffer

The gap buffer is the classic data structure for text editors.
All text before the cursor is at buf[0..gap_start).
All text after the cursor is at buf[gap_end..buf_size).
The gap is the empty space between.

```forth
: GAP-SIZE  ( ed -- n )
    DUP 24 + @ SWAP 16 + @ - ;

: GAP-MOVE-TO  ( pos ed -- )
    \ Move the gap to position pos in the logical text.
    \ If pos < gap_start: CMOVE bytes from [pos..gap_start) to
    \   [gap_end - (gap_start - pos) .. gap_end)
    \ If pos > gap_start: CMOVE bytes from [gap_end..gap_end + delta)
    \   to [gap_start..gap_start + delta)
    ;

: ED-INSERT-CHAR  ( char ed -- )
    DUP 16 + @                   \ gap_start
    OVER @ +                     \ buf + gap_start = insertion addr
    ROT SWAP C!                  \ store char
    1 SWAP 16 + +! ;             \ gap_start++

: ED-DELETE-CHAR  ( ed -- )
    \ Backspace: decrement gap_start if > 0
    DUP 16 + @ 0> IF
        -1 SWAP 16 + +!
    ELSE DROP THEN ;
```

### Rendering

```forth
: RENDER-EDITOR  ( widget -- )
    \ 1. Clear client area with CLR-EDIT-BG
    \ 2. Calculate visible line range from scroll-y
    \ 3. For each visible line:
    \    a. Optionally draw line number in CLR-TEXT-DIM
    \    b. Extract line text from gap buffer
    \    c. Draw text with GFX-TYPE at proper y offset
    \ 4. Draw cursor as a filled rect (CLR-CURSOR) at cursor position
    \    Toggle visibility based on timer for blink effect
    ;

: EDITOR-KEY  ( key widget -- )
    \ Printable char: ED-INSERT-CHAR, mark dirty
    \ Backspace: ED-DELETE-CHAR
    \ Left/Right arrow: move cursor
    \ Up/Down arrow: move cursor to prev/next line
    \ Page Up/Down: scroll
    \ Ctrl-S: save (FWRITE to filesystem)
    \ Escape: close/unfocus
    ;
```

---

## 9. Event Loop & Focus Model

### Keyboard Focus

Only one widget has focus at a time.  Keys go to the focused widget.
If the focused widget doesn't handle a key, it bubbles up to the parent.

```forth
VARIABLE FOCUS-WIDGET   \ currently focused widget, 0 = root

: DELIVER-KEY  ( key -- )
    FOCUS-WIDGET @ DUP 0= IF DROP EXIT THEN
    BEGIN
        2DUP WG-KEY WG@ DUP IF
            EXECUTE             \ returns consumed flag
            IF 2DROP EXIT THEN
        ELSE
            DROP
        THEN
        WG-PARENT WG@           \ bubble up
        DUP 0=
    UNTIL
    2DROP ;
```

### Main Event Loop

```forth
VARIABLE KALKI-RUNNING

: KALKI-LOOP  ( -- )
    1 KALKI-RUNNING !
    BEGIN
        \ Handle input
        KEY? IF KEY DELIVER-KEY THEN
        \ Render dirty widgets
        RENDER-ALL
        \ Vsync
        GFX-SYNC
    KALKI-RUNNING @ 0= UNTIL ;
```

### Dirty-Region Rendering

Instead of redrawing everything every frame, track which widgets are
dirty and only redraw those:

```forth
: RENDER-ALL  ( -- )
    WIN-COUNT @ 0 DO
        I WIN-GET DUP WG-FLAGS WG@ WGF-DIRTY AND IF
            DUP WG-RENDER WG@ EXECUTE
            DUP WG-FLAGS WG@ WGF-DIRTY INVERT AND
            OVER WG-FLAGS WG!   \ clear dirty flag
        ELSE DROP THEN
    LOOP ;
```

---

## 10. Desktop & Taskbar

### Desktop

The desktop is the root widget — fills the entire screen.  It renders:
1. Background fill (CLR-DESKTOP)
2. All child windows
3. Taskbar at bottom

```forth
: RENDER-DESKTOP  ( -- )
    CLR-DESKTOP GFX-CLEAR       \ fill background
    WIN-RENDER-ALL               \ render all windows
    RENDER-TASKBAR ;             \ render taskbar

: RENDER-TASKBAR  ( -- )
    \ Fixed 20px bar at bottom of screen
    CLR-BTN-FACE 0 GFX-H @ 20 - GFX-W @ 20 FAST-RECT
    \ Top border
    CLR-BTN-LIGHT 0 GFX-H @ 20 - GFX-W @ GFX-HLINE
    \ "Start" button area
    \ Clock at right edge (from RTC)
    ;
```

### Clock Widget

```forth
: RENDER-CLOCK  ( x y -- )
    \ Read RTC: HOUR MIN SEC
    \ Format as "HH:MM"
    \ Draw with GFX-TYPE at position
    ;
```

---

## 11. Font System

The built-in 8×8 font in graphics.f is fine for labels but too small
for comfortable reading.  Ideas for multi-size fonts:

### Scaled Fonts (Quick Win)

2× scale the 8×8 font to get a 16×16 font by doubling each pixel:

```forth
: GFX-CHAR-2X  ( char x y color -- )
    GFX-CLR !
    8 0 DO                       \ for each font row
        2 PICK GFX-GLYPH I + C@  \ get row bits
        8 0 DO                   \ for each bit
            DUP 0x80 AND IF
                GFX-CLR @
                3 PICK I 2* +
                3 PICK J 2* +
                2 2                  \ 2×2 block
                FAST-RECT
            THEN
            1 LSHIFT
        LOOP
        DROP
    LOOP
    DROP 2DROP ;
```

### Proportional Font (Future)

Store glyph widths in a parallel table:

```forth
CREATE GFX-FONT-WIDTH  96 ALLOT   \ width of each glyph (3-8 pixels)
\ Populate from font metrics analysis
```

### External Fonts (Future)

Store larger fonts (e.g., 12×16, 16×24) as MP64FS files.  Load into
XMEM on boot:

```forth
: LOAD-FONT  ( "filename" -- font-addr )
    OPEN DUP FSIZE
    XMEM-ALLOT                   \ allocate in ext mem
    DUP ROT FREAD DROP ;
```

---

## 12. Double Buffering

To eliminate flicker during window redraws:

```forth
VARIABLE FB-FRONT   \ currently displayed buffer address
VARIABLE FB-BACK    \ currently being drawn to

: FB-INIT-DOUBLE  ( -- )
    GFX-FB @ FB-FRONT !
    GFX-FB @ GFX-STR @ GFX-H @ * + FB-BACK ! ;

: FB-SWAP  ( -- )
    GFX-SYNC                     \ wait for vsync
    FB-BACK @ FB-BASE!           \ scanout switches to back buffer
    FB-FRONT @ FB-BACK @ FB-FRONT ! FB-BACK ! ; \ swap pointers

: FB-DRAW-TARGET  ( -- addr )
    FB-BACK @ ;                  \ always draw to back buffer
```

This requires 2× framebuffer memory (600 KiB at 640×480×8bpp).
Fits in HBW Bank 3 (1 MiB).

---

## 13. Scrollbar

```forth
: RENDER-SCROLLBAR  ( widget -- )
    \ Vertical scrollbar: narrow rect on right edge of parent
    \ Track: CLR-SCROLL-BG
    \ Thumb: CLR-SCROLL-FG, sized proportional to visible/total ratio
    \ Up/down arrows at top/bottom (optional)
    ;

: SCROLLBAR-KEY  ( key widget -- )
    \ Up arrow: scroll up
    \ Down arrow: scroll down
    \ Page keys: scroll by page
    ;
```

---

## 14. 3D Button Effect

Classic raised/sunken button borders:

```forth
: DRAW-3D-RAISED  ( x y w h -- )
    \ Top and left edges: CLR-BTN-LIGHT
    \ Bottom and right edges: CLR-BTN-SHADOW
    \ Outer bottom-right: CLR-BTN-DARK
    2OVER 2OVER
    CLR-BTN-LIGHT -ROT GFX-HLINE           \ top
    CLR-BTN-LIGHT -ROT SWAP GFX-VLINE      \ left
    \ ... bottom and right in shadow colors ...
    ;

: DRAW-3D-SUNKEN  ( x y w h -- )
    \ Reverse: shadow on top/left, light on bottom/right
    ;

: RENDER-BUTTON  ( widget -- )
    \ Draw 3D raised rect
    \ Draw label text centered
    ;

: BUTTON-PRESS  ( widget -- )
    \ Briefly redraw as sunken, execute action xt, redraw as raised
    ;
```

---

## 15. WVEC GUI Renderer (Bridge to KDOS)

Replace TUI renderers with framebuffer equivalents:

```forth
: GUI-TITLE  ( addr len -- )
    CLR-TITLE-FG GFX-CLR !
    GFX-CX @ GFX-CY @ CLR-TITLE-FG GFX-TYPE
    GFX-CR ;

: GUI-SECTION  ( addr len -- )
    GFX-CR
    CLR-TEXT GFX-CLR !
    GFX-CX @ GFX-CY @ CLR-TEXT GFX-TYPE
    GFX-CR ;

\ ... etc. for all 15 WVEC slots ...

: INSTALL-GUI  ( -- )
    ['] GUI-TITLE    WV-TITLE   WV!
    ['] GUI-SECTION  WV-SECTION WV!
    \ ... etc ...
    ;
```

---

## 16. State Diagram

```
                    ┌──────────┐
         boot ────→│  UART    │
                    │  REPL    │
                    └────┬─────┘
                         │ KALKI (command)
                    ┌────▼─────┐
                    │ Desktop  │
                    │  Init    │
                    └────┬─────┘
                         │
              ┌──────────▼──────────┐
              │    Event Loop       │
              │  KEY? → DELIVER-KEY │
              │  RENDER-ALL         │
              │  GFX-SYNC           │
              └──────────┬──────────┘
                         │ Escape / Quit
                    ┌────▼─────┐
                    │  UART    │
                    │  REPL    │
                    └──────────┘
```

---

## 17. Open Questions

1. **Mouse support?** — Would require a new MMIO peripheral.  For now,
   keyboard-only is the constraint.  Tab/arrow navigation for all widgets.

2. **Overlapping windows?** — Adds complexity (z-order, occlusion, redraw
   regions).  Start with tiled/non-overlapping, add overlap later.

3. **Theming?** — The palette is easy to swap.  Could support "themes"
   as different palette-init words.

4. **Unicode?** — The font is ASCII-only.  Extended characters would
   need multi-byte encoding + larger font tables.

5. **How does Kalki coexist with SCREENS?** — Option A: the `SCREENS`
   entry point detects framebuffer mode and uses Kalki rendering.
   Option B: `KALKI` is a separate entry point that replaces `SCREENS`.

6. **Performance?** — At 1 MHz effective CPU speed, full-screen redraws
   will be slow.  Dirty-region tracking is essential.  Tile engine
   acceleration for fills/clears is critical.

7. **Dialog boxes / modal windows?** — Need a modal stack that captures
   all input until dismissed.

8. **Integration with ED (line editor)?** — The text editor widget
   could replace or wrap ED's functionality with a graphical interface.
