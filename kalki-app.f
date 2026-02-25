\ kalki-app.f — Kalki Application Layer Process Manager
\ =====================================================================
\  Each application runs as a named process with its own dictionary,
\  memory region, arena, and module-registry snapshot.  The desktop
\  shell dispatches events via APP-DELIVER; context switches are
\  cooperative at event boundaries.
\
\  Lives in the system dictionary (shared by all processes).
\
\  Provides:
\    APP-LAUNCH      ( entry-xt c-addr u -- pid | -1 )
\    APP-KILL        ( pid -- )
\    APP-DELIVER     ( key pid -- consumed? )
\    APP-SWITCH      ( pid -- )
\    APP-NEXT        ( -- )
\    APP-KILL-CURRENT ( -- )
\    APP-FOCUSED     ( -- addr )
\    APP-SET-ROOT    ( widget -- )     called inside entry-xt
\    APP-SET-ONKEY   ( xt -- )         called inside entry-xt
\    APP-SET-CLEANUP ( xt -- )         called inside entry-xt
\    APP-LIST        ( -- )            debug: print running apps
\    KALKI-APP-TEST  ( -- )            smoke test
\
\  Depends on: kalki-widget.f, kalki-window.f
\ =====================================================================

PROVIDED kalki-app.f

\ =====================================================================
\  Section 1: Process Descriptor Layout
\ =====================================================================
\
\  256 slots × 96 bytes = 24 KiB in system dict.
\
\  Offset  Size  Field
\  ──────  ────  ─────
\    +0    cell  AP.STATE       0=free 1=running 2=suspended
\    +8    cell  AP.ARENA       arena descriptor address (32B, heap)
\   +16    cell  AP.ROOT        root widget (window) of this app
\   +24    cell  AP.ONKEY       xt of key handler ( key -- consumed? )
\   +32    cell  AP.CLEANUP     xt of cleanup word (or 0)
\   +40    cell  AP.LATEST      saved LATEST for this process
\   +48    cell  AP.HERE        saved HERE for this process
\   +56    cell  AP.MODHT       addr of 616-byte HT backup (heap)
\   +64    cell  AP.DICT-BASE   start of XMEM dict zone
\   +72    cell  AP.DICT-SIZE   size of dict zone (bytes)
\   +80    16B   AP.NAME        app name string (null-padded)

 0 CONSTANT AP.STATE
 8 CONSTANT AP.ARENA
16 CONSTANT AP.ROOT
24 CONSTANT AP.ONKEY
32 CONSTANT AP.CLEANUP
40 CONSTANT AP.LATEST
48 CONSTANT AP.HERE
56 CONSTANT AP.MODHT
64 CONSTANT AP.DICT-BASE
72 CONSTANT AP.DICT-SIZE
80 CONSTANT AP.NAME
96 CONSTANT AP.SIZE

256 CONSTANT AP-MAX             \ max process slots (24 KiB table)

CREATE AP-TABLE  AP.SIZE AP-MAX * ALLOT
AP-TABLE AP.SIZE AP-MAX * 0 FILL

\ Current focused process (-1 = no app focused)
VARIABLE AP-FOCUSED  -1 AP-FOCUSED !

\ =====================================================================
\  Section 2: Helpers
\ =====================================================================

\ _AP-SLOT ( pid -- desc-addr )
: _AP-SLOT  ( pid -- addr )
    AP.SIZE * AP-TABLE + ;

\ _AP-FIND-FREE ( -- pid | -1 )
\   Scan AP.STATE for first free slot.
: _AP-FIND-FREE  ( -- pid | -1 )
    AP-MAX 0 DO
        I _AP-SLOT AP.STATE + @ 0= IF I UNLOOP EXIT THEN
    LOOP
    -1 ;

\ =====================================================================
\  Section 3: Desktop Context Save Area
\ =====================================================================
\
\  The desktop's LATEST / HERE / _MOD-HT are saved here during
\  APP-LAUNCH / APP-DELIVER / APP-KILL (cleanup callback).

