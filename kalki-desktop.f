\ kalki-desktop.f — Phase 8: Desktop Shell
\ =====================================================================
\  Full desktop experience: root surface, taskbar with clock,
\  file manager, integrated editor launching.
\
\  Provides:
\    KALKI         ( -- )          enter the desktop environment
\    DESKTOP-ROOT                  root widget for the desktop
\    TASKBAR                       24px bar at bottom with clock
\    FILE-PANEL                    file listing in the main area
\
\  Depends on: kalki-editor.f (EDITOR, EDIT integration)
\ =====================================================================

PROVIDED kalki-desktop.f
REQUIRE kalki-editor.f
REQUIRE kalki-menu.f

\ =====================================================================
\  Section 1: Constants & Layout
\ =====================================================================

24 CONSTANT TASKBAR-H            \ taskbar height (pixels)
800 600 TASKBAR-H - CONSTANT WORKSPACE-H  \ available height above taskbar

\ =====================================================================
\  Section 2: Desktop State
\ =====================================================================

VARIABLE DK-ROOT                 \ root widget
VARIABLE DK-TASKBAR              \ taskbar panel widget
VARIABLE DK-CLOCK-LBL            \ clock label widget
VARIABLE DK-FILE-WIN             \ file manager window
VARIABLE DK-FILE-LIST            \ file list panel inside window
VARIABLE DK-RUNNING              \ desktop event loop flag

VARIABLE DK-LAST-SEC             \ last rendered clock second
VARIABLE DK-CLOCK-TICK           \ ms timestamp of last clock update

\ Clock text buffer
CREATE DK-CLOCK-BUF 9 ALLOT     \ "HH:MM:SS" + null

\ =====================================================================
\  Section 3: Desktop Render Callbacks
\ =====================================================================

\ _DK-ROOT-RENDER ( widget -- )
\   Fill screen with desktop color.
: _DK-ROOT-RENDER  ( widget -- )
    DROP CLR-DESKTOP 0 0 800 600 FAST-RECT ;

\ _DK-TASKBAR-RENDER ( widget -- )
\   Flat dark bar at bottom of screen.
: _DK-TASKBAR-RENDER  ( widget -- )
    RD-SETUP
    CLR-WIN-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ Top separator line
    CLR-WIN-BORDER RD-AX @ RD-AY @ RD-W @ FAST-HLINE ;

\ =====================================================================
\  Section 4: Clock
\ =====================================================================

\ _DK-FMT-2D ( n addr -- )
\   Format a 2-digit number into addr (zero-padded).
: _DK-FMT-2D  ( n addr -- )
    OVER 10 / 48 + OVER C!
    1+ SWAP 10 MOD 48 + SWAP C! ;

\ _DK-UPDATE-CLOCK ( -- )
\   Read RTC and format "HH:MM:SS" into DK-CLOCK-BUF.
: _DK-UPDATE-CLOCK  ( -- )
    RTC@                         ( sec min hour day mon year dow )
    DROP DROP DROP DROP          ( sec min hour )
    DK-CLOCK-BUF _DK-FMT-2D     \ hour → buf[0..1]
    58 DK-CLOCK-BUF 2 + C!      \ ':'
    DK-CLOCK-BUF 3 + _DK-FMT-2D \ min → buf[3..4]
    58 DK-CLOCK-BUF 5 + C!      \ ':'
    DK-CLOCK-BUF 6 + _DK-FMT-2D \ sec → buf[6..7]
    0 DK-CLOCK-BUF 8 + C! ;     \ null terminator

\ _DK-CLOCK-RENDER ( widget -- )
\   Render clock text directly (overwrite label area).
: _DK-CLOCK-RENDER  ( widget -- )
    RD-SETUP
    \ Fill background
    CLR-WIN-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ Draw text
    RD-AX @ GFX-CX !
    RD-AY @ RD-H @ FONT-H - 2 / + GFX-CY !
    DK-CLOCK-BUF 8 CLR-TEXT GFX-TYPE ;

\ =====================================================================
\  Section 5: File Manager
\ =====================================================================

\ File list storage — extract names from FS directory
16 CONSTANT FM-MAX-FILES         \ max files to display
VARIABLE FM-COUNT                \ number of files found
CREATE FM-NAMES FM-MAX-FILES 24 * ALLOT  \ name storage (24 chars each)
CREATE FM-INDICES FM-MAX-FILES CELLS ALLOT  \ dir slot indices
VARIABLE FM-SELECTED             \ currently selected file index
0 FM-SELECTED !

