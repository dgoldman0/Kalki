\ kalki-scroll.f — Phase 6: Scrollable Containers
\ =====================================================================
\  Scrollbar and listbox widgets.
\
\  Provides:
\    SCROLLBAR  ( x y w h parent -- widget )    vertical scrollbar
\    SB-UPDATE  ( total vis pos sb -- )         update scrollbar state
\    LISTBOX    ( x y w h parent -- widget )     scrollable list
\    LB-SET-ITEMS    ( count widget -- )         set item count
\    LB-SET-RENDER   ( xt widget -- )            set item render callback
\    LB-SET-ACTION   ( xt widget -- )            set Enter action
\    LB-SELECTED     ( widget -- idx )           get selected index
\    LB-SCROLL       ( widget -- scroll )        get scroll offset
\
\  Item render XT signature: ( index x y w selected? -- )
\
\  Depends on: kalki-basic.f (RD-SETUP, _F-* factory vars)
\              kalki-widget.f (widget core)
\              kalki-gfx.f (drawing primitives)
\              kalki-color.f (CLR-SCROLL-BG, CLR-SCROLL-FG)
\ =====================================================================

PROVIDED kalki-scroll.f
REQUIRE kalki-basic.f

\ =====================================================================
\  Section 1: Constants
\ =====================================================================

12 CONSTANT SB-WIDTH             \ scrollbar width in pixels

\ =====================================================================
\  Section 2: Scrollbar Data Layout
\ =====================================================================
\  Scrollbar data block (32 bytes):
\    +0   total       — total number of items
\    +8   visible     — number of visible items
\    +16  position    — current scroll position (0-based)
\    +24  orientation — 0=vertical, 1=horizontal (future)

: SB.TOTAL     ;                 \ +0
: SB.VISIBLE  8 + ;             \ +8
: SB.POS     16 + ;             \ +16
: SB.ORIENT  24 + ;             \ +24

32 CONSTANT /SB-DATA

\ =====================================================================
\  Section 3: Scrollbar Rendering
\ =====================================================================

VARIABLE _SB-TRACK-H             \ track height (pixels)
VARIABLE _SB-THUMB-H             \ thumb height (pixels)
VARIABLE _SB-THUMB-Y             \ thumb Y offset (pixels)

VARIABLE _SBC-TOTAL
VARIABLE _SBC-VIS

: _SB-CALC  ( data -- )
    DUP SB.TOTAL @  DUP _SBC-TOTAL !   ( data total )
    0= IF DROP                           \ no items → full thumb
        _SB-TRACK-H @ _SB-THUMB-H !
        0 _SB-THUMB-Y !  EXIT
    THEN
    DUP SB.VISIBLE @ _SBC-TOTAL @ MIN _SBC-VIS !  ( data )
    \ Thumb height
    _SB-TRACK-H @ _SBC-VIS @ * _SBC-TOTAL @ / 8 MAX _SB-THUMB-H !
    \ Scrollable range
    _SBC-TOTAL @ _SBC-VIS @ -            ( data scrollable )
    DUP 1 < IF
        DROP DROP 0 _SB-THUMB-Y !  EXIT
    THEN                                  ( data scrollable )
    SWAP SB.POS @                        ( scrollable pos )
    _SB-TRACK-H @ _SB-THUMB-H @ -       ( scrollable pos usable )
    ROT                                   ( pos usable scrollable )
    DUP 0= IF DROP DROP DROP 0 _SB-THUMB-Y ! EXIT THEN
    ROT ROT * SWAP /              ( thumb-y = pos*usable/scrollable )
    0 MAX _SB-THUMB-Y ! ;

: SB-RENDER  ( widget -- )
    RD-SETUP
    RD-H @ _SB-TRACK-H !
    RD-WG @ WG.DATA @ DUP 0= IF DROP EXIT THEN
    _SB-CALC
    \ Draw track
    CLR-SCROLL-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ Draw thumb
    CLR-SCROLL-FG
    RD-AX @ 1+
    RD-AY @ _SB-THUMB-Y @ +
    RD-W @ 2 -
    _SB-THUMB-H @
    FAST-RECT ;