VARIABLE _AP-DK-LATEST
VARIABLE _AP-DK-HERE

\ _MOD-HT is a 616-byte block: 40-byte header + 576-byte data.
\   keysize=16  valsize=1  slots=32  stride=18  data=32×18=576
\   header: keysize(8) valsize(8) slots(8) count(8) lock(8) = 40
616 CONSTANT _AP-HT-SIZE

CREATE _AP-DK-MODHT  _AP-HT-SIZE ALLOT

\ =====================================================================
\  Section 4: Module HT Swapping
\ =====================================================================
\
\  _MOD-HT (KDOS §19a) is a CONSTANT — its address is baked into
\  _MOD-MARK and _MOD-LOADED? at compile time.  Redefining those
\  words won't help because REQUIRE/_MOD-PRESCAN call the OLD xts.
\
\  Solution: swap the DATA at the _MOD-HT address in-place.
\  We memcpy 616 bytes in/out on every context switch.  At 100 MIPS
\  this is ~100 instructions — negligible (happens once per keypress).

\ _AP-HT-NEW ( -- addr )
\   ALLOCATE a 616-byte zeroed buffer for per-process HT backup.
: _AP-HT-NEW  ( -- addr )
    _AP-HT-SIZE ALLOCATE ABORT" APP: HT alloc failed"
    DUP _AP-HT-SIZE 0 FILL ;

\ _AP-HT-SNAPSHOT ( buf -- )
\   Copy _MOD-HT → buf  (save current module registry)
: _AP-HT-SNAPSHOT  ( buf -- )
    _MOD-HT SWAP _AP-HT-SIZE CMOVE ;

\ _AP-HT-LOAD ( buf -- )
\   Copy buf → _MOD-HT  (restore a saved module registry)
: _AP-HT-LOAD  ( buf -- )
    _MOD-HT _AP-HT-SIZE CMOVE ;

\ =====================================================================
\  Section 5: Context Switch Primitives
\ =====================================================================

\ ── Desktop context ──────────────────────────────────────────────────

\ _AP-CTX-SAVE-DK ( -- )
\   Save desktop's dictionary state to the static save area.
: _AP-CTX-SAVE-DK  ( -- )
    LATEST            _AP-DK-LATEST !
    HERE              _AP-DK-HERE   !
    _AP-DK-MODHT     _AP-HT-SNAPSHOT ;

\ _AP-CTX-RESTORE-DK ( -- )
\   Restore desktop's dictionary state from the static save area.
: _AP-CTX-RESTORE-DK  ( -- )
    _AP-DK-LATEST @  LATEST!
    _AP-DK-HERE   @  HERE - ALLOT
    _AP-DK-MODHT     _AP-HT-LOAD ;

\ ── Process context ──────────────────────────────────────────────────

\ _AP-CTX-SAVE ( desc -- )
\   Save current LATEST/HERE/_MOD-HT to a process descriptor.
: _AP-CTX-SAVE  ( desc -- )
    LATEST     OVER AP.LATEST + !
    HERE       OVER AP.HERE   + !
    AP.MODHT + @  _AP-HT-SNAPSHOT ;

\ _AP-CTX-RESTORE ( desc -- )
\   Restore LATEST/HERE/_MOD-HT from a process descriptor.
: _AP-CTX-RESTORE  ( desc -- )
    DUP  AP.LATEST + @ LATEST!
    DUP  AP.HERE   + @ HERE - ALLOT
    AP.MODHT + @  _AP-HT-LOAD ;

\ =====================================================================
\  Section 6: Descriptor Setters (called from inside entry-xt)
\ =====================================================================
\
\  These use _AP-PID to find the current launching/active slot.
\  _AP-PID is set by APP-LAUNCH and APP-DELIVER before entering
\  the process context.

VARIABLE _AP-PID               \ scratch: current process slot id
VARIABLE _AP-XT                \ scratch: launch entry-xt

