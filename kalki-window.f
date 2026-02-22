\ kalki-window.f — Phase 4: Window, Window Manager, Dialogs
\ =====================================================================
\  Windowed containers with title bars, a simple window manager for
\  tracking and cycling between windows, and modal dialog boxes.
\
\  Provides:
\    WINDOW          ( x y w h title-addr title-len parent -- widget )
\    WIN-REGISTER / WIN-UNREGISTER  ( window -- )
\    WIN-CYCLE       ( -- )           cycle active window (Ctrl-N)
\    WIN-DELIVER-KEY ( key -- consumed? )
\    DIALOG          ( w h title-addr title-len -- widget )
\    MSG-BOX         ( text-addr text-len title-addr title-len -- )
\    CONFIRM         ( text-addr text-len -- flag )
\
\  Window children must be positioned at y >= WIN-CLIENT-Y (22) to
\  avoid overlapping the title bar.  WIN-CLIENT-X (1) for left inset.
\
\  Depends on: kalki-basic.f (label, button, bevel helpers)
\ =====================================================================

PROVIDED kalki-window.f
REQUIRE kalki-basic.f

\ =====================================================================
\  Section 1: Constants & Layout
\ =====================================================================

20 CONSTANT TITLE-BAR-H         \ title bar height in pixels
1  CONSTANT WIN-BORDER          \ border width in pixels

\ Client area origin relative to window top-left:
\   y = border (1) + title bar (20) + 1 = 22
\   x = border (1)
WIN-BORDER TITLE-BAR-H + 1+ CONSTANT WIN-CLIENT-Y
WIN-BORDER CONSTANT WIN-CLIENT-X

24 CONSTANT /WINDOW-DATA        \ text-addr(8) + text-len(8) + close-xt(8)
16 CONSTANT MAX-WINDOWS         \ max windows in manager
14 CONSTANT K-WINCYCLE          \ Ctrl-N — cycle active window

\ =====================================================================
\  Section 2: Window Manager State
\ =====================================================================

CREATE WIN-TABLE  MAX-WINDOWS CELLS ALLOT
VARIABLE WIN-COUNT    0 WIN-COUNT !
VARIABLE WIN-ACTIVE  -1 WIN-ACTIVE !   \ 0-based index, -1 = none

\ =====================================================================
\  Section 3: Window Manager Operations
\ =====================================================================

\ WIN-GET-ACTIVE ( -- window | 0 )
: WIN-GET-ACTIVE
    WIN-ACTIVE @ DUP 0< IF DROP 0 EXIT THEN
    DUP WIN-COUNT @ >= IF DROP 0 EXIT THEN
    CELLS WIN-TABLE + @ ;

\ WIN-REGISTER ( window -- )
: WIN-REGISTER
    WIN-COUNT @ MAX-WINDOWS >= IF DROP EXIT THEN
    WIN-TABLE WIN-COUNT @ CELLS + !
    1 WIN-COUNT +!
    \ Auto-activate if this is the first window
    WIN-COUNT @ 1 = IF 0 WIN-ACTIVE ! THEN ;

\ WIN-UNREGISTER ( window -- )
VARIABLE _WU-IDX
: WIN-UNREGISTER
    -1 _WU-IDX !
    WIN-COUNT @ 0 DO
        WIN-TABLE I CELLS + @ OVER = IF I _WU-IDX ! THEN
    LOOP
    DROP
    _WU-IDX @ 0< IF EXIT THEN
    \ Shift remaining entries down
    _WU-IDX @
    BEGIN DUP WIN-COUNT @ 1- < WHILE
        DUP 1+ CELLS WIN-TABLE + @
        OVER CELLS WIN-TABLE + !
        1+
    REPEAT DROP
    -1 WIN-COUNT +!
    \ Adjust active index
    WIN-ACTIVE @ _WU-IDX @ > IF -1 WIN-ACTIVE +! THEN
    WIN-ACTIVE @ WIN-COUNT @ >= IF
        WIN-COUNT @ 1- 0 MAX WIN-ACTIVE !
    THEN
    WIN-COUNT @ 0= IF -1 WIN-ACTIVE ! THEN ;

