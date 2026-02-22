\ kalki-basic.f — Basic widgets: label, button, panel, separator
\ =====================================================================
\  Phase 3 of the Kalki GUI framework.
\
\  Depends on: kalki-widget.f (widget core)
\              kalki-gfx.f (drawing primitives)
\              kalki-color.f (theme colors)
\
\  Widgets store text as addr+len in allocated data blocks.
\  Callers must ensure strings outlive the widget.
\ =====================================================================
PROVIDED kalki-basic.f
REQUIRE kalki-widget.f

\ =====================================================================
\  Section 1: Data Block Layouts
\ =====================================================================
\  Label data:  +0 text-addr  +8 text-len              = 16 bytes
\  Button data: +0 text-addr  +8 text-len  +16 XT      = 24 bytes
\  Panel data:  +0 text-addr  +8 text-len              = 16 bytes

16 CONSTANT /LABEL-DATA
24 CONSTANT /BUTTON-DATA
16 CONSTANT /PANEL-DATA

\ Data field accessors ( data-ptr -- field-addr )
: WD.TEXT     ;                  \ +0
: WD.TLEN    8 + ;              \ +8
: WD.ACTION  16 + ;             \ +16

\ =====================================================================
\  Section 2: Render Scratch Variables
\ =====================================================================
\  Used by all render words.  Avoids deep stack gymnastics.

VARIABLE RD-AX   VARIABLE RD-AY \ absolute x, y
VARIABLE RD-W    VARIABLE RD-H  \ widget width, height
VARIABLE RD-WG                  \ current widget pointer

\ Helper: load render scratch from widget ( widget -- )
: RD-SETUP
    DUP RD-WG !
    DUP WG-ABS-X RD-AX !
    DUP WG-ABS-Y RD-AY !
    DUP WG.W @ RD-W !
    WG.H @ RD-H ! ;

\ =====================================================================
\  Section 3: 3D Border Drawing
\ =====================================================================
\  Win95-style beveled borders using FAST-HLINE / FAST-VLINE.
\  Draws on the current RD-AX/AY/W/H rectangle.

\ Raised: light top-left, shadow bottom-right
: BEVEL-RAISED  ( -- )
    \ Top edge: light
    CLR-BTN-LIGHT RD-AX @ RD-AY @ RD-W @ FAST-HLINE
    \ Left edge: light
    CLR-BTN-LIGHT RD-AX @ RD-AY @ RD-H @ FAST-VLINE
    \ Bottom edge: shadow
    CLR-BTN-SHADOW RD-AX @ RD-AY @ RD-H @ 1- + RD-W @ FAST-HLINE
    \ Right edge: shadow
    CLR-BTN-SHADOW RD-AX @ RD-W @ 1- + RD-AY @ RD-H @ FAST-VLINE ;

\ Sunken: shadow top-left, light bottom-right (for pressed state)
: BEVEL-SUNKEN  ( -- )
    CLR-BTN-SHADOW RD-AX @ RD-AY @ RD-W @ FAST-HLINE
    CLR-BTN-SHADOW RD-AX @ RD-AY @ RD-H @ FAST-VLINE
    CLR-BTN-LIGHT RD-AX @ RD-AY @ RD-H @ 1- + RD-W @ FAST-HLINE
    CLR-BTN-LIGHT RD-AX @ RD-W @ 1- + RD-AY @ RD-H @ FAST-VLINE ;

\ =====================================================================
\  Section 4: Label
\ =====================================================================
\  Passive text display.  No focus, no key handler.

: LABEL-RENDER  ( widget -- )
    RD-SETUP
    RD-AX @ GFX-CX !
    RD-AY @ GFX-CY !
    RD-WG @ WG.DATA @
    DUP WD.TEXT @ SWAP WD.TLEN @
    CLR-TEXT GFX-TYPE ;

\ Factory variables (avoid deep stack)
VARIABLE _F-X     VARIABLE _F-Y
VARIABLE _F-W     VARIABLE _F-H
VARIABLE _F-TA    VARIABLE _F-TL
VARIABLE _F-XT    VARIABLE _F-PAR