\ _FM-SCAN ( -- )
\   Scan the filesystem directory and collect file names.
: _FM-SCAN  ( -- )
    0 FM-COUNT !
    FS-MAX-FILES 0 DO
        FM-COUNT @ FM-MAX-FILES >= IF LEAVE THEN
        I DIRENT DUP C@ 0<> IF      ( de — non-empty slot )
            \ Copy name (first 24 bytes of dir entry)
            FM-NAMES FM-COUNT @ 24 * +   ( de dest )
            OVER SWAP 24 CMOVE          ( de )
            DROP
            I FM-INDICES FM-COUNT @ CELLS + !
            1 FM-COUNT +!
        ELSE DROP THEN
    LOOP ;

\ _FM-ITEM-LEN ( idx -- n )
\   Return length of filename at index (up to 24, stopping at null).
: _FM-ITEM-LEN  ( idx -- n )
    24 * FM-NAMES +              ( addr )
    0                            ( addr n )
    BEGIN
        OVER OVER + C@ 0<>       ( addr n nonzero? )
        OVER 23 < AND            ( addr n continue? )
    WHILE
        1+
    REPEAT
    NIP ;

\ =====================================================================
\  Section 6: Editor Integration  (must be defined before _FM-LIST-KEY)
\ =====================================================================
\  Opens an editor window inside the desktop (not standalone EDIT).
\  Includes a menu bar with File → Save / Close.

VARIABLE _DKE-WIN               \ editor window inside desktop
VARIABLE _DKE-WG                \ editor widget inside that window
VARIABLE _DKE-MBAR              \ menu bar widget (0 if none)
CREATE _DKE-FNAME 24 ALLOT      \ filename for desktop editor
VARIABLE _DKE-FNLEN

\ _DK-CLOSE-EDITOR ( -- )
\   Close the editor window and return to file manager.
\   Must be defined before _DK-OPEN-FILE (used by menu action XT).
: _DK-CLOSE-EDITOR  ( -- )
    _DKE-WIN @ DUP 0= IF DROP EXIT THEN
    DUP WIN-UNREGISTER
    WG-FREE-SUBTREE
    0 _DKE-WIN !
    0 _DKE-WG !
    0 _DKE-MBAR !
    \ Show file manager again
    DK-FILE-WIN @ WGF-VISIBLE WG-SET-FLAG
    DK-FILE-LIST @ FOCUS
    DK-ROOT @ MARK-ALL-DIRTY ;

\ ── Menu action words ──

: _DKE-DO-SAVE  ( -- )
    _DKE-WG @ IF
        19 _DKE-WG @ EDITOR-KEY DROP
        _DKE-WG @ WG-DIRTY
    THEN ;

: _DKE-DO-CLOSE  ( -- )
    _DK-CLOSE-EDITOR ;

\ ── Transient variable for menu creation ──
VARIABLE _DKE-FMENU

