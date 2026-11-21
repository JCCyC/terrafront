; ---------------------------------------------------------------------------
; Terra Front - the front (MSX1, 16 KB ROM at 4000h)
;
; SCREEN 2, all black. The top and bottom STATUS_LINES pixel lines are kept
; out of the playfield (for the score and the reserve ships). The front, up
; to FRONT_MAX player ships side by side (their art glued, no pixel
; between), sits at the bottom of the playfield and moves left and right
; at SHIP_SPEED px/s (20% faster than MSX Galaga's 90 px/s, measured on the
; Expert: 1.5 px a frame at 60 Hz), its art reaching both screen edges.
; Fire shoots a volley: a 1x3 bullet straight up from each ship's nose at
; BULLET_SPEED px/s, drawn in the bitmap (the ships fill the 4 sprites a
; line); at most MAX_VOLLEYS in flight, a press with all of them in flight
; is ignored. Each volley plays a 0.25 s laser "cheeoom" on PSG channel A.
; The bottom status area shows the reserve ships at its left, one black
; pixel apart. C calls one up: it leaves the reserve and flies in from the
; side away from the front, with woosh lines, at a constant speed that
; takes CALL_TIME_MS from the far edge, and glues on to the front's side.
; Meanwhile the front can shoot but not move. A call-up needs the front's
; span (first to last ship, holes included) under FRONT_MAX.
; A dying ship shows the three boom images in turn (BOOM*_60 / BOOM*_50
; frames each) and doesn't fire; then its slot is empty, a hole in the
; front, and the front is trimmed to its first and last ships. A ship
; starting to die plays Skyfighter's ship-blown-up sound (1.4 s, U-boat
; Killer's "water, loud") on PSG channel C; another death starts it again.
; It wins over the shot's sound where they clash (the PSG's one noise period).
; An empty front stays where its last ship died, can't move or shoot, and a
; call-up lands there: one starts by itself the frame the front empties. With
; no reserve left, GAME OVER shows in the screen's middle (OVER_ROW), centred
; (no star or bullet is drawn in its cells meanwhile), and the game runs on for GAME_OVER_MS (a press of fire, space or either joystick's
; button A, from OVER_SKIP_MS on cuts it short); then it's back to the title.
; Behind it all, STARS one-pixel STAR_COLOR stars in the playfield's bitmap
; scroll left at STAR_SPEED px/s; one that leaves past column 0 comes back
; at column 255 on a random line. No two stars share a line (so never a
; bitmap byte), and a star isn't drawn in a byte a bullet is in (each byte
; has one colour; the bullet's is kept).
; The enemies come in waves: a formation of FORM_PAIRS_N pairs of one enemy
; in one colour, the first wave enemy 0 in FORM_COLOR_LIST's first colour,
; each next wave the next enemy (of ENEMIES) in the next colour (each list
; from its start again after its last); a wave begins WAVE_DELAY_MS after
; the last one's every enemy is gone. Laid out as in images/formation-enemy-*-color-*.png (each pair
; one sprite: the enemy twice, side by side), flies a loop at a constant
; speed: northeast across a 35 x 29 box, east-southeast across a 60 x 29
; one, southwest and northwest across 35 x 29 ones, in path.py's
; CYCLE_SECS (1.8 s), ending 25 px east of where it started (path.py: its
; tunables and table). The loop is
; centred between the top status area and the front's sprite lines. Past the right
; edge, it comes back in from the left (x mod 256 + 16, a pair's width).
; Every other frame the whole SAT is in reverse order: where a line has more
; than 4 sprites (enemies on the front's lines), the ones dropped on one
; frame show on the next, so the front and the enemies flicker but show.
; A bullet that hits an enemy (a pixel of its art on a line the bullet
; covered this frame) is gone. An enemy in a pair: the pair breaks up, with
; U-boat Killer's "miss" boom on PSG channel B, and each of its two enemies
; flies on alone, at a random one of FREE_DIRS directions, at the loop's
; speed; at the playfield's top or bottom line it turns to a random
; direction away from it (not a mirror), and past the right or left edge it
; comes back on the other side, as the formation. A free enemy hit
; explodes where it is, the ship's boom images in its colour, with the
; ship's death sound. The enemies' sprites take turns in the SAT (its order
; rotates every frame), so a fifth sprite on a line flickers instead of
; staying hidden (turns of two frames: one straight, one reversed; on lines
; of up to 7 sprites no sprite is dropped two frames running).
; The enemies shoot: every EB_ROLL_MS a roll, one in EB_CHANCE, fires a
; bullet (the player's shape, going down) from a random enemy, in a pair or
; free, whose art's last line is at least EB_CLEAR lines above the front's
; art's first (none: no bullet), with fewer in flight than the wave's most
; (EB_MAX_LIST); their speed is a share of BULLET_SPEED that grows with the
; wave (EB_SPEED_LIST). One that hits a ship (a pixel of its art on a line
; the bullet covered this frame, the front where it shows) is gone and the
; ship dies (as by a test key). They're gone at the playfield's bottom, and
; all of them as a new wave shows. A bitmap byte two bullets share holds both.
; The score (8 BCD digits, 99999999 at most) shows on the top status row's
; right: BREAK_PTS a pair broken up, FREE_PTS a free enemy's death (shot or
; crashing into a ship), with a one-ship front; with more, the front's share
; (SHARE_2..4 %) by its living ships before the hit.
; BONUS_WAVES waves in a row finished (each one's last enemy gone) with no
; ship lost: a reserve ship more, if the reserve has room (RESERVE_MAX),
; with a 0.25 s "happy beep" on PSG channel A (it wins over the shot's).
; After waves 5 and 10 of a level (BOSS_AFTER_LIST), the boss
; (images/boss.png, four sprites) instead of the next wave: it cruises left
; and right at the playfield's top, BOSS_MARGIN px from either edge, one way
; in BOSS_TRAVERSE_MS, and rains bullets (the enemies', at BOSS_EB_PCT % of
; BULLET_SPEED) from random columns of its lower edge at the rate that keeps
; BOSS_EB_N in flight. It starts in FORM_COLOR_REDDENING's first colour and
; takes the next every BOSS_HITS hits (each with the break sound);
; BOSS_HITS in its last and it dies:
; eight ship booms side by side, then "BONUS ddd POINTS" (BOSS_PTS by the
; front's share as it died) in the screen's middle for BONUS_TEXT_MS, then
; the points, and the next wave.
; It starts with a splash screen, images/title.png (title.py), with
; "(C) 2026 JCCYC" and "HTTPS://RETROPOLIS.COM.BR" on rows 21 and 22 and
; "PRESS SPACE OR FIRE TO BEGIN" on row 23, centred, in the game's font
; (U-boat Killer's, images/font.png, font.py; print_text, for all the
; game's text), the last one blinking BLINK_ON_MS on and BLINK_OFF_MS
; off; space (or either
; joystick's button A) starts the game. Meanwhile the keyboard and the
; joysticks are polled as fast as the loop goes, and the time of every
; press and release (the polls so far, and R) is mixed into entropy, kept
; for later (unused for now).
; Attract mode: the title left alone TITLE_WAIT_MS, a pseudo-game plays for
; ATTRACT_MS (game over's end, if it comes first, ends it too; no GAME
; OVER shows, the enemies just fly on), silent, the
; top status row kept as the title had it (the last game's level, wave and
; score; none at power-on): a pseudo-player moves the front to random
; columns (standing still a random while at each), now and then (at random)
; moves it clear of the first enemy bullet or free enemy it sees close
; above it, presses fire at random,
; and every ATTRACT_CALL_MS calls up a reserve ship with a chance of 1 in
; ATTRACT_CALL_CHANCE, through the game's own controls code (virtual keys).
; A press of fire (space or either joystick's button A) ends it at once;
; then, and at its end, it's back to the title.
; Controls: left / right arrows, space (fire), C (call-up); or either
; joystick (button A fires, B calls up). Test keys 1..4 kill the front's
; first..fourth ship. Fire, call-up and the test keys are edge-triggered:
; one action per press.
; Speeds are Bresenham on frames (whole pixels plus a remainder per frame,
; per frame rate), so they're the same in px/s at 50 and 60 Hz.
; ---------------------------------------------------------------------------

; ---- Version ---------------------------------------------------------------

; Stored at 4010h, right after the cartridge header: major, minor (bytes),
; patch (word, little-endian)
VERSION_MAJOR   equ 0
VERSION_MINOR   equ 1
VERSION_PATCH   equ 0

; ---- Tunables --------------------------------------------------------------

BG_COLOR        equ 1           ; black
STATUS_LINES    equ 8           ; top and bottom pixel lines kept for status
SHIP_SPEED      equ 108         ; px/s: 1.2 x MSX Galaga's 90 px/s
BULLET_SPEED    equ 230         ; px/s, straight up
BULLET_H        equ 3           ; the bullet is 1 px wide, BULLET_H tall
BULLET_COLOR    equ 15          ; white
MAX_VOLLEYS     equ 2           ; volleys (a bullet from each ship) in flight at once
FRONT_MAX       equ 4           ; ships in the front at most
RESERVES        equ 4           ; reserve ships at the start
RESERVE_MAX     equ 5           ; ... and at most (a bonus ship: none past it)
BONUS_WAVES     equ 2           ; waves in a row finished with no ship lost: a reserve ship more
CALL_TIME_MS    equ 250         ; a call-up's flight from the far edge takes at most this
RESERVE_X       equ 0           ; the first reserve ship's art's left column
RESERVE_GAP     equ 1           ; black pixels between two reserve ships
BOOM1_60        equ 6           ; frames each boom image shows, at 60 Hz ...
BOOM2_60        equ 4
BOOM3_60        equ 5
BOOM1_50        equ 5           ; ... and at 50 Hz
BOOM2_50        equ 3
BOOM3_50        equ 4
STARS           equ 15          ; one-pixel stars in the background
STAR_COLOR      equ 14          ; light grey
STAR_SPEED      equ 10          ; px/s to the left: 1 px every 6 frames at 60 Hz, every 5 at 50 Hz
        assert STAR_SPEED < 50  ; at most 1 px a frame
BLINK_ON_MS     equ 300         ; the splash's "PRESS SPACE OR FIRE TO BEGIN" shows this long ...
BLINK_OFF_MS    equ 200         ; ... then is hidden this long
BLINK_ROW       equ 23          ; its character row (lines 184..191), centred on it
CREDIT_ROW      equ 21          ; the splash's credit line (CREDIT_TEXT), centred, not blinking
URL_ROW         equ 22          ; ... and the URL (URL_TEXT) under it
TEXT_COLOR      equ 15          ; white: the game's text
WAVE_DELAY_MS   equ 700         ; a wave's last enemy gone: the next one begins this much later
GAME_OVER_MS    equ 10000       ; GAME OVER shows this long, the game running on, then the title
OVER_SKIP_MS    equ 3000        ; ... a press of fire from this much on: the title at once
TITLE_WAIT_MS   equ 20000       ; the title this long with no start: attract mode ...
ATTRACT_MS      equ 40000       ; ... plays this long, then the title again
ATTRACT_THINK_MS equ 100        ; the pseudo-player decides on fire (and counts to a call-up) this often
ATTRACT_FIRE_CHANCE equ 2       ; ... fire released: pressed with a chance of 1 in this (a power of 2); held: released
ATTRACT_CALL_MS equ 5000        ; ... every this long, a call-up ...
ATTRACT_CALL_CHANCE equ 2       ; ... with a chance of 1 in this (a power of 2)
ATTRACT_PAUSE_MAX equ 8         ; ... its target column reached: still for 0..this-1 thinks (a power of 2)
ATTRACT_NEAR    equ 3           ; ... the target reached: the front's ship_x within this many px of it
ATTRACT_DODGE_CHANCE equ 1      ; ... at a think, it looks out for a threat with a chance of 1 in this (a power of 2)
ATTRACT_DODGE_LINES equ 40      ; ... seen: an enemy bullet's top, a free enemy's art's last line, this close above the front's art or lower
ATTRACT_DODGE_MARGIN equ 4      ; ... and its column within this many px of the front's; it moves the front this far clear of it
OVER_ROW        equ 12          ; GAME OVER's character row (lines 96..103: the screen's middle), centred on it
OVER_COL        equ (32-OVER_LEN)/2 ; ... its first column
LW_ROW          equ 0           ; the level and wave ("L1 W1"): the top status row ...
LW_COL          equ 0           ; ... from its left; a level is ENEMIES waves, images/enemy-0..9.png
LW_LEN          equ 8           ; ... cells kept for it ("L255 W10")
SCORE_ROW       equ 0           ; the score: the top status row ...
SCORE_LEN       equ 8           ; ... its last cells, right-aligned, no leading zeros (99999999 at most)
SCORE_COL       equ 32-SCORE_LEN
;
; Points: a pair broken up, a free enemy's death (shot, or crashing into a
; ship), with a one-ship front; with more ships, the front's share of them
; (% by its living ships before the hit: SHARE_1 for one ship or none)
BREAK_PTS       equ 50
FREE_PTS        equ 100
SHARE_1         equ 100
SHARE_2         equ 80
SHARE_3         equ 60
SHARE_4         equ 50
;
; Enemy bullets: every EB_ROLL_MS a roll; one in EB_CHANCE fires one
EB_ROLL_MS      equ 250
EB_CHANCE       equ 4           ; (a power of 2)
EB_CLEAR        equ 8           ; a shooter's art's last line at least this many lines above the front's art's first
EB_DX           equ 3           ; a bullet's column in its enemy's 8 (3 and 4: the art's middle)
; their speed in % of BULLET_SPEED, in waves 1, 2, ...; the last from then on
        define EB_SPEED_LIST 70, 77, 84, 91, 98, 105, 112, 119
; at most this many in flight, in waves 1, 2, ...; the last from then on
        define EB_MAX_LIST 3, 3, 3, 4, 4, 4, 5
EB_N            equ 5           ; slots: EB_MAX_LIST's largest
;
; the waves' colours in turn (their enemies: images/enemy-0..9.png in turn)
        define FORM_COLOR_LIST 2, 3, 5, 7, 8, 9, 10, 11, 13
; the same colours by hue, bluest to reddest (the boss's, in turn): from light
; blue (245°) down through cyan (189°), green (126°, 125°), yellow (55°, 50°)
; to red (6°: light, then the more saturated medium), then magenta (302°),
; past red; hues from the TMS9918's usual RGB values
        define FORM_COLOR_REDDENING 5, 7, 3, 2, 10, 11, 9, 8, 13
;
; The boss (images/boss.png): after these waves of a level (its last
; wave's last enemy gone, WAVE_DELAY_MS later), the boss instead of the next wave
        define BOSS_AFTER_LIST 5, 10
BOSS_MARGIN     equ 32          ; it cruises left and right at the playfield's top, this many px from either edge ...
BOSS_TRAVERSE_MS equ 4000       ; ... one way in this long
BOSS_EB_N       equ 5           ; its bullets rain at the rate that keeps this many in flight ...
BOSS_EB_PCT     equ 70          ; ... at this % of BULLET_SPEED (wave 1's, whatever the wave)
BOSS_HITS       equ 10          ; hits a colour: then the next of FORM_COLOR_REDDENING; past its last, it dies
BOSS_PTS        equ 500         ; its death's bonus with a one-ship front (with more, SHARE_2..4 % of it) ...
BONUS_TEXT_MS   equ 2000        ; ... shown this long in the screen's middle (OVER_ROW) after its boom; then the score, the next wave
; (the formation's loop: path.py)

; ---- Layout ----------------------------------------------------------------

PLAY_TOP        equ STATUS_LINES            ; first playfield line
PLAY_BOTTOM     equ 191-STATUS_LINES        ; last playfield line
PLAY_LINES      equ PLAY_BOTTOM+1-PLAY_TOP
BL_SIZE         equ PLAY_BOTTOM/8+2             ; bl_lines: a bullet's lines reach at most the next byte
        assert STARS <= PLAY_LINES && PLAY_LINES < 256

; SHIP_* come from build/sprites.inc (png2spr.py), SHOT_* from build/sfx.inc
; (sfx.py), included with the data at the end
SHIP_TOP        equ PLAY_BOTTOM-SHIP_ART_B  ; the sprite's first line (its art's last row on PLAY_BOTTOM)
SHIP_X_MAX      equ 256-SHIP_ART_W          ; one ship: ship_x is the art's left column, 0..SHIP_X_MAX
BULLET_START    equ SHIP_TOP+SHIP_ART_T-BULLET_H    ; a new bullet's top line: right above the nose
        assert BULLET_START >= PLAY_TOP
        assert SHIP_ART_L < 32              ; the EC bit's 32 px cover the left clip
        assert FRONT_MAX*SHIP_ART_W <= 128  ; a front left of the middle has room on its right

; The formation (FORM_* from build/sprites.inc and build/path.inc): its top
; line when the cycle starts, so that its loop is centred between the
; playfield's first line and the front's sprites' first
FORM_Y0         equ (PLAY_TOP+SHIP_TOP-FORM_H)/2
        assert FORM_Y0-FORM_RISE >= PLAY_TOP && FORM_Y0+FORM_RISE+FORM_H <= SHIP_TOP
; Enemy bullets: a shooter's art's last line at most EB_LAST; the roll
; clock counts 1/300 s (a whole number of them a frame at 50 and 60 Hz)
EB_LAST         equ SHIP_TOP+SHIP_ART_T-EB_CLEAR
EB_TICKS        equ EB_ROLL_MS*300/1000
        assert EB_ROLL_MS*300%1000 == 0 && EB_TICKS+300/50 < 256 && EB_LAST >= PLAY_TOP
        assert (EB_CHANCE & (EB_CHANCE-1)) == 0 && EB_CHANCE <= 256 && EB_DX < 8
        assert BULLET_SPEED*255+100*60 < 65536  ; eb_move's sums (a % up to 255)
FORM_WRAP       equ 256+16      ; x is mod this: a pair off the right edge comes in from the left
        assert FORM_X0 < FORM_WRAP && FORM_ADVANCE < FORM_WRAP
        assert FORM_WRAP-1+FORM_PATH_DX_MAX+FORM_W-16 < 2*FORM_WRAP    ; one wrap at most
        assert FORM_TICKS*2 < 65536 && ENEMIES <= 16

; The boss: its art's box (BOSS_W x BOSS_H, all art) on the playfield's
; first lines, its left column BOSS_X_MIN..BOSS_X_MAX at BOSS_SPEED px/s;
; its bullets' top line BOSS_EB_Y (right under it), gone after BOSS_EB_RUN px
BOSS_Y          equ PLAY_TOP
BOSS_X_MIN      equ BOSS_MARGIN
BOSS_X_MAX      equ 256-BOSS_MARGIN-BOSS_W
BOSS_SPEED      equ (BOSS_X_MAX-BOSS_X_MIN)*1000/BOSS_TRAVERSE_MS
        assert (BOSS_X_MAX-BOSS_X_MIN)*1000%BOSS_TRAVERSE_MS == 0 && BOSS_X_MAX > BOSS_X_MIN
        assert BOSS_SPEED < 50 && BOSS_X_MIN > BOSS_SPEED/50+1 && BOSS_X_MAX+BOSS_SPEED/50+1 < 256   ; (a step reflects off an end once)
BOSS_EB_Y       equ BOSS_Y+BOSS_H
BOSS_EB_RUN     equ PLAY_BOTTOM+2-BULLET_H-BOSS_EB_Y    ; (eb_move: gone once its top would reach line BOSS_EB_Y + this)
        assert BOSS_EB_N <= EB_N && BOSS_EB_RUN+256/50+BOSS_EB_N < 256
; boss_st: none, fighting, booming (one state a boom image), the bonus text
; shown, the bonus's end (next_wave: the text gone, the score), then the
; next wave (next frame: a frame's work each, on the Expert)
BS_NONE         equ 0
BS_FIGHT        equ 1
BS_BOOM         equ 2
BS_BONUS        equ BS_BOOM+BOOM_STAGES
BS_END          equ BS_BONUS+1
BS_NEXT         equ BS_END+1
BONUS_COL       equ (32-BONUS_LEN)/2    ; the bonus text's first column on OVER_ROW

; The enemies: pair k is enemies 2k (left) and 2k+1 (right, 8 px on). In
; a pair both are EN_FORM; once it breaks up, each is EN_FREE, then booms
; (EN_BOOM.., one state a boom image), then EN_GONE.
ENEMY_N         equ FORM_PAIRS_N*2
EN_FORM         equ 0
EN_FREE         equ 1
EN_BOOM         equ 2
EN_GONE         equ EN_BOOM+BOOM_STAGES
        assert ENEMY_N == 8 && FREE_DIRS == 64

; A call-up: the new ship starts with its art just off screen, on the side
; away from the front, and flies to the front's side at CALL_SPEED px/s.
; The longest flight (into an empty front whose last ship died at an edge)
; is CALL_DIST px, which must take at most CALL_TIME_MS at both rates:
; whole frames at 50 Hz.
CALL_DIST       equ 256
CALL_FRAMES_50  equ CALL_TIME_MS*50/1000
CALL_SPEED      equ (CALL_DIST*50+CALL_FRAMES_50-1)/CALL_FRAMES_50
        assert (CALL_DIST*60+CALL_SPEED-1)/CALL_SPEED*1000 <= CALL_TIME_MS*60
        assert CALL_SPEED/50 < 256

; The reserve ships: 8x8 art in the bottom status area's one row of cells
; (SCREEN 2 with INIGRP's names: cell (col, row) at pattern / colour byte
; (row*32 + col)*8), drawn at RESERVE_X + n*RESERVE_STEP
RESERVE_ROW     equ 23
        assert STATUS_LINES == 8 && RESERVE_ROW*8 == PLAY_BOTTOM+1
RESERVE_STEP    equ RESERVE_ART_W+RESERVE_GAP
RESERVE_CELLS   equ (RESERVE_X+(RESERVE_MAX-1)*RESERVE_STEP+RESERVE_ART_W-1)/8+1
RESERVE_VRAM    equ RESERVE_ROW*32*8    ; the row's first cell, from GRPCGP / GRPCOL
        assert RESERVE_X+(RESERVE_MAX-1)*RESERVE_STEP+RESERVE_ART_W <= 256
        assert RESERVES <= RESERVE_MAX && BONUS_WAVES > 0

; Sprite names (16x16 sprites: patterns in steps of 4)
NAME_SHIP       equ 0
NAME_COMING_R   equ 4           ; the ship coming in from the right, its woosh lines behind
NAME_COMING_L   equ 8           ; ... from the left
NAME_BOOM       equ 12          ; the boom images: 12, 16, 20
BOOM_STAGES     equ 3
NAME_ENEMY      equ 24          ; the formation's pair
NAME_ENEMY1     equ 28          ; one enemy alone (in the sprite's left 8 columns)
NAME_BOSS       equ 32          ; the boss: 32, 36, 40, 44, left to right
NAME_BOSS_BOOM  equ 48          ; its booms: 4 sprites a boom image (48.., 64.., 80..)
        assert NAME_BOSS == NAME_ENEMY1+4 && NAME_BOSS_BOOM == NAME_BOSS+16 && NAME_BOSS_BOOM+16*BOOM_STAGES <= 256
SPR_PARK        equ 0C0h        ; a sprite's Y off screen (lines 193..208); below D0h, the end marker
SPR_END         equ 0D0h        ; Y that ends the sprite list
SPR_EC          equ 80h         ; colour byte: early clock, X shifted 32 px left

; Input bits (as the joystick's in PSG R14, 1 = pressed)
IN_LEFT         equ 04h
IN_RIGHT        equ 08h
IN_FIRE         equ 10h
IN_CALL         equ 80h

; ---- Hardware and BIOS -----------------------------------------------------

VDP_DATA        equ 98h
VDP_ADDR        equ 99h
PSG_ADDR        equ 0A0h
PSG_WRITE       equ 0A1h
PSG_READ        equ 0A2h
PPI_B           equ 0A9h        ; the keyboard matrix row selected (read, bit = 0 when pressed)
PPI_C           equ 0AAh        ; bits 0..3 select the row; 4..7 cassette, CAPS LED, click (kept)

PSG_TONE_A      equ 0           ; R0, R1: channel A's tone period
PSG_TONE_B      equ 2           ; R2, R3: channel B's
PSG_TONE_C      equ 4           ; R4, R5: channel C's
PSG_NOISE       equ 6           ; the noise period
PSG_MIXER       equ 7           ; bits 0..5 = 1: tone / noise off; bits 6, 7 the I/O ports' direction
PSG_VOL_A       equ 8
PSG_VOL_B       equ 9
PSG_VOL_C       equ 10
PSG_IO_A        equ 14          ; the joystick port's lines (read)
PSG_IO_B        equ 15          ; selects the joystick port (write)
MIX_TONE_A      equ 01h         ; mixer bit: channel A's tone (0 = on)
MIX_ALL_OFF     equ 3Fh

KEY_ROW         equ 8           ; space bit 0, left bit 4, right bit 7
KEY_SPACE       equ 01h
KEY_LEFT        equ 10h
KEY_RIGHT       equ 80h
KEY_ROW_C       equ 3
KEY_C           equ 01h
KEY_ROW_NUM     equ 0           ; keys 0..7 on bits 0..7
KEYS_KILL       equ 1Eh         ; the test keys 1..4
KEY_ROWS        equ 11          ; keyboard matrix rows 0..10 (9, 10: the keypad, if any)
JOY_A           equ 10h         ; R14: button A (0 when pressed)

MSXID1          equ 002Bh       ; bit 7 set = 50 Hz
WRTVDP          equ 0047h
FILVRM          equ 0056h
LDIRVM          equ 005Ch
INIGRP          equ 0072h
RDPSG           equ 0096h

RG1SAV          equ 0F3E0h
CLIKSW          equ 0F3DBh
FORCLR          equ 0F3E9h
BAKCLR          equ 0F3EAh
BDRCLR          equ 0F3EBh
GRPCOL          equ 0F3C9h      ; SCREEN 2's colour table
GRPCGP          equ 0F3CBh      ; ... pattern table
GRPATR          equ 0F3CDh      ; SCREEN 2's sprite attribute table
GRPPAT          equ 0F3CFh      ; ... and sprite pattern table

; ---- RAM -------------------------------------------------------------------

; IM 2: a 257-byte table of IM2_HI at IM2_TABLE, so any data bus value
; gives the vector IM2_HI*257, where a jp to isr goes
IM2_TABLE       equ 0E800h
IM2_HI          equ 0E9h
IM2_JUMP        equ IM2_HI*257

        struct VOLLEY
Y               byte            ; the bullets' top line, 0 = not in flight
X               block FRONT_MAX ; each front slot's bullet's column, 0 = none
        ends

        struct EN
ST              byte            ; EN_*
LEFT            byte            ; booming: frames its image still shows
XF              byte            ; x's fraction (1/256 px) ...
X               word            ; ... and x: the art's left column, mod FORM_WRAP (256..: -16.. on screen)
YF              byte            ; y's fraction ...
Y               byte            ; ... and y: the art box's top line (the sprite's first)
DIR             byte            ; free: 0..FREE_DIRS-1 (path.py)
        ends

        struct EB
Y               byte            ; an enemy bullet's top line, 0 = not in flight
X               byte            ; ... its column
        ends

        struct STAR
X               byte            ; column
Y               byte            ; line
ON              byte            ; nonzero: drawn in the bitmap at (X, Y)
        ends

        org 0E000h
ram_start:
rates:                          ; copied from RATES_60 or RATES_50
fps:            ds 1
ship_whole:     ds 1            ; SHIP_SPEED / fps
ship_frac:      ds 1            ; ... and its remainder
bullet_whole:   ds 1
bullet_frac:    ds 1
call_whole:     ds 1
call_frac:      ds 1
star_whole:     ds 1
star_frac:      ds 1
form_whole:     ds 1            ; path entries a frame
form_frac:      ds 1
shot_sound:     ds 2            ; SHOT_60 or SHOT_50
death_sound:    ds 2            ; DEATH_60 or DEATH_50
brk_sound:      ds 2            ; BREAK_60 or BREAK_50
vel_table:      ds 2            ; FREE_VEL_60 or FREE_VEL_50
boom_frames:    ds BOOM_STAGES  ; frames each boom image shows
blink_on:       ds 1            ; the splash's text: frames shown ...
blink_off:      ds 1            ; ... and hidden
wave_delay:     ds 1            ; frames from a wave's last enemy gone to the next wave
over_end:       ds 2            ; frames GAME OVER shows
over_skip:      ds 2            ; ... and from which fire cuts it short
eb_tick:        ds 1            ; 1/300 s a frame (the enemy bullets' roll clock)
eb_unit:        ds 2            ; 100 * fps (their Bresenham: 1/100 px a second)
bonus_sound:    ds 2            ; BONUS_60 or BONUS_50
title_wait:     ds 2            ; frames the title shows before attract mode
attract_len:    ds 2            ; ... and frames attract mode plays
think_frames:   ds 1            ; frames between the pseudo-player's thinks
boss_whole:     ds 1            ; BOSS_SPEED / fps
boss_frac:      ds 1
bonus_frames:   ds 1            ; frames the bonus text shows
RATES_SIZE      equ $-rates
frames:         ds 1            ; +1 every frame interrupt
entropy:        ds 2            ; the splash's key press and release times, mixed; never 0 once a key moved
polls:          ds 2            ; the splash's input polls so far
lw_text:        ds LW_LEN+1     ; the level and wave as shown (0-terminated; the title shows the last game's)
score_digits:   ds SCORE_LEN    ; show_score: the score's cells, ASCII ...
score_shown:    ds SCORE_LEN+1  ; ... and as they show (0-terminated; the title shows the last game's; 0: none)

; From here on, cleared for every new game
game_ram:
attract:        ds 1            ; nonzero: attract mode (from splash)
att_left:       ds 2            ; ... its frames left
att_real:       ds 1            ; ... the real input (IN_*) this frame (FFh at the start: all held)
att_quit:       ds 1            ; ... nonzero: fire pressed for real this frame
att_fire:       ds 1            ; ... the pseudo-player's fire (IN_FIRE or 0)
att_call:       ds 1            ; ... its call-up press this frame (IN_CALL or 0)
att_think:      ds 1            ; ... frames to its next think
att_calls:      ds 1            ; ... thinks to its next call-up roll
att_target:     ds 1            ; ... the column it moves the front's ship_x to
att_pause:      ds 1            ; ... thinks it still stands there
att_tw:         ds 1            ; ... attract_dodge: the threat's width - 1
title_left:     ds 2            ; splash: frames until attract mode
input:          ds 1            ; IN_* this frame
input_prev:     ds 1            ; ... and last frame (fire is edge-triggered)
kill_keys:      ds 1            ; the test keys 1..4 held (bits 1..4) this frame
kill_prev:      ds 1            ; ... and last frame
ship_x:         ds 1            ; front slot 0's art's left column, 0..256-front_w
ship_acc:       ds 1            ; Bresenham remainder
; The front: FRONT_MAX slots from the left, SHIP_ART_W px apart. Slot 0
; holds a ship (unless the front is empty); the others may be holes.
front_mask:     ds 1            ; bit i set: a ship (living or dying) in slot i
front_slots:    ds 1            ; slots the front spans (0..FRONT_MAX)
front_w:        ds 1            ; ... in px: front_slots*SHIP_ART_W
boom_stage:     ds FRONT_MAX    ; per slot: 0 = alive (or empty), 1..BOOM_STAGES the boom image shown
boom_left:      ds FRONT_MAX    ; ... and the frames it still shows
reserves:       ds 1
; A call-up, while call_on: the new ship's art's left column is call_target
; + call_rem (from the right) or call_target - call_rem (from the left)
call_on:        ds 1
call_left:      ds 1            ; nonzero: coming from the left
call_target:    ds 1            ; its art's left column once glued
call_rem:       ds 2            ; px still to fly (up to CALL_DIST)
call_acc:       ds 1            ; Bresenham remainder
over_on:        ds 1            ; nonzero: game over
over_text:      ds 1            ; nonzero: GAME OVER shows (game over, not in attract mode)
over_time:      ds 2            ; ... frames since it began
; A text in the screen's middle (OVER_ROW): GAME OVER's or the boss's bonus;
; no star or bullet is drawn in its cells (over_at)
mid_text:       ds 1            ; nonzero: one shows
mid_x0:         ds 1            ; ... its first pixel column
mid_w:          ds 1            ; ... its width in px
; The boss
boss_st:        ds 1            ; BS_*
boss_left:      ds 1            ; booming: frames its image still shows; the bonus: frames its text still shows
boss_x:         ds 1            ; its art's left column (BOSS_X_MIN..BOSS_X_MAX)
boss_acc:       ds 1            ; ... Bresenham remainder
boss_dir:       ds 1            ; nonzero: going left
boss_hits:      ds 1            ; hits in this colour (0..BOSS_HITS-1)
boss_cidx:      ds 1            ; its colour: BOSS_COLORS[boss_cidx] ...
boss_color:     ds 1            ; ... this
boss_eb:        ds 1            ; px its bullets moved since its last one (it fires one every boss_gap px)
boss_gap:       ds 1
boss_alive:     ds 1            ; the front's living ships as it died (its bonus's share)
boss_done:      ds 1            ; nonzero: the boss after this wave is over (next_wave.go: the next wave)
bonus_text:     ds 1            ; nonzero: its bonus text shows (in bonus_buf)
bonus_buf:      ds BONUS_LEN+1
volleys:        ds MAX_VOLLEYS*VOLLEY
ebullets:       ds EB_N*EB      ; the enemies' bullets
eb_acc:         ds 2            ; ... their Bresenham remainder (1/100 px), one for all
eb_step:        ds 1            ; ... this frame's px
eb_clock:       ds 1            ; ... 1/300 s since the last roll
eb_wipe:        ds 1            ; ... nonzero: a new wave began, all of them go (eb_move)
eb_alive:       ds 1            ; eb_move: the front's ships living when it began (FFh: not worked out yet)
eb_slot:        ds 2            ; enemy_fire: a free slot
eb_cand:        ds ENEMY_N*2    ; ... the enemies that can shoot: their bullets' {Y X}
eb_cells:       ds 4            ; the 8-px columns (cells) enemy bullets are in: bit (X/8)%8 of byte X/64
bb_bits:        ds 1            ; bullet_bits: the bits so far
hc_first:       ds ENEMY_N      ; this frame, each enemy's art's first line (FFh: booming or gone), for ...
hc_list:        ds ENEMY_N      ; ... volley_hits: the enemies (0..) whose art has a line the volley covered
hc_n:           ds 1            ; ... how many
hc_i:           ds 1            ; bullet_hit: the enemy tried
bl_lines:       ds BL_SIZE      ; move_stars: bit 80h >> (line%8) of byte line/8: a bullet is on the line
wave_n:         ds 1            ; the wave: 0 the first, up to 255 (then it stays)
level:          ds 1            ; the level: 1 the first, up to 255 (then it stays); its wave: form_enemy+1
score:          ds 4            ; BCD, 8 digits, the lowest two first
score_dirty:    ds 1            ; nonzero: changed since show_score
score_cell:     ds 2            ; ... one cell's text (0-terminated)
wave_lost:      ds 1            ; nonzero: a ship lost since the last wave finished
clean_waves:    ds 1            ; waves finished in a row with no ship lost (0..BONUS_WAVES-1)
bullet_acc:     ds 1            ; Bresenham remainder, one for all (volleys keep their spacing)
bullet_step:    ds 1            ; this frame's px
pat_hi:         ds 1            ; GRPCGP's high byte with the VDP's write bit
col_hi:         ds 1            ; ... GRPCOL's
stars:          ds STARS*STAR
star_acc:       ds 1            ; Bresenham remainder
star_step:      ds 1            ; this frame's px (0 or 1)
rand_seed:      ds 2            ; xorshift state, never 0
sfx_ptr:        ds 2            ; the shot sound's next frame in its table, 0 = silent
shot_mix:       ds 1            ; mixer bits the shot sound switches on now
death_ptr:      ds 2            ; the death sound's next frame in its table, 0 = silent
death_mix:      ds 1            ; ... the mixer bits it switches on now
brk_ptr:        ds 2            ; the same for the break sound
brk_mix:        ds 1
bonus_ptr:      ds 2            ; the happy beep's next frame in its table, 0 = silent
psg_io:         ds 1            ; mixer bits 6..7 as the BIOS set them
sat_w:          ds 2            ; GRPATR with the VDP's write bit
key_state:      ds KEY_ROWS+2   ; the splash's last poll: keyboard rows 0.., joysticks 1 and 2 (R14)
key_prev:       ds KEY_ROWS+2   ; ... and the one before
frames_seen:    ds 1            ; frames when the splash last blinked
blink_left:     ds 1            ; frames until the text shows or hides
blink_shown:    ds 1            ; nonzero: the text shows
; The formation: its left column when this cycle started (0..FORM_WRAP-1),
; plus FORM_PATH's offset at form_tick (0..FORM_TICKS-1)
form_x:         ds 2
form_tick:      ds 2
form_acc:       ds 1            ; Bresenham remainder
form_enemy:     ds 1            ; its enemy (0..ENEMIES-1) ...
form_color:     ds 1            ; ... and colour (FORM_COLORS[form_cidx]), the wave's
form_cidx:      ds 1            ; 0..FORM_COLORS_N-1
wave_wait:      ds 1            ; every enemy gone: frames until the next wave, else 0
form_rows:      ds 2            ; its art's 16 rows (ENEMY_PATTERN's left half)
form_art_t:     ds 1            ; its art's first row ...
form_art_b:     ds 1            ; ... and last
rot_rows:       ds 8*16         ; form_rows rotated right 0..7 bits, 16 rows each
col_alive:      ds 1            ; collide: the ships living when it began
col_hit:        ds 1            ; ... nonzero: this enemy touched one
col_n:          ds 1            ; ... the lines both arts' rows are on
col_erow:       ds 1            ; ... the enemy's row on the first
col_srow:       ds 2            ; ... the ship's (in SHIP_ROWS)
col_ex:         ds 2            ; ... the enemy's art's left column + 7
enemies:        ds ENEMY_N*EN
enemy_rot:      ds 1            ; the enemies' first entry in the SAT (0..ENEMY_N-1), one back every other frame
sat_flip:       ds 1            ; nonzero: this frame's SAT is in reverse order
enemy_sat:      ds ENEMY_N*4    ; their entries (pair k: 2k and 2k+1) before the rotation
sat_buf:        ds (FRONT_MAX+1+ENEMY_N)*4+1    ; the front's slots, the incoming ship, the enemies, the end marker
SAT_SIZE        equ $-sat_buf
reserve_buf:    ds (RESERVE_CELLS+1)*8  ; the reserve ships' cells' patterns (+1: a ship's spill)
RAM_SIZE        equ $-ram_start
GAME_RAM_SIZE   equ $-game_ram
        assert $ <= IM2_TABLE

; ---- Cartridge header -------------------------------------------------------

        output "terrafnt.rom"
        org 4000h
        db "AB"
        dw init
        ds 12,0
        assert $ == 4010h
        db VERSION_MAJOR, VERSION_MINOR
        dw VERSION_PATCH

; ---- Init ------------------------------------------------------------------

init:
        ld a,BG_COLOR
        ld (FORCLR),a
        ld (BAKCLR),a
        ld (BDRCLR),a
        xor a
        ld (CLIKSW),a
        call INIGRP             ; SCREEN 2, all black, sprites cleared

        ld a,(RG1SAV)
        or 02h                  ; 16x16 sprites
        and 0BFh                ; display off until the splash is drawn
        ld b,a
        ld c,1
        call WRTVDP

        ld hl,ram_start         ; RAM starts as anything
        ld de,ram_start+1
        ld bc,RAM_SIZE-1
        ld (hl),0
        ldir

        ld hl,RATES_60
        ld a,(MSXID1)
        rla
        jr nc,.hz60
        ld hl,RATES_50
.hz60:  ld de,rates
        ld bc,RATES_SIZE
        ldir

        di
        ld hl,IM2_TABLE
        ld de,IM2_TABLE+1
        ld bc,256
        ld (hl),IM2_HI
        ldir
        ld a,0C3h               ; jp isr
        ld (IM2_JUMP),a
        ld hl,isr
        ld (IM2_JUMP+1),hl
        ld a,IM2_TABLE/256
        ld i,a
        im 2
        ei
        jr new_game

; Game over's end: back to the title, the game's RAM as at power-on
restart:
        call show_score         ; (score_shown: the game's last score, for the title; not attract mode's)
        call display_off
        ld hl,(GRPATR)          ; no sprites on the title
        call vdp_write
        ld a,SPR_END
        out (VDP_DATA),a
        ld hl,game_ram
        ld de,game_ram+1
        ld bc,GAME_RAM_SIZE-1
        ld (hl),0
        ldir
new_game:
        call splash
        call load_formation     ; the first wave's (form_enemy, form_cidx: 0)
        ld a,1
        ld (level),a
        call level_text         ; L1 W1 (attract mode: none, the top row as the title had it)
        ld a,(attract)
        or a
        jr nz,.shown
        ld hl,score_shown       ; (the title's, the last game's) not printed yet: every cell
        ld b,SCORE_LEN
.unshown:
        ld (hl),0
        inc hl
        djnz .unshown
        ld a,1
        ld (score_dirty),a
        call show_score         ; 0
.shown:

        ld hl,SHIP_PATTERN      ; the six ship patterns follow each other
        ld de,(GRPPAT)
        ld bc,(3+BOOM_STAGES)*32
        call LDIRVM
        assert COMING_R_PATTERN == SHIP_PATTERN+32 && COMING_L_PATTERN == SHIP_PATTERN+64
        assert BOOM_PATTERN == SHIP_PATTERN+96
        ld hl,(GRPPAT)          ; the boss and its booms
        ld de,NAME_BOSS*8
        add hl,de
        ex de,hl
        ld hl,BOSS_PATTERN
        ld bc,(4+4*BOOM_STAGES)*32
        call LDIRVM
        assert BOSS_BOOM_PATTERN == BOSS_PATTERN+4*32 && BOSS_W == 64 && BOSS_H == 16
        assert NAME_SHIP == 0 && NAME_COMING_R == 4 && NAME_COMING_L == 8 && NAME_BOOM == 12
        ld hl,(GRPCOL)          ; the playfield's bitmap: the bullets' colour
        ld de,PLAY_TOP/8*256
        add hl,de
        ld bc,(PLAY_BOTTOM+1-PLAY_TOP)/8*256
        ld a,BULLET_COLOR*16+BG_COLOR
        call FILVRM
        assert PLAY_TOP%8 == 0 && (PLAY_BOTTOM+1)%8 == 0

        ld a,SHIP_X_MAX/2       ; one ship in the middle
        ld (ship_x),a
        ld a,1
        ld (front_mask),a
        ld (front_slots),a
        ld a,SHIP_ART_W
        ld (front_w),a
        ld a,RESERVES
        ld (reserves),a
        ld hl,FORM_X0
        ld (form_x),hl
        call form_place         ; (the enemies start EN_FORM: RAM is cleared)
        assert EN_FORM == 0
        ld a,IN_FIRE|IN_CALL    ; armed only once released (read_input moves it to input_prev)
        ld (input),a
        ld a,KEYS_KILL
        ld (kill_keys),a
        ld a,(GRPCGP+1)         ; (SCREEN 2's pattern table: at 0000h or 2000h)
        or 40h
        ld (pat_hi),a
        ld a,(GRPCOL+1)
        or 40h
        ld (col_hi),a
        ld hl,(GRPATR)
        set 6,h
        ld (sat_w),hl
        ld a,SPR_END
        ld (sat_buf+SAT_SIZE-1),a

        call init_sound
        call init_stars         ; (drawn by the first move_stars)
        ld a,(attract)
        or a
        call nz,attract_init
        call build_sat
        ld hl,(GRPCOL)          ; the reserve ships' colour, once (draw_reserves: patterns only)
        ld de,RESERVE_VRAM
        add hl,de
        ld bc,RESERVE_CELLS*8
        ld a,RESERVE_COLOR*16+BG_COLOR
        call FILVRM
        ld a,RESERVES
        call draw_reserves

        call display_on

main_loop:
        halt
        call upload_sat         ; last frame's sprites, in vertical blank
        call read_input
        call booms              ; before kill: a new boom's first image shows its full count
        call enemy_booms        ; ... and before the hits
        call boss_booms
        call kill
        call move_bullets       ; first: in vertical blank, and a volley gone frees its slot; hits
        call fire               ; (hits too; both against the enemies where they show now)
        call enemy_fire         ; from the enemies where they show now
        call boss_fire          ; ... and the boss
        call eb_draw            ; after the volleys are drawn: a shared byte holds both
        call move_stars         ; after the bullets (fire's too): a star in their bytes hides
        call call_up            ; before move_ship: the front stays put while one runs
        call game_over          ; after it: an empty front with none flying has no reserve
        jp c,restart
        call move_ship
        call move_formation
        call form_place
        call move_enemies       ; (a pair broken this frame: its enemies start from its place)
        call collide            ; after the moves: where the enemies and the front show
        call next_wave          ; after them: a new wave shows from this frame's SAT on
        call show_score         ; after the hits and collisions
        ld a,(attract)
        or a
        jr nz,.quiet            ; attract mode: no sound
        call sfx
        call brk_sfx            ; after sfx: its noise period wins over the shot's ...
        call death              ; ... and the death sound's over both
.quiet: call build_sat
        jr main_loop

; The frame interrupt: reading the VDP's status acknowledges it
isr:    push af
        in a,(VDP_ADDR)
        ld a,(frames)
        inc a
        ld (frames),a
        pop af
        ei
        reti

; ---- Splash ----------------------------------------------------------------

; The title screen (images/title.png) until space or either joystick's
; button A goes down (a press: held from before doesn't count), or for
; TITLE_WAIT_MS (then attract is set: attract mode); it leaves the display
; off and SCREEN 2's tables cleared, all black (attract mode: but the top
; status row, as the title had it). Busy-polls the
; inputs; every change (a key or button going down or up) mixes the time,
; in polls since the splash began, into entropy.
splash:
        ld hl,TITLE_PAT_ROWS
        ld de,(GRPCGP)
        call unpack_rows
        ld hl,TITLE_COL_ROWS
        ld de,(GRPCOL)
        call unpack_rows
        ld hl,lw_text           ; the last game's level and wave (at power-on: none)
        ld de,LW_ROW*256+LW_COL*8
        ld c,TEXT_COLOR*16+BG_COLOR
        call print_text
        ld hl,score_shown       ; ... and score, right-aligned (none at power-on)
        ld de,SCORE_ROW*256+SCORE_COL*8
.lead:  ld a,(hl)
        cp ' '                  ; (the leading blanks not printed: the picture stays)
        jr nz,.score
        inc hl
        ld a,e
        add a,8
        ld e,a
        jr .lead
.score: call print_text
        ld hl,CREDIT_TEXT       ; the credit and URL, centred, staying
        ld de,CREDIT_ROW*256+(32-CREDIT_LEN)/2*8
        call print_text
        ld hl,URL_TEXT
        ld de,URL_ROW*256+(32-URL_LEN)/2*8
        call print_text
        call print_press
        call display_on
        ld hl,(title_wait)
        ld (title_left),hl
        ld a,(blink_on)
        ld (blink_left),a
        ld a,1
        ld (blink_shown),a
        ld a,(frames)
        ld (frames_seen),a
        call poll_inputs        ; what's held now isn't a press
.poll:  ld hl,(polls)
        inc hl
        ld (polls),hl
        call poll_inputs
        ld hl,key_prev+KEY_ROW  ; space: down now, up before
        ld a,(key_state+KEY_ROW)
        cpl
        and (hl)
        and KEY_SPACE
        jr nz,.go
        ld hl,key_prev+KEY_ROWS ; either joystick's button A: the same
        ld a,(key_state+KEY_ROWS)
        cpl
        and (hl)
        ld b,a
        inc hl
        ld a,(key_state+KEY_ROWS+1)
        cpl
        and (hl)
        or b
        and JOY_A               ; either joystick's button A
        jr nz,.go
        ld a,(frames)
        ld hl,frames_seen
        cp (hl)
        jr z,.poll
        ld (hl),a               ; a new frame (the loop keeps up: one at a time)
.blink: call blink
        ld hl,(title_left)
        dec hl
        ld (title_left),hl
        ld a,h
        or l
        jr nz,.poll
        inc a                   ; left alone: attract mode
        ld (attract),a
        call display_off
        ld hl,(GRPCGP)          ; the tables cleared from row 1 on (the top row stays)
        inc h
        ld bc,23*256
        xor a
        call FILVRM
        ld hl,(GRPCOL)
        inc h
        ld bc,23*256
        ld a,BG_COLOR*16+BG_COLOR
        jp FILVRM
        assert LW_ROW == 0 && SCORE_ROW == 0
.go:    call display_off
        ld hl,(GRPCGP)
        ld bc,24*256
        xor a
        call FILVRM
        ld hl,(GRPCOL)
        ld bc,24*256
        ld a,BG_COLOR*16+BG_COLOR
        jp FILVRM

; One frame of the splash's blinking text: after blink_on frames shown,
; its cells' colours go all black for blink_off frames, then white again
blink:
        ld hl,blink_left
        dec (hl)
        ret nz
        ld a,(blink_shown)
        xor 1
        ld (blink_shown),a
        ld c,TEXT_COLOR*16+BG_COLOR
        ld a,(blink_on)
        jr nz,.set
        ld c,BG_COLOR*16+BG_COLOR
        ld a,(blink_off)
.set:   ld (hl),a
; "PRESS SPACE OR FIRE TO BEGIN", centred on BLINK_ROW, in colour C
print_press:
        ld hl,PRESS_TEXT
        ld de,BLINK_ROW*256+(32-PRESS_LEN)/2*8
; Text in the game's font (font.py) on SCREEN 2: HL = the text, ASCII
; 20h..5Fh, 0-terminated; DE = its first cell (row*256 + column*8); C = the
; colour byte (foreground*16 + background) for all 8 lines of its cells.
; A glyph's FONT_ROWS rows go on its cell's lines 0..5, lines 6..7 blank.
; At least 29 T a byte: safe outside vertical blank. Keeps C.
print_text:
.ch:    ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        push de
        sub ' '
        ld l,a
        ld h,0
        add hl,hl
        push hl
        add hl,hl
        pop de
        add hl,de               ; FONT_ROWS = 6 bytes a glyph
        ld de,FONT
        add hl,de
        ex (sp),hl              ; HL = the cell, the glyph on the stack
        push hl
        ld de,(GRPCGP)
        add hl,de
        call vdp_write
        pop de
        pop hl
        ld b,FONT_ROWS
.row:   ld a,(hl)               ; 37 T a byte
        out (VDP_DATA),a
        inc hl
        djnz .row
        xor a
        ld b,8-FONT_ROWS
.gap:   out (VDP_DATA),a        ; 32 T
        nop
        nop
        djnz .gap
        ld hl,(GRPCOL)
        add hl,de
        call vdp_write
        ld a,c
        ld b,8
.col:   out (VDP_DATA),a        ; 32 T
        nop
        nop
        djnz .col
        ld hl,8                 ; the next cell
        add hl,de
        ex de,hl
        pop hl
        jr .ch

; The VDP's write address := HL. Keeps BC, DE, HL.
vdp_write:
        ld a,l
        di
        out (VDP_ADDR),a
        ld a,h
        or 40h
        out (VDP_ADDR),a
        ei
        ret

; key_prev = key_state; key_state = the keyboard's rows 0..KEY_ROWS-1 and
; both joysticks' R14 (bit = 0 when pressed); each byte that changed
; mixes the time into entropy
poll_inputs:
        ld hl,key_state
        ld de,key_prev
        ld bc,KEY_ROWS+2
        ldir
        ld hl,key_state
        ld b,0                  ; the row
.row:   di
        in a,(PPI_C)
        and 0F0h
        or b
        out (PPI_C),a
        in a,(PPI_B)
        ei
        call .put
        inc b
        ld a,b
        cp KEY_ROWS
        jr c,.row
        ld b,03h                ; joystick 1 (as read_joy)
        ld e,0AFh
        call joy_r14
        call .put
        ld b,4Ch                ; joystick 2
        ld e,0DFh
        call joy_r14
.put:   cp (hl)
        ld (hl),a
        inc hl
        ret z
; entropy = xorshift(entropy + polls, xor A (the byte now) xor B (its row
; or port) * 256 xor R * 256); never 0. Keeps B, HL.
mix:    push hl
        ld hl,(entropy)
        ld de,(polls)
        add hl,de
        xor l
        ld l,a
        ld a,r
        xor b
        xor h
        ld h,a
        ld a,h                  ; (rand's xorshift, 7/9/8)
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        or l
        jr nz,.keep
        inc l
.keep:  ld (entropy),hl
        pop hl
        ret

; 24 rows of characters (256 bytes each) to VRAM from DE on, unpacked
; from the RLE streams HL points to (24 words: title.py)
unpack_rows:
        ld b,24
.r:     push bc
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push de
        call unpack
        pop de
        inc d
        pop hl
        inc hl
        inc hl
        pop bc
        djnz .r
        ret

; The RLE stream HL (title.py) to VRAM at DE: n = 1..127, n bytes as they
; are; n = 128..255, the next byte n-126 times; 0, the end. At least 29 T
; a byte: safe outside vertical blank.
unpack:
        di
        ld a,e
        out (VDP_ADDR),a
        ld a,d
        or 40h
        out (VDP_ADDR),a
        ei
.n:     ld a,(hl)
        inc hl
        or a
        ret z
        ld b,a
        jp p,.lit
        sub 126
        ld b,a
        ld a,(hl)
        inc hl
.rep:   out (VDP_DATA),a        ; 32 T
        nop
        nop
        djnz .rep
        jr .n
.lit:   ld a,(hl)               ; 37 T
        out (VDP_DATA),a
        inc hl
        djnz .lit
        jr .n

; The display on or off (R1's blank bit)
display_on:
        ld a,(RG1SAV)
        or 40h
        jr display_r1
display_off:
        ld a,(RG1SAV)
        and 0BFh
display_r1:
        ld b,a
        ld c,1
        jp WRTVDP

; ---- Input -----------------------------------------------------------------

; input = IN_* from the keyboard (arrows, space) and both joysticks
; (button A fires, B calls up); input_prev = the last frame's
read_input:
        ld a,(input)
        ld (input_prev),a
        ld a,(kill_keys)
        ld (kill_prev),a
        in a,(PPI_C)            ; keyboard row KEY_ROW_NUM: the test keys
        and 0F0h
        or KEY_ROW_NUM
        out (PPI_C),a
        in a,(PPI_B)
        cpl
        and KEYS_KILL
        ld (kill_keys),a
        ld c,0
        in a,(PPI_C)            ; keyboard row KEY_ROW
        and 0F0h
        or KEY_ROW
        out (PPI_C),a
        in a,(PPI_B)
        cpl                     ; 1 = pressed
        ld b,a
        and KEY_LEFT
        jr z,.k1
        set 2,c                 ; IN_LEFT
.k1:    ld a,b
        and KEY_RIGHT
        jr z,.k2
        set 3,c                 ; IN_RIGHT
.k2:    ld a,b
        and KEY_SPACE
        jr z,.k3
        set 4,c                 ; IN_FIRE
.k3:    in a,(PPI_C)            ; keyboard row KEY_ROW_C
        and 0F0h
        or KEY_ROW_C
        out (PPI_C),a
        in a,(PPI_B)
        and KEY_C
        jr nz,.k4
        set 7,c                 ; IN_CALL
.k4:    ld b,03h                ; joystick 1: (R15 and AFh) or 03h
        ld e,0AFh
        call read_joy
        ld b,4Ch                ; joystick 2: (R15 and DFh) or 4Ch
        ld e,0DFh
        call read_joy
        ld a,(attract)
        or a
        jr nz,.cpu
        ld a,c
        ld (input),a
        ret
.cpu:   ld hl,att_real          ; attract mode: the real input only quits it (a
        ld a,(hl)               ; press of fire), the pseudo-player's plays
        ld (hl),c
        cpl
        and c
        and IN_FIRE
        ld (att_quit),a
        xor a
        ld (kill_keys),a        ; (no test keys)
        call attract_cpu
        ld (input),a
        ret
        assert IN_LEFT == 04h && IN_RIGHT == 08h && IN_FIRE == 10h && IN_CALL == 80h

; C |= the joystick's left, right, button A (fire) and B (call-up) as IN_*;
; the port is selected in R15 by (R15 and E) or B
read_joy:
        call joy_r14
        cpl                     ; 1 = pressed: bit 2 left, 3 right, 4 A, 5 B
        ld b,a
        and IN_LEFT|IN_RIGHT|IN_FIRE    ; button A fires
        or c
        ld c,a
        bit 5,b                 ; button B calls up
        ret z
        set 7,c                 ; IN_CALL
        ret

; A = the joystick port's R14 (bit = 0 when pressed), the port selected in
; R15 by (R15 and E) or B. Keeps B, C, D, HL.
joy_r14:
        di
        ld a,PSG_IO_B
        out (PSG_ADDR),a
        in a,(PSG_READ)
        and e
        or b
        out (PSG_WRITE),a
        ld a,PSG_IO_A
        out (PSG_ADDR),a
        in a,(PSG_READ)
.r14:   ei
        ret

; ---- Attract mode ----------------------------------------------------------

; Attract mode's start (new_game, after init_stars: rand is seeded): its
; time, the real input all held (a press must come after it), the first
; think in think_frames, the first call-up roll ATTRACT_CALL_MS on, a random
; target column
attract_init:
        ld hl,(attract_len)
        ld (att_left),hl
        ld a,0FFh
        ld (att_real),a
        ld a,(think_frames)
        ld (att_think),a
        ld a,ATTRACT_CALL_MS/ATTRACT_THINK_MS
        ld (att_calls),a
        call rand
        ld (att_target),a
        ret

; A = the pseudo-player's input this frame (IN_*): right or left towards
; att_target (the front's last column at most) until ship_x is within
; ATTRACT_NEAR px of it, then a new random target after a random pause.
; Every think (think_frames): fire held is released, else pressed with a
; chance of 1 in ATTRACT_FIRE_CHANCE; every ATTRACT_CALL_MS of thinks, a
; roll: call-up pressed (for this frame) with a chance of 1 in
; ATTRACT_CALL_CHANCE.
attract_cpu:
        xor a
        ld (att_call),a
        ld hl,att_think
        dec (hl)
        jr nz,.move
        ld a,(think_frames)
        ld (hl),a
        ld a,(att_fire)
        or a
        ld a,0
        jr nz,.fire             ; held: released
        call rand
        and ATTRACT_FIRE_CHANCE-1
        ld a,0
        jr nz,.fire
        ld a,IN_FIRE
.fire:  ld (att_fire),a
        ld hl,att_calls
        dec (hl)
        jr nz,.wait
        ld (hl),ATTRACT_CALL_MS/ATTRACT_THINK_MS
        call rand
.roll:                          ; (test.tcl: A = the roll)
        and ATTRACT_CALL_CHANCE-1
        jr nz,.wait
        ld a,IN_CALL
        ld (att_call),a
.wait:  ld hl,att_pause
        ld a,(hl)
        or a
        jr z,.dodge
        dec (hl)
.dodge: call attract_dodge
.move:  ld c,0                  ; the direction
        ld a,(att_pause)
        or a
        jr nz,.put              ; standing still
        ld a,(front_w)
        neg                     ; the front's last column (256 - front_w)
        ld b,a
        ld a,(att_target)
        cp b
        jr c,.t
        ld a,b
.t:     ld hl,ship_x
        sub (hl)
        jr c,.left
        ld c,IN_RIGHT
        cp ATTRACT_NEAR+1
        jr nc,.put
        jr .there
.left:  neg
        ld c,IN_LEFT
        cp ATTRACT_NEAR+1
        jr nc,.put
.there: call rand               ; reached: a new target, and a pause
        ld (att_target),a
        call rand
        and ATTRACT_PAUSE_MAX-1
        ld (att_pause),a
        ld c,0
.put:   ld a,(att_fire)
        or c
        ld hl,att_call
        or (hl)
        ret
        assert (ATTRACT_FIRE_CHANCE & (ATTRACT_FIRE_CHANCE-1)) == 0 && (ATTRACT_CALL_CHANCE & (ATTRACT_CALL_CHANCE-1)) == 0
        assert (ATTRACT_PAUSE_MAX & (ATTRACT_PAUSE_MAX-1)) == 0 && ATTRACT_PAUSE_MAX <= 256
        assert ATTRACT_NEAR >= (SHIP_SPEED+49)/50 && FRONT_MAX*SHIP_ART_W < 256

; At a think, with a chance of 1 in ATTRACT_DODGE_CHANCE (the front there
; and free to move): the first threat seen (enemy bullets first, then free
; enemies) whose lowest line is ATTRACT_DODGE_LINES above the front's art's
; first or lower, and whose columns (a bullet's one, a free enemy's art's
; 8) come within ATTRACT_DODGE_MARGIN px of the front's: the target becomes
; the place that has the front ATTRACT_DODGE_MARGIN px clear of it, on the
; side away from it (right of it if its middle is left of the front's or
; on it); if that's off the screen, the other side's (at the edge if
; neither fits); no pause. Only that threat is looked at.
attract_dodge:
        ld a,(call_on)
        or a
        ret nz
        ld a,(front_w)
        or a
        ret z
        call rand
        and ATTRACT_DODGE_CHANCE-1
        ret nz
        ld (att_tw),a           ; (0: a bullet's 1 column)
        ld hl,ebullets
        ld b,EB_N
.eb:    ld a,(hl)
        inc hl
        or a
        jr z,.ebn
        cp DODGE_LINE
        jr c,.ebn
        push hl
        push bc
        ld l,(hl)
        ld h,0
        call .threat
        pop bc
        pop hl
        ret c
.ebn:   inc hl
        djnz .eb
        ld a,7                  ; an enemy's art: 8 columns
        ld (att_tw),a
        ld iy,enemies
        ld b,ENEMY_N
.en:    ld a,(iy+EN.ST)
        cp EN_FREE
        jr nz,.enn
        ld a,(form_art_b)
        add a,(iy+EN.Y)
        cp DODGE_LINE
        jr c,.enn
        ld l,(iy+EN.X)
        ld h,(iy+EN.X+1)
        call to_screen
        push bc
        call .threat
        pop bc
        ret c
.enn:   ld de,EN
        add iy,de
        djnz .en
        ret
; Carry: columns HL (signed) .. HL + att_tw come within ATTRACT_DODGE_MARGIN
; px of the front's: the target set to dodge them
.threat:                        ; (test.tcl: HL = the first column)
        push hl
        ld a,(att_tw)
        add a,ATTRACT_DODGE_MARGIN
        ld e,a
        ld d,0
        add hl,de
        ld a,(ship_x)
        ld e,a
        or a
        sbc hl,de               ; e = last column + margin - ship_x: within if 0 <= e < k
        ld a,h
        or a
        jr nz,.no
        ld c,l
        ld a,(front_w)
        ld b,a
        ld a,(att_tw)
        add a,b
        add a,2*ATTRACT_DODGE_MARGIN    ; k = front_w + att_tw + 2 * margin
        cp c
        jr c,.no
        jr z,.no
        pop hl                  ; the first column
        push hl
        ld a,(att_tw)
        add a,ATTRACT_DODGE_MARGIN+1
        ld e,a
        ld d,0
        add hl,de
        ex de,hl                ; DE = the right side's target
        pop hl
        push de
        ld de,-ATTRACT_DODGE_MARGIN
        add hl,de
        ld e,b
        ld d,0
        or a
        sbc hl,de               ; HL = the left side's target
        pop de
        ld a,(att_tw)
        add a,b
        add a,2*ATTRACT_DODGE_MARGIN
        sla c                   ; (e < k < 128) 2e < k: its middle left of the front's or on it
        cp c
        jr c,.left
        jr z,.left
        push hl                 ; right first: it fits if DE + front_w <= 256
        ld l,b
        ld h,0
        add hl,de
        ld a,h
        dec a
        or l                    ; (Z: exactly 256)
        ld a,h
        pop hl
        jr z,.r
        or a
        jr z,.r
        jr .put
.left:  bit 7,h
        jr z,.put               ; fits: 0 or more
.r:     ex de,hl
.put:   bit 7,h                 ; HL clamped to 0..255
        jr z,.pos
        ld hl,0
.pos:   ld a,h
        or a
        ld a,l
        jr z,.set
        ld a,255
.set:                           ; (test.tcl: A = the target)
        ld (att_target),a
        xor a
        ld (att_pause),a
        scf
        ret
.no:    pop hl
        or a
        ret
DODGE_LINE      equ SHIP_TOP+SHIP_ART_T-ATTRACT_DODGE_LINES
        assert DODGE_LINE >= PLAY_TOP && 2*(2*ATTRACT_DODGE_MARGIN+FRONT_MAX*SHIP_ART_W+7) < 256
        assert (ATTRACT_DODGE_CHANCE & (ATTRACT_DODGE_CHANCE-1)) == 0

; ---- Movement --------------------------------------------------------------

; A = this frame's step in pixels: B whole pixels a frame, plus one when
; the remainder D, added to (HL) each frame, reaches fps
bresenham:
        ld a,(fps)
        ld e,a
        ld a,(hl)
        add a,d
        cp e
        jr c,.keep
        sub e
        inc b
.keep:  ld (hl),a
        ld a,b
        ret

; Left or right while one of them is held (not both), the front's art kept
; on screen; not during a call-up, nor with the front empty
move_ship:
        ld a,(call_on)
        or a
        ret nz
        ld a,(front_w)
        or a
        ret z
        ld a,(input)
        and IN_LEFT|IN_RIGHT
        ret z
        cp IN_LEFT|IN_RIGHT
        ret z
        ld c,a
        ld a,(ship_whole)
        ld b,a
        ld a,(ship_frac)
        ld d,a
        ld hl,ship_acc
        call bresenham          ; A = step
        ld b,a
        ld hl,ship_x
        ld a,c
        cp IN_LEFT
        ld a,(hl)
        jr z,.left
        add a,b                 ; no carry: SHIP_X_MAX + a step < 256
        ld c,a
        ld a,(front_w)
        neg                     ; 256 - front_w: the front's last x
        cp c
        jr c,.set               ; past it: there
        ld a,c
        jr .set
.left:  sub b
        jr nc,.set
        xor a
.set:   ld (hl),a
        ret
        assert SHIP_X_MAX+(SHIP_SPEED+49)/50 < 256

; The formation one frame on along its loop: FORM_TICK_RATE path entries
; a second; past the last, the next cycle starts FORM_ADVANCE px east
move_formation:
        ld a,(form_whole)
        ld b,a
        ld a,(form_frac)
        ld d,a
        ld hl,form_acc
        call bresenham
        ld hl,(form_tick)
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld de,-FORM_TICKS
        add hl,de
        jr c,.lap               ; carry: form_tick + step >= FORM_TICKS
        ld de,FORM_TICKS
        add hl,de
        ld (form_tick),hl
        ret
.lap:   ld (form_tick),hl
        ld hl,(form_x)
        ld de,FORM_ADVANCE-FORM_WRAP
        add hl,de
        jr c,.at                ; carry: form_x + FORM_ADVANCE >= FORM_WRAP
        ld de,FORM_WRAP
        add hl,de
.at:    ld (form_x),hl
        ret
        assert FORM_TICK_RATE/50 < FORM_TICKS

; HL = pair C's left column (mod FORM_WRAP), A = its top line, where the
; loop has the formation now. Keeps C, IX.
pair_pos:
        ld hl,(form_tick)
        add hl,hl
        ld de,FORM_PATH
        add hl,de
        ld a,(hl)               ; the loop's dx
        inc hl
        ld b,(hl)               ; ... and dy (signed)
        ld hl,(form_x)
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    push hl                 ; the formation's left column (one wrap at most)
        ld l,c
        ld h,0
        add hl,hl
        ld de,FORM_PAIRS
        add hl,de
        ld e,(hl)               ; the pair's dx ...
        inc hl
        ld a,(hl)               ; ... and dy
        add a,b
        add a,FORM_Y0
        ld b,a
        pop hl
        ld d,0
        add hl,de
        ld de,-FORM_WRAP
        add hl,de
        jr c,.w                 ; carry: it was >= FORM_WRAP
        ld de,FORM_WRAP
        add hl,de
.w:     ld a,b
        ret

; The enemies still in their pairs at their pairs' places: the left one at
; the pair's column, the right one 8 px on (mod FORM_WRAP)
form_place:
        ld ix,enemies
        ld c,0
.p:     ld a,(ix+EN.ST)
        or a                    ; EN_FORM: the pair's both are
        jr nz,.next
        call pair_pos
        ld (ix+EN.Y),a
        ld (ix+EN+EN.Y),a
        ld (ix+EN.X),l
        ld (ix+EN.X+1),h
        ld de,8-FORM_WRAP
        add hl,de
        jr c,.w
        ld de,FORM_WRAP
        add hl,de
.w:     ld (ix+EN+EN.X),l
        ld (ix+EN+EN.X+1),h
.next:  ld de,2*EN
        add ix,de
        inc c
        ld a,c
        cp FORM_PAIRS_N
        jr c,.p
        ret

; Each free enemy one frame on, at its direction's velocity (vel_table:
; whole and 1/256 px a frame); x mod FORM_WRAP. Its art past the playfield's
; top or bottom line: back on it, and a random direction away from it.
move_enemies:
        ld ix,enemies
        ld b,ENEMY_N
.e:     ld a,(ix+EN.ST)
        cp EN_FREE
        jr nz,.next
        push bc
        call free_step
        pop bc
.next:  ld de,EN
        add ix,de
        djnz .e
        ret

free_step:
        ld l,(ix+EN.DIR)
        ld h,0
        add hl,hl
        add hl,hl
        ld de,(vel_table)
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)               ; vx
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)               ; vy
        ld a,d
        add a,a
        sbc a,a                 ; vx's sign: 0 or FFh
        ld l,(ix+EN.XF)
        ld h,(ix+EN.X)
        add hl,de
        adc a,(ix+EN.X+1)
        ld (ix+EN.XF),l
        ld l,h
        ld h,a                  ; HL: the new column, -1.. or ..FORM_WRAP
        bit 7,h
        jr z,.pos
        ld de,FORM_WRAP
        add hl,de
        jr .xs
.pos:   ld de,-FORM_WRAP
        add hl,de
        jr c,.xs                ; carry: it was >= FORM_WRAP
        ld de,FORM_WRAP
        add hl,de
.xs:    ld (ix+EN.X),l
        ld (ix+EN.X+1),h
        ld l,(ix+EN.YF)
        ld h,(ix+EN.Y)
        add hl,bc
        ld (ix+EN.YF),l
        ld (ix+EN.Y),h
        ld a,(form_art_t)
        add a,h
        cp PLAY_TOP
        jr c,.top
        ld a,(form_art_b)
        add a,h
        cp PLAY_BOTTOM+1
        ret c
        ld a,(form_art_b)       ; past the bottom line
        ld b,a
        ld a,PLAY_BOTTOM
        sub b
        ld (ix+EN.Y),a
        ld (ix+EN.YF),0
        call rand_half
        or FREE_DIRS/2          ; up
        ld (ix+EN.DIR),a
        ret
.top:   ld a,(form_art_t)       ; past the top line
        ld b,a
        ld a,PLAY_TOP
        sub b
        ld (ix+EN.Y),a
        ld (ix+EN.YF),0
        call rand_half          ; down
        ld (ix+EN.DIR),a
        ret
        assert FORM_Y0-FORM_RISE >= PLAY_TOP+3  ; (no pair broken past a line)

; A = a random direction 1..FREE_DIRS/2-1 (down; OR FREE_DIRS/2: up)
rand_half:
        call rand
        and FREE_DIRS/2-1
        jr z,rand_half
        ret

; Each booming enemy: the next image when one's frames are over; after the
; last, gone
enemy_booms:
        ld ix,enemies
        ld b,ENEMY_N
.e:     ld a,(ix+EN.ST)
        cp EN_BOOM
        jr c,.next
        cp EN_GONE
        jr nc,.next
        dec (ix+EN.LEFT)
        jr nz,.next
        inc a
        ld (ix+EN.ST),a
        cp EN_GONE
        jr nc,.next
        ld e,a
        ld d,0
        ld hl,boom_frames-EN_BOOM
        add hl,de
        ld a,(hl)
        ld (ix+EN.LEFT),a
.next:  ld de,EN
        add ix,de
        djnz .e
        ret

; Each volley in flight goes up BULLET_SPEED px/s; it's gone once its top
; leaves the playfield. All are erased first (the enemies' bullets too),
; then drawn, so one's erase never takes a pixel of another's.
move_bullets:
        call hit_lines          ; (for this frame's volley_hits, fire's too)
        ld a,(bullet_whole)
        ld b,a
        ld a,(bullet_frac)
        ld d,a
        ld hl,bullet_acc
        call bresenham
        ld (bullet_step),a
        ld ix,volleys
        ld b,MAX_VOLLEYS
.erase: push bc
        ld a,(ix+VOLLEY.Y)
        or a
        jr z,.enext
        ld c,0
        call volley_px
        ld a,(bullet_step)
        ld b,a
        ld a,(ix+VOLLEY.Y)
        ld c,a
        add a,BULLET_H-1
        ld e,a                  ; the lines covered: up to its old bottom ...
        ld a,c
        sub b                   ; (no borrow: Y >= PLAY_TOP > a step)
        ld d,a                  ; ... from its new top
        call volley_hits        ; (a bullet that hits is gone: erased already)
        ld a,(ix+VOLLEY.Y)
        or a
        jr z,.enext             ; every bullet hit
        ld a,d
        cp PLAY_TOP
        jr nc,.keep
        xor a                   ; gone
.keep:  ld (ix+VOLLEY.Y),a
.enext: ld de,VOLLEY
        add ix,de
        pop bc
        djnz .erase
        call eb_move            ; erased too before anything is drawn
        ld ix,volleys
        ld b,MAX_VOLLEYS
.draw:  push bc
        ld a,(ix+VOLLEY.Y)
        or a
        ld c,1
        call nz,volley_px
        ld de,VOLLEY
        add ix,de
        pop bc
        djnz .draw
        ret
        assert PLAY_TOP > (BULLET_SPEED+49)/50

; A new press of fire, with a volley free and a living ship: a bullet from
; each living ship's nose, and the laser sound
fire:
        ld a,(input_prev)
        cpl
        ld b,a
        ld a,(input)
        and b
        and IN_FIRE
        ret z
        call alive_mask
        or a
        ret z
        ld c,a
        ld hl,volleys
        ld de,VOLLEY
        ld b,MAX_VOLLEYS
.find:  ld a,(hl)
        or a
        jr z,.free
        add hl,de
        djnz .find
        ret                     ; all in flight
.free:  push hl
        pop ix
        ld (hl),BULLET_START    ; Y
        inc hl
        ld a,(ship_x)
        add a,SHIP_NOSE_DX
        ld b,FRONT_MAX
.x:     rr c                    ; this slot's ship
        ld (hl),0
        jr nc,.nx
        ld (hl),a               ; its nose's column (> 0)
.nx:    inc hl
        add a,SHIP_ART_W
        djnz .x
        ld de,BULLET_START*256+BULLET_START+BULLET_H-1
        call volley_hits
        ld c,1
        call volley_px
        ld hl,(shot_sound)      ; (re)start the sound
        ld (sfx_ptr),hl
        ret
        assert VOLLEY.Y == 0 && VOLLEY.X == 1 && SHIP_NOSE_DX > 0

; ---- Enemy bullets ---------------------------------------------------------

; A = this wave's (wave_n's) entry in the table HL of B entries (the last
; from then on). Keeps C, DE.
wave_entry:
        ld a,(wave_n)
        cp b
        jr c,.in
        ld a,b
        dec a
.in:    add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld a,(hl)
        ret

; Each enemy bullet in flight erased and moved down this wave's speed
; (BULLET_SPEED * EB_SPEED_LIST's % / 100 px/s); gone if a new wave began
; last frame (eb_wipe: its sprites show from this frame on), or if it hits
; a ship (eb_hit), or once its bottom would leave the playfield
eb_move:
        ld a,0FFh               ; (worked out once a bullet reaches the front's lines)
        ld (eb_alive),a
        call eb_speed
        ld de,(eb_acc)
        add hl,de
        ld de,(eb_unit)         ; 100 * fps: a px
        ld b,0
.div:   or a
        sbc hl,de
        jr c,.dn
        inc b
        jr .div
.dn:    add hl,de
        ld (eb_acc),hl
        ld a,b
        ld (eb_step),a
        ld a,(eb_wipe)
        ld c,a
        ld ix,ebullets
        ld b,EB_N
.e:     ld a,(ix+EB.Y)
        or a
        jr z,.next
        push bc
        ld e,a
        ld d,(ix+EB.X)
        ld c,0
        call bullet_px          ; erased
        pop bc
        inc c
        dec c
        jr nz,.gone             ; a new wave
        ld a,(eb_step)
        add a,(ix+EB.Y)         ; its new top
        cp SHIP_TOP+SHIP_ART_T+1-BULLET_H
        jr c,.keep              ; its new bottom over the front's art
        push bc
        ld c,(ix+EB.Y)
        ld d,(ix+EB.X)
        add a,BULLET_H-1
        ld e,a                  ; the lines covered: its old top to its new bottom
        call eb_hit
        pop bc
        jr c,.gone
        ld a,(eb_step)
        add a,(ix+EB.Y)
        cp PLAY_BOTTOM+2-BULLET_H
        jr c,.keep              ; else its bottom off the playfield
.gone:  xor a
.keep:  ld (ix+EB.Y),a
.next:  inc ix
        inc ix
        djnz .e
        xor a
        ld (eb_wipe),a
        ret
        assert EB == 2 && PLAY_BOTTOM+(BULLET_SPEED*255/100+49)/50 < 256
        assert SHIP_TOP+SHIP_ART_T+1-BULLET_H <= PLAY_BOTTOM+2-BULLET_H

; HL = this wave's enemy bullet speed in 1/100 px a second (BULLET_SPEED *
; EB_SPEED_LIST's %; the boss's, BOSS_EB_PCT, while there is one)
eb_speed:
        ld a,(boss_st)
        or a
        ld a,BOSS_EB_PCT
        jr nz,.pct
        ld hl,EB_PCTS
        ld b,EB_PCTS_N
        call wave_entry
.pct:   ld de,BULLET_SPEED
        ld hl,0
        ld b,8
.mul:   add hl,hl
        rla
        jr nc,.m0
        add hl,de
.m0:    djnz .mul
        ret

; Carry: the enemy bullet in column D, covering lines C..E this frame,
; hits a ship of the front living when eb_move began (eb_alive): a pixel of
; the ship's art (SHIP_ROWS) in column D on one of those lines; the ship
; starts to die (as by a test key; not again if a bullet hit it already).
; Keeps IX.
eb_hit:
        ld a,(eb_alive)
        inc a
        jr nz,.have
        push bc
        push de
        call alive_mask         ; (before any ship this frame's bullets hit dies)
        ld (eb_alive),a
        pop de
        pop bc
.have:  ld a,e
        cp SHIP_TOP+SHIP_ART_T
        jr c,.no                ; above the front's art
        cp SHIP_TOP+SHIP_ART_B+1
        jr c,.e
        ld e,SHIP_TOP+SHIP_ART_B
.e:     ld a,c
        cp SHIP_TOP+SHIP_ART_T
        jr nc,.c
        ld c,SHIP_TOP+SHIP_ART_T
.c:     ld a,e
        sub c
        jr c,.no
        inc a
        ld e,a                  ; E = the lines on the art's rows, from line C
        ld a,(eb_alive)
        ld b,a
        ld a,(ship_x)
        ld h,a
        ld a,d
        sub h                   ; the column on the front's art
        jr c,.no
        ld hl,boom_stage
.slot:  cp SHIP_ART_W
        jr c,.in
        sub SHIP_ART_W
        inc hl
        srl b
        jr nz,.slot
        jr .no                  ; past the front's last ship
.in:    bit 0,b
        jr z,.no                ; no ship living in this slot
        push hl
        ld hl,SHIP_ROWS+1       ; columns 0..7: a row word's high byte
        cp 8
        jr c,.hi
        sub 8
        dec hl                  ; 8..15: its low byte
.hi:    ld b,a
        ld a,80h
        inc b
.bit:   dec b
        jr z,.got
        rrca
        jr .bit
.got:   ld d,a                  ; the column's bit
        ld a,c
        sub SHIP_TOP
        add a,a
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld b,e
.row:   ld a,(hl)
        and d
        jr nz,.hit
        inc hl
        inc hl
        djnz .row
        pop hl
.no:    or a
        ret
.hit:   pop hl
        ld a,(hl)               ; boom_stage
        or a
        call z,ship_dies
        scf
        ret
        assert SHIP_ART_W <= 16 && SHIP_TOP+SHIP_ART_B <= PLAY_BOTTOM

; Every EB_ROLL_MS a roll: one in EB_CHANCE, with fewer enemy bullets in
; flight than this wave's most (EB_MAX_LIST) and an enemy that can shoot
; (eb_can), one of those at random fires a bullet from its art's column
; EB_DX, its top right under the art's last row (eb_draw draws it)
enemy_fire:
        ld a,(eb_tick)
        ld hl,eb_clock
        add a,(hl)
        cp EB_TICKS
        jr nc,.roll
        ld (hl),a
        ret
.roll:  sub EB_TICKS
        ld (hl),a
        call rand
.rolled:                        ; (test.tcl: A = the roll)
        and EB_CHANCE-1
        ret nz
        ld hl,ebullets+(EB_N-1)*EB  ; C = in flight; eb_slot = the first free slot
        ld b,EB_N               ; (from the last: the first free one is kept)
        ld c,0
.cnt:   ld a,(hl)
        or a
        jr z,.free
        inc c
        jr .cn
.free:  ld (eb_slot),hl
.cn:    dec hl
        dec hl
        djnz .cnt
        ld hl,EB_MAXES
        ld b,EB_MAXES_N
        call wave_entry
        cp c
        ret z                   ; as many in flight as the wave's most
        ret c
        ld iy,enemies           ; C = the enemies that can shoot, their
        ld hl,eb_cand           ; bullets' places in eb_cand
        ld b,ENEMY_N
        ld c,0
.can:   push hl
        call eb_can
        pop hl
        jr nc,.cnext
        inc c
        ld e,a                  ; the column
        ld a,(form_art_b)
        add a,(iy+EN.Y)
        inc a
        ld (hl),a               ; Y: under its art
        inc hl
        ld (hl),e
        inc hl
.cnext: ld de,EN
        add iy,de
        djnz .can
        ld a,c
        or a
        ret z                   ; none
        ld b,a
.pick:  call rand
        and ENEMY_N-1
        cp b
        jr nc,.pick
        add a,a
        ld e,a
        ld d,0
        ld hl,eb_cand
        add hl,de
.shoot:                         ; (test.tcl: HL = the bullet's {Y X})
        ld de,(eb_slot)
        ldi
        ldi
        ret
        assert ENEMY_N == 8 && (ebullets+EB_N*EB)/256 == ebullets/256

; Carry: the enemy at IY can shoot: in a pair or free, its art's last line
; on EB_LAST or above, its column EB_DX on screen (A = that column). Keeps
; BC, IY.
eb_can:
        ld a,(iy+EN.ST)
        cp EN_BOOM
        ret nc                  ; booming or gone
        ld a,(form_art_b)
        add a,(iy+EN.Y)
        cp EB_LAST+1
        ret nc                  ; too close to the front
        ld l,(iy+EN.X)
        ld h,(iy+EN.X+1)
        call to_screen
        ld de,EB_DX
        add hl,de
        ld a,h
        or a
        ld a,l
        scf
        ret z                   ; 0..255
        or a
        ret
        assert EN_FORM < EN_BOOM && EN_FREE < EN_BOOM

; Every enemy bullet in flight drawn: its pixels alone, or, where another
; bullet (a volley's or an enemy's) shares a byte with it, each of its bytes
; as the bits of every bullet in it; eb_cells from them all
eb_draw:
        ld hl,eb_cells
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ld hl,ebullets
        ld b,EB_N
.e:     ld a,(hl)
        inc hl
        or a
        jr z,.next
        push bc
        push hl
        ld e,a
        ld d,(hl)
        call eb_cell
        or (hl)
        ld (hl),a
        call eb_alone
        jr nz,.shared
        ld a,d
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld c,(hl)
        call bullet_px          ; its bit alone
        jr .done
.shared:
        ld b,BULLET_H
.row:   call over_at
        jr c,.rnext             ; GAME OVER's
        call bullet_bits
        ld c,a
        ld a,(pat_hi)
        call vdp_at
        ld a,c
        out (VDP_DATA),a
.rnext: inc e
        djnz .row
.done:  pop hl
        pop bc
.next:  inc hl
        djnz .e
        ret

; HL = column D's byte in eb_cells, A = its bit there. Keeps BC, DE.
eb_cell:
        ld a,d
        rlca
        rlca
        and 3
        add a,low eb_cells
        ld l,a
        ld h,high eb_cells
        ld a,d
        rrca
        rrca
        rrca
        and 7
        push hl
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld a,(hl)
        pop hl
        ret
        assert eb_cells/256 == (eb_cells+3)/256

; Z: no other bullet in flight (a volley's or an enemy's) shares a bitmap
; byte with the enemy bullet at column D, top line E. Keeps DE.
eb_alone:
        ld hl,volleys
        ld b,MAX_VOLLEYS
.v:     ld a,(hl)
        or a
        jr z,.nv
        sub e
        add a,BULLET_H-1
        cp 2*BULLET_H-1
        jr nc,.nv               ; their lines apart
        push hl
        ld c,FRONT_MAX
.x:     inc hl
        ld a,(hl)
        or a
        jr z,.nx
        xor d
        and 0F8h
        jr z,.shared
.nx:    dec c
        jr nz,.x
        pop hl
.nv:    ld a,l
        add a,VOLLEY
        ld l,a
        djnz .v
        ld hl,ebullets
        ld bc,EB_N*256          ; C = those in its bytes (itself one)
.e:     ld a,(hl)
        inc hl
        or a
        jr z,.ne
        sub e
        add a,BULLET_H-1
        cp 2*BULLET_H-1
        jr nc,.ne
        ld a,(hl)
        xor d
        and 0F8h
        jr nz,.ne
        inc c
.ne:    inc hl
        djnz .e
        dec c
        ret
.shared:
        pop hl
        or 1                    ; (NZ)
        ret

; A = the bits of every bullet in flight (the volleys' and the enemies') in
; pixel (D, E)'s bitmap byte. Keeps BC, DE.
bullet_bits:
        push bc
        xor a
        ld (bb_bits),a
        ld hl,volleys
        ld b,MAX_VOLLEYS
.v:     ld a,e
        sub (hl)                ; line - the volley's top (0 = none: E is more than BULLET_H)
        cp BULLET_H
        jr nc,.nv
        push hl
        ld c,FRONT_MAX
.x:     inc hl
        ld a,(hl)
        or a
        jr z,.nx                ; no bullet from this slot
        xor d
        and 0F8h
        call z,.bit
.nx:    dec c
        jr nz,.x
        pop hl
.nv:    ld a,l
        add a,VOLLEY
        ld l,a
        djnz .v
        ld hl,ebullets
        ld b,EB_N
.e:     ld a,e
        sub (hl)                ; (0 = none, as above)
        inc hl
        cp BULLET_H
        jr nc,.ne
        ld a,(hl)
        xor d
        and 0F8h
        call z,.bit
.ne:    inc hl
        djnz .e
        pop bc
        ld a,(bb_bits)
        ret
; bb_bits |= column (HL)'s bit. Keeps BC, DE, HL.
.bit:   push hl
        ld a,(hl)
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld a,(hl)
        ld hl,bb_bits
        or (hl)
        ld (hl),a
        pop hl
        ret
        assert PIXEL_BIT/256 == (PIXEL_BIT+7)/256

; ---- Hits ------------------------------------------------------------------

; The volley at IX against the enemies where they show now: each bullet
; whose column has a pixel of a living enemy's art on lines D..E (the lines
; it covered this frame) is gone and the enemy hit (bullet_hit). A volley
; left with no bullet is free. Only the enemies whose art has a line in
; D..E (from hc_first) are tried (hc_list). Keeps DE, IX.
volley_hits:
        ld a,(boss_st)
        cp BS_FIGHT
        jp z,boss_volley
        push de
        ld a,(form_art_t)
        ld b,a
        ld a,(form_art_b)
        sub b
        ld b,a                  ; the art's lines - 1
        ld a,d
        sub b
        jr nc,.lo
        xor a
.lo:    ld d,a                  ; first lines D - that .. E: the art has a line in D..E
        ld hl,hc_first
        ld iy,hc_list
        ld bc,ENEMY_N*256
.c:     ld a,(hl)
        inc hl
        cp d
        jr c,.cn
        cp e
        jr z,.cin
        jr nc,.cn               ; (FFh: booming or gone)
.cin:   ld (iy+0),c
        inc iy
.cn:    inc c
        djnz .c
        pop de
        push iy
        pop hl
        ld a,l
        sub low hc_list
        ld (hc_n),a
        ret z                   ; no enemy on its lines
        push ix
        pop hl
        inc hl                  ; X
        ld b,FRONT_MAX
        ld c,0                  ; bullets left
.b:     ld a,(hl)
        or a
        jr z,.next
        push bc
        push hl
        ld c,a
        call bullet_hit
        pop hl
        pop bc
        jr nc,.keep
        ld (hl),0
        jr .next
.keep:  inc c
.next:  inc hl
        djnz .b
        inc c
        dec c
        ret nz
        ld (ix+VOLLEY.Y),0
        ret

; Carry: column C has a pixel of a living (in a pair or free) enemy's art
; on lines D..E; the first such enemy (0..ENEMY_N-1; of those in hc_list)
; is hit: in a pair, the pair breaks up (each enemy free, at a random
; direction; the break sound); free, it starts to boom (the death sound).
; Keeps DE, IX.
bullet_hit:
        ld hl,hc_list
        ld a,(hc_n)
        or a
        ret z
        ld b,a
.e:     push bc
        push hl
        ld a,(hl)
        ld (hc_i),a
        add a,a
        add a,a
        add a,a                 ; * EN
        ld l,a
        ld h,0
        push de
        ld de,enemies
        add hl,de
        pop de
        push hl
        pop iy
        ld a,(iy+EN.ST)
        cp EN_BOOM
        jr nc,.next             ; booming or gone
        ld a,(iy+EN.X+1)
        or a
        ld a,c
        jr z,.on
        cp 8                    ; at -16..-1 on screen: only columns 0..7 can be in it
        jr nc,.next
        add a,16
.on:    sub (iy+EN.X)           ; the column in its art
        jr c,.next
        cp 8
        jr nc,.next
        call art_px
        jr c,.hit
.next:  pop hl
        inc hl
        pop bc
        djnz .e
        or a
        ret
.hit:   pop hl
        pop bc
        push de
        ld a,(iy+EN.ST)
        or a
        jr nz,.boom
        ld a,(hc_i)
        rrca                    ; odd: a pair's right one
        jr nc,.pair
        ld de,-EN
        add iy,de
.pair:  call free_en
        ld de,EN
        add iy,de
        call free_en
        call brk_start
        ld b,PTS_BREAK
        jr .done
.boom:  call en_boom
        ld b,PTS_FREE
.done:  call alive_mask         ; (keeps B) the front's ships now
        call score_add
        pop de
        scf
        ret
        assert EN_FORM == 0 && EN_FREE < EN_BOOM && EN == 8 && ENEMY_N*EN < 256

; hc_first := each enemy's art's first line, FFh if booming or gone (the
; enemies don't move till move_enemies; a hit only makes one free or booming)
hit_lines:
        ld a,(form_art_t)
        ld c,a
        ld iy,enemies
        ld hl,hc_first
        ld de,EN
        ld b,ENEMY_N
.e:     ld a,(iy+EN.ST)
        cp EN_BOOM
        ld a,0FFh
        jr nc,.put
        ld a,(iy+EN.Y)
        add a,c                 ; (no carry: the art is in the playfield)
.put:   ld (hl),a
        inc hl
        add iy,de
        djnz .e
        ret
        assert PLAY_BOTTOM < 0FFh

; The enemy at IY starts to boom (the death sound). Keeps BC, DE.
en_boom:
        ld (iy+EN.ST),EN_BOOM
        ld a,(boom_frames)
        ld (iy+EN.LEFT),a
        jp death_start

; The enemy at IY leaves its pair, at its place (whole pixels), flying at a
; random direction, never level (0 and FREE_DIRS/2 left out). Keeps DE.
free_en:
        ld (iy+EN.ST),EN_FREE
        ld (iy+EN.XF),0
        ld (iy+EN.YF),0
.r:     call rand
        ld c,a
        and FREE_DIRS/2-1
        jr z,.r                 ; level: again
        ld a,c
        and FREE_DIRS-1
        ld (iy+EN.DIR),a
        ret

; Carry: the art (form_rows) of the enemy at IY has a pixel in its column A
; (0..7) on one of lines D..E. Keeps DE, IX, IY.
art_px:
        ld hl,PIXEL_BIT
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld c,(hl)               ; the column's bit
        ld b,(iy+EN.Y)          ; the art box's top line
        ld a,d
        cp b
        jr nc,.lo
        ld a,b
.lo:    ld l,a                  ; from max(D, top) ...
        ld a,b
        add a,15
        cp e
        jr c,.hi
        ld a,e                  ; ... to min(E, top + 15)
.hi:    sub l
        jr c,.none
        inc a
        push de
        ld e,a                  ; lines
        ld a,l
        sub b                   ; the first one's row
        ld hl,(form_rows)
        add a,l
        ld l,a
        jr nc,.nc2
        inc h
.nc2:   ld b,e
.row:   ld a,(hl)
        and c
        jr nz,.hit
        inc hl
        djnz .row
        pop de
.none:  or a
        ret
.hit:   pop de
        scf
        ret

; ---- Collisions ------------------------------------------------------------

; Each free enemy against each living ship of the front, where both show
; this frame (after their moves): a pixel of the enemy's art on a pixel of
; the ship's, and the enemy booms (as when shot) and the ship dies (as by
; a test key). Every enemy and ship that touch: a ship living when this
; began touches a second enemy too (it dies once). Pairs never reach the
; front's lines.
collide:
        call alive_mask
        or a
        ret z
        ld (col_alive),a
        ld iy,enemies
        ld b,ENEMY_N
.e:     ld a,(iy+EN.ST)
        cp EN_FREE
        jr nz,.next
        push bc
        call en_front
        pop bc
.next:  ld de,EN
        add iy,de
        djnz .e
        ret
        assert FORM_Y0+FORM_RISE+FORM_H <= SHIP_TOP+SHIP_ART_T

; The free enemy at IY against the front's ships living (col_alive)
en_front:
        ld a,(form_art_t)       ; the lines both arts' rows are on:
        add a,(iy+EN.Y)         ; (no carry: the art is in the playfield)
        cp SHIP_TOP+SHIP_ART_T
        jr nc,.lo
        ld a,SHIP_TOP+SHIP_ART_T
.lo:    ld c,a                  ; from the lower first one ...
        ld a,(form_art_b)
        add a,(iy+EN.Y)
        cp SHIP_TOP+SHIP_ART_B
        jr c,.hi
        ld a,SHIP_TOP+SHIP_ART_B
.hi:    sub c                   ; ... to the higher last one
        ret c                   ; none
        inc a
        ld (col_n),a
        ld a,c
        sub (iy+EN.Y)
        ld (col_erow),a
        ld a,c
        sub SHIP_TOP
        add a,a
        ld l,a
        ld h,0
        ld de,SHIP_ROWS
        add hl,de
        ld (col_srow),hl
        ld l,(iy+EN.X)
        ld h,(iy+EN.X+1)
        call to_screen
        ld de,7
        add hl,de
        ld (col_ex),hl          ; -9..262
        xor a
        ld (col_hit),a
        ld a,(col_alive)
        ld c,a
        ld a,(ship_x)
        ld b,a                  ; this slot's art's left column
        ld hl,boom_stage
.slot:  srl c                   ; a ship living in this slot
        jr nc,.snext
        push bc
        push hl
        ld hl,(col_ex)
        ld e,b
        ld d,0
        or a
        sbc hl,de               ; the enemy's left column on the ship's art, + 7
        ld a,h
        or a
        jr nz,.no
        ld a,l
        cp SHIP_ART_W+7
        jr nc,.no               ; the arts' boxes apart
        call touch
        jr nc,.no
        ld a,1
        ld (col_hit),a
        pop hl
        push hl
        ld a,(hl)               ; boom_stage
        or a
        call z,ship_dies        ; (not again when a second enemy touches it)
.no:    pop hl
        pop bc
.snext: inc hl
        ld a,b
        add a,SHIP_ART_W
        ld b,a
        inc c
        dec c
        jr nz,.slot
        ld a,(col_hit)
        or a
        ret z
        call en_boom
        ld a,(col_alive)        ; the front's ships before the crash
        ld b,PTS_FREE
        jp score_add
        assert SHIP_ART_W <= 9 && SHIP_ART_B <= 15

; Carry: the enemy's art and the ship's have a pixel in common on col_n
; lines from the enemy's row col_erow and the ship's row at col_srow, the
; enemy's left column on the ship's art's A-7 (-7..8). The enemy's rows
; rotated right by that mod 8 (rot_rows) hold its columns on the ship's
; art's 0..7 and 8..15 (the SHIP_ROWS word's high and low bytes) apart:
; masks D and E.
touch:
        sub 7
        ld c,a                  ; -7..8
        and 7
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,col_erow
        add a,(hl)
        ld e,a
        ld d,0
        ld hl,rot_rows
        add hl,de
        push hl
        ld a,c
        ld hl,MASK_R
        or a
        jp m,.left
        ld e,a
        add hl,de
        ld a,(hl)
        ld d,a                  ; on columns 0..7: FFh >> it
        cpl
        ld e,a                  ; on 8..15: the rest
        jr .rows
.left:  add a,8
        ld e,a
        add hl,de
        ld a,(hl)
        cpl
        ld d,a                  ; on columns 0..7: FFh << -it
        ld e,0                  ; none on 8..15
.rows:  pop hl
        ld ix,(col_srow)
        ld a,(col_n)
        ld b,a
.row:   ld a,(hl)
        and d
        and (ix+1)
        jr nz,.hit
        ld a,(hl)
        and e
        and (ix+0)
        jr nz,.hit
        inc hl
        inc ix
        inc ix
        djnz .row
        or a
        ret
.hit:   scf
        ret

MASK_R: db 0FFh,7Fh,3Fh,1Fh,0Fh,07h,03h,01h,00h ; FFh >> 0..8

; ---- Bitmap bullets --------------------------------------------------------

; The volley at IX (top line Y) drawn (C nonzero) or erased (C = 0) in the
; bitmap; the cells hold nothing else, since a volley's bullets are
; SHIP_ART_W > 8 px apart and volleys at least a frame's step + BULLET_H
; lines apart. Keeps IX.
volley_px:
        ld e,(ix+VOLLEY.Y)
        push ix
        pop hl
        inc hl                  ; X
        ld b,FRONT_MAX
.b:     ld a,(hl)
        or a
        jr z,.next
        ld d,a
        push bc
        push de
        push hl
        ld a,c
        or a
        jr z,.px                ; C = 0: erase
        ld a,d
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld c,(hl)               ; the column's bit in its byte
.px:    call bullet_px
        pop hl
        pop de
        pop bc
.next:  inc hl
        djnz .b
        ret
        assert SHIP_ART_W > 8

; Lines E..E+BULLET_H-1 of the bitmap at pixel column D's cell := C (outside
; vertical blank too: 40 T between the VRAM writes), but for the middle
; text's cells (over_at)
bullet_px:
        ld b,BULLET_H
.cell:  ld a,(mid_text)
        or a                    ; (no carry)
        call nz,over_cell
        jr c,.skip
        ld a,e                  ; byte (E/8)*256 + (D and F8h) + E%8
        and 7
        ld l,a
        ld a,d
        and 0F8h
        or l
        ld l,a
        ld a,e
        rrca
        rrca
        rrca
        and 1Fh
        ld h,a
        ld a,(pat_hi)
        or h
        ld h,a
        ld a,l
        di
        out (VDP_ADDR),a
        ld a,h
        out (VDP_ADDR),a
        ei
.row:   ld a,c
        out (VDP_DATA),a
        dec b
        ret z
        inc e
        ld a,e
        and 7
        jr nz,.row              ; same cell: the next byte
        jr .cell
.skip:  dec b                   ; GAME OVER's: its lines left alone
        ret z
        inc e
        ld a,e
        and 7
        jr nz,.skip
        jr .cell

; ---- Stars -----------------------------------------------------------------

; The stars at random columns, on random lines (one each), not drawn yet
init_stars:
        ld a,r
        ld h,a
        ld l,0B5h               ; (never 0)
        ld (rand_seed),hl
        ld ix,stars
        ld b,STARS
.s:     push bc
        call rand
        ld (ix+STAR.X),a
        call random_line        ; (the lines not set yet are 0: off the playfield)
        ld (ix+STAR.Y),a
        ld de,STAR
        add ix,de
        pop bc
        djnz .s
        ret
        assert PLAY_TOP > 0

; Every star one frame on
move_stars:
        ld hl,bl_lines          ; the lines the bullets are on now
        xor a
        dup BL_SIZE
        ld (hl),a
        inc l
        edup
        ld hl,volleys
        ld b,MAX_VOLLEYS
.v:     ld a,(hl)
        or a
        call nz,bl_mark
        ld a,l
        add a,VOLLEY
        ld l,a
        djnz .v
        ld hl,ebullets
        ld b,EB_N
.eb:    ld a,(hl)
        or a
        call nz,bl_mark
        inc l
        inc l
        djnz .eb
        ld a,(star_whole)
        ld b,a
        ld a,(star_frac)
        ld d,a
        ld hl,star_acc
        call bresenham
        ld (star_step),a
        ld ix,stars
        ld b,STARS
.s:     push bc
        call star
        ld de,STAR
        add ix,de
        pop bc
        djnz .s
        ret

; Lines A..A+BULLET_H-1 marked in bl_lines. Keeps B, HL.
bl_mark:
        push hl
        ld e,a
        and 7
        add a,a
        add a,low BL_MASKS
        ld l,a
        ld h,high BL_MASKS
        ld c,(hl)               ; its bits in line/8's byte ...
        inc l
        ld d,(hl)               ; ... and in the next one's
        ld a,e
        rrca
        rrca
        rrca
        and 1Fh
        add a,low bl_lines
        ld l,a
        ld h,high bl_lines
        ld a,(hl)
        or c
        ld (hl),a
        inc l
        ld a,(hl)
        or d
        ld (hl),a
        pop hl
        ret
        assert BULLET_H == 3 && BL_MASKS/256 == (BL_MASKS+15)/256
        assert bl_lines/256 == (bl_lines+BL_SIZE-1)/256 && EB == 2

; The star at IX: this frame's step left (out past column 0: a new star at
; column 255 on a free random line); in the bitmap, off its byte if it left
; it or a bullet is in it now (the bullet's pixels stay, its colour comes
; back), then drawn at its place unless a bullet is in that byte. Staying in
; its byte, shown: one VRAM write if it moved, none if not.
star:
        ld a,(star_step)
        ld c,a
        ld a,(ix+STAR.X)
        sub c
        ld d,a                  ; its new column
        ld e,(ix+STAR.Y)        ; ... and line
        jr nc,.in
        call random_line        ; out: the new star (column 255)
        ld e,a
.in:    call bullet_at
        sbc a,a
        ld c,a                  ; FFh: a bullet in the new byte, not shown
        ld a,(ix+STAR.ON)
        or a
        jr z,.draw
        inc c
        dec c
        jr nz,.off
        ld a,(ix+STAR.Y)
        cp e
        jr nz,.off
        ld a,(ix+STAR.X)
        xor d
        and 0F8h
        jr nz,.off              ; another byte
        ld a,(ix+STAR.X)
        cp d
        call nz,pat_bit         ; the same byte: just its new bit
        jr .put
.off:   push de
        ld d,(ix+STAR.X)
        ld e,(ix+STAR.Y)
        call bullet_at
        jr c,.col               ; a bullet drew over it: its pixels stay
        ld a,(pat_hi)
        call vdp_at
        xor a
        out (VDP_DATA),a
.col:   ld a,(col_hi)
        call vdp_at
        ld a,BULLET_COLOR*16+BG_COLOR
        out (VDP_DATA),a
        pop de
        ld (ix+STAR.ON),0
.draw:  inc c
        jr z,.put               ; hidden
        call pat_bit
        ld a,(col_hi)
        call vdp_at
        ld a,STAR_COLOR*16+BG_COLOR
        out (VDP_DATA),a
        ld (ix+STAR.ON),1
.put:   ld (ix+STAR.X),d
        ld (ix+STAR.Y),e
        ret

; Carry: a bullet in flight (a volley's or an enemy's) is in pixel (D, E)'s
; bitmap byte (line E, the 8-px cell of column D), or the middle text is
; (over_at). Keeps BC, DE.
bullet_at:
        push bc
        ld a,e                  ; first: none on line E (bl_lines), none
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld c,(hl)
        ld a,e
        rrca
        rrca
        rrca
        and 1Fh
        add a,low bl_lines
        ld l,a
        ld h,high bl_lines
        ld a,(hl)
        and c
        jr z,.none
        ld hl,volleys
        ld b,MAX_VOLLEYS
.v:     ld a,e
        sub (hl)                ; line - the volley's top (0 = none: E is more than BULLET_H)
        cp BULLET_H
        jr nc,.nv
        push hl
        ld c,FRONT_MAX
.x:     inc hl
        ld a,(hl)
        or a
        jr z,.nx                ; no bullet from this slot
        xor d
        and 0F8h
        jr z,.hit
.nx:    dec c
        jr nz,.x
        pop hl
.nv:    ld a,l
        add a,VOLLEY
        ld l,a
        djnz .v
        call eb_cell            ; no enemy bullet in its column's cell: none
        and (hl)
        jr z,.none
        ld hl,ebullets
        ld b,EB_N
.e:     ld a,e
        sub (hl)                ; (0 = none, as above)
        inc hl
        cp BULLET_H
        jr nc,.ne
        ld a,(hl)
        xor d
        and 0F8h
        jr z,.ehit
.ne:    inc hl
        djnz .e
.none:  pop bc
        jp over_at
.hit:   pop hl
.ehit:  pop bc
        scf
        ret
        assert PLAY_TOP >= BULLET_H
        assert volleys/256 == (volleys+MAX_VOLLEYS*VOLLEY-1)/256

; Pixel (D, E)'s bitmap byte := its bit alone. Keeps BC, DE.
pat_bit:
        ld a,(pat_hi)
        call vdp_at
        ld a,d
        and 7
        ld hl,PIXEL_BIT
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld a,(hl)
        out (VDP_DATA),a
        ret

; The VDP's write address := pixel (D, E)'s byte, (E/8)*256 + (D and F8h) +
; E%8, in the table whose high byte (with the write bit) is A. Keeps BC, DE.
vdp_at:
        ld l,a
        ld a,e
        rrca
        rrca
        rrca
        and 1Fh
        or l
        ld h,a
        ld a,e
        and 7
        ld l,a
        ld a,d
        and 0F8h
        or l
        di
        out (VDP_ADDR),a
        ld a,h
        out (VDP_ADDR),a
        ei
        ret

; A = a random playfield line no star is on. Keeps BC, DE.
random_line:
        push bc
.r:     call rand
        cp PLAY_LINES
        jr nc,.r
        add a,PLAY_TOP
        ld c,a
        ld hl,stars+STAR.Y
        ld b,STARS
.chk:   ld a,(hl)
        cp c
        jr z,.r                 ; taken
        inc hl
        inc hl
        inc hl
        djnz .chk
        ld a,c
        pop bc
        ret
        assert STAR == 3

; The wave's enemy (form_enemy) and colour (FORM_COLORS[form_cidx]): its
; art's rows and bounds, its colour, its pair's and its lone enemy's
; patterns in VRAM (no enemy sprite shows them while they change)
load_formation:
        ld a,(form_cidx)
        ld e,a
        ld d,0
        ld hl,FORM_COLORS
        add hl,de
        ld a,(hl)
        ld (form_color),a
        ld a,(form_enemy)
        ld l,a
        ld h,0
        add hl,hl
        ld de,ENEMY_ROWS
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (form_art_t),de      ; (and form_art_b)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,ENEMY_PATTERN
        add hl,de
        ld (form_rows),hl
        ld de,rot_rows          ; its rows rotated right 0..7 bits (collide)
        ld bc,16
        ldir
        ld hl,rot_rows
        ld b,7*16
.rot:   ld a,(hl)
        rrca
        ld (de),a
        inc hl
        inc de
        djnz .rot
        ld hl,(form_rows)
        push hl
        ld hl,(GRPPAT)          ; the formation's pair
        ld de,NAME_ENEMY*8
        add hl,de
        ex de,hl
        pop hl
        ld bc,32
        call LDIRVM
        ld hl,(GRPPAT)          ; one enemy alone: its rows, then 16 blank
        ld de,NAME_ENEMY1*8
        add hl,de
        ex de,hl
        ld hl,(form_rows)
        ld bc,16
        call LDIRVM
        ld hl,(GRPPAT)
        ld de,NAME_ENEMY1*8+16
        add hl,de
        ld bc,16
        xor a
        jp FILVRM
        assert NAME_BOOM+BOOM_STAGES*4 <= NAME_ENEMY && NAME_ENEMY1 == NAME_ENEMY+4

; Every enemy gone: WAVE_DELAY_MS later (wave_delay frames after the frame
; the last one went), a new wave, the next enemy (images/enemy-0..9.png in
; turn) in the next colour of FORM_COLOR_LIST (each list from its start
; again after its last), the formation in its pairs at the loop's start;
; after a wave of BOSS_AFTER_LIST, the boss instead, and the next wave once
; its bonus is over. While the boss is on: it moves (fighting), or its
; bonus ends (BS_END: the text gone, the score; BS_NEXT: the next wave)
next_wave:
        ld a,(boss_st)
        or a
        jr z,.waves
        cp BS_FIGHT
        jp z,boss_move
        cp BS_END
        jp z,boss_end
        cp BS_NEXT
        ret nz
        xor a                   ; the next wave
        ld (boss_st),a
        inc a
        ld (boss_done),a
        jr .go
.waves: ld hl,wave_wait
        ld a,(hl)
        or a
        jr z,.idle
        dec (hl)                ; waiting (every enemy stays gone meanwhile)
        ret nz
        jr .go
.idle:  ld hl,enemies+EN.ST
        ld de,EN
        ld b,ENEMY_N
.e:     ld a,(hl)
        cp EN_GONE
        ret nz
        add hl,de
        djnz .e
        ld a,(wave_delay)       ; the last one just went: the wait starts
        ld (wave_wait),a
; The wave is finished: BONUS_WAVES in a row with no ship lost, a reserve
; ship more, if the reserve has room (else none: the count starts again);
; not in game over
.done:  ld hl,wave_lost
        ld a,(hl)
        ld (hl),0
        ld hl,clean_waves
        or a
        jr nz,.lost
        inc (hl)
        ld a,(hl)
        cp BONUS_WAVES
        ret c
        xor a
.lost:  ld (hl),0
        ret nz                  ; (a ship lost)
        ld a,(over_on)
        or a
        ret nz
        ld a,(reserves)
        cp RESERVE_MAX
        ret nc
        inc a
        ld (reserves),a
        call draw_reserves
        jp bonus_start
.go:    ld a,1                  ; the last wave's (or boss's) enemy bullets go (next frame's eb_move)
        ld (eb_wipe),a
        ld hl,boss_done
        ld a,(hl)
        ld (hl),0
        or a
        jr nz,.wave             ; the boss after it is over
        call boss_after
        jp c,boss_begin
.wave:  ld hl,wave_n            ; (stays at 255)
        inc (hl)
        jr nz,.wn
        dec (hl)
.wn:    ld a,(form_enemy)
        inc a
        cp ENEMIES
        jr c,.en
        ld hl,level             ; the next level (stays at 255)
        inc (hl)
        jr nz,.lv
        dec (hl)
.lv:    xor a
.en:    ld (form_enemy),a
        ld a,(form_cidx)
        inc a
        cp FORM_COLORS_N
        jr c,.cn
        xor a
.cn:    ld (form_cidx),a
        call load_formation
        call level_text
        ld hl,enemies           ; all EN_FORM, as at the start
        ld de,enemies+1
        ld bc,ENEMY_N*EN-1
        ld (hl),0
        ldir
        ld hl,FORM_X0
        ld (form_x),hl
        ld hl,0
        ld (form_tick),hl
        xor a
        ld (form_acc),a
        jp form_place
        assert EN_FORM == 0

; A = a random byte (16-bit xorshift, 7/9/8). Keeps BC, DE.
rand:   ld hl,(rand_seed)
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (rand_seed),hl
        ret

; ---- Boss ------------------------------------------------------------------

; Carry: a boss comes after this wave (form_enemy + 1 in BOSS_AFTER_LIST)
boss_after:
        ld a,(form_enemy)
        inc a
        ld hl,BOSS_AFTERS
        ld b,BOSS_AFTERS_N
.a:     cp (hl)
        scf
        ret z
        inc hl
        djnz .a
        or a
        ret

; The boss begins (next_wave.go, instead of the next wave; it shows from
; this frame's SAT on): at its left end going right, in its first colour;
; its bullets one every boss_gap px they move: BOSS_EB_N * boss_gap at
; least BOSS_EB_RUN + the longest step - 1, so that the one fired
; BOSS_EB_N before is gone by then (at BOSS_EB_PCT %: eb_speed)
boss_begin:
        ld a,BS_FIGHT
        ld (boss_st),a
        ld a,BOSS_X_MIN
        ld (boss_x),a
        xor a
        ld (boss_dir),a
        ld (boss_acc),a
        ld (boss_hits),a
        ld (boss_cidx),a
        ld (boss_eb),a
        ld a,(BOSS_COLORS)
        ld (boss_color),a
        call eb_speed           ; the longest step: ceil(speed / eb_unit)
        ld de,(eb_unit)
        add hl,de
        dec hl
        ld a,-1
.st:    inc a
        or a
        sbc hl,de
        jr nc,.st
        add a,BOSS_EB_RUN-1+BOSS_EB_N-1     ; the gap: ceil((run + step - 1) / BOSS_EB_N)
        ld b,-1
.gp:    inc b
        sub BOSS_EB_N
        jr nc,.gp
        ld a,b
        ld (boss_gap),a
        ret

; The boss one frame on (fighting): BOSS_SPEED px/s, back the other way
; from either end (a step past it reflected)
boss_move:
        ld a,(boss_whole)
        ld b,a
        ld a,(boss_frac)
        ld d,a
        ld hl,boss_acc
        call bresenham
        ld b,a
        ld hl,boss_x
        ld a,(boss_dir)
        or a
        ld a,(hl)
        jr nz,.left
        add a,b
        cp BOSS_X_MAX
        jr c,.set
        neg
        add a,low (2*BOSS_X_MAX)    ; (reflected: 2 * BOSS_X_MAX - x, mod 256)
        ld c,1
        jr .turn
.left:  sub b
        cp BOSS_X_MIN+1
        jr nc,.set
        neg
        add a,2*BOSS_X_MIN
        ld c,0
.turn:  ld (hl),a
        ld a,c
        ld (boss_dir),a
        ret
.set:   ld (hl),a
        ret
        assert 2*BOSS_X_MIN < 256

; The boss fighting: every boss_gap px its bullets move (this frame's
; eb_step), one more from its art's lower edge at a random one of its
; columns, in the first free slot (eb_draw draws it)
boss_fire:
        ld a,(boss_st)
        cp BS_FIGHT
        ret nz
        ld a,(boss_gap)
        ld c,a
        ld a,(eb_step)
        ld hl,boss_eb
        add a,(hl)
        cp c
        jr c,.keep
        sub c
        ld (hl),a
        ld hl,ebullets
        ld b,EB_N
.find:  ld a,(hl)
        or a
        jr z,.free
        inc hl
        inc hl
        djnz .find
        ret                     ; (none free: can't be, BOSS_EB_N <= EB_N)
.free:  ld (hl),BOSS_EB_Y
        push hl
        call rand               ; (HL lost)
        pop hl
        and BOSS_W-1
        ld c,a
        ld a,(boss_x)
        add a,c
        inc hl
        ld (hl),a
        dec hl
.shoot:                         ; (test.tcl: HL = the bullet's {Y X})
        ret
.keep:  ld (hl),a
        ret
        assert (BOSS_W & (BOSS_W-1)) == 0 && BOSS_X_MAX+BOSS_W <= 256

; The volley at IX against the boss (fighting), where it shows now: each
; bullet whose column has a pixel of its art on lines D..E (the lines it
; covered this frame) is gone, and the boss hit (boss_hit; once it dies, no
; more). A volley left with no bullet is free. Keeps DE, IX.
boss_volley:
        ld a,d
        cp BOSS_Y+BOSS_H
        ret nc                  ; under it
        push ix
        pop hl
        inc hl                  ; X
        ld b,FRONT_MAX
        ld c,0                  ; bullets left
.b:     ld a,(hl)
        or a
        jr z,.next
        push bc
        push hl
        call boss_px
        pop hl
        pop bc
        jr nc,.keep
        ld (hl),0
        push bc
        push de
        push hl
        call boss_hit
        pop hl
        pop de
        pop bc
        jr .next
.keep:  inc c
.next:  inc hl
        djnz .b
        inc c
        dec c
        ret nz
        ld (ix+VOLLEY.Y),0
        ret

; Carry: the boss fights and its art has a pixel in column A on one of
; lines D..E. Keeps DE.
boss_px:
        ld c,a
        ld a,(boss_st)
        cp BS_FIGHT
        jr nz,.no
        ld a,(boss_x)
        ld b,a
        ld a,c
        sub b
        jr c,.no
        cp BOSS_W
        jr nc,.no
        ld c,a                  ; the column in its art
        rrca
        rrca
        rrca
        and 7                   ; its byte: sprite (col / 16) * 32, half (col / 8 % 2) * 16
        rla
        rla
        rla
        rla                     ; (no carry: < 128)
        ld l,a
        ld h,0
        push de
        ld de,BOSS_PATTERN
        add hl,de
        pop de
        ld a,c
        and 7
        push hl
        ld hl,PIXEL_BIT
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld c,(hl)               ; its bit
        pop hl
        ld a,d                  ; lines max(D, BOSS_Y) .. min(E, its last)
        cp BOSS_Y
        jr nc,.lo
        ld a,BOSS_Y
.lo:    ld b,a
        ld a,e
        cp BOSS_Y+BOSS_H
        jr c,.hi
        ld a,BOSS_Y+BOSS_H-1
.hi:    sub b
        jr c,.no
        inc a
        push af
        ld a,b
        sub BOSS_Y              ; the first one's row
        add a,l
        ld l,a
        jr nc,.nc2
        inc h
.nc2:   pop af
        ld b,a
.row:   ld a,(hl)
        and c
        jr nz,.hit
        inc hl
        djnz .row
.no:    or a
        ret
.hit:   scf
        ret
        assert BOSS_Y >= PLAY_TOP

; A hit on the boss: the break sound (as a pair's); every BOSS_HITS, the
; next colour; past the last, it dies (boss_dies)
boss_hit:
        call brk_start
        ld hl,boss_hits
        inc (hl)
        ld a,(hl)
        cp BOSS_HITS
        ret c
        ld (hl),0
        ld hl,boss_cidx
        inc (hl)
        ld a,(hl)
        cp BOSS_COLORS_N
        jr nc,boss_dies
        ld e,a
        ld d,0
        ld hl,BOSS_COLORS
        add hl,de
        ld a,(hl)
        ld (boss_color),a
        ret
; It starts to boom (in its last colour; the death sound), the front's
; living ships now kept for its bonus (test.tcl: it dies here)
boss_dies:
        ld a,BS_BOOM
        ld (boss_st),a
        ld a,(boom_frames)
        ld (boss_left),a
        call alive_mask
        ld (boss_alive),a
        jp death_start

; The boss booming: the next boom image when one's frames are over; after
; the last, its bonus text (its points: BOSS_PTS by the front's share,
; boss_alive) for bonus_frames in the screen's middle (not over GAME OVER);
; then BS_END (next_wave: the score, the next wave)
boss_booms:
        ld a,(boss_st)
        cp BS_BOOM
        ret c
        cp BS_END
        ret nc
        ld hl,boss_left
        dec (hl)
        ret nz
        inc a
        ld (boss_st),a
        cp BS_BONUS
        jr z,.bonus
        ret nc                  ; (the bonus's end)
        ld e,a
        ld d,0
        ld hl,boom_frames-BS_BOOM
        add hl,de
        ld a,(hl)
        ld (boss_left),a
        ret
.bonus: ld a,(bonus_frames)
        ld (boss_left),a
        ld hl,BONUS_TEXT
        ld de,bonus_buf
        ld bc,BONUS_LEN+1
        ldir
        call boss_pts           ; HL = its BCD points
        ld de,bonus_buf+BONUS_DIGITS
        inc hl                  ; the hundreds: the high byte's low digit
        ld a,(hl)
        and 0Fh
        add a,'0'
        ld (de),a
        inc de
        dec hl
        ld a,(hl)
        rrca
        rrca
        rrca
        rrca
        and 0Fh
        add a,'0'
        ld (de),a
        inc de
        ld a,(hl)
        and 0Fh
        add a,'0'
        ld (de),a
        ld a,(over_text)
        or a
        ret nz                  ; GAME OVER shows: no text
        inc a
        ld (bonus_text),a
        ld hl,bonus_buf
        ld a,BONUS_COL
        ld b,BONUS_LEN
        jp mid_show
        assert BS_BONUS == BS_BOOM+BOOM_STAGES && BS_END == BS_BONUS+1

; HL = the boss's bonus points' BCD word in PTS, by boss_alive's ships
boss_pts:
        ld a,(boss_alive)
        ld c,0
.cnt:   srl a
        jr nc,.z
        inc c
        or a
.z:     jr nz,.cnt
        ld a,c
        add a,a
        add a,c
        add a,a
        add a,PTS_BOSS
        ld hl,PTS
        add a,l
        ld l,a
        ret nc
        inc h
        ret

; The bonus's end (next_wave, BS_END): its text gone, its points to the
; score; the next frame, the next wave (BS_NEXT)
boss_end:
        call bonus_erase
        ld a,(boss_alive)
        ld b,PTS_BOSS
        call score_add
        ld a,BS_NEXT
        ld (boss_st),a
        ret

; The boss's SAT entries at DE (the enemies' 8: 4 sprites, then 4 parked):
; fighting, its sprites; booming, its boom image's; in its colour
boss_sat:
        ld a,(boss_st)
        sub BS_BOOM
        ld c,NAME_BOSS
        jr c,.nm
        add a,a
        add a,a
        add a,a
        add a,a
        add a,NAME_BOSS_BOOM
        ld c,a
.nm:    ld a,(boss_x)
        ld b,4
.s:     ld l,a
        ld a,BOSS_Y-1           ; a sprite's first line is Y + 1
        ld (de),a
        inc de
        ld a,l
        ld (de),a
        inc de
        ld a,c
        ld (de),a
        inc de
        ld a,(boss_color)
        ld (de),a
        inc de
        ld a,c
        add a,4
        ld c,a
        ld a,l
        add a,16
        djnz .s
        ld b,4
.p:     call park_ent
        djnz .p
        ret
        assert BS_FIGHT == 1 && BS_BOOM == 2

; ---- Call-up ---------------------------------------------------------------

; A new press of C (or an empty front: no press needed), with no call-up
; running, a reserve ship and a front spanning under FRONT_MAX slots: one
; ship leaves the reserve and comes in
; from the right if the front's middle is left of the screen's (or on it),
; else from the left, to glue on to that side of the front (an empty front:
; to where its last ship died). While one runs, it flies CALL_SPEED px/s;
; on arrival it joins the front (and move_ship moves it).
call_up:
        ld a,(call_on)
        or a
        jr nz,.fly
        ld a,(front_mask)
        or a
        jr z,.force             ; empty: one comes by itself
        ld a,(input_prev)
        cpl
        ld b,a
        ld a,(input)
        and b
        and IN_CALL
        ret z
.force: ld a,(reserves)
        or a
        ret z
        ld a,(front_slots)
        cp FRONT_MAX
        ret nc
        ld a,(front_w)
        ld c,a                  ; the front's width, 0 = empty
        or a
        jr nz,.mid
        ld a,SHIP_ART_W         ; empty: its last ship's place
.mid:   ld e,a
        ld a,(ship_x)
        ld l,a
        ld h,0
        add hl,hl
        ld d,h
        add hl,de               ; twice the front's middle
        ld de,-257
        add hl,de               ; carry: right of the screen's middle
        ld a,(ship_x)
        jr c,.left
        add a,c
        ld (call_target),a      ; on the front's right (empty: at ship_x)
        ld e,a
        ld d,0
        ld hl,256               ; from just off the right edge
        or a
        sbc hl,de
        xor a
        jr .go
.left:  inc c
        dec c
        jr z,.lt                ; empty: at ship_x
        sub SHIP_ART_W          ; on the front's left
.lt:    ld (call_target),a
        ld l,a
        ld h,0
        ld de,SHIP_ART_W        ; from just off the left edge (-SHIP_ART_W)
        add hl,de
        ld a,1
.go:    ld (call_left),a
        ld (call_rem),hl
        ld a,1
        ld (call_on),a
        xor a
        ld (call_acc),a
        ld hl,reserves
        dec (hl)
        ld a,(hl)
        jp draw_reserves
.fly:   ld a,(call_whole)
        ld b,a
        ld a,(call_frac)
        ld d,a
        ld hl,call_acc
        call bresenham          ; A = step
        ld e,a
        ld d,0
        ld hl,(call_rem)
        or a
        sbc hl,de
        jr z,.glue
        jr c,.glue
        ld (call_rem),hl
        ret
        ; Glued at call_target. The front may have been trimmed in flight
        ; (its end ships died), so the slot comes from where it is now.
.glue:  ld hl,0
        ld (call_rem),hl
        xor a
        ld (call_on),a
        ld hl,front_mask
        or (hl)
        jr nz,.join
        inc (hl)                ; empty: the new ship is the front
        ld a,(call_target)
        ld (ship_x),a
        jp front_span
.join:  ld a,(call_target)
        ld hl,ship_x
        sub (hl)
        jr c,.gl
        ld b,0                  ; on the right: slot (target - ship_x) / SHIP_ART_W
.div:   sub SHIP_ART_W
        jr c,.slot
        inc b
        jr .div
.slot:  inc b
        ld a,1
        jr .bit
.sh:    add a,a
.bit:   djnz .sh
        ld hl,front_mask
        or (hl)
        ld (hl),a
        jp front_span
.gl:    call front_shift        ; on the left: slots shift right until slot 0 is there
        ld a,(call_target)
        ld hl,ship_x
        cp (hl)
        jr nz,.gl
        ld hl,front_mask
        set 0,(hl)
        jp front_span

; The level and wave ("L1 W1" .. "L255 W10": level, form_enemy+1) in
; lw_text, printed on LW_ROW from LW_COL, blank cells after it up to LW_LEN
; (a shorter text than the last leaves none of it); not in attract mode
level_text:
        ld a,(attract)
        or a
        ret nz                  ; (attract mode: the title's kept)
        ld de,lw_text
        ld a,'L'
        ld (de),a
        inc de
        ld a,(level)
        call decimal
        ld a,' '
        ld (de),a
        inc de
        ld a,'W'
        ld (de),a
        inc de
        ld a,(form_enemy)
        inc a
        call decimal
        xor a
        ld (de),a
        ld hl,lw_text
        ld de,LW_ROW*256+LW_COL*8
        ld c,TEXT_COLOR*16+BG_COLOR
        call print_text         ; (DE: the next cell)
.pad:   ld a,e
        cp (LW_COL+LW_LEN)*8
        ret nc
        ld hl,SPACE_TEXT
        call print_text
        jr .pad
        assert (LW_COL+LW_LEN)*8 < 256 && ENEMIES < 100

; A (1..255) in decimal at DE.., no leading zeros; DE past it
decimal:
        ld c,0                  ; nonzero: a digit written
        ld b,100
        call .dig
        ld b,10
        call .dig
        add a,'0'
        ld (de),a
        inc de
        ret
; A's digit for B (A / B) at DE unless a leading zero; A = the rest
.dig:   ld h,'0'-1
.sub:   inc h
        sub b
        jr nc,.sub
        add a,b
        ld l,a
        ld a,h
        cp '0'
        jr nz,.put
        inc c
        dec c
        jr z,.skip
.put:   ld (de),a
        inc de
        ld c,1
.skip:  ld a,l
        ret

; ---- Score -----------------------------------------------------------------

; Points to the score (BCD; at 99999999 it stays): B = PTS_BREAK, PTS_FREE
; or PTS_BOSS, A = the front's living ships' mask (their count picks the
; share; none counts as one). Keeps IX, IY.
score_add:
        ld c,0                  ; the ships
.cnt:   srl a
        jr nc,.z
        inc c
        or a
.z:     jr nz,.cnt
        ld a,c
        add a,a
        add a,c
        add a,a                 ; 6 bytes a count
        add a,b
        ld hl,PTS
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld e,(hl)
        inc hl
        ld d,(hl)               ; the points, BCD
        ld hl,score
        ld a,(hl)
        add a,e
        daa
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,d
        daa
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,0
        daa
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,0
        daa
        ld (hl),a
        jr nc,.ok
        ld a,99h                ; past 99999999: it stays there
        ld (hl),a
        dec hl
        ld (hl),a
        dec hl
        ld (hl),a
        dec hl
        ld (hl),a
.ok:    ld a,1
        ld (score_dirty),a
        ret
PTS_BREAK       equ 0
PTS_FREE        equ 2
PTS_BOSS        equ 4
        assert FRONT_MAX == 4

; The score, if it changed, on SCORE_ROW's last SCORE_LEN cells,
; right-aligned, no leading zeros: only the cells that changed are printed
show_score:
        ld a,(attract)
        or a
        ret nz                  ; (attract mode: the title's kept)
        ld a,(score_dirty)
        or a
        ret z
        xor a
        ld (score_dirty),a
        ld hl,score+3
        ld de,score_digits
        ld bc,4*256+0           ; C nonzero: a digit written
.byte:  ld a,(hl)
        rrca
        rrca
        rrca
        rrca
        call .dig
        ld a,(hl)
        call .dig
        dec hl
        djnz .byte
        dec de
        ld a,(de)
        cp ' '
        jr nz,.cmp
        ld a,'0'                ; 0: one digit
        ld (de),a
.cmp:   ld hl,score_digits
        ld de,SCORE_ROW*256+SCORE_COL*8
        ld b,SCORE_LEN
.c:     ld a,(hl)
        push hl
        push bc
        ld bc,SCORE_LEN
        add hl,bc               ; score_shown's
        cp (hl)
        jr z,.same
        ld (hl),a
        ld (score_cell),a
        push de
        ld hl,score_cell
        ld c,TEXT_COLOR*16+BG_COLOR
        call print_text
        pop de
.same:  ld a,e
        add a,8
        ld e,a
        pop bc
        pop hl
        inc hl
        djnz .c
        ret
; digit A (low nibble) at DE, a space if a leading zero
.dig:   and 0Fh
        jr nz,.nz
        inc c
        dec c
        ld a,' '
        jr z,.put
        ld a,'0'
        jr .put
.nz:    ld c,1
        add a,'0'
.put:   ld (de),a
        inc de
        ret
        assert score_shown == score_digits+SCORE_LEN && SCORE_LEN == 8
        assert SCORE_COL >= LW_COL+LW_LEN && SCORE_ROW == LW_ROW

; Carry: game over's end, back to the title. The front empty with no
; call-up flying (none left in reserve: call_up sends one by itself) is
; game over: GAME OVER centred on OVER_ROW (not in attract mode), the game running on
; (the front can't move, shoot or call up) until GAME_OVER_MS later, or a
; press of fire (space or either joystick's button A) from OVER_SKIP_MS on.
game_over:
        ld a,(attract)
        or a
        jr z,.game
        ld a,(att_quit)         ; attract mode: a press of fire, or its time over
        or a
        scf
        ret nz
        ld hl,(att_left)
        dec hl
        ld (att_left),hl
        ld a,h
        or l
        scf
        ret z
.game:  ld a,(over_on)
        or a
        jr nz,.on
        ld a,(front_mask)
        or a
        ret nz                  ; (no carry after the or)
        ld a,(call_on)
        or a
        ret nz
        inc a
        ld (over_on),a          ; (over_time: 0)
        ld a,(attract)
        or a
        ret nz                  ; attract mode: no text, just the timeout (no carry after the or)
        inc a
        ld (over_text),a
        call bonus_erase        ; (the boss's bonus text goes; its bonus runs on)
        ld hl,OVER_TEXT
        ld a,OVER_COL
        ld b,OVER_LEN
        call mid_show
        or a
        ret
.on:    ld hl,(over_time)
        inc hl
        ld (over_time),hl
        ld de,(over_end)
        or a
        sbc hl,de
        ccf
        ret c                   ; its time is over
        ld hl,(over_time)
        ld de,(over_skip)
        or a
        sbc hl,de
        ccf
        ret nc                  ; too soon for fire
        ld a,(attract)
        or a
        ret nz                  ; (attract mode: the pseudo-player's fire doesn't count)
        ld a,(input_prev)
        cpl
        ld b,a
        ld a,(input)
        and b
        and IN_FIRE
        ret z                   ; (no carry after the and)
        scf
        ret

; Carry: a text shows in the screen's middle (mid_text: GAME OVER or the
; boss's bonus), and pixel (D, E)'s bitmap byte is in its cells (no star or
; bullet is drawn there meanwhile). Keeps BC, DE, HL.
over_at:
        ld a,(mid_text)
        or a
        ret z
; ... the same, with one showing
over_cell:
        ld a,e
        and 0F8h
        cp OVER_ROW*8
        jr nz,.no
        push bc
        ld a,(mid_x0)
        ld c,a
        ld a,(mid_w)
        ld b,a
        ld a,d
        sub c
        cp b
        pop bc
        ret
.no:    or a
        ret
        assert OVER_ROW >= PLAY_TOP/8 && OVER_ROW*8+7 <= PLAY_BOTTOM && OVER_COL*8+OVER_LEN*8 <= 256
        assert BONUS_COL*8+BONUS_LEN*8 <= 256 && BONUS_LEN < 32
        ; (a star leaving one of its bytes sets the byte's colour to BULLET_COLOR's: the text's)
        assert TEXT_COLOR == BULLET_COLOR

; Text HL in the screen's middle (OVER_ROW) from column A, B cells: its
; cells kept from stars and bullets from now on (a star in them now: not
; drawn any more, the text over it)
mid_show:
        ld (mid_text),a         ; (nonzero: the column is)
        add a,a
        add a,a
        add a,a
        ld (mid_x0),a
        ld e,a
        ld a,b
        add a,a
        add a,a
        add a,a
        ld (mid_w),a
        ld d,OVER_ROW
        push hl
        push de
        ld ix,stars
        ld b,STARS
.s:     push de
        ld d,(ix+STAR.X)
        ld e,(ix+STAR.Y)
        call over_cell
        pop de
        jr nc,.sn
        ld (ix+STAR.ON),0
.sn:    ld de,STAR
        add ix,de
        djnz .s
        pop de
        pop hl
        ld c,TEXT_COLOR*16+BG_COLOR
        jp print_text
        assert OVER_COL > 0 && BONUS_COL > 0

; The boss's bonus text, if it shows, gone (blank cells), and its cells
; free again; with over_text set (GAME OVER about to take its place), not
; the cells GAME OVER will cover (the work fits a frame on the Expert)
bonus_erase:
        ld a,(bonus_text)
        or a
        ret z
        xor a
        ld (bonus_text),a
        ld (mid_text),a
        ld de,OVER_ROW*256+BONUS_COL*8
        ld b,BONUS_LEN
        ld c,TEXT_COLOR*16+BG_COLOR
.c:     ld a,(over_text)
        or a
        jr z,.blank
        ld a,e
        sub OVER_COL*8
        cp OVER_LEN*8
        jr c,.skip              ; (GAME OVER's)
.blank: push bc
        ld hl,SPACE_TEXT
        call print_text
        pop bc
        djnz .c
        ret
.skip:  ld a,e
        add a,8
        ld e,a
        djnz .c
        ret
        assert OVER_COL >= BONUS_COL && OVER_COL+OVER_LEN <= BONUS_COL+BONUS_LEN

; HL = the incoming ship's art's left column (-SHIP_ART_W..256, signed)
call_pos:
        ld de,(call_rem)
        ld a,(call_target)
        ld l,a
        ld h,0
        ld a,(call_left)
        or a
        jr nz,.left
        add hl,de
        ret
.left:  sbc hl,de               ; (no carry after the or)
        ret

; ---- Front -----------------------------------------------------------------

; front_slots and front_w from front_mask (its highest ship)
front_span:
        ld a,(front_mask)
        ld b,0
.hi:    or a
        jr z,.w
        inc b
        srl a
        jr .hi
.w:     ld a,b
        ld (front_slots),a
        xor a
        inc b
        jr .add
.mul:   add a,SHIP_ART_W
.add:   djnz .mul
        ld (front_w),a
        ret

; The front's slots one to the right (a new empty slot 0, one SHIP_ART_W
; further left), the boom states with them
front_shift:
        ld hl,front_mask
        sla (hl)
        ld hl,boom_left+FRONT_MAX-2
        ld de,boom_left+FRONT_MAX-1
        ld bc,2*FRONT_MAX-1
        lddr
        xor a
        ld (boom_stage),a
        ld (boom_left),a
        ld a,(ship_x)
        sub SHIP_ART_W
        ld (ship_x),a
        ret
        assert boom_left == boom_stage+FRONT_MAX

; A = front_mask without the dying ships. Keeps B.
alive_mask:
        ld hl,boom_stage+FRONT_MAX-1
        ld c,FRONT_MAX
.s:     ld a,(hl)
        cp 1                    ; carry: stage 0, alive
        rl e                    ; slot 3 first: it ends on bit 3
        dec hl
        dec c
        jr nz,.s
        ld a,(front_mask)
        and e
        ret

; New presses of the test keys 1..4: the front's first..fourth living ship
; (counted from the left) starts to die; from 4 down, so that a kill doesn't
; renumber the keys still to do
kill:
        ld a,(kill_prev)
        cpl
        ld b,a
        ld a,(kill_keys)
        and b
        ret z
        add a,a
        add a,a
        add a,a                 ; key 4 on bit 7
        ld c,a
        ld b,4
.key:   sla c
        jr nc,.next
        push bc
        call kill_nth
        pop bc
.next:  djnz .key
        ret
        assert KEYS_KILL == 1Eh

; The front's Bth living ship (1..) starts to die, if there is one
kill_nth:
        call alive_mask
        ld hl,boom_stage
.s:     or a
        ret z                   ; no more living ships
        rra
        jr nc,.next
        djnz .next              ; not the Bth yet
        jr ship_dies
.next:  inc hl
        jr .s

; The ship in the front slot at HL (boom_stage + the slot) starts to die
; (the death sound). Keeps BC.
ship_dies:
        ld (hl),1
        ld a,1
        ld (wave_lost),a
        ld de,FRONT_MAX
        add hl,de
        ld a,(boom_frames)
        ld (hl),a               ; boom_left
        jp death_start

; Each dying ship's boom: the next image when one's frames are over; after
; the last, the slot is empty and the front trimmed to its first and last
; ships (an emptied front stays where its leftmost of them died)
booms:
        ld ix,boom_stage
        ld b,FRONT_MAX
        ld c,0                  ; slots whose boom ended
        ld d,1                  ; this slot's bit
.s:     ld a,(ix+0)
        or a
        jr z,.next
        dec (ix+FRONT_MAX)      ; boom_left
        jr nz,.next
        inc a
        cp BOOM_STAGES+1
        jr nc,.done
        ld (ix+0),a
        ld hl,boom_frames-1
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld a,(hl)
        ld (ix+FRONT_MAX),a
        jr .next
.done:  ld (ix+0),0
        ld a,c
        or d
        ld c,a
.next:  inc ix
        sla d
        djnz .s
        ld a,c
        or a
        ret z
        cpl
        ld hl,front_mask
        and (hl)
        ld (hl),a
        jr nz,.trim
        ld a,(ship_x)           ; empty
.lo:    rr c
        jr c,.at
        add a,SHIP_ART_W
        jr .lo
.at:    ld (ship_x),a
        jp front_span
.trim:  bit 0,(hl)              ; slot 0 empty: everything one slot left
        jp nz,front_span
        srl (hl)
        push hl
        ld hl,boom_stage+1
        ld de,boom_stage
        ld bc,2*FRONT_MAX-1
        ldir
        xor a
        ld (boom_stage+FRONT_MAX-1),a
        ld (boom_left+FRONT_MAX-1),a
        ld a,(ship_x)
        add a,SHIP_ART_W
        ld (ship_x),a
        pop hl
        jr .trim

; ---- Sprites ---------------------------------------------------------------

; sat_buf from the front's slots (the ship or its boom) and the incoming
; ship (the end marker stays)
build_sat:
        ld hl,sat_buf
        ld ix,boom_stage
        ld a,(front_mask)
        ld d,a
        ld a,(ship_x)
        ld e,a                  ; this slot's art's left column
        ld b,FRONT_MAX
.slot:  ld c,SHIP_COLOR
        rr d
        jr nc,.park
        ld (hl),SHIP_TOP-1      ; a sprite's first line is Y + 1
        inc hl
        ld a,e
        sub SHIP_ART_L
        jr nc,.x
        add a,32                ; left of 0: the early clock
        ld c,SHIP_COLOR|SPR_EC
.x:     ld (hl),a
        jr .rest
.park:  ld (hl),SPR_PARK
        inc hl
.rest:  inc hl
        ld a,(ix+0)             ; boom_stage: 0 the ship, else a boom image
        or a
        jr z,.nm
        add a,a
        add a,a
        add a,NAME_BOOM-4
        ld (hl),a
        ld a,c
        and SPR_EC
        or BOOM_COLOR
        ld c,a
        jr .col
.nm:    ld (hl),NAME_SHIP
.col:   inc hl
        ld (hl),c
        inc hl
        inc ix
        ld a,e
        add a,SHIP_ART_W
        ld e,a
        djnz .slot
        ld a,(call_on)
        or a
        jr z,.nocall
        push hl
        call call_pos
        ld a,(call_left)
        or a
        ld de,-COMING_R_ART_L
        ld b,NAME_COMING_R
        jr z,.side
        ld de,-COMING_L_ART_L
        ld b,NAME_COMING_L
.side:  add hl,de               ; the sprite's X (signed)
        ld a,l
        ld c,COMING_COLOR
        bit 7,h
        jr z,.cx
        add a,32                ; left of 0 (down to -16): the early clock
        ld c,COMING_COLOR|SPR_EC
        jr .on
.cx:    ld a,h
        or a
        ld a,l
        jr z,.on
        pop hl                  ; X >= 256: still all off screen
        jr .nocall
.on:    pop hl
        ld (hl),SHIP_TOP-1
        inc hl
        ld (hl),a
        inc hl
        ld (hl),b
        inc hl
        ld (hl),c
        inc hl
        jr .form
.nocall:
        ld (hl),SPR_PARK
        ld de,4
        add hl,de
.form:  ld de,enemy_sat         ; the enemies: pair k's entries 2k and 2k+1
        ld a,(boss_st)          ; (the boss: in their entries, all gone then)
        dec a
        cp BS_BONUS-BS_FIGHT
        jr nc,.pairs
        call boss_sat
        jr .turn
.pairs: ld ix,enemies
        ld b,FORM_PAIRS_N
.pair:  push bc
        ld a,(ix+EN.ST)
        or a
        jr nz,.apart
        ld b,NAME_ENEMY         ; EN_FORM: the pair, one sprite at its left one's place
        call en_ent
        call park_ent
        jr .pnext
.apart: call en_sprite
        ld bc,EN
        add ix,bc
        call en_sprite
        ld bc,-EN
        add ix,bc
.pnext: ld bc,2*EN
        add ix,bc
        pop bc
        djnz .pair
.turn:  ld hl,sat_flip          ; every other frame the SAT reversed (upload_sat) ...
        ld a,(hl)
        xor 1
        ld (hl),a
        ld a,(enemy_rot)
        jr nz,.rot              ; ... and else the enemies' turn back by one (the
        dec a                   ; last first: one dropped on the reversed frame,
        and ENEMY_N-1           ; early in the list, doesn't go last now)
.rot:   ld (enemy_rot),a        ; into sat_buf from entry enemy_rot on, round
        add a,a
        add a,a
        ld c,a
        ld b,0
        ld hl,enemy_sat
        add hl,bc
        ld a,ENEMY_N*4
        sub c
        ld c,a
        ld de,sat_buf+(FRONT_MAX+1)*4
        ldir
        ld a,(enemy_rot)
        add a,a
        add a,a
        ret z
        ld c,a
        ld hl,enemy_sat
        ldir
        ret

; The SAT entry at DE (DE += 4) for the enemy at IX alone: free, booming
; (the ship's boom images, where the ship's art would be with its art's
; left column on the enemy's), or gone (parked)
en_sprite:
        ld a,(ix+EN.ST)
        cp EN_FREE
        ld b,NAME_ENEMY1
        jr z,en_ent
        cp EN_GONE
        jr nc,park_ent
        add a,a
        add a,a
        add a,NAME_BOOM-4*EN_BOOM
        ld b,a
        ld l,(ix+EN.X)
        ld h,(ix+EN.X+1)
        call to_screen
        push de
        ld de,-SHIP_ART_L
        add hl,de
        pop de
        jr ent_at
; ... name B at the enemy IX's place
en_ent: ld l,(ix+EN.X)
        ld h,(ix+EN.X+1)
        call to_screen
; ... name B at column HL (signed, -32..255; < 0: the early clock), the
; enemy IX's line, in the formation's colour
ent_at: ld a,(ix+EN.Y)
        dec a                   ; a sprite's first line is Y + 1
        ld (de),a
        inc de
        ld a,(form_color)
        ld c,a
        ld a,l
        bit 7,h
        jr z,.x
        add a,32
        set 7,c                 ; SPR_EC
.x:     ld (de),a
        inc de
        ld a,b
        ld (de),a
        inc de
        ld a,c
        ld (de),a
        inc de
        ret
        assert SPR_EC == 80h && SHIP_ART_L+16 <= 32
; ... parked
park_ent:
        ld a,SPR_PARK
        ld (de),a
        inc de
        xor a
        ld (de),a
        inc de
        ld (de),a
        inc de
        ld (de),a
        inc de
        ret

; HL (a column mod FORM_WRAP) := the screen column, -16..255. Keeps BC, DE.
to_screen:
        inc h
        dec h
        ret z
        push de
        ld de,-FORM_WRAP
        add hl,de
        pop de
        ret
        assert COMING_L_ART_L <= 16 && COMING_R_ART_L+SHIP_ART_W <= 16
        assert SAT_SIZE == (FRONT_MAX+1+ENEMY_N)*4+1

; sat_buf to the VDP, its entries in reverse order when sat_flip is set
; (where a line has more than 4 sprites, the ones dropped on one frame show
; on the next); right after halt, so OTIR / OUTI are safe (vertical blank)
upload_sat:
        ld hl,(sat_w)
        di
        ld a,l
        out (VDP_ADDR),a
        ld a,h
        out (VDP_ADDR),a
        ei
        ld a,(sat_flip)
        or a
        jr nz,.rev
        ld hl,sat_buf
        ld bc,SAT_SIZE*256+VDP_DATA
        otir
        ret
.rev:   ld hl,sat_buf+SAT_SIZE-1-4  ; the last entry first
        ld c,VDP_DATA
        ld d,(SAT_SIZE-1)/4
.ent:   outi
        outi
        outi
        outi
        ld a,l                  ; back to the entry before
        sub 8
        ld l,a
        jr nc,.nc
        dec h
.nc:    dec d
        jr nz,.ent
        ld a,SPR_END
        out (c),a
        ret
        assert (SAT_SIZE-1)%4 == 0

; ---- Status area -----------------------------------------------------------

; A (0..RESERVE_MAX) reserve ships in the bottom status area, from its left
; (the rest of RESERVE_CELLS blank): their patterns, straight to the VDP (40 T
; between the VRAM writes: outside vertical blank too); their colour is set
; once, at the game's start
draw_reserves:
        ld hl,reserve_buf
        ld de,reserve_buf+1
        ld bc,(RESERVE_CELLS+1)*8-1
        ld (hl),0
        ldir
        or a
        jr z,.show
        ld b,a                  ; ships left to draw
        ld c,RESERVE_X          ; this ship's art's left column
.ship:  push bc
        ld a,c
        and 0F8h                ; its cell's first byte
        ld e,a
        ld d,0
        ld hl,reserve_buf
        add hl,de
        ld a,c
        and 7
        ld c,a                  ; the art's shift in the cell
        ld de,RESERVE_SHAPE
        ld b,8
.row:   push bc
        ld a,(de)
        ld b,c
        ld c,0
        inc b                   ; A:C = the row shifted right C bits
        jr .shift
.sh:    srl a
        rr c
.shift: djnz .sh
        or (hl)
        ld (hl),a               ; this cell
        push de
        push hl
        ld de,8
        add hl,de
        ld a,c
        or (hl)
        ld (hl),a               ; the cell on its right
        pop hl
        pop de
        inc hl
        inc de
        pop bc
        djnz .row
        pop bc
        ld a,c
        add a,RESERVE_STEP
        ld c,a
        djnz .ship
.show:  ld a,(pat_hi)
        or RESERVE_VRAM>>8
        ld h,a
        di
        xor a                   ; (RESERVE_VRAM's low byte)
        out (VDP_ADDR),a
        ld a,h
        out (VDP_ADDR),a
        ei
        ld hl,reserve_buf
        ld b,RESERVE_CELLS*8
.out:   ld a,(hl)               ; 40 T a byte
        out (VDP_DATA),a
        inc hl
        dec b
        jr nz,.out
        ret
        assert (RESERVE_VRAM & 0FFh) == 0 && RESERVE_CELLS*8 < 256

; ---- Sound -----------------------------------------------------------------

; PSG register A = E
psg_write:
        out (PSG_ADDR),a
        ld a,e
        out (PSG_WRITE),a
        ret

; Mixer bits 6..7 kept from the BIOS (the I/O ports' direction); all
; channels off and silent
init_sound:
        ld a,PSG_MIXER
        call RDPSG
        and 0C0h
        ld (psg_io),a
        or MIX_ALL_OFF
        ld e,a
        ld a,PSG_MIXER
        call psg_write
        ld e,0
        ld a,PSG_VOL_A
        call psg_write
        ld e,0
        ld a,PSG_VOL_B
        call psg_write
        ld e,0
        ld a,PSG_VOL_C
        jp psg_write

; The mixer: all off but what the shot, break and death sounds switch on
; (shot_mix, brk_mix, death_mix; channels A, B and C, so no bit in two),
; the I/O ports' direction bits kept. Keeps BC, HL.
mixer:  ld a,(shot_mix)
        ld e,a
        ld a,(brk_mix)
        or e
        ld e,a
        ld a,(death_mix)
        or e
        ld e,a
        ld a,(psg_io)
        or MIX_ALL_OFF
        xor e                   ; their bits to 0 (on)
        ld e,a
        ld a,PSG_MIXER
        jp psg_write

; One frame of channel A: the happy beep while it plays (the shot's
; table, if one runs, goes on unheard), else the shot sound
sfx:
        ld hl,(bonus_ptr)
        ld a,h
        or l
        jr z,shot_sfx
        ld a,(hl)
        or a
        jr z,.bend
        ld e,a                  ; the beep: volume, tone period (sfx.py's table)
        ld a,PSG_VOL_A
        call psg_write
        inc hl
        ld e,(hl)
        ld a,PSG_TONE_A
        call psg_write
        inc hl
        ld e,(hl)
        ld a,PSG_TONE_A+1
        call psg_write
        inc hl
        ld (bonus_ptr),hl
        ld a,MIX_TONE_A         ; tone only
        ld (shot_mix),a
        ld hl,(sfx_ptr)         ; the shot's frame passes, unheard
        ld a,h
        or l
        jr z,mixer
        ld a,(hl)
        or a
        jr z,.sgone
        ld de,4
        add hl,de
        jr .skeep
.sgone: ld hl,0
.skeep: ld (sfx_ptr),hl
        jr mixer
.bend:  ld hl,0                 ; the beep's end: the shot's frame, if one still runs, else silence
        ld (bonus_ptr),hl
        ld hl,(sfx_ptr)
        ld a,h
        or l
        jr z,shot_sfx.end

; One frame of the shot sound on channel A: volume, tone period, noise
; bit (sfx.py's table; with the noise on, the noise period is the shot's
; unless the death sound plays: it shares R6 and wins); its end marker
; silences the channel
shot_sfx:
        ld hl,(sfx_ptr)
        ld a,h
        or l
        ret z
        ld a,(hl)
        or a
        jr z,.end
        ld e,a
        ld a,PSG_VOL_A
        call psg_write
        inc hl
        ld e,(hl)
        ld a,PSG_TONE_A
        call psg_write
        inc hl
        ld e,(hl)
        ld a,PSG_TONE_A+1
        call psg_write
        inc hl
        ld a,(hl)               ; the noise bit, if any
        or a
        jr z,.mix
        ld e,SHOT_NOISE
        ld a,PSG_NOISE
        call psg_write
        ld a,(hl)
.mix:   or MIX_TONE_A
        inc hl
        ld (sfx_ptr),hl
        ld (shot_mix),a
        jp mixer
.end:   ld hl,0
        ld (sfx_ptr),hl
        ld a,l
        ld (shot_mix),a
        ld e,a
        ld a,PSG_VOL_A
        call psg_write
        jp mixer
        assert ((SHOT_NOISE_BIT|MIX_TONE_A) & (DEATH_MIX|BREAK_MIX)) == 0 && (DEATH_MIX & BREAK_MIX) == 0

; (Re)start the death sound (test.tcl: it starts here)
death_start:
        ld hl,(death_sound)
        ld (death_ptr),hl
        ret

; Start the happy beep (test.tcl: it starts here)
bonus_start:
        ld hl,(bonus_sound)
        ld (bonus_ptr),hl
        ret

; (Re)start the break sound (test.tcl: it starts here)
brk_start:
        ld hl,(brk_sound)
        ld (brk_ptr),hl
        ret

; One frame of the death sound on channel C, and of the break sound on
; channel B: volume, noise period, tone period (sfx.py's tables), tone and
; noise on; the end marker silences the channel and switches them off
death:  ld ix,death_ptr
        ld bc,DEATH_MIX*256+PSG_TONE_C
        jr boom_sfx
brk_sfx:
        ld ix,brk_ptr
        ld bc,BREAK_MIX*256+PSG_TONE_B
; ... the table pointer at IX, its mixer bits at IX+2 (B when on), the
; channel's tone register C
boom_sfx:
        ld l,(ix+0)
        ld h,(ix+1)
        ld a,h
        or l
        ret z
        ld d,(hl)               ; volume, 0 = the end
        inc d
        dec d
        jr z,.end
        inc hl
        ld e,(hl)
        ld a,PSG_NOISE
        call psg_write
        inc hl
        ld e,(hl)
        ld a,c
        call psg_write
        inc hl
        ld e,(hl)
        ld a,c
        inc a
        call psg_write
        inc hl
        ld a,b
.put:   ld (ix+0),l
        ld (ix+1),h
        ld (ix+2),a
        ld e,d
        ld a,c
        rrca                    ; the channel
        add a,PSG_VOL_A
        call psg_write
        jp mixer
.end:   ld hl,0
        xor a
        jr .put
        assert death_mix == death_ptr+2 && brk_mix == brk_ptr+2
        assert PSG_TONE_B == 2 && PSG_VOL_B == PSG_VOL_A+1 && PSG_VOL_C == PSG_VOL_A+2

; ---- Data ------------------------------------------------------------------

RATES_60:       db 60, SHIP_SPEED/60, SHIP_SPEED%60, BULLET_SPEED/60, BULLET_SPEED%60
                db CALL_SPEED/60, CALL_SPEED%60, STAR_SPEED/60, STAR_SPEED%60
                db FORM_TICK_RATE/60, FORM_TICK_RATE%60
                dw SHOT_60, DEATH_60, BREAK_60, FREE_VEL_60
                db BOOM1_60, BOOM2_60, BOOM3_60
                db BLINK_ON_MS*60/1000, BLINK_OFF_MS*60/1000
                db WAVE_DELAY_MS*60/1000
                dw GAME_OVER_MS*60/1000, OVER_SKIP_MS*60/1000
                db 300/60
                dw 100*60
                dw BONUS_60
                dw TITLE_WAIT_MS*60/1000, ATTRACT_MS*60/1000
                db ATTRACT_THINK_MS*60/1000
                db BOSS_SPEED/60, BOSS_SPEED%60
                db BONUS_TEXT_MS*60/1000
RATES_50:       db 50, SHIP_SPEED/50, SHIP_SPEED%50, BULLET_SPEED/50, BULLET_SPEED%50
                db CALL_SPEED/50, CALL_SPEED%50, STAR_SPEED/50, STAR_SPEED%50
                db FORM_TICK_RATE/50, FORM_TICK_RATE%50
                dw SHOT_50, DEATH_50, BREAK_50, FREE_VEL_50
                db BOOM1_50, BOOM2_50, BOOM3_50
                db BLINK_ON_MS*50/1000, BLINK_OFF_MS*50/1000
                db WAVE_DELAY_MS*50/1000
                dw GAME_OVER_MS*50/1000, OVER_SKIP_MS*50/1000
                db 300/50
                dw 100*50
                dw BONUS_50
                dw TITLE_WAIT_MS*50/1000, ATTRACT_MS*50/1000
                db ATTRACT_THINK_MS*50/1000
                db BOSS_SPEED/50, BOSS_SPEED%50
                db BONUS_TEXT_MS*50/1000
        assert RATES_50-RATES_60 == RATES_SIZE && BOOM_STAGES == 3
        assert BONUS_TEXT_MS*60%1000 == 0 && BONUS_TEXT_MS*50%1000 == 0 && BONUS_TEXT_MS*60/1000 < 256 && BONUS_TEXT_MS > 0
        assert BLINK_ON_MS*60%1000 == 0 && BLINK_OFF_MS*60%1000 == 0
        assert BLINK_ON_MS*50%1000 == 0 && BLINK_OFF_MS*50%1000 == 0
        assert WAVE_DELAY_MS*60%1000 == 0 && WAVE_DELAY_MS*50%1000 == 0
        assert WAVE_DELAY_MS*50/1000 > 0 && WAVE_DELAY_MS*60/1000 < 256
        assert GAME_OVER_MS*60%1000 == 0 && GAME_OVER_MS*50%1000 == 0
        assert OVER_SKIP_MS*60%1000 == 0 && OVER_SKIP_MS*50%1000 == 0
        assert OVER_SKIP_MS < GAME_OVER_MS && GAME_OVER_MS*60/1000 < 65536
        assert TITLE_WAIT_MS*60%1000 == 0 && TITLE_WAIT_MS*50%1000 == 0 && TITLE_WAIT_MS*60/1000 < 65536
        assert ATTRACT_MS*60%1000 == 0 && ATTRACT_MS*50%1000 == 0 && ATTRACT_MS*60/1000 < 65536
        assert ATTRACT_THINK_MS*60%1000 == 0 && ATTRACT_THINK_MS*50%1000 == 0 && ATTRACT_THINK_MS*50/1000 > 0
        assert ATTRACT_CALL_MS%ATTRACT_THINK_MS == 0 && ATTRACT_CALL_MS/ATTRACT_THINK_MS < 256

FORM_COLORS:    db FORM_COLOR_LIST
FORM_COLORS_N   equ $-FORM_COLORS
        assert FORM_COLORS_N <= 16 && form_art_b == form_art_t+1

BOSS_COLORS:    db FORM_COLOR_REDDENING
BOSS_COLORS_N   equ $-BOSS_COLORS
BOSS_AFTERS:    db BOSS_AFTER_LIST
BOSS_AFTERS_N   equ $-BOSS_AFTERS
        assert BOSS_COLORS_N > 0 && BOSS_AFTERS_N > 0

EB_PCTS:        db EB_SPEED_LIST
EB_PCTS_N       equ $-EB_PCTS
EB_MAXES:       db EB_MAX_LIST
EB_MAXES_N      equ $-EB_MAXES
        assert EB_PCTS_N < 256 && EB_MAXES_N < 256

PRESS_TEXT:     db "PRESS SPACE OR FIRE TO BEGIN",0
PRESS_LEN       equ $-PRESS_TEXT-1
        assert PRESS_LEN <= 32
CREDIT_TEXT:    db "(C) 2026 JCCYC",0
CREDIT_LEN      equ $-CREDIT_TEXT-1
        assert CREDIT_LEN <= 32
URL_TEXT:       db "HTTPS://RETROPOLIS.COM.BR",0
URL_LEN         equ $-URL_TEXT-1
        assert URL_LEN <= 32
OVER_TEXT:      db "GAME OVER",0
OVER_LEN        equ $-OVER_TEXT-1
SPACE_TEXT:     db " ",0
BONUS_TEXT:     db "BONUS 000 POINTS",0     ; (its digits: the points)
BONUS_LEN       equ $-BONUS_TEXT-1
BONUS_DIGITS    equ 6               ; the points' first digit in it

; The points (BCD words) for 0..FRONT_MAX living ships: a break-up's, a
; free enemy's, the boss's
        macro BCD16 val
        assert (val) < 10000
        dw ((val)/1000%10)*4096 + ((val)/100%10)*256 + ((val)/10%10)*16 + (val)%10
        endm
        macro PTS_FOR pct
        assert BREAK_PTS*(pct)%100 == 0 && FREE_PTS*(pct)%100 == 0 && BOSS_PTS*(pct)%100 == 0
        assert BOSS_PTS*(pct)/100 >= 100 && BOSS_PTS*(pct)/100 < 1000   ; (three digits in its text)
        BCD16 BREAK_PTS*(pct)/100
        BCD16 FREE_PTS*(pct)/100
        BCD16 BOSS_PTS*(pct)/100
        endm
PTS:    PTS_FOR SHARE_1         ; (none: as one)
        PTS_FOR SHARE_1
        PTS_FOR SHARE_2
        PTS_FOR SHARE_3
        PTS_FOR SHARE_4
        assert $-PTS == (FRONT_MAX+1)*6 && PTS_FREE == 2 && PTS_BOSS == 4

        if ($ & 0FFh) > 100h-24     ; (PIXEL_BIT and BL_MASKS in one 256-byte page)
        ds 100h-($ & 0FFh),0FFh
        endif
PIXEL_BIT:      db 80h, 40h, 20h, 10h, 08h, 04h, 02h, 01h   ; a column's bit in its byte
BL_MASKS:                       ; lines n..n+2 of a byte's 8 (and the next one's): (E000h >> n), high byte first
        dup 8, n
        db high (0E000h >> n), low (0E000h >> n)
        edup

        include "build/sprites.inc"
        include "build/sfx.inc"
        include "build/path.inc"
        include "build/title.inc"
        include "build/font.inc"

        assert $ <= 8000h
        ds 8000h-$,0FFh         ; a 16 KB ROM