\ LABEL ( x y text-addr text-len parent -- widget )
: LABEL
    _F-PAR ! _F-TL ! _F-TA ! _F-Y ! _F-X !
    WGT-LABEL WG-ALLOC
    DUP 0= IF EXIT THEN
    \ Set rect: width = len * FONT-W, height = FONT-H
    _F-X @ _F-Y @ _F-TL @ TEXT-WIDTH FONT-H WG-SET-RECT
    \ Alloc data
    /LABEL-DATA ALLOCATE IF DROP 0 EXIT THEN
    _F-TA @ OVER WD.TEXT !
    _F-TL @ OVER WD.TLEN !
    OVER WG.DATA !
    ['] LABEL-RENDER OVER WG.RENDER !
    _F-PAR @ OVER SWAP WG-ADD-CHILD ;

\ =====================================================================
\  Section 5: Button
\ =====================================================================
\  Raised 3D face + centered text.  Enter/Space fires action.
\  Tab-focusable.  Focused buttons show inner dotted border.

: BUTTON-RENDER  ( widget -- )
    RD-SETUP
    \ Flat button face (no bevel)
    CLR-BTN-FACE RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ Center text
    RD-WG @ WG.DATA @
    DUP WD.TLEN @ TEXT-WIDTH    ( data text-px-width )
    RD-W @ SWAP - 2 /          ( data offset-x )
    RD-AX @ + GFX-CX !         ( data )
    RD-H @ FONT-H - 2 / RD-AY @ + GFX-CY !
    DUP WD.TEXT @ SWAP WD.TLEN @
    CLR-TEXT GFX-TYPE
    \ Focus indicator: accent-colored outline
    RD-WG @ WGF-FOCUSED WG-FLAG? IF
        CLR-TITLE-BG RD-AX @ RD-AY @
        RD-W @ RD-H @ FAST-BOX
    THEN ;

13 CONSTANT K-ENTER
32 CONSTANT K-SPACE

: BUTTON-KEY  ( key widget -- consumed? )
    SWAP DUP K-ENTER = SWAP K-SPACE = OR 0= IF
        DROP 0 EXIT
    THEN
    \ Execute action
    WG.DATA @ WD.ACTION @
    DUP IF EXECUTE ELSE DROP THEN
    -1 ;

\ BUTTON ( x y w h text-addr text-len action-xt parent -- widget )
: BUTTON
    _F-PAR ! _F-XT ! _F-TL ! _F-TA ! _F-H ! _F-W ! _F-Y ! _F-X !
    WGT-BUTTON WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ _F-H @ WG-SET-RECT
    WG-MAKE-FOCUSABLE
    \ Alloc data
    /BUTTON-DATA ALLOCATE IF DROP 0 EXIT THEN
    _F-TA @ OVER WD.TEXT !
    _F-TL @ OVER WD.TLEN !
    _F-XT @ OVER WD.ACTION !
    OVER WG.DATA !
    ['] BUTTON-RENDER OVER WG.RENDER !
    ['] BUTTON-KEY OVER WG.ONKEY !
    _F-PAR @ OVER SWAP WG-ADD-CHILD ;

\ =====================================================================
\  Section 6: Panel
\ =====================================================================
\  Container with border and optional title label.
\  Children render inside the panel's bounds (clipped by framework).

: PANEL-RENDER  ( widget -- )
    RD-SETUP
    \ Fill background
    CLR-WIN-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ Subtle border
    CLR-WIN-BORDER RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-BOX
    \ Title text (if any)
    RD-WG @ WG.DATA @ DUP IF
        DUP WD.TLEN @ 0> IF
            RD-AX @ FONT-W + GFX-CX !
            RD-AY @ 2 + GFX-CY !
            DUP WD.TEXT @ SWAP WD.TLEN @
            CLR-TEXT GFX-TYPE
        ELSE DROP THEN
    ELSE DROP THEN ;

\ PANEL ( x y w h label-addr label-len parent -- widget )
: PANEL
    _F-PAR ! _F-TL ! _F-TA ! _F-H ! _F-W ! _F-Y ! _F-X !
    WGT-PANEL WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ _F-H @ WG-SET-RECT
    \ Alloc label data (even if empty — simplifies cleanup)
    /PANEL-DATA ALLOCATE IF DROP 0 EXIT THEN
    _F-TA @ OVER WD.TEXT !
    _F-TL @ OVER WD.TLEN !
    OVER WG.DATA !
    ['] PANEL-RENDER OVER WG.RENDER !
    _F-PAR @ OVER SWAP WG-ADD-CHILD ;

\ =====================================================================
\  Section 7: Horizontal Separator
\ =====================================================================
\  A single-pixel horizontal line in CLR-BTN-SHADOW.

: HSEP-RENDER  ( widget -- )
    RD-SETUP
    CLR-BTN-SHADOW RD-AX @ RD-AY @ RD-W @ FAST-HLINE ;

\ HSEP ( x y w parent -- widget )
: HSEP
    _F-PAR ! _F-W ! _F-Y ! _F-X !
    WGT-HSEP WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ 1 WG-SET-RECT
    ['] HSEP-RENDER OVER WG.RENDER !
    _F-PAR @ OVER SWAP WG-ADD-CHILD ;

\ =====================================================================
\  Section 8: Cleanup
\ =====================================================================
\  WG-DESTROY  ( widget -- ) — full teardown (dtor + data + struct)
\  WG-FREE-SUBTREE ( widget -- ) — post-order recursive destroy

: WG-FREE-DATA  ( widget -- )  WG-DESTROY ;  \ backward compat

\ =====================================================================
\  Section 9: Smoke Test
\ =====================================================================

VARIABLE _BT-COUNT

: _BT-ACTION   1 _BT-COUNT +! ;

VARIABLE _BT-ROOT
VARIABLE _BT-PANEL
VARIABLE _BT-BTN

: KALKI-BASIC-TEST  ( -- )
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    0 FOCUS-WIDGET !
    0 _BT-COUNT !
    CLR-DESKTOP 0 0 800 600 FAST-RECT
    WGT-ROOT WG-ALLOC DUP _BT-ROOT !
    0 0 800 600 WG-SET-RECT DROP
    20 20 300 200 S" Test Panel" _BT-ROOT @ PANEL
    _BT-PANEL !
    10 16 S" Hello from Kalki!" _BT-PANEL @ LABEL DROP
    10 40 120 24 S" Click Me" ['] _BT-ACTION _BT-PANEL @ BUTTON
    _BT-BTN !
    10 76 280 _BT-PANEL @ HSEP DROP
    10 86 S" After separator" _BT-PANEL @ LABEL DROP
    20 240 300 80 S" " _BT-ROOT @ PANEL DROP
    _BT-BTN @ FOCUS
    _BT-ROOT @ MARK-ALL-DIRTY
    _BT-ROOT @ RENDER-TREE
    FB-SWAP
    K-ENTER DELIVER-KEY DROP
    ." Click count: " _BT-COUNT @ . CR
    K-ENTER DELIVER-KEY DROP
    ." Click count: " _BT-COUNT @ . CR
    ." kalki-basic test complete" CR ;

