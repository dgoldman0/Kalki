\ kalki-editor.f — Phase 7: Gap Buffer Text Editor Widget
\ =====================================================================
\  A graphical text editor widget — the showcase feature.
\
\  Provides:
\    Gap buffer:  GAP-INIT, GAP-INSERT, GAP-DELETE, GAP-MOVE,
\                 GAP-CHAR@, GAP-LENGTH
\    EKEY:        Extended key reader (decodes VT100 escape sequences)
\    EDITOR:      Full editor widget with scrolling, cursor, line nums
\    EDIT:        Open a file in a stand-alone editor window
\
\  Gap buffer layout:
\    [ text-before-cursor | gap | text-after-cursor ]
\    gap_start = cursor position in buffer
\    gap_end   = start of text-after-cursor
\    Logical length = total_size - (gap_end - gap_start)
\
\  Depends on: kalki-window.f (WINDOW, dialogs)
\ =====================================================================

PROVIDED kalki-editor.f
REQUIRE kalki-window.f

\ =====================================================================
\  Section 0: Utility — Number to String
\ =====================================================================
\  This Forth lacks <# #S #>.  We roll our own U>STR.

CREATE _NUMBUF 12 ALLOT         \ enough for a 64-bit decimal
VARIABLE _NP

\ U>STR ( u -- addr len )
\   Convert unsigned integer to decimal string.
: U>STR  ( u -- addr len )
    _NUMBUF 12 + _NP !          \ _NP → past end of buffer
    BEGIN
        10 /MOD SWAP             ( quot rem )
        48 +                     ( quot digit-char )
        _NP @ 1- DUP _NP !      ( quot digit ptr )
        C!                       ( quot )
        DUP 0=
    UNTIL
    DROP
    _NP @                        ( addr )
    _NUMBUF 12 + OVER - ;       ( addr len )

\ Line rendering buffer — holds one extracted line for batch GFX-TYPE
CREATE _LINE-BUF 256 ALLOT

