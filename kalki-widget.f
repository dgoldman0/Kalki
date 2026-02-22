\ kalki-widget.f — Widget core: descriptors, tree, focus, render
\ =====================================================================
\  Phase 2 of the Kalki GUI framework.
\  Provides the generic widget system that all concrete widgets
\  (labels, buttons, panels, windows) are built on.
\
\  Depends on: kalki-gfx.f (clipping, drawing primitives)
\              kalki-color.f (theme colors)
\ =====================================================================
PROVIDED kalki-widget.f
REQUIRE kalki-gfx.f
REQUIRE kalki-color.f

\ =====================================================================
\  Section 1: Widget Struct — 96-byte descriptor
\ =====================================================================
\  All fields are cell-sized (8 bytes) for alignment on the 64-bit CPU.
\  Positions (X/Y) are relative to the parent widget.

96 CONSTANT /WIDGET              \ struct size in bytes

\ Field accessors: ( widget-addr -- field-addr )
: WG.TYPE     ;                  \ +0   widget type constant
: WG.FLAGS    8 + ;              \ +8   bit flags
: WG.X        16 + ;             \ +16  x relative to parent
: WG.Y        24 + ;             \ +24  y relative to parent
: WG.W        32 + ;             \ +32  width
: WG.H        40 + ;             \ +40  height
: WG.PARENT   48 + ;             \ +48  parent ptr (0=root)
: WG.CHILD1   56 + ;             \ +56  first child ptr (0=leaf)
: WG.NEXT     64 + ;             \ +64  next sibling ptr (0=last)
: WG.RENDER   72 + ;             \ +72  render XT
: WG.ONKEY    80 + ;             \ +80  key handler XT
: WG.DATA     88 + ;             \ +88  user data cell

\ =====================================================================
\  Section 2: Widget Type Constants
\ =====================================================================

0 CONSTANT WGT-NONE              \ uninitialized / sentinel
1 CONSTANT WGT-ROOT              \ root desktop container
2 CONSTANT WGT-LABEL             \ static text
3 CONSTANT WGT-BUTTON            \ clickable button
4 CONSTANT WGT-PANEL             \ grouping container with border
5 CONSTANT WGT-WINDOW            \ movable window with title bar
6 CONSTANT WGT-MENU              \ dropdown menu
7 CONSTANT WGT-EDITOR            \ text editor
8 CONSTANT WGT-HSEP              \ horizontal separator
9 CONSTANT WGT-LISTBOX           \ scrollable list
10 CONSTANT WGT-SCROLLBAR        \ scrollbar

\ =====================================================================
\  Section 3: Widget Flags
\ =====================================================================

1 CONSTANT WGF-DIRTY             \ needs repaint
2 CONSTANT WGF-VISIBLE           \ currently visible
4 CONSTANT WGF-FOCUSABLE         \ can receive keyboard focus
8 CONSTANT WGF-FOCUSED           \ currently focused (display hint)
16 CONSTANT WGF-DISABLED         \ grayed out, skipped by tab

\ Default flags for new widgets: visible + dirty
WGF-VISIBLE WGF-DIRTY OR CONSTANT WGF-DEFAULT

\ Flag helpers: ( widget -- )
: WG-SET-FLAG    ( widget flag -- )  OVER WG.FLAGS @ OR   SWAP WG.FLAGS ! ;
: WG-CLR-FLAG    ( widget flag -- )  INVERT OVER WG.FLAGS @ AND SWAP WG.FLAGS ! ;
: WG-FLAG?       ( widget flag -- f )  SWAP WG.FLAGS @ AND 0<> ;

: WG-DIRTY       ( widget -- )  WGF-DIRTY WG-SET-FLAG ;
: WG-DIRTY?      ( widget -- f )  WGF-DIRTY WG-FLAG? ;
: WG-CLEAN       ( widget -- )  WGF-DIRTY WG-CLR-FLAG ;
: WG-VISIBLE?    ( widget -- f )  WGF-VISIBLE WG-FLAG? ;
: WG-FOCUSABLE?  ( widget -- f )
    DUP WGF-FOCUSABLE WG-FLAG?
    SWAP WGF-DISABLED WG-FLAG? 0= AND ;

\ =====================================================================
\  Section 4: Default Handlers (no-ops)
\ =====================================================================
\  Used when a widget has no custom render or key handler.

