#!/usr/bin/env bash
# =====================================================================
#  boot.sh — Build disk image and boot Megapad-64 with Kalki modules
# =====================================================================
#
#  Usage:
#    ./boot.sh              # Interactive terminal (text-only)
#    ./boot.sh --display    # With framebuffer window (pygame)
#    ./boot.sh --test       # Run smoke test and exit
#
#  What it does:
#    1. Builds a sample MP64FS disk image (emu/diskutil.py sample)
#    2. Injects kalki-gfx.f and kalki-color.f as Forth modules
#    3. Injects kalki-autoexec.f as autoexec.f (replaces default)
#    4. Boots the emulator with --storage pointing to the image
#
#  The boot chain:
#    BIOS → FSLOAD kdos.f → KDOS startup → autoexec.f
#    → REQUIRE graphics.f → REQUIRE kalki-gfx.f → REQUIRE kalki-color.f
#    → REPL (or test commands)
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMU_DIR="$SCRIPT_DIR/emu"
DISK_IMG="$SCRIPT_DIR/kalki.img"

# Parse flags
DISPLAY_FLAG=""
TEST_MODE=""
EXTRA_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --display)  DISPLAY_FLAG="--display" ;;
        --test)     TEST_MODE=1 ;;
        *)          EXTRA_ARGS+=("$arg") ;;
    esac
done

# ── Step 1: Build base disk image ────────────────────────────────────
echo "=== Building disk image ==="
cd "$EMU_DIR"
python3 diskutil.py sample -o "$DISK_IMG"
echo "    Base image: $DISK_IMG"

# ── Step 2: Inject Kalki modules ─────────────────────────────────────
echo "=== Injecting Kalki modules ==="

# Inject our Forth modules
python3 diskutil.py inject "$DISK_IMG" "$SCRIPT_DIR/kalki-gfx.f" \
    -n kalki-gfx.f -t forth
echo "    + kalki-gfx.f"

python3 diskutil.py inject "$DISK_IMG" "$SCRIPT_DIR/kalki-color.f" \
    -n kalki-color.f -t forth
echo "    + kalki-color.f"

# Replace autoexec.f with our version that loads Kalki modules
python3 diskutil.py rm "$DISK_IMG" autoexec.f 2>/dev/null || true
python3 diskutil.py inject "$DISK_IMG" "$SCRIPT_DIR/kalki-autoexec.f" \
    -n autoexec.f -t forth
echo "    + autoexec.f (kalki)"

# ── Step 3: Show disk contents ───────────────────────────────────────
echo "=== Disk contents ==="
python3 diskutil.py ls "$DISK_IMG"

# ── Step 4: Boot ─────────────────────────────────────────────────────
echo ""
echo "=== Booting Megapad-64 ==="

if [[ -n "$TEST_MODE" ]]; then
    echo "    Mode: smoke test (headless)"
    cd "$EMU_DIR"
    python3 -c "
import sys
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
import os
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

# Run both smoke tests
for cmd in ['KALKI-GFX-TEST', 'KALKI-COLOR-TEST']:
    sys_emu.uart.inject_input((cmd + '\n').encode())
    run_until_idle(500_000_000)

print()
print('=== All smoke tests passed ===')
"
else
    echo "    Mode: interactive"
    echo "    Type 'KALKI-GFX-TEST' or 'KALKI-COLOR-TEST' to test."
    echo "    Ctrl-C to exit."
    echo ""
    cd "$EMU_DIR"
    python3 cli.py --bios bios.asm --storage "$DISK_IMG" \
        --extmem 16 $DISPLAY_FLAG \
        "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
fi
