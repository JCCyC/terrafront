# Terra Front — notes for Claude

The game's name is **Terra Front** (two words); `terrafront` (directory) and
`terrafnt` (8.3 file names) are only identifiers.

An MSX1 shoot-'em-up in Z80 assembly (sjasmplus), built as a 16 KB plain
cartridge ROM at 4000h..7FFFh (`terrafnt.rom`, an 8.3 name). RAM at E000h.

**Current state:** it starts with a splash screen, `images/title.png`
(256×192, the user may retouch it: MSX1 colours, at most two per 8×1
byte), the logo solid cyan, and "PRESS SPACE OR FIRE TO BEGIN" printed on it in
white (`TEXT_COLOR`), centred on character row 22 (`BLINK_ROW`; the
picture's row is blank), blinking 0.3 s on, 0.2 s off by its cells'
colours. **Text:** all the game's text (scores later too) is in U-boat
Killer's font (`images/font.png`, copied from `../ubhunter/images/Font.png`:
8×6 glyphs for ASCII 20h..5Fh, black letters on blue, black = ink), drawn
in the SCREEN 2 bitmap by `print_text` (HL = text, 0-terminated; DE = first
cell, row·256 + column·8; C = colour byte), a glyph's 6 rows on its cell's
lines 0..5, lines 6..7 blank. Space or either joystick's button A starts the game (a press;
held from before doesn't count). Meanwhile `splash` busy-polls the 11
keyboard rows and both joysticks (about 22 polls a frame on the Expert)
and mixes every press's and release's time (polls so far, R) into
`entropy` (16 bits, nonzero once a key moved; unused for now). Then the tables are cleared, display off until the game's
init is done. The game: SCREEN 2, all black. The top 8 and bottom 8 pixel lines
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
can't move or shoot, and a call-up lands there: the frame the front is
empty (its last boom over), with no call-up flying, one starts by itself
(no C needed; `call_up`). With no reserve left, that frame is game over
(`game_over`, after `call_up`): "GAME OVER" (`OVER_TEXT`) in the font,
white, in the screen's middle (`OVER_ROW` 12, lines 96..103), centred to
the cell (columns 11..19, `OVER_COL`; meanwhile no star or bullet is drawn
in its cells: `over_at`, from `bullet_at` and `bullet_px`, and `eb_draw`'s
shared rows), and the game runs on (enemies, waves, stars; the front can't
move, shoot or call up) for 10 s (`GAME_OVER_MS`; 600 / 500 frames), or
until a press of fire (`IN_FIRE`: space or either joystick's button A)
seen from 3 s on (`OVER_SKIP_MS`; held from before doesn't count); then
`restart`: display off, no sprites, the game's RAM (from `game_ram`; the
rates, `frames`, `entropy`, `polls`, `lw_text`, `score_digits`,
`score_shown` kept) cleared, the splash
(with the last game's level and wave on its top row's left, from `lw_text`,
and its score on its right, as in the game, from `score_shown`, its leading
blanks not printed (the picture stays);
none at power-on), and a new game as at power-on.
**Levels:** a level is 10 waves (enemies 0..9); `level` (1.., stays at
255) goes up when `form_enemy` wraps to 0. "L1 W1" .. "L1 W10", "L2 W1",
... (`level`, `form_enemy`+1) is on the top status row's left in the font,
white (`level_text`: into `lw_text`, printed from `LW_COL` 0 on `LW_ROW`
0, blank cells after it up to `LW_LEN` 8), at a new game and when each
wave begins (`next_wave`). **Score:** a pair broken up 50 points
(`BREAK_PTS`), a free enemy's death, shot or crashing into a ship, 100
(`FREE_PTS`), with a one-ship front; with 2, 3, 4 living ships 80%, 60%,
50% (`SHARE_1..4`; none counts as one; the same for future bosses): the
ships living before the hit (a bullet's: the front then; a crash's: as
`collide` began, `col_alive`, so one enemy killing one ship of two gives
80). `score` is 8 BCD digits (cheaper than 32-bit binary: the add is the
same few `daa`s, the display needs no division), 99999999 at most (it
stays there); `score_add` (B = `PTS_BREAK`/`PTS_FREE`, A = the living
ships' mask; the BCD points in `PTS`, built from the tunables). It shows on
the top status row's right (`SCORE_ROW` 0, `SCORE_COL` 24, `SCORE_LEN` 8),
right-aligned, no leading zeros ("0" at the start), white, printed by
`show_score` (after `next_wave`; and at `restart`, for the title) only on a
frame it changed, only the cells that changed (`score_shown`); a new game
starts at 0 (`score_shown` cleared after the splash: every cell printed). Behind it all, 15
one-pixel light grey stars (random columns, random lines, never two on a
line) scroll left at 10 px/s (1 px every 6 frames at 60 Hz, every 5 at
50 Hz), drawn in the bitmap (`move_stars`, after `fire`); one leaving past
column 0 comes back at column 255 on a free random line. A star isn't
drawn in a bitmap byte a bullet is in (one colour per byte: the bullet's
white is kept); it shows again once the bullet has left the byte.
The enemies come in waves: a formation of 4 pairs of one enemy in one
colour. The first wave is enemy 0 (`images/enemy-0..9.png`) in colour 2;
each next wave is the next enemy in the next colour of 2, 3, 5, 7, 8, 9,
10, 11, 13 (`FORM_COLOR_LIST`), each list from its start again after its
last (`form_enemy`, `form_cidx`): 0/2, 1/3, ..., 8/13, 9/2, 0/3, ....
Once every enemy of a wave is gone (its last boom over), that frame
starts a 0.7 s wait (`WAVE_DELAY_MS`: 42 frames at 60 Hz, 35 at 50 Hz,
counted down in `wave_wait`), and the frame it runs out begins the next
wave (`next_wave`, after `move_enemies`): its patterns
loaded (`load_formation`), all in their pairs, the loop from its start
(column 25, line 66), shown from that frame's SAT on. Each pair
is one 16×16 sprite, the 8×16 enemy twice side by side; laid out
as in `images/formation-enemy-0-color-12.png` and starting at its column
25, flies a loop at a constant 113 px/s: northeast across a 35×29 box,
east-southeast across 60×29, southwest and northwest across 35×29, in
1.8 s (`CYCLE_SECS` in `path.py`, the user's choice), 25 px east a cycle
(first 70×58 etc. in 1 s, then halved, then slowed to 1.8 s). The loop is centred between line 8 and the front's
sprite lines (168..183): the cycle starts with the formation's top on
line 66. x is mod 272: a pair past the right edge comes
back in from the left (EC). Its sprites come after the front's and the
incoming ship's in the SAT. Every other frame the whole SAT is reversed
(`sat_flip`), and with each straight frame the enemies' order turns one
back (`enemy_rot`, the last first): where a line has more than 4 sprites
(e.g. enemies on a 4-ship front's lines) they flicker instead of one
staying hidden; on lines of up to 7 sprites none is dropped two frames
running.
Hits: a bullet hits an enemy when its column has a pixel of the enemy's
art on a line the bullet covered that frame (its new top to its old
bottom), checked against where the enemies show (before they move); the
bullet is gone (`volley_hits`, `bullet_hit`). An enemy in a pair: the pair
breaks up, with U-boat Killer's "miss" (its `BOOM_WATER`, a depth charge on
the seabed; Skyfighter's `BOOM_ROCK`, byte for byte; 0.8 s) on PSG channel
B, and each of its two enemies (`enemies`, 8 records, pair k = enemies 2k
and 2k+1) flies alone from where it was, at a random one of 64 directions (never
level: 0 and 32 are left out),
at the loop's speed, the square legs' (112.8 px/s; `FREE_VEL_60/50` in
`path.py`, 1/256 px a frame). When its art passes line 8 or 183 it is put
back on that line and turns to a random direction away from it (any of
the 31 strictly down or up ones, not a mirror). x is mod 272 as the
formation's. A free enemy hit: it shows the ship's three boom images in its
own colour, where it was (the boom's art box from the enemy's left column),
for the ship's boom frame counts, and the ship's death sound (re)starts;
then it's gone. Noise period (R6) priority: death > break > shot.
Collisions (`collide`, after `move_enemies`): each free enemy, where it
shows this frame (after its move), against each living ship of the front
(after the call-up and the move): a pixel of the enemy's art on a pixel of
the ship's art (`touch`; `load_formation` keeps the wave's art rows
rotated 0..7 bits in `rot_rows`, the ship's art rows are `SHIP_ROWS`).
Both die: the enemy booms as when shot, the ship as by a test key (boom,
death sound, then a hole and the trim). Every enemy and ship that touch:
one enemy across two ships kills both; two enemies on one ship both boom
(the ship dies once, one death sound start). Pairs never reach the
front's lines (assert); dying ships, booming enemies and the incoming
ship don't collide.
Enemy bullets (`enemy_fire`, after `fire`): every 0.25 s (`EB_ROLL_MS`;
a clock in 1/300 s: 15 frames at 60 Hz, 13/12 at 50 Hz) a roll; one in 4
(`EB_CHANCE`) hits; then, with fewer in flight than the wave's most
(`EB_MAX_LIST`: 3 in waves 1..3, 4 in 4..6, 5 from 7 on), a random one of
the enemies that can shoot fires: in a pair or free, its art's last row
at least 8 lines over the front's art's first (`EB_CLEAR`: line 160 or
above), its column 3 (`EB_DX`, the art's middle) on screen; none, no
bullet. The bullet: the player's shape and colour (1×3, white, in the
bitmap), its top right under the art's last row, going down at
`EB_SPEED_LIST`% of the player's 230 px/s (70% in wave 1, +10% a wave,
140% from wave 8 on; `wave_n` counts the waves, stopping at 255),
Bresenham in 1/100 px (one table for both rates); gone once its bottom
would pass line 183. It hits a ship of the front (`eb_hit`, from `eb_move`)
when its column has a pixel of the ship's art (`SHIP_ROWS`) on a line the
bullet covered that frame (its old top to its new bottom), the front
where it shows (before it moves), its ships living when `eb_move` began
(`eb_alive`, worked out once a bullet reaches the front's lines): the
bullet is gone and the ship dies as by a test key (boom, death sound,
then a hole and the trim); two bullets on one ship: both gone, it dies
once. Dying ships and the incoming ship aren't hit. When a wave begins
(`next_wave`, `eb_wipe`), all enemy bullets go: the next frame's
`eb_move` erases them, the frame the new wave first shows. All bullets are erased before
any is drawn; an enemy bullet sharing a bitmap byte with another (a
volley's or an enemy's) is drawn as the bits of all of them (`eb_draw`,
after the volleys); stars hide in their bytes as in the volleys'. The
SAT's reversal every other frame is done by `upload_sat` (the entries
sent backwards, in vertical blank). The worst frame's work is about
11.6 ms on the Expert (16.7 ms a frame; two full volleys on a star-step
frame: `move_bullets` ~3.9 ms, `move_stars` ~3.0 ms). Speed-ups that
keep it there: `hit_lines` puts each enemy's art's first line in
`hc_first` once a frame, and `volley_hits` only tries, per bullet, the
enemies whose art has a line the volley covered (`hc_list`); `move_stars`
first marks the lines bullets are on (`bl_lines`, `bl_mark`), so
`bullet_at` answers "none" for a star's line without one at once.

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
  art bounds, nose column, art rows (`SHIP_ROWS`, at the end: the
  patterns before it must stay contiguous); the coming ship's two patterns and where the
  ship's art is in them; the three boom patterns and their colour; the
  reserve ship's rows, colour, art width; the enemies' pair patterns and
  art rows; the formation's pair offsets, from its picture) and `path.py` (→
  `build/path.inc`: the formation loop's tunables and its table, 300
  entries per second of cycle, stepped by Bresenham on frames; only
  `CYCLE_SECS` sets the timing; the free enemies' velocity tables) and `sfx.py` (→ `build/sfx.inc`: the shot, death and break
  sound tables; the death one is Skyfighter's `BOOM_SHIP`, the break one its
  `BOOM_ROCK`, byte for byte) and
  `font.py` (→ `build/font.inc`: `FONT`, 6 bytes a glyph; `font.py --raw`
  prints them for the test) and
  `title.py` (→ `build/title.inc`: the splash's SCREEN 2 pattern and colour
  tables from `images/title.png`, 24 rows each RLE-packed alone, so the
  blinking row unpacks by itself; `title.py --raw` prints them unpacked,
  for the test), then `sjasmplus main.asm` (→ `terrafnt.rom`, symbols
  `build/terrafnt.sym`). `build/` is generated; don't edit it.
- `make run` runs the Gradiente Expert 1.1 (primary target, 60 Hz),
  `make run-cbios` C-BIOS MSX1 (50 Hz), `make run-nms8250` the Philips
  NMS 8250 (MSX2, 50 Hz). `FS=1` starts fullscreen, `VIDEO=1` records to
  `videos/<target>-<date>-<time>.avi`, `CMDONLY=1` only prints the openMSX
  command (each on when a nonzero number; see `../MSXDEV.md`).
- `make test` runs `test.tcl` headless on all three machines (log in
  `build/test-<machine>.log`, screenshots `build/shot-<machine>.png` and
  `build/shot-<machine>-call.png`, a call-up in flight). It boots twice:
  first space held from power-on (then let go) doesn't start, joystick 1's
  button A does, then a reset; then the splash's VRAM against
  `title.py --raw` with the text (read from the ROM) overlaid in
  `font.py --raw`'s glyphs (text shown and hidden; the space glyph blank), the blink every frame (on/off
  frame counts, 0.5 s period between frame interrupts in emulated time, no frame missed), A, C and
  button B changing `entropy` without starting, and space starting; then
  "L1 W1" on the top status row and the score's "0" at its right, the
  rest of the status rows blank. Then: ship start, speed
  over 1 s, both arrows, edge clamps for 1, 2 and 4 ships and their sprite
  X / EC, bullet spawn point, speed, removal at the top, the shot sound's
  length, the 2-volley limit, one shot per press, the reserve ships' pixels
  and colours in VRAM; three call-ups (side, distance, frames ≤ 0.25 s,
  constant step, frozen front, glue point), a shot during one, C ignored
  with 4 ships, a 4-bullet volley; joystick buttons A (fires, no
  call-up) and B (calls up, no shot), faked by a breakpoint after
  `joy_r14`'s R14 read; the test keys: a boom's images and frame counts
  in the SAT, no bullet from a dying ship, holes, C refused for
  ship-gap-gap-ship, the death sound (every frame: channel C's volume,
  tone, noise period and mixer bits against the table, restarted by each
  death, its noise period winning over the shot's; the last
  one plays out in 1.4 s), a key with no such ship, trims, ship-gap-ship calling
  up from either side, an emptied front's call-up of the last reserve
  starting by itself that frame (no move, no shot meanwhile), landing
  where its last ship died (the test writes `reserves` in RAM for these
  call-ups); the stars: 15 on 15 lines, all moving together 1 px every
  6 / 5 frames, wraps to 255 on a free line, a star the test puts on a
  new volley's spawn line hiding under it; the first wave's enemy 0 and colour 2
  and its pair pattern and the lone enemy's in VRAM. Hits are off for all of that (a
  breakpoint makes `volley_hits` return), and so are enemy bullets' hits on
