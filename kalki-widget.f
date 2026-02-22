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

104 CONSTANT /WIDGET             \ struct size (13 cells × 8 bytes)

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
: WG.DTOR     96 + ;             \ +96  destructor XT (0=none)

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
\  Section 3b: Font Metrics
\ =====================================================================
\  Centralized font geometry.  Change here when switching fonts.
\  Current: built-in 8×8 bitmap font (graphics.f / BIOS).

8 CONSTANT FONT-W               \ glyph advance width (pixels)
8 CONSTANT FONT-H               \ glyph height / line height (pixels)

: TEXT-WIDTH  ( n-chars -- pixels )  FONT-W * ;

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

\ WG-DESTROY ( widget -- )
\   Full teardown: call destructor XT, free data block, free struct.
\   Safe to call with 0.
: WG-DESTROY  ( widget -- )
    DUP 0= IF DROP EXIT THEN
    DUP WG.DTOR @ DUP IF OVER SWAP EXECUTE ELSE DROP THEN
    DUP WG.DATA @ DUP IF FREE THEN DROP
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
    OVER                        ( wg parent wg )
    OVER WG.CHILD1 @            ( wg parent wg first )
    = IF                        ( wg parent )
        \ First child — set parent.child1 = widget.next
        OVER WG.NEXT @          ( wg parent next )
        OVER WG.CHILD1 !        ( wg parent )
        DROP                     ( wg )
        0 SWAP WG.PARENT !      \ clear parent link
        EXIT
    THEN
    \ Walk siblings to find predecessor
    DUP WG.CHILD1 @             ( wg parent first )
    NIP                          ( wg cur )
    BEGIN
        DUP WG.NEXT @           ( wg cur next )
        DUP 0= IF              \ not found (shouldn't happen)
            2DROP DROP EXIT
        THEN
        2 PICK = IF             ( wg cur )
            \ Found: cur.next = widget.next
            SWAP DUP WG.NEXT @  ( cur wg wnext )
            ROT WG.NEXT !       ( wg ) \ cur.next = wnext
            0 SWAP WG.PARENT !  \ clear parent link
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

\ WG-FREE-SUBTREE ( widget -- )
\   Post-order recursive free: destroy children first, then self.
\   Calls WG-DESTROY on each node (destructor + data + struct).
: WG-FREE-SUBTREE  ( widget -- )
    DUP 0= IF DROP EXIT THEN
    DUP WG.CHILD1 @
    BEGIN DUP 0<> WHILE
        DUP WG.NEXT @          ( child next )
        SWAP RECURSE            ( next )
    REPEAT DROP
    DUP WG-REMOVE
    WG-DESTROY ;

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

\ _FOCUS-ROOT ( widget -- root )
\   Walk parent chain to find the root widget.
: _FOCUS-ROOT  ( widget -- root )
    BEGIN DUP WG.PARENT @ DUP 0<> WHILE NIP REPEAT DROP ;

\ --- Global focus-next traversal (DFS pre-order) ---
VARIABLE _FN-FOUND              \ have we passed the current widget?
VARIABLE _FN-FIRST              \ first focusable in DFS order (for wrap)
VARIABLE _FN-RESULT             \ next focusable after current

: _FN-VISITOR  ( widget -- )
    DUP WG-FOCUSABLE? 0= IF DROP EXIT THEN
    _FN-RESULT @ 0<> IF DROP EXIT THEN
    _FN-FIRST @ 0= IF DUP _FN-FIRST ! THEN
    _FN-FOUND @ IF
        _FN-RESULT !
    ELSE
        FOCUS-WIDGET @ = IF -1 _FN-FOUND ! THEN
    THEN ;

\ FOCUS-NEXT ( -- )
\   Move focus to next focusable widget in global DFS pre-order.
\   Wraps to first focusable when end is reached.
: FOCUS-NEXT  ( -- )
    FOCUS-WIDGET @ DUP 0= IF DROP EXIT THEN
    0 _FN-FOUND !  0 _FN-FIRST !  0 _FN-RESULT !
    _FOCUS-ROOT
    ['] _FN-VISITOR SWAP WG-WALK
    _FN-RESULT @ DUP 0= IF DROP _FN-FIRST @ THEN
    DUP IF FOCUS ELSE DROP THEN ;

\ --- Global focus-prev traversal (DFS pre-order, reversed) ---
VARIABLE _FP-PREV               \ last focusable seen before current
VARIABLE _FP-LAST               \ last focusable in entire DFS
VARIABLE _FP-FOUND              \ have we seen the current widget?

: _FP-VISITOR  ( widget -- )
    DUP WG-FOCUSABLE? 0= IF DROP EXIT THEN
    DUP _FP-LAST !
    _FP-FOUND @ IF DROP EXIT THEN
    DUP FOCUS-WIDGET @ = IF
        -1 _FP-FOUND !
        DROP
    ELSE
        _FP-PREV !
    THEN ;

\ FOCUS-PREV ( -- )
\   Move focus to previous focusable widget in global DFS pre-order.
\   Wraps to last focusable when beginning is reached.
: FOCUS-PREV  ( -- )
    FOCUS-WIDGET @ DUP 0= IF DROP EXIT THEN
    0 _FP-PREV !  0 _FP-LAST !  0 _FP-FOUND !
    _FOCUS-ROOT
    ['] _FP-VISITOR SWAP WG-WALK
    _FP-PREV @ DUP 0= IF DROP _FP-LAST @ THEN
    DUP IF FOCUS ELSE DROP THEN ;

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

\ Internal: clip stack (16 levels deep)
16 CONSTANT MAX-CLIP-DEPTH
VARIABLE CLIP-SP               \ clip stack pointer
CREATE CLIP-STACK  MAX-CLIP-DEPTH 4 * CELLS ALLOT   \ 4 values per level

: CLIP-PUSH  ( -- )
    CLIP-SP @ MAX-CLIP-DEPTH >= IF
        ." CLIP OVERFLOW" CR EXIT
    THEN  \ overflow guard
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

\ Scratch for clip intersection (avoids error-prone stack shuffling)
VARIABLE _CL-AX   VARIABLE _CL-AY

\ WG-CLIP-TO ( widget -- )
\   Intersect current clip rect with widget's absolute bounds.
\   x0' = max(ax, CLIP-X0)   y0' = max(ay, CLIP-Y0)
\   x1' = min(ax+w, CLIP-X1) y1' = min(ay+h, CLIP-Y1)
: WG-CLIP-TO  ( widget -- )
    DUP WG-ABS-X _CL-AX !
    DUP WG-ABS-Y _CL-AY !
    DUP WG.W @ _CL-AX @ +      ( widget x2 )
    CLIP-X1 @ MIN CLIP-X1 !
    WG.H @ _CL-AY @ +          ( y2 )
    CLIP-Y1 @ MIN CLIP-Y1 !
    _CL-AX @ CLIP-X0 @ MAX CLIP-X0 !
    _CL-AY @ CLIP-Y0 @ MAX CLIP-Y0 ! ;

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
\ Invalidation policy: parent-dirty cascades to children.
\   When a widget renders (was dirty), all direct children are
\   forced dirty so they repaint on top of the fresh background.
\   WG-DIRTY marks only the target widget; no ancestor bubbling.
: RENDER-SUBTREE  ( widget -- )
    DUP 0= IF DROP EXIT THEN
    DUP WG-VISIBLE? 0= IF DROP EXIT THEN
    CLIP-PUSH
    DUP WG-CLIP-TO
    DUP WG-DIRTY?              ( widget dirty? )
    IF
        DUP WG-CLEAN
        DUP DUP WG.RENDER @ EXECUTE
        \  ^^^ extra DUP: WG.RENDER @ uses one copy for field access,
        \      EXECUTE's render fn consumes another; keep original below
        -1                      ( widget -1 )
    ELSE 0 THEN                 ( widget cascade? )
    SWAP WG.CHILD1 @            ( cascade? child )
    BEGIN DUP 0<> WHILE
        OVER IF DUP WGF-DIRTY WG-SET-FLAG THEN
        DUP RECURSE
        WG.NEXT @
    REPEAT 2DROP
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

\ WG-SET-DTOR ( widget xt -- widget )
: WG-SET-DTOR  ( widget xt -- widget )
    OVER WG.DTOR ! ;

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
    0 FOCUS-WIDGET !
    _T-ROOT @ WG-FREE-SUBTREE
    ." kalki-widget test complete" CR ;

