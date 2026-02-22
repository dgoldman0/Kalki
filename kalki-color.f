\ =====================================================================
\  kalki-color.f -- Kalki GUI Framework: Phase 1 Color System
\ =====================================================================
\  GUI color system for RGB565 direct color mode.
\
\  Provides:
\    CLR-BLACK through CLR-WARN  (25 color VARIABLEs, RGB565 values)
\    KALKI-PAL-INIT              (load default theme into CLR-* vars)
\    THEME-CLASSIC, THEME-DARK, THEME-OCEAN  (theme tables, 24-bit RGB)
\    THEME-LOAD                  (convert 24-bit theme → RGB565 CLR-*)
\
\  Color representation:
\    All CLR-* words return RGB565 values (16-bit direct color).
\    Theme tables store 24-bit 0x00RRGGBB; THEME-LOAD converts them
\    to RGB565 via RGB24>565 (defined in kalki-gfx.f).
\
\  Depends on: kalki-gfx.f (RGB24>565, drawing primitives, graphics.f)
\ =====================================================================

PROVIDED kalki-color.f
REQUIRE kalki-gfx.f

\ =====================================================================
\  Section 1: Color Variables
\ =====================================================================
\  Each CLR-* is a VARIABLE holding an RGB565 value.
\  THEME-LOAD fills them from a 24-bit theme table.

\ Color variable array — 25 cells, accessed as CLR-TABLE + index*CELL
CREATE CLR-TABLE  25 CELLS ALLOT

\ Convenience accessors: each returns the RGB565 value (not the address)
: CLR-BLACK          CLR-TABLE  0 CELLS + @ ;
: CLR-DESKTOP        CLR-TABLE  1 CELLS + @ ;
: CLR-WIN-BG         CLR-TABLE  2 CELLS + @ ;
: CLR-WIN-BORDER     CLR-TABLE  3 CELLS + @ ;
: CLR-TITLE-BG       CLR-TABLE  4 CELLS + @ ;
: CLR-TITLE-FG       CLR-TABLE  5 CELLS + @ ;
: CLR-TITLE-INACTIVE CLR-TABLE  6 CELLS + @ ;
: CLR-TEXT           CLR-TABLE  7 CELLS + @ ;
: CLR-TEXT-DIM       CLR-TABLE  8 CELLS + @ ;
: CLR-HIGHLIGHT      CLR-TABLE  9 CELLS + @ ;
: CLR-HILITE-FG      CLR-TABLE 10 CELLS + @ ;
: CLR-BTN-FACE       CLR-TABLE 11 CELLS + @ ;
: CLR-BTN-LIGHT      CLR-TABLE 12 CELLS + @ ;
: CLR-BTN-SHADOW     CLR-TABLE 13 CELLS + @ ;
: CLR-BTN-DARK       CLR-TABLE 14 CELLS + @ ;
: CLR-MENU-BG        CLR-TABLE 15 CELLS + @ ;
: CLR-MENU-SEL       CLR-TABLE 16 CELLS + @ ;
: CLR-SCROLL-BG      CLR-TABLE 17 CELLS + @ ;
: CLR-SCROLL-FG      CLR-TABLE 18 CELLS + @ ;
: CLR-EDIT-BG        CLR-TABLE 19 CELLS + @ ;
: CLR-EDIT-FG        CLR-TABLE 20 CELLS + @ ;
: CLR-CURSOR         CLR-TABLE 21 CELLS + @ ;
: CLR-ERROR          CLR-TABLE 22 CELLS + @ ;
: CLR-SUCCESS        CLR-TABLE 23 CELLS + @ ;
: CLR-WARN           CLR-TABLE 24 CELLS + @ ;

\ =====================================================================
\  Section 2: Theme Tables
\ =====================================================================
\  A theme is a 25-entry table of 24-bit RGB values (stored as cells).
\  THEME-LOAD programs palette entries 0-24 from a theme table.

25 CONSTANT #GUI-COLORS

\ Classic theme — warm gray, Win95/98 inspired
CREATE THEME-CLASSIC
    0x000000 ,    \  0 black
    0x3A6EA5 ,    \  1 desktop (steel blue)
    0xD4D0C8 ,    \  2 window bg (warm gray)
    0x808080 ,    \  3 window border
    0x0A246A ,    \  4 title bar bg (navy)
    0xFFFFFF ,    \  5 title bar text
    0x808080 ,    \  6 inactive title
    0x000000 ,    \  7 text
    0x808080 ,    \  8 dim text
    0x0A246A ,    \  9 highlight bg
    0xFFFFFF ,    \ 10 highlight text
    0xD4D0C8 ,    \ 11 button face
    0xFFFFFF ,    \ 12 button light
    0x808080 ,    \ 13 button shadow
    0x404040 ,    \ 14 button dark
    0xF0F0F0 ,    \ 15 menu bg
    0x0A246A ,    \ 16 menu selection
    0xC0C0C0 ,    \ 17 scrollbar bg
    0x808080 ,    \ 18 scrollbar fg
    0xFFFFFF ,    \ 19 edit bg
    0x000000 ,    \ 20 edit fg
    0x000000 ,    \ 21 cursor
    0xFF0000 ,    \ 22 error
    0x008000 ,    \ 23 success
    0xFFA500 ,    \ 24 warning