ships (`eb_hit` returns no hit) outside the enemies' part's hunting and
the staged test below. Then the enemies' part, hits on,
  with four ships (three call-ups first): the test steers the front's first ship under the nearest pair and fires until
  all 4 pairs broke up, holds fire 6 s (screenshot
  `build/shot-<machine>-enemies.png`), then hunts the free enemies until
  all 8 are gone, then stops firing (at the pairs it fires one aimed volley at a time, so
  that free enemies are left to fly; whenever the front spans fewer than
  4 slots and no call-up flies, it writes 3 `reserves` and calls one up,
  as enemies touching the front and enemy bullets kill ships; reserves
  kept at 2 or more); the second wave must begin
  exactly 0.7 s later, all gone till then (enemy 1, colour 3, its patterns in VRAM, the loop from its
  start; the per-frame models follow it for 2 s); then staged collisions
  (written in RAM, the formation's check skipping the 2 frames whose SAT
  predates the writes: a four-ship front at column 100, enemies flying
  straight down placed by the test's own pixel model so that after their
  next move one is across ships 1 and 2, two are on ship 3, one's art box
  overlaps a ship's with no pixel touching: the next frame's states, booms
  and 6 death sound starts); then staged bounces (two free enemies written
  2 lines short of lines 8 and 183, flying straight at them, away from
  the front: a bounce at each, as modelled); then, with the
  per-frame models off, the test makes every enemy gone in RAM 19 times
  and checks waves 3..21 (both lists wrap; the top status row's level
  and wave at every wave, L3 W1 at the 21st; none begun a frame before
  its 0.7 s; the frame before each begins, the test puts 3 enemy
  bullets in flight: the model has them gone the frame after). Then the
  enemy bullets' levels (rolls forced to hit): the
  wave then (21) and waves 1..8 (`wave_n` written): the speed, and with
  one fewer than the most in flight (the test's own bullets, two sharing
  bytes) a roll fires, with the most it doesn't; then the 8-line rule at
  its edge (free enemies flying level, art's last row on 161, one on 160:
  only that one shoots; all on 161: none does). Then enemy bullets on
  ships, staged (all 5 slots written, a four-ship front placed where no
  star shares the bullets' bytes): next frame, one on ship 0's nose and
  one low on ship 1's column 0 hit them, two on ship 3 kill it once, one
  in ship 2's column 0 over its rows without pixels flies on; 3 death
  sound starts. Then game over, twice: 1 reserve left (RAM), the front
  killed (keys 1..4 at once): it's called up, no game over; killed again:
  GAME OVER in the middle row that frame (VRAM against `font.py --raw`),
  intact every frame of game over (a star and an enemy bullet the test
  puts in it fly through, not drawn in its cells, and show past them), the
  front can't move, shoot or call up, the formation and stars move
  (screenshot `build/shot-<machine>-over.png`), space and joystick 2's
  button A pressed a frame before 3 s and held past it ignored, the title exactly 10 s on; the
  title's VRAM (with the game's level and wave, L3 W1, on its top row's
  left and its score, 99999999, on its right; "0" after games 2 and 3), no sprites, a held space not starting; the new game as at
  power-on (RAM, first wave, patterns, silent, status rows, 4 reserves).
  Then twice no reserves, the front killed: joystick 1's button A, then
  space, seen exactly at 3 s goes to the title at once; a fourth game for
  the final screenshot. The score, every frame of the game: each `score_add` call
  (a breakpoint) with the front's living ships before the hit (the front
  then; for a crash, as `collide` began), one call per pair broken and per
  enemy booming (from the enemies' states), the score in RAM the spec's
  sum (50 / 100 by the shares), its cells on the top row's right the frames
  it changed and the next; staged with the collisions, from 99999890
  (written) the three crashes stop it at 99999999. It checks the velocity table (64 directions, the square
  legs' speed), every enemy's boom (images and frame counts), the break
  sound's starts and length, a death-sound start per enemy boom, bounces at
  both lines (not mirrors), no level break-up direction, the SAT's flip and
  turn, no sprite the VDP drops (worked out from the SAT shown) dropped two
  frames running on a line of 5..7 sprites, and no frame dropped. Enemy
  bullets: a roll exactly every 0.25 s, about one in 4 hitting, each
  hit's outcome against the test's model (room under the wave's most,
  the enemies able to shoot from RAM, the bullet's place one of theirs,
  the picks spread); with hits on, each bullet against the front as
  `eb_move` began (a breakpoint's snapshot), pixel against pixel from
  `SHIP_PATTERN`: the ships hit booming (image 1, its full count, once),
  the others not, the front not moved. Every frame it also
  checks the SAT against the front (ships and booms), the incoming ship
  and the enemies (from RAM, rotated; the pairs against the test's own
  model of the loop from the spec, the cycle from the build: pair layout,
  the picked colour, ±1 px, 25 px east a cycle later, its lines clear of the front, the wrap with EC), the
  bitmap (pixels and the playfield's colours) against the bullets in
  flight (the enemies' too; a shared byte holds both) and the stars not
  in their bytes, the enemy bullets against its own model (each down the
  frame's step, Bresenham exact for the wave's %, gone past line 183, a
  new one in the first free slot, never more than the wave's most),
  channel B against the break
  table, and the enemies and volleys against its own model of the frame
  (booms on, every bullet's hit test against the art in game order, the
  free enemies' flight exact to 1/256 px, wraps and bounces; the
  collisions: every free enemy after its move against the ships living
  when `collide` began (a breakpoint's snapshot), pixel against pixel
  from `SHIP_PATTERN` and the enemy's art, the touching ones booming and
  dying, the others unchanged; a new volley's bullets from the front as
  `fire` had it, a breakpoint's snapshot). The break checks count the
  first wave's (a bullet in flight may break a second wave's pair).
