\ =====================================================================
\  kalki-gfx.f -- Kalki GUI Framework: Phase 0 Graphics Primitives
\ =====================================================================
\  Fast framebuffer drawing for RGB565 (mode 1, 16bpp) direct color.
\
\  Provides:
\    FAST-HLINE, FAST-VLINE, FAST-RECT, FAST-BOX
\    GFX-CHAR, GFX-TYPE  (redefined — RGB565 fast path)
\    CLIP-SET, CLIP-RESET
\    CL-HLINE, CL-VLINE, CL-RECT, CL-BOX
\    GFX-BLIT2, GFX-SCROLL-UP2
\    FB-INIT-DOUBLE, FB-SWAP
\    RGB24>565, WFILL
\
\  Depends on: graphics.f (GFX-*, font data)
\
\  Default mode: 800x600 RGB565 (mode 1) — 65536 colors, 2 bytes/pixel.
\  Uses dedicated VRAM (4 MiB) for double buffering.
\  Frame budget: 800*600*2*2 = 1.83 MiB — easily fits.
\ =====================================================================

PROVIDED kalki-gfx.f
REQUIRE graphics.f

\ =====================================================================
\  Section 0: Color Conversion Helpers
\ =====================================================================

\ RGB24>565 ( rgb24 -- rgb565 )
\   Convert 0x00RRGGBB to 16-bit RGB565 (RRRRRGGGGGGBBBBB).
\   Extracts the TOP 5/6/5 bits of each 8-bit channel.
: RGB24>565  ( rgb24 -- rgb565 )
    DUP 16 RSHIFT 0xFF AND 3 RSHIFT 11 LSHIFT  ( rgb24 r5<<11 )
    SWAP DUP 8 RSHIFT 0xFF AND 2 RSHIFT 5 LSHIFT  ( r5<<11 rgb24 g6<<5 )
    ROT OR SWAP  ( rg rgb24 )
    0xFF AND 3 RSHIFT OR ;  ( rgb565 )

\ WFILL ( addr count color16 -- )
\   Fill 'count' 16-bit words with color16.  Like FILL but for W!.
: WFILL  ( addr count color16 -- )
    ROT ROT                     ( color16 addr count )
    0 DO                        ( color16 addr )
        2DUP W!                 \ store 16-bit pixel
        2 +                     \ next pixel
    LOOP
    2DROP ;

\ =====================================================================
\  Section 1: Fast Drawing Primitives
\ =====================================================================
\  RGB565 (16bpp) versions.  Each pixel = 2 bytes.  Uses W! for stores
\  and WFILL for horizontal spans.

\ FAST-HLINE ( color x y len -- )
\   Draw a horizontal line.  RGB565: W! in a loop.
: FAST-HLINE
    >R                          ( color x y  R: len )
    GFX-ADDR                    ( color addr  R: len )
    R>                          ( color addr len )
    ROT                         ( addr len color )
    WFILL ;

\ FAST-VLINE ( color x y len -- )
\   Draw a vertical line.  Computes address once, steps by stride.
: FAST-VLINE
    >R                          ( color x y  R: len )
    GFX-ADDR                    ( color addr  R: len )
    R>                          ( color addr len )
    0 DO                        ( color addr )
        2DUP W!                 \ store 16-bit pixel
        GFX-STR @ +             \ advance to next row
    LOOP
    2DROP ;

\ FAST-RECT ( color x y w h -- )
\   Filled rectangle.  Uses FAST-HLINE per row.
\   Reuses GFX-D* scratch vars from graphics.f.
: FAST-RECT
    GFX-DH ! GFX-DW ! GFX-DY ! GFX-DX ! GFX-DC !
    GFX-DH @ 0 DO
        GFX-DC @ GFX-DX @ GFX-DY @ I + GFX-DW @
        FAST-HLINE
    LOOP ;

\ FAST-BOX ( color x y w h -- )
\   Outlined rectangle.  Uses FAST-HLINE for horizontals,
\   FAST-VLINE for verticals.  Reuses GFX-D* scratch vars.
: FAST-BOX
    GFX-DH ! GFX-DW ! GFX-DY ! GFX-DX ! GFX-DC !
    \ Top edge
    GFX-DC @ GFX-DX @ GFX-DY @
    GFX-DW @ FAST-HLINE
    \ Bottom edge
    GFX-DC @ GFX-DX @ GFX-DY @ GFX-DH @ + 1-
    GFX-DW @ FAST-HLINE
    \ Left & right edges (skip corners already drawn)
    GFX-DH @ 2 > IF
        GFX-DC @ GFX-DX @
        GFX-DY @ 1+ GFX-DH @ 2 - FAST-VLINE
        GFX-DC @ GFX-DX @ GFX-DW @ + 1-
        GFX-DY @ 1+ GFX-DH @ 2 - FAST-VLINE
    THEN ;

