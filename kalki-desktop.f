\ kalki-desktop.f — Desktop Shell
\ =====================================================================
\  Desktop environment: root surface, taskbar with clock.
\  Applications run as isolated processes via APP-LAUNCH.
\  Events routed via APP-DELIVER to the focused app.
\
\  Provides:
\    KALKI            ( -- )   enter the desktop (Esc to exit)
\    DK-ROOT          root widget for the desktop
\    WORKSPACE-H      usable height above taskbar
\
\  Depends on: kalki-app.f (process manager)
\ =====================================================================

PROVIDED kalki-desktop.f

\ =====================================================================
\  Section 1: Constants & Layout
\ =====================================================================

24 CONSTANT TASKBAR-H
600 TASKBAR-H - CONSTANT WORKSPACE-H

\ =====================================================================
\  Section 2: Desktop State
\ =====================================================================

VARIABLE DK-ROOT
VARIABLE DK-TASKBAR
VARIABLE DK-CLOCK-LBL
VARIABLE DK-RUNNING

VARIABLE DK-LAST-SEC
VARIABLE DK-CLOCK-TICK

\ Clock text buffer
CREATE DK-CLOCK-BUF 9 ALLOT     \ "HH:MM:SS" + null

\ =====================================================================
\  Section 3: Render Callbacks
\ =====================================================================

: _DK-ROOT-RENDER  ( widget -- )
    DROP CLR-DESKTOP 0 0 800 600 FAST-RECT ;

: _DK-TASKBAR-RENDER  ( widget -- )
    RD-SETUP
    CLR-WIN-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    CLR-WIN-BORDER RD-AX @ RD-AY @ RD-W @ FAST-HLINE ;

\ =====================================================================
\  Section 4: Clock
\ =====================================================================

: _DK-FMT-2D  ( n addr -- )
    OVER 10 / 48 + OVER C!
    1+ SWAP 10 MOD 48 + SWAP C! ;

: _DK-UPDATE-CLOCK  ( -- )
    RTC@                         ( sec min hour day mon year dow )
    DROP DROP DROP DROP          ( sec min hour )
    DK-CLOCK-BUF _DK-FMT-2D     \ hour → buf[0..1]
    58 DK-CLOCK-BUF 2 + C!      \ ':'
    DK-CLOCK-BUF 3 + _DK-FMT-2D \ min → buf[3..4]
    58 DK-CLOCK-BUF 5 + C!      \ ':'
    DK-CLOCK-BUF 6 + _DK-FMT-2D \ sec → buf[6..7]
    0 DK-CLOCK-BUF 8 + C! ;     \ null terminator

: _DK-CLOCK-RENDER  ( widget -- )
    RD-SETUP
    CLR-WIN-BG RD-AX @ RD-AY @ RD-W @ RD-H @ FAST-RECT
    RD-AX @ GFX-CX !
    RD-AY @ RD-H @ FONT-H - 2 / + GFX-CY !
    DK-CLOCK-BUF 8 CLR-TEXT GFX-TYPE ;

\ =====================================================================
\  Section 5: App Launch Helpers
\ =====================================================================

\ _DK-LAUNCH-FM ( -- )
\   Entry-xt for file manager process.  Loads filemgr.f per-process.
\   Uses EVALUATE because REQUIRE parses its filename from the input
\   stream — can't be compiled into a colon definition directly.
: _DK-LAUNCH-FM  ( -- )
    S" REQUIRE filemgr.f" EVALUATE ;

\ _DK-KILL-ALL-APPS ( -- )
\   Kill every running app.  Used at desktop exit.
: _DK-KILL-ALL-APPS  ( -- )
    AP-MAX 0 DO
        I _AP-SLOT AP.STATE + @ 0<> IF
            I APP-KILL
        THEN
    LOOP ;

\ =====================================================================
\  Section 6: Desktop Construction
\ =====================================================================

: _DK-BUILD  ( -- )
    \ Reset window manager
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
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
    \ Launch file manager as app
    ['] _DK-LAUNCH-FM S" Files" APP-LAUNCH
    DUP 0< IF ." Warning: file manager launch failed" CR THEN
    DROP
    -1 DK-LAST-SEC ! ;

\ =====================================================================
\  Section 7: Desktop Event Loop
\ =====================================================================

: _DK-LOOP  ( -- )
    -1 DK-RUNNING !
    \ Initial render (both buffers)
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE  FB-SWAP
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE  FB-SWAP
    BEGIN
        \ Update clock every second
        RTC@ DROP DROP DROP DROP DROP DROP
        DUP DK-LAST-SEC @ <> IF
            DK-LAST-SEC !
            _DK-UPDATE-CLOCK
            DK-CLOCK-LBL @ WG-DIRTY
        ELSE DROP THEN
        \ Render dirty widgets
        DK-ROOT @ RENDER-TREE  FB-SWAP
        IDLE
        \ Poll keyboard
        KEY? IF
            EKEY
            DUP 14 = IF                   \ Ctrl-N → cycle apps
                DROP APP-NEXT
            ELSE DUP 17 = IF              \ Ctrl-Q → kill current app
                DROP APP-KILL-CURRENT
            ELSE DUP 27 = IF              \ Esc → exit desktop
                DROP 0 DK-RUNNING !
            ELSE
                \ Forward to focused app
                AP-FOCUSED @ DUP 0< IF
                    2DROP                  \ no app — discard key
                ELSE
                    APP-DELIVER DROP       \ deliver to app
                THEN
            THEN THEN THEN
        THEN
        DK-RUNNING @ 0=
    UNTIL ;

\ =====================================================================
\  Section 8: Entry Point
\ =====================================================================

: KALKI  ( -- )
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    _DK-BUILD
    _DK-LOOP
    \ Cleanup
    _DK-KILL-ALL-APPS
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    DK-ROOT @ WG-FREE-SUBTREE ;

\ =====================================================================
\  Section 9: Smoke Test
\ =====================================================================

: KALKI-DESKTOP-TEST  ( -- )
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    _DK-BUILD
    \ Verify desktop structure
    DK-ROOT @ 0<> IF ." root=ok " ELSE ." root=FAIL " THEN
    DK-TASKBAR @ 0<> IF ." taskbar=ok " ELSE ." taskbar=FAIL " THEN
    DK-CLOCK-LBL @ 0<> IF ." clock=ok " ELSE ." clock=FAIL " THEN
    \ Verify file manager app launched
    AP-FOCUSED @ 0< 0= IF ." app=ok " ELSE ." app=FAIL " THEN
    \ Render test
    DK-ROOT @ MARK-ALL-DIRTY
    DK-ROOT @ RENDER-TREE
    FB-SWAP
    ." render=ok " CR
    \ Clock format
    _DK-UPDATE-CLOCK
    DK-CLOCK-BUF 2 + C@ 58 = IF ." clockfmt=ok " ELSE ." clockfmt=FAIL " THEN
    CR
    \ Cleanup: kill all apps, then free root
    _DK-KILL-ALL-APPS
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    DK-ROOT @ WG-FREE-SUBTREE
    ." kalki-desktop test complete" CR ;

\ =====================================================================
\  Done
\ =====================================================================

." kalki-desktop.f loaded — desktop shell ready" CR
." Words: KALKI  KALKI-DESKTOP-TEST" CR
