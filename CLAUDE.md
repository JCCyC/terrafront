# Terra Front — notes for Claude

The game's name is **Terra Front** (two words); `terrafront` (directory) and
`terrafnt` (8.3 file names) are only identifiers.

An MSX1 shoot-'em-up in Z80 assembly (sjasmplus), built as a 16 KB plain
cartridge ROM at 4000h..7FFFh (`terrafnt.rom`, an 8.3 name). RAM at E000h.

**Current state:** SCREEN 2, all black. The top 8 and bottom 8 pixel lines
are not playfield (reserved for scores and reserve ships later). The player
ship (`images/player-ship.png`, one 16×16 sprite) sits on the playfield's
last line and moves left/right at 108 px/s, its art reaching both screen
edges (EC bit on the left). Fire shoots a 1×3 white bullet up from the nose
at 230 px/s, at most 2 in flight (a press with both in flight is ignored),
one shot per press. Each shot plays a 0.25 s laser "cheeoom" on PSG
channel A. Controls: arrows + space, or either joystick (either button).

**Reference speed:** "Galaga" means the user's MSX Galaga dump
(`galaga.rom`, notes in `GALAGA-TECHNIQUES.md`). Its ship moves 1.5 px a
frame on the Expert (60 Hz) = 90 px/s, measured in openMSX from the SAT
while holding →. Terra Front's ship is 20% faster: 108 px/s.

**How the user works:** one small step at a time, a spec per step.
Implement only the step asked for. Tunables are constants at the top of
`main.asm`. Speeds and durations are in real time (px/s, s), the same at
50 and 60 Hz: Bresenham on frames (whole pixels + remainder per frame,
from the `RATES_60` / `RATES_50` tables), sound tables per rate.

MSX tools and references: `../MSXDEV.md`, `../docs/README.md`. Read
`../HARD-EARNED-EXPERIENCE.md` before MSX work.

## Build / run / test

- `make` runs `png2spr.py` (→ `build/sprites.inc`: ship pattern, colour,
  art bounds, nose column) and `sfx.py` (→ `build/sfx.inc`: the shot sound
  tables), then `sjasmplus main.asm` (→ `terrafnt.rom`, symbols
  `build/terrafnt.sym`). `build/` is generated; don't edit it.
- `make run` runs the Gradiente Expert 1.1 (primary target, 60 Hz),
  `make run-cbios` C-BIOS MSX1 (50 Hz), `make run-nms8250` the Philips
  NMS 8250 (MSX2, 50 Hz). `FS=1` starts fullscreen, `VIDEO=1` records to
  `videos/<target>-<date>-<time>.avi`, `CMDONLY=1` only prints the openMSX
  command (each on when a nonzero number; see `../MSXDEV.md`).
- `make test` runs `test.tcl` headless on all three machines (log in
  `build/test-<machine>.log`, screenshot `build/shot-<machine>.png`): ship
  start, speed over 1 s, both arrows, both edge clamps and their sprite X /
  EC, bullet spawn point, speed, removal at the top, the shot sound's
  length, the 2-bullet limit, and one shot per press.