\ GFX-CHAR ( char x y color -- )   [REDEFINED — RGB565 fast path]
\   Render an 8×8 glyph directly in RGB565 mode.
\   Computes row address once per row, uses direct W! — no CASE dispatch.
\   Shadows the slow generic GFX-CHAR from graphics.f (~3× faster).
VARIABLE _FC-CLR
VARIABLE _FC-ADDR

: GFX-CHAR  ( char x y color -- )
    _FC-CLR !                          ( char x y )
    GFX-ADDR _FC-ADDR !               ( char )
    GFX-GLYPH                         ( glyph-addr )
    8 0 DO                             \ 8 rows
        DUP I + C@                     ( glyph rowbits )
        _FC-ADDR @                     ( glyph rowbits addr )
        8 0 DO                         ( glyph rowbits addr )
            OVER 0x80 AND IF
                _FC-CLR @ OVER W!
            THEN
            2 +                        \ advance addr by 2 bytes (1 pixel)
            SWAP 1 LSHIFT SWAP        \ shift rowbits left
        LOOP
        DROP DROP                      ( glyph )
        _FC-ADDR @ GFX-STR @ + _FC-ADDR !   \ next row
    LOOP
    DROP ;

\ GFX-TYPE ( addr len color -- )   [REDEFINED — RGB565 fast path]
\   Render a string using the fast GFX-CHAR above.
\   Shadows the slow generic GFX-TYPE from graphics.f.
: GFX-TYPE  ( addr len color -- )
    _FC-CLR !                          ( addr len )
    0 DO                               ( addr )
        DUP I + C@                     ( addr char )
        GFX-CX @ GFX-CY @             ( addr char cx cy )
        _FC-CLR @                      ( addr char cx cy color )
        GFX-CHAR                       ( addr )
        GFX-CX @ 8 + GFX-CX !         \ advance cursor
        GFX-CX @ GFX-W @ >= IF
            0 GFX-CX !
            GFX-CY @ 8 + GFX-CY !
        THEN
    LOOP
    DROP ;

\ =====================================================================
\  Section 2: Clipping System
\ =====================================================================
\  Global clip rectangle.  All CL-* drawing words respect this rect.
\  Widgets set CLIP-SET to their bounds before rendering children.

VARIABLE CLIP-X0  VARIABLE CLIP-Y0
VARIABLE CLIP-X1  VARIABLE CLIP-Y1

\ CLIP-SET ( x0 y0 x1 y1 -- )
\   Set the global clip rectangle.  Coordinates are pixel positions;
\   the clip region is [x0,x1) × [y0,y1).
: CLIP-SET
    CLIP-Y1 ! CLIP-X1 ! CLIP-Y0 ! CLIP-X0 ! ;

\ CLIP-RESET ( -- )
\   Reset clip to full screen.
: CLIP-RESET
    0 CLIP-X0 !  0 CLIP-Y0 !
    GFX-W @ CLIP-X1 !  GFX-H @ CLIP-Y1 ! ;

\ --- Scratch variables for clipped drawing ---
\ CL-* used by CL-HLINE and CL-RECT (non-overlapping callers).
\ CV-* used by CL-VLINE.  GFX-D* used by CL-BOX.
\ This separation prevents variable clobbering across call chains.

VARIABLE CL-C                  \ color
VARIABLE CL-X   VARIABLE CL-Y
VARIABLE CL-W   VARIABLE CL-H
VARIABLE CL-X0V                \ clipped left edge
VARIABLE CL-Y0V                \ clipped top edge
VARIABLE CL-WC                 \ clipped width
VARIABLE CL-HC                 \ clipped height

VARIABLE CV-C                  \ CL-VLINE: color
VARIABLE CV-X   VARIABLE CV-Y  \ CL-VLINE: position
VARIABLE CV-H                  \ CL-VLINE: length

\ CL-HLINE ( color x y len -- )
\   Clipped horizontal line.  Uses CL-* scratch.
: CL-HLINE
    CL-W ! CL-Y ! CL-X ! CL-C !
    \ Y range check
    CL-Y @ CLIP-Y0 @ < IF EXIT THEN
    CL-Y @ CLIP-Y1 @ >= IF EXIT THEN
    \ X range: intersect [x, x+len) with [CLIP-X0, CLIP-X1)
    CL-X @ CLIP-X0 @ MAX CL-X0V !
    CL-X @ CL-W @ + CLIP-X1 @ MIN CL-X0V @ -
    DUP 0 <= IF DROP EXIT THEN
    CL-WC !
    CL-C @ CL-X0V @ CL-Y @ CL-WC @ FAST-HLINE ;

