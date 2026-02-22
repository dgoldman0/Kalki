\ =====================================================================
\  kalki-color.f -- Kalki GUI Framework: Phase 1 Color System
\ =====================================================================
\  GUI palette constants and theme support for 8bpp indexed color.
\
\  Provides:
\    CLR-BLACK through CLR-WARN  (25 color constants, indices 0-24)
\    KALKI-PAL-INIT              (program palette registers)
\    THEME-CLASSIC, THEME-DARK, THEME-OCEAN  (theme tables)
\    THEME-LOAD                  (apply a theme)
\
\  Palette layout:
\    0-24   GUI system colors (set by KALKI-PAL-INIT)
\    25-31  Reserved for future system use
\    32-255 Application-defined (sprites, gradients, etc.)
\
\  Depends on: kalki-gfx.f (and transitively graphics.f)
\ =====================================================================

PROVIDED kalki-color.f
REQUIRE kalki-gfx.f

\ =====================================================================
\  Section 1: Color Constants
\ =====================================================================
\  These are palette indices (0-24).  The actual RGB values are
\  programmed by KALKI-PAL-INIT or THEME-LOAD.

 0 CONSTANT CLR-BLACK
 1 CONSTANT CLR-DESKTOP         \ steel blue background
 2 CONSTANT CLR-WIN-BG          \ warm gray window fill
 3 CONSTANT CLR-WIN-BORDER      \ window border
 4 CONSTANT CLR-TITLE-BG        \ active title bar background
 5 CONSTANT CLR-TITLE-FG        \ active title bar text
 6 CONSTANT CLR-TITLE-INACTIVE  \ inactive title bar
 7 CONSTANT CLR-TEXT            \ primary text color
 8 CONSTANT CLR-TEXT-DIM        \ secondary / disabled text
 9 CONSTANT CLR-HIGHLIGHT       \ selection highlight background
10 CONSTANT CLR-HILITE-FG       \ selection highlight text
11 CONSTANT CLR-BTN-FACE        \ button face / control surface
12 CONSTANT CLR-BTN-LIGHT       \ 3D highlight (top-left bevel)
13 CONSTANT CLR-BTN-SHADOW      \ 3D shadow (bottom-right bevel)
14 CONSTANT CLR-BTN-DARK        \ outer dark shadow
15 CONSTANT CLR-MENU-BG         \ menu / popup background
16 CONSTANT CLR-MENU-SEL        \ menu selection bar
17 CONSTANT CLR-SCROLL-BG       \ scrollbar track
18 CONSTANT CLR-SCROLL-FG       \ scrollbar thumb
19 CONSTANT CLR-EDIT-BG         \ text input background
20 CONSTANT CLR-EDIT-FG         \ text input foreground
21 CONSTANT CLR-CURSOR          \ text cursor / caret
22 CONSTANT CLR-ERROR           \ red — error / destructive
23 CONSTANT CLR-SUCCESS         \ green — success / confirm
24 CONSTANT CLR-WARN            \ orange — warning / caution

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
\   Program palette entries 0-24 from a theme table.
\   Each table entry is one cell (64-bit) holding a 24-bit RGB value.
: THEME-LOAD
    #GUI-COLORS 0 DO
        DUP I CELLS + @                ( theme rgb )
        I FB-PAL!                       ( theme )
    LOOP
    DROP ;

\ KALKI-PAL-INIT ( -- )
\   Program the default (Classic) GUI palette.
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

\ CLR>RGB ( idx -- rgb )
\   Read back the RGB value currently programmed for a palette index.
\   NOTE: Requires FB-PAL@ (not available in current BIOS).
\   Future: add FB-PAL@ to BIOS or implement palette shadow table.
\ : CLR>RGB  FB-PAL@ ;

\ =====================================================================
\  Section 5: Color Demo
\ =====================================================================

: KALKI-COLOR-TEST  ( -- )
    640 480 KALKI-GFX-INIT
    KALKI-PAL-INIT
    \ Fill desktop
    CLR-DESKTOP GFX-CLEAR
    \ Draw palette swatches (5 rows × 5 columns, 60×30 each)
    #GUI-COLORS 0 DO
        I                               ( color )
        I 5 MOD 64 * 20 +              ( color x )
        I 5 / 36 * 20 +                ( color x y )
        60 30                           ( color x y w h )
        FAST-RECT
    LOOP
    \ Labels
    0 GFX-CX !  210 GFX-CY !
    S" Kalki Color System - Classic" CLR-TITLE-FG GFX-TYPE
    \ Dark theme preview
    THEME-DARK THEME-LOAD
    #GUI-COLORS 0 DO
        I  I 5 MOD 64 * 20 +  I 5 / 36 * 240 +  60 30 FAST-RECT
    LOOP
    0 GFX-CX !  430 GFX-CY !
    S" Dark Theme" 5 GFX-TYPE
    \ Restore classic
    KALKI-PAL-INIT
    FB-SWAP
    ." kalki-color test complete" CR ;