\ Scrollbar has no key handler — parent (listbox) drives it.
: SB-KEY  ( key widget -- consumed? )  2DROP 0 ;

\ =====================================================================
\  Section 4: Scrollbar Factory
\ =====================================================================

\ SCROLLBAR ( x y w h parent -- widget )
: SCROLLBAR
    _F-PAR ! _F-H ! _F-W ! _F-Y ! _F-X !
    WGT-SCROLLBAR WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ _F-H @ WG-SET-RECT
    /SB-DATA ALLOCATE IF DROP 0 EXIT THEN
    DUP /SB-DATA 0 FILL
    OVER WG.DATA !
    ['] SB-RENDER OVER WG.RENDER !
    ['] SB-KEY OVER WG.ONKEY !
    _F-PAR @ OVER SWAP WG-ADD-CHILD ;

\ SB-UPDATE ( total visible pos scrollbar -- )
\   Update scrollbar state and mark dirty.
: SB-UPDATE  ( total visible pos scrollbar -- )
    DUP >R WG.DATA @ DUP 0= IF DROP R> DROP 2DROP EXIT THEN
    \ Stack: ( total visible pos data )
    SWAP OVER SB.POS !           \ ( total visible data )
    SWAP OVER SB.VISIBLE !       \ ( total data )
    SB.TOTAL !                    \ ( )
    R> WG-DIRTY ;

\ =====================================================================
\  Section 5: Listbox Data Layout
\ =====================================================================
\  Listbox data block (48 bytes):
\    +0   count       — number of items
\    +8   selected    — currently selected index
\    +16  scroll      — first visible item index
\    +24  vis-items   — number of visible items (computed from height)
\    +32  item-xt     — XT for rendering one item
\                       ( index x y w selected? -- )
\    +40  action-xt   — XT for Enter on selected item ( index -- )

: LB.COUNT    ;                  \ +0
: LB.SELECTED 8 + ;             \ +8
: LB.SCROLL  16 + ;             \ +16
: LB.VIS     24 + ;             \ +24
: LB.ITEM-XT 32 + ;             \ +32
: LB.ACTION  40 + ;             \ +40

48 CONSTANT /LB-DATA

\ =====================================================================
\  Section 6: Listbox Rendering
\ =====================================================================

\ ── Number-to-string (local, since we can't depend on editor) ──────
CREATE _SCR-NBUF 12 ALLOT
VARIABLE _SCR-NP

: _SCR-U>STR  ( u -- addr len )
    _SCR-NBUF 12 + _SCR-NP !
    BEGIN
        10 /MOD SWAP 48 +
        _SCR-NP @ 1- DUP _SCR-NP ! C!
        DUP 0=
    UNTIL DROP
    _SCR-NP @ _SCR-NBUF 12 + OVER - ;

\ Default item renderer — just draws item index as a number
: _LB-DEFAULT-ITEM  ( index x y w selected? -- )
    IF CLR-HILITE-FG ELSE CLR-EDIT-FG THEN
    >R DROP GFX-CY ! GFX-CX !
    _SCR-U>STR R> GFX-TYPE ;

VARIABLE _LBR-DATA
VARIABLE _LBR-SCROLL
VARIABLE _LBR-SEL
VARIABLE _LBR-ITRW              \ item width
VARIABLE _LBR-XT                \ render XT

: LB-RENDER  ( widget -- )
    RD-SETUP
    \ Background
    CLR-EDIT-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ Get listbox data
    RD-WG @ WG.DATA @ DUP 0= IF DROP EXIT THEN
    DUP _LBR-DATA !
    DUP LB.SCROLL @ _LBR-SCROLL !
    DUP LB.SELECTED @ _LBR-SEL !
    DUP LB.ITEM-XT @ _LBR-XT !
    LB.VIS @                      ( vis )
    \ Item width = widget width - scrollbar
    RD-W @ SB-WIDTH - _LBR-ITRW !
    \ Iterate visible items
    0 DO
        I _LBR-SCROLL @ +         ( item-idx )
        DUP _LBR-DATA @ LB.COUNT @ >= IF DROP LEAVE THEN
        \ Selection highlight
        DUP _LBR-SEL @ = IF
            CLR-HIGHLIGHT
            RD-AX @
            RD-AY @ I LINE-H * +
            _LBR-ITRW @
            LINE-H
            FAST-RECT
        THEN
        \ Call item render XT: ( index x y w selected? -- )
        RD-AX @ 4 +              ( idx x )
        RD-AY @ I LINE-H * + 2 + ( idx x y )
        _LBR-ITRW @ 8 -          ( idx x y w )
        3 PICK _LBR-SEL @ =      ( idx x y w sel? )
        _LBR-XT @ ?DUP IF EXECUTE ELSE 2DROP 2DROP DROP THEN
    LOOP ;

\ =====================================================================
\  Section 7: Listbox Scrollbar Sync
\ =====================================================================

VARIABLE _LBS-SB                 \ scrollbar child widget

\ _LB-SYNC-SB ( listbox -- )
\   Update the scrollbar child to reflect current listbox state.
: _LB-SYNC-SB  ( listbox -- )
    DUP WG.CHILD1 @             ( lb child )
    DUP 0= IF 2DROP EXIT THEN
    DUP WG.TYPE @ WGT-SCROLLBAR <> IF 2DROP EXIT THEN
    _LBS-SB !                    ( lb )
    WG.DATA @ DUP 0= IF DROP EXIT THEN   ( data )
    DUP LB.COUNT @              ( data count )
    OVER LB.VIS @               ( data count vis )
    ROT LB.SCROLL @             ( count vis scroll )
    _LBS-SB @ SB-UPDATE ;

\ =====================================================================
\  Section 8: Listbox Key Handling
\ =====================================================================

VARIABLE _LBK-DATA
VARIABLE _LBK-WG                \ widget pointer during key handling

\ _LBK-DONE ( -- -1 )
\   Mark listbox dirty, sync scrollbar, push -1 (consumed flag).
: _LBK-DONE  ( -- -1 )
    _LBK-WG @ DUP _LB-SYNC-SB WG-DIRTY -1 ;

\ _LB-ENSURE-VISIBLE ( lb-data -- )
\   Adjust scroll so that selected item is visible.
: _LB-ENSURE-VISIBLE  ( data -- )
    DUP LB.SELECTED @           ( data sel )
    OVER LB.SCROLL @            ( data sel scroll )
    2DUP > IF                    \ selected < scroll → scroll up
        DROP OVER LB.SCROLL !
    ELSE
        OVER LB.VIS @ + 1-      ( data sel last-vis )
        2DUP < IF                \ selected > last visible → scroll down
            DROP OVER LB.VIS @ - 1+ 0 MAX
            OVER LB.SCROLL !
        ELSE 2DROP
        THEN
    THEN DROP ;

: LB-KEY  ( key widget -- consumed? )
    DUP _LBK-WG !
    WG.DATA @ DUP 0= IF DROP DROP 0 EXIT THEN
    _LBK-DATA !
    \ Up arrow
    DUP K-UP = IF
        DROP
        _LBK-DATA @ LB.SELECTED @ 1- 0 MAX
        _LBK-DATA @ LB.SELECTED !
        _LBK-DATA @ _LB-ENSURE-VISIBLE
        _LBK-DONE EXIT
    THEN
    \ Down arrow
    DUP K-DOWN = IF
        DROP
        _LBK-DATA @ LB.SELECTED @ 1+
        _LBK-DATA @ LB.COUNT @ 1- 0 MAX MIN
        _LBK-DATA @ LB.SELECTED !
        _LBK-DATA @ _LB-ENSURE-VISIBLE
        _LBK-DONE EXIT
    THEN
    \ Page Up
    DUP K-PGUP = IF
        DROP
        _LBK-DATA @ LB.SELECTED @
        _LBK-DATA @ LB.VIS @ - 0 MAX
        _LBK-DATA @ LB.SELECTED !
        _LBK-DATA @ _LB-ENSURE-VISIBLE
        _LBK-DONE EXIT
    THEN
    \ Page Down
    DUP K-PGDN = IF
        DROP
        _LBK-DATA @ LB.SELECTED @
        _LBK-DATA @ LB.VIS @ +
        _LBK-DATA @ LB.COUNT @ 1- 0 MAX MIN
        _LBK-DATA @ LB.SELECTED !
        _LBK-DATA @ _LB-ENSURE-VISIBLE
        _LBK-DONE EXIT
    THEN
    \ Home
    DUP K-HOME = IF
        DROP
        0 _LBK-DATA @ LB.SELECTED !
        _LBK-DATA @ _LB-ENSURE-VISIBLE
        _LBK-DONE EXIT
    THEN
    \ End
    DUP K-END = IF
        DROP
        _LBK-DATA @ LB.COUNT @ 1- 0 MAX
        _LBK-DATA @ LB.SELECTED !
        _LBK-DATA @ _LB-ENSURE-VISIBLE
        _LBK-DONE EXIT
    THEN
    \ Enter — trigger action
    DUP K-ENTER = IF
        DROP
        _LBK-DATA @ LB.ACTION @ ?DUP IF
            _LBK-DATA @ LB.SELECTED @ SWAP EXECUTE
        THEN
        _LBK-DONE EXIT
    THEN
    DROP 0 ;

\ =====================================================================
\  Section 9: Listbox Factory
\ =====================================================================

\ LISTBOX ( x y w h parent -- widget )
\   Create a scrollable list widget.  Item count and render callback
\   must be set separately via LB-SET-ITEMS and LB-SET-RENDER.
: LISTBOX
    _F-PAR ! _F-H ! _F-W ! _F-Y ! _F-X !
    WGT-LISTBOX WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ _F-H @ WG-SET-RECT
    WG-MAKE-FOCUSABLE
    \ Allocate listbox data
    /LB-DATA ALLOCATE IF DROP 0 EXIT THEN
    DUP /LB-DATA 0 FILL
    ['] _LB-DEFAULT-ITEM OVER LB.ITEM-XT !
    OVER WG.DATA !
    \ Compute visible items from height
    _F-H @ LINE-H / OVER WG.DATA @ LB.VIS !
    \ Renderers
    ['] LB-RENDER OVER WG.RENDER !
    ['] LB-KEY OVER WG.ONKEY !
    _F-PAR @ OVER SWAP WG-ADD-CHILD
    \ Add scrollbar as child (right edge)
    DUP >R
    _F-W @ SB-WIDTH - 0 SB-WIDTH _F-H @ R@ SCROLLBAR DROP
    R> ;

\ LB-SET-ITEMS ( count widget -- )
\   Set the number of items in the listbox.  Resets selection to 0.
: LB-SET-ITEMS  ( count widget -- )
    DUP >R WG.DATA @ DUP 0= IF DROP DROP R> DROP EXIT THEN
    0 OVER LB.SELECTED !
    0 OVER LB.SCROLL !
    LB.COUNT !
    R> DUP _LB-SYNC-SB WG-DIRTY ;

\ LB-SET-RENDER ( xt widget -- )
\   Set the item rendering callback.
\   XT signature: ( index x y w selected? -- )
: LB-SET-RENDER  ( xt widget -- )
    WG.DATA @ DUP 0= IF DROP DROP EXIT THEN
    LB.ITEM-XT ! ;

\ LB-SET-ACTION ( xt widget -- )
\   Set the Enter/select action callback.
\   XT signature: ( index -- )
: LB-SET-ACTION  ( xt widget -- )
    WG.DATA @ DUP 0= IF DROP DROP EXIT THEN
    LB.ACTION ! ;

\ LB-SELECTED ( widget -- idx )
\   Get the currently selected item index.
: LB-SELECTED  ( widget -- idx )
    WG.DATA @ DUP 0= IF EXIT THEN LB.SELECTED @ ;

\ LB-SCROLL ( widget -- scroll )
\   Get the current scroll offset.
: LB-SCROLL  ( widget -- scroll )
    WG.DATA @ DUP 0= IF EXIT THEN LB.SCROLL @ ;

\ =====================================================================
\  Section 10: Smoke Test
\ =====================================================================

VARIABLE _ST-ROOT
VARIABLE _ST-SB
VARIABLE _ST-LB

\ Test item renderer
: _ST-ITEM-RENDER  ( index x y w selected? -- )
    IF CLR-HILITE-FG ELSE CLR-EDIT-FG THEN
    >R                           ( index x y w  R: color )
    DROP GFX-CY ! GFX-CX !      ( index  R: color )
    S" Item " R@ GFX-TYPE
    _SCR-U>STR R> GFX-TYPE ;

: KALKI-SCROLL-TEST  ( -- )
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    \ Root
    WGT-ROOT WG-ALLOC DUP _ST-ROOT !
    0 0 800 600 WG-SET-RECT DROP
    CLR-DESKTOP 0 0 800 600 FAST-RECT
    \ Scrollbar test
    700 20 SB-WIDTH 200 _ST-ROOT @ SCROLLBAR
    _ST-SB !
    50 20 5 _ST-SB @ SB-UPDATE
    _ST-SB @ WG.DATA @ SB.TOTAL @ 50 = IF ." sb-total=ok " ELSE ." sb-total=FAIL " THEN
    _ST-SB @ WG.DATA @ SB.VISIBLE @ 20 = IF ." sb-vis=ok " ELSE ." sb-vis=FAIL " THEN
    _ST-SB @ WG.DATA @ SB.POS @ 5 = IF ." sb-pos=ok " ELSE ." sb-pos=FAIL " THEN
    \ Listbox test
    50 50 400 200 _ST-ROOT @ LISTBOX
    DUP _ST-LB !
    25 OVER LB-SET-ITEMS
    ['] _ST-ITEM-RENDER OVER LB-SET-RENDER
    DROP
    \ Verify
    _ST-LB @ WG.DATA @ LB.COUNT @ 25 = IF ." lb-count=ok " ELSE ." lb-count=FAIL " THEN
    _ST-LB @ WG.DATA @ LB.VIS @ 0> IF ." lb-vis=ok " ELSE ." lb-vis=FAIL " THEN
    _ST-LB @ WG.DATA @ LB.SELECTED @ 0= IF ." lb-sel=ok " ELSE ." lb-sel=FAIL " THEN
    \ Test key handling — Down arrow
    K-DOWN _ST-LB @ LB-KEY DROP
    _ST-LB @ WG.DATA @ LB.SELECTED @ 1 = IF ." down=ok " ELSE ." down=FAIL " THEN
    \ Test key handling — Up arrow
    K-UP _ST-LB @ LB-KEY DROP
    _ST-LB @ WG.DATA @ LB.SELECTED @ 0= IF ." up=ok " ELSE ." up=FAIL " THEN
    \ Test scrolling — move down past visible area
    _ST-LB @ WG.DATA @ LB.VIS @ 0 DO
        K-DOWN _ST-LB @ LB-KEY DROP
    LOOP
    _ST-LB @ WG.DATA @ LB.SCROLL @ 0> IF ." scroll=ok " ELSE ." scroll=FAIL " THEN
    \ Render — use RENDER-TREE
    _ST-ROOT @ MARK-ALL-DIRTY
    _ST-ROOT @ RENDER-TREE
    FB-SWAP
    ." render=ok "
    CR
    \ Cleanup
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    _ST-ROOT @ WG-FREE-SUBTREE
    ." kalki-scroll test complete" CR ;
