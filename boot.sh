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

fs = MP64FS()
fs.format()

# KDOS -- must be first Forth file (BIOS auto-loads it)
fs.inject_file('kdos.f', Path('kdos.f').read_bytes(),
               ftype=FTYPE_FORTH, flags=0x02)

# Dependencies
fs.inject_file('graphics.f', Path('graphics.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('tools.f', Path('tools.f').read_bytes(),
               ftype=FTYPE_FORTH)

# Kalki modules
fs.inject_file('kalki-gfx.f',
               Path('$SCRIPT_DIR/kalki-gfx.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('kalki-color.f',
               Path('$SCRIPT_DIR/kalki-color.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('kalki-widget.f',
               Path('$SCRIPT_DIR/kalki-widget.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('kalki-basic.f',
               Path('$SCRIPT_DIR/kalki-basic.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('kalki-window.f',
               Path('$SCRIPT_DIR/kalki-window.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('kalki-editor.f',
               Path('$SCRIPT_DIR/kalki-editor.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('kalki-scroll.f',
               Path('$SCRIPT_DIR/kalki-scroll.f').read_bytes(),
               ftype=FTYPE_FORTH)
fs.inject_file('kalki-desktop.f',
               Path('$SCRIPT_DIR/kalki-desktop.f').read_bytes(),
               ftype=FTYPE_FORTH)

# Autoexec (loads Kalki modules on boot)
fs.inject_file('autoexec.f',
               Path('$SCRIPT_DIR/kalki-autoexec.f').read_bytes(),
               ftype=FTYPE_FORTH)

fs.save('$DISK_IMG')
print(f'Kalki disk: 12 files')
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
for cmd in ['KALKI-GFX-TEST', 'KALKI-COLOR-TEST', 'KALKI-WIDGET-TEST', 'KALKI-BASIC-TEST', 'KALKI-WINDOW-TEST', 'KALKI-EDITOR-TEST', 'KALKI-SCROLL-TEST', 'KALKI-DESKTOP-TEST']:
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
