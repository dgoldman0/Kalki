\ =====================================================================
\  kalki-font.f — Kalki GUI Framework: Scalable Font Bridge
\ =====================================================================
\  Bridges the Akashic font stack (ttf.f, raster.f, cache.f, layout.f)
\  into Kalki's widget rendering pipeline.
\
\  When a TTF is loaded via KF-INIT, this module REDEFINES GFX-CHAR
\  and GFX-TYPE so that ALL existing widget code automatically renders
\  with scalable TrueType glyphs — zero changes needed in consumers.
\
\  Provides:
\    KF-INIT         — parse a TTF from memory, init cache + layout
\    KF-SIZE!         — set rendering size (8–64 px)
\    KF-TEXT-W        — measure string width in pixels
\    KF-LINE-H        — current line height in pixels
\    KF-ASCENDER      — scaled ascender in pixels
\    KF-ACTIVE?       — true if a TTF font is loaded
\    GFX-CHAR          — [REDEFINED] renders TTF glyph when active
\    GFX-TYPE          — [REDEFINED] renders TTF string when active
\
\  Falls back to the 8×8 bitmap font when no TTF is loaded.
\
\  Load order: after kalki-gfx.f, before kalki-widget.f
\ =====================================================================

PROVIDED kalki-font.f
REQUIRE kalki-gfx.f

\ Pre-load Akashic dependencies in flat order to stay within the
\ 5-level _LD-STK nesting limit.  Each module's internal REQUIREs
\ find their deps already PROVIDED and skip, preventing deep chains
\ like cache→raster→bezier→fp16-ext→fp16 from overflowing the stack.
REQUIRE math/fp16.f
REQUIRE math/fp16-ext.f
REQUIRE math/fixed.f
REQUIRE math/bezier.f
REQUIRE font/ttf.f
REQUIRE font/raster.f
REQUIRE font/cache.f
REQUIRE text/utf8.f
REQUIRE text/layout.f

\ =====================================================================
\  State
\ =====================================================================

VARIABLE _KF-ACTIVE    \ true if TTF loaded and parsed
0 _KF-ACTIVE !

VARIABLE _KF-SIZE      \ current pixel size
12 _KF-SIZE !          \ default 12px

: KF-ACTIVE?  ( -- flag )  _KF-ACTIVE @ ;

\ =====================================================================
\  Save original bitmap GFX-CHAR and GFX-TYPE before redefining
\ =====================================================================
\  We save their XTs so the new definitions can fall back.

' GFX-CHAR CONSTANT _KF-BITMAP-CHAR
' GFX-TYPE CONSTANT _KF-BITMAP-TYPE

\ =====================================================================
\  Initialisation
\ =====================================================================
\  KF-INIT ( ttf-addr ttf-len -- flag )
\    Parse TTF tables and set up for rendering.
\    Returns TRUE on success, FALSE on parse failure.
\    ttf-len is ignored — TTF-BASE! takes only the base address.

: KF-INIT  ( ttf-addr ttf-len -- flag )
    DROP                               \ len unused by ttf.f
    TTF-BASE!
    TTF-PARSE-HEAD  0= IF FALSE EXIT THEN
    TTF-PARSE-MAXP  0= IF FALSE EXIT THEN
    TTF-PARSE-HHEA  0= IF FALSE EXIT THEN
    TTF-PARSE-HMTX  0= IF FALSE EXIT THEN
    TTF-PARSE-LOCA  0= IF FALSE EXIT THEN
    TTF-PARSE-GLYF  0= IF FALSE EXIT THEN
    TTF-PARSE-CMAP  0= IF FALSE EXIT THEN
    \ Init layout engine with current size
    _KF-SIZE @ LAY-SCALE!
    \ Flush glyph cache (might have stale data from previous font)
    GC-FLUSH
    TRUE _KF-ACTIVE !
    TRUE ;

\ =====================================================================
\  Size control
\ =====================================================================

: KF-SIZE!  ( pixel-size -- )
    DUP _KF-SIZE !
    KF-ACTIVE? IF LAY-SCALE! THEN ;

: KF-SIZE@  ( -- pixel-size )  _KF-SIZE @ ;

\ =====================================================================
\  Metrics (delegated to layout.f when active, bitmap fallback)
\ =====================================================================

: KF-TEXT-W  ( addr len -- pixels )
    KF-ACTIVE? IF
        LAY-TEXT-WIDTH
    ELSE
        NIP 8 *                    \ 8×8 bitmap: 8 pixels per char
    THEN ;