\ Dark theme — charcoal/slate, easy on the eyes
CREATE THEME-DARK
    0x000000 ,    \  0 black
    0x1E1E2E ,    \  1 desktop (dark slate)
    0x2D2D3D ,    \  2 window bg
    0x555568 ,    \  3 window border
    0x3D5A99 ,    \  4 title bar bg
    0xE0E0E0 ,    \  5 title bar text
    0x555568 ,    \  6 inactive title
    0xD4D4D4 ,    \  7 text (light gray)
    0x808090 ,    \  8 dim text
    0x3D5A99 ,    \  9 highlight bg
    0xFFFFFF ,    \ 10 highlight text
    0x3A3A4A ,    \ 11 button face
    0x555568 ,    \ 12 button light
    0x1A1A2A ,    \ 13 button shadow
    0x0A0A1A ,    \ 14 button dark
    0x2D2D3D ,    \ 15 menu bg
    0x3D5A99 ,    \ 16 menu selection
    0x2A2A3A ,    \ 17 scrollbar bg
    0x555568 ,    \ 18 scrollbar fg
    0x1E1E2E ,    \ 19 edit bg
    0xD4D4D4 ,    \ 20 edit fg
    0xE0E0E0 ,    \ 21 cursor
    0xFF4444 ,    \ 22 error
    0x44CC44 ,    \ 23 success
    0xFFAA33 ,    \ 24 warning

\ Ocean theme — blue-green, cool tones
CREATE THEME-OCEAN
    0x000000 ,    \  0 black
    0x1B4F72 ,    \  1 desktop (deep ocean)
    0xD5E8D4 ,    \  2 window bg (sea foam)
    0x5DADE2 ,    \  3 window border
    0x154360 ,    \  4 title bar bg
    0xF0F8FF ,    \  5 title bar text
    0x5DADE2 ,    \  6 inactive title
    0x1B2631 ,    \  7 text (dark navy)
    0x7FB3D8 ,    \  8 dim text
    0x2E86C1 ,    \  9 highlight bg
    0xFFFFFF ,    \ 10 highlight text
    0xAED6F1 ,    \ 11 button face
    0xD6EAF8 ,    \ 12 button light
    0x5DADE2 ,    \ 13 button shadow
    0x2E86C1 ,    \ 14 button dark
    0xEBF5FB ,    \ 15 menu bg
    0x2E86C1 ,    \ 16 menu selection
    0xAED6F1 ,    \ 17 scrollbar bg
    0x5DADE2 ,    \ 18 scrollbar fg
    0xFDFEFE ,    \ 19 edit bg
    0x1B2631 ,    \ 20 edit fg
    0x154360 ,    \ 21 cursor
    0xE74C3C ,    \ 22 error
    0x27AE60 ,    \ 23 success
    0xF39C12 ,    \ 24 warning

\ =====================================================================
\  Section 3: Theme Loading
\ =====================================================================

\ THEME-LOAD ( theme-addr -- )
\   Populate CLR-TABLE with RGB565 values converted from a 24-bit
\   theme table.  Each table entry is one cell holding 0x00RRGGBB.
: THEME-LOAD
    #GUI-COLORS 0 DO
        DUP I CELLS + @                ( theme rgb24 )
        RGB24>565                       ( theme rgb565 )
        CLR-TABLE I CELLS + !           ( theme )
    LOOP
    DROP ;

\ KALKI-PAL-INIT ( -- )
\   Load the default (Classic) GUI palette into CLR-TABLE.
: KALKI-PAL-INIT
    THEME-CLASSIC THEME-LOAD ;

\ =====================================================================
\  Section 4: Convenience Helpers
\ =====================================================================

\ THEME-APPLY ( theme-addr -- )
\   Load theme and force a full repaint.  (Repaint deferred until
\   widget system exists; for now just loads the palette.)
: THEME-APPLY
    THEME-LOAD ;

\ =====================================================================
\  Section 5: Color Demo
\ =====================================================================

: KALKI-COLOR-TEST  ( -- )
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    \ Fill desktop
    CLR-DESKTOP 0 0 800 600 FAST-RECT
    \ Draw palette swatches (5 rows × 5 columns, 80×36 each)
    #GUI-COLORS 0 DO
        CLR-TABLE I CELLS + @          ( color565 )
        I 5 MOD 84 * 20 +             ( color x )
        I 5 / 46 * 20 +               ( color x y )
        80 36                          ( color x y w h )
        FAST-RECT
    LOOP
    \ Labels
    20 GFX-CX !  260 GFX-CY !
    S" Kalki Color System - Classic" CLR-TITLE-FG GFX-TYPE
    \ Dark theme preview
    THEME-DARK THEME-LOAD
    #GUI-COLORS 0 DO
        CLR-TABLE I CELLS + @
        I 5 MOD 84 * 20 +  I 5 / 46 * 310 +  80 36 FAST-RECT
    LOOP
    20 GFX-CX !  550 GFX-CY !
    S" Dark Theme" CLR-TITLE-FG GFX-TYPE
    \ Restore classic
    KALKI-PAL-INIT
    FB-SWAP
    ." kalki-color test complete" CR ;
