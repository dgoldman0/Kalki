\ kalki-autoexec.f — Kalki GUI Framework boot script
\ =====================================================================
\  Replaces the default autoexec.f on the Kalki disk image.
\  Loaded automatically by KDOS at startup.
\
\  Boot chain:
\    BIOS → FSLOAD kdos.f → KDOS → autoexec.f (this file)
\    → REQUIRE graphics.f → REQUIRE kalki-gfx.f → REQUIRE kalki-color.f
\    → REQUIRE kalki-widget.f
\ =====================================================================

PROVIDED autoexec.f

\ ── Skip networking for development ──────────────────────────────────
\ DHCP blocks when NIC is present but no network is connected.
\ Uncomment the block below when running with --nic.
\ : AUTOEXEC-NET  ( -- )
\     NET-STATUS DUP 128 AND 0= IF DROP EXIT THEN
\     4 AND 0= IF EXIT THEN
\     ." DHCP..." CR
\     DHCP-START IF ." Network ready." CR
\     ELSE ." DHCP failed." CR THEN ;
\ AUTOEXEC-NET

\ ── Switch to userland dictionary ────────────────────────────────────
: _ENTER-UL  XMEM? IF ENTER-USERLAND THEN ;
_ENTER-UL

\ ── Load Kalki modules ───────────────────────────────────────────────
REQUIRE graphics.f
REQUIRE tools.f
REQUIRE kalki-gfx.f
REQUIRE kalki-color.f
REQUIRE kalki-widget.f
REQUIRE kalki-basic.f
REQUIRE kalki-window.f
REQUIRE kalki-editor.f

\ ── Banner ───────────────────────────────────────────────────────────
." Kalki GUI Framework loaded." CR
." Commands: KALKI-GFX-TEST  KALKI-COLOR-TEST" CR
."           KALKI-WIDGET-TEST  KALKI-BASIC-TEST" CR
."           KALKI-WINDOW-TEST  KALKI-EDITOR-TEST" CR
."           EDIT <filename>" CR