: APP-SET-ROOT     ( widget -- )
    _AP-PID @ _AP-SLOT AP.ROOT    + ! ;
: APP-SET-ONKEY    ( xt -- )
    _AP-PID @ _AP-SLOT AP.ONKEY   + ! ;
: APP-SET-CLEANUP  ( xt -- )
    _AP-PID @ _AP-SLOT AP.CLEANUP + ! ;

\ APP-CURRENT-PID ( -- pid )
\   Return the pid of the currently executing process.
\   Valid only inside entry-xt or ONKEY handler.
: APP-CURRENT-PID  ( -- pid )
    _AP-PID @ ;

\ =====================================================================
\  Section 7: Process Focus / Visibility
\ =====================================================================

\ _AP-DO-FOCUS ( pid -- )
\   Switch focus to pid.  Hides old root, shows new root.
: _AP-DO-FOCUS  ( pid -- )
    \ Hide old app's root (if any)
    AP-FOCUSED @ DUP 0< 0= IF
        _AP-SLOT AP.ROOT + @ ?DUP IF
            WGF-VISIBLE WG-CLR-FLAG
        THEN
    ELSE DROP THEN
    \ Show new app's root, focus first widget
    DUP AP-FOCUSED !
    _AP-SLOT AP.ROOT + @ ?DUP IF
        DUP WGF-VISIBLE WG-SET-FLAG
        DUP MARK-ALL-DIRTY
        _FOCUS-FIRST
    THEN ;

\ =====================================================================
\  Section 8: _AP-KILL-SLOT (internal teardown)
\ =====================================================================
\
\  Defined before APP-LAUNCH because APP-LAUNCH's error path calls it.
\  Must be called from desktop context (or during APP-LAUNCH).

\ _AP-KILL-SLOT ( pid -- )
\   Internal: unconditional teardown.
: _AP-KILL-SLOT  ( pid -- )
    DUP _AP-SLOT AP.STATE + @ 0= IF DROP EXIT THEN  \ already free

    \ ── Un-focus if needed ────────────────
    DUP AP-FOCUSED @ = IF -1 AP-FOCUSED ! THEN

    \ ── Free root widget subtree ──────────
    DUP _AP-SLOT AP.ROOT + @ ?DUP IF
        DUP WIN-UNREGISTER
        WG-FREE-SUBTREE
    THEN

    \ ── Run cleanup callback (in process context) ──
    DUP _AP-SLOT AP.CLEANUP + @ ?DUP IF
        >R                                       ( pid  R: cleanup-xt )
        _AP-CTX-SAVE-DK
        DUP _AP-SLOT _AP-CTX-RESTORE
        R> CATCH DROP                            ( pid ; ignore errors )
        DUP _AP-SLOT _AP-CTX-SAVE
        _AP-CTX-RESTORE-DK                      ( pid )
    THEN

    \ ── Destroy arena ─────────────────────
    DUP _AP-SLOT AP.ARENA + @ ?DUP IF
        DUP ARENA-DESTROY
        FREE                                     \ free 32-byte descriptor
    THEN

    \ ── Free XMEM dict zone ──────────────
    DUP _AP-SLOT AP.DICT-BASE + @ ?DUP IF
        OVER _AP-SLOT AP.DICT-SIZE + @
        XMEM-FREE-BLOCK
    THEN

    \ ── Free HT backup buffer ────────────
    DUP _AP-SLOT AP.MODHT + @ ?DUP IF FREE THEN

    \ ── Zero the entire slot ──────────────
    _AP-SLOT AP.SIZE 0 FILL ;