: WG-RENDER-NOP  ( widget -- )  DROP ;
: WG-KEY-NOP     ( key widget -- consumed? )  2DROP 0 ;

\ =====================================================================
\  Section 5: Widget Allocation
\ =====================================================================
\  Uses KDOS ALLOCATE/FREE.  Each widget is exactly /WIDGET bytes.

: WG-ALLOC  ( type -- widget | 0 )
    /WIDGET ALLOCATE            ( type addr ior )
    IF  DROP 0  EXIT  THEN      \ allocation failed
    DUP /WIDGET 0 FILL          \ zero all fields
    TUCK WG.TYPE !              \ store type
    WGF-DEFAULT OVER WG.FLAGS ! \ set default flags
    ['] WG-RENDER-NOP OVER WG.RENDER !
    ['] WG-KEY-NOP OVER WG.ONKEY ! ;

: WG-FREE  ( widget -- )
    DUP 0= IF DROP EXIT THEN
    FREE ;

\ =====================================================================
\  Section 6: Widget Tree Operations
\ =====================================================================

\ WG-ADD-CHILD ( child parent -- )
\   Append child to end of parent's sibling list.
: WG-ADD-CHILD
    OVER SWAP                   ( child child parent )
    DUP ROT WG.PARENT !        ( child parent )  \ child.parent = parent
    DUP WG.CHILD1 @            ( child parent first )
    DUP 0= IF                  \ no children yet
        DROP WG.CHILD1 !       \ parent.child1 = child
        EXIT
    THEN
    \ Walk to last sibling
    NIP                         ( child first )
    BEGIN
        DUP WG.NEXT @          ( child cur next )
        DUP 0<>
    WHILE
        NIP                     ( child next )
    REPEAT
    DROP                        ( child last )
    WG.NEXT !                   \ last.next = child
;

\ WG-REMOVE ( widget -- )
\   Unlink from parent's child list.
: WG-REMOVE
    DUP WG.PARENT @            ( wg parent )
    DUP 0= IF 2DROP EXIT THEN  \ no parent, nothing to do
    \ Is widget the first child?
    2DUP WG.CHILD1 @           ( wg parent first )
    ROT TUCK = IF              ( parent wg )
        \ First child — set parent.child1 = widget.next
        DUP WG.NEXT @          ( parent wg next )
        ROT WG.CHILD1 !        ( wg )
        0 SWAP WG.PARENT !     \ clear parent link
        EXIT
    THEN
    \ Walk siblings to find predecessor
    DROP SWAP WG.CHILD1 @      ( wg first )
    BEGIN
        DUP WG.NEXT @          ( wg prev next )
        DUP 0= IF              \ not found (shouldn't happen)
            2DROP DROP EXIT
        THEN
        2 PICK = IF             ( wg prev )
            \ Found: prev.next = widget.next
            SWAP DUP WG.NEXT @ ( prev wg next )
            ROT WG.NEXT !      \ prev.next = next
            0 SWAP WG.PARENT ! \ clear parent link
            EXIT
        THEN
        NIP                     ( wg next — continue )
    AGAIN ;

\ WG-CHILD-COUNT ( widget -- n )
\   Count direct children.
: WG-CHILD-COUNT
    0 SWAP WG.CHILD1 @
    BEGIN DUP 0<> WHILE
        SWAP 1+ SWAP
        WG.NEXT @
    REPEAT DROP ;

\ =====================================================================
\  Section 7: Absolute Position
\ =====================================================================
\  Convert widget-relative coords to screen-absolute coords.

: WG-ABS-X  ( widget -- screen-x )
    0 SWAP
    BEGIN DUP 0<> WHILE
        DUP WG.X @ ROT + SWAP
        WG.PARENT @
    REPEAT DROP ;

: WG-ABS-Y  ( widget -- screen-y )
    0 SWAP
    BEGIN DUP 0<> WHILE
        DUP WG.Y @ ROT + SWAP
        WG.PARENT @
    REPEAT DROP ;

: WG-ABS-XY  ( widget -- screen-x screen-y )
    DUP WG-ABS-X SWAP WG-ABS-Y ;

\ =====================================================================
\  Section 8: Tree Traversal
\ =====================================================================
\  Depth-first walk: visit node, then children, then siblings.
\  The walker calls ( xt widget -- ) for each visible node.

\ WG-WALK ( xt root -- )
\   Depth-first traversal.  xt receives ( widget ) on each node.
: WG-WALK  ( xt widget -- )
    DUP 0= IF 2DROP EXIT THEN
    DUP WG-VISIBLE? 0= IF 2DROP EXIT THEN
    2DUP SWAP EXECUTE           ( xt widget )  \ visit self
    2DUP                         ( xt widget xt widget )
    WG.CHILD1 @ RECURSE         ( xt widget )  \ visit children
    WG.NEXT @ RECURSE ;          \ visit siblings

\ WG-WALK-REV ( xt root -- )
\   Walk siblings first, then children (reverse order for hit-testing).
: WG-WALK-REV  ( xt widget -- )
    DUP 0= IF 2DROP EXIT THEN
    DUP WG-VISIBLE? 0= IF 2DROP EXIT THEN
    2DUP WG.NEXT @ RECURSE      ( xt widget )  \ siblings first
    2DUP                         ( xt widget xt widget )
    WG.CHILD1 @ RECURSE         ( xt widget )  \ children
    SWAP EXECUTE ;              \ visit self last

\ =====================================================================
\  Section 9: Focus Management
\ =====================================================================

VARIABLE FOCUS-WIDGET           \ pointer to currently focused widget
0 FOCUS-WIDGET !

\ FOCUS ( widget -- )
\   Set focus to widget.  Marks old and new as dirty for repaint.
: FOCUS  ( widget -- )
    FOCUS-WIDGET @ DUP IF
        DUP WGF-FOCUSED WG-CLR-FLAG
        WG-DIRTY
    ELSE DROP THEN
    DUP FOCUS-WIDGET !
    DUP IF
        DUP WGF-FOCUSED WG-SET-FLAG
        WG-DIRTY
    ELSE DROP THEN ;

\ FOCUS-NEXT ( -- )
\   Move focus to next focusable sibling, wrapping around.
\   If no siblings, try children of parent.
: FOCUS-NEXT  ( -- )
    FOCUS-WIDGET @ DUP 0= IF DROP EXIT THEN
    \ Try next siblings first
    DUP WG.NEXT @               ( cur next )
    BEGIN DUP 0<> WHILE
        DUP WG-FOCUSABLE? IF
            NIP FOCUS EXIT
        THEN
        WG.NEXT @
    REPEAT DROP
    \ Wrap: go to parent's first child
    DUP WG.PARENT @             ( cur parent )
    DUP 0= IF 2DROP EXIT THEN
    WG.CHILD1 @                  ( cur first )
    BEGIN DUP 0<> WHILE
        DUP WG-FOCUSABLE? IF
            2DUP = IF           \ back to self, no other found
                2DROP EXIT
            THEN
            NIP FOCUS EXIT
        THEN
        WG.NEXT @
    REPEAT 2DROP ;

\ FOCUS-PREV ( -- )
\   Move focus to previous focusable sibling (walk from parent's first child).
: FOCUS-PREV  ( -- )
    FOCUS-WIDGET @ DUP 0= IF DROP EXIT THEN
    DUP WG.PARENT @             ( cur parent )
    DUP 0= IF 2DROP EXIT THEN
    WG.CHILD1 @                  ( cur first )
    0 ROT                        ( first prev=0 cur )
    \ Walk siblings, track last focusable before current
    2 PICK                       ( first prev cur walk=first )
    BEGIN DUP 0<> WHILE
        DUP 3 PICK = IF         \ found current
            DROP
            DUP 0<> IF          \ prev exists? focus it
                NIP NIP FOCUS EXIT
            THEN
            \ No prev — wrap to last focusable
            DROP                 ( first )
            0 SWAP               ( last=0 first )
            BEGIN DUP 0<> WHILE
                DUP WG-FOCUSABLE? IF
                    NIP DUP      ( last=this this )
                THEN
                WG.NEXT @
            REPEAT DROP
            DUP IF FOCUS ELSE DROP THEN
            EXIT
        THEN
        DUP WG-FOCUSABLE? IF
            NIP DUP              ( first prev=this cur this )
        THEN
        WG.NEXT @
    REPEAT
    2DROP 2DROP ;

\ FOCUS-PARENT ( -- )
\   Move focus to parent widget (Escape behavior).
: FOCUS-PARENT  ( -- )
    FOCUS-WIDGET @ DUP 0= IF DROP EXIT THEN
    WG.PARENT @
    DUP 0= IF DROP EXIT THEN
    DUP WG-FOCUSABLE? IF FOCUS ELSE DROP THEN ;

\ FOCUS-CHILD ( -- )
\   Move focus to first focusable child of current widget.
: FOCUS-CHILD  ( -- )
    FOCUS-WIDGET @ DUP 0= IF DROP EXIT THEN
    WG.CHILD1 @
    BEGIN DUP 0<> WHILE
        DUP WG-FOCUSABLE? IF FOCUS EXIT THEN
        WG.NEXT @
    REPEAT DROP ;

\ =====================================================================
\  Section 10: Rendering
\ =====================================================================
\  Renders the widget tree.  Sets up clipping for each widget based
\  on its parent's bounds, then calls the widget's render XT.

\ Internal: clip stack (4 levels deep, matching the nesting we expect)
4 CONSTANT MAX-CLIP-DEPTH
VARIABLE CLIP-SP               \ clip stack pointer
CREATE CLIP-STACK  MAX-CLIP-DEPTH 4 * CELLS ALLOT   \ 4 values per level

: CLIP-PUSH  ( -- )
    CLIP-SP @ MAX-CLIP-DEPTH >= IF EXIT THEN  \ overflow guard
    CLIP-STACK CLIP-SP @ 4 * CELLS +
    CLIP-X0 @ OVER !  CELL+
    CLIP-Y0 @ OVER !  CELL+
    CLIP-X1 @ OVER !  CELL+
    CLIP-Y1 @ SWAP !
    1 CLIP-SP +! ;

: CLIP-POP  ( -- )
    CLIP-SP @ 0 <= IF EXIT THEN  \ underflow guard
    -1 CLIP-SP +!
    CLIP-STACK CLIP-SP @ 4 * CELLS +
    DUP @ CLIP-X0 !  CELL+
    DUP @ CLIP-Y0 !  CELL+
    DUP @ CLIP-X1 !  CELL+
    @ CLIP-Y1 ! ;

\ WG-CLIP-TO ( widget -- )
\   Intersect current clip rect with widget's absolute bounds.
: WG-CLIP-TO  ( widget -- )
    DUP WG-ABS-X                ( wg ax )
    OVER WG-ABS-Y               ( wg ax ay )
    ROT DUP WG.W @              ( ax ay wg w )
    SWAP WG.H @                 ( ax ay w h )
    \ Compute widget's absolute bounds: ax ay ax+w ay+h
    2OVER                        ( ax ay w h ax ay )
    2 PICK +                     ( ax ay w h ax ay+h )
    SWAP 3 PICK +                ( ax ay w h ay+h ax+w )
    SWAP                         ( ax ay w h x2 y2 )
    2SWAP 2DROP                  ( ax ay x2 y2 )
    \ Intersect with current clip
    CLIP-Y1 @ MIN  ROT            ( ax x2 y2' ay )
    CLIP-Y0 @ MAX  ROT            ( ax y2' ay' x2 )
    CLIP-X1 @ MIN  ROT            ( y2' ay' x2' ax )
    CLIP-X0 @ MAX                  ( y2' ay' x2' x1' )
    \ Set new clip rect
    CLIP-X0 !  CLIP-X1 !  CLIP-Y0 !  CLIP-Y1 ! ;

\ RENDER-WIDGET ( widget -- )
\   Render a single widget (called during tree walk).
: RENDER-WIDGET  ( widget -- )
    DUP WG-DIRTY? 0= IF DROP EXIT THEN
    DUP WG-CLEAN
    DUP WG.RENDER @ EXECUTE ;

\ RENDER-TREE ( root -- )
\   Walk tree, render dirty widgets with clipping.
\   We do a manual recursive walk rather than WG-WALK so we can
\   push/pop clip rects at each level.
: RENDER-SUBTREE  ( widget -- )
    DUP 0= IF DROP EXIT THEN
    DUP WG-VISIBLE? 0= IF DROP EXIT THEN
    CLIP-PUSH
    DUP WG-CLIP-TO
    DUP RENDER-WIDGET
    \ Render children (NOT siblings -- the parent's loop handles that)
    WG.CHILD1 @
    BEGIN DUP 0<> WHILE
        DUP RECURSE
        WG.NEXT @
    REPEAT DROP
    CLIP-POP ;

: RENDER-TREE  ( root -- )
    0 CLIP-SP !
    CLIP-RESET
    RENDER-SUBTREE ;

\ MARK-ALL-DIRTY ( root -- )
\   Force full repaint.
: MARK-ALL-DIRTY  ( root -- )
    ['] WG-DIRTY SWAP WG-WALK ;

\ =====================================================================
\  Section 11: Key Dispatch
\ =====================================================================
\  Delivers a key to the focused widget.  If unhandled, bubbles up
\  to parent.  Returns true if consumed.

9 CONSTANT K-TAB
27 CONSTANT K-ESC

\ DELIVER-KEY ( key -- consumed? )
\   Send key to focused widget.  Try built-in navigation first.
: DELIVER-KEY  ( key -- consumed? )
    \ Built-in navigation: Tab, Shift-Tab (backtab), Escape
    DUP K-TAB = IF
        DROP FOCUS-NEXT -1 EXIT
    THEN
    DUP K-ESC = IF
        DROP FOCUS-PARENT -1 EXIT
    THEN
    \ Send to focused widget, bubble up on reject
    FOCUS-WIDGET @             ( key widget )
    BEGIN DUP 0<> WHILE
        2DUP DUP WG.ONKEY @ EXECUTE  ( key widget consumed? )
        IF 2DROP -1 EXIT THEN
        WG.PARENT @
    REPEAT
    2DROP 0 ;

\ =====================================================================
\  Section 12: Convenience Builders
\ =====================================================================
\  Helpers for creating widgets with common patterns.

\ WG-SET-RECT ( widget x y w h -- widget )
\   Set position and size.  Returns the widget for chaining.
: WG-SET-RECT  ( widget x y w h -- widget )
    4 PICK WG.H !
    3 PICK WG.W !
    2 PICK WG.Y !
    OVER WG.X ! ;

\ WG-SET-RENDER ( widget xt -- widget )
: WG-SET-RENDER  ( widget xt -- widget )
    OVER WG.RENDER ! ;

\ WG-SET-ONKEY ( widget xt -- widget )
: WG-SET-ONKEY  ( widget xt -- widget )
    OVER WG.ONKEY ! ;

\ WG-MAKE-FOCUSABLE ( widget -- widget )
: WG-MAKE-FOCUSABLE  ( widget -- widget )
    DUP WGF-FOCUSABLE WG-SET-FLAG ;

\ =====================================================================
\  Section 13: Smoke Test
\ =====================================================================

\ Test state variables
VARIABLE _T-ROOT  VARIABLE _T-P1
VARIABLE _T-P2    VARIABLE _T-BTN

: KALKI-WIDGET-TEST  ( -- )
    \ Create root widget
    WGT-ROOT WG-ALLOC DUP _T-ROOT !
    0 0 640 480 WG-SET-RECT DROP
    \ Panel 1
    WGT-PANEL WG-ALLOC DUP _T-P1 !
    10 10 200 100 WG-SET-RECT DROP
    _T-P1 @ _T-ROOT @ WG-ADD-CHILD
    \ Panel 2 (focusable)
    WGT-PANEL WG-ALLOC DUP _T-P2 !
    220 10 200 100 WG-SET-RECT
    WG-MAKE-FOCUSABLE DROP
    _T-P2 @ _T-ROOT @ WG-ADD-CHILD
    \ Button in Panel 1 (focusable)
    WGT-BUTTON WG-ALLOC DUP _T-BTN !
    5 5 80 20 WG-SET-RECT
    WG-MAKE-FOCUSABLE DROP
    _T-BTN @ _T-P1 @ WG-ADD-CHILD
    \ Report tree structure
    ." Widget tree:" CR
    ."   Root children: " _T-ROOT @ WG-CHILD-COUNT . CR
    ."   P1 children: " _T-P1 @ WG-CHILD-COUNT . CR
    ."   Button type: " _T-BTN @ WG.TYPE @ . CR
    ."   Button abs-X: " _T-BTN @ WG-ABS-X . CR
    ."   Button abs-Y: " _T-BTN @ WG-ABS-Y . CR
    \ Focus test
    _T-BTN @ FOCUS
    ."   Focused type: " FOCUS-WIDGET @ WG.TYPE @ . CR
    FOCUS-NEXT
    ."   After Tab: " FOCUS-WIDGET @ WG.TYPE @ . CR
    \ Clean up
    0 FOCUS-WIDGET !            \ clear before freeing widgets
    _T-BTN @ WG-FREE
    _T-P1 @ WG-FREE
    _T-P2 @ WG-FREE
    _T-ROOT @ WG-FREE
    ." kalki-widget test complete" CR ;