\ =====================================================================
\  Section 1: Extended Key Reader (EKEY)
\ =====================================================================
\  Reads VT100/ANSI escape sequences and returns high key constants.
\  Single bytes pass through unchanged.  ESC followed by [ triggers
\  CSI decoding.  Unknown sequences are consumed and discarded.

\ High key constants (above ASCII range)
256 CONSTANT K-UP
257 CONSTANT K-DOWN
258 CONSTANT K-RIGHT
259 CONSTANT K-LEFT
260 CONSTANT K-HOME
261 CONSTANT K-END
262 CONSTANT K-PGUP
263 CONSTANT K-PGDN
264 CONSTANT K-DEL
  8 CONSTANT K-BS
127 CONSTANT K-DEL2              \ alternate delete (0x7F)
 19 CONSTANT K-CTRL-S            \ Ctrl-S = 0x13

\ EKEY ( -- key )
\   Read one key event.  Decodes VT100 CSI sequences into K-* constants.
\   For unknown CSI sequences, consumes all bytes and returns 0.
: EKEY  ( -- key )
    KEY
    DUP 27 <> IF EXIT THEN       \ not ESC — return raw byte
    DROP                          \ discard ESC
    KEY? 0= IF 27 EXIT THEN      \ bare ESC (no follow-up)
    KEY DUP 91 <> IF             \ not '[' — unknown ESC sequence
        DROP 0 EXIT
    THEN
    DROP                          \ discard '['
    KEY                           ( final-or-param )
    DUP 65 = IF DROP K-UP    EXIT THEN   \ ESC[A = Up
    DUP 66 = IF DROP K-DOWN  EXIT THEN   \ ESC[B = Down
    DUP 67 = IF DROP K-RIGHT EXIT THEN   \ ESC[C = Right
    DUP 68 = IF DROP K-LEFT  EXIT THEN   \ ESC[D = Left
    DUP 72 = IF DROP K-HOME  EXIT THEN   \ ESC[H = Home
    DUP 70 = IF DROP K-END   EXIT THEN   \ ESC[F = End
    \ Parameterized: ESC[5~ = PgUp, ESC[6~ = PgDn, ESC[3~ = Delete
    DUP 53 = IF DROP KEY DROP K-PGUP EXIT THEN   \ ESC[5~
    DUP 54 = IF DROP KEY DROP K-PGDN EXIT THEN   \ ESC[6~
    DUP 51 = IF DROP KEY DROP K-DEL  EXIT THEN   \ ESC[3~
    \ Unknown — consume until final byte (64-126)
    BEGIN
        DUP 64 >= OVER 126 <= AND IF DROP 0 EXIT THEN
        DROP KEY
    AGAIN ;

\ =====================================================================
\  Section 2: Gap Buffer
\ =====================================================================
\  Contiguous memory block with a gap at the cursor position.
\  The gap buffer struct is a 6-cell block (48 bytes):
\    +0  buf     — base address of allocated buffer
\    +8  size    — total allocated size
\    +16 gs      — gap start (= cursor position in buffer)
\    +24 ge      — gap end
\    +32 dirty   — modified since last save
\    +40 lines   — cached line count (always >= 1)

: GB.BUF     ;                   \ +0
: GB.SIZE   8 + ;               \ +8
: GB.GS    16 + ;               \ +16  gap start
: GB.GE    24 + ;               \ +24  gap end
: GB.DIRTY 32 + ;               \ +32  dirty flag
: GB.LINES 40 + ;               \ +40  cached line count

48 CONSTANT /GAP-BUF            \ struct size

4096 CONSTANT GAP-INIT-SIZE     \ initial buffer size

\ GAP-LENGTH ( gb -- n )  logical text length
: GAP-LENGTH  ( gb -- n )
    DUP GB.SIZE @ SWAP
    DUP GB.GE @ SWAP GB.GS @ - - ;

\ GAP-INIT ( -- gb )
\   Allocate a new gap buffer.  Returns struct address or 0.
: GAP-INIT  ( -- gb )
    /GAP-BUF ALLOCATE IF DROP 0 EXIT THEN   ( gb )
    DUP /GAP-BUF 0 FILL
    GAP-INIT-SIZE ALLOCATE IF               ( gb addr ior )
        DROP FREE 0 EXIT                    ( -- 0 )
    THEN                                     ( gb buf )
    OVER GB.BUF !
    GAP-INIT-SIZE OVER GB.SIZE !
    0 OVER GB.GS !
    GAP-INIT-SIZE OVER GB.GE !
    0 OVER GB.DIRTY !
    1 OVER GB.LINES ! ;

\ GAP-FREE ( gb -- )
\   Free buffer and struct.
: GAP-FREE  ( gb -- )
    DUP 0= IF DROP EXIT THEN
    DUP GB.BUF @ ?DUP IF FREE THEN
    FREE ;

\ _GAP-GROW ( gb -- flag )
\   Double the buffer.  Returns true on success.
\   gb pointer remains valid (struct is updated in place).
VARIABLE _GG-OLD  VARIABLE _GG-NEW  VARIABLE _GG-SZ
: _GAP-GROW  ( gb -- flag )
    DUP _GG-OLD !
    GB.SIZE @ 2* _GG-SZ !               \ consume gb from stack
    _GG-SZ @ ALLOCATE IF DROP 0 EXIT THEN
    _GG-NEW !
    \ Copy text-before-gap
    _GG-OLD @ GB.BUF @
    _GG-NEW @
    _GG-OLD @ GB.GS @
    CMOVE
    \ Copy text-after-gap
    _GG-OLD @ GB.BUF @ _GG-OLD @ GB.GE @ +
    _GG-NEW @ _GG-SZ @ _GG-OLD @ GB.SIZE @ _GG-OLD @ GB.GE @ - - +
    _GG-OLD @ GB.SIZE @ _GG-OLD @ GB.GE @ -
    CMOVE
    \ Update struct
    _GG-OLD @ GB.BUF @ FREE
    _GG-NEW @ _GG-OLD @ GB.BUF !
    _GG-OLD @ GB.GE @  _GG-SZ @ _GG-OLD @ GB.SIZE @ - +
    _GG-OLD @ GB.GE !
    _GG-SZ @ _GG-OLD @ GB.SIZE !
    -1 ;

\ _GAP-ENSURE ( gb n -- )
\   Ensure gap has at least n bytes.  Grows if needed.
: _GAP-ENSURE  ( gb n -- )
    OVER DUP GB.GE @ SWAP GB.GS @ -   ( gb n gap-size )
    ROT DROP                            ( n gap-size )
    <= IF                               ( -- gap too small? )
        \ Need to grow — retrieve gb from caller context
    ELSE EXIT THEN ;

\ Redefine with variables for clarity:
VARIABLE _GE-GB  VARIABLE _GE-N
: _GAP-ENSURE  ( gb n -- )
    _GE-N ! _GE-GB !
    _GE-GB @ GB.GE @ _GE-GB @ GB.GS @ - ( gap-size )
    _GE-N @ > IF EXIT THEN              \ gap already big enough
    BEGIN
        _GE-GB @ _GAP-GROW 0= IF EXIT THEN
        _GE-GB @ GB.GE @ _GE-GB @ GB.GS @ -
        _GE-N @ >
    UNTIL ;

\ GAP-MOVE ( pos gb -- )
\   Move gap so that gap_start = pos (clamped to logical length).
VARIABLE _GM-GB  VARIABLE _GM-POS
VARIABLE _GM-GS  VARIABLE _GM-CNT
: GAP-MOVE  ( pos gb -- )
    DUP _GM-GB !
    SWAP 0 MAX OVER GAP-LENGTH MIN _GM-POS !
    GB.GS @ _GM-GS !
    _GM-POS @ _GM-GS @ = IF EXIT THEN
    _GM-POS @ _GM-GS @ < IF
        \ Move left: shift bytes [pos..gs) to end of gap
        _GM-GS @ _GM-POS @ - _GM-CNT !
        _GM-GB @ GB.BUF @ _GM-POS @ +                ( src )
        _GM-GB @ GB.GE @ _GM-CNT @ - _GM-GB @ GB.BUF @ +  ( src dst )
        _GM-CNT @ CMOVE
        _GM-POS @ _GM-GB @ GB.GS !
        _GM-GB @ GB.GE @ _GM-CNT @ - _GM-GB @ GB.GE !
    ELSE
        \ Move right: shift bytes [ge..ge+count) to gs
        _GM-POS @ _GM-GS @ - _GM-CNT !
        _GM-GB @ GB.BUF @ _GM-GB @ GB.GE @ +        ( src )
        _GM-GB @ GB.BUF @ _GM-GS @ +                ( src dst )
        _GM-CNT @ CMOVE
        _GM-GS @ _GM-CNT @ + _GM-GB @ GB.GS !
        _GM-GB @ GB.GE @ _GM-CNT @ + _GM-GB @ GB.GE !
    THEN ;

\ GAP-INSERT ( char gb -- )
\   Insert a character at the gap position.
: GAP-INSERT  ( char gb -- )
    DUP 1 _GAP-ENSURE
    OVER 10 = IF DUP GB.LINES @ 1+ OVER GB.LINES ! THEN
    DUP GB.BUF @ OVER GB.GS @ + ROT SWAP C!
    DUP GB.GS @ 1+ OVER GB.GS !
    1 SWAP GB.DIRTY ! ;

\ GAP-DELETE ( gb -- )
\   Delete character before gap (backspace).  No-op if at start.
: GAP-DELETE  ( gb -- )
    DUP GB.GS @ 0= IF DROP EXIT THEN
    \ Check if deleted char is LF — update cached line count
    DUP GB.BUF @ OVER GB.GS @ 1- + C@ 10 = IF
        DUP GB.LINES @ 1- 1 MAX OVER GB.LINES !
    THEN
    DUP GB.GS @ 1- OVER GB.GS !
    1 SWAP GB.DIRTY ! ;

\ GAP-DELETE-FWD ( gb -- )
\   Delete character after gap (Delete key).  No-op if at end.
: GAP-DELETE-FWD  ( gb -- )
    DUP GB.GE @ OVER GB.SIZE @ >= IF DROP EXIT THEN
    \ Check if deleted char is LF — update cached line count
    DUP GB.BUF @ OVER GB.GE @ + C@ 10 = IF
        DUP GB.LINES @ 1- 1 MAX OVER GB.LINES !
    THEN
    DUP GB.GE @ 1+ OVER GB.GE !
    1 SWAP GB.DIRTY ! ;

\ GAP-CHAR@ ( pos gb -- char )
\   Read logical position.  pos is in 0..length-1.
VARIABLE _GCA-GB
: GAP-CHAR@  ( pos gb -- char )
    _GCA-GB !                    ( pos )
    DUP _GCA-GB @ GB.GS @ < IF
        _GCA-GB @ GB.BUF @ + C@
    ELSE
        _GCA-GB @ GB.GS @ -
        _GCA-GB @ GB.GE @ +
        _GCA-GB @ GB.BUF @ + C@
    THEN ;

\ GAP-CURSOR ( gb -- pos )
\   Return current cursor position (= gap start).
: GAP-CURSOR  ( gb -- pos )  GB.GS @ ;

\ =====================================================================
\  Section 3: Line Geometry Helpers
\ =====================================================================
\  For rendering and cursor movement we need to map between logical
\  positions and line/column pairs.

\ _GB-LINE-START ( line# gb -- pos )
\   Return the logical position of the start of line N (0-based).
\   Line 0 starts at pos 0.  Line N starts after the Nth LF.
VARIABLE _GLS-GB
: _GB-LINE-START  ( line# gb -- pos )
    _GLS-GB !                    ( line# )
    DUP 0= IF DROP 0 EXIT THEN  ( line# )
    0 SWAP                       ( pos n )
    0 DO                         ( pos )
        BEGIN
            DUP _GLS-GB @ GAP-LENGTH >= IF
                UNLOOP EXIT      \ hit end of text — return pos
            THEN
            DUP _GLS-GB @ GAP-CHAR@   ( pos char )
            10 =                       ( pos lf? )
            SWAP 1+ SWAP              ( pos+1 lf? )
        UNTIL
    LOOP ;                       ( pos — start of line N )

\ _GB-COUNT-LINES ( gb -- n )
\   Return cached line count.  O(1).
: _GB-COUNT-LINES  ( gb -- n )
    GB.LINES @ ;

\ _GB-POS-TO-LINE ( pos gb -- line# col# )
\   Convert a logical position to line/column.
VARIABLE _PTL-GB  VARIABLE _PTL-POS
: _GB-POS-TO-LINE  ( pos gb -- line col )
    _PTL-GB ! _PTL-POS !
    0 0                          ( line col )
    _PTL-GB @ GAP-LENGTH _PTL-POS @ MIN
    0 DO                         ( line col )
        I _PTL-POS @ = IF UNLOOP EXIT THEN
        I _PTL-GB @ GAP-CHAR@
        10 = IF
            SWAP 1+ SWAP DROP 0
        ELSE
            1+
        THEN
    LOOP ;

\ _GB-LINE-END ( line# gb -- pos )
\   Position just past the last char on line N (before the LF or EOF).
VARIABLE _GLE-GB
: _GB-LINE-END  ( line# gb -- pos )
    DUP _GLE-GB !
    _GB-LINE-START               ( pos — start of line )
    BEGIN
        DUP _GLE-GB @ GAP-LENGTH >= IF EXIT THEN
        DUP _GLE-GB @ GAP-CHAR@ 10 = IF EXIT THEN
        1+
    AGAIN ;

\ =====================================================================
\  Section 4: Editor Widget Data
\ =====================================================================
\  Editor data block layout (48 bytes):
\    +0   gb          — gap buffer pointer
\    +8   scroll-y    — first visible line (0-based)
\    +16  filename    — pointer to filename string (alloc'd)
\    +24  fname-len   — filename string length
\    +32  vis-lines   — number of visible text lines in client area
\    +40  vis-cols    — number of visible text columns

: ED.GB       ;                  \ +0
: ED.SCROLL  8 + ;              \ +8
: ED.FNAME  16 + ;              \ +16
: ED.FNLEN  24 + ;              \ +24
: ED.VLINES 32 + ;              \ +32
: ED.VCOLS  40 + ;              \ +40

48 CONSTANT /EDITOR-DATA

4  CONSTANT LINENUM-W            \ digits for line number column
2  CONSTANT LINENUM-PAD          \ padding after line numbers
4  CONSTANT ED-PAD               \ inner padding (pixels) around text area

\ Total left margin in pixels for the line number gutter
LINENUM-W LINENUM-PAD + TEXT-WIDTH CONSTANT GUTTER-PX

\ =====================================================================
\  Section 5: Editor Rendering
\ =====================================================================

VARIABLE _ER-AX   VARIABLE _ER-AY
VARIABLE _ER-W    VARIABLE _ER-H
VARIABLE _ER-WG   VARIABLE _ER-ED
VARIABLE _ER-GB
VARIABLE _ER-CURLINE  VARIABLE _ER-CURCOL
VARIABLE _ER-NLINES                      \ cached total line count

\ --- Line-start table (pre-computed once per frame) ---
\ Stores byte-offset of first char for each visible line.
\ Index 0 = scroll line, index 1 = scroll+1, etc.
\ Max 128 visible lines (800px / 8px font = 100, plus margin).
128 CONSTANT _LST-MAX
CREATE _LST-TBL _LST-MAX 8 * ALLOT    \ 128 cells
VARIABLE _LST-CNT                      \ entries actually filled

\ _BUILD-LINE-STARTS ( scroll-line count gb -- )
\   Single O(N) pass: scan from pos 0 counting newlines.
\   Record start-of-line offsets for lines [scroll..scroll+count).
\   Also computes cursor line/col as a side effect (stored in
\   _BLS-CUR-LINE / _BLS-CUR-COL) to avoid a separate O(pos) scan.
VARIABLE _BLS-GB  VARIABLE _BLS-WANT  VARIABLE _BLS-END
VARIABLE _BLS-CPOS                     \ cursor position to find
VARIABLE _BLS-CUR-LINE  VARIABLE _BLS-CUR-COL
VARIABLE _BLS-FOUND                    \ cursor found flag
: _BUILD-LINE-STARTS  ( scroll count gb -- )
    _BLS-GB !
    OVER + _LST-MAX MIN _BLS-END !   \ last line# to capture (excl)
    _BLS-WANT !                      \ first line# to capture
    0 _LST-CNT !
    _BLS-GB @ GAP-CURSOR _BLS-CPOS !  \ record cursor pos
    0 _BLS-CUR-LINE !  0 _BLS-CUR-COL !  0 _BLS-FOUND !
    0                                  ( cur-line )
    \ Line 0 always starts at pos 0
    DUP _BLS-WANT @ = IF
        0 _LST-TBL !  1 _LST-CNT !
    THEN
    0                                  ( cur-line col )
    _BLS-GB @ GAP-LENGTH             ( cur-line col total-len )
    0 DO                              ( cur-line col )
        \ Check if this position is the cursor
        _BLS-FOUND @ 0= IF
            I _BLS-CPOS @ = IF
                OVER _BLS-CUR-LINE !  DUP _BLS-CUR-COL !
                -1 _BLS-FOUND !
            THEN
        THEN
        I _BLS-GB @ GAP-CHAR@ 10 = IF
            DROP 0                    \ reset col to 0
            SWAP 1+ SWAP             ( cur-line+1 col=0 )
            OVER _BLS-WANT @ >= IF
                OVER _BLS-END @ < IF
                    OVER _BLS-WANT @ -  \ table index
                    8 * _LST-TBL +
                    I 1+ SWAP !        \ store pos (after the LF)
                    _LST-CNT @ 1+ _LST-CNT !
                THEN
            THEN
            \ Early exit if table full AND cursor found
            _LST-CNT @ _BLS-END @ _BLS-WANT @ - >= IF
                _BLS-FOUND @ IF
                    2DROP UNLOOP EXIT
                THEN
            THEN
        ELSE
            1+                        \ advance col
        THEN
    LOOP
    \ Cursor might be at end-of-buffer (past last char)
    _BLS-FOUND @ 0= IF
        OVER _BLS-CUR-LINE !  DUP _BLS-CUR-COL !
    THEN
    2DROP ;

\ _LST-GET ( screen-line -- pos )
\   Retrieve pre-computed line start for a screen line (0-based index).
: _LST-GET  ( idx -- pos )
    8 * _LST-TBL + @ ;

: _ED-SETUP  ( widget -- )
    DUP _ER-WG !
    DUP WG-ABS-X _ER-AX !
    DUP WG-ABS-Y _ER-AY !
    DUP WG.W @ _ER-W !
    DUP WG.H @ _ER-H !
    WG.DATA @ DUP _ER-ED !
    ED.GB @ _ER-GB ! ;

\ _ED-RENDER-LINENUM ( line-1based -- )
\   Right-justify a line number in LINENUM-W characters using GFX-TYPE.
: _ED-RENDER-LINENUM  ( n -- )
    U>STR                        ( addr len )
    LINENUM-W OVER - 0 MAX      ( addr len pad )
    DUP 0> IF
        0 DO S"  " CLR-TEXT-DIM GFX-TYPE LOOP
    ELSE DROP THEN
    CLR-TEXT-DIM GFX-TYPE ;

\ _ED-RENDER-LINE ( screen-line line# -- )
\   Render one line of text at y = screen-line * FONT-H + editor-abs-y.
\   line# is 0-based absolute line number.
\   Extracts the line into _LINE-BUF for a single GFX-TYPE call.
VARIABLE _ERL-X  VARIABLE _ERL-Y  VARIABLE _ERL-LN  VARIABLE _ERL-POS
VARIABLE _ERL-CNT  VARIABLE _ERL-SL
: _ED-RENDER-LINE  ( screen-line line# -- )
    _ERL-LN !                    ( screen-line )
    DUP _ERL-SL !                \ save screen-line for table lookup
    FONT-H * _ER-AY @ + ED-PAD + ( y-pixel with top pad )
    _ERL-Y !
    _ER-AX @ ED-PAD + _ERL-X !  ( -- )
    \ Draw line number (right-justified in gutter)
    _ERL-X @ GFX-CX !
    _ERL-Y @ GFX-CY !
    _ERL-LN @ 1+ _ED-RENDER-LINENUM
    \ Set text cursor after gutter
    _ERL-X @ GUTTER-PX + GFX-CX !
    \ Extract up to VCOLS chars into _LINE-BUF (use pre-built table)
    _ERL-SL @ _LST-GET _ERL-POS !
    0 _ERL-CNT !
    _ER-ED @ ED.VCOLS @ 0 DO
        _ERL-POS @ _ER-GB @ GAP-LENGTH >= IF LEAVE THEN
        _ERL-POS @ _ER-GB @ GAP-CHAR@     ( char )
        DUP 10 = IF DROP LEAVE THEN
        _LINE-BUF _ERL-CNT @ + C!
        _ERL-CNT @ 1+ _ERL-CNT !
        _ERL-POS @ 1+ _ERL-POS !
    LOOP
    \ Batch render the whole line in one GFX-TYPE call
    _ERL-CNT @ 0> IF
        _LINE-BUF _ERL-CNT @ CLR-EDIT-FG GFX-TYPE
    THEN ;

: EDITOR-RENDER  ( widget -- )
    _ED-SETUP
    \ Editor widget area is already at absolute coords (ax, ay, w, h).
    \ No WIN-CLIENT offsets needed — they are baked into WG-ABS-X/Y.
    \ Layout: text area = (ax, ay, w, h - statusH)  statusH = FONT-H+2
    \         gutter in left GUTTER-PX of text area
    \         status bar at (ax, ay+h-statusH, w, statusH)
    \ Text area background (white)
    CLR-EDIT-BG
    _ER-AX @
    _ER-AY @
    _ER-W @
    _ER-H @ FONT-H 2 + -
    FAST-RECT
    \ Line number gutter background (overwrites left strip)
    CLR-WIN-BG
    _ER-AX @ ED-PAD +
    _ER-AY @ ED-PAD +
    GUTTER-PX
    _ER-H @ FONT-H 2 + - ED-PAD 2* -
    FAST-RECT
    \ Build line-start table + cursor line/col (single O(N) pass)
    _ER-GB @ _GB-COUNT-LINES _ER-NLINES !
    _ER-ED @ ED.SCROLL @
    _ER-ED @ ED.VLINES @ _ER-NLINES @ _ER-ED @ ED.SCROLL @ - MIN
    _ER-GB @
    _BUILD-LINE-STARTS
    _BLS-CUR-COL @ _ER-CURCOL !
    _BLS-CUR-LINE @ _ER-CURLINE !
    \ Ensure cursor is visible (auto-scroll); rebuild table if changed
    _ER-CURLINE @ _ER-ED @ ED.SCROLL @ < IF
        _ER-CURLINE @ _ER-ED @ ED.SCROLL !
        _ER-ED @ ED.SCROLL @
        _ER-ED @ ED.VLINES @ _ER-NLINES @ _ER-ED @ ED.SCROLL @ - MIN
        _ER-GB @ _BUILD-LINE-STARTS
    THEN
    _ER-CURLINE @ _ER-ED @ ED.SCROLL @ _ER-ED @ ED.VLINES @ + >= IF
        _ER-CURLINE @ _ER-ED @ ED.VLINES @ - 1+ 0 MAX
        _ER-ED @ ED.SCROLL !
        _ER-ED @ ED.SCROLL @
        _ER-ED @ ED.VLINES @ _ER-NLINES @ _ER-ED @ ED.SCROLL @ - MIN
        _ER-GB @ _BUILD-LINE-STARTS
    THEN
    \ Render visible lines using pre-built table
    _LST-CNT @ 0 DO
        I I _ER-ED @ ED.SCROLL @ + _ED-RENDER-LINE
    LOOP
    \ Draw cursor (thin 2px bar)
    _ER-CURLINE @ _ER-ED @ ED.SCROLL @ - DUP 0 >= IF
        DUP _ER-ED @ ED.VLINES @ < IF
            FONT-H * _ER-AY @ + ED-PAD +             ( cursor-y )
            _ER-CURCOL @ FONT-W *
            _ER-AX @ ED-PAD + GUTTER-PX + +           ( cursor-y cursor-x )
            SWAP                                      ( cx cy )
            CLR-CURSOR ROT ROT 2 FONT-H FAST-RECT
        ELSE DROP THEN
    ELSE DROP THEN
    \ Status bar at bottom of widget
    CLR-BTN-FACE
    _ER-AX @ ED-PAD +
    _ER-AY @ _ER-H @ + FONT-H 2 + - ED-PAD -
    _ER-W @ ED-PAD 2* -
    FONT-H 2 +
    FAST-RECT
    \ Status text: filename  L#:C#  [modified]
    _ER-AX @ ED-PAD + 4 + GFX-CX !
    _ER-AY @ _ER-H @ + ED-PAD - FONT-H - 1 - GFX-CY !
    _ER-ED @ ED.FNAME @ _ER-ED @ ED.FNLEN @
    CLR-TEXT GFX-TYPE
    S"  L" CLR-TEXT GFX-TYPE
    _ER-CURLINE @ 1+ U>STR CLR-TEXT GFX-TYPE
    S" :C" CLR-TEXT GFX-TYPE
    _ER-CURCOL @ 1+ U>STR CLR-TEXT GFX-TYPE
    _ER-GB @ GB.DIRTY @ IF
        S"  [modified]" CLR-ERROR GFX-TYPE
    THEN ;

\ =====================================================================
\  Section 6: Editor Key Handling
\ =====================================================================

VARIABLE _EK-GB   VARIABLE _EK-ED  VARIABLE _EK-WG

: _ED-KEY-SETUP  ( widget -- )
    DUP _EK-WG !
    WG.DATA @ DUP _EK-ED !
    ED.GB @ _EK-GB ! ;

\ _ED-CURSOR-UP ( -- )
: _ED-CURSOR-UP
    _EK-GB @ GAP-CURSOR _EK-GB @ _GB-POS-TO-LINE  ( line col )
    SWAP 1- DUP 0< IF 2DROP EXIT THEN              ( col line-1 )
    DUP _EK-GB @ _GB-LINE-START                    ( col line-1 start )
    ROT                                              ( line-1 start col )
    \ Clamp col to line length
    2 PICK _EK-GB @ _GB-LINE-END                    ( line-1 start col end )
    3 PICK -                                         ( line-1 start col linelen )
    MIN                                              ( line-1 start col' )
    + NIP                                            ( new-pos )
    _EK-GB @ GAP-MOVE ;

\ _ED-CURSOR-DOWN ( -- )
: _ED-CURSOR-DOWN
    _EK-GB @ GAP-CURSOR _EK-GB @ _GB-POS-TO-LINE  ( line col )
    SWAP 1+ DUP _EK-GB @ _GB-COUNT-LINES >= IF 2DROP EXIT THEN
    DUP _EK-GB @ _GB-LINE-START                    ( col line+1 start )
    ROT                                              ( line+1 start col )
    2 PICK _EK-GB @ _GB-LINE-END
    3 PICK -
    MIN
    + NIP
    _EK-GB @ GAP-MOVE ;

\ _ED-CURSOR-HOME ( -- )
: _ED-CURSOR-HOME
    _EK-GB @ GAP-CURSOR _EK-GB @ _GB-POS-TO-LINE DROP
    _EK-GB @ _GB-LINE-START
    _EK-GB @ GAP-MOVE ;

\ _ED-CURSOR-END ( -- )
: _ED-CURSOR-END
    _EK-GB @ GAP-CURSOR _EK-GB @ _GB-POS-TO-LINE DROP
    _EK-GB @ _GB-LINE-END
    _EK-GB @ GAP-MOVE ;

\ _ED-PAGE-UP ( -- )
: _ED-PAGE-UP
    _EK-ED @ ED.VLINES @ 0 DO _ED-CURSOR-UP LOOP ;

\ _ED-PAGE-DOWN ( -- )
: _ED-PAGE-DOWN
    _EK-ED @ ED.VLINES @ 0 DO _ED-CURSOR-DOWN LOOP ;

\ _ED-SAVE-FILE ( -- )
\   Save gap buffer contents to the open file.
: _ED-SAVE-FILE
    _EK-ED @ ED.FNLEN @ 0= IF EXIT THEN   \ no filename
    \ Copy filename to NAMEBUF
    NAMEBUF 24 0 FILL
    _EK-ED @ ED.FNAME @ NAMEBUF
    _EK-ED @ ED.FNLEN @ 23 MIN CMOVE
    FIND-BY-NAME DUP -1 = IF DROP EXIT THEN
    DIRENT                               ( de )
    \ Build contiguous text at HERE from gap buffer
    _EK-GB @ GAP-LENGTH                  ( de len )
    DUP 0= IF 2DROP EXIT THEN
    \ Copy before-gap
    _EK-GB @ GB.BUF @ HERE _EK-GB @ GB.GS @ CMOVE
    \ Copy after-gap
    _EK-GB @ GB.BUF @ _EK-GB @ GB.GE @ +
    HERE _EK-GB @ GB.GS @ +
    _EK-GB @ GB.SIZE @ _EK-GB @ GB.GE @ - CMOVE
    \ Write to disk
    OVER DE.SEC DISK-SEC!
    HERE DISK-DMA!
    OVER DE.COUNT DISK-N!
    DISK-WRITE
    \ Update used_bytes: L! ( u32 addr -- )
    SWAP 28 + L!                         ( -- )
    FS-SYNC
    0 _EK-GB @ GB.DIRTY ! ;

: EDITOR-KEY  ( key widget -- consumed? )
    _ED-KEY-SETUP
    \ Ctrl-S = save
    DUP K-CTRL-S = IF DROP _ED-SAVE-FILE _EK-WG @ WG-DIRTY -1 EXIT THEN
    \ Arrow keys
    DUP K-UP    = IF DROP _ED-CURSOR-UP    _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-DOWN  = IF DROP _ED-CURSOR-DOWN  _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-LEFT  = IF DROP
        _EK-GB @ GAP-CURSOR 1- 0 MAX _EK-GB @ GAP-MOVE
        _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-RIGHT = IF DROP
        _EK-GB @ GAP-CURSOR 1+ _EK-GB @ GAP-LENGTH MIN
        _EK-GB @ GAP-MOVE
        _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-HOME  = IF DROP _ED-CURSOR-HOME  _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-END   = IF DROP _ED-CURSOR-END   _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-PGUP  = IF DROP _ED-PAGE-UP      _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-PGDN  = IF DROP _ED-PAGE-DOWN    _EK-WG @ WG-DIRTY -1 EXIT THEN
    \ Backspace
    DUP K-BS = IF DROP _EK-GB @ GAP-DELETE _EK-WG @ WG-DIRTY -1 EXIT THEN
    \ Delete (both 0x7F and ESC[3~)
    DUP K-DEL  = IF DROP _EK-GB @ GAP-DELETE-FWD _EK-WG @ WG-DIRTY -1 EXIT THEN
    DUP K-DEL2 = IF DROP _EK-GB @ GAP-DELETE-FWD _EK-WG @ WG-DIRTY -1 EXIT THEN
    \ Enter
    DUP K-ENTER = IF DROP 10 _EK-GB @ GAP-INSERT _EK-WG @ WG-DIRTY -1 EXIT THEN
    \ Printable ASCII (32-126)
    DUP 32 >= OVER 126 <= AND IF
        _EK-GB @ GAP-INSERT _EK-WG @ WG-DIRTY -1 EXIT THEN
    \ Unknown key — not consumed
    DROP 0 ;

\ =====================================================================
\  Section 7: Editor Widget Factory
\ =====================================================================

\ _ED-DTOR ( widget -- )
\   Destructor: free gap buffer and filename.
\   WG-DESTROY frees WG.DATA block after calling this.
: _ED-DTOR  ( widget -- )
    WG.DATA @ DUP 0= IF DROP EXIT THEN
    DUP ED.GB @ ?DUP IF GAP-FREE THEN
    DUP ED.FNAME @ ?DUP IF FREE THEN
    DROP ;                       \ clean stack; data block freed by WG-DESTROY

\ EDITOR ( x y w h parent -- widget )
\   Create an editor widget (child of a window or panel).
\   Caller should set filename and load content separately.
: EDITOR
    _F-PAR ! _F-H ! _F-W ! _F-Y ! _F-X !
    WGT-EDITOR WG-ALLOC
    DUP 0= IF EXIT THEN
    _F-X @ _F-Y @ _F-W @ _F-H @ WG-SET-RECT
    WG-MAKE-FOCUSABLE
    \ Allocate editor data
    /EDITOR-DATA ALLOCATE IF DROP 0 EXIT THEN  ( widget data )
    DUP /EDITOR-DATA 0 FILL
    OVER WG.DATA !                             ( widget data -- but data consumed by OVER/! )
    \ After OVER WG.DATA !: stack is ( widget )
    \ Retrieve data pointer back from widget for field init
    DUP WG.DATA @                      ( widget data )
    \ Init gap buffer
    GAP-INIT OVER ED.GB !
    \ Compute visible lines/cols from widget height
    \ Visible area = widget height - status bar (FONT-H+2)
    _F-H @ FONT-H 2 + - ED-PAD 2* - FONT-H /   ( widget data vis-lines )
    OVER ED.VLINES !
    _F-W @ GUTTER-PX - ED-PAD 2* - FONT-W /     ( widget data vis-cols )
    OVER ED.VCOLS !
    0 OVER ED.SCROLL !
    DROP                                ( widget )
    ['] EDITOR-RENDER OVER WG.RENDER !
    ['] EDITOR-KEY OVER WG.ONKEY !
    ['] _ED-DTOR OVER WG.DTOR !
    _F-PAR @ OVER SWAP WG-ADD-CHILD ;

\ _ED-SET-FILENAME ( addr len widget -- )
\   Copy filename string into editor data.
VARIABLE _ESFN-ED
: _ED-SET-FILENAME  ( addr len widget -- )
    WG.DATA @ _ESFN-ED !        ( addr len )
    DUP ALLOCATE IF DROP 2DROP EXIT THEN   ( addr len copy )
    >R 2DUP R@ SWAP CMOVE       ( addr len  R: copy )
    NIP                          ( len  R: copy )
    R>                           ( len copy )
    _ESFN-ED @ ED.FNAME !
    _ESFN-ED @ ED.FNLEN ! ;

\ _ED-LOAD-FILE ( widget -- )
\   Load file content into the editor's gap buffer.
VARIABLE _ELF-SZ  VARIABLE _ELF-GB
: _ED-LOAD-FILE  ( widget -- )
    DUP WG.DATA @ ED.FNLEN @ 0= IF DROP EXIT THEN
    \ Copy filename to NAMEBUF
    DUP WG.DATA @ >R
    NAMEBUF 24 0 FILL
    R@ ED.FNAME @ NAMEBUF R@ ED.FNLEN @ 23 MIN CMOVE
    R> ED.GB @ _ELF-GB !        ( widget -- consumed )
    \ Find file
    FIND-BY-NAME DUP -1 = IF DROP EXIT THEN
    DIRENT DUP DE.USED DUP 0= IF DROP DROP EXIT THEN
    _ELF-SZ !                    ( de )
    \ Read file data into HERE
    DUP DE.SEC DISK-SEC!
    HERE DISK-DMA!
    DE.COUNT DISK-N!
    DISK-READ
    \ Insert file data into gap buffer
    _ELF-SZ @ 0 DO
        HERE I + C@ _ELF-GB @ GAP-INSERT
    LOOP
    \ Move cursor to start
    0 _ELF-GB @ GAP-MOVE
    0 _ELF-GB @ GB.DIRTY ! ;

\ =====================================================================
\  Section 8: EDIT — Open File in Editor Window
\ =====================================================================

VARIABLE _EDIT-ROOT
VARIABLE _EDIT-WIN
VARIABLE _EDIT-WG
CREATE _EDIT-FNAME 24 ALLOT     \ local copy of filename
VARIABLE _EDIT-FNLEN

\ _DESKTOP-RENDER ( widget -- )
\   Root widget render: fills entire screen with desktop color.
\   Ensures both double-buffers get the desktop background.
: _DESKTOP-RENDER ( widget -- )
    DROP CLR-DESKTOP 0 0 800 600 FAST-RECT ;

\ EDIT ( "filename" -- )
\   Open a file in a full-screen editor window.
\   Uses EKEY loop; Ctrl-S saves; Esc closes.
: EDIT  ( "filename" -- )
    \ Parse filename from input
    BL WORD DUP C@ 0= IF DROP ." Usage: EDIT <filename>" CR EXIT THEN
    DUP C@ SWAP 1+              ( len addr )
    SWAP                         ( addr len )
    \ Copy filename to local buffer (BL WORD result is transient)
    23 MIN DUP _EDIT-FNLEN !     ( addr clen )
    _EDIT-FNAME SWAP CMOVE       ( -- )
    \ Init graphics
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    \ Root
    WGT-ROOT WG-ALLOC DUP _EDIT-ROOT !
    0 0 800 600 WG-SET-RECT DROP
    ['] _DESKTOP-RENDER _EDIT-ROOT @ WG.RENDER !
    \ Editor window — full screen with margins
    10 10 780 580
    _EDIT-FNAME _EDIT-FNLEN @
    _EDIT-ROOT @ WINDOW
    _EDIT-WIN !
    \ Editor widget fills the window client area
    WIN-CLIENT-X WIN-CLIENT-Y
    780 WIN-CLIENT-X 2* - WIN-BORDER 2* -
    580 WIN-CLIENT-Y - WIN-BORDER 2* -
    _EDIT-WIN @ EDITOR
    _EDIT-WG !
    \ Set filename and load
    _EDIT-FNAME _EDIT-FNLEN @ _EDIT-WG @ _ED-SET-FILENAME
    _EDIT-WG @ _ED-LOAD-FILE
    _EDIT-WG @ FOCUS
    \ Render both buffers so double-buffering shows consistent content
    _EDIT-ROOT @ MARK-ALL-DIRTY
    _EDIT-ROOT @ RENDER-TREE
    FB-SWAP
    _EDIT-ROOT @ MARK-ALL-DIRTY
    _EDIT-ROOT @ RENDER-TREE
    FB-SWAP
    \ Event loop — use EKEY for arrow keys
    BEGIN
        EKEY
        DUP 27 = IF             \ ESC — exit editor
            DROP
            \ Exit editor
            0 FOCUS-WIDGET !
            0 WIN-COUNT !  -1 WIN-ACTIVE !
            _EDIT-ROOT @ WG-FREE-SUBTREE
            EXIT
        THEN
        \ Deliver to editor widget
        DUP _EDIT-WG @ EDITOR-KEY IF
            DROP
            \ Re-render — copy front→back so we only repaint what changed
            _EDIT-WG @ WG-DIRTY
            _EDIT-ROOT @ RENDER-TREE
            FB-SWAP
            FB-COPY-BACK
        ELSE
            DROP
        THEN
    AGAIN ;

\ =====================================================================
\  Section 9: Smoke Test
\ =====================================================================

VARIABLE _ET-GB

: KALKI-EDITOR-TEST  ( -- )
    \ === Gap buffer tests ===
    GAP-INIT DUP _ET-GB !
    DUP 0<> IF ." gap-init=ok " ELSE ." gap-init=FAIL " THEN

    \ Insert "Hello"
    72 OVER GAP-INSERT   \ H
    101 OVER GAP-INSERT  \ e
    108 OVER GAP-INSERT  \ l
    108 OVER GAP-INSERT  \ l
    111 OVER GAP-INSERT  \ o
    DUP GAP-LENGTH 5 = IF ." len=ok " ELSE ." len=FAIL " THEN

    \ Read back
    0 OVER GAP-CHAR@ 72 = IF ." H=ok " ELSE ." H=FAIL " THEN
    4 OVER GAP-CHAR@ 111 = IF ." o=ok " ELSE ." o=FAIL " THEN

    \ Move cursor to position 2, insert 'X'
    2 OVER GAP-MOVE
    88 OVER GAP-INSERT   \ X
    DUP GAP-LENGTH 6 = IF ." ins=ok " ELSE ." ins=FAIL " THEN
    2 OVER GAP-CHAR@ 88 = IF ." X=ok " ELSE ." X=FAIL " THEN

    \ Backspace at position 3 (deletes 'X')
    DUP GAP-DELETE
    DUP GAP-LENGTH 5 = IF ." del=ok " ELSE ." del=FAIL " THEN
    2 OVER GAP-CHAR@ 108 = IF ." l=ok " ELSE ." l=FAIL " THEN

    \ Insert newline
    5 OVER GAP-MOVE
    10 OVER GAP-INSERT   \ LF
    DUP _GB-COUNT-LINES 2 = IF ." lines=ok " ELSE ." lines=FAIL " THEN

    \ Line geometry
    0 OVER _GB-LINE-START 0 = IF ." ls0=ok " ELSE ." ls0=FAIL " THEN
    1 OVER _GB-LINE-START 6 = IF ." ls1=ok " ELSE ." ls1=FAIL " THEN

    \ Cursor position → line/col
    3 OVER _GB-POS-TO-LINE 3 = SWAP 0 = AND
    IF ." pos2lc=ok " ELSE ." pos2lc=FAIL " THEN

    \ Free
    GAP-FREE
    CR

    \ === EKEY constants check ===
    K-UP 256 = K-DOWN 257 = AND K-LEFT 259 = AND
    IF ." ekey-consts=ok " ELSE ." ekey-consts=FAIL " THEN

    \ === Editor widget test (graphical) ===
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    0 FOCUS-WIDGET !
    800 600 KALKI-GFX-INIT
    KALKI-PAL-INIT
    WGT-ROOT WG-ALLOC DUP _EDIT-ROOT !
    0 0 800 600 WG-SET-RECT DROP
    CLR-DESKTOP 0 0 800 600 FAST-RECT
    \ Create editor window
    20 20 760 560 S" Test Editor" _EDIT-ROOT @ WINDOW
    _EDIT-WIN !
    \ Editor widget
    WIN-CLIENT-X WIN-CLIENT-Y
    760 WIN-CLIENT-X 2* - WIN-BORDER 2* -
    560 WIN-CLIENT-Y - WIN-BORDER 2* -
    _EDIT-WIN @ EDITOR
    _EDIT-WG !
    S" test.txt" _EDIT-WG @ _ED-SET-FILENAME
    \ Insert some text programmatically
    _EDIT-WG @ WG.DATA @ ED.GB @  _ET-GB !
    S" First line of text" 0 DO
        DUP I + C@ _ET-GB @ GAP-INSERT
    LOOP DROP
    10 _ET-GB @ GAP-INSERT
    S" Second line here" 0 DO
        DUP I + C@ _ET-GB @ GAP-INSERT
    LOOP DROP
    10 _ET-GB @ GAP-INSERT
    S" Third line - hello Kalki!" 0 DO
        DUP I + C@ _ET-GB @ GAP-INSERT
    LOOP DROP
    0 _ET-GB @ GAP-MOVE
    _EDIT-WG @ FOCUS
    _EDIT-ROOT @ MARK-ALL-DIRTY
    _EDIT-ROOT @ RENDER-TREE
    FB-SWAP
    \ Verify
    _EDIT-WG @ WG.TYPE @ WGT-EDITOR = IF ." widget=ok " ELSE ." widget=FAIL " THEN
    _ET-GB @ _GB-COUNT-LINES 3 = IF ." 3lines=ok " ELSE ." 3lines=FAIL " THEN
    _EDIT-WG @ WG.DATA @ ED.VLINES @ 0> IF ." vlines=ok " ELSE ." vlines=FAIL " THEN
    CR
    \ Cleanup
    0 FOCUS-WIDGET !
    0 WIN-COUNT !  -1 WIN-ACTIVE !
    _EDIT-ROOT @ WG-FREE-SUBTREE
    ." kalki-editor test complete" CR ;