\ _DK-OPEN-FILE ( fm-idx -- )
\   Open selected file in an editor window on the desktop.
: _DK-OPEN-FILE  ( fm-idx -- )
    \ Get filename
    DUP 24 * FM-NAMES +          ( idx name-addr )
    SWAP _FM-ITEM-LEN            ( name-addr len )
    DUP _DKE-FNLEN !
    _DKE-FNAME SWAP CMOVE
    \ Hide file manager
    DK-FILE-WIN @ WGF-VISIBLE WG-CLR-FLAG
    \ Create editor window (full workspace area)
    0 0 800 WORKSPACE-H
    _DKE-FNAME _DKE-FNLEN @
    DK-ROOT @ WINDOW
    _DKE-WIN !
    \ ── Menu bar at top of client area ──
    _DKE-WIN @ MENU-BAR _DKE-MBAR !
    \ File menu: Save, separator, Close
    3 MENU-CREATE _DKE-FMENU !
    S" Save"  ['] _DKE-DO-SAVE  _DKE-FMENU @ MENU-ADD
    _DKE-FMENU @ MENU-ADD-SEP
    S" Close" ['] _DKE-DO-CLOSE _DKE-FMENU @ MENU-ADD
    S" File" _DKE-FMENU @ _DKE-MBAR @ MBAR-ADD
    \ ── Editor widget fills client area below menu bar ──
    WIN-CLIENT-X WIN-CLIENT-Y MBAR-H +
    800 WIN-CLIENT-X 2* -
    WORKSPACE-H WIN-CLIENT-Y - MBAR-H -
    _DKE-WIN @ EDITOR
    _DKE-WG !
    \ Set filename and load
    _DKE-FNAME _DKE-FNLEN @ _DKE-WG @ _ED-SET-FILENAME
    _DKE-WG @ _ED-LOAD-FILE
    _DKE-WG @ FOCUS
    \ Full repaint
    DK-ROOT @ MARK-ALL-DIRTY ;

\ =====================================================================
\  Section 5 continued: File Manager UI
\ =====================================================================

\ _FM-LIST-RENDER ( widget -- )
\   Render the file list with selection highlight.
: _FM-LIST-RENDER  ( widget -- )
    RD-SETUP
    \ Background
    CLR-EDIT-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    \ Each file entry: LINE-H pixels tall
    FM-COUNT @ 0 DO
        I FM-SELECTED @ = IF
            \ Selection highlight bar
            CLR-HIGHLIGHT
            RD-AX @
            RD-AY @ I LINE-H * + 2 +
            RD-W @
            LINE-H
            FAST-RECT
        THEN
        RD-AX @ 8 + GFX-CX !
        RD-AY @ I LINE-H * + 3 + GFX-CY !
        \ File icon glyph (simple text indicator)
        I FM-SELECTED @ = IF CLR-HILITE-FG ELSE CLR-EDIT-FG THEN
        FM-NAMES I 24 * + I _FM-ITEM-LEN
        ROT GFX-TYPE
    LOOP ;

\ _FM-LIST-KEY ( key widget -- consumed? )
\   Handle Up/Down/Enter in the file list.
VARIABLE _FMK-KEY
: _FM-LIST-KEY  ( key widget -- consumed? )
    DROP _FMK-KEY !
    _FMK-KEY @ K-UP = IF
        FM-SELECTED @ 1- 0 MAX FM-SELECTED !
        DK-FILE-LIST @ WG-DIRTY -1 EXIT
    THEN
    _FMK-KEY @ K-DOWN = IF
        FM-SELECTED @ 1+ FM-COUNT @ 1- 0 MAX MIN FM-SELECTED !
        DK-FILE-LIST @ WG-DIRTY -1 EXIT
    THEN
    _FMK-KEY @ K-ENTER = IF
        FM-COUNT @ 0= IF -1 EXIT THEN
        \ Open selected file in editor
        FM-SELECTED @ _DK-OPEN-FILE
        -1 EXIT
    THEN
    0 ;

\ =====================================================================
\  Section 7: Desktop Key Handler
\ =====================================================================

\ Desktop-level key handling:
\   - Esc in editor closes it
\   - Ctrl-N cycles windows
\   - Otherwise dispatched to focused widget
: _DK-HANDLE-KEY  ( key -- )
    \ If editor is open and Esc pressed, close editor
    DUP K-ESC = IF
        _DKE-WIN @ IF
            DROP _DK-CLOSE-EDITOR EXIT
        THEN
    THEN
    WIN-DELIVER-KEY DROP ;

\ =====================================================================
\  Section 8: Desktop Construction
\ =====================================================================

: _DK-BUILD  ( -- )
    \ Reset window manager
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    0 _DKE-WIN !  0 _DKE-WG !  0 _DKE-MBAR !
    \ Root widget
    WGT-ROOT WG-ALLOC DUP DK-ROOT !
    0 0 800 600 WG-SET-RECT DROP
    ['] _DK-ROOT-RENDER DK-ROOT @ WG.RENDER !
    \ Taskbar
    WGT-PANEL WG-ALLOC DUP DK-TASKBAR !
    0 WORKSPACE-H 800 TASKBAR-H WG-SET-RECT DROP
    ['] _DK-TASKBAR-RENDER DK-TASKBAR @ WG.RENDER !
    DK-TASKBAR @ DK-ROOT @ WG-ADD-CHILD
    \ Clock label in taskbar (right-aligned)
    _DK-UPDATE-CLOCK
    WGT-LABEL WG-ALLOC DUP DK-CLOCK-LBL !
    800 TASKBAR-H - 8 TEXT-WIDTH - 0 8 TEXT-WIDTH TASKBAR-H WG-SET-RECT DROP
    ['] _DK-CLOCK-RENDER DK-CLOCK-LBL @ WG.RENDER !
    DK-CLOCK-LBL @ DK-TASKBAR @ WG-ADD-CHILD
    \ "Kalki" branding in taskbar (left side)
    4 0 S" Kalki" DK-TASKBAR @ LABEL DROP
    \ File manager window (centered in workspace)
    40 20 720 WORKSPACE-H 40 -
    S" Files" DK-ROOT @ WINDOW
    DK-FILE-WIN !
    \ File list panel inside window
    _FM-SCAN
    WGT-PANEL WG-ALLOC DUP DK-FILE-LIST !
    WIN-CLIENT-X WIN-CLIENT-Y
    720 WIN-CLIENT-X 2* -
    WORKSPACE-H 40 - WIN-CLIENT-Y -
    WG-SET-RECT
    WG-MAKE-FOCUSABLE DROP
    ['] _FM-LIST-RENDER DK-FILE-LIST @ WG.RENDER !
    ['] _FM-LIST-KEY DK-FILE-LIST @ WG.ONKEY !
    DK-FILE-LIST @ DK-FILE-WIN @ WG-ADD-CHILD
    DK-FILE-LIST @ FOCUS
    -1 DK-LAST-SEC ! ;

\ =====================================================================
\  Section 9: Desktop Event Loop
\ =====================================================================

: _DK-LOOP  ( -- )
    -1 DK-RUNNING !
    \ Initial render (both buffers)
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE
    FB-SWAP
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE
    FB-SWAP
    BEGIN
        \ Update clock every second
        RTC@ DROP DROP DROP DROP DROP DROP  ( sec )
        DUP DK-LAST-SEC @ <> IF
            DK-LAST-SEC !
            _DK-UPDATE-CLOCK
            DK-CLOCK-LBL @ WG-DIRTY
        ELSE DROP THEN
        \ Render dirty widgets
        DK-ROOT @ RENDER-TREE
        FB-SWAP
        FB-COPY-BACK
        \ Wait for vsync / yield CPU
        GFX-SYNC
        \ Poll keyboard
        KEY? IF
            EKEY
            DUP K-CTRL-S = IF
                \ Ctrl-S in editor → save, don't exit
                _DKE-WG @ IF
                    DROP
                    19 _DKE-WG @ EDITOR-KEY DROP
                    _DKE-WG @ WG-DIRTY
                ELSE
                    _DK-HANDLE-KEY
                THEN
            ELSE
                \ Handle keys when editor is open
                _DKE-WG @ IF
                    \ Check if the menu bar is focused
                    _DKE-MBAR @ 0<>
                    FOCUS-WIDGET @ _DKE-MBAR @ = AND IF
                        \ ── Menu bar focused ──
                        DUP FOCUS-WIDGET @
                        DUP WG.ONKEY @ EXECUTE IF
                            DROP         \ consumed by menu bar
                        ELSE
                            \ Not consumed — handle Tab/Esc/other
                            DUP K-ESC = IF
                                DROP
                                _DKE-WG @ FOCUS
                                _DKE-MBAR @ WG-DIRTY
                            ELSE DUP K-TAB = IF
                                DROP
                                _DKE-WG @ FOCUS
                                _DKE-MBAR @ WG-DIRTY
                            ELSE
                                DROP     \ ignore other keys
                            THEN THEN
                        THEN
                    ELSE
                        \ ── Editor focused ──
                        DUP K-TAB = IF
                            \ Tab → switch focus to menu bar
                            DROP
                            _DKE-MBAR @ IF
                                _DKE-MBAR @ FOCUS
                                _DKE-WG @ WG-DIRTY
                            THEN
                        ELSE
                            DUP _DKE-WG @ EDITOR-KEY IF
                                DROP
                                _DKE-WG @ WG-DIRTY
                            ELSE
                                _DK-HANDLE-KEY
                            THEN
                        THEN
                    THEN
                ELSE
                    _DK-HANDLE-KEY
                THEN
            THEN
        THEN
        DK-RUNNING @ 0=
    UNTIL ;

\ =====================================================================
\  Section 10: Entry Point
\ =====================================================================

\ KALKI ( -- )
\   Initialize the desktop environment and enter the event loop.
\   Returns to Forth prompt when desktop exits.
: KALKI  ( -- )
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    _DK-BUILD
    _DK-LOOP
    \ Cleanup
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    DK-ROOT @ WG-FREE-SUBTREE ;

\ =====================================================================
\  Section 11: Smoke Test
\ =====================================================================

VARIABLE _DKT-ROOT

: KALKI-DESKTOP-TEST  ( -- )
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    _DK-BUILD
    \ Verify structure
    DK-ROOT @ 0<> IF ." root=ok " ELSE ." root=FAIL " THEN
    DK-TASKBAR @ 0<> IF ." taskbar=ok " ELSE ." taskbar=FAIL " THEN
    DK-CLOCK-LBL @ 0<> IF ." clock=ok " ELSE ." clock=FAIL " THEN
    DK-FILE-WIN @ 0<> IF ." filewin=ok " ELSE ." filewin=FAIL " THEN
    DK-FILE-LIST @ 0<> IF ." filelist=ok " ELSE ." filelist=FAIL " THEN
    FM-COUNT @ 0> IF ." files>0=ok " ELSE ." files=FAIL " THEN
    \ Render test
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE
    FB-SWAP
    ." render=ok " CR
    \ Clock format
    _DK-UPDATE-CLOCK
    DK-CLOCK-BUF 2 + C@ 58 = IF ." clockfmt=ok " ELSE ." clockfmt=FAIL " THEN
    CR
    \ Cleanup
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    DK-ROOT @ WG-FREE-SUBTREE
    ." kalki-desktop test complete" CR ;
