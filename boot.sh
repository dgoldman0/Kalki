#!/usr/bin/env bash
# =====================================================================
#  boot.sh — Build disk image and boot Megapad-64 with Kalki GUI
# =====================================================================
#
#  Usage:
#    ./boot.sh              # Interactive with framebuffer window
#    ./boot.sh --test       # Run smoke tests and exit
#
#  Boot chain:
#    BIOS → FSLOAD kdos.f → KDOS → autoexec.f
#    → REQUIRE graphics.f → REQUIRE kalki-gfx.f → REQUIRE kalki-color.f
#    → REPL
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMU_DIR="$SCRIPT_DIR/emu"
DISK_IMG="$SCRIPT_DIR/kalki.img"
SCALE=3

# Parse flags
TEST_MODE=""
EXTRA_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --test)     TEST_MODE=1 ;;
        *)          EXTRA_ARGS+=("$arg") ;;
    esac
done

# ── Step 1: Build minimal disk image (KDOS + graphics + Kalki only) ──
echo "=== Building Kalki disk image ==="
cd "$EMU_DIR"

python3 -c "
from pathlib import Path
from diskutil import MP64FS, FTYPE_FORTH

KALKI  = Path('$SCRIPT_DIR')
AKASHIC = KALKI / 'akashic' / 'akashic'

fs = MP64FS()
fs.format()

# ── System (root dir) ────────────────────────────────────────────────
fs.inject_file('kdos.f', Path('kdos.f').read_bytes(),
               ftype=FTYPE_FORTH, flags=0x02)
fs.inject_file('graphics.f', Path('graphics.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('tools.f', Path('tools.f').read_bytes(),
               ftype=FTYPE_FORTH)

# ── Akashic libraries (in subdirectories) ────────────────────────────
# math/
fs.mkdir('math')
for name in ['fp16.f', 'fp16-ext.f', 'fixed.f', 'bezier.f']:
    fs.inject_file(name, (AKASHIC / 'math' / name).read_bytes(),
                   ftype=FTYPE_FORTH, path='math')

# font/
fs.mkdir('font')
for name in ['ttf.f', 'raster.f', 'cache.f']:
    fs.inject_file(name, (AKASHIC / 'font' / name).read_bytes(),
                   ftype=FTYPE_FORTH, path='font')

# text/
fs.mkdir('text')
for name in ['utf8.f', 'layout.f']:
    fs.inject_file(name, (AKASHIC / 'text' / name).read_bytes(),
                   ftype=FTYPE_FORTH, path='text')

# ── Kalki modules (root dir) ────────────────────────────────────────
for name in ['kalki-gfx.f', 'kalki-color.f', 'kalki-widget.f',
             'kalki-basic.f', 'kalki-window.f', 'kalki-editor.f',
             'kalki-scroll.f', 'kalki-menu.f', 'kalki-font.f',
             'kalki-app.f', 'filemgr.f', 'kalki-desktop.f']:
    fs.inject_file(name, (KALKI / name).read_bytes(),
                   ftype=FTYPE_FORTH)

# ── Autoexec ─────────────────────────────────────────────────────────
fs.inject_file('autoexec.f',
               (KALKI / 'kalki-autoexec.f').read_bytes(),
               ftype=FTYPE_FORTH)

n = sum(1 for _ in fs.list_files())
fs.save('$DISK_IMG')
print(f'Kalki disk: {n} files (3 dirs)')
"

echo "=== Disk contents ==="
python3 diskutil.py ls "$DISK_IMG"

# ── Step 2: Boot ─────────────────────────────────────────────────────
echo ""
echo "=== Booting Megapad-64 ==="

if [[ -n "$TEST_MODE" ]]; then
    echo "    Mode: smoke test"
    cd "$EMU_DIR"
    python3 -c "
import sys, os
sys.path.insert(0, '.')
from accel_wrapper import Megapad64, HaltError
from system import MegapadSystem
from asm import assemble

with open('bios.asm') as f:
    bios_code = assemble(f.read())

sys_emu = MegapadSystem(ram_size=1024*1024,
                        storage_image='$DISK_IMG',
                        ext_mem_size=16*1024*1024)
out_fd = sys.stdout.fileno()
sys_emu.uart.on_tx = lambda b: os.write(out_fd, bytes([b]))
sys_emu.load_binary(0, bios_code)
sys_emu.boot()

def run_until_idle(max_steps=2_000_000_000):
    total = 0
    idle_count = 0
    while total < max_steps:
        if sys_emu.cpu.halted: break
        if sys_emu.cpu.idle and not sys_emu.uart.has_rx_data:
            idle_count += 1
            if idle_count > 5: break
            sys_emu.run_batch(10_000); total += 10_000; continue
        idle_count = 0
        batch = sys_emu.run_batch(min(500_000, max_steps - total))
        total += max(batch, 1)
    return total

run_until_idle()
for cmd in ['KALKI-GFX-TEST', 'KALKI-COLOR-TEST', 'KALKI-WIDGET-TEST', 'KALKI-BASIC-TEST', 'KALKI-FONT-TEST', 'KALKI-WINDOW-TEST', 'KALKI-EDITOR-TEST', 'KALKI-SCROLL-TEST', 'KALKI-MENU-TEST', 'KALKI-DESKTOP-TEST']:
    sys_emu.uart.inject_input((cmd + '\n').encode())
    run_until_idle(500_000_000)

print()
print('=== Smoke tests complete ===')
"
else
    echo "    Type KALKI-BASIC-TEST to test widgets (or GFX/COLOR/WIDGET)."
    echo "    Ctrl-C to exit."
    echo ""
    cd "$EMU_DIR"
    python3 cli.py --bios bios.asm --storage "$DISK_IMG" \
        --extmem 16 --display --scale "$SCALE" \
        "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
fi