\ =====================================================================
\  Section 9: APP-LAUNCH
\ =====================================================================
\
\  APP-LAUNCH ( entry-xt c-addr u -- pid | -1 )
\    1. Find free slot
\    2. Store name
\    3. Allocate XMEM dict zone (1 MiB)
\    4. Create arena (64 KiB, heap-backed)
\    5. Create per-process _MOD-HT backup (snapshot system modules)
\    6. Context-switch to process: set HERE, keep LATEST at fork point
\    7. ARENA-PUSH, CATCH-execute entry-xt
\    8. Context-switch back to desktop
\    9. Mark running, focus
\   10. Return pid (or -1 on failure)

1048576 CONSTANT _AP-DICT-SZ    \ 1 MiB default dict zone
 262144 CONSTANT _AP-ARENA-SZ    \ 256 KiB default arena

: APP-LAUNCH  ( entry-xt c-addr u -- pid | -1 )
    ROT _AP-XT !                                 ( c-addr u )

    \ ── Find free slot ────────────────────
    _AP-FIND-FREE DUP 0< IF
        DROP 2DROP -1 EXIT
    THEN
    _AP-PID !                                    ( c-addr u )

    \ ── Store name (up to 15 chars + NUL) ─
    _AP-PID @ _AP-SLOT AP.NAME + 16 0 FILL
    15 MIN                                       ( c-addr u' )
    _AP-PID @ _AP-SLOT AP.NAME +                 ( c-addr u' dest )
    SWAP CMOVE                                   ( )

    \ ── Zero remaining fields ─────────────
    0 _AP-PID @ _AP-SLOT AP.ROOT    + !
    0 _AP-PID @ _AP-SLOT AP.ONKEY   + !
    0 _AP-PID @ _AP-SLOT AP.CLEANUP + !

    \ ── Allocate XMEM dict zone ───────────
    _AP-DICT-SZ XMEM-ALLOT                      ( dict-base )
    DUP _AP-PID @ _AP-SLOT AP.DICT-BASE + !
    _AP-DICT-SZ _AP-PID @ _AP-SLOT AP.DICT-SIZE + !  ( dict-base )

    \ ── Create arena descriptor (32B heap) then init ──
    32 ALLOCATE ABORT" APP: arena desc"          ( dict-base arena-desc )
    DUP _AP-ARENA-SZ 1 ARENA-NEW-AT
    ABORT" APP: arena alloc"                     ( dict-base arena-desc )
    _AP-PID @ _AP-SLOT AP.ARENA + !             ( dict-base )

    \ ── Create per-process HT backup ──────
    _AP-HT-NEW                                   ( dict-base ht-buf )
    DUP _AP-PID @ _AP-SLOT AP.MODHT + !
    _AP-HT-SNAPSHOT                              ( dict-base )
    \ ht-buf now contains a copy of the system _MOD-HT
    \ (all system modules marked as loaded)

    \ ── Save desktop context ──────────────
    _AP-CTX-SAVE-DK                              ( dict-base )

    \ ── Switch HERE to process dict zone ──
    HERE - ALLOT                                 ( ; HERE = dict-base )
    \ LATEST stays at system LATEST (fork point).
    \ _MOD-HT still has system modules (correct —
    \   the process sees system modules as already loaded).

    \ ── Push process arena ────────────────
    _AP-PID @ _AP-SLOT AP.ARENA + @ ARENA-PUSH

    \ ── Execute entry XT (CATCH-protected) ─
    _AP-XT @ CATCH                               ( 0 | ior )
    ?DUP IF
        ." APP: init failed (" . ." )" CR
        ARENA-POP
        _AP-PID @ _AP-SLOT _AP-CTX-SAVE
        _AP-CTX-RESTORE-DK
        _AP-PID @ _AP-KILL-SLOT
        -1 EXIT
    THEN                                         ( )

    \ ── Context-switch BACK to desktop ────
    ARENA-POP
    _AP-PID @ _AP-SLOT _AP-CTX-SAVE
    _AP-CTX-RESTORE-DK

    \ ── Mark running ──────────────────────
    1 _AP-PID @ _AP-SLOT AP.STATE + !

    \ ── Focus this app ────────────────────
    _AP-PID @ _AP-DO-FOCUS

    _AP-PID @ ;                                  ( pid )

\ =====================================================================
\  Section 10: APP-KILL
\ =====================================================================
\
\  APP-KILL ( pid -- )
\    Tear down a process: free widgets, arena, dict zone, HT backup.
\    Must be called from desktop context (not from inside a process).

: APP-KILL  ( pid -- )
    DUP 0< IF DROP EXIT THEN
    DUP AP-MAX >= IF DROP EXIT THEN
    DUP _AP-KILL-SLOT
    \ Focus next running app (or none)
    AP-FOCUSED @ 0< IF
        AP-MAX 0 DO
            I _AP-SLOT AP.STATE + @ 1 = IF
                I _AP-DO-FOCUS UNLOOP EXIT
            THEN
        LOOP
    THEN ;

\ APP-KILL-CURRENT ( -- )
\   Kill the currently focused app.
: APP-KILL-CURRENT  ( -- )
    AP-FOCUSED @ DUP 0< IF DROP EXIT THEN
    APP-KILL ;

\ =====================================================================
\  Section 11: APP-DELIVER
\ =====================================================================
\
\  APP-DELIVER ( key pid -- consumed? )
\    Context-switch to process, execute ONKEY handler, switch back.
\    If handler THROWs, the app is killed.

VARIABLE _AP-KEY                 \ scratch for key during delivery

: APP-DELIVER  ( key pid -- consumed? )
    DUP _AP-SLOT AP.STATE + @ 1 <> IF 2DROP 0 EXIT THEN
    _AP-PID !  _AP-KEY !                         ( )

    \ ── Context-switch to process ─────────
    _AP-CTX-SAVE-DK
    _AP-PID @ _AP-SLOT _AP-CTX-RESTORE

    \ ── Push arena ────────────────────────
    _AP-PID @ _AP-SLOT AP.ARENA + @ ARENA-PUSH

    \ ── Execute ONKEY handler ─────────────
    _AP-PID @ _AP-SLOT AP.ONKEY + @ ?DUP IF
        _AP-KEY @ SWAP                           ( key xt )
        CATCH                                    ( consumed 0 | key ior )
        ?DUP IF
            \ Handler threw — kill process
            ." APP: key handler threw (" . ." )" CR
            DROP                                 ( drop key )
            ARENA-POP
            _AP-PID @ _AP-SLOT _AP-CTX-SAVE
            _AP-CTX-RESTORE-DK
            _AP-PID @ _AP-KILL-SLOT
            0 EXIT
        THEN                                     ( consumed? )
    ELSE
        0                                        ( no handler → not consumed )
    THEN                                         ( consumed? )

    \ ── Context-switch back ───────────────
    ARENA-POP
    _AP-PID @ _AP-SLOT _AP-CTX-SAVE
    _AP-CTX-RESTORE-DK ;                        ( consumed? )

\ =====================================================================
\  Section 12: APP-SWITCH / APP-NEXT
\ =====================================================================

\ APP-SWITCH ( pid -- )
\   Switch visibility and focus to a different app.
\   No context switch — just visibility flags.
: APP-SWITCH  ( pid -- )
    DUP 0< IF DROP EXIT THEN
    DUP AP-MAX >= IF DROP EXIT THEN
    DUP _AP-SLOT AP.STATE + @ 1 <> IF DROP EXIT THEN
    _AP-DO-FOCUS ;

\ APP-NEXT ( -- )
\   Cycle focus to next running app (round-robin).
: APP-NEXT  ( -- )
    AP-FOCUSED @ 1+                              ( start )
    AP-MAX 0 DO
        DUP AP-MAX MOD                           ( start idx )
        DUP _AP-SLOT AP.STATE + @ 1 = IF
            NIP _AP-DO-FOCUS UNLOOP EXIT
        THEN
        DROP 1+                                  ( start+1 )
    LOOP
    DROP ;                                       \ no apps running

\ =====================================================================
\  Section 13: APP-LIST (debug)
\ =====================================================================

\ APP-LIST ( -- )
\   Print all process slots and their state.
: APP-LIST  ( -- )
    ." ── Process Table ──" CR
    AP-MAX 0 DO
        I _AP-SLOT AP.STATE + @ ?DUP IF
            ."   [" I . ." ] "
            1 = IF ." RUN " ELSE ." SUS " THEN
            ." name='"
            I _AP-SLOT AP.NAME +
            DUP 15 + OVER DO
                I C@ ?DUP IF EMIT ELSE LEAVE THEN
            LOOP
            ." '"
            ."  root=" I _AP-SLOT AP.ROOT + @ .
            ."  here=" I _AP-SLOT AP.HERE + @ .
            CR
        THEN
    LOOP
    ." ── Focused: " AP-FOCUSED @ . ." ──" CR ;

\ =====================================================================
\  Section 14: Smoke Test
\ =====================================================================
\
\  KALKI-APP-TEST exercises the full lifecycle:
\    1. Launch a tiny test app
\    2. Deliver a key to it
\    3. Kill it
\    4. Verify clean state

VARIABLE _AT-GOT-KEY            \ did the test ONKEY fire?
VARIABLE _AT-CLEANUP            \ did the test cleanup fire?
0 _AT-GOT-KEY !
0 _AT-CLEANUP !

\ _AT-ONKEY ( key -- consumed? )
\   Test key handler: just sets the flag and consumes.
: _AT-ONKEY  ( key -- consumed? )
    DROP 1 _AT-GOT-KEY ! -1 ;

\ _AT-CLEANUP ( -- )
\   Test cleanup handler.
: _AT-DO-CLEANUP  ( -- )
    1 _AT-CLEANUP ! ;

\ _AT-ENTRY ( -- )
\   Test app entry point: create a minimal root widget, set handlers.
: _AT-ENTRY  ( -- )
    \ Create a bare panel widget as app root (no parent needed)
    WGT-PANEL WG-ALLOC
    100 100 200 150 WG-SET-RECT
    APP-SET-ROOT
    ['] _AT-ONKEY APP-SET-ONKEY
    ['] _AT-DO-CLEANUP APP-SET-CLEANUP ;

: KALKI-APP-TEST  ( -- )
    ." === APP-TEST ===" CR

    \ Reset flags
    0 _AT-GOT-KEY !  0 _AT-CLEANUP !

    \ Launch test app
    ." Launch... " CR
    ['] _AT-ENTRY S" Test" APP-LAUNCH        ( pid | -1 )
    DUP 0< IF ." FAIL: launch returned -1" CR DROP EXIT THEN
    ." OK pid=" DUP . CR

    \ List processes
    APP-LIST

    \ Deliver a key
    ." Deliver key... " CR
    65 OVER APP-DELIVER                      ( pid consumed? )
    0= IF ." FAIL: key not consumed" CR DROP EXIT THEN
    _AT-GOT-KEY @ 0= IF ." FAIL: ONKEY didn't fire" CR DROP EXIT THEN
    ." OK key consumed" CR

    \ Kill
    ." Kill... " CR
    DUP APP-KILL                             ( pid )
    _AT-CLEANUP @ 0= IF ." FAIL: cleanup didn't fire" CR DROP EXIT THEN
    DUP _AP-SLOT AP.STATE + @ 0<> IF ." FAIL: slot not freed" CR DROP EXIT THEN
    DROP

    \ Verify no processes remain
    APP-LIST

    ." === ALL PASS ===" CR ;

\ =====================================================================
\  Done
\ =====================================================================

." kalki-app.f loaded — process manager ready" CR
." Words: APP-LAUNCH APP-KILL APP-DELIVER APP-SWITCH APP-NEXT" CR
."        APP-SET-ROOT APP-SET-ONKEY APP-SET-CLEANUP" CR
."        APP-LIST APP-KILL-CURRENT KALKI-APP-TEST" CR
