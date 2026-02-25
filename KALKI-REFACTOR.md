# Kalki Refactor Plan

## Current State

**Kalki GUI** — 3,285 lines across 10 Forth files.
Phases 0–8 implemented: framebuffer graphics, color themes, widget tree,
windows/dialogs, labels/buttons/panels, menus, scrollbars/listboxes,
gap-buffer editor, desktop shell with file manager and RTC clock.

**Akashic library** — 53 modules across 11 packages.
math (16), font (3), text (2), utils (4), net (6), web (3),
dom (1), markup (3), css (2), cbor (2), atproto (6).
All font stack modules complete: ttf.f, raster.f (C2 Bézier done),
cache.f, layout.f.

**KDOS** — 11,384 lines.  Arenas, hash tables, ring buffers, CATCH/THROW,
spinlocks, cluster MPU, userland dict isolation, multicore scheduler,
work stealing, tile engine SIMD, full network stack through TLS 1.3.

---

## Goals

1. **Integrate the Akashic font stack** into Kalki's rendering path.
2. **Replace hardcoded 8×8 bitmap font** with scalable TrueType glyphs.
3. **Add protected application processes** — secure run environment for
   Kalki apps with memory isolation, resource limits, and clean teardown.
4. **Restructure Kalki into a cleaner architecture** that scales beyond
   a single monolithic desktop file.
5. **Bring the Kalki roadmap current** (Phases 8.3, 8.4, 9, 10).

---

## Architecture After Refactor

