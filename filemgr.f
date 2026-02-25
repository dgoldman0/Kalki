\ filemgr.f — File Manager Application (per-process)
\ =====================================================================
\  Loaded per-process via REQUIRE inside APP-LAUNCH.
\  Creates a file listing window with keyboard navigation.
\
\  Called by: _DK-LAUNCH-FM (in kalki-desktop.f) as entry-xt for
\             APP-LAUNCH.  Runs in the process context — all
\             VARIABLEs and CREATEd buffers live in the process's
\             dict zone.
\
\  Provides: file listing window with Up/Down/Enter navigation.
\  TODO Stage 3: Enter launches editor app via APP-LAUNCH.
\ =====================================================================

PROVIDED filemgr.f

\ =====================================================================
\  Section 1: File List Storage
\ =====================================================================

16 CONSTANT FM-MAX-FILES
VARIABLE FM-COUNT
CREATE FM-NAMES FM-MAX-FILES 24 * ALLOT
CREATE FM-INDICES FM-MAX-FILES CELLS ALLOT
VARIABLE FM-SELECTED  0 FM-SELECTED !

\ Per-process state
VARIABLE _FMG-WIN
VARIABLE _FMG-LIST

\ =====================================================================
\  Section 2: File Scanning
\ =====================================================================

: _FM-SCAN  ( -- )
    0 FM-COUNT !
    FS-MAX-FILES 0 DO
        FM-COUNT @ FM-MAX-FILES >= IF LEAVE THEN
        I DIRENT DUP C@ 0<> IF
            FM-NAMES FM-COUNT @ 24 * +
            OVER SWAP 24 CMOVE
            DROP
            I FM-INDICES FM-COUNT @ CELLS + !
            1 FM-COUNT +!
        ELSE DROP THEN
    LOOP ;

\ =====================================================================
\  Section 3: Filename Length
\ =====================================================================

: _FM-ITEM-LEN  ( idx -- n )
    24 * FM-NAMES +
    0
    BEGIN
        OVER OVER + C@ 0<>
        OVER 23 < AND
    WHILE
        1+
    REPEAT
    NIP ;

\ =====================================================================
\  Section 4: Rendering
\ =====================================================================

: _FMG-LIST-RENDER  ( widget -- )
    RD-SETUP
    CLR-EDIT-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    FM-COUNT @ 0 DO
        I FM-SELECTED @ = IF
            CLR-HIGHLIGHT
            RD-AX @
            RD-AY @ I LINE-H * + 2 +
            RD-W @
            LINE-H
            FAST-RECT
        THEN
        RD-AX @ 8 + GFX-CX !
        RD-AY @ I LINE-H * + 3 + GFX-CY !
        I FM-SELECTED @ = IF CLR-HILITE-FG ELSE CLR-EDIT-FG THEN
        FM-NAMES I 24 * + I _FM-ITEM-LEN
        ROT GFX-TYPE
    LOOP ;

\ =====================================================================
\  Section 5: Key Handling
\ =====================================================================

VARIABLE _FMK-KEY

: _FMG-LIST-KEY  ( key widget -- consumed? )
    DROP _FMK-KEY !
    _FMK-KEY @ K-UP = IF
        FM-SELECTED @ 1- 0 MAX FM-SELECTED !
        _FMG-LIST @ WG-DIRTY -1 EXIT
    THEN
    _FMK-KEY @ K-DOWN = IF
        FM-SELECTED @ 1+ FM-COUNT @ 1- 0 MAX MIN FM-SELECTED !
        _FMG-LIST @ WG-DIRTY -1 EXIT
    THEN
    _FMK-KEY @ K-ENTER = IF
        \ TODO Stage 3: APP-LAUNCH editor for selected file
        -1 EXIT
    THEN
    0 ;

\ =====================================================================
\  Section 6: App-Level Key Handler
\ =====================================================================
\
\  Called by APP-DELIVER.  Forwards keys to the focused widget.

: _FMG-KEY  ( key -- consumed? )
    FOCUS-WIDGET @ ?DUP IF
        DUP WG.ONKEY @ ?DUP IF
            EXECUTE EXIT
        THEN
        DROP
    THEN
    DROP 0 ;

\ =====================================================================
\  Section 7: Build File Manager UI (runs at load time)
\ =====================================================================
\  NOTE: This section runs in interpreted mode (top-level during
\  REQUIRE inside APP-LAUNCH).  Use ' (tick) not ['] (bracket-tick)
\  because ['] is compile-only and produces garbage in interp mode.

_FM-SCAN

40 20 720 WORKSPACE-H 40 -
S" Files" DK-ROOT @ WINDOW
_FMG-WIN !

WGT-PANEL WG-ALLOC DUP _FMG-LIST !
WIN-CLIENT-X WIN-CLIENT-Y
720 WIN-CLIENT-X 2* -
WORKSPACE-H 40 - WIN-CLIENT-Y -
WG-SET-RECT
WG-MAKE-FOCUSABLE DROP

' _FMG-LIST-RENDER _FMG-LIST @ WG.RENDER !
' _FMG-LIST-KEY _FMG-LIST @ WG.ONKEY !
_FMG-LIST @ _FMG-WIN @ WG-ADD-CHILD

_FMG-LIST @ FOCUS

_FMG-WIN @ APP-SET-ROOT
' _FMG-KEY APP-SET-ONKEY

." filemgr loaded" CR
