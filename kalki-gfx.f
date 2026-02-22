\ =====================================================================
\  kalki-gfx.f -- Kalki GUI Framework: Phase 0 Graphics Primitives
\ =====================================================================
\  Fixed and fast framebuffer drawing for 8bpp indexed-color mode.
\
\  Provides:
\    FAST-HLINE, FAST-VLINE, FAST-RECT, FAST-BOX
\    CLIP-SET, CLIP-RESET
\    CL-HLINE, CL-VLINE, CL-RECT, CL-BOX
\    GFX-BLIT2, GFX-SCROLL-UP2
\    FB-INIT-DOUBLE, FB-SWAP
\
\  Depends on: graphics.f (GFX-*, font data, palette helpers)
\
\  IMPORTANT: All FAST-* and CL-* words assume 8bpp mode (mode 0).
\  This is the optimal mode for GUI work: 1 byte/pixel, FILL-friendly,
\  64 pixels per tile for SIMD acceleration.
\ =====================================================================

PROVIDED kalki-gfx.f
REQUIRE graphics.f

\ =====================================================================
\  Section 1: Fast Drawing Primitives
\ =====================================================================
\  These replace the slow pixel-by-pixel routines in graphics.f with
\  FILL-based operations.  For 8bpp, each pixel = 1 byte, so FILL
\  writes a horizontal span in one call (~64x faster than GFX-HLINE).

\ FAST-HLINE ( color x y len -- )
\   Draw a horizontal line using FILL.  8bpp only.
: FAST-HLINE
    >R                          ( color x y  R: len )
    GFX-ADDR                    ( color addr  R: len )
    R>                          ( color addr len )
    ROT                         ( addr len color )
    FILL ;

\ FAST-VLINE ( color x y len -- )
\   Draw a vertical line.  Computes address once, steps by stride.
: FAST-VLINE
    >R                          ( color x y  R: len )
    GFX-ADDR                    ( color addr  R: len )
    R>                          ( color addr len )
    0 DO                        ( color addr )
        2DUP C!                 \ store pixel
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
    \ Clear bottom rows
    GFX-FB @ GFX-STR @ GFX-H @ * +     ( fb_end )
    SCROLL-N @ -                        ( clear_start )
    SCROLL-N @                          ( clear_start count )
    0 FILL ;

\ =====================================================================
\  Section 5: Double Buffering
\ =====================================================================
\  Two framebuffers in memory.  Draw to the back buffer, then swap
\  on vsync to eliminate flicker.  FB-FRONT is displayed; FB-BACK
\  is the draw target (aliased to GFX-FB for all drawing primitives).

VARIABLE FB-FRONT              \ address displayed by hardware
VARIABLE FB-BACK               \ address we draw to (= GFX-FB)

\ FB-INIT-DOUBLE ( -- )
\   Set up double buffering.  Call after GFX-INIT or GFX-INIT-HBW.
\   Front buffer = current GFX-FB.  Back buffer = immediately after.
: FB-INIT-DOUBLE
    GFX-FB @ FB-FRONT !
    GFX-FB @ GFX-STR @ GFX-H @ * + FB-BACK !
    \ Start drawing to back buffer
    FB-BACK @ GFX-FB !
    \ Clear back buffer
    FB-BACK @ GFX-STR @ GFX-H @ * 0 FILL ;

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

\ =====================================================================
\  Section 6: Kalki GFX Initialization
\ =====================================================================

\ KALKI-GFX-INIT ( w h -- )
\   Initialize for Kalki: 8bpp mode, HBW for tile acceleration,
\   double buffered, clip to full screen.
: KALKI-GFX-INIT
    0 GFX-INIT-HBW
    FB-INIT-DOUBLE
    CLIP-RESET ;

\ =====================================================================
\  Section 7: Smoke Test
\ =====================================================================

: KALKI-GFX-TEST  ( -- )
    640 480 KALKI-GFX-INIT
    GFX-PAL-DEFAULT
    \ Fast filled rects
    1  10  10  200 100 FAST-RECT
    4  50  50  200 100 FAST-RECT
    2  90  90  200 100 FAST-RECT
    \ Fast outlined boxes
    15 10  10  200 100 FAST-BOX
    15 50  50  200 100 FAST-BOX
    15 90  90  200 100 FAST-BOX
    \ Clipped drawing (clip to center region)
    100 80 540 400 CLIP-SET
    14  80  60  200  80 CL-RECT   \ partially clipped
    3   500 350 200 200 CL-RECT   \ partially clipped
    11  80  60  200  80 CL-BOX    \ partially clipped
    CLIP-RESET
    \ Text
    0 GFX-CX !  220 GFX-CY !
    S" Kalki GFX Phase 0 — OK" 15 GFX-TYPE
    \ Blit test: copy a 32x16 strip from (10,10) to (300,250)
    10 10 GFX-ADDR              ( src )
    300 250 32 16 GFX-BLIT2
    \ Scroll test
    8 GFX-SCROLL-UP2
    FB-SWAP
    ." kalki-gfx test complete" CR ;