```
┌─────────────────────────────────────────────────────────────┐
│  Kalki Applications                                         │
│    (editor, file-mgr, settings, user apps)                  │
│    Each runs in a PROTECTED PROCESS sandbox                 │
├─────────────────────────────────────────────────────────────┤
│  kalki-app.f — Application Process Manager                  │
│    APP-LAUNCH / APP-KILL / APP-LIST                         │
│    Arena-per-app, MPU fencing, CATCH/THROW isolation        │
├─────────────────────────────────────────────────────────────┤
│  kalki-desktop.f — Desktop Shell                            │
│    Taskbar, workspace, app launcher, process list           │
├────────────────────┬────────────────────────────────────────┤
│  kalki-font.f      │  kalki-menu.f / kalki-scroll.f /      │
│    Akashic bridge: │  kalki-window.f / kalki-editor.f       │
│    ttf → cache →   │  (existing widget vocabulary)          │
│    layout → render │                                        │
├────────────────────┴────────────────────────────────────────┤
│  kalki-widget.f — Widget core + focus + tree                │
│  kalki-gfx.f    — RGB565 drawing + double buffer            │
│  kalki-color.f  — Theme system                              │
├─────────────────────────────────────────────────────────────┤
│  Akashic Libraries (font/, text/, math/, utils/, ...)       │
├─────────────────────────────────────────────────────────────┤
│  KDOS (arenas, scheduler, MPU, CATCH/THROW, FS, network)   │
│  graphics.f / tools.f                                       │
├─────────────────────────────────────────────────────────────┤
│  BIOS + Tile Engine + Hardware                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase R1: Font Integration

**Goal**: Replace the 8×8 bitmap font with scalable TrueType rendering.

### R1.1 — `kalki-font.f` — Akashic Font Bridge

Bridge module that connects Akashic's font stack to Kalki's widget layer.

| Word | Stack | Description |
|------|-------|-------------|
| `KF-INIT` | ( ttf-addr ttf-len -- ) | parse TTF, init cache & layout |
| `KF-SIZE!` | ( pixel-size -- ) | set rendering size (8–64px) |
| `KF-CHAR` | ( codepoint x y color -- ) | render one glyph at (x,y) |
| `KF-TYPE` | ( addr len x y color -- ) | render UTF-8 string |
| `KF-TEXT-W` | ( addr len -- pixels ) | measure string width |
| `KF-LINE-H` | ( -- pixels ) | current line height |
| `KF-ASCENDER` | ( -- pixels ) | scaled ascender |

**Implementation**:
- Wraps `GC-RENDER` (cache.f) for bitmap lookup/rasterize-on-miss
- Wraps `LAY-TEXT-WIDTH` / `LAY-LINE-HEIGHT` for metrics
- Blits cached glyph bitmaps to framebuffer via `GFX-PIXEL!` or
  a fast byte-to-RGB565 blit word
- Falls back to 8×8 bitmap font if no TTF loaded (graceful degrade)

### R1.2 — Embed a Default Font

Ship a minimal TTF on the Kalki disk image.  Options:
- Subset a libre font (e.g. Cozette, Tamzen, or a custom ~2–4 KiB subset)
- Load at boot in `kalki-autoexec.f` via `KF-INIT`
- Store in XMEM/HBW — a 10 KiB TTF has negligible footprint

### R1.3 — Update Widget Rendering

- `kalki-widget.f`: make `FONT-W` / `FONT-H` / `LINE-H` dynamic,
  switchable between bitmap and TTF modes
- `kalki-basic.f`: `LABEL-RENDER` and `BUTTON-RENDER` call `KF-TYPE`
  when TTF is active, fall back to `GFX-TYPE` otherwise
- `kalki-editor.f`: use `KF-CHAR` for editor text, `KF-TEXT-W` for
  cursor positioning; update `LINENUM-W` based on actual glyph width
- `kalki-menu.f`: menu item widths via `KF-TEXT-W` instead of
  hardcoded `TEXT-WIDTH`

### R1.4 — Font Size Themes

Extend `kalki-color.f` themes to include a font size parameter.
Small (8px), Medium (12px), Large (16px).  `THEME-LOAD` sets both
colors and `KF-SIZE!`.

---

## Phase R2: Protected Application Processes

**Goal**: Kalki applications run in isolated sandboxes.  A misbehaving
app cannot corrupt the desktop, other apps, or the kernel.

### Hardware & KDOS Primitives Available

| Primitive | Source | What it gives us |
|-----------|--------|-----------------|
| **Arenas** | KDOS §2 | Per-app memory pool with allot/reset/destroy |
| **Arena scoping** | KDOS | `ARENA-PUSH` / `ARENA-POP` / `CURRENT-ARENA` / `AALLOT` |
| **Cluster MPU** | KDOS §8.9 | Hardware memory fencing: `CL-MPU-SETUP` sets [base, limit) |
| **CATCH/THROW** | KDOS §1.2 | Exception isolation — app THROW doesn't unwind desktop |
| **Userland dict** | KDOS §1.15 | `ENTER-USERLAND` / `LEAVE-USERLAND` — separate HERE |
| **Slot tables** | akashic table.f | Fixed-width slot arrays for process table |
| **Hash tables** | KDOS §19 | Lock-protected `HT-PUT` / `HT-GET` for resource tracking |
| **Ring buffers** | KDOS §18 | Event queues between desktop and app processes |
| **Spinlocks** | KDOS §8 | `LOCK` / `UNLOCK` for shared resource coordination |
| **Multicore** | KDOS §8 | `CORE-DISPATCH` for running apps on secondary cores |

### R2.1 — `kalki-app.f` — Application Process Manager

**Process descriptor** (per-app, stored in a slot table):

| Field | Size | Description |
|-------|------|-------------|
| `AP.STATE` | cell | 0=free, 1=running, 2=suspended, 3=zombie |
| `AP.ARENA` | cell | arena handle — all app memory lives here |
| `AP.ROOT` | cell | root widget of the app's window |
| `AP.ENTRY` | cell | XT of app's main word |
| `AP.NAME` | 16B | app name (padded) |
| `AP.EVENT-Q` | cell | ring buffer for input events |
| `AP.DICT-SAVE` | cell | saved HERE before app dictionary entries |
| `AP.MPU-BASE` | cell | MPU window base (if on cluster core) |
| `AP.MPU-LIMIT` | cell | MPU window limit |

**Public API**:

| Word | Stack | Description |
|------|-------|-------------|
| `APP-LAUNCH` | ( entry-xt name-addr name-len -- pid \| -1 ) | create process, allocate arena, CATCH-wrapped |
| `APP-KILL` | ( pid -- ) | destroy arena, free widgets, reclaim slot |
| `APP-SUSPEND` | ( pid -- ) | mark suspended, skip in event dispatch |
| `APP-RESUME` | ( pid -- ) | resume |
| `APP-LIST` | ( -- ) | print active processes |
| `APP-CURRENT` | ( -- pid ) | currently focused app's PID |
| `APP-DELIVER` | ( key pid -- consumed? ) | deliver key event to app |

**Lifecycle**:

```
APP-LAUNCH:
  1. TBL-ALLOC from process table
  2. ARENA-NEW (configurable size, default 64 KiB from XMEM)
  3. Save system HERE, ENTER-USERLAND
  4. ARENA-PUSH (so app's ALLOT goes to its arena)
  5. [CATCH] Execute entry-xt
     - entry-xt creates its window, widgets, sets up handlers
     - Returns control (does NOT enter event loop — desktop owns that)
  6. If THROW: log error, APP-KILL, return -1
  7. ARENA-POP, LEAVE-USERLAND
  8. Register app window in window manager
  9. Return pid

APP-KILL:
  1. Mark zombie
  2. WG-FREE-SUBTREE on app's root widget
  3. WIN-UNREGISTER
  4. ARENA-DESTROY (bulk-frees ALL app memory at once)
  5. TBL-FREE slot
  6. If on cluster core: CL-MPU-OFF

Event loop (in kalki-desktop.f):
  1. Read key
  2. Route to APP-CURRENT's root widget via APP-DELIVER
  3. If not consumed: desktop handles it (Ctrl-N cycle, etc.)
  4. Wrap delivery in CATCH — if app throws, APP-KILL it
```

### R2.2 — Memory Isolation Model

**Per-app arena**: Every `ALLOT`, `CREATE`, `VARIABLE` inside the app
goes to its private arena.  When the app is killed, `ARENA-DESTROY`
reclaims everything in one shot — no individual frees, no leaks.

**MPU fencing** (for cluster-core apps): If an app runs on a micro-core,
`CL-MPU-SETUP` restricts its memory window to the arena bounds.
Hardware traps on out-of-bounds access.  Desktop apps on core 0
use software guards (arena bounds checking in `ARENA-ALLOT`).

**Dictionary isolation**: `ENTER-USERLAND` before app init, `LEAVE-USERLAND`
after.  App's word definitions go to userland dict space, not system dict.
On kill, userland words from that app need cleanup — either maintain a
per-app dictionary watermark or use `FORGET` to the saved mark.

### R2.3 — Error Containment

Every app entry and every event delivery is wrapped in `CATCH`:

```forth
: APP-DELIVER  ( key pid -- consumed? )
    DUP AP.STATE @ 1 <> IF 2DROP FALSE EXIT THEN
    AP.ROOT @                        ( key widget )
    ['] DELIVER-KEY CATCH            ( result | exc-code )
    ?DUP IF
        ." App crashed: exception " . CR
        APP-KILL  FALSE
    THEN ;
```

An app can `THROW` or `ABORT"` and the desktop survives.
Stack depth is verified after each delivery to catch leaks.

### R2.4 — Resource Limits

| Resource | Limit | Enforcement |
|----------|-------|------------|
| Memory | Arena size (default 64 KiB) | `ARENA-ALLOT` returns error when full |
| Widgets | Max per app (e.g. 64) | Counter in process descriptor |
| Stack depth | Check before/after delivery | Detect stack corruption |
| Time | Optional watchdog per-dispatch | Timer interrupt can kill stuck app |

---

## Phase R3: Desktop Restructure

### R3.1 — Extract App Launcher from Desktop

Currently `kalki-desktop.f` hardcodes the file manager and editor.
Refactor so the file manager and editor are launchable apps:

- `kalki-app-filemgr.f` — the file manager as a proper app
- `kalki-app-editor.f` — thin wrapper that calls `EDITOR` inside an app process
- Desktop just provides: root surface, taskbar, app launcher menu, process list

### R3.2 — Taskbar Process Indicators

Show running apps in the taskbar.  Each `APP-LAUNCH` adds an entry.
Clicking (or key shortcut) switches focus.  Zombie apps shown greyed out
before cleanup.

### R3.3 — WVEC Bridge (Phase 8.3)

`INSTALL-GUI` replaces KDOS's VT100 output vector with Kalki's
graphical terminal.  `TYPE`, `EMIT`, `CR` route through Kalki's
text rendering.  Allows KDOS interactive commands to work inside
a Kalki window.

---

## Phase R4: Polish & Completeness

### R4.1 — Multi-size Font Rendering

Allow different widgets to use different font sizes.
Label at 12px, title bar at 14px, editor at 10px.
`KF-SIZE!` is cheap (just changes the scale factor and
cache hash key).

### R4.2 — Theme-Aware Font Colors

Anti-aliased fonts (future): 4× vertical supersampling in raster.f.
Glyph bitmaps become 4-level alpha.  Blend with theme background color
for proper AA on colored surfaces.

### R4.3 — Clipboard

Shared string buffer accessible to all apps:
`CLIP-COPY ( addr len -- )` / `CLIP-PASTE ( -- addr len )`.
Ring buffer in HBW, protected by spinlock.

### R4.4 — Undo/Redo for Editor

One of the key editor enhancements.  Gap buffer already supports
efficient insert/delete.  Add an operation log (ring buffer per editor
instance) recording operations for `CTRL-Z` / `CTRL-Y`.

---

## Build Order

| # | Module | Phase | Depends On | Effort |
|---|--------|-------|-----------|--------|
| 1 | `kalki-font.f` | R1.1 | cache.f, layout.f, ttf.f | Medium |
| 2 | Embed default TTF | R1.2 | kalki-font.f | Small |
| 3 | Update widget renders | R1.3 | kalki-font.f | Medium |
| 4 | `kalki-app.f` | R2.1 | arena, table.f, CATCH | Large |
| 5 | Memory isolation | R2.2 | kalki-app.f, MPU | Medium |
| 6 | Error containment | R2.3 | kalki-app.f | Small |
| 7 | Resource limits | R2.4 | kalki-app.f | Small |
| 8 | Extract file mgr app | R3.1 | kalki-app.f | Medium |
| 9 | Extract editor app | R3.1 | kalki-app.f | Small |
| 10 | Taskbar indicators | R3.2 | kalki-app.f | Small |
| 11 | WVEC bridge | R3.3 | kalki-font.f | Medium |
| 12 | Polish (R4.x) | R4 | all above | Ongoing |

**Suggested first sprint**: R1.1 + R1.2 (font bridge + embedded font),
then R2.1 + R2.2 + R2.3 (process manager core).  These two tracks
are independent and could be developed in parallel.

---

## Disk Image Changes

Current boot.sh packs 13 files.  After refactor:

```
KDOS  graphics.f  tools.f                     (system)
kalki-gfx.f  kalki-color.f  kalki-widget.f    (GUI core)
kalki-basic.f  kalki-window.f                 (widgets)
kalki-scroll.f  kalki-menu.f                  (widgets)
kalki-font.f                                  (NEW — font bridge)
kalki-app.f                                   (NEW — process manager)
kalki-editor.f                                (app)
kalki-desktop.f                               (shell)
kalki-autoexec.f                              (boot)
default.ttf                                   (NEW — embedded font)
akashic/ deps: fp16.f fp16-ext.f fixed.f      (math)
               bezier.f                       (math)
               utf8.f                         (text)
               ttf.f raster.f cache.f         (font)
               layout.f                       (text)
               table.f                        (utils)
```

Dependency count grows but each module is small.  Total additional
Forth source estimated at ~400–600 lines (kalki-font.f + kalki-app.f).

---

## Open Questions

1. **App dictionary cleanup**: `FORGET` to watermark, or maintain a
   per-app marker in the userland dict?  Need to test `FORGET` behaviour
   with KDOS's `PROVIDED` / `REQUIRE` module tracking.

2. **Multi-core apps**: Should desktop apps run on core 0 only (simpler,
   software isolation) or dispatch to micro-cores (hardware MPU, true
   isolation, but IPC overhead for rendering)?  Suggestion: core 0 first,
   micro-core as opt-in for compute-heavy apps.

3. **Font cache sharing**: One global cache or per-app caches?
   Global cache saves memory, but a killed app shouldn't leave stale
   entries.  Solution: global cache with generation counter; `APP-KILL`
   bumps generation, stale entries evicted lazily.

4. **Maximum apps**: Process table size.  8 slots should be more than
   enough — the display can't meaningfully show more than a few windows.

5. **Event model**: Current keyboard-only.  Mouse support is a separate
   future track (KDOS doesn't expose mouse device yet).  Design the
   event ring to carry typed events `( type payload )` so mouse events
   can be added later without restructuring.
