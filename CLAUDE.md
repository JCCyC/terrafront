# Terra Front — notes for Claude

The game's name is **Terra Front** (two words); `terrafront` (directory) and
`terrafnt` (8.3 file names) are only identifiers.

An MSX1 shoot-'em-up in Z80 assembly (sjasmplus), built as a 16 KB plain
cartridge ROM at 4000h..7FFFh (`terrafnt.rom`, an 8.3 name). RAM at E000h.

**Current state:** SCREEN 2, all black. The top 8 and bottom 8 pixel lines
are not playfield (reserved for scores and reserve ships). The front, 1 to
4 player ships (`images/player-ship.png`, one 16×16 sprite each) glued side
by side (9-px art, no pixel between), sits on the playfield's last line and
moves left/right at 108 px/s, its art reaching both screen edges (EC bit on
the left). It's held as a slot mask (`front_mask`, slot 0 at `ship_x`) so
that holes can come later. Fire shoots a volley, a 1×3 white bullet up from
every ship's nose at 230 px/s, drawn in the SCREEN 2 bitmap (the ships fill
the 4 sprites a line), at most 2 volleys in flight (a press with both in
flight is ignored), one volley per press. Each volley plays a 0.25 s laser
"cheeoom" on PSG channel A. Controls: arrows + space (fire) + C (call-up), or
either joystick (button A fires, B calls up). The bottom status area shows the reserve ships
(4 at the start; `images/reserve-ship.png`, 8×8, drawn in the bitmap) at its
left, art from column 0, one black pixel apart (`draw_reserves`, A = how
many). C calls one up (not while one is flying, nor with the front
spanning 4 slots):
it leaves the reserve and flies in from just off the edge away from the
front (from the right if the front's middle is left of the screen's or on
it) as `images/player-ship-coming.png` (mirrored when coming from the left),
at a constant 1067 px/s (the longest flight, 256 px into an empty front at
an edge, in at most 0.25 s at 50 and 60 Hz), and glues on to that side.
Meanwhile the front shoots but can't move. The front's span runs from its
first ship to its last, holes included: ship-gap-ship can still call one
up (from either side), ship-gap-gap-ship can't. Test keys 1..4 kill the
front's 1st..4th living ship: it shows `images/player-ship-boom-1..3.png`
(9×16, the ship's art box) for 6/4/5 frames at 60 Hz, 5/3/4 at 50 Hz, and
doesn't fire, and Skyfighter's ship-blown-up sound plays on PSG channel C
(1.4 s, U-boat Killer's "water, loud"; another death restarts it; where
it clashes with the shot's sound, the PSG's one noise period, it wins); then its slot is a hole, and the front is trimmed to its
first and last ships. An emptied front stays where its last ship died,
can't move or shoot, and a call-up lands there. Behind it all, 15
one-pixel light grey stars (random columns, random lines, never two on a
line) scroll left at 10 px/s (1 px every 6 frames at 60 Hz, every 5 at
50 Hz), drawn in the bitmap (`move_stars`, after `fire`); one leaving past
column 0 comes back at column 255 on a free random line. A star isn't
drawn in a bitmap byte a bullet is in (one colour per byte: the bullet's
white is kept); it shows again once the bullet has left the byte.

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
  art bounds, nose column; the coming ship's two patterns and where the
  ship's art is in them; the three boom patterns and their colour; the
  reserve ship's rows, colour, art width) and `sfx.py` (→ `build/sfx.inc`: the shot and death
  sound tables; the death one is Skyfighter's `BOOM_SHIP`, byte for byte), then `sjasmplus main.asm` (→ `terrafnt.rom`, symbols
  `build/terrafnt.sym`). `build/` is generated; don't edit it.
- `make run` runs the Gradiente Expert 1.1 (primary target, 60 Hz),
  `make run-cbios` C-BIOS MSX1 (50 Hz), `make run-nms8250` the Philips
  NMS 8250 (MSX2, 50 Hz). `FS=1` starts fullscreen, `VIDEO=1` records to
  `videos/<target>-<date>-<time>.avi`, `CMDONLY=1` only prints the openMSX
  command (each on when a nonzero number; see `../MSXDEV.md`).
- `make test` runs `test.tcl` headless on all three machines (log in
  `build/test-<machine>.log`, screenshots `build/shot-<machine>.png` and
  `build/shot-<machine>-call.png`, a call-up in flight): ship start, speed
  over 1 s, both arrows, edge clamps for 1, 2 and 4 ships and their sprite
  X / EC, bullet spawn point, speed, removal at the top, the shot sound's
  length, the 2-volley limit, one shot per press, the reserve ships' pixels
  and colours in VRAM; three call-ups (side, distance, frames ≤ 0.25 s,
  constant step, frozen front, glue point), a shot during one, C ignored
  with 4 ships, a 4-bullet volley; joystick buttons A (fires, no
  call-up) and B (calls up, no shot), faked by a breakpoint after
  `read_joy`'s R14 read; the test keys: a boom's images and frame counts
  in the SAT, no bullet from a dying ship, holes, C refused for
  ship-gap-gap-ship, the death sound (every frame: channel C's volume,
  tone, noise period and mixer bits against the table, restarted by each
  death, its noise period winning over the shot's; the last
  one plays out in 1.4 s), a key with no such ship, trims, ship-gap-ship calling
  up from either side, an emptied front (no move, no shot) refilled where
  its last ship died (the test writes `reserves` in RAM for these
  call-ups); the stars: 15 on 15 lines, all moving together 1 px every
  6 / 5 frames, wraps to 255 on a free line, a star the test puts on a
  new volley's spawn line hiding under it. Every frame it also checks the
  SAT against the front (ships and booms) and the incoming ship, and the
  bitmap (pixels and the playfield's colours) against the bullets in
  flight and the stars not in their bytes.