: KF-LINE-H  ( -- pixels )
    KF-ACTIVE? IF
        LAY-LINE-HEIGHT
    ELSE
        11                         \ matches Kalki LINE-H constant
    THEN ;

: KF-ASCENDER  ( -- pixels )
    KF-ACTIVE? IF
        LAY-ASCENDER
    ELSE
        8                          \ bitmap font ascender
    THEN ;

: KF-DESCENDER  ( -- pixels )
    KF-ACTIVE? IF
        LAY-DESCENDER
    ELSE
        0                          \ bitmap font has no descender
    THEN ;

: KF-CHAR-W  ( codepoint -- pixels )
    KF-ACTIVE? IF
        LAY-CHAR-WIDTH
    ELSE
        DROP 8                     \ 8-pixel fixed width
    THEN ;

\ =====================================================================
\  Glyph rendering — blit a cached bitmap to framebuffer in RGB565
\ =====================================================================
\  The cache stores 1-byte-per-pixel bitmaps (0x00 = bg, 0xFF = fg).
\  We blit non-zero pixels as the foreground color.

VARIABLE _KF-BX   VARIABLE _KF-BY   VARIABLE _KF-CLR
VARIABLE _KF-BMP  VARIABLE _KF-BW   VARIABLE _KF-BH

: _KF-BLIT-GLYPH  ( bmp-addr w h x y color -- )
    _KF-CLR !  _KF-BY !  _KF-BX !
    _KF-BH !  _KF-BW !  _KF-BMP !
    _KF-BH @ 0 DO                     \ for each row
        _KF-BW @ 0 DO                 \ for each column
            _KF-BMP @                 ( bmp-base )
            J _KF-BW @ * I + +        ( pixel-addr )
            C@ IF                     \ non-zero = foreground
                _KF-CLR @
                _KF-BX @ I +
                _KF-BY @ J +
                GFX-PIXEL!
            THEN
        LOOP
    LOOP ;

\ =====================================================================
\  GFX-CHAR — [REDEFINED] transparent TTF upgrade
\ =====================================================================
\  Same stack effect as original: ( char x y color -- )
\  When TTF is active, looks up glyph in cache and blits.
\  When no TTF, falls back to original bitmap GFX-CHAR.

: GFX-CHAR  ( char x y color -- )
    KF-ACTIVE? 0= IF
        _KF-BITMAP-CHAR EXECUTE EXIT
    THEN
    >R >R >R                           \ save color y x ( R: color y x )
    TTF-CMAP-LOOKUP                    ( glyph-id )
    _KF-SIZE @ GC-GET                  ( bmp w h | 0 0 0 )
    DUP 0= IF
        DROP 2DROP R> R> R> DROP 2DROP EXIT  \ render failed — skip
    THEN
    R> R> R>                           ( bmp w h x y color )
    _KF-BLIT-GLYPH ;

\ =====================================================================
\  GFX-TYPE — [REDEFINED] transparent TTF upgrade
\ =====================================================================
\  Same stack effect as original: ( addr len color -- )
\  Uses GFX-CX / GFX-CY as cursor (callers set these before calling).
\  When TTF is active, decodes UTF-8, renders cached glyphs, advances
\  cursor by actual glyph width.
\  When no TTF, falls back to original bitmap GFX-TYPE.

: GFX-TYPE  ( addr len color -- )
    KF-ACTIVE? 0= IF
        _KF-BITMAP-TYPE EXECUTE EXIT
    THEN
    _KF-CLR !                          ( addr len )
    DUP 0= IF 2DROP EXIT THEN
    BEGIN DUP 0 > WHILE
        UTF8-DECODE                    ( cp addr' len' )
        ROT                           ( addr' len' cp )
        DUP >R                        ( addr' len' cp )
        GFX-CX @ GFX-CY @  _KF-CLR @
        GFX-CHAR                       ( addr' len' )
        R> KF-CHAR-W                   ( addr' len' advance )
        GFX-CX @ + GFX-CX !           \ advance cursor by glyph width
    REPEAT
    2DROP ;

\ =====================================================================
\  Smoke test
\ =====================================================================

: KALKI-FONT-TEST  ( -- )
    ." KF: active=" KF-ACTIVE? . CR
    ." KF: size=" KF-SIZE@ . CR
    ." KF: line-h=" KF-LINE-H . CR
    S" Hello" KF-TEXT-W
    ." KF: 'Hello' width=" . CR
    ." PASS: kalki-font smoke" CR ;
