\ kalki-menu.f — Phase 5: Menu System
\ =====================================================================
\  Menu bars and dropdown menus for the Kalki GUI framework.
\
\  Provides:
\    MENU-CREATE   ( max-items -- menu | 0 )
\    MENU-ADD      ( label-addr label-len action-xt menu -- )
\    MENU-ADD-SEP  ( menu -- )
\    MENU-FREE     ( menu -- )
\    MENU-BAR      ( parent -- widget )
\    MBAR-ADD      ( label-addr label-len menu bar -- )
\
\  Usage:
\    1. Create menus:  4 MENU-CREATE VALUE file-menu
\    2. Add items:     S" Save"  ['] do-save file-menu MENU-ADD
\    3. Add separator: file-menu MENU-ADD-SEP
\    4. Create bar:    my-window MENU-BAR VALUE bar
\    5. Add triggers:  S" File" file-menu bar MBAR-ADD
\    6. Focus bar to navigate; Enter/Down opens dropdown
\
\  The menu bar occupies MBAR-H (20px) at the top of the parent
\  window's client area.  Content below should start at
\  WIN-CLIENT-Y + MBAR-H.
\
\  Dropdown rendering uses a modal key loop.  While open, the
\  scene is repainted each frame to cleanly overlay the dropdown.
\
\  Depends on: kalki-editor.f (EKEY, K-UP/K-DOWN/K-LEFT/K-RIGHT)
\ =====================================================================

PROVIDED kalki-menu.f
REQUIRE kalki-editor.f

\ =====================================================================
\  Section 1: Constants
\ =====================================================================

20 CONSTANT MBAR-H               \ menu bar height (pixels)
18 CONSTANT MN-ITEM-H            \ dropdown item height
 7 CONSTANT MN-SEP-H             \ separator item height
 8 CONSTANT MBAR-PAD             \ horizontal pad before first trigger
16 CONSTANT MBAR-GAP             \ gap between triggers
 8 CONSTANT MN-TEXT-PAD           \ text padding inside dropdown items
 8 CONSTANT MBAR-MAX              \ max triggers per menu bar

\ =====================================================================
\  Section 2: Menu Item Struct
\ =====================================================================
\  Each item is MI-SIZE (32) bytes in a contiguous array.
\    +0   label addr
\    +8   label len
\    +16  action XT
\    +24  flags (bit 0 = separator)

 0 CONSTANT MI.LABEL
 8 CONSTANT MI.LEN
16 CONSTANT MI.ACTION
24 CONSTANT MI.FLAGS
32 CONSTANT MI-SIZE

1 CONSTANT MIF-SEP                \ separator flag

\ =====================================================================
\  Section 3: Menu Data Structure
\ =====================================================================
\  Allocated block:
\    +0    count   (items added so far)
\    +8    cap     (max items)
\    +16   items[] (MI-SIZE each)

 0 CONSTANT MNU.COUNT
 8 CONSTANT MNU.CAP
16 CONSTANT MNU.ITEMS

\ =====================================================================
\  Section 4: Menu Creation & Manipulation
\ =====================================================================

VARIABLE _MC-CAP

\ MENU-CREATE ( max-items -- menu | 0 )
\   Allocate a menu struct with room for max-items entries.
: MENU-CREATE  ( max-items -- menu | 0 )
    DUP _MC-CAP !
    MI-SIZE * MNU.ITEMS +            ( alloc-size )
    ALLOCATE IF DROP 0 EXIT THEN     ( menu )
    0 OVER MNU.COUNT + !
    _MC-CAP @ OVER MNU.CAP + ! ;

VARIABLE _MA-MENU

\ MENU-ADD ( label-addr label-len action-xt menu -- )
\   Add a normal menu item.
: MENU-ADD  ( label-addr label-len action-xt menu -- )
    DUP _MA-MENU !
    DUP MNU.COUNT + @                ( la ll xt menu count )
    OVER MNU.CAP + @ OVER <= IF      \ full?
        2DROP 2DROP DROP EXIT
    THEN
    MI-SIZE * SWAP MNU.ITEMS + +     ( la ll xt item )
    SWAP OVER MI.ACTION + !          ( la ll item )
    SWAP OVER MI.LEN + !             ( la item )
    SWAP OVER MI.LABEL + !           ( item )
    0 SWAP MI.FLAGS + !
    1 _MA-MENU @ MNU.COUNT + +! ;

\ MENU-ADD-SEP ( menu -- )
\   Add a separator line.
: MENU-ADD-SEP  ( menu -- )
    DUP _MA-MENU !
    DUP MNU.COUNT + @                ( menu count )
    OVER MNU.CAP + @ OVER <= IF
        2DROP EXIT
    THEN
    MI-SIZE * SWAP MNU.ITEMS + +     ( item )
    0 OVER MI.LABEL + !
    0 OVER MI.LEN + !
    0 OVER MI.ACTION + !
    MIF-SEP SWAP MI.FLAGS + !
    1 _MA-MENU @ MNU.COUNT + +! ;

\ MENU-FREE ( menu -- )
\   Free a menu's memory.
: MENU-FREE  ( menu -- )
    ?DUP IF FREE THEN ;

\ =====================================================================
\  Section 5: Menu Bar Trigger Struct
\ =====================================================================
\  Each trigger in the bar: 32 bytes.
\    +0   label addr
\    +8   label len
\    +16  menu data pointer
\    +24  pixel X offset within bar

 0 CONSTANT MT.LABEL
 8 CONSTANT MT.LEN
16 CONSTANT MT.MENU
24 CONSTANT MT.X
32 CONSTANT MT-SIZE

\ =====================================================================
\  Section 6: Menu Bar Data
\ =====================================================================
\  Stored in WG.DATA of the menu bar widget.
\    +0   sel        highlighted trigger index (0-based)
\    +8   count      number of triggers
\    +16  triggers[] (MT-SIZE each, up to MBAR-MAX)

 0 CONSTANT MB.SEL
 8 CONSTANT MB.COUNT
16 CONSTANT MB.TRIGGERS

\ Total size: 16 + 8 * 32 = 272
MBAR-MAX MT-SIZE * MB.TRIGGERS + CONSTANT /MB-DATA

\ =====================================================================
\  Section 7: Dropdown Helpers
\ =====================================================================

\ Scratch variables for dropdown modal loop
VARIABLE _MN-BAR                 \ bar widget
VARIABLE _MN-BIDX                \ which trigger is open
VARIABLE _MN-MENU                \ current menu data ptr
VARIABLE _MN-SEL                 \ selected item index (0-based)
VARIABLE _MN-DONE                \ exit flag
VARIABLE _MN-ACT                 \ action XT to execute (0=none)
VARIABLE _MN-X                   \ dropdown screen X
VARIABLE _MN-Y                   \ dropdown screen Y
VARIABLE _MN-W                   \ dropdown pixel width
VARIABLE _MN-H                   \ dropdown pixel height
VARIABLE _MN-ROOT                \ root widget for scene repaint
VARIABLE _MN-CY                  \ current Y during item drawing
VARIABLE _MN-KEY                 \ current key in modal loop

\ _MN-FIND-ROOT ( widget -- root )
\   Walk parent chain to find the root.
: _MN-FIND-ROOT  ( widget -- root )
    BEGIN DUP WG.PARENT @ DUP 0<> WHILE NIP REPEAT DROP ;

\ _MN-GET-TRIG ( bar idx -- trig-addr )
\   Address of trigger struct at index in bar's data.
: _MN-GET-TRIG  ( bar idx -- trig-addr )
    MT-SIZE * SWAP WG.DATA @ MB.TRIGGERS + + ;

\ _MN-GET-MENU ( bar idx -- menu )
\   Get the menu data pointer for trigger at index.
: _MN-GET-MENU  ( bar idx -- menu )
    _MN-GET-TRIG MT.MENU + @ ;

\ _MN-IS-SEP ( idx -- flag )
\   Check if item at idx in _MN-MENU is a separator.
: _MN-IS-SEP  ( idx -- flag )
    MI-SIZE * _MN-MENU @ MNU.ITEMS + + MI.FLAGS + @ MIF-SEP AND ;

\ =====================================================================
\  Section 8: Dropdown Dimension Calculation
\ =====================================================================

VARIABLE _MC-MN                  \ scratch for calc

\ _MN-CALC-W ( menu -- w )
\   Dropdown width = max label width + padding.  Min MN-MIN-W.
: _MN-CALC-W  ( menu -- w )
    DUP _MC-MN !
    0                                    ( max-len )
    _MC-MN @ MNU.COUNT + @ 0 DO
        _MC-MN @ MNU.ITEMS + I MI-SIZE * +
        MI.LEN + @
        MAX
    LOOP
    FONT-W * MN-TEXT-PAD 2* + 2 +        ( w + border )
    120 MAX ;                            \ minimum 120px wide

\ _MN-CALC-H ( menu -- h )
\   Dropdown height = sum of item heights + 2px border.
: _MN-CALC-H  ( menu -- h )
    DUP _MC-MN !
    2                                    ( h — 2px border )
    _MC-MN @ MNU.COUNT + @ 0 DO
        _MC-MN @ MNU.ITEMS + I MI-SIZE * +
        MI.FLAGS + @ MIF-SEP AND IF
            MN-SEP-H +
        ELSE
            MN-ITEM-H +
        THEN
    LOOP ;

\ =====================================================================
\  Section 9: Dropdown Rendering
\ =====================================================================

\ _MN-DRAW-DROPDOWN ( -- )
\   Paint the dropdown overlay.  Uses _MN-X/Y/W/H, _MN-MENU, _MN-SEL.
\   Must be called AFTER RENDER-TREE (scene is on back buffer).
: _MN-DRAW-DROPDOWN  ( -- )
    \ Background fill
    CLR-MENU-BG _MN-X @ _MN-Y @ _MN-W @ _MN-H @ FAST-RECT
    \ Border
    CLR-WIN-BORDER _MN-X @ _MN-Y @ _MN-W @ _MN-H @ FAST-BOX
    \ Walk items
    _MN-Y @ 1+ _MN-CY !
    _MN-MENU @ MNU.COUNT + @ 0 DO
        _MN-MENU @ MNU.ITEMS + I MI-SIZE * +   ( item )
        DUP MI.FLAGS + @ MIF-SEP AND IF
            \ ── Separator line ──
            CLR-BTN-SHADOW
            _MN-X @ 4 +
            _MN-CY @ MN-SEP-H 2 / +
            _MN-W @ 8 -
            FAST-HLINE
            MN-SEP-H _MN-CY +!
        ELSE
            \ ── Normal item ──
            I _MN-SEL @ = IF
                \ Selection highlight bar
                CLR-MENU-SEL
                _MN-X @ 1+ _MN-CY @
                _MN-W @ 2 - MN-ITEM-H
                FAST-RECT
            THEN
            \ Item text
            _MN-X @ MN-TEXT-PAD + GFX-CX !
            _MN-CY @ MN-ITEM-H FONT-H - 2 / + GFX-CY !
            DUP MI.LABEL + @ OVER MI.LEN + @
            I _MN-SEL @ = IF CLR-HILITE-FG ELSE CLR-TEXT THEN
            GFX-TYPE
            MN-ITEM-H _MN-CY +!
        THEN
        DROP                             \ drop item pointer
    LOOP ;

\ =====================================================================
\  Section 10: Dropdown Navigation
\ =====================================================================

\ _MN-NEXT-ITEM ( -- )
\   Move selection to next non-separator item.
: _MN-NEXT-ITEM  ( -- )
    _MN-SEL @
    BEGIN
        1+
        DUP _MN-MENU @ MNU.COUNT + @ >= IF
            DROP _MN-SEL @ EXIT          \ at end — stay put
        THEN
        DUP _MN-IS-SEP 0=               \ not separator?
    UNTIL
    _MN-SEL ! ;

\ _MN-PREV-ITEM ( -- )
\   Move selection to previous non-separator item.
: _MN-PREV-ITEM  ( -- )
    _MN-SEL @
    BEGIN
        1-
        DUP 0< IF
            DROP _MN-SEL @ EXIT          \ at start — stay put
        THEN
        DUP _MN-IS-SEP 0=
    UNTIL
    _MN-SEL ! ;

\ =====================================================================
\  Section 11: Dropdown Repaint
\ =====================================================================

\ _MN-REPAINT ( -- )
\   Repaint the full scene, then overlay the dropdown.
: _MN-REPAINT  ( -- )
    _MN-ROOT @ MARK-ALL-DIRTY
    _MN-ROOT @ RENDER-TREE           \ scene → back buffer
    _MN-DRAW-DROPDOWN                \ dropdown on top
    FB-SWAP
    FB-COPY-BACK ;

\ =====================================================================
\  Section 12: Dropdown Menu Switch
\ =====================================================================

\ _MN-SWITCH-MENU ( -- )
\   Set up _MN-MENU/X/Y/W/H/SEL from current _MN-BAR + _MN-BIDX.
: _MN-SWITCH-MENU  ( -- )
    \ Get menu for this trigger
    _MN-BAR @ _MN-BIDX @ _MN-GET-MENU _MN-MENU !
    \ Compute dimensions
    _MN-MENU @ _MN-CALC-W _MN-W !
    _MN-MENU @ _MN-CALC-H _MN-H !
    \ Position below bar, aligned to trigger's X
    _MN-BAR @ _MN-BIDX @ _MN-GET-TRIG
    MT.X + @ _MN-BAR @ WG-ABS-X + 4 - _MN-X !
    _MN-BAR @ WG-ABS-Y MBAR-H + _MN-Y !
    \ Clamp to screen
    _MN-X @ _MN-W @ + 800 > IF
        800 _MN-W @ - 0 MAX _MN-X !
    THEN
    _MN-Y @ _MN-H @ + 600 > IF
        600 _MN-H @ - 0 MAX _MN-Y !
    THEN
    \ Select first non-separator item
    0 _MN-SEL !
    _MN-SEL @ _MN-IS-SEP IF _MN-NEXT-ITEM THEN
    \ Sync bar highlight
    _MN-BIDX @ _MN-BAR @ WG.DATA @ MB.SEL + ! ;

\ =====================================================================
\  Section 13: Modal Dropdown Loop
\ =====================================================================

\ _MN-MODAL ( -- )
\   Run the modal dropdown key loop.  Sets _MN-ACT if an action
\   is selected.  Returns when Esc or Enter is pressed.
: _MN-MODAL  ( -- )
    0 _MN-DONE !
    0 _MN-ACT !
    _MN-REPAINT
    BEGIN
        EKEY _MN-KEY !
        \ ── Up arrow ──
        _MN-KEY @ K-UP = IF
            _MN-PREV-ITEM  _MN-REPAINT
        THEN
        \ ── Down arrow ──
        _MN-KEY @ K-DOWN = IF
            _MN-NEXT-ITEM  _MN-REPAINT
        THEN
        \ ── Enter: execute selected item ──
        _MN-KEY @ K-ENTER = IF
            _MN-MENU @ MNU.COUNT + @ 0> IF
                _MN-SEL @ MI-SIZE *
                _MN-MENU @ MNU.ITEMS + +         ( item )
                DUP MI.FLAGS + @ MIF-SEP AND 0= IF
                    MI.ACTION + @ ?DUP IF _MN-ACT ! THEN
                ELSE DROP THEN
            THEN
            -1 _MN-DONE !
        THEN
        \ ── Escape: close ──
        _MN-KEY @ K-ESC = IF
            -1 _MN-DONE !
        THEN
        \ ── Left arrow: switch to previous trigger ──
        _MN-KEY @ K-LEFT = IF
            _MN-BIDX @ 0> IF
                -1 _MN-BIDX +!
                _MN-SWITCH-MENU
                _MN-REPAINT
            THEN
        THEN
        \ ── Right arrow: switch to next trigger ──
        _MN-KEY @ K-RIGHT = IF
            _MN-BIDX @ 1+
            _MN-BAR @ WG.DATA @ MB.COUNT + @ 1- MIN
            DUP _MN-BIDX @ <> IF
                _MN-BIDX !
                _MN-SWITCH-MENU
                _MN-REPAINT
            ELSE DROP THEN
        THEN
        _MN-DONE @
    UNTIL ;

\ =====================================================================
\  Section 14: Open Dropdown Entry Point
\ =====================================================================

\ _MBAR-OPEN-DROPDOWN ( bar trigger-idx -- )
\   Open a dropdown at the given trigger.  Runs modal loop.
\   On return, the scene is repainted without the dropdown.
: _MBAR-OPEN-DROPDOWN  ( bar trigger-idx -- )
    _MN-BIDX !
    _MN-BAR !
    _MN-BAR @ _MN-FIND-ROOT _MN-ROOT !
    _MN-SWITCH-MENU
    _MN-MODAL
    \ Repaint scene clean (no dropdown)
    _MN-ROOT @ MARK-ALL-DIRTY
    _MN-ROOT @ RENDER-TREE
    FB-SWAP
    FB-COPY-BACK
    \ Update bar selection BEFORE executing the action, because
    \ the action might free the bar widget (e.g. Close editor).
    _MN-BIDX @ _MN-BAR @ WG.DATA @ MB.SEL + !
    _MN-BAR @ WG-DIRTY
    \ Execute action LAST (it may free the bar/window)
    _MN-ACT @ ?DUP IF EXECUTE THEN ;

\ =====================================================================
\  Section 15: Menu Bar Renderer
\ =====================================================================

VARIABLE _MR-SEL                 \ selected trigger index
VARIABLE _MR-FOC                 \ is bar focused? (0 or -1)
VARIABLE _MR-TRIG               \ current trigger during rendering

: MBAR-RENDER  ( widget -- )
    RD-SETUP
    RD-WG @ WG.DATA @ DUP 0= IF DROP EXIT THEN
    DUP MB.SEL + @ _MR-SEL !
    RD-WG @ WGF-FOCUSED WG-FLAG? IF -1 ELSE 0 THEN _MR-FOC !
    \ — Background —
    CLR-MENU-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ — Bottom border —
    CLR-WIN-BORDER RD-AX @ RD-AY @ MBAR-H 1- + RD-W @ FAST-HLINE
    \ — Draw each trigger label —
    DUP MB.COUNT + @ SWAP MB.TRIGGERS +   ( count first-trig )
    SWAP 0 DO                             ( trig )
        DUP _MR-TRIG !
        \ Highlight bar: selected + focused
        _MR-FOC @ I _MR-SEL @ = AND IF
            CLR-HIGHLIGHT
            RD-AX @ _MR-TRIG @ MT.X + @ + 4 -
            RD-AY @ 2 +
            _MR-TRIG @ MT.LEN + @ FONT-W * 8 +
            MBAR-H 4 -
            FAST-RECT
        THEN
        \ Label text
        RD-AX @ _MR-TRIG @ MT.X + @ + GFX-CX !
        RD-AY @ MBAR-H FONT-H - 2 / + GFX-CY !
        _MR-TRIG @ MT.LABEL + @ _MR-TRIG @ MT.LEN + @
        _MR-FOC @ I _MR-SEL @ = AND IF CLR-HILITE-FG ELSE CLR-TEXT THEN
        GFX-TYPE
        MT-SIZE +                         ( next-trig )
    LOOP DROP ;

\ =====================================================================
\  Section 16: Menu Bar Key Handler
\ =====================================================================

VARIABLE _MBK-KEY
VARIABLE _MBK-DATA

: MBAR-KEY  ( key widget -- consumed? )
    WG.DATA @ DUP 0= IF DROP DROP 0 EXIT THEN
    _MBK-DATA !
    _MBK-KEY !
    _MBK-DATA @ MB.COUNT + @ 0= IF 0 EXIT THEN   \ no triggers
    \ ── Left arrow ──
    _MBK-KEY @ K-LEFT = IF
        _MBK-DATA @ MB.SEL + @ 1- 0 MAX
        _MBK-DATA @ MB.SEL + !
        FOCUS-WIDGET @ WG-DIRTY
        -1 EXIT
    THEN
    \ ── Right arrow ──
    _MBK-KEY @ K-RIGHT = IF
        _MBK-DATA @ MB.SEL + @
        1+ _MBK-DATA @ MB.COUNT + @ 1- MIN
        _MBK-DATA @ MB.SEL + !
        FOCUS-WIDGET @ WG-DIRTY
        -1 EXIT
    THEN
    \ ── Enter or Down: open dropdown ──
    _MBK-KEY @ K-ENTER = _MBK-KEY @ K-DOWN = OR IF
        FOCUS-WIDGET @ _MBK-DATA @ MB.SEL + @ _MBAR-OPEN-DROPDOWN
        -1 EXIT
    THEN
    0 ;

\ =====================================================================
\  Section 17: Menu Bar Destructor
\ =====================================================================

\ _MBAR-DTOR ( widget -- )
\   Free all owned menus.  WG-DESTROY frees WG.DATA after this.
: _MBAR-DTOR  ( widget -- )
    WG.DATA @ DUP 0= IF DROP EXIT THEN
    DUP MB.COUNT + @ SWAP MB.TRIGGERS +   ( count trigs )
    SWAP 0 DO
        DUP MT.MENU + @ MENU-FREE
        MT-SIZE +
    LOOP DROP ;

\ =====================================================================
\  Section 18: Menu Bar Factory
\ =====================================================================

\ MENU-BAR ( parent -- widget )
\   Create a menu bar widget at the top of a window's client area.
\   The bar spans the full parent width and is MBAR-H pixels tall.
\   Content below should start at y = WIN-CLIENT-Y + MBAR-H.
: MENU-BAR  ( parent -- widget )
    _F-PAR !
    WGT-MENU WG-ALLOC
    DUP 0= IF EXIT THEN
    WIN-CLIENT-X WIN-CLIENT-Y
    _F-PAR @ WG.W @ WIN-CLIENT-X 2* -
    MBAR-H WG-SET-RECT
    WG-MAKE-FOCUSABLE
    /MB-DATA ALLOCATE IF DROP 0 EXIT THEN
    DUP /MB-DATA 0 FILL
    OVER WG.DATA !
    ['] MBAR-RENDER OVER WG.RENDER !
    ['] MBAR-KEY OVER WG.ONKEY !
    ['] _MBAR-DTOR OVER WG.DTOR !
    _F-PAR @ OVER SWAP WG-ADD-CHILD ;

\ =====================================================================
\  Section 19: Adding Triggers to Bar
\ =====================================================================

VARIABLE _MBA-DATA
VARIABLE _MBA-IDX
VARIABLE _MBA-TRIG

\ MBAR-ADD ( label-addr label-len menu bar -- )
\   Add a named menu trigger to the bar.
: MBAR-ADD  ( label-addr label-len menu bar -- )
    WG.DATA @ DUP 0= IF DROP 2DROP DROP EXIT THEN
    _MBA-DATA !
    \ Check capacity
    _MBA-DATA @ MB.COUNT + @ DUP _MBA-IDX !
    MBAR-MAX >= IF 2DROP DROP EXIT THEN
    \ Get trigger slot
    _MBA-DATA @ MB.TRIGGERS + _MBA-IDX @ MT-SIZE * +
    _MBA-TRIG !
    \ Store fields: stack is ( label-addr label-len menu )
    _MBA-TRIG @ MT.MENU + !
    _MBA-TRIG @ MT.LEN + !
    _MBA-TRIG @ MT.LABEL + !
    \ Compute X pixel offset
    _MBA-IDX @ 0= IF
        MBAR-PAD _MBA-TRIG @ MT.X + !
    ELSE
        \ X = prev.X + prev.len * FONT-W + gap
        _MBA-DATA @ MB.TRIGGERS + _MBA-IDX @ 1- MT-SIZE * +   ( prev )
        DUP MT.X + @ SWAP MT.LEN + @ FONT-W * + MBAR-GAP +
        _MBA-TRIG @ MT.X + !
    THEN
    1 _MBA-DATA @ MB.COUNT + +! ;

\ =====================================================================
\  Section 20: Smoke Test
\ =====================================================================

VARIABLE _MT-ROOT
VARIABLE _MT-WIN
VARIABLE _MT-BAR
VARIABLE _MT-MN1
VARIABLE _MT-MN2
VARIABLE _MT-COUNT

: _MT-ACTION  1 _MT-COUNT +! ;

: _MT-ROOT-RENDER  ( widget -- )
    DROP CLR-DESKTOP 0 0 800 600 FAST-RECT ;

: KALKI-MENU-TEST  ( -- )
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    0 _MT-COUNT !
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    \ Root
    WGT-ROOT WG-ALLOC DUP _MT-ROOT !
    0 0 800 600 WG-SET-RECT DROP
    ['] _MT-ROOT-RENDER _MT-ROOT @ WG.RENDER !
    \ Window
    20 20 400 300 S" Menu Test" _MT-ROOT @ WINDOW
    _MT-WIN !
    \ Menu bar
    _MT-WIN @ MENU-BAR _MT-BAR !
    \ ── File menu ──
    4 MENU-CREATE _MT-MN1 !
    S" New"   ['] _MT-ACTION _MT-MN1 @ MENU-ADD
    S" Save"  ['] _MT-ACTION _MT-MN1 @ MENU-ADD
    _MT-MN1 @ MENU-ADD-SEP
    S" Close" ['] _MT-ACTION _MT-MN1 @ MENU-ADD
    \ ── Edit menu ──
    3 MENU-CREATE _MT-MN2 !
    S" Undo"  ['] _MT-ACTION _MT-MN2 @ MENU-ADD
    _MT-MN2 @ MENU-ADD-SEP
    S" Redo"  ['] _MT-ACTION _MT-MN2 @ MENU-ADD
    \ Add triggers to bar
    S" File" _MT-MN1 @ _MT-BAR @ MBAR-ADD
    S" Edit" _MT-MN2 @ _MT-BAR @ MBAR-ADD
    \ ── Verify structure ──
    _MT-BAR @ 0<> IF ." bar=ok " ELSE ." bar=FAIL " THEN
    _MT-BAR @ WG.TYPE @ WGT-MENU = IF ." type=ok " ELSE ." type=FAIL " THEN
    _MT-BAR @ WG.DATA @ MB.COUNT + @ 2 =
    IF ." trig=ok " ELSE ." trig=FAIL " THEN
    _MT-MN1 @ MNU.COUNT + @ 4 =
    IF ." items1=ok " ELSE ." items1=FAIL " THEN
    _MT-MN2 @ MNU.COUNT + @ 3 =
    IF ." items2=ok " ELSE ." items2=FAIL " THEN
    \ ── Render test ──
    _MT-BAR @ FOCUS
    _MT-ROOT @ MARK-ALL-DIRTY
    _MT-ROOT @ RENDER-TREE
    FB-SWAP
    ." render=ok "
    \ ── Dropdown calc tests ──
    _MT-MN1 @ _MN-CALC-W 0> IF ." calcw=ok " ELSE ." calcw=FAIL " THEN
    _MT-MN1 @ _MN-CALC-H 0> IF ." calch=ok " ELSE ." calch=FAIL " THEN
    CR
    \ Cleanup
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    _MT-ROOT @ WG-FREE-SUBTREE
    ." kalki-menu test complete" CR ;
