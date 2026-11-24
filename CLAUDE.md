# Terra Front — notes for Claude

The game's name is **Terra Front** (two words); `terrafront` (directory) and
`terrafnt` (8.3 file names) are only identifiers.

An MSX1 shoot-'em-up in Z80 assembly (sjasmplus), built as a 16 KB plain
cartridge ROM at 4000h..7FFFh (`terrafnt.rom`, an 8.3 name). RAM at E000h.
Nearly full: see ISSUES.md ("Code space"). Also a disk version, as
Skyfighter's: `terrafnt.bin` (`sjasmplus -DBIN`:
the same code at 8000h, BLOADed from Disk BASIC, RAM at C000h laid out
as the ROM's, `CODE_BASE` / `RAM_BASE`; its `isr` also calls H.TIMI,
`disk_timer`, for the first `DISK_HOOK_SECS` (10), so the disk ROM turns
the drive motor off) on `terrafnt.dsk` (`blank720k.dsk`, copied from
Skyfighter, plus `autoexec.bas`, which BLOADs it).

**Current state:** it starts with a splash screen, `images/title.png`
(256×192, the user may retouch it: MSX1 colours, at most two per 8×1
byte), the logo solid cyan (its last line 155: rows 20..23 blank), and
printed on it in white (`TEXT_COLOR`), each centred on its character row:
"(C) 2026 JCCYC" (`CREDIT_TEXT`, row 21, `CREDIT_ROW`) and
"HTTPS://RETROPOLIS.COM.BR" (`URL_TEXT`, row 22, `URL_ROW`), staying, and
"PRESS SPACE OR FIRE TO BEGIN" (row 23, `BLINK_ROW`), blinking 0.3 s on,
0.2 s off by its cells' colours. **Text:** all the game's text (scores later too) is in U-boat
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
either joystick (button A fires, B calls up). **Pause** (user's spec):
in a game (game over too; not attract mode), a press of F1 or STOP
(`pause_check`, after `read_input`; `pause_key`: a key down now, up
before, `pause_held`) stops it: "PAUSED" (`PAUSE_TEXT`) white, centred on
the top status row (`PAUSE_ROW` 0, `PAUSE_COL` 13), the PSG silenced
(`init_sound`; each sound's next frame writes its volume and the mixer
again), the sprites as they were, `halt` until the next press of either;
then the text's cells blank again (spaces, colour 11h, as the row was),
one more `halt`, the input read again (`read_input`: what's held then
isn't a fresh fire or call-up) and the frame goes on. Release of a key
never counts. `key_row` (A = row) reads a keyboard row (keeps BC). **Cheat mode** (user's
spec; `cheat_on`, kept until a reset, before `game_ram`): off at power-on;
on the title (not the high score list), CTRL held, C H E A T typed in
turn (`CHEAT_WORD`, stored XORed with `CHEAT_XOR`, `CHEAT_TEXT`;
`cheat_word` per splash poll, `ent_key`'s letters, `cheat_step`; a wrong
letter starts over, a C counting as the first; CTRL up starts over)
turns it on: `cheat_on` = `CHEAT_MASK` (the cheat keys' `IN_*` bits,
`read_input` masks them with it), the logo turns colour 2
(`cheat_logo`: the colour table's rows 0..19, each nibble `LOGO_COLOR`
(7) made `CHEAT_LOGO_COLOR` (2), read and written back in VRAM, about
0.3 s; again at every `splash`), and no score enters the high score
table (`restart` skips `hi_enter`). **Cheat keys (playtesting, cheat
mode only):** key 1 (`CHEAT_KEYS`, 0 to build without them and cheat
mode; `IN_BOSS`, `cheat_boss` from `next_wave`), a press in a game (not in game over, nor during a boss), goes
to the level's next boss: that frame the wave's enemies are gone (no bonus
counted), `form_enemy`, `form_cidx` and `wave_n` move on to the wave
before the boss (its level text shown), and the boss begins (wave 1..5:
the boss after wave 5; 6..10: after 10). Key 2 (`IN_SHIP`, from
`next_wave`, a boss on or not), a press in a game (not in game over),
gives a reserve ship as a bonus ship does (`bonus_ship`: under
`RESERVE_MAX` only, shown that frame, the happy beep). The bottom status area shows the reserve ships
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
up (from either side), ship-gap-gap-ship can't. A dying ship (`ship_dies`)
shows `images/player-ship-boom-1..3.png`
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
**Attract mode:** the title left alone 20 s (`TITLE_WAIT_MS`, counted per
frame `splash` sees; `title_left`), then the high score list 7 s (below),
plays a pseudo-game (`attract`, set by
`splash`) for 40 s (`ATTRACT_MS`, `att_left`; or till game over's 10 s,
if that comes first): a new game's start (`attract_init`), but the top
status row stays as the title had it (the last game's level, wave and
score; none at power-on: `splash` clears from row 1 on, `level_text` and
`show_score` do nothing, `lw_text` and `score_shown` kept for the next
title), and no sound (`sfx`, `brk_sfx`, `death` not called; the PSG
stays as `init_sound` left it). A pseudo-player (`attract_cpu`, called
from `read_input`) presses virtual keys through the game's own code:
right or left towards a random column (`att_target`, at most the front's
last), and within 3 px of it (`ATTRACT_NEAR`) a new one after a pause of
0..7 thinks (`ATTRACT_PAUSE_MAX`); at every think (`ATTRACT_DODGE_CHANCE`
1: a chance of 1 in it, the user's choice), it dodges (`attract_dodge`): the first enemy
bullet, else free enemy, whose lowest line is 40 lines
(`ATTRACT_DODGE_LINES`) above the front's art or lower and whose columns
(1, or the art's 8) come within 4 px (`ATTRACT_DODGE_MARGIN`) of the
front's becomes the target's reason: the front 4 px clear of it, on the
side away from its middle (right if left of the front's or on it), the
other side if that's off screen, no pause (only that threat is looked at,
so it isn't too good: measured over 24 runs, about 3.6 ships lost per 40 s
against 4.8 with no dodging, game over in a third of the runs; 1 in 2:
4.0, half); every think (0.1 s,
`ATTRACT_THINK_MS`: 6 / 5 frames) fire held is released, else pressed
with a chance of 1 in 2 (`ATTRACT_FIRE_CHANCE`); every 50 thinks (5 s,
`ATTRACT_CALL_MS`) a roll (`attract_cpu.roll`): 1 in 2
(`ATTRACT_CALL_CHANCE`) presses call-up for that frame (refused as C
would be: one flying, no reserve, a span of 4). The real input only
quits: a press of fire (space or either joystick's button A; held from
before doesn't count: `att_real` starts all held) goes to the title that
frame (`game_over`, `att_quit`); arrows and C do nothing.
Enemy bullets and crashes kill ships as in a game; game over in it shows
no GAME OVER (`over_text` stays 0: no cells kept from stars and bullets),
just its 10 s with the enemies flying on (the pseudo-player's fire doesn't
cut it short). Then
`restart`: the title (its 20 s from the start again).
**Easter egg** (Skyfighter's, user's spec; not in a game): a fresh
Ctrl-V (CTRL row 6 bit 1 + V row 5 bit 3, the press of the pair, either
key last, `egg_pressed`, per splash poll) on the title shows, over the
picture in place of its text (`title_rows` unpacks the picture's rows
`EGG_ROW` (20)..23 again, then the lines are printed white, each centred,
odd lengths half a cell left), "VERSION X.Y.Z" (from `VERSION_BYTES` at
4010h, `put_dec`) on row 20 and "JCCYC IS" / "JUAN CARLOS CASTRO Y
CASTRO" / "WELCOME TO THE FRONT!" (`EGG_TEXTS`) on rows 21..23 (no blank
line after the version: only rows 20..23 are free of the logo; Claude's
choice), for `EGG_SECS` (5) s (`egg_left`, from the `egg_frames` rate);
no blink meanwhile; then the title's text again, its blink from the
start (`show_title_text`); sooner at a press of space or either
joystick's button A (user's spec), which then starts nothing (it's held
at the next poll). Another Ctrl-V meanwhile doesn't restart it; the
title's 20 s count goes on. In attract mode (user's spec: the egg shows only over the title) a
fresh Ctrl-V (`IN_EGG`, read in attract mode only, `att_real` all held at
its start) ends it as fire would, and the title opens with the egg up
(`egg_now`, kept through `restart`'s clear). The texts are stored XORed
with `EGG_KEY` + `EGG_KEY_STEP`·index (Lua `egg_text`, Skyfighter's and
U-boat Killer's key) so they don't show in a ROM dump; `decode` into
`egg_buf`. The splash's frames are now caught up on one at a time
(`frames_seen` counts up): a redraw takes over a frame, and the egg's and
the title's counts stay exact.
**License lines** (an egg in the egg, as Skyfighter's): with the egg up
and CTRL held all along, `LICENSE_TAPS` (3) more V presses (`egg_tap`,
`lic_taps`; CTRL up, seen at any poll, starts over; the press that showed
the egg doesn't count) replace the egg with the two lines of
`LICENSE_TEXT` (at the fixed address 4014h, BIN 8014h, right after the
version bytes, asserted; 2 × `LICENSE_LEN` (32) space-padded bytes, each
line `egg_text`-encoded from index 0) on rows `LICENSE_ROW` (21) and 22,
each centred without its trailing spaces (all spaces: nothing;
`print_buf`). No timer (`lic_state` 1), the title's count stopped: once
all keys of matrix rows 0..8 and both sticks' buttons are released
(`lic_state` 2, `any_input`), any of them brings the title's text back
(`hide_license`), its blink from the start, the title's count from 20 s
again, starting nothing (that press is held at the next poll). Default:
"MASTER COPY - IF YOU AIN'T JCCYC" / "YOU SHOULDN'T HAVE THIS!". The font
has no lowercase. `licenserom.py ROM LINE1 LINE2 >OUT`, `licensebin.py`,
`licensedsk.py` (TERRAFNT.BIN in the image) and `licensezip.py` (the ROM,
BIN and DSK in a release zip) rewrite the lines: U-boat Killer's scripts
(ASCII 20h..5Fh, lowercase turned into capitals, ≤ 32 each), renamed;
they check for "PRESS SPACE OR FIRE TO BEGIN" and "JCCYC" (plain in the
ROM) and that the lines at 4014h decode to font characters; their
`EGG_KEY`, `EGG_KEY_STEP` and offset must match main.asm. None ships in
the zip. `changes.txt` mentions the eggs only generically ("Easter egg
adjustments.", user's spec, as Skyfighter's).
**High scores** (U-boat Killer's, user's spec): `hi_table`, `HI_COUNT`
(10) records of `HI_SIZE` (7) bytes: the score (4 BCD bytes, the lowest
two digits first, as `score`) and 3 letters (`HI_NAME`), best first,
kept across games (before `game_ram`); `HI_DEFAULTS` at power-on (the
user's list: LTR 5000, EHE 4800, TEN 4500, SAA 4000, ALZ 3500, SII 3000,
SES 2500, UNT 2000, MSO 1500, EAO 1000). The title shows "HI SCORE"
(`HISC_TEXT`) on row 17 (`HISC_ROW`) and the best score on row 18, both
right-justified to column 31, white (user's spec: the blank space at the
logo's lower right; `show_hi`, from `splash`, after the top row; the
score's leading blanks not printed, `print_lead`; the egg's rows 20..23
don't touch them). The title left alone 20 s: the list (`show_list`,
display off meanwhile: the rows under the top status row cleared,
`clear_below`; the egg, if up, gone) for 7 s (`HI_LIST_MS`,
`list_frames`, `list_left`; user's choice: title, list, attract mode),
then attract mode: "HIGH SCORES" (`HI_HEAD`) centred on row 6
(`HI_ROW`), the records on rows 8..17 (`HI_LIST_ROW`) from column 8
(`HI_COL`), " 1. LTR     5000" (16 cells, `hi_row`, the score
right-aligned in 8; Claude's layout); no blink. On it, a press of space
or either joystick's button A starts a game, as on the title; a fresh
Ctrl-V brings the title back with the egg up (`.legg`: `egg_now`, `jp
splash`; its 20 s from the start; Claude's choice, as attract mode's).
A game's score (not attract mode's) enters the table if it beats a
record (`hi_rank`: strict >, a tie under the older one): at game over's
end (`restart`, display off, no sprites, before the game's RAM is
cleared) `hi_enter` moves the records under it down a place (the last
gone), puts the score there with "___", and `enter_initials` shows the
list under "ENTER YOUR INITIALS" (`ENTRY_HEAD`), the top status row as
the game had it. U-boat Killer's entry: a letter typed (A..Z, matrix
rows 2..5, `ent_key`) goes in its slot, BS takes the last one back;
left / right (the arrows or either joystick, `ent_dirs`) pick a letter
(none at first, shown as a blinking "_"; right from none or Z: A, left
from none or A: Z; held: the next after 0.4 s, `HI_REPEAT_DELAY_MS`,
then every 0.1 s, `HI_REPEAT_MS`; held from the entry's start: no
repeat) and space or either joystick's button (A or B) takes it (none
picked: nothing); taken by space or a button, the third ends the entry.
The letter picked blinks in its slot (the title's blink, 0.3 s on, 0.2 s
off: `blink_tick`); after a third typed, a blinking "_" in a fourth
place (the gap before the score). RETURN, or up, ends it once there's a
letter (empty slots become spaces); down takes the last letter back. Up
and down count straight only (neither left nor right held); what's
held as it begins counts once released. Then the list stays 1 s
(`HI_DONE_MS`, `done_frames`), display off, and the title (the best
score updated). **High score file** (disk version only, U-boat
Killer's): `TERRAFNT.HSC` on the default drive, `HSC_SIZE` (71) bytes:
`hi_table`, then a check byte (`HSC_KEY` + the table's bytes), all XORed
with `HSC_XOR` + `HSC_XOR_STEP`·index (`hsc_xor`; keep the scramble out
of changes.txt and the manual, as U-boat Killer's). `hsc_load` (in
`init`, after IM 2 is set up) takes it only with a disk ROM (`H_PHYD` ≠
C9h, else `has_disk` 0: nothing saved either), the exact size, the
check byte, and a sound table (`hsc_check`: BCD digits, initials A..Z or
spaces, each score at most the one above); else the defaults stay.
`hsc_save` (at the entry's end, the list showing) creates or empties
the file and writes it. Disk errors are silently ignored, as U-boat
Killer's (`DISKVE` → `disk_err_vec` → `disk_err_stub`, Abort;
`disk_abort` through `BREAKV` under DOS 2, `DOS1_ABORT` under DOS 1;
all in page 3, RAM before `game_ram`). The FCB and the file's bytes
(`hsc_fcb`, `hsc_buf`) are in `rot_rows` (no game runs then). `bdos`
runs the disk ROM with IM 1 (the BIOS's interrupt handler, as under
Disk BASIC; Claude's choice), then IM 2 again and `hook_arm`:
`disk_timer` calls H.TIMI for 10 s more, so the drive motor goes off.
No HSC file ships (the disk is built fresh).
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
starts at 0 (`score_shown` cleared after the splash: every cell printed).
**Bonus ship:** 2 waves in a row (`BONUS_WAVES`) finished (the frame the
last enemy is gone, `next_wave.done`) with no ship lost (`ship_dies` sets
`wave_lost`; a death in the 0.7 s wait counts against the next wave) gain
a reserve ship, if under `RESERVE_MAX` (5; 4 at the start) and not in game over; that
frame it shows in the reserve and a 0.25 s "happy beep" (`BONUS_60/50`:
C6 E6 G6 C7, tone only) plays on PSG channel A (`bonus_start`, `sfx`), winning over
the shot (whose table runs on unheard). The count (`clean_waves`) starts
again after each pair of waves, a bonus or not (reserve full).
**Boss:** after waves 5 and 10 of a level (`BOSS_AFTER_LIST`; its last
enemy gone, the 0.7 s wait, then `next_wave.go` calls `boss_begin`
instead of the next wave; `boss_done` set when it's over sends the next
`.go` on to the wave), the boss (`images/boss.png`, 64×16, four 16×16
sprites, names 32..44, in the enemies' SAT entries) with its art's top
on line 8, from column 0 going right, cruising at 32 px/s
(`BOSS_SPEED`) between the playfield's edges (columns 0 and 192;
`BOSS_MARGIN` 0), one way in 6 s (Bresenham, reflected at the ends;
`boss_move`, from `next_wave`). It
rains enemy bullets (the same slots, `eb_move`, `eb_draw`, `eb_hit`; at
`BOSS_EB_PCT` 70% of 230 px/s, wave 1's, whatever the wave: `eb_speed`
while `boss_st` isn't 0) from a random one of its 64 columns,
their top on line 24 (`boss_fire`, after `enemy_fire`, which runs on
with no enemy able): one every `boss_gap` px they move, worked out at
its start so that `BOSS_EB_N` (5) are in flight (gap = ceil((158 + the
longest step − 1) / 5), 32 or 33). Player bullets hit it as enemies
(`volley_hits` → `boss_volley`, `boss_px`: a pixel of its art on a line
the bullet covered, where it shows); each hit (`boss_hit`) (re)starts the break sound, as a
pair's; colours `FORM_COLOR_REDDENING`
(5 7 3 2 10 11 9 8 13), the next every 10 hits (`BOSS_HITS`); 10 in the
last: it dies (`boss_dies`: `boss_alive` = the front's living ships then;
the ship's death sound), booming as 8 ship booms side by side
(`BOSS_BOOM_PATTERN`, png2spr.py: the 3 boom images at columns 0, 8, 16,
24, 31, 39, 47, 55, as 4 sprites each, names 48.., in its last colour, the
ship's boom frame counts; `boss_booms`, after `enemy_booms`); then a
frame with nothing (`BS_GAP`: its last boom gone, no text yet); then
"BONUS ddd POINTS" (printed over two frames: its first 8 cells,
`BONUS_HALF`, then the rest, `bonus_rest`; a star in its cells is
erased by `mid_show`) (`BONUS_TEXT`; 500 `BOSS_PTS` by the front's share
then: 500/400/300/250) on `OVER_ROW` from column 8, white, 2 s
(`BONUS_TEXT_MS`; not over GAME OVER; GAME OVER coming during it takes
its place, `bonus_erase`, the bonus running on unseen); then
(`boss_end`, `BS_END`) the text gone, the points (`score_add`,
`PTS_BOSS`), and the next frame (`BS_NEXT`: on the Expert both in one
frame dropped one) the next wave (its bullets wiped as any wave's). A middle-row text
(`mid_show`: `mid_text`, `mid_x0`, `mid_w`) keeps stars and bullets out
of its cells (`over_at`), GAME OVER's or the bonus's. Not a wave for the
bonus ship's count (a ship lost in it counts against the next wave);
the level text stays as the wave before. Behind it all, 15
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
(column 25, line 46), shown from that frame's SAT on. Each pair
is one 16×16 sprite, the 8×16 enemy twice side by side; laid out
as in `images/formation-enemy-0-color-12.png` and starting at its column
25, flies a loop at a constant 102 px/s: northeast across a 35×20 box,
east-southeast across 60×20, southwest and northwest across 35×20, in
1.8 s (`CYCLE_SECS` in `path.py`, the user's choice), 25 px east a cycle
(first 70×58 etc. in 1 s, then halved, then slowed to 1.8 s, then
20 tall, the widths and 1.8 s kept). At its highest the formation's top
(the top pair's sprites' first line, whatever the enemy's art) is 18 lines
under line 8 (`FORM_TOP_GAP`, line 26): the cycle starts with it on
line 46 (`FORM_Y0`). x is mod 272: a pair past the right edge comes
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
at the loop's speed, the square legs' (102.3 px/s; `FREE_VEL_60/50` in
`path.py`, 1/256 px a frame). When its art passes line 8 or 183 it is put
back on that line and turns to a random direction away from it (at line
8: any of the 31 strictly down ones; at 183: up, at least 30° from level,
`BOUNCE_MIN_DEG` (user's spec), 30..150°: the 21 directions 38..58,
`BOUNCE_STEPS`, `BOUNCE_DIRS`; not a mirror). x is mod 272 as the
formation's. A free enemy hit: it shows the ship's three boom images in its
own colour, where it was (the boom's art box from the enemy's left column),
for the ship's boom frame counts, and the ship's death sound (re)starts;
then it's gone. Noise period (R6) priority: death > break > shot.
Collisions (`collide`, after `move_enemies`): each free enemy, where it
shows this frame (after its move), against each living ship of the front
(after the call-up and the move): a pixel of the enemy's art on a pixel of
the ship's art (`touch`; `load_formation` keeps the wave's art rows
rotated 0..7 bits in `rot_rows`, the ship's art rows are `SHIP_ROWS`).
Both die: the enemy booms as when shot, the ship by `ship_dies` (boom,
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
`EB_SPEED_LIST`% of the player's 230 px/s (70% in wave 1, +7% a wave,
119% from wave 8 on; `wave_n` counts the waves, stopping at 255),
Bresenham in 1/100 px (one table for both rates); gone once its bottom
would pass line 183. It hits a ship of the front (`eb_hit`, from `eb_move`)
when its column has a pixel of the ship's art (`SHIP_ROWS`) on a line the
bullet covered that frame (its old top to its new bottom), the front
where it shows (before it moves), its ships living when `eb_move` began
(`eb_alive`, worked out once a bullet reaches the front's lines): the
bullet is gone and the ship dies by `ship_dies` (boom, death sound,
then a hole and the trim); two bullets on one ship: both gone, it dies
once. Dying ships and the incoming ship aren't hit. When a wave begins
(`next_wave`, `eb_wipe`), all enemy bullets go: the next frame's
`eb_move` erases them, the frame the new wave first shows. All bullets are erased before
any is drawn; an enemy bullet sharing a bitmap byte with another (a
volley's or an enemy's) is drawn as the bits of all of them (`eb_draw`,
after the volleys); stars hide in their bytes as in the volleys'. The
SAT's reversal every other frame is done by `upload_sat` (the entries
sent backwards, in vertical blank). The worst frame measured (`make profile`, over the
test's games) is about 14.6 ms on the Expert (16.67 ms a frame; ISSUES.md).
Speed-ups that keep it there: `hit_lines` puts each enemy's art's first
line in `hc_first` and its left column on screen (mod 256) in `hc_x` once
a frame; `volley_hits` only tries, per bullet, the enemies whose art has a
line the volley covered (`hc_list`), and `bullet_hit` skips one whose 8
columns miss the bullet's (`hc_x`) before anything else; `volley_px`
works out a volley's VRAM address once for all its bullets (no middle
text; 31 T between writes); `eb_draw` finds the bits of every bullet in
an enemy bullet's 3 bytes in one pass (`eb_masks`, `ROW_MASKS`);
`move_stars` flags the lines bullets are on (and the middle text's row)
in `LN_FLAGS` (a page at E400h, one byte a line, set from `ln_list` and
cleared from it the next frame; `bullet_at` reads it first), and a star
shown with nothing on its line, or a bullet there but not in its byte
(nor the one it steps into: `bullet_at`), takes a fast path: nothing
without a step, its new bit (`star_px`), or the old byte blanked and the
new one drawn, with one; the full way (`star`) otherwise. `level_text`
prints only the cells that changed (`lw_shown`); the middle-row texts
print patterns only (`print_text` with C = 0: the playfield's colour bytes
are the text's white, but a shown star's, which `mid_show` erases);
`draw_reserves` copies one of 6 pictures made once at power-on
(`make_reserves`, `RES_PICS` at E500h); `load_formation` writes the
patterns straight to the VDP and leaves 7 of the art's 8 rotations to
`rot_step`, one a frame from `collide` (no free enemy can reach the
front's lines that soon: assert). `make profile` (`prof.tcl`, with
`test.tcl`) writes each main-loop routine's worst and mean time and the
heaviest frames to `build/profile-<machine>.txt`.

**Reference speed:** "Galaga" means the user's MSX Galaga dump
(`galaga.rom`, notes in `GALAGA-TECHNIQUES.md`). Its ship moves 1.5 px a
frame on the Expert (60 Hz) = 90 px/s, measured in openMSX from the SAT
while holding →. Terra Front's ship is 20% faster: 108 px/s.

**Version:** every change to the ROM or BIN bumps `VERSION_PATCH` (user's
rule), with its entry in `changes.txt` (player-facing; hidden features as
the eggs: generic or none) and `terrafnt.txt`'s first line, so `make zip`
passes.

**How the user works:** one small step at a time, a spec per step.
Implement only the step asked for. Tunables are constants at the top of
`main.asm`. Speeds and durations are in real time (px/s, s), the same at
50 and 60 Hz: Bresenham on frames (whole pixels + remainder per frame,
from the `RATES_60` / `RATES_50` tables), sound tables per rate.

MSX tools and references: `../MSXDEV.md`, `../docs/README.md`. Read
`../HARD-EARNED-EXPERIENCE.md` before MSX work.

**Open issues:** `ISSUES.md` lists problems found but not dealt with yet
(and only those): read it before working on the game, add new ones
there, and remove an entry when it's fixed.

## Build / run / test

- `make` runs `png2spr.py` (→ `build/sprites.inc`: ship pattern, colour,
  art bounds, nose column, art rows (`SHIP_ROWS`, at the end: the
  patterns before it must stay contiguous); the coming ship's two patterns and where the
  ship's art is in them; the three boom patterns and their colour; the
  reserve ship's rows, colour, art width; the enemies' pair patterns and
  art rows; the formation's pair offsets, from its picture; the boss's four
  patterns and its 3 x 4 boom patterns, 8 ship booms side by side) and `path.py` (→
  `build/path.inc`: the formation loop's tunables and its table, 300
  entries per second of cycle, stepped by Bresenham on frames; only
  `CYCLE_SECS` sets the timing; the free enemies' velocity tables) and `sfx.py` (→ `build/sfx.inc`: the shot, death and break
  sound tables and the bonus beep's; the death one is Skyfighter's `BOOM_SHIP`, the break one its
  `BOOM_ROCK`, byte for byte) and
  `font.py` (→ `build/font.inc`: `FONT`, 6 bytes a glyph; `font.py --raw`
  prints them for the test) and
  `title.py` (→ `build/title.inc`: the splash's SCREEN 2 pattern and colour
  tables from `images/title.png`, 24 rows each RLE-packed alone, so the
  blinking row unpacks by itself; `title.py --raw` prints them unpacked,
  for the test), then `sjasmplus main.asm` (→ `terrafnt.rom`, symbols
  `build/terrafnt.sym`), and `sjasmplus -DBIN main.asm` (→ `terrafnt.bin`,
  symbols `build/terrafnt-bin.sym`), and with mtools `terrafnt.dsk`.
  `build/` is generated; don't edit it.
- `make zip` → `terrafnt_<major>_<minor>_<patch>.zip` (the version from
  `main.asm`): the ROM, BIN, DSK, `terrafnt.txt` (the manual) and
  `changes.txt`; it refuses unless `terrafnt.txt`'s first line is
  `TERRA FRONT v. <version>` and `changes.txt`'s latest entry
  `Version <version>`. `make freeware` / `make playtest` → that zip with `_freeware` / `_playtest` before `.zip`, its ROM, BIN and DSK licensed by `licensezip.py`: "THIS GAME IS FREEWARE" / "SHARE THE ZIPFILE AT WILL", "PLAYTEST COPY" / "DO NOT DISTRIBUTE" (user's spec; only the license lines change: no version bump).
- `make run` runs the Gradiente Expert 1.1 (primary target, 60 Hz),
  `make run-cbios` C-BIOS MSX1 (50 Hz), `make run-nms8250` the Philips
  NMS 8250 (MSX2, 50 Hz); `make rundisk` the disk on the Expert with a
  Panasonic FS-FD1A drive, `make rundisk-nms8250` on the NMS 8250. `FS=1` starts fullscreen, `VIDEO=1` records to
  `videos/<target>-<date>-<time>.avi`, `CMDONLY=1` only prints the openMSX
  command (each on when a nonzero number; see `../MSXDEV.md`).
- `make test` runs `test.tcl` headless on all three machines (log in
  `build/test-<machine>.log`, screenshots `build/shot-<machine>.png` and
  `build/shot-<machine>-call.png`, a call-up in flight). It boots twice:
  first space held from power-on (then let go) doesn't start, joystick 1's
  button A does, then a reset; then the splash's VRAM against
  `title.py --raw` with the three lines of text (read from the ROM) overlaid in
  `font.py --raw`'s glyphs (text shown and hidden; the space glyph blank), the blink every frame (on/off
  frame counts, 0.5 s period between frame interrupts in emulated time, no frame missed), A, C and
  button B changing `entropy` without starting, and space starting; then
  "L1 W1" on the top status row and the score's "0" at its right, the
  rest of the status rows blank. Then: ship start, speed
  over 1 s, both arrows, edge clamps for 1, 2 and 4 ships and their sprite
  X / EC, bullet spawn point, speed, removal at the top, the shot sound's
  length, the 2-volley limit, one shot per press; the pause (a volley in flight, its sound on: F1,
  1 s on PAUSED on the top row in VRAM, R8..R10 0, nothing moved, no
  main loop pass; STOP: the text gone, the volley one step on, the
  sound one entry on and heard; `plan_pause`), the reserve ships' pixels
  and colours in VRAM; three call-ups (side, distance, frames ≤ 0.25 s,
  constant step, frozen front, glue point), a shot during one, C ignored
  with 4 ships, a 4-bullet volley; joystick buttons A (fires, no
  call-up) and B (calls up, no shot), faked by a breakpoint after
  `joy_r14`'s R14 read; ships killed by the test (`tkill k`: the front's
  kth living ship, `ship_dies` called from a breakpoint at `move_bullets`,
  where the removed test keys were read): a boom's images and frame counts
  in the SAT, no bullet from a dying ship, holes, C refused for
  ship-gap-gap-ship, the death sound (every frame: channel C's volume,
  tone, noise period and mixer bits against the table, restarted by each
  death, its noise period winning over the shot's; the last
  one plays out in 1.4 s), a kill with no such ship, trims, ship-gap-ship calling
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
  and checks waves 3..21 (the bonus ships too: 2 reserves written first,
  wave 2 lost ships, a shot fired a frame before wave 4 ends, `tkill 1` kills
  a ship in wave 10: bonuses at the ends of waves 4, 6, 8 and 12, none at 5
  in reserve, the beep every frame as its table; both lists wrap; the top status row's level
  and wave at every wave, L3 W1 at the 21st; none begun a frame before
  its 0.7 s; the frame before each begins, the test puts 3 enemy
  bullets in flight: the model has them gone the frame after; after
  waves 5, 10, 15 and 20 the boss instead, 0.7 s on, and the next wave
  once its bonus is over: `boss_frame`'s model every frame: its patterns
  in VRAM, its start (column 32, colour 5, its gap from the spec), its
  four SAT entries (place, names, colour, booms), its move (32 px/s,
  reflected at 0 and 192), each volley bullet against its art (gone; 10
  hits a colour of the reddening list; the 90th kills it, `boss_alive` =
  the front's living ships at `boss_dies`), its rain (a breakpoint at
  `boss_fire.shoot`: line 24, one of its 64 columns, exactly every gap px
(at 70%); a break sound start per hit;
  5 in flight at most, 4 or 5 once going; the enemy bullet model takes
  them), its booms' frames, the one empty frame, "BONUS ddd POINTS" (its first half on its
  first frame) every frame of its 2 s,
  then the text gone and one `PTS_BOSS` score, the next frame the next
  wave (no frame dropped from its start to its bonus's end; this
  part's wave begin frames: not checked); boss 1
  fought all through by a 4-ship front (90 hits, the score written 0
  first: 250 after it, no frame dropped), bosses 2..4 with 1 hit left
  (written) by 1-, 2- and 3-ship fronts (500, 400, 300); the test steers
  under it and fires every other frame, enemy bullets not hitting ships).
  Then the enemy bullets' levels (rolls forced to hit): the
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
  killed (`tkill 1 2 3 4`): it's called up, no game over; killed again:
  GAME OVER in the middle row that frame (VRAM against `font.py --raw`),
  intact every frame of game over (a star and an enemy bullet the test
  puts in it fly through, not drawn in its cells, and show past them), the
  front can't move, shoot or call up, the formation and stars move
  (screenshot `build/shot-<machine>-over.png`), space and joystick 2's
  button A pressed a frame before 3 s and held past it ignored, the title exactly 10 s on; the
  title's VRAM (with the game's level and wave, L3 W1, on its top row's
  left and its score, 1450 (the bosses' bonuses from 0), on its right;
  game 2's as written (the table's last), "500" after game 3), no sprites, a held space not starting; the new game as at
  power-on (RAM, first wave, patterns, silent, status rows, 4 reserves).
  Then twice no reserves, the front killed: joystick 1's button A, then
  space, seen exactly at 3 s goes to the title at once; the second time
  during a boss's bonus text (staged in RAM: its empty frame after the booms,
  one ship as it died): the text shows, GAME OVER takes its place (the
  other cells blank), and 2 s after the text came its 500 points, the
  next frame the next wave (L1 W2 on the title). Then the title
  left alone: attract mode, four times. Each: exactly 20 s of title
  first; the top row as the title had it (L1 W1 and the score) and the
  bitmap below blank as it begins, a new game's state; every frame silent
  (R7..R10) and the top row unchanged; a call-up roll (a breakpoint)
  exactly every 5 s, a call-up starting exactly on the heads that could
  (against `call_up`'s start, a snapshot) and none else but an empty
  front's; no dropped frame. The first plays 40 s (C held 1 s, F1 and STOP 0.5 s each ignored: no pause; a game over, staged at 25 s if none came by itself:
  no GAME OVER on any of its frames, the title 10 s on; the front moves
  both ways over 100+ columns, shoots,
  calls up, dodges: each dodge's target, from the threat tried (a
  breakpoint), against the rule), back to the title (its VRAM as before); the second ends at
  joystick 1's button A 3 s in (CTRL alone and V alone, 0.5 s each,
  before it ignored), the third at space 2 s in, the fourth at Ctrl-V
  2 s in, that frame (`egg_now` set by the fourth only); then the title
  with the egg up (`egg_frame`): the egg's VRAM against the picture with
  the spec's lines on rows 20..23 (frames 3, 2 s, 5 s; the version bytes
  and the license lines read from the game's file, the license logged,
  so a licensed copy passes; neither's texts in it in plain), gone
  exactly 5 s on (the title's text, its blink from the start); V alone,
  CTRL alone: nothing; Ctrl-V: the egg; two taps, CTRL released and
  pressed, two taps: still the egg, its count not restarted; a third:
  the license's VRAM; 6 s more with CTRL held: still up, the title's
  count stopped; CTRL released, space: the title's text back, its count
  from 20 s, no game; the license again, taken away by joystick 1's
  button A; Ctrl-V and joystick 1's button A, Ctrl-V and space: each
  takes the egg away (the title's text back), no game; then a press of
  space: a fourth game, as at power-on (Ctrl-V in it: nothing), for the
  final screenshot (before that, games 3 and 4: keys 1 and 2 do
  nothing out of cheat mode). Cheat mode (`cheat_frame`, `cheat_game`):
  the title after game 5: CHEAT without CTRL, CTRL C H E A (CTRL
  released and pressed) T, CTRL C H E X A T: still off; CTRL C H C H E
  A T: on, the logo's colour bytes (rows 1..19) 7 made 2 (`cheat_colours`,
  `::cheat`: every later title check too); game 6: key 1, the boss after
  wave 5 (L1 W5), key 2, a fifth reserve, the per-frame models off; its
  99999998 makes no entry (`hi_enter` not called); game 7 for the
  screenshot. Every wave's end: the bonus model (ship deaths
  seen at `ship_dies`, the streak, the reserve that frame in RAM and VRAM,
  `bonus_start` calls). The score, every frame of the game: each `score_add` call
  (a breakpoint) with the front's living ships before the hit (the front
  then; for a crash, as `collide` began), one call per pair broken and per
  enemy booming (from the enemies' states), the score in RAM the spec's
  sum (50 / 100 by the shares), its cells on the top row's right the frames
  it changed and the next; staged with the collisions, from 99999890
  (written) the three crashes stop it at 99999999. It checks the velocity table (64 directions, the square
  legs' speed), every enemy's boom (images and frame counts), the break
  sound's starts and length, a death-sound start per enemy boom, bounces at
  both lines (not mirrors; the bottom's within `BOUNCE_MIN_DEG`..180−it), no level break-up direction, the SAT's flip and
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
- The high score part of `make test` (`test.tcl`'s last section): the
  table at both boots (the user's), the title's "HI SCORE" lines in
  every title check (`build_titles` from the test's model, `::hi`), the
  list's VRAM every time the title is left alone (`list_check`, 20 s on;
  attract mode at 27 s), game 1's 1450 entering it (tenth: G typed,
  RETURN), games 2 and 3 falling short (game 2's score written as the
  table's last, a tie; game 3's 500: no initials, the table unchanged), `hi_enter` never in
  attract mode; then, after the fourth game's start (the egg's part),
  games 4 and 5 (`hi_game`: the score written, no reserve, the front
  killed, space at 3 s): game 4, 3500 (a tie with ALZ: sixth), A held
  from game over (not typed), the entry's screen, the slot's blink,
  RETURN with no letter, J C BS X typed, RETURN: "JX "; the list's 1 s;
  the title left alone: the list, Ctrl-V on it: the title with the egg,
  its count from the start; 20 s on the list again, space: game 5,
  12345678 (the best), joystick only: right held from game over (nothing),
  right held (A, B after 0.4 s, C 0.1 s later), button A takes, joystick
  2's left (Z, Y), B takes, down takes back, up-right (no end, Z), space
  takes, right (A), button A takes the third: "CZA"; the title's
  12345678. The disk test also puts `TERRAFNT.HSC` on the disk
  (`diskmanipulator import`): boot 1 a wrong check byte (the defaults
  kept), boot 2 a sound one (taken: its last two records unlike the
  defaults); at the end it exports the file and decodes it against the
  table, and checks the drive's LED (`::led_FDD`) is off 8 s after the
  last save.
- `make test-disk` runs the same `test.tcl` on the disk version, booted
  from a copy of `terrafnt.dsk` (`build/test-disk.dsk`) on the Expert
  (with an FS-FD1A) and the NMS 8250 (C-BIOS has no Disk BASIC): env
  `SYMFILE` `build/terrafnt-bin.sym`, `IMAGE` `terrafnt.bin` (the texts
  are read from it, past its 7-byte BLOAD header); logs
  `build/test-disk-<machine>.log`, screenshots `build/shot-disk-<machine>*.png`.
  Run it and `make test` one after the other, not at once
  (`../HARD-EARNED-EXPERIENCE.md`).
- `test.tcl`'s breakpoints are set with `cart_bp`: their body runs only
  while the game is there ("AB" at `CODE_BASE`: 4000h in page 1, the
  cartridge; 8000h for the BIN). While the BIOS boots,
  MSX BASIC's ROM is there, and its code passing one of the game's
  addresses fired them (one that returns early broke the boot on the
  Expert and the NMS 8250 once the code moved).
- `make profile` runs `test.tcl` with `prof.tcl` on one machine
  (`PROF_MACHINE`, default the Expert; `PROF_MS` 14) and writes
  `build/profile-<machine>.txt`: each main-loop routine's worst frame and
  mean, the frames over `PROF_MS` ms, the 40 heaviest with their state.
  openMSX sometimes crashes under Xvfb (ISSUES.md): rerun then.