\ _FOCUS-FIRST ( widget -- )
\   DFS walk to find and focus the first focusable descendant.
VARIABLE _FF-RESULT
: _FF-VISITOR  ( widget -- )
    _FF-RESULT @ IF DROP EXIT THEN
    DUP WG-FOCUSABLE? IF _FF-RESULT ! ELSE DROP THEN ;
: _FOCUS-FIRST  ( widget -- )
    0 _FF-RESULT !
    ['] _FF-VISITOR SWAP WG-WALK
    _FF-RESULT @ DUP IF FOCUS ELSE DROP THEN ;

\ WIN-ACTIVATE ( index -- )
\   Switch active window.  Marks old/new dirty, focuses first child.
: WIN-ACTIVATE
    DUP WIN-ACTIVE @ = IF DROP EXIT THEN
    WIN-GET-ACTIVE DUP IF WG-DIRTY ELSE DROP THEN
    WIN-ACTIVE !
    WIN-GET-ACTIVE DUP IF
        DUP WG-DIRTY
        _FOCUS-FIRST
    ELSE DROP THEN ;

\ WIN-CYCLE ( -- )
\   Cycle to next registered window.
: WIN-CYCLE
    WIN-COUNT @ 2 < IF EXIT THEN
    WIN-ACTIVE @ 1+ WIN-COUNT @ MOD WIN-ACTIVATE ;

\ =====================================================================
\  Section 4: Window Rendering
\ =====================================================================

: WINDOW-RENDER  ( widget -- )
    RD-SETUP
    \ 1-pixel border
    CLR-WIN-BORDER RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-BOX
    \ Title bar background — active or inactive
    RD-WG @ WIN-GET-ACTIVE = IF CLR-TITLE-BG ELSE CLR-TITLE-INACTIVE THEN
    RD-AX @ WIN-BORDER +
    RD-AY @ WIN-BORDER +
    RD-W @ WIN-BORDER 2* -
    TITLE-BAR-H
    FAST-RECT
    \ Title text (vertically centered in title bar, left-padded)
    RD-AX @ WIN-BORDER + FONT-W + GFX-CX !
    RD-AY @ WIN-BORDER + TITLE-BAR-H FONT-H - 2 / + GFX-CY !
    RD-WG @ WG.DATA @
    DUP WD.TEXT @ SWAP WD.TLEN @
    CLR-TITLE-FG GFX-TYPE
    \ Close glyph "x" at right edge (decorative — shown if close-xt set)
    RD-WG @ WG.DATA @ WD.ACTION @ IF
        RD-AX @ RD-W @ + WIN-BORDER - FONT-W - 4 - GFX-CX !
        RD-AY @ WIN-BORDER + TITLE-BAR-H FONT-H - 2 / + GFX-CY !
        S" x" CLR-TITLE-FG GFX-TYPE
    THEN ;
    \ Client area is NOT filled here — children paint their own
    \ backgrounds.  This avoids a ~436K pixel fill that would be
    \ immediately overwritten by the editor or other child widgets.

\ Window key handler — stub; children handle their own keys.
: WINDOW-KEY  ( key widget -- consumed? )
    2DROP 0 ;

\ =====================================================================
\  Section 5: Window Factory
\ =====================================================================

\ WINDOW ( x y w h title-addr title-len parent -- widget )
\   Create a window widget with title bar.  Auto-registers with
\   the window manager.  Children should start at y >= WIN-CLIENT-Y.
: WINDOW
    _F-PAR ! _F-TL ! _F-TA ! _F-H ! _F-W ! _F-Y ! _F-X !
    WGT-WINDOW WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ _F-H @ WG-SET-RECT
    \ Allocate window data (text + close-xt, same layout as button data)
    /WINDOW-DATA ALLOCATE IF DROP 0 EXIT THEN
    _F-TA @ OVER WD.TEXT !
    _F-TL @ OVER WD.TLEN !
    0 OVER WD.ACTION !                  \ no close action by default
    OVER WG.DATA !
    ['] WINDOW-RENDER OVER WG.RENDER !
    ['] WINDOW-KEY OVER WG.ONKEY !
    _F-PAR @ OVER SWAP WG-ADD-CHILD
    DUP WIN-REGISTER ;

\ WIN-SET-CLOSE ( xt window -- )
\   Set the close action and display the close glyph.
: WIN-SET-CLOSE
    WG.DATA @ WD.ACTION ! ;

\ =====================================================================
\  Section 6: Window-Aware Key Dispatch
\ =====================================================================
\  Use WIN-DELIVER-KEY instead of DELIVER-KEY to support Ctrl-N
\  window cycling alongside normal Tab/Esc/key dispatch.

: WIN-DELIVER-KEY  ( key -- consumed? )
    DUP K-WINCYCLE = IF
        DROP WIN-CYCLE -1 EXIT
    THEN
    DELIVER-KEY ;

\ =====================================================================
\  Section 7: Dialog Boxes
\ =====================================================================
\  Modal dialogs render over the current scene and block until
\  dismissed.  The front buffer is saved to dynamically allocated
\  memory and restored when the dialog closes.

VARIABLE _DIALOG-DONE
VARIABLE _DIALOG-RESULT
VARIABLE _DLG-WIN
VARIABLE _DLG-BTN
VARIABLE _DLG-SAVE-ACTIVE
VARIABLE _DLG-SAVE-BUF   0 _DLG-SAVE-BUF !

\ Frame size in bytes (stride × height)
: _FB-FRAME-BYTES  ( -- n )  GFX-STR @ GFX-H @ * ;

\ Save current front buffer to allocated memory.
: _DLG-SAVE-SCENE  ( -- )
    _FB-FRAME-BYTES ALLOCATE IF
        DROP 0 _DLG-SAVE-BUF !  EXIT
    THEN
    _DLG-SAVE-BUF !
    FB-FRONT @ _DLG-SAVE-BUF @ _FB-FRAME-BYTES CMOVE ;

\ _DLG-OPEN ( dialog -- )
\   Save scene, register dialog, activate, render.
: _DLG-OPEN  ( dialog -- )
    _DLG-SAVE-SCENE
    WIN-ACTIVE @ _DLG-SAVE-ACTIVE !
    DUP WIN-REGISTER
    WIN-COUNT @ 1- WIN-ACTIVATE
    \ Copy saved scene to back buffer, then render dialog on top
    _DLG-SAVE-BUF @ IF
        _DLG-SAVE-BUF @ FB-BACK @ _FB-FRAME-BYTES CMOVE
    THEN
    DUP MARK-ALL-DIRTY
    DUP RENDER-TREE
    FB-SWAP ;

\ _DLG-CLOSE ( dialog -- )
\   Unregister, free subtree, restore saved scene.
: _DLG-CLOSE  ( dialog -- )
    0 FOCUS-WIDGET !
    DUP WIN-UNREGISTER
    _DLG-SAVE-ACTIVE @ DUP 0< IF DROP ELSE
        DUP WIN-COUNT @ < IF WIN-ACTIVE ! ELSE DROP THEN
    THEN
    WG-FREE-SUBTREE
    \ Restore: copy saved scene → back buffer, swap
    _DLG-SAVE-BUF @ DUP IF
        DUP FB-BACK @ _FB-FRAME-BYTES CMOVE
        FREE DROP
        0 _DLG-SAVE-BUF !
        FB-SWAP
    ELSE DROP THEN ;

\ _DLG-REPAINT ( dialog -- )
\   Re-render dialog after focus/state changes.
\   Copies saved scene to back buffer first for a clean background.
: _DLG-REPAINT  ( dialog -- )
    _DLG-SAVE-BUF @ IF
        _DLG-SAVE-BUF @ FB-BACK @ _FB-FRAME-BYTES CMOVE
    THEN
    DUP MARK-ALL-DIRTY
    DUP RENDER-TREE
    FB-SWAP ;

\ DIALOG ( w h title-addr title-len -- widget )
\   Create a centered dialog window (no parent, standalone root).
: DIALOG
    _F-TL ! _F-TA ! _F-H ! _F-W !
    GFX-W @ _F-W @ - 2 / _F-X !
    GFX-H @ _F-H @ - 2 / _F-Y !
    WGT-WINDOW WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ _F-H @ WG-SET-RECT
    /WINDOW-DATA ALLOCATE IF DROP 0 EXIT THEN
    _F-TA @ OVER WD.TEXT !
    _F-TL @ OVER WD.TLEN !
    0 OVER WD.ACTION !
    OVER WG.DATA !
    ['] WINDOW-RENDER OVER WG.RENDER ! ;

\ --- MSG-BOX scratch ---
VARIABLE _MB-TEXT    VARIABLE _MB-TLEN
VARIABLE _MB-TITLE  VARIABLE _MB-TITLEN

\ MSG-BOX ( text-addr text-len title-addr title-len -- )
\   Show a modal OK dialog.  Blocks until Enter or Esc.
: MSG-BOX
    _MB-TITLEN ! _MB-TITLE !
    _MB-TLEN ! _MB-TEXT !
    \ Compute dialog size
    _MB-TLEN @ TEXT-WIDTH 40 + 200 MAX   ( width )
    85                                    ( width height )
    _MB-TITLE @ _MB-TITLEN @
    DIALOG
    DUP 0= IF EXIT THEN
    DUP _DLG-WIN !
    \ Text label inside client area
    WIN-CLIENT-X 10 + WIN-CLIENT-Y 8 +
    _MB-TEXT @ _MB-TLEN @ _DLG-WIN @ LABEL DROP
    \ OK button — centered horizontally
    _DLG-WIN @ WG.W @ 60 - 2 /
    WIN-CLIENT-Y 30 +
    60 20 S" OK" ['] WG-RENDER-NOP _DLG-WIN @ BUTTON
    _DLG-BTN !
    _DLG-BTN @ FOCUS
    \ Open dialog (save scene, register, render)
    _DLG-WIN @ _DLG-OPEN
    \ Modal key loop — only Enter and Esc dismiss
    0 _DIALOG-DONE !
    BEGIN
        KEY
        DUP K-ENTER = OVER K-ESC = OR IF
            DROP -1 _DIALOG-DONE !
        ELSE DROP THEN
        _DIALOG-DONE @
    UNTIL
    \ Close and restore scene
    _DLG-WIN @ _DLG-CLOSE ;

\ --- CONFIRM scratch ---
VARIABLE _CONF-YES   VARIABLE _CONF-NO

\ CONFIRM ( text-addr text-len -- flag )
\   Show a modal Yes/No dialog.  Returns TRUE (-1) for Yes, FALSE (0)
\   for No.  Tab toggles between buttons.  Esc = No.
: CONFIRM
    _MB-TLEN ! _MB-TEXT !
    \ Compute dialog size
    _MB-TLEN @ TEXT-WIDTH 40 + 220 MAX   ( width )
    85                                    ( width height )
    S" Confirm"
    DIALOG
    DUP 0= IF EXIT THEN
    DUP _DLG-WIN !
    \ Text label
    WIN-CLIENT-X 10 + WIN-CLIENT-Y 8 +
    _MB-TEXT @ _MB-TLEN @ _DLG-WIN @ LABEL DROP
    \ Yes button
    _DLG-WIN @ WG.W @ 130 - 2 /   ( yes-x )
    WIN-CLIENT-Y 30 +
    60 20 S" Yes" ['] WG-RENDER-NOP _DLG-WIN @ BUTTON
    _CONF-YES !
    \ No button
    _DLG-WIN @ WG.W @ 130 - 2 / 70 +  ( no-x )
    WIN-CLIENT-Y 30 +
    60 20 S" No" ['] WG-RENDER-NOP _DLG-WIN @ BUTTON
    _CONF-NO !
    \ Focus Yes by default
    _CONF-YES @ FOCUS
    _DLG-WIN @ _DLG-OPEN
    \ Modal loop
    0 _DIALOG-DONE !
    0 _DIALOG-RESULT !
    BEGIN
        KEY
        DUP K-ENTER = OVER K-SPACE = OR IF
            DROP
            FOCUS-WIDGET @ _CONF-YES @ = IF -1 ELSE 0 THEN
            _DIALOG-RESULT !
            -1 _DIALOG-DONE !
        ELSE DUP K-ESC = IF
            DROP 0 _DIALOG-RESULT ! -1 _DIALOG-DONE !
        ELSE DUP K-TAB = IF
            DROP
            FOCUS-WIDGET @ _CONF-YES @ = IF
                _CONF-NO @ FOCUS
            ELSE
                _CONF-YES @ FOCUS
            THEN
            _DLG-WIN @ _DLG-REPAINT
        ELSE DROP THEN THEN THEN
        _DIALOG-DONE @
    UNTIL
    _DIALOG-RESULT @
    _DLG-WIN @ _DLG-CLOSE ;

\ =====================================================================
\  Section 8: Smoke Test
\ =====================================================================

VARIABLE _WT-ROOT
VARIABLE _WT-WIN1   VARIABLE _WT-WIN2

: KALKI-WINDOW-TEST  ( -- )
    \ Reset window manager state
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    \ Root widget (desktop)
    WGT-ROOT WG-ALLOC DUP _WT-ROOT !
    0 0 800 600 WG-SET-RECT DROP
    CLR-DESKTOP 0 0 800 600 FAST-RECT
    \ Window 1: left side
    20 30 360 250 S" Editor" _WT-ROOT @ WINDOW
    _WT-WIN1 !
    \ Content in window 1
    WIN-CLIENT-X 8 + WIN-CLIENT-Y 8 +
    S" Document content here" _WT-WIN1 @ LABEL DROP
    WIN-CLIENT-X 8 + WIN-CLIENT-Y 28 +
    100 20 S" Save" ['] WG-RENDER-NOP _WT-WIN1 @ BUTTON DROP
    \ Window 2: right side
    420 30 360 250 S" Browser" _WT-ROOT @ WINDOW
    _WT-WIN2 !
    \ Content in window 2
    WIN-CLIENT-X 8 + WIN-CLIENT-Y 8 +
    S" Web page content" _WT-WIN2 @ LABEL DROP
    WIN-CLIENT-X 8 + WIN-CLIENT-Y 28 +
    100 20 S" Reload" ['] WG-RENDER-NOP _WT-WIN2 @ BUTTON DROP
    \ Render everything
    _WT-ROOT @ MARK-ALL-DIRTY
    _WT-ROOT @ RENDER-TREE
    FB-SWAP
    \ Report state
    ." Windows registered: " WIN-COUNT @ . CR
    ." Active window: " WIN-ACTIVE @ . CR
    ." Win1 is active: "
        _WT-WIN1 @ WIN-GET-ACTIVE = IF ." yes" ELSE ." no" THEN CR
    \ Cycle to window 2
    WIN-CYCLE
    ." After cycle, active: " WIN-ACTIVE @ . CR
    ." Win2 is active: "
        _WT-WIN2 @ WIN-GET-ACTIVE = IF ." yes" ELSE ." no" THEN CR
    \ Re-render to show updated title bars
    _WT-ROOT @ MARK-ALL-DIRTY
    _WT-ROOT @ RENDER-TREE
    FB-SWAP
    \ Test DIALOG structure (non-blocking — no KEY loop)
    ." Dialog test: "
    300 85 S" Test" DIALOG
    DUP 0<> IF
        DUP WG.TYPE @ WGT-WINDOW = IF ." type=ok " THEN
        DUP WG.W @ 300 = IF ." size=ok " THEN
        \ Centered position check
        DUP WG.X @ 250 = IF ." pos=ok " THEN
        DUP WIN-UNREGISTER
        WG-FREE-SUBTREE
    ELSE DROP ." ALLOC-FAIL" THEN
    CR
    \ Cleanup
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    _WT-ROOT @ WG-FREE-SUBTREE
    ." kalki-window test complete" CR ;