\ CL-VLINE ( color x y len -- )
\   Clipped vertical line.  Uses CV-* scratch.
: CL-VLINE
    CV-H ! CV-Y ! CV-X ! CV-C !
    \ X: single column must be within [CLIP-X0, CLIP-X1)
    CV-X @ CLIP-X0 @ < IF EXIT THEN
    CV-X @ CLIP-X1 @ >= IF EXIT THEN
    \ Y: clip [y, y+len) to [CLIP-Y0, CLIP-Y1)
    CV-Y @ CV-H @ + CLIP-Y1 @ MIN      ( bottom' )
    CV-Y @ CLIP-Y0 @ MAX               ( bottom' top' )
    TUCK -                              ( top' len' )
    DUP 0 <= IF 2DROP EXIT THEN        ( top' len' )
    CV-C @ CV-X @ 2SWAP                ( color x top' len' )
    FAST-VLINE ;

\ CL-RECT ( color x y w h -- )
\   Clipped filled rectangle.  Pre-clips the rectangle, then draws
\   with FAST-HLINE (no per-line clip overhead).  Uses CL-* scratch.
: CL-RECT
    CL-H ! CL-W ! CL-Y ! CL-X ! CL-C !
    \ Clip Y range
    CL-Y @ CLIP-Y0 @ MAX CL-Y0V !
    CL-Y @ CL-H @ + CLIP-Y1 @ MIN CL-Y0V @ -
    DUP 0 <= IF DROP EXIT THEN
    CL-HC !
    \ Clip X range
    CL-X @ CLIP-X0 @ MAX CL-X0V !
    CL-X @ CL-W @ + CLIP-X1 @ MIN CL-X0V @ -
    DUP 0 <= IF DROP EXIT THEN
    CL-WC !
    \ Draw
    CL-HC @ 0 DO
        CL-C @ CL-X0V @ CL-Y0V @ I + CL-WC @
        FAST-HLINE
    LOOP ;

\ CL-BOX ( color x y w h -- )
\   Clipped outlined rectangle.  Uses GFX-D* scratch (from graphics.f)
\   so it doesn't collide with CL-HLINE's CL-* or CL-VLINE's CV-*.
: CL-BOX
    GFX-DH ! GFX-DW ! GFX-DY ! GFX-DX ! GFX-DC !
    \ Top edge
    GFX-DC @ GFX-DX @ GFX-DY @
    GFX-DW @ CL-HLINE
    \ Bottom edge
    GFX-DC @ GFX-DX @ GFX-DY @ GFX-DH @ + 1-
    GFX-DW @ CL-HLINE
    \ Left & right edges
    GFX-DH @ 2 > IF
        GFX-DC @ GFX-DX @
        GFX-DY @ 1+ GFX-DH @ 2 - CL-VLINE
        GFX-DC @ GFX-DX @ GFX-DW @ + 1-
        GFX-DY @ 1+ GFX-DH @ 2 - CL-VLINE
    THEN ;

\ =====================================================================
\  Section 3: Blit (fixed rewrite)
\ =====================================================================
\  The original GFX-BLIT in graphics.f has broken stack management.
\  This rewrite stores arguments in variables, then CMOVE per row.

VARIABLE BLIT-SRC              \ source buffer address
VARIABLE BLIT-SS               \ source stride (bytes per row)
VARIABLE BLIT-X   VARIABLE BLIT-Y
VARIABLE BLIT-W   VARIABLE BLIT-H

\ GFX-BLIT2 ( src x y w h -- )
\   Blit a rectangular region from src buffer to framebuffer.
\   Source is assumed tightly packed (stride = w * bpp).
\   For custom source stride, set BLIT-SS after calling this setup.
: GFX-BLIT2
    BLIT-H ! BLIT-W ! BLIT-Y ! BLIT-X ! BLIT-SRC !
    BLIT-W @ GFX-BPP @ * BLIT-SS !
    BLIT-H @ 0 DO
        BLIT-SRC @ I BLIT-SS @ * +     \ source row address
        BLIT-X @ BLIT-Y @ I + GFX-ADDR \ dest row address
        BLIT-W @ GFX-BPP @ *           \ bytes per row
        CMOVE
    LOOP ;

\ =====================================================================
\  Section 4: Scroll (fixed rewrite)
\ =====================================================================
\  The original GFX-SCROLL-UP is incomplete — it never clears the
\  newly exposed bottom rows.  This version finishes the job.

VARIABLE SCROLL-N              \ scroll distance in bytes

\ GFX-SCROLL-UP2 ( nrows -- )
\   Scroll the framebuffer up by nrows pixel rows.
\   Copies remaining content up, then clears the bottom.
: GFX-SCROLL-UP2
    GFX-STR @ * SCROLL-N !
    \ Copy: src = FB + scroll_n, dst = FB, count = total - scroll_n
    GFX-FB @ SCROLL-N @ +              ( src )
    GFX-FB @                            ( src dst )
    GFX-STR @ GFX-H @ * SCROLL-N @ -   ( src dst count )
    CMOVE
    \ Clear bottom rows (fill with black = 0x0000)
    GFX-FB @ GFX-STR @ GFX-H @ * +     ( fb_end )
    SCROLL-N @ -                        ( clear_start )
    SCROLL-N @ 2 /                      ( clear_start wpixels )
    0 WFILL ;

\ =====================================================================
\  Section 5: Double Buffering
\ =====================================================================
\  Two framebuffers in memory.  Draw to the back buffer, then swap
\  on vsync to eliminate flicker.  FB-FRONT is displayed; FB-BACK
\  is the draw target (aliased to GFX-FB for all drawing primitives).

VARIABLE FB-FRONT              \ address displayed by hardware
VARIABLE FB-BACK               \ address we draw to (= GFX-FB)

\ FB-INIT-DOUBLE ( -- )
\   Set up double buffering.  Call after GFX-INIT.
\   Front buffer = current GFX-FB.  Back buffer = immediately after.
: FB-INIT-DOUBLE
    GFX-FB @ FB-FRONT !
    GFX-FB @ GFX-STR @ GFX-H @ * + FB-BACK !
    \ Start drawing to back buffer
    FB-BACK @ GFX-FB !
    \ Clear back buffer (16-bit zero fill)
    FB-BACK @ GFX-STR @ GFX-H @ * 2 / 0 WFILL ;

\ FB-SWAP ( -- )
\   Swap front and back buffers on vsync.  After this call:
\   - The newly drawn frame becomes visible (new front)
\   - Drawing continues to the old front (new back)
: FB-SWAP
    GFX-SYNC
    \ Swap pointers
    FB-FRONT @                          ( old_front )
    FB-BACK @ FB-FRONT !               \ front = old back (display it)
    FB-BACK !                           \ back = old front (draw here)
    \ Update hardware and drawing target
    FB-FRONT @ FB-BASE!
    FB-BACK @ GFX-FB ! ;

\ FB-COPY-BACK ( -- )
\   Copy front buffer content to back buffer.  Call after FB-SWAP
\   so the back buffer starts with a complete scene.  This lets you
\   do incremental (partial) redraws instead of repainting everything.
: FB-COPY-BACK
    FB-FRONT @ FB-BACK @ GFX-STR @ GFX-H @ * CMOVE ;

\ =====================================================================
\  Section 6: Kalki GFX Initialization
\ =====================================================================

\ KALKI-GFX-INIT ( w h -- )
\   Initialize for Kalki: RGB565 mode (mode 1), dedicated VRAM,
\   double buffered, clip to full screen.
\   Default: 800x600 — 1.83 MiB double-buffered in 4 MiB VRAM.
: KALKI-GFX-INIT
    1 GFX-INIT
    FB-INIT-DOUBLE
    CLIP-RESET ;

\ =====================================================================
\  Section 7: Smoke Test
\ =====================================================================

\ RGB565 color literals for smoke test
0xF800 CONSTANT _T-RED
0x07E0 CONSTANT _T-GREEN
0x001F CONSTANT _T-BLUE
0xFFFF CONSTANT _T-WHITE
0xFFE0 CONSTANT _T-YELLOW
0x07FF CONSTANT _T-CYAN

: KALKI-GFX-TEST  ( -- )
    800 600 KALKI-GFX-INIT
    \ Fast filled rects (direct RGB565 colors)
    _T-RED    10  10  200 100 FAST-RECT
    _T-GREEN  50  50  200 100 FAST-RECT
    _T-BLUE   90  90  200 100 FAST-RECT
    \ Fast outlined boxes
    _T-WHITE  10  10  200 100 FAST-BOX
    _T-WHITE  50  50  200 100 FAST-BOX
    _T-WHITE  90  90  200 100 FAST-BOX
    \ Clipped drawing (clip to center region)
    100 80 700 520 CLIP-SET
    _T-YELLOW 80  60  200  80 CL-RECT   \ partially clipped
    _T-CYAN   600 450 200 200 CL-RECT   \ partially clipped
    _T-WHITE  80  60  200  80 CL-BOX    \ partially clipped
    CLIP-RESET
    \ Text (GFX-TYPE is now RGB565 fast path)
    0 GFX-CX !  320 GFX-CY !
    S" Kalki GFX -- 800x600 RGB565" _T-WHITE GFX-TYPE
    \ Blit test: copy a 32x16 strip from (10,10) to (400,350)
    10 10 GFX-ADDR              ( src )
    400 350 32 16 GFX-BLIT2
    \ Scroll test
    8 GFX-SCROLL-UP2
    FB-SWAP
    ." kalki-gfx test complete" CR ;
