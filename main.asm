; ---------------------------------------------------------------------------
; Terra Front - the front (MSX1, 32 KB ROM at 4000h; or a BIN at 8000h for Disk BASIC)
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
; direction away from it (not a mirror; from the bottom, BOUNCE_MIN_DEG or
; more from level), and past the right or left edge it
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
; ship dies (it booms). They're gone at the playfield's bottom, and
; all of them as a new wave shows. A bitmap byte two bullets share holds both.
; The score (8 BCD digits, 99999999 at most) shows on the top status row's
; right: BREAK_PTS a pair broken up, FREE_PTS a free enemy's death (shot or
; crashing into a ship), with a one-ship front; with more, the front's share
; (SHARE_2..4 %) by its living ships before the hit.
; BONUS_WAVES waves in a row finished (each one's last enemy gone) with no
; ship lost: a reserve ship more, if the reserve has room (RESERVE_MAX),
; with a 0.25 s "happy beep" on PSG channel A (it wins over the shot's).
; After waves 5 and 10 of a level (BOSS_AFTER_LIST), the boss
; (images/boss1.png, four sprites) instead of the next wave: it cruises left
; and right at the playfield's top at BOSS_SPEED px/s, bumping into its
; edges (BOSS_MARGIN px from them), and rains bullets (the enemies', at BOSS_EB_PCT % of
; BULLET_SPEED) from random columns of its lower edge at the rate that keeps
; BOSS_EB_N in flight. It starts in FORM_COLOR_REDDENING's first colour and
; takes the next every BOSS_HITS hits (each with the break sound);
; BOSS_HITS in its last and it dies:
; eight ship booms side by side, then "BONUS ddd POINTS" (BOSS_PTS by the
; front's share as it died) in the screen's middle for BONUS_TEXT_MS, then
; the points, and the next wave.
; After wave BOSS2_AFTER (10) of a level, Boss2 (images/boss2.png) instead:
; still, in the bitmap at the playfield's top, centred (no star or bullet
; drawn in its cells), over a line of B2_PAIRS pairs of a random enemy
; (each pair a random colour) that swerves left and right (B2_MARGIN px
; from the edges, at B2_SWERVE_PAIRS pairs' speed); with B2_SPAWN_AT living
; enemies or fewer it sends down a new pair into a free slot of the line
; (B2_DESC_MS, the line still meanwhile; B2_SPAWNS at most). Its pairs
; break up and score as a wave's, it's one more shooter of the enemies'
; bullets (wave 1's); its hits, colours (its white stays), booms and bonus
; are Boss1's; as it dies, every enemy and bullet is gone at once.
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
; Every other run starts with a boss instead of wave 1, Boss1 and Boss2 in
; turn (runs from power-on: wave 1, Boss1, wave 1, Boss2, wave 1, ...).
; A press of fire (space or either joystick's button A) ends it at once;
; then, and at its end, it's back to the title. A press of Ctrl-V ends it
; too, and the title comes with the easter egg up.
; The easter egg (Skyfighter's): a press of Ctrl-V on the title shows the
; version and the credit over the picture, in place of the title's text,
; for EGG_SECS (space or fire takes it away sooner, starting nothing); with CTRL held, LICENSE_TAPS more V presses show the
; license lines instead, until any key or button. Not in a game.
; Controls: left / right arrows, space (fire), C (call-up); or either
; joystick (button A fires, B calls up). Fire and call-up are
; edge-triggered: one action per press. F1 or STOP pauses the game (not
; attract mode): PAUSED centred on the top status row, silent, until the
; next press of either.
; Speeds are Bresenham on frames (whole pixels plus a remainder per frame,
; per frame rate), so they're the same in px/s at 50 and 60 Hz.
; ---------------------------------------------------------------------------

; ---- Memory map ------------------------------------------------------------

; The ROM is a plain 32 KB cartridge in pages 1 and 2 (4000h..BFFFh; init
; switches page 2 to it) with its RAM at E000h. The BIN
; (sjasmplus -DBIN, BLOADed from Disk BASIC by the disk's AUTOEXEC.BAS) is
; the same code at 8000h (page 1 holds BASIC there), its RAM at CF00h laid
; out as the ROM's, clear of BASIC's stack (about DB80h, which the game
; keeps: BIN_STACK_ROOM below it) and the disk ROM's work area (from
; HIMEM, about DE00h), whose interrupt hook the BIN keeps calling for a
; while (it turns the drive motor off).
                ifdef BIN
CODE_BASE       equ 8000h
RAM_BASE        equ 0CF00h
BIN_STACK_ROOM  equ 0DB00h-200h     ; the BIN's RAM must end below it
; The disk ROM's frame interrupt hook turns the drive motor off a few
; seconds after the BLOAD (Skyfighter measured 4 s on the Expert with an
; FS-FD1A, 3 s on the NMS 8250), but it costs 1.8k to 3.1k T-states a
; frame. So the BIN calls it only for the first DISK_HOOK_SECS.
DISK_HOOK_SECS  equ 10
                else
CODE_BASE       equ 4000h
RAM_BASE        equ 0E000h
                endif

; ---- Version ---------------------------------------------------------------

; Stored at 4010h (BIN: 8010h), right after the cartridge header: major,
; minor (bytes), patch (word, little-endian)
VERSION_MAJOR   equ 0
VERSION_MINOR   equ 10
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
;
; The easter egg (Skyfighter's, with its own message): a fresh Ctrl-V (the
; press of the pair, either key last) on the title shows "VERSION X.Y.Z"
; (from the version bytes) and EGG_TEXTS' lines over the picture, in
; place of the title's text, from EGG_ROW down, each centred, for EGG_SECS;
; then the title's text again, blinking from the start (sooner at a
; press of space or either joystick's button A, which then starts
; nothing; the title's count to attract mode goes on). In attract mode a
; fresh Ctrl-V ends it, and the title comes with the egg up (nothing is
; drawn over the pseudo-game). Not in a game. Its texts are stored with
; each byte XORed with EGG_KEY + EGG_KEY_STEP * index (egg_text), so they
; don't show in a ROM dump.
EGG_SECS        equ 5
EGG_ROW         equ 20          ; the version's character row; the texts on the rows under it
EGG_KEY         equ 0A7h
EGG_KEY_STEP    equ 3Bh
                lua allpass
                function egg_text(s)
                    local k = sj.get_label("EGG_KEY")
                    local step = sj.get_label("EGG_KEY_STEP")
                    for i = 1, #s do
                        sj.add_byte(string.byte(s, i) ~ ((k + (i - 1) * step) & 0xFF))
                    end
                end
                -- a line of the egg: its length, then its text; counts the
                -- lines (egg_end defines EGG_TEXT_LINES)
                egg_lines = 0
                function egg_line(s)
                    if #s == 0 or #s > 32 then sj.error("egg line empty or too long: " .. s) end
                    sj.add_byte(#s)
                    egg_text(s)
                    egg_lines = egg_lines + 1
                end
                function egg_end()
                    sj.insert_label("EGG_TEXT_LINES", egg_lines)
                    egg_lines = 0
                end
                -- a license line: padded with spaces to LICENSE_LEN
                function license_line(s)
                    local n = sj.get_label("LICENSE_LEN")
                    if #s > n then sj.error("license line too long: " .. s) end
                    egg_text(s .. string.rep(" ", n - #s))
                end
                endlua
; The license (an egg in the egg, as in Skyfighter and U-boat Killer): with
; the egg up, LICENSE_TAPS more V presses with CTRL held all along
; (releasing it starts over; the press that showed the egg doesn't count)
; show the two lines of LICENSE_TEXT in its place, each centred without
; its trailing spaces (all spaces: nothing), on LICENSE_ROW and the row
; under it. No timer (the title's count to attract mode stops, and starts
; over when it goes): once every key and button has been released, any of
; them brings the title's text back, blinking from the start, starting
; nothing. licenserom.py (licensebin.py, licensedsk.py, licensezip.py)
; rewrites the lines in a built ROM (BIN, disk, zip).
LICENSE_LEN     equ 32              ; each line, space-padded
LICENSE_TAPS    equ 3
LICENSE_ROW     equ 21
;
; High scores (U-boat Killer's): HI_COUNT records, best first (HI_DEFAULTS
; at power-on; the disk version keeps them in TERRAFNT.HSC). A game's score
; enters if it beats one (a tie goes under the older score): at game over's
; end the initials are entered (enter_initials) on the list. The title
; shows the best on HISC_ROW and the row under it, right-justified (in the
; blank space at the logo's lower right); TITLE_WAIT_MS on, the list
; shows for HI_LIST_MS, then attract mode.
HI_COUNT        equ 10
HI_LIST_MS      equ 7000        ; the list on the title's turn
HI_ROW          equ 6           ; the list's heading: its character row, centred ...
HI_LIST_ROW     equ 8           ; ... and the records' first row, from column HI_COL
HI_REPEAT_DELAY_MS equ 400      ; initials: a direction held picks the next letter this much later ...
HI_REPEAT_MS    equ 100         ; ... then one every this much
HI_DONE_MS      equ 1000        ; ... the entry done: the list stays this long
HISC_ROW        equ 17          ; the title's "HI SCORE"; the best score on the row under it
WAVE_DELAY_MS   equ 700        ; a wave's last enemy gone: the next one begins this much later
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
ATTRACT_BOSS1   equ 5           ; every other run starts with a boss: Boss1 as after this wave (of BOSS_AFTER_LIST), then Boss2 (BOSS2_AFTER), in turn
OVER_ROW        equ 12          ; GAME OVER's character row (lines 96..103: the screen's middle), centred on it
OVER_COL        equ (32-OVER_LEN)/2 ; ... its first column
LW_ROW          equ 0           ; the level and wave ("L1 W1"): the top status row ...
LW_COL          equ 0           ; ... from its left; a level is ENEMIES waves, images/enemy-0..9.png
LW_LEN          equ 8           ; ... cells kept for it ("L255 W10")
SCORE_ROW       equ 0           ; the score: the top status row ...
SCORE_LEN       equ 8           ; ... its last cells, right-aligned, no leading zeros (99999999 at most)
SCORE_COL       equ 32-SCORE_LEN
PAUSE_ROW       equ 0           ; PAUSED (F1 or STOP pauses the game): the top status row, centred
PAUSE_COL       equ (32-PAUSE_LEN)/2
        assert PAUSE_COL >= LW_COL+LW_LEN && PAUSE_COL+PAUSE_LEN <= SCORE_COL
;
; A free enemy at the playfield's bottom line turns up at least this many
; degrees from level, either way (BOUNCE_MIN_DEG..180-BOUNCE_MIN_DEG); at the
; top line, and out of a broken pair, any direction but level
BOUNCE_MIN_DEG  equ 30
; (the directions BOUNCE_MIN_DEG or more from level: a step is 360/FREE_DIRS)
BOUNCE_STEPS    equ (BOUNCE_MIN_DEG*FREE_DIRS+359)/360
BOUNCE_DIRS     equ FREE_DIRS/2-2*BOUNCE_STEPS+1
        assert BOUNCE_STEPS >= 1 && BOUNCE_DIRS >= 1
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
; The boss (images/boss1.png): after these waves of a level (its last
; wave's last enemy gone, WAVE_DELAY_MS later), the boss instead of the next wave
        define BOSS_AFTER_LIST 5, 10
BOSS_MARGIN     equ 0           ; it cruises left and right at the playfield's top, turning this many px from either edge ...
BOSS_SPEED      equ 32          ; ... at this many px/s
BOSS_EB_N       equ 5           ; its bullets rain at the rate that keeps this many in flight ...
BOSS_EB_PCT     equ 70          ; ... at this % of BULLET_SPEED (wave 1's, whatever the wave)
BOSS_HITS       equ 10          ; hits a colour: then the next of FORM_COLOR_REDDENING; past its last, it dies
BOSS_PTS        equ 500         ; its death's bonus with a one-ship front (with more, SHARE_2..4 % of it) ...
BONUS_TEXT_MS   equ 2000        ; ... shown this long in the screen's middle (OVER_ROW) after its boom; then the score, the next wave
;
; Boss2 (images/boss2.png): after this wave of a level (one of
; BOSS_AFTER_LIST), Boss2 instead of the boss above (Boss1). Stationary,
; in the bitmap, centred at the playfield's top; under it a line of
; B2_PAIRS pairs of one random enemy (each pair in a random colour of
; FORM_COLOR_LIST) swerves left and right; it takes hits and changes colour
; as Boss1 (its white parts stay), with Boss1's bonus; a bullet of the
; enemies' may come from it too (it's one more shooter)
BOSS2_AFTER     equ 10
B2_PAIRS        equ 3           ; the pairs' line: this many slots (at most 2 * this enemies; record pairs 0..this-1)
B2_GAP_Y        equ 8           ; the pairs' art's first line this many blank lines under its art's last
B2_GAP_X        equ 8           ; ... blank px between two pairs' arts
B2_MARGIN       equ 56          ; ... at the line's left end, its art's first column; at the right end its last 255 - this
B2_SWERVE_MS    equ 500         ; ... its speed: a line of B2_SWERVE_PAIRS pairs from one end to the other in this long ...
B2_SWERVE_PAIRS equ 4           ; ... (the speed's range: B2_PAIRS pairs' less a slot for each pair more)
B2_SPAWN_AT     equ 4           ; living enemies this many or fewer: it spawns a pair into a free slot of the line ...
B2_SPAWNS       equ 17          ; ... this many at most
B2_DESC_MS      equ 500         ; ... coming down from just above the screen to its slot in this long (the line stops meanwhile)
;
; A cheat for playtesting: key 1 (a press, in a game, not in game over nor
; during a boss) goes to the level's next boss: that frame its wave's
; enemies are gone (no bonus ship counted), the level text shows the wave
; before it (form_enemy, form_cidx and wave_n moved on as if the waves
; between were played), and the boss begins the next frame. Key 2 (a press,
; in a game, not in game over; a boss on or not) gives a reserve ship, if
; under RESERVE_MAX, with the happy beep (as a bonus ship). Key 3 (a press,
; in a game) toggles invulnerability (invul; off at a new game): enemy
; bullets and enemies pass through the front's ships, which show in
; INVUL_COLOR (the incoming ship too; booms as ever). Key 4 (a press, in a
; game) kills a random living ship of the front (ship_dies), invulnerable
; or not. 0: no cheats (nor cheat mode). They work only in cheat mode: on the title (not the
; high score list), CTRL held, CHEAT_WORD's letters typed in turn (a wrong
; letter or CTRL up starts over); it stays on until a reset, and no score
; enters the high score table meanwhile. The title's logo then shows in
; CHEAT_LOGO_COLOR (its LOGO_COLOR bytes changed).
CHEAT_KEYS      equ 1
        define CHEAT_WORD "CHEAT"
LOGO_COLOR      equ 7           ; cyan: the logo's colour in images/title.png ...
CHEAT_LOGO_COLOR equ 2          ; ... and in cheat mode (green)
INVUL_COLOR     equ 2           ; the player's ships while invulnerable (the cheat key 3; green)
; The formation's loop (its boxes and cycle: path.py): at its highest, its
; top (the top pair's sprites' first line) this many lines under the
; playfield's first
FORM_TOP_GAP    equ 18

; ---- Layout ----------------------------------------------------------------

PLAY_TOP        equ STATUS_LINES            ; first playfield line
PLAY_BOTTOM     equ 191-STATUS_LINES        ; last playfield line
PLAY_LINES      equ PLAY_BOTTOM+1-PLAY_TOP
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
; line when the cycle starts (the first leg rises FORM_RISE to its highest)
FORM_Y0         equ PLAY_TOP+FORM_TOP_GAP+FORM_RISE
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
        assert BOSS_X_MAX > BOSS_X_MIN+BOSS_SPEED/50+1
        assert BOSS_SPEED < 50 && BOSS_X_MAX+BOSS_SPEED/50+1 < 256   ; (a step reflects off an end once)
BOSS_EB_Y       equ BOSS_Y+BOSS_H
BOSS_EB_RUN     equ PLAY_BOTTOM+2-BULLET_H-BOSS_EB_Y    ; (eb_move: gone once its top would reach line BOSS_EB_Y + this)
        assert BOSS_EB_N <= EB_N && BOSS_EB_RUN+256/50+BOSS_EB_N < 256
; Boss2: its art's box (BOSS_W x BOSS_H, as Boss1's) in the bitmap at
; (B2_X, B2_Y), whole cells; the pairs' line: their art's first line
; B2_LINE_TOP; a spawned pair's sprite starts B2_DESC_FROM lines above
; line 0 (all off screen)
B2_X            equ (256-BOSS_W)/2
B2_Y            equ PLAY_TOP
B2_VRAM         equ B2_Y/8*256+B2_X ; its first cell, from GRPCGP / GRPCOL
B2_LINE_TOP     equ B2_Y+BOSS2_LAST+1+B2_GAP_Y
B2_DESC_FROM    equ 16
B2_SW_MUL       equ 1000/B2_SWERVE_MS   ; the swerve's px/s: B2_SWERVE_PAIRS pairs' range times this
B2_DESC_MUL     equ 1000/B2_DESC_MS     ; the descent's px/s: its distance times this
        assert B2_X%8 == 0 && B2_Y%8 == 0 && B2_Y == BOSS_Y && BOSS2_LAST == BOSS_H-1
        assert 1000%B2_SWERVE_MS == 0 && 1000%B2_DESC_MS == 0 && B2_SW_MUL >= 1 && B2_DESC_MUL >= 1
        ; the line: B2_PAIRS pairs (B2_SWERVE_PAIRS for the speed), each at most 16 px of art, inside
        ; the margins, with room to swerve (a frame's step, at most the speed's range / 50 + 1, under it)
        assert B2_SWERVE_PAIRS >= B2_PAIRS && B2_PAIRS >= 2 && B2_PAIRS <= 4 && B2_PAIRS <= FORM_PAIRS_N
        assert 2*B2_MARGIN+B2_SWERVE_PAIRS*16+(B2_SWERVE_PAIRS-1)*B2_GAP_X < 256
        assert (256-2*B2_MARGIN-B2_SWERVE_PAIRS*9-(B2_SWERVE_PAIRS-1)*B2_GAP_X)*B2_SW_MUL/50+1 < 256-2*B2_MARGIN-B2_PAIRS*16-(B2_PAIRS-1)*B2_GAP_X
        assert (256-2*B2_MARGIN)*B2_SW_MUL < 65536 && B2_SPAWN_AT < 2*B2_PAIRS-1 && B2_SPAWNS < 256
        assert B2_LINE_TOP+16+B2_DESC_FROM < 256 && (B2_LINE_TOP+B2_DESC_FROM)*B2_DESC_MUL < 65536
        assert B2_LINE_TOP+16 <= FORM_Y0+FORM_RISE+FORM_H      ; (as the formation: clear of the front)
; boss_st: none, fighting, booming (one state a boom image), a frame with
; nothing (its last boom gone; the text not yet: two heavy jobs apart, on
; the Expert), the bonus text shown, the bonus's end (next_wave: the text gone, the score), then the
; next wave (next frame: a frame's work each, on the Expert)
BS_NONE         equ 0
BS_FIGHT        equ 1
BS_BOOM         equ 2
BS_GAP          equ BS_BOOM+BOOM_STAGES
BS_BONUS        equ BS_GAP+1
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
RES_PIC         equ RESERVE_CELLS*8     ; bytes of one picture of the reserve
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
IN_BOSS         equ 01h         ; the cheat key 1 (CHEAT_KEYS)
IN_SHIP         equ 02h         ; the cheat key 2 (CHEAT_KEYS)
IN_INVUL        equ 20h         ; the cheat key 3 (CHEAT_KEYS; not read in attract mode)
IN_KILL         equ 40h         ; the cheat key 4 (CHEAT_KEYS; not read in attract mode: IN_EGG's bit)
CHEAT_MASK      equ IN_BOSS|IN_SHIP|IN_INVUL|IN_KILL ; the cheat keys (cheat_on)
IN_EGG          equ 40h         ; Ctrl-V, both down (read in attract mode only)
ENT_UP          equ 01h         ; the initials' entry (ent_dirs): up, straight ...
ENT_DOWN        equ 02h         ; ... down, straight (and IN_LEFT, IN_RIGHT) ...
ENT_TRIG        equ 10h         ; ... space or a joystick's button

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
KEY_ROW_1       equ 0
KEY_1           equ 02h
KEY_2           equ 04h
KEY_3           equ 08h
KEY_4           equ 10h
KEY_ROW_CTRL    equ 6
KEY_CTRL        equ 02h
KEY_ROW_V       equ 5
KEY_V           equ 08h
KEY_ROW_F1      equ 6
KEY_F1          equ 20h
KEY_ROW_STOP    equ 7
KEY_STOP        equ 10h
KEY_ANY_ROWS    equ 9           ; the license goes at any key of rows 0..8 (as Skyfighter's)
JOY_BUTTONS     equ 30h         ; R14: buttons A and B
KEY_ROWS        equ 11          ; keyboard matrix rows 0..10 (9, 10: the keypad, if any)
JOY_A           equ 10h         ; R14: button A (0 when pressed)

MSXID1          equ 002Bh       ; bit 7 set = 50 Hz
ENASLT          equ 0024h
RSLREG          equ 0138h
EXPTBL          equ 0FCC1h
SLTTBL          equ 0FCC5h
WRTVDP          equ 0047h
FILVRM          equ 0056h
LDIRVM          equ 005Ch
INIGRP          equ 0072h
RDPSG           equ 0096h
H_TIMI          equ 0FD9Fh      ; the frame interrupt's hook (the disk ROM's motor-off count)

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
IM2_TABLE       equ RAM_BASE+800h
IM2_HI          equ IM2_TABLE/256+1
IM2_JUMP        equ IM2_HI*257
; A page of flags, one byte a line: bit 0 a bullet (a volley's or an
; enemy's) on it now, bit 1 a row with cells kept from stars and bullets
; (the middle text's, Boss2's) (move_stars sets them, from ln_list;
; bullet_at reads bit 0)
LN_FLAGS        equ RAM_BASE+700h
LN_BULLET       equ 1
LN_MID          equ 2
LN_MAX          equ (MAX_VOLLEYS+EB_N)*BULLET_H+8+BOSS_H
RES_PICS        equ RAM_BASE+500h   ; draw_reserves' patterns for 0..RESERVE_MAX ships (make_reserves)

; A high score record: the score (4 BCD bytes, the lowest two digits
; first, as score), then three letters (A..Z or spaces)
HI_SIZE         equ 7
HI_NAME         equ 4
HI_ROW_LEN      equ 16              ; a line of the list: " 1. LTR     5000"
HI_COL          equ (32-HI_ROW_LEN)/2
        ifdef BIN
; TERRAFNT.HSC on the default drive: hi_table, then a check byte (HSC_KEY
; plus the table's bytes), all XORed with HSC_XOR + HSC_XOR_STEP * index so
; the scores don't show in a dump. Through Disk BASIC's BDOS entry, FCB
; functions (U-boat Killer's UBKILLER.HSC)
HSC_SIZE        equ HI_COUNT*HI_SIZE+1
HSC_KEY         equ 6Bh
HSC_XOR         equ 0C5h
HSC_XOR_STEP    equ 2Fh
BDOS            equ 0F37Dh      ; C = function
DISKVE          equ 0F323h      ; -> a word with the disk error handler's address
BREAKV          equ 0F325h      ; -> a word with the abort routine's address (DOS 2's abort)
DOS1_ABORT      equ 0F1E6h      ; DOS 1 aborts a disk error with "jp (DOS1_ABORT)"
H_PHYD          equ 0FFA7h      ; RET (C9h) when there's no disk ROM
F_OPEN          equ 0Fh
F_CLOSE         equ 10h
F_CREATE        equ 16h         ; an existing file is emptied
F_SETDTA        equ 1Ah
F_WRBLK         equ 26h         ; random block write, HL records
F_RDBLK         equ 27h         ; random block read, HL records
F_DOSVER        equ 6Fh         ; -> B = 2 or more under DOS 2 (DOS 1 leaves B)
FCB_RECSIZE     equ 14          ; word
FCB_FILESIZE    equ 16          ; 32 bits
FCB_RANDOM      equ 33          ; 32 bits
FCB_LEN         equ 37
        endif

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
COL             byte            ; its colour (form_color; Boss2's pairs: one each)
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

        org RAM_BASE
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
egg_frames:     ds 2            ; frames the egg shows
list_frames:    ds 2            ; frames the high score list shows on the title's turn
rep_delay:      ds 1            ; initials: frames a direction is held before it repeats ...
rep_frames:     ds 1            ; ... and between repeats
done_frames:    ds 1            ; ... the entry done: frames the list stays
RATES_SIZE      equ $-rates
frames:         ds 1            ; +1 every frame interrupt
entropy:        ds 2            ; the splash's key press and release times, mixed; never 0 once a key moved
polls:          ds 2            ; the splash's input polls so far
lw_text:        ds LW_LEN+1     ; the level and wave as shown (0-terminated; the title shows the last game's)
vp_y7:          ds 1            ; volley_px: the volley's first line mod 8 ...
vp_n1:          ds 1            ; ... its lines in that cell row
vp_hi:          ds 1            ; ... that row's VRAM address high byte (write bit set)
vp_n2:          ds 1            ; ... its lines in the next cell row
lw_cell:        ds 2            ; level_text: one character to print (0-terminated)
score_digits:   ds SCORE_LEN    ; show_score: the score's cells, ASCII ...
score_shown:    ds SCORE_LEN+1  ; ... and as they show (0-terminated; the title shows the last game's; 0: none)
egg_now:        ds 1            ; nonzero: the title opens with the egg up (attract mode's or the list's Ctrl-V)
cheat_on:       ds 1            ; cheat mode: CHEAT_MASK (the cheat keys' IN_* bits) if on, else 0 (until a reset)
att_runs:       ds 1            ; attract mode's runs so far (mod 256): odd, it starts with a boss (bit 1: Boss2)
cheat_step:     ds 1            ; ... the title: CHEAT_WORD's letters typed so far, CTRL held
hi_table:       ds HI_COUNT*HI_SIZE ; the high scores, best first (ties: the older above)
        ifdef BIN
has_disk:       ds 1            ; nonzero: a disk ROM (the scores are saved)
disk_sp:        ds 2            ; SP inside bdos, for disk_abort
disk_err_stub:  ds 3            ; "ld c,2 / ret": a disk error picks Abort ...
disk_err_vec:   ds 2            ; ... -> disk_err_stub; DISKVE points here
disk_abort_vec: ds 2            ; -> disk_abort; BREAKV points here
        endif

        ifdef BIN
hook_frames:    ds 2            ; isr: frames left of calling H.TIMI (disk_timer)
        endif

; From here on, cleared for every new game
ln_n:          ds 1            ; move_stars: the lines it flagged in LN_FLAGS (unflagged next frame) ...
ln_list:        ds LN_MAX       ; ... (a line may be there twice)
game_ram:
lw_shown:       ds LW_LEN       ; level_text: its cells as they show (0: not printed yet)
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
pause_held:     ds 1            ; F1 and STOP held last time (KEY_F1, KEY_STOP bits: 1 = held)
input:          ds 1            ; IN_* this frame
input_prev:     ds 1            ; ... and last frame (fire is edge-triggered)
invul:          ds 1            ; nonzero: invulnerable (the cheat key 3)
ship_col:       ds 1            ; build_sat: the player's ships' colour this frame
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
boss_kind:      ds 1            ; 0: Boss1; nonzero: Boss2
boss_art:       ds 2            ; its art for the hits: BOSS_PATTERN or BOSS2_PATTERN (boss_px)
; Boss2: in the bitmap while b2_shown (no star or bullet drawn in its cells:
; over_at); the pairs' line at b2_pos (0..b2_range, its left end 0)
b2_shown:       ds 1
b2_vanish:      ds 1            ; nonzero: it just died, the volleys go (move_bullets)
b2_pos:         ds 1
b2_dir:         ds 1            ; nonzero: going left
b2_acc:         ds 1            ; ... Bresenham remainder
b2_whole:       ds 1            ; ... the swerve's px a frame ...
b2_frac:        ds 1            ; ... and remainder (fps)
b2_range:       ds 1
b2_x0:          ds 1            ; slot 0's sprite column at the left end
b2_step:        ds 1            ; ... px from a slot to the next
b2_land:        ds 1            ; ... the pairs' Y (their art box's top line)
b2_slot:        ds FORM_PAIRS_N ; per record pair (enemies 2k, 2k+1) in a pair: its slot in the line
b2_spawned:     ds 1            ; pairs it spawned
b2_desc:        ds 1            ; a spawned pair coming down: its record pair + 1 (0: none) ...
b2_drem:        ds 1            ; ... lines still to come (its Y: b2_land - this)
b2_dacc:        ds 1            ; ... Bresenham remainder
b2_dwhole:      ds 1            ; ... px a frame ...
b2_dfrac:       ds 1            ; ... and remainder
b2_dfull:       ds 1            ; ... its whole way down, in lines
b2_half:        ds 2            ; b2_spawn: a half-gone record pair's gone record (0: none yet)
bonus_text:     ds 1            ; nonzero: its bonus text shows (in bonus_buf)
bonus_buf:      ds BONUS_LEN+1
bonus_half:     ds 1            ; nonzero: the text's second half still to print (its first character)
volleys:        ds MAX_VOLLEYS*VOLLEY
ebullets:       ds EB_N*EB      ; the enemies' bullets
eb_acc:         ds 2            ; ... their Bresenham remainder (1/100 px), one for all
eb_step:        ds 1            ; ... this frame's px
eb_clock:       ds 1            ; ... 1/300 s since the last roll
eb_wipe:        ds 1            ; ... nonzero: a new wave began, all of them go (eb_move)
eb_alive:       ds 1            ; eb_move: the front's ships living when it began (FFh: not worked out yet)
eb_slot:        ds 2            ; enemy_fire: a free slot
eb_cand:        ds (ENEMY_N+1)*2 ; ... the enemies (and Boss2) that can shoot: their bullets' {Y X}
eb_cells:       ds 4            ; the 8-px columns (cells) enemy bullets are in: bit (X/8)%8 of byte X/64
eb_m:           ds BULLET_H     ; eb_masks: the bits in each of an enemy bullet's bytes
hc_first:       ds ENEMY_N      ; this frame, each enemy's art's first line (FFh: booming or gone), for ...
hc_list:        ds ENEMY_N      ; ... volley_hits: the enemies (0..) whose art has a line the volley covered
hc_n:           ds 1            ; ... how many
hc_i:           ds 1            ; bullet_hit: the enemy tried
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
hc_x:           ds ENEMY_N      ; hit_lines: each enemy's art's left column on screen, mod 256 (bullet_hit)
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
list_left:      ds 2            ; the title: frames left of the high score list, 0 = not up
ent_rec:        ds 2            ; initials: the new record ...
ent_row:        ds 1            ; ... its rank (0..HI_COUNT-1)
ent_pos:        ds 1            ; ... the slot being entered (3: all three in)
ent_letter:     ds 1            ; ... the letter picked for it (0: none)
ent_held:       ds 1            ; ... ent_dirs last frame
ent_lr:         ds 1            ; ... left and right held (ent_dirs' bits) last frame
ent_count:      ds 1            ; ... frames to the next repeat (0: none)
frames_seen:    ds 1            ; frames the splash has seen (one at a time)
egg_left:       ds 2            ; the title: frames left of the egg, 0 = not up
lic_state:      ds 1            ; ... the license: 0 not up, 1 up (keys held), 2 up, all released since
lic_taps:       ds 1            ; ... Ctrl-V presses with the egg up, CTRL held all along
egg_buf:        ds 33           ; ... a line of the egg or the license (0-terminated)
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
rot_ptr:        ds 2            ; ... the next rotation's place (rot_step) ...
rot_left:       ds 1            ; ... and how many are left
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
        assert $ <= RES_PICS && RES_PICS+(RESERVE_MAX+1)*RES_PIC <= LN_FLAGS && LN_FLAGS+256 <= IM2_TABLE && (LN_FLAGS & 0FFh) == 0
        assert (IM2_TABLE & 0FFh) == 0 && IM2_TABLE+257 <= IM2_JUMP
        ifdef BIN
        assert IM2_JUMP+3 <= BIN_STACK_ROOM
; The file's FCB and bytes, while no game runs (at power-on, and when its
; initials are in): in rot_rows
hsc_fcb         equ rot_rows
hsc_buf         equ rot_rows+FCB_LEN
        assert FCB_LEN+HSC_SIZE <= 8*16
        endif
        assert key_prev == key_state+KEY_ROWS+2   ; (ent_key)

; ---- Cartridge header -------------------------------------------------------

        ifdef BIN
        output "terrafnt.bin"
        org CODE_BASE-7         ; BLOAD header: FEh, start, end, run
        db 0FEh
        dw CODE_BASE, code_end-1, init
        else
        output "terrafnt.rom"
        endif
        org CODE_BASE
        db "AB"                 ; the BIN keeps the header, for the layout (and test.tcl's cart)
        dw init
        ds 12,0
        assert $ == CODE_BASE+10h
VERSION_BYTES:  db VERSION_MAJOR, VERSION_MINOR
                dw VERSION_PATCH
; Two license lines, egg_text-encoded, at a fixed spot: licenserom.py
; rewrites them in a built ROM (licensebin.py in a BIN, at 8014h)
        assert $ == CODE_BASE+14h
LICENSE_TEXT:
                lua allpass
                license_line("MASTER COPY - IF YOU AIN'T JCCYC")
                license_line("YOU SHOULDN'T HAVE THIS!")
                endlua
        assert $ == LICENSE_TEXT+2*LICENSE_LEN

; ---- Init ------------------------------------------------------------------

init:
        ifndef BIN
        call enable_page2       ; (first: the code past 8000h is the cartridge's from now on)
        endif
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
        ld hl,LN_FLAGS
        ld de,LN_FLAGS+1
        ld bc,255
        ld (hl),0
        ldir
        call make_reserves

        ld hl,RATES_60
        ld a,(MSXID1)
        rla
        jr nc,.hz60
        ld hl,RATES_50
.hz60:  ld de,rates
        ld bc,RATES_SIZE
        ldir
        ifdef BIN
        call hook_arm
        endif
        ld hl,HI_DEFAULTS
        ld de,hi_table
        ld bc,HI_COUNT*HI_SIZE
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
        ifdef BIN
        call hsc_load           ; (with IM 2 set up: bdos goes back to it)
        endif
        jr new_game

        ifndef BIN
; Page 2 switched to this cartridge's slot (the BIOS switched page 1 only):
; page 1's primary slot P from RSLREG; expanded (EXPTBL+P bit 7), page 1's
; subslot from SLTTBL+P, so 80h | subslot*4 | P; else P. Palavrale's.
; In page 1 (assert), as init's start.
enable_page2:
        call RSLREG
        rrca
        rrca
        and 3
        ld c,a
        ld b,0
        ld hl,EXPTBL
        add hl,bc
        ld a,(hl)
        and 80h
        jr z,.single            ; (A = 0) not expanded
        or c
        ld c,a
        inc hl                  ; SLTTBL + P
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        and 0Ch                 ; page 1's subslot
.single:
        or c
        ld h,80h
        call ENASLT
        ei                      ; (ENASLT returns with interrupts disabled)
        ret
        assert $ <= 8000h
        endif

; Game over's end: back to the title, the game's RAM as at power-on; first,
; if the score made the high score table, the initials (not attract mode's)
restart:
        call show_score         ; (score_shown: the game's last score, for the title; not attract mode's)
        call display_off
        ld hl,(GRPATR)          ; no sprites on the title
        call vdp_write
        ld a,SPR_END
        out (VDP_DATA),a
        ld a,(attract)          ; (nor in cheat mode)
        ld hl,cheat_on
        or (hl)
        call z,hi_enter
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
        call pause_check        ; (F1 or STOP: until the next press)
        call booms              ; before the hits: a new boom's first image shows its full count
        call enemy_booms        ; ... and before the hits
        call boss_booms
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
        ifdef BIN
        call disk_timer
        endif
        ld a,(frames)
        inc a
        ld (frames),a
        pop af
        ei
        reti

        ifdef BIN
; The BIN's frame interrupt also calls H.TIMI (A = the VDP status), as the
; BIOS's handler would, for the first DISK_HOOK_SECS (hook_frames): the
; disk ROM hooks it to turn the drive motor off after the BLOAD. Every
; register is kept, as the BIOS keeps them.
disk_timer:
        push hl
        ld hl,(hook_frames)
        dec hl
        bit 7,h
        jr nz,.done             ; (it stays 0)
        ld (hook_frames),hl
        push de
        push bc
        push ix
        push iy
        exx
        ex af,af'
        push hl
        push de
        push bc
        push af
        ex af,af'
        call H_TIMI
        ex af,af'
        pop af
        pop bc
        pop de
        pop hl
        ex af,af'
        exx
        pop iy
        pop ix
        pop bc
        pop de
.done:  pop hl
        ret

; disk_timer calls H.TIMI for DISK_HOOK_SECS from now (after the BLOAD,
; and after the high score file's every use: the drive motor goes off)
hook_arm:
        ld hl,DISK_HOOK_SECS*60
        ld a,(fps)
        cp 60
        jr z,.hook
        ld hl,DISK_HOOK_SECS*50
.hook:  ld (hook_frames),hl
        ret
        endif

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
        if CHEAT_KEYS
        ld a,(cheat_on)
        or a
        call nz,cheat_logo
        xor a
        ld (cheat_step),a
        endif
        ld hl,lw_text           ; the last game's level and wave (at power-on: none)
        ld de,LW_ROW*256+LW_COL*8
        ld c,TEXT_COLOR*16+BG_COLOR
        call print_text
        ld hl,score_shown       ; ... and score, right-aligned (none at power-on)
        ld de,SCORE_ROW*256+SCORE_COL*8
        call print_lead
        call show_hi
        ld a,(egg_now)          ; attract mode's (or the list's) Ctrl-V: the egg up from the start
        or a
        jr z,.text
        xor a
        ld (egg_now),a
        call show_egg
        jr .shown
.text:  call title_text         ; the credit, the URL and the blinking line
.shown: call display_on
        ld hl,(title_wait)
        ld (title_left),hl
        ld a,(frames)
        ld (frames_seen),a
        call poll_inputs        ; what's held now isn't a press (Ctrl-V neither)
.poll:  ld hl,(polls)
        inc hl
        ld (polls),hl
        call poll_inputs
        ld a,(lic_state)
        or a
        jp nz,.lic
        ld a,(key_state+KEY_ROW_CTRL)
        and KEY_CTRL
        jr z,.ctrl
        xor a
        ld (lic_taps),a         ; CTRL up: the license's taps start over
.ctrl:  call egg_pressed
        jr z,.noegg
        ld hl,(list_left)
        ld a,h
        or l
        jp nz,.legg             ; the high score list up: the title, with the egg
        call show_egg           ; (or a tap towards the license)
.noegg:
        if CHEAT_KEYS
        call cheat_word
        endif
        ld a,(lic_state)
        or a
        jr nz,.frame            ; the license just came
        ld hl,key_prev+KEY_ROW  ; space: down now, up before
        ld a,(key_state+KEY_ROW)
        cpl
        and (hl)
        and KEY_SPACE
        jr nz,.start
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
        jr z,.frame
.start: ld hl,(egg_left)        ; the egg up: it goes, the title's text back, no game
        ld a,h                  ; (the press is held at the next poll)
        or l
        jp z,.go
        ld hl,0
        ld (egg_left),hl
        call show_title_text
.frame: ld a,(frames)
        ld hl,frames_seen
        cp (hl)
        jr z,.poll
        inc (hl)                ; a new frame (one at a time: a slow poll's are caught up on)
.blink: ld a,(lic_state)
        or a
        jr nz,.poll             ; the license up: no blink, no count
        ld hl,(list_left)
        ld a,h
        or l
        jr nz,.list
        ld hl,(egg_left)
        ld a,h
        or l
        jr z,.blnk
        dec hl                  ; the egg up: no blink, the title's text back at its end
        ld (egg_left),hl
        ld a,h
        or l
        call z,show_title_text
        jr .count
.blnk:  call blink
.count: ld hl,(title_left)
        dec hl
        ld (title_left),hl
        ld a,h
        or l
        jp nz,.poll
        call show_list          ; the title's time over: the high score list
        jp .poll
.list:  dec hl                  ; its time over: attract mode
        ld (list_left),hl
        ld a,h
        or l
        jp nz,.poll
        jr .attract
.legg:  ld (egg_now),a          ; (nonzero)
        ld hl,0
        ld (list_left),hl
        call display_off
        jp splash
; the license up: once all keys and buttons were released, a press of any
; takes it away (and starts nothing: it's held at the next poll)
.lic:   call any_input
        ld hl,lic_state
        jr z,.armed
        ld a,(hl)
        cp 2
        call z,hide_license
        jr .frame
.armed: ld (hl),2
        jr .frame
.attract:
        inc a                   ; left alone: attract mode
        ld (attract),a
        call display_off
        jp clear_below
.go:    call display_off
        ; fall through

; SCREEN 2's tables cleared, all black: all of them (clear_all), or from
; character row 1 on (clear_below: the top status row stays)
clear_all:
        ld hl,0
        ld bc,24*256
        jr clear_rows
clear_below:
        ld hl,256
        ld bc,23*256
        assert LW_ROW == 0 && SCORE_ROW == 0
clear_rows:
        push hl
        push bc
        ld de,(GRPCGP)
        add hl,de
        xor a
        call FILVRM
        pop bc
        pop hl
        ld de,(GRPCOL)
        add hl,de
        ld a,BG_COLOR*16+BG_COLOR
        jp FILVRM

; ---- The title's texts: its own, the egg, the license ----------------------

; The title's text over the picture (just unpacked): the credit and URL,
; centred, staying, and the blinking line, shown, its blink from the start
title_text:
        ld c,TEXT_COLOR*16+BG_COLOR
        ld hl,CREDIT_TEXT
        ld de,CREDIT_ROW*256+(32-CREDIT_LEN)/2*8
        call print_text
        ld hl,URL_TEXT
        ld de,URL_ROW*256+(32-URL_LEN)/2*8
        call print_text
        call print_press
        ld a,(blink_on)
        ld (blink_left),a
        ld a,1
        ld (blink_shown),a
        ret

; The license's end: the title's text back, its count to attract mode from
; the start
hide_license:
        xor a
        ld (lic_state),a
        ld hl,(title_wait)
        ld (title_left),hl
        ; fall through
; The egg's (or the license's) end: the title's text back
show_title_text:
        call title_rows
        jr title_text

; The picture's rows EGG_ROW..23 again (title.inc's rows are packed one by
; one), whatever text was over them gone. A frame's time or so.
title_rows:
        ld hl,TITLE_PAT_ROWS+EGG_ROW*2
        ld de,(GRPCGP)
        call .rows
        ld hl,TITLE_COL_ROWS+EGG_ROW*2
        ld de,(GRPCOL)
.rows:  ld a,d
        add a,EGG_ROW
        ld d,a
        ld b,24-EGG_ROW
        jp unpack_rows.n

; Has Ctrl-V just gone down in the splash's last poll (V pressed with CTRL
; held, or the other way round)? NZ if so.
egg_pressed:
        ld hl,key_state
        call .both
        jr nz,.no
        ld hl,key_prev
        call .both
        ret nz
.no:    xor a
        ret
; Z: CTRL and V both down in the rows at HL
.both:  push hl
        ld de,KEY_ROW_CTRL
        add hl,de
        ld a,(hl)
        pop hl
        and KEY_CTRL
        ret nz
        ld de,KEY_ROW_V
        add hl,de
        ld a,(hl)
        and KEY_V
        ret

        if CHEAT_KEYS
; The splash's last poll: CTRL up, CHEAT_WORD starts over; else a letter
; just pressed on the title (not the list) is its next (on its last:
; cheat mode on, the logo recoloured), or a wrong one (it starts over: a
; first letter counts as the first)
cheat_word:
        ld hl,cheat_step
        ld a,(key_state+KEY_ROW_CTRL)
        and KEY_CTRL
        jr nz,.over
        ld de,(list_left)
        ld a,d
        or e
        ret nz
        push hl
        call ent_key            ; A: the letter (or BS, RETURN, 0)
        pop hl
        or a
        ret z
        ld b,a
        ld e,(hl)
        ld d,0
        push hl
        ld hl,CHEAT_TEXT
        add hl,de
        ld a,(hl)
        pop hl
        xor CHEAT_XOR
        cp b
        jr z,.next
        ld a,(CHEAT_TEXT)
        xor CHEAT_XOR
        cp b
        ld a,1
        jr z,.set
.over:  xor a
.set:   ld (hl),a
        ret
.next:  inc (hl)
        ld a,(hl)
        cp CHEAT_LEN
        ret c
        ld (hl),0
        ld a,CHEAT_MASK
        ld (cheat_on),a
        ; fall through

; The logo in CHEAT_LOGO_COLOR: in the colour table's rows 0..EGG_ROW-1
; (the picture's, the text's are white), each nibble LOGO_COLOR changed.
; Read and written back a byte at a time (a byte changed only), at least
; 29 T between VRAM accesses: safe outside vertical blank. Under 0.3 s.
cheat_logo:
        ld hl,(GRPCOL)
        ld bc,EGG_ROW*256
.byte:  di
        ld a,l
        out (VDP_ADDR),a
        ld a,h
        out (VDP_ADDR),a
        ei
        ex (sp),hl              ; (the VDP's read-ahead)
        ex (sp),hl
        in a,(VDP_DATA)
        ld e,a
        ld d,a
        and 0F0h
        cp LOGO_COLOR*16
        jr nz,.lo
        ld a,d
        xor (LOGO_COLOR^CHEAT_LOGO_COLOR)*16
        ld d,a
.lo:    ld a,d
        and 0Fh
        cp LOGO_COLOR
        jr nz,.put
        ld a,d
        xor LOGO_COLOR^CHEAT_LOGO_COLOR
        ld d,a
.put:   ld a,d
        cp e
        jr z,.same
        di
        ld a,l
        out (VDP_ADDR),a
        ld a,h
        or 40h
        out (VDP_ADDR),a
        ei
        ld a,d
        out (VDP_DATA),a
.same:  inc hl
        dec bc
        ld a,b
        or c
        jr nz,.byte
        ret

; CHEAT_WORD, each letter XORed with CHEAT_XOR (not plain in a ROM dump)
CHEAT_XOR       equ 5Ah
CHEAT_TEXT:
        lua allpass
        local w = string.gsub(sj.get_define("CHEAT_WORD"), '"', '')
        for i = 1, #w do
            sj.add_byte(string.byte(w, i) ~ sj.get_label("CHEAT_XOR"))
        end
        endlua
CHEAT_LEN       equ $-CHEAT_TEXT
        assert CHEAT_LEN >= 2 && CHEAT_LEN < 256
        endif

; NZ: any key of matrix rows 0..KEY_ANY_ROWS-1 or either joystick's button
; down in the splash's last poll (not the sticks' directions)
any_input:
        ld hl,key_state
        ld b,KEY_ANY_ROWS
.row:   ld a,(hl)
        inc hl
        inc a                   ; (FFh: none down)
        ret nz
        djnz .row
        ld a,(key_state+KEY_ROWS)
        ld hl,key_state+KEY_ROWS+1
        and (hl)
        cpl
        and JOY_BUTTONS
        ret

; The title: the egg over the picture for EGG_SECS, in place of its text
; (if it's up already, a tap towards the license): "VERSION X.Y.Z" on
; EGG_ROW, EGG_TEXTS' lines under it, each centred
show_egg:
        ld hl,(egg_left)
        ld a,h
        or l
        jr nz,egg_tap
        ld (lic_taps),a
        ld hl,(egg_frames)
        ld (egg_left),hl
        call title_rows         ; the title's text gone
        ld hl,EGG_LABEL
        ld de,egg_buf
        ld bc,EGG_LABEL_LEN
        ldir
        ld a,(VERSION_BYTES)
        call .byte
        ld a,(VERSION_BYTES+1)
        call .byte
        ld hl,(VERSION_BYTES+2)
        call put_dec
        xor a
        ld (de),a
        ld b,EGG_ROW
        call print_buf
        ld hl,EGG_TEXTS
        ld b,EGG_ROW+1
.text:  ld a,(hl)
        or a
        ret z
        inc hl
        push bc
        ld b,a
        call decode
        pop bc
        push hl
        push bc
        call print_buf
        pop bc
        pop hl
        inc b
        jr .text
; A = a number: its digits at DE, then a '.'
.byte:  ld l,a
        ld h,0
        call put_dec
        ld a,'.'
        ld (de),a
        inc de
        ret

; Ctrl-V with the egg up and CTRL held since the last: on the last tap,
; the license in its place, with no timer
egg_tap:
        ld hl,lic_taps
        inc (hl)
        ld a,(hl)
        cp LICENSE_TAPS
        ret c
        ld hl,0
        ld (egg_left),hl
        inc l
        ld (lic_state),hl       ; up, keys held (lic_taps 0)
        assert lic_taps == lic_state+1
        call title_rows         ; the egg gone
        ld hl,LICENSE_TEXT
        ld b,LICENSE_LEN
        call decode
        push hl
        ld b,LICENSE_ROW
        call print_buf
        pop hl
        ld b,LICENSE_LEN
        call decode
        ld b,LICENSE_ROW+1
        ; fall through

; egg_buf's text without its trailing spaces (all spaces: nothing),
; centred on character row B (odd lengths a half cell left), white
print_buf:
        ld hl,egg_buf
        ld c,0                  ; its length up to its last non-space
        ld e,c
.len:   ld a,(hl)
        or a
        jr z,.end
        inc hl
        inc e
        cp ' '
        jr z,.len
        ld c,e
        jr .len
.end:   ld a,c
        or a
        ret z
        ld e,c
        ld d,0
        ld hl,egg_buf
        add hl,de
        ld (hl),d               ; the end
        ld a,32
        sub c
        srl a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,b
        ld hl,egg_buf
        ld c,TEXT_COLOR*16+BG_COLOR
        jp print_text

; B bytes at HL, egg_text-encoded, decoded into egg_buf (0-terminated); HL
; past them
decode: ld de,egg_buf
        ld c,EGG_KEY
.loop:  ld a,(hl)
        xor c
        ld (de),a
        inc hl
        inc de
        ld a,c
        add a,EGG_KEY_STEP
        ld c,a
        djnz .loop
        xor a
        ld (de),a
        ret

; HL = a number: its decimal digits (no leading zeros) at DE, DE past them
put_dec:
        ld ix,DEC_POWERS
        ld bc,5*256             ; B: digits to go; C: nonzero once one was written
.pow:   push bc
        push de
        ld e,(ix+0)
        ld d,(ix+1)
        inc ix
        inc ix
        ld a,'0'-1
.sub:   inc a
        or a
        sbc hl,de
        jr nc,.sub
        add hl,de
        pop de
        pop bc
        cp '0'
        jr nz,.put
        inc c
        dec c
        jr nz,.put
        dec b
        jr z,.last              ; the last digit: always
        inc b
        jr .next
.last:  inc b
.put:   ld (de),a
        inc de
        ld c,1
.next:  djnz .pow
        ret

; One frame of the splash's blinking text: after blink_on frames shown,
; its cells' colours go all black for blink_off frames, then white again
blink:
        call blink_tick
        ret nz
; "PRESS SPACE OR FIRE TO BEGIN", centred on BLINK_ROW, in colour C
print_press:
        ld hl,PRESS_TEXT
        ld de,BLINK_ROW*256+(32-PRESS_LEN)/2*8
; Text in the game's font (font.py) on SCREEN 2: HL = the text, ASCII
; 20h..5Fh, 0-terminated; DE = its first cell (row*256 + column*8); C = the
; colour byte (foreground*16 + background) for all 8 lines of its cells
; (0: the colours left as they are).
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
        inc c
        dec c
        jr z,.nocol
        ld hl,(GRPCOL)
        add hl,de
        call vdp_write
        ld a,c
        ld b,8
.col:   out (VDP_DATA),a        ; 32 T
        nop
        nop
        djnz .col
.nocol: ld hl,8                 ; the next cell
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
; (B rows)
.n:
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
        ld c,0
        ld a,KEY_ROW
        call key_row
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
.k3:    ld a,KEY_ROW_C
        call key_row
        and KEY_C
        jr nz,.k4
        set 7,c                 ; IN_CALL
.k4:     ld b,03h                ; joystick 1: (R15 and AFh) or 03h
        ld e,0AFh
        call read_joy
        ld b,4Ch                ; joystick 2: (R15 and DFh) or 4Ch
        ld e,0DFh
        call read_joy
        ld a,(attract)
        or a
        jr nz,.cpu
        if CHEAT_KEYS
        ld a,KEY_ROW_1          ; the cheat keys 1..4 (only in cheat mode)
        call key_row
        cpl                     ; 1 = pressed
        ld b,a
        rrca                    ; KEY_1, KEY_2 to bits 0, 1 (IN_BOSS, IN_SHIP)
        and IN_BOSS|IN_SHIP
        ld d,a
        ld a,b
        rlca                    ; KEY_3, KEY_4 to bits 5, 6 (IN_INVUL, IN_KILL)
        rlca
        and IN_INVUL|IN_KILL
        or d
        ld hl,cheat_on
        and (hl)
        or c
        ld c,a
        endif
        ld a,c
        ld (input),a
        ret
.cpu:   ld a,KEY_ROW_CTRL       ; attract mode: Ctrl-V too (IN_EGG)
        call key_row
        ld b,a
        ld a,KEY_ROW_V
        call key_row
        and KEY_V
        jr nz,.noegg
        ld a,b
        and KEY_CTRL
        jr nz,.noegg
        set 6,c                 ; IN_EGG
.noegg: ld hl,att_real          ; the real input only quits it (a press of
        ld a,(hl)               ; fire or Ctrl-V), the pseudo-player's plays
        ld (hl),c
        cpl
        and c
        ld b,a
        and IN_EGG              ; Ctrl-V: the title, with the egg up
        ld (egg_now),a
        ld a,b
        and IN_FIRE|IN_EGG
        ld (att_quit),a
        call attract_cpu
        ld (input),a
        ret
        assert IN_LEFT == 04h && IN_RIGHT == 08h && IN_FIRE == 10h && IN_CALL == 80h && IN_BOSS == 01h && IN_SHIP == 02h && IN_EGG == 40h
        assert SPR_EC == 80h && IN_KILL == IN_EGG     ; (IN_KILL read outside attract mode only)
        assert KEY_1 == IN_BOSS*2 && KEY_2 == IN_SHIP*2 && KEY_3*4 == IN_INVUL && KEY_4*4 == IN_KILL

; A = keyboard row A (bit = 0 when pressed). Keeps BC, D, HL.
key_row:
        ld e,a
        in a,(PPI_C)
        and 0F0h
        or e
        out (PPI_C),a
        in a,(PPI_B)
        ret

; The pause (not in attract mode): a press of F1 or STOP stops the game
; (nothing moves; the PSG silent, init_sound), PAUSED centred on the top
; status row, until the next press; then the text goes and the game goes
; on, with the input read again (read_input: what's held then isn't a
; press of fire or call-up)
pause_check:
        ld a,(attract)
        or a
        ret nz
        call pause_key
        ret z
        ld hl,PAUSE_TEXT
        ld c,TEXT_COLOR*16+BG_COLOR
        call .print
        call init_sound
.wait:  halt
        call pause_key
        jr z,.wait
        ld hl,PAUSE_BLANK
        ld c,BG_COLOR*16+BG_COLOR   ; (the status row's cells as they were)
        call .print
        halt
        jp read_input
.print: ld de,PAUSE_ROW*256+PAUSE_COL*8
        jp print_text

; NZ: F1 or STOP pressed now, up last time (pause_held)
pause_key:
        ld a,KEY_ROW_F1
        call key_row
        and KEY_F1
        ld c,a
        ld a,KEY_ROW_STOP
        call key_row
        and KEY_STOP
        or c
        xor KEY_F1|KEY_STOP     ; 1 = held
        ld hl,pause_held
        ld c,(hl)
        ld (hl),a
        ld a,c
        cpl
        and (hl)
        ret
        assert (KEY_F1 & KEY_STOP) == 0

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
; target column. Every other run (att_runs odd) a boss instead of wave 1,
; Boss1 and Boss2 in turn: the waves before it counted as played
; (form_enemy, form_cidx, wave_n, as cheat_boss), every enemy gone, the
; boss begun (its sprites from build_sat's SAT on; Boss2 in the bitmap
; now, the display off); the level stays 1, the next wave the one after it
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
        ld hl,att_runs
        ld a,(hl)
        inc (hl)
        rra
        ret nc                  ; (even: wave 1)
        rra
        ld a,ATTRACT_BOSS1
        jr nc,.boss
        ld a,BOSS2_AFTER
.boss:  dec a
        ld (form_enemy),a
        ld (wave_n),a
.cidx:  sub FORM_COLORS_N
        jr nc,.cidx
        add a,FORM_COLORS_N
        ld (form_cidx),a
        ld hl,enemies+EN.ST
        ld de,EN
        ld b,ENEMY_N
.gone:  ld (hl),EN_GONE
        add hl,de
        djnz .gone
        jp boss_begin
        assert ATTRACT_BOSS1 != BOSS2_AFTER && ATTRACT_BOSS1 <= ENEMIES && BOSS2_AFTER <= ENEMIES

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
; top or bottom line: back on it, and a random direction away from it (from
; the bottom, BOUNCE_MIN_DEG or more from level).
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
.up:    call rand               ; up, BOUNCE_MIN_DEG or more from level
        and FREE_DIRS/2-1
        cp BOUNCE_DIRS
        jr nc,.up
        add a,FREE_DIRS/2+BOUNCE_STEPS
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
        ld hl,b2_vanish         ; Boss2 died: the volleys go (all erased now)
        ld a,(hl)
        or a
        jr z,.drawv
        xor a
        ld (hl),a
        ld (volleys+VOLLEY.Y),a
        ld (volleys+VOLLEY+VOLLEY.Y),a
.drawv: ld ix,volleys
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
        assert PLAY_TOP > (BULLET_SPEED+49)/50 && MAX_VOLLEYS == 2

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
; from then on; during a boss, the first). Keeps C, DE.
wave_entry:
        ld a,(boss_st)          ; (a boss: wave 1's)
        or a
        ld a,(wave_n)
        jr z,.w
        xor a
.w:     cp b
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
; starts to die (ship_dies; not again if a bullet hit it already).
; Keeps IX.
eb_hit:
        ld a,(invul)
        or a
        ret nz                  ; invulnerable: no hit (no carry)
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
; EB_DX, its top right under the art's last row (eb_draw draws it); with
; Boss2 fighting, it's one of them too (from its lower edge, at a random
; one of its columns), and its spawn coming down isn't
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
        ld a,ENEMY_N            ; Boss2's spawn coming down (b2_desc: its
        sub b                   ; record pair + 1) can't yet
        rrca
        and 3
        inc a
        ld hl,b2_desc
        cp (hl)
        call nz,eb_can          ; (Z: no carry)
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
        ld a,(boss_st)          ; Boss2 fighting: one more, from a random
        cp BS_FIGHT             ; column of its art's lower edge
        jr nz,.nob
        ld a,(boss_kind)
        or a
        jr z,.nob
        ld (hl),BOSS_EB_Y
        inc hl
        push hl
        call rand
        pop hl
        and BOSS_W-1
        add a,B2_X
        ld (hl),a
        inc c
.nob:   ld a,c
        or a
        ret z                   ; none
        ld b,a
        ld e,ENEMY_N-1          ; (rolls of 0..ENEMY_N-1; with Boss2's, 0..15)
        cp ENEMY_N+1
        jr c,.pick
        ld e,15
.pick:  call rand
        and e
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
        assert ENEMY_N == 8 && (ebullets+EB_N*EB)/256 == ebullets/256 && FORM_PAIRS_N == 4

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
        call eb_masks           ; C = its bit
        jr nz,.shared
        call bullet_px          ; its bit alone
        jr .done
.shared:
        ld hl,eb_m
        ld b,BULLET_H
.row:   call over_at
        jr c,.rnext             ; GAME OVER's
        push hl
        ld a,(pat_hi)
        call vdp_at
        pop hl
        ld a,(hl)
        out (VDP_DATA),a
.rnext: inc hl
        inc e
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

; The enemy bullet at column D, top line E: eb_m = the bits of every bullet
; in flight (the volleys' and the enemies') in each of its 3 bytes, in one
; pass; C = its own bit; Z: no other bullet's bit in them (it can be drawn
; alone). Keeps DE.
eb_masks:
        ld a,d
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld a,(hl)
        ld (eb_m),a
        ld (eb_m+1),a
        ld (eb_m+2),a
        push af
        ld hl,volleys
        ld b,MAX_VOLLEYS
.v:     ld a,(hl)
        or a
        jr z,.nv
        sub e
        add a,BULLET_H-1
        cp 2*BULLET_H-1
        jr nc,.nv               ; their lines apart
        push bc
        push hl
        call .rowm
        ld b,a                  ; the rows they share
        ld c,FRONT_MAX
.x:     inc hl
        ld a,(hl)
        or a
        jr z,.nx
        xor d
        and 0F8h
        jr nz,.nx
        ld a,(hl)
        call .or
.nx:    dec c
        jr nz,.x
        pop hl
        pop bc
.nv:    ld a,l
        add a,VOLLEY
        ld l,a
        djnz .v
        ld hl,ebullets          ; (itself too: its own bits)
        ld b,EB_N
.e:     ld a,(hl)
        inc hl
        or a
        jr z,.ne
        sub e
        add a,BULLET_H-1
        cp 2*BULLET_H-1
        jr nc,.ne
        ld c,a
        ld a,(hl)
        xor d
        and 0F8h
        jr nz,.ne
        push bc
        ld a,c
        call .rowm
        ld b,a
        ld a,(hl)
        call .or
        pop bc
.ne:    inc hl
        djnz .e
        pop af
        ld c,a                  ; its bit
        ld hl,eb_m
        ld a,(hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        xor c                   ; Z: only its own
        ret
; A (0..4: the other's top - E + 2) := the rows (bits 0..2) both cover
.rowm:  push hl
        add a,low ROW_MASKS
        ld l,a
        ld h,high ROW_MASKS
        ld a,(hl)
        pop hl
        ret
; eb_m's rows in B |= column A's bit. Keeps BC, DE, HL.
.or:    push hl
        push bc
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld c,(hl)
        ld hl,eb_m
        dup BULLET_H
        rr b
        jr nc,1f
        ld a,c
        or (hl)
        ld (hl),a
1:      inc hl
        edup
        pop bc
        pop hl
        ret
        assert BULLET_H == 3 && volleys/256 == (volleys+MAX_VOLLEYS*VOLLEY-1)/256

; ---- Hits ------------------------------------------------------------------

; The volley at IX against the enemies where they show now: each bullet
; whose column has a pixel of a living enemy's art on lines D..E (the lines
; it covered this frame) is gone and the enemy hit (bullet_hit). A volley
; left with no bullet is free. Only the enemies whose art has a line in
; D..E (from hc_first) are tried (hc_list). Keeps DE, IX.
volley_hits:
        ld a,(boss_st)
        cp BS_FIGHT
        jr nz,.en
        ld a,(boss_kind)
        or a
        jp z,boss_volley        ; Boss1 (no enemies then)
        call .en                ; Boss2: the enemies first (in front of it), then it
        ld a,(ix+VOLLEY.Y)
        or a
        ret z
        jp boss_volley
.en:    push de
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
.e:     ld a,(hl)               ; first: column C not in its art's 8 (hc_x;
        push hl                 ; mod 256: off-screen ones may pass, tried
        add a,low hc_x          ; below)
        ld l,a
        ld h,high hc_x
        ld a,c
        sub (hl)
        pop hl
        cp 8
        jr c,.try
        inc hl
        djnz .e
        or a
        ret
.try:   push bc
        push hl
        ld a,(hl)
        ld (hc_i),a
        ld l,a
        add a,a
        add a,a
        add a,a
        add a,l                 ; * EN
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
        assert EN_FORM == 0 && EN_FREE < EN_BOOM && EN == 9 && ENEMY_N*EN < 256
        assert hc_x/256 == (hc_x+ENEMY_N-1)/256 && FORM_WRAP-256 == 16

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
        jr nc,.put              ; (booming or gone: never in hc_list, no hc_x)
        ld a,(iy+EN.X+1)        ; hc_x: its art's left column on screen,
        neg                     ; mod 256 (X 256..: X - 272)
        and 16
        ld e,a
        ld a,(iy+EN.X)
        sub e
        push hl
        ld de,hc_x-hc_first
        add hl,de
        ld (hl),a
        pop hl
        ld de,EN
        ld a,(iy+EN.Y)
        add a,c                 ; (no carry: the art is in the playfield; but
        jr nc,.put              ; Boss2's spawn coming down, its art box partly
        ld a,0FFh               ; above line 0: not hit yet; all above: its
.put:   ld (hl),a               ; first line FxH, under no bullet's lines either)
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
; the ship's, and the enemy booms (as when shot) and the ship dies
; (ship_dies). Every enemy and ship that touch: a ship living when this
; began touches a second enemy too (it dies once). Pairs never reach the
; front's lines.
collide:
        ld a,(rot_left)
        or a
        call nz,rot_step
        ld a,(invul)
        or a
        ret nz                  ; invulnerable: enemies pass through
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

; The wave's next rotation of its art's rows in rot_rows (A: how many are
; left), one a frame after load_formation: no free enemy can reach the
; front's lines (the only place collide uses them) in those frames
rot_step:
        dec a
        ld (rot_left),a
        ld hl,(rot_ptr)
        ld d,h
        ld e,l
        ld bc,-16
        add hl,bc
        dup 16
        ld a,(hl)
        rrca
        ld (de),a
        inc hl
        inc de
        edup
        ld (rot_ptr),de
        ret
        assert FORM_Y0+FORM_RISE+FORM_H+7*3 <= SHIP_TOP+SHIP_ART_T     ; (a free enemy: under 3 px a frame)

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
; lines apart. Keeps IX. With no middle text (nor Boss2's lines), the VRAM
; addresses worked out once for the volley (its lines are all its
; bullets'), 31 T between writes.
volley_px:
        ld a,(mid_text)
        or a
        jp nz,.slow
        ld a,(b2_shown)         ; (Boss2: the slow way on its lines)
        or a
        jr z,.fast
        ld a,(ix+VOLLEY.Y)
        cp B2_Y+BOSS_H
        jp c,.slow
.fast:  ld a,(ix+VOLLEY.Y)
        ld e,a
        and 7
        ld (vp_y7),a            ; its first line in its cell row
        ld d,a
        ld a,8
        sub d                   ; lines left in that cell row
        cp BULLET_H
        jr c,.n1
        ld a,BULLET_H
.n1:    ld (vp_n1),a
        neg
        add a,BULLET_H
        ld (vp_n2),a            ; ... and in the next one
        ld a,e
        rrca
        rrca
        rrca
        and 1Fh
        ld d,a
        ld a,(pat_hi)
        or d
        ld (vp_hi),a
        ld d,c                  ; D: draw (nonzero) or erase
        push ix
        pop hl
        inc hl                  ; X
        ld c,FRONT_MAX
.fb:    ld a,(hl)
        or a
        jr z,.fnext
        ld e,0                  ; E: its byte (erase: 0)
        inc d
        dec d
        jr z,.f0
        push hl
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld e,(hl)               ; the column's bit in its byte
        pop hl
        ld a,(hl)
.f0:    and 0F8h                ; its cell's column
        ld b,a
        ld a,(vp_y7)
        or b
        di
        out (VDP_ADDR),a
        ld a,(vp_hi)
        out (VDP_ADDR),a
        ei
        ld a,(vp_n1)
        ld b,a
.f1:    ld a,e                  ; 31 T a byte
        out (VDP_DATA),a
        djnz .f1
        ld a,(vp_n2)
        or a
        jr z,.fnext
        ld b,a                  ; the rest: the next cell row, from line 0
        ld a,(hl)
        and 0F8h
        di
        out (VDP_ADDR),a
        ld a,(vp_hi)
        inc a
        out (VDP_ADDR),a
        ei
.f2:    ld a,e
        out (VDP_DATA),a
        djnz .f2
.fnext: inc hl
        dec c
        jr nz,.fb
        ret
.slow:  ld e,(ix+VOLLEY.Y)
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
; text's cells and Boss2's (over_at)
bullet_px:
        ld b,BULLET_H
.cell:  ld a,(mid_text)
        ld l,a
        ld a,(b2_shown)
        or l                    ; (no carry)
        call nz,over_at
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
.skip:  dec b                   ; kept cells: their lines left alone
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
        ld hl,ln_list           ; last frame's line flags off
        ld a,(ln_n)
        or a
        jr z,.marks
        ld b,a
        ld d,high LN_FLAGS
        xor a
.un:    ld e,(hl)
        ld (de),a
        inc hl
        djnz .un
        ld hl,ln_list
.marks: ld de,volleys           ; the lines the bullets are on now
        ld b,MAX_VOLLEYS
.v:     ld a,(de)
        or a
        call nz,ln_bullet
        ld a,e
        add a,VOLLEY
        ld e,a
        djnz .v
        ld de,ebullets
        ld b,EB_N
.eb:    ld a,(de)
        or a
        call nz,ln_bullet
        inc e
        inc e
        djnz .eb
        ld a,(mid_text)         ; ... and the middle text's row
        or a
        jr z,.nomid
        ld d,high LN_FLAGS
        ld e,OVER_ROW*8
        ld b,8
.mid:   ld a,(de)
        or LN_MID
        ld (de),a
        ld (hl),e
        inc hl
        inc e
        djnz .mid
.nomid: ld a,(b2_shown)         ; ... and Boss2's
        or a
        jr z,.nob2
        ld d,high LN_FLAGS
        ld e,B2_Y
        ld b,BOSS_H
.b2:    ld a,(de)
        or LN_MID
        ld (de),a
        ld (hl),e
        inc hl
        inc e
        djnz .b2
.nob2:  ld a,l
        sub low ln_list
        ld (ln_n),a
        ld a,(star_whole)
        ld b,a
        ld a,(star_frac)
        ld d,a
        ld hl,star_acc
        call bresenham
        ld (star_step),a
        ld c,a
        ld hl,stars             ; a star shown, no bullet in its byte (or the
        ld b,STARS              ; one it steps into; LN_FLAGS first, then
.f:     ld d,(hl)               ; bullet_at), not on the middle text's row:
        inc hl                  ; nothing to do, or a step (its new bit; or,
        ld e,(hl)               ; into the next byte, the old one blank and
        inc hl                  ; the new one drawn); else the full way (star)
        ld a,(hl)               ; ON
        or a
        jr z,.slow
        push hl
        ld h,high LN_FLAGS
        ld l,e
        ld a,(hl)
        or a
        jr z,.clear             ; nothing on its line
        and LN_MID
        jr nz,.slowp            ; kept cells' row (the middle text's, Boss2's)
        call bullet_at          ; a bullet on its line: in its byte?
        jr c,.slowp
        ld a,c
        or a
        jr z,.clear
        ld a,d
        sub c
        jr c,.slowp             ; (out past column 0)
        xor d
        and 0F8h
        jr z,.clear
        push de                 ; ... or in the next one, if it goes there?
        ld a,d
        sub c
        ld d,a
        call bullet_at
        pop de
        jr c,.slowp
.clear: pop hl
        ld a,c
        or a
        jr z,.next              ; no step: as it is
        ld a,d
        sub c
        jr c,.slow              ; out past column 0
        push hl
        xor d
        and 0F8h
        jr z,.same
        ld a,(pat_hi)           ; into the next byte: the old one blank, its
        call vdp_at             ; colour back to a bullet's (as star's .off)
        xor a
        out (VDP_DATA),a
        ld a,(col_hi)
        call vdp_at
        ld a,BULLET_COLOR*16+BG_COLOR
        out (VDP_DATA),a
        ld a,d
        sub c
        ld d,a
        call star_px
        ld a,(col_hi)
        call vdp_at
        ld a,STAR_COLOR*16+BG_COLOR
        out (VDP_DATA),a
        jr .put
.same:  ld a,d
        sub c
        ld d,a
        call star_px
.put:   pop hl
        dec hl
        dec hl
        ld (hl),d               ; X
        inc hl
        inc hl
        jr .next
.slowp: pop hl
.slow:  push bc
        push hl
        dec hl
        dec hl
        push hl
        pop ix
        call star
        pop hl
        pop bc
.next:  inc hl
        dec b
        jp nz,.f
        ret
        assert STAR == 3 && STAR.X == 0 && STAR.Y == 1 && STAR.ON == 2
        assert volleys/256 == (volleys+MAX_VOLLEYS*VOLLEY-1)/256 && ebullets/256 == (ebullets+EB_N*EB-1)/256

; Pixel (D, E)'s pattern byte := its bit alone (pat_bit, vdp_at inlined).
; Keeps BC, DE.
star_px:
        ld a,e
        and 7
        ld l,a
        ld a,d
        and 0F8h
        or l
        di
        out (VDP_ADDR),a
        ld a,e
        rrca
        rrca
        rrca
        and 1Fh
        ld l,a
        ld a,(pat_hi)
        or l
        out (VDP_ADDR),a
        ei
        ld a,d
        and 7
        add a,low PIXEL_BIT
        ld l,a
        ld h,high PIXEL_BIT
        ld a,(hl)
        out (VDP_DATA),a
        ret

; Lines A..A+BULLET_H-1 flagged LN_BULLET, each put in the list at HL (HL
; past them). Keeps B, DE.
ln_bullet:
        push de
        ld d,high LN_FLAGS
        ld e,a
        dup BULLET_H
        ld a,(de)
        or LN_BULLET
        ld (de),a
        ld (hl),e
        inc hl
        inc e
        edup
        pop de
        ret

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
        ld h,high LN_FLAGS      ; first: none on line E (LN_FLAGS), none
        ld l,e
        bit 0,(hl)
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

; The wave's enemy (form_enemy) and colour (FORM_COLORS[form_cidx], every
; enemy record's): its art's rows and bounds, its colour, its pair's and
; its lone enemy's patterns in VRAM (no enemy sprite shows them while they
; change)
load_formation:
        ld a,(form_cidx)
        ld e,a
        ld d,0
        ld hl,FORM_COLORS
        add hl,de
        ld a,(hl)
        ld (form_color),a
        ld hl,enemies+EN.COL    ; every enemy's
        ld de,EN
        ld b,ENEMY_N
.col:   ld (hl),a
        add hl,de
        djnz .col
        ld a,(form_enemy)
; ... enemy A's (not its colour; Boss2's)
load_enemy:
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
        ld de,rot_rows          ; its rows rotated right 0..7 bits (collide):
        ld bc,16                ; 0 now, the rest one a frame (rot_step)
        ldir
        ld (rot_ptr),de
        ld a,7
        ld (rot_left),a
        ld hl,(GRPPAT)          ; the formation's pair, then one enemy alone:
        ld de,NAME_ENEMY*8      ; its rows and 16 blank (NAME_ENEMY1 follows)
        add hl,de
        call vdp_write
        ld hl,(form_rows)
        ld b,32
.pat:   ld a,(hl)               ; 37 T a byte
        out (VDP_DATA),a
        inc hl
        djnz .pat
        ld hl,(form_rows)
        ld b,16
.one:   ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .one
        ld b,16
        xor a
.blank: out (VDP_DATA),a        ; 32 T
        nop
        nop
        djnz .blank
        ret
        assert NAME_ENEMY1 == NAME_ENEMY+4
        assert NAME_BOOM+BOOM_STAGES*4 <= NAME_ENEMY && NAME_ENEMY1 == NAME_ENEMY+4

; Every enemy gone: WAVE_DELAY_MS later (wave_delay frames after the frame
; the last one went), a new wave, the next enemy (images/enemy-0..9.png in
; turn) in the next colour of FORM_COLOR_LIST (each list from its start
; again after its last), the formation in its pairs at the loop's start;
; after a wave of BOSS_AFTER_LIST, the boss instead, and the next wave once
; its bonus is over. While the boss is on: it moves (fighting), or its
; bonus ends (BS_END: the text gone, the score; BS_NEXT: the next wave)
next_wave:
        if CHEAT_KEYS
        call cheat_keys         ; 2, 3, 4
        endif
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
.waves:
        if CHEAT_KEYS
        ld a,(input_prev)       ; the cheat key 1 pressed: to the next boss
        cpl
        ld hl,input
        and (hl)
        and IN_BOSS
        call nz,cheat_boss
        endif
        ld hl,wave_wait
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
        jp bonus_ship
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
        ld hl,enemies           ; all EN_FORM, as at the start
        ld de,enemies+1
        ld bc,ENEMY_N*EN-1
        ld (hl),0
        ldir
        call load_formation     ; (their colour too)
        call level_text
        ld hl,FORM_X0
        ld (form_x),hl
        ld hl,0
        ld (form_tick),hl
        xor a
        ld (form_acc),a
        jp form_place
        assert EN_FORM == 0

; A bonus ship (next_wave.done; the cheat key 2): not in game over (nor
; attract mode: the pseudo-player never presses the key), a reserve ship
; more, if under RESERVE_MAX, shown in the reserve and the happy beep
bonus_ship:
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

        if CHEAT_KEYS
; The cheat keys 2, 3 and 4 (next_wave, a boss on or not; never pressed in
; attract mode): key 2 a reserve ship (bonus_ship), key 3 invulnerability
; on or off, key 4 a random living ship of the front dies (ship_dies)
cheat_keys:
        ld a,(input_prev)
        cpl
        ld hl,input
        and (hl)
        ld c,a                  ; C = the keys pressed this frame
        and IN_INVUL
        jr z,.ship
        ld hl,invul
        ld a,(hl)
        cpl
        ld (hl),a
.ship:  ld a,c
        and IN_SHIP
        push bc
        call nz,bonus_ship
        pop bc
        ld a,c
        and IN_KILL
        ret z
        call alive_mask
        or a
        ret z                   ; none living
        ld c,a
.r:     call rand               ; a random slot, till one with a living ship (keeps BC, DE)
        and FRONT_MAX-1
        ld e,a
        ld b,a
        inc b
        ld a,c
.bit:   rrca
        djnz .bit
        jr nc,.r
        ld hl,boom_stage
        ld d,0
        add hl,de
        jp ship_dies
        assert FRONT_MAX == 4

; The cheat key 1 (next_wave, no boss on): not in game over (nor attract
; mode: the pseudo-player never presses it), the level's next boss (the
; first of BOSS_AFTER_LIST from this wave on) begins next frame
; (wave_wait 1: next_wave.go, boss_after), this wave's enemies gone, the
; waves before it counted as played (form_enemy, form_cidx, wave_n)
cheat_boss:
        ld a,(over_on)
        or a
        ret nz
        ld a,(form_enemy)
        inc a
        ld c,a                  ; C = this wave (1..)
        ld e,255                ; E = the smallest boss wave >= C
        ld hl,BOSS_AFTERS
        ld b,BOSS_AFTERS_N
.b:     ld a,(hl)
        cp c
        jr c,.nb
        cp e
        jr nc,.nb
        ld e,a
.nb:    inc hl
        djnz .b
        ld a,e
        cp ENEMIES+1
        ret nc                  ; none in this level
        dec a
        ld (form_enemy),a
        sub c
        inc a
        ld b,a                  ; B = the waves skipped
        ld hl,wave_n            ; (stays at 255)
        add a,(hl)
        jr nc,.wn
        ld a,255
.wn:    ld (hl),a
        ld a,(form_cidx)
        inc b
        jr .cs
.c:     inc a
        cp FORM_COLORS_N
        jr c,.cs
        xor a
.cs:    djnz .c
        ld (form_cidx),a
        ld hl,enemies+EN.ST     ; every enemy gone
        ld de,EN
        ld b,ENEMY_N
.e:     ld (hl),EN_GONE
        add hl,de
        djnz .e
        ld a,1
        ld (wave_wait),a
        jp level_text
        endif

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
; this frame's SAT on): Boss2 after BOSS2_AFTER (boss2_begin); Boss1 at
; its left end going right, in its first colour;
; its bullets one every boss_gap px they move: BOSS_EB_N * boss_gap at
; least BOSS_EB_RUN + the longest step - 1, so that the one fired
; BOSS_EB_N before is gone by then (at BOSS_EB_PCT %: eb_speed)
boss_begin:
        ld a,(form_enemy)
        inc a
        cp BOSS2_AFTER
        jp z,boss2_begin
        ld hl,BOSS_PATTERN
        ld (boss_art),hl
        xor a
        ld (boss_kind),a
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
        ld a,(boss_kind)
        or a
        jp nz,boss2_move
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
        jr c,.lref              ; (past column 0: BOSS_X_MIN 0)
        cp BOSS_X_MIN+1
        jr nc,.set
.lref:  neg
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
        ld a,(boss_kind)        ; (Boss2: one of enemy_fire's shooters)
        or a
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
        ld de,(boss_art)        ; (BOSS_PATTERN or BOSS2_PATTERN: the same layout)
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
        ld a,(boss_kind)
        or a
        ret z
        jp b2_colours           ; (Boss2: its bitmap's)
; It starts to boom (in its last colour; the death sound), the front's
; living ships now kept for its bonus (test.tcl: it dies here). Keeps IX.
boss_dies:
        ld a,BS_BOOM
        ld (boss_st),a
        ld a,(boom_frames)
        ld (boss_left),a
        call alive_mask
        ld (boss_alive),a
        call death_start
        ld a,(boss_kind)
        or a
        ret z
; Boss2: its enemies and every bullet gone at once (enemy bullets: this
; frame's eb_move, after the volleys; the volleys: move_bullets, all
; erased by then), its bitmap too (its booms are sprites, as Boss1's)
        ld hl,enemies+EN.ST
        ld de,EN
        ld b,ENEMY_N
.gone:  ld (hl),EN_GONE
        add hl,de
        djnz .gone
        xor a
        ld (b2_desc),a
        inc a
        ld (eb_wipe),a
        ld (b2_vanish),a
        jp b2_erase

; The boss booming: the next boom image when one's frames are over; after
; the last, a frame with nothing (BS_GAP), then its bonus text (its points:
; BOSS_PTS by the front's share, boss_alive) for bonus_frames in the
; screen's middle (not over GAME OVER), printed over two frames (its first
; BONUS_HALF cells, then the rest: one frame's work was too much on the
; Expert); then BS_END (next_wave: the score, the next wave)
boss_booms:
        ld a,(bonus_half)
        or a
        call nz,bonus_rest
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
        cp BS_GAP
        jr z,.gap
        jr nc,.after
        ld e,a
        ld d,0
        ld hl,boom_frames-BS_BOOM
        add hl,de
        ld a,(hl)
        ld (boss_left),a
        ret
.gap:   ld (hl),1               ; (boss_left) its one frame
        ret
.after: cp BS_BONUS
        ret nz                  ; (the bonus's end)
        ld a,(bonus_frames)
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
        ld hl,bonus_buf+BONUS_HALF  ; its first half only (the rest: bonus_rest, next frame)
        ld a,(hl)
        ld (bonus_half),a
        ld (hl),0
        ld hl,bonus_buf
        ld a,BONUS_COL
        ld b,BONUS_HALF         ; (only its cells kept from stars and bullets yet:
        jp mid_show             ; a bullet in the others is erased as usual)

; The bonus text's second half (A = its first character, kept in
; bonus_half), the frame after its first, its cells kept from stars and
; bullets from now on too; not if GAME OVER took its place
bonus_rest:
        ld hl,bonus_buf+BONUS_HALF
        ld (hl),a
        xor a
        ld (bonus_half),a
        ld a,(bonus_text)
        or a
        ret z
        ld hl,bonus_buf+BONUS_HALF
        ld a,BONUS_COL+BONUS_HALF
        ld b,BONUS_LEN-BONUS_HALF
        call mid_show           ; (its stars hidden, the rest printed)
        ld a,BONUS_COL*8        ; all its cells kept from now on
        ld (mid_x0),a
        ld a,BONUS_LEN*8
        ld (mid_w),a
        ret
        assert BS_GAP == BS_BOOM+BOOM_STAGES && BS_BONUS == BS_GAP+1 && BS_END == BS_BONUS+1

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

; ---- Boss2 -----------------------------------------------------------------

; Boss2 begins (boss_begin, after BOSS2_AFTER; every enemy gone): fighting,
; in its first colour, in the bitmap (its stars there off: it covers them);
; under it B2_PAIRS pairs of a random enemy (each pair in a random
; colour), pair k in slot k, the line in its middle going right. The line's
; geometry from the enemy's art: a pair's art W = 8 + its last column - its
; first + 1 px wide, slots W + B2_GAP_X apart, the line's art B2_MARGIN px
; from the screen's left edge at its left end (b2_x0: slot 0's sprite
; column there), b2_range px from it to its right end (as far from the
; right edge); its speed: a line of B2_SWERVE_PAIRS pairs' range (b2_range
; less (B2_SWERVE_PAIRS - B2_PAIRS) slots) in B2_SWERVE_MS; a spawn's way down, from
; B2_DESC_FROM lines above line 0 to the line, in B2_DESC_MS
boss2_begin:
        ld a,BS_FIGHT
        ld (boss_st),a
        ld (boss_kind),a
        ld hl,BOSS2_PATTERN
        ld (boss_art),hl
        ld a,B2_X
        ld (boss_x),a           ; (its booms: boss_sat)
        xor a
        ld (boss_hits),a
        ld (boss_cidx),a
        ld (b2_spawned),a
        ld (b2_desc),a
        ld (b2_dir),a
        ld (b2_acc),a
        ld a,(BOSS_COLORS)
        ld (boss_color),a
.e:     call rand               ; a random enemy
        and 15
        cp ENEMIES
        jr nc,.e
        push af
        call load_enemy
        pop af
        add a,a
        ld l,a
        ld h,0
        ld de,ENEMY_COLS
        add hl,de
        ld e,(hl)               ; its art's first column ...
        inc hl
        ld a,(hl)               ; ... and last
        sub e
        add a,9
        ld d,a                  ; D = a pair's art's width
        add a,B2_GAP_X
        ld (b2_step),a
        ld a,B2_MARGIN
        sub e
        ld (b2_x0),a
        ld a,d
        ld b,B2_PAIRS-1
.w:     add a,d
        djnz .w
        add a,(B2_PAIRS-1)*B2_GAP_X         ; the line's art's width
        neg
        add a,256-2*B2_MARGIN
        ld (b2_range),a
        ld l,a
        srl a
        ld (b2_pos),a           ; in the middle
        ld a,(b2_step)          ; the speed's range: B2_SWERVE_PAIRS pairs'
        ld b,a
        ld a,l
        dup B2_SWERVE_PAIRS-B2_PAIRS
        sub b
        edup
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        dup B2_SW_MUL-1
        add hl,de
        edup
        call rate
        ld a,b
        ld (b2_whole),a
        ld a,d
        ld (b2_frac),a
        ld a,(form_art_t)
        ld b,a
        ld a,B2_LINE_TOP
        sub b
        ld (b2_land),a
        add a,B2_DESC_FROM
        ld (b2_dfull),a
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        dup B2_DESC_MUL-1
        add hl,de
        edup
        call rate
        ld a,b
        ld (b2_dwhole),a
        ld a,d
        ld (b2_dfrac),a
        ld ix,enemies           ; the pairs (the records were all gone; the
        ld b,B2_PAIRS           ; others stay so)
        ld hl,b2_slot
        ld c,0
.p:     push bc
        push hl
        call b2_pair
        pop hl
        pop bc
        ld (hl),c
        inc hl
        inc c
        ld de,2*EN
        add ix,de
        djnz .p
        call b2_place
        ld ix,stars             ; its cells' stars off (not drawn: it covers them)
        ld b,STARS
        ld de,STAR
.s:     ld a,(ix+STAR.Y)
        cp B2_Y+BOSS_H
        jr nc,.sn
        ld a,(ix+STAR.X)
        sub B2_X
        cp BOSS_W
        jr nc,.sn
        ld (ix+STAR.ON),0
.sn:    add ix,de
        djnz .s
        ld a,1
        ld (b2_shown),a
        ld hl,(GRPCGP)          ; its patterns ...
        ld de,BOSS2_PAT
        ld c,0
        call b2_put
; ... and its colours (BOSS2_COL: the body's bytes in boss_color)
b2_colours:
        ld a,(boss_color)
        add a,a
        add a,a
        add a,a
        add a,a
        ld c,a
        ld hl,(GRPCOL)
        ld de,BOSS2_COL
; Its two rows of cells in the VRAM table at HL (GRPCGP or GRPCOL) from DE,
; BOSS_W bytes each, a byte under 10h ORed with C (outside vertical blank:
; over 40 T between writes). Keeps IX.
b2_put:
        push bc
        ld bc,B2_VRAM
        add hl,bc
        pop bc
        ld b,2
.row:   push bc
        push hl
        call vdp_write
        ld b,BOSS_W
.byte:  ld a,(de)
        cp 10h
        jr nc,.out
        or c
.out:   out (VDP_DATA),a
        inc de
        djnz .byte
        pop hl
        inc h                   ; the next row of cells
        pop bc
        djnz .row
        ret
        assert BOSS_H == 16

; Boss2 gone from the bitmap (it died): its cells blank, in the playfield's
; colour (a bullet's), stars and bullets in them again. Keeps IX.
b2_erase:
        xor a
        ld (b2_shown),a
        ld hl,(GRPCGP)
        call .fill
        ld hl,(GRPCOL)
        ld a,BULLET_COLOR*16+BG_COLOR
.fill:  ld e,a
        ld bc,B2_VRAM
        add hl,bc
        ld d,2
.row:   push hl
        call vdp_write
        ld b,BOSS_W
.byte:  ld a,e                  ; 32 T
        out (VDP_DATA),a
        nop
        djnz .byte
        pop hl
        inc h
        dec d
        jr nz,.row
        ret

; The record pair at IX: a pair (EN_FORM, no fractions), in a random colour
; of FORM_COLORS
b2_pair:
        xor a
        ld (ix+EN.ST),a
        ld (ix+EN+EN.ST),a
        ld (ix+EN.XF),a
        ld (ix+EN+EN.XF),a
        ld (ix+EN.YF),a
        ld (ix+EN+EN.YF),a
.c:     call rand
        and 15
        cp FORM_COLORS_N
        jr nc,.c
        ld hl,FORM_COLORS
        add a,l
        ld l,a
        jr nc,.nc
        inc h
.nc:    ld a,(hl)
        ld (ix+EN.COL),a
        ld (ix+EN+EN.COL),a
        ret
        assert EN_FORM == 0

; B = HL px/s / fps, D = the remainder (bresenham's whole px and remainder
; a frame for HL px/s; both under 256)
rate:   ld a,(fps)
        ld e,a
        ld d,0
        ld b,-1
.d:     inc b
        or a
        sbc hl,de
        jr nc,.d
        add hl,de
        ld d,l
        ret

; Boss2 one frame on (next_wave, fighting): a spawn coming down moves on
; (shot, broken up: its way down is over), the line standing still;
; else the line swerves (B2_SW_MUL * b2_range px/s, back the other way from
; either end, a step past it reflected), and with B2_SPAWN_AT living
; enemies or fewer and spawns left, a new pair (b2_spawn); then the pairs
; at their places
boss2_move:
        ld a,(b2_desc)
        or a
        jr z,.swerve
        dec a                   ; its record pair's state
        ld l,a
        add a,a
        add a,a
        add a,a
        add a,l
        add a,a                 ; * 2*EN
        ld l,a
        ld h,0
        ld de,enemies
        add hl,de
        ld a,(hl)
        or a
        jr nz,.over             ; broken up
        ld a,(b2_dwhole)
        ld b,a
        ld a,(b2_dfrac)
        ld d,a
        ld hl,b2_dacc
        call bresenham
        ld b,a
        ld hl,b2_drem
        ld a,(hl)
        sub b
        jr c,.land
        ld (hl),a
        jr nz,b2_place          ; still coming
.land:  ld (hl),0
.over:  xor a
        ld (b2_desc),a
        jr b2_place
.swerve:
        ld a,(b2_whole)
        ld b,a
        ld a,(b2_frac)
        ld d,a
        ld hl,b2_acc
        call bresenham
        ld b,a
        ld a,(b2_range)
        ld c,a
        ld hl,b2_pos
        ld a,(b2_dir)
        or a
        ld a,(hl)
        jr nz,.left
        add a,b                 ; (no carry: the range + a step < 256)
        sub c                   ; past the right end by this
        jr c,.inr
        ld e,a
        ld a,c
        sub e                   ; reflected
        ld (hl),a
        ld a,1
        ld (b2_dir),a
        jr .spawn
.inr:   add a,c
        ld (hl),a
        jr .spawn
.left:  sub b
        jr z,.lend
        jr nc,.inl
        neg                     ; past the left end: reflected
.lend:  ld (hl),a
        xor a
        ld (b2_dir),a
        jr .spawn
.inl:   ld (hl),a
.spawn: ld a,(b2_spawned)
        cp B2_SPAWNS
        jr nc,b2_place
        ld hl,enemies+EN.ST     ; the living enemies
        ld de,EN
        ld bc,ENEMY_N*256
.cnt:   ld a,(hl)
        cp EN_BOOM
        jr nc,.nl
        inc c
.nl:    add hl,de
        djnz .cnt
        ld a,c
        cp B2_SPAWN_AT+1
        call c,b2_spawn
; The pairs (EN_FORM) at their slots' places in the line, the spawn
; coming down at its line
b2_place:
        ld ix,enemies
        ld c,0
.p:     ld a,(ix+EN.ST)
        or a
        jr nz,.next
        ld a,c                  ; its slot
        add a,low b2_slot
        ld l,a
        ld h,high b2_slot
        ld b,(hl)
        ld a,(b2_step)
        ld d,a
        ld a,(b2_x0)
        ld hl,b2_pos
        add a,(hl)
        inc b
.m:     dec b
        jr z,.x
        add a,d
        jr .m
.x:     ld (ix+EN.X),a
        ld (ix+EN.X+1),0
        add a,8
        ld (ix+EN+EN.X),a
        ld (ix+EN+EN.X+1),0
        ld a,(b2_desc)
        dec a
        cp c
        ld a,(b2_land)
        jr nz,.y
        ld hl,b2_drem           ; coming down: this much above the line
        sub (hl)
.y:     ld (ix+EN.Y),a
        ld (ix+EN+EN.Y),a
.next:  ld de,2*EN
        add ix,de
        inc c
        ld a,c
        cp B2_PAIRS
        jr c,.p
        ret
        assert b2_slot/256 == (b2_slot+FORM_PAIRS_N-1)/256 && FORM_PAIRS_N*4 < 256

; A spawn (boss2_move: B2_SPAWN_AT living enemies or fewer): a record pair
; with both gone (none, but two with one gone each: the other's enemy
; moved into the first's gone record, the other's then both gone; none of
; those yet, enemies still booming: nothing, till a later frame) becomes a
; pair in a random colour in a random free slot of the line, coming down
; from B2_DESC_FROM lines above line 0
b2_spawn:
        ld hl,0
        ld (b2_half),hl
        ld ix,enemies
        ld c,0
.k:     ld a,(ix+EN+EN.ST)
        ld b,a
        ld a,(ix+EN.ST)
        cp EN_GONE
        jr nz,.lin
        ld a,b                  ; the left one gone
        cp EN_GONE
        jr z,.found             ; ... both
        push ix
        pop hl
        jr .half
.lin:   ld a,b
        cp EN_GONE
        jr nz,.next             ; neither
        push ix                 ; the right one gone
        pop hl
        ld de,EN
        add hl,de
.half:  ld de,(b2_half)
        ld a,d
        or e
        jr nz,.move
        ld (b2_half),hl         ; the first such pair
        jr .next
.move:  push ix                 ; this pair's living one (free or booming)
        pop hl                  ; into the first's gone record
        ld a,(ix+EN.ST)
        cp EN_GONE
        jr nz,.lv
        ld de,EN
        add hl,de
.lv:    push bc
        ld de,(b2_half)
        ld bc,EN
        ldir
        ld de,-EN
        add hl,de
        ld (hl),EN_GONE         ; (EN.ST) this pair now both gone
        pop bc
        jr .found
.next:  ld de,2*EN
        add ix,de
        inc c
        ld a,c
        cp B2_PAIRS
        jr c,.k
        ret                     ; none yet
.found: ld hl,b2_slot           ; IX, C: the record pair. E = the line's
        ld iy,enemies           ; slots taken (bit k: slot k)
        ld b,B2_PAIRS
        ld e,0
.tk:    ld a,(iy+EN.ST)
        or a
        jr nz,.tn               ; not a pair
        push bc
        ld b,(hl)
        ld a,1
        inc b
.tb:    dec b
        jr z,.tset
        add a,a
        jr .tb
.tset:  or e
        ld e,a
        pop bc
.tn:    inc hl
        push de
        ld de,2*EN
        add iy,de
        pop de
        djnz .tk
.slot:  call rand               ; a free one, at random (keeps BC, DE)
        and 3
        cp B2_PAIRS
        jr nc,.slot
        ld d,a
        ld b,a
        inc b
        ld a,e
.sb:    rrca
        djnz .sb                ; (carry: slot D's bit)
        jr c,.slot              ; taken
        ld a,c
        add a,low b2_slot
        ld l,a
        ld h,high b2_slot
        ld (hl),d
        call b2_pair
        ld a,c
        inc a
        ld (b2_desc),a
        ld a,(b2_dfull)
        ld (b2_drem),a
        xor a
        ld (b2_dacc),a
        ld hl,b2_spawned
        inc (hl)
        ret
        assert B2_PAIRS <= 4 && B2_SPAWN_AT < 2*B2_PAIRS   ; (a slot free then)

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
        ld hl,lw_text           ; only the cells that changed (lw_shown)
        ld de,LW_ROW*256+LW_COL*8
        ld ix,lw_shown
        ld b,LW_LEN
.cell:  ld a,(hl)
        or a
        jr nz,.ch
        ld a,' '                ; past its end: blank
        dec hl                  ; (stays on the 0)
.ch:    inc hl
        cp (ix+0)
        jr z,.same
        ld (ix+0),a
        push bc
        push hl
        ld (lw_cell),a
        ld hl,lw_cell
        ld c,TEXT_COLOR*16+BG_COLOR
        call print_text         ; (DE: the next cell)
        pop hl
        pop bc
        jr .next
.same:  ld a,e
        add a,8
        ld e,a
.next:  inc ix
        djnz .cell
        ret
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
        call bcd8
        ld hl,score_digits
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

; An 8-digit BCD number (4 bytes, HL = its highest) as 8 characters at
; DE, right-aligned, no leading zeros (0: "0"); DE past them
bcd8:
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
        jr nz,.end
        ld a,'0'                ; 0: one digit
        ld (de),a
.end:   inc de
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

; Carry: pixel (D, E)'s bitmap byte is kept from stars and bullets: in
; Boss2's cells while it shows (b2_shown), or a text shows in the screen's
; middle (mid_text: GAME OVER or the boss's bonus) and it's in its cells.
; Keeps BC, DE, HL.
over_at:
        ld a,(b2_shown)
        or a
        jr z,.mid
        ld a,e
        cp B2_Y+BOSS_H
        jr nc,.mid
        ld a,d
        sub B2_X
        cp BOSS_W
        ret c
.mid:   ld a,(mid_text)
        or a
        ret z
; ... the middle text's, with one showing
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
; cells kept from stars and bullets from now on (a star in them now: gone
; from the bitmap, not drawn any more; the text may cover fewer cells
; than B, its other cells left blank)
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
        jr nc,.sn
        ld a,(ix+STAR.ON)
        or a
        jr z,.sn
        ld (ix+STAR.ON),0       ; shown: its byte blank (no bullet in a star's byte)
        ld a,(pat_hi)
        call vdp_at
        xor a
        out (VDP_DATA),a
        ld a,(col_hi)
        call vdp_at
        ld a,BULLET_COLOR*16+BG_COLOR
        out (VDP_DATA),a
.sn:    pop de
        ld de,STAR
        add ix,de
        djnz .s
        pop de
        pop hl
        ld c,0                  ; patterns only: the playfield's colour bytes
        jp print_text           ; are the text's (but a star's: gone now)
        assert OVER_COL > 0 && BONUS_COL > 0 && TEXT_COLOR == BULLET_COLOR

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
        ld b,BONUS_LEN
        ld hl,bonus_half
        cp (hl)
        jr z,.all
        ld (hl),a               ; its second half not printed yet: only the
        ld b,BONUS_HALF         ; first (the others aren't the text's)
.all:   ld de,OVER_ROW*256+BONUS_COL*8
        ld c,0                  ; (patterns only, as mid_show)
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
        ld a,(invul)
        or a
        ld a,SHIP_COLOR
        jr z,.sc
        ld a,INVUL_COLOR
.sc:    ld (ship_col),a
        ld hl,sat_buf
        ld ix,boom_stage
        ld a,(front_mask)
        ld d,a
        ld a,(ship_x)
        ld e,a                  ; this slot's art's left column
        ld b,FRONT_MAX
.slot:  ld a,(ship_col)
        ld c,a
        rr d
        jr nc,.park
        ld (hl),SHIP_TOP-1      ; a sprite's first line is Y + 1
        inc hl
        ld a,e
        sub SHIP_ART_L
        jr nc,.x
        add a,32                ; left of 0: the early clock
        set 7,c                 ; (SPR_EC)
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
        ld a,(invul)
        or a
        ld c,COMING_COLOR
        jr z,.cc
        ld c,INVUL_COLOR
.cc:    ld a,l
        bit 7,h
        jr z,.cx
        add a,32                ; left of 0 (down to -16): the early clock
        set 7,c                 ; (SPR_EC)
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
        cp BS_GAP-BS_FIGHT      ; (fighting or booming)
        jr nc,.pairs
        or a
        jr nz,.boss             ; booming (Boss2's booms too)
        ld a,(boss_kind)
        or a
        jr nz,.pairs            ; Boss2 fighting: in the bitmap, its enemies here
.boss:  call boss_sat
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
; enemy IX's line, in its colour
ent_at: ld a,(ix+EN.Y)
        dec a                   ; a sprite's first line is Y + 1
        ld (de),a
        inc de
        ld a,(ix+EN.COL)
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
; (the rest of RESERVE_CELLS blank): their patterns (made once, at power-on,
; in RES_PICS), straight to the VDP (40 T between the VRAM writes: outside
; vertical blank too); their colour is set once, at the game's start
draw_reserves:
        ld l,a
        ld h,0
        ld de,RES_PIC
        call mul_hl_de          ; HL = A * RES_PIC
        ld de,RES_PICS
        add hl,de
        ld a,(pat_hi)
        or RESERVE_VRAM>>8
        ld d,a
        di
        xor a                   ; (RESERVE_VRAM's low byte)
        out (VDP_ADDR),a
        ld a,d
        out (VDP_ADDR),a
        ei
        ld b,RES_PIC
.out:   ld a,(hl)               ; 40 T a byte
        out (VDP_DATA),a
        inc hl
        dec b
        jr nz,.out
        ret

; HL *= DE (small numbers)
mul_hl_de:
        ld b,l
        ld hl,0
        inc b
        jr .m
.a:     add hl,de
.m:     djnz .a
        ret

; RES_PICS: draw_reserves' patterns for 0..RESERVE_MAX ships, made once
make_reserves:
        ld de,RES_PICS
        xor a
.n:     push af
        push de
        call build_reserves
        pop de
        ld hl,reserve_buf
        ld bc,RES_PIC
        ldir
        pop af
        inc a
        cp RESERVE_MAX+1
        jr c,.n
        ret

; reserve_buf := A (0..RESERVE_MAX) reserve ships' cells' patterns
build_reserves:
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
.show:  ret
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

; ---- High scores -----------------------------------------------------------

; One frame of a blink (blink_on frames shown, then blink_off hidden): NZ,
; no change; Z, it turned: blink_shown nonzero if shown now, C = the
; text's colour byte then (white, or all black)
blink_tick:
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
        xor a
        ret

; Text HL from cell DE on, in colour C, its leading blanks not printed
; (the picture under them stays)
print_lead:
        ld a,(hl)
        cp ' '
        jp nz,print_text
        inc hl
        ld a,e
        add a,8
        ld e,a
        jr print_lead

; The title's best score: "HI SCORE" on HISC_ROW and the table's first
; score on the row under it, both right-justified, white
show_hi:
        ld hl,HISC_TEXT
        ld de,HISC_ROW*256+(32-HISC_LEN)*8
        ld c,TEXT_COLOR*16+BG_COLOR
        call print_text
        ld hl,hi_table+3
        ld de,egg_buf
        call bcd8
        xor a
        ld (de),a
        ld hl,egg_buf
        ld de,(HISC_ROW+1)*256+(32-8)*8
        ld c,TEXT_COLOR*16+BG_COLOR
        jr print_lead

; The title's time over: the high score list for list_frames in place of
; the picture (the top status row stays); the egg, if up, gone
show_list:
        ld hl,(list_frames)
        ld (list_left),hl
        ld hl,0
        ld (egg_left),hl
        call display_off
        call clear_below
        ld hl,HI_HEAD
        ld de,HI_ROW*256+(32-HI_HEAD_LEN)/2*8
        call draw_list
        jp display_on

; Heading HL on cell DE, then the table's lines under it
draw_list:
        ld c,TEXT_COLOR*16+BG_COLOR
        call print_text
        xor a
.row:   push af
        call hi_row
        pop af
        inc a
        cp HI_COUNT
        jr c,.row
        ret

; A = a rank: its line of the list, " 1. LTR     5000" (the rank, the
; initials, the score right-aligned), on row HI_LIST_ROW + A from column
; HI_COL, white
hi_row:
        call hi_line
; ... egg_buf at cell DE
hi_print:
        ld hl,egg_buf
        ld c,TEXT_COLOR*16+BG_COLOR
        jp print_text
; ... the line in egg_buf (0-terminated); DE = its first cell
hi_line:
        push af
        call hi_rec
        push hl
        inc hl
        inc hl
        inc hl
        ld de,egg_buf+HI_ROW_LEN-8
        call bcd8
        xor a
        ld (de),a
        pop hl
        ld de,HI_NAME
        add hl,de
        ld de,egg_buf+4
        ld bc,3
        ldir
        ld hl,'.'+' '*256
        ld (egg_buf+2),hl
        ld a,' '
        ld (egg_buf+7),a
        pop af
        push af
        inc a                   ; 1..HI_COUNT
        ld c,' '
        cp 10
        jr c,.one
        ld c,'1'
        sub 10
.one:   add a,'0'
        ld b,a
        ld (egg_buf),bc         ; (C, then B)
        pop af
        add a,HI_LIST_ROW
        ld d,a
        ld e,HI_COL*8
        ret
        assert HI_COUNT < 20 && HI_ROW_LEN == 16 && HI_NAME == 4 && HI_LIST_ROW+HI_COUNT <= 24

; HL = hi_table's record A. Keeps A.
hi_rec:
        ld l,a
        add a,a
        add a,a
        add a,a
        sub l                   ; 7 * A
        ld e,a
        ld d,0
        ld a,l
        ld hl,hi_table
        add hl,de
        ret
        assert HI_SIZE == 7 && HI_COUNT*HI_SIZE < 256

; A = the score's rank in the table (0 the best; HI_COUNT: it beats none),
; HL = that record: the first whose score is under it (a tie: under the
; older score)
hi_rank:
        ld hl,hi_table
        ld b,0
.rec:   push hl
        inc hl
        inc hl
        inc hl
        ld de,score+3
        ld c,4
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.diff
        dec hl
        dec de
        dec c
        jr nz,.cmp
        jr .next                ; a tie: under it
.diff:  jr nc,.found            ; above it
.next:  pop hl
        ld de,HI_SIZE
        add hl,de
        inc b
        ld a,b
        cp HI_COUNT
        jr c,.rec
        ret
.found: pop hl
        ld a,b
        ret

; Game over's end (display off, no sprites): if the score beats a record,
; it goes in the table there (the ones under it a place down, the last
; gone), and its initials are entered
hi_enter:
        call hi_rank
        cp HI_COUNT
        ret nc
        ld (ent_rec),hl
        ld (ent_row),a
        ld b,a
        ld a,HI_COUNT-1
        sub b                   ; records to move down
        jr z,.put
        ld c,a
        add a,a
        add a,a
        add a,a
        sub c                   ; their bytes
        ld c,a
        ld b,0
        ld hl,hi_table+(HI_COUNT-1)*HI_SIZE-1
        ld de,hi_table+HI_COUNT*HI_SIZE-1
        lddr
.put:   ld de,(ent_rec)
        ld hl,score
        ld bc,4
        ldir
        ld a,'_'
        ld b,3
.name:  ld (de),a
        inc de
        djnz .name
        ; fall through

; The new record's initials (ent_rec, rank ent_row), on the list under
; "ENTER YOUR INITIALS" (the top status row stays): a letter typed (A..Z)
; goes in its slot, BS (or down) takes the last one back; or left / right
; (the arrows or either joystick; held, it repeats) picks a letter, and
; space or either joystick's button takes it. The letter picked blinks in
; its slot; after a third typed, a blinking cursor in a fourth place.
; RETURN (or up) ends it once there's a letter (the slots left empty
; become spaces); the third taken by space or a button ends it too. Up
; and down count straight only. What's held as it begins counts once
; released. Then the list stays for done_frames (the disk version saves
; the table meanwhile), and the display goes off.
enter_initials:
        call clear_below
        ld hl,ENTRY_HEAD
        ld de,HI_ROW*256+(32-ENTRY_HEAD_LEN)/2*8
        call draw_list
        call display_on
        call poll_inputs        ; (what's held now: not a press)
        call ent_dirs
        ld (ent_held),a
        and IN_LEFT|IN_RIGHT
        ld (ent_lr),a
        xor a
        ld (ent_count),a        ; (held from the start: no repeat)
        ld (ent_pos),a
        ld (ent_letter),a       ; none picked yet
        call new_letter
.frame: halt
        call blink_tick
        call z,show_entry
        call poll_inputs
        call ent_key
        or a
        jr z,.trig
        cp 8
        jr z,.bs
        cp 13
        jr z,.enter
        ld c,a
        ld a,(ent_pos)
        cp 3
        jr nc,.frame            ; all three in: only BS or RETURN
        ld a,c
        call put_letter
        jr .frame
.bs:    ld a,(ent_pos)
        or a
        jr z,.frame
        cp 3
        jr nc,.bs3
        call ent_slot
        ld (hl),'_'
.bs3:   dec a
        ld (ent_pos),a
        call ent_slot
        ld a,(hl)               ; the letter taken back: picked
        ld (ent_letter),a
        call new_letter         ; (the cursor gone too)
        jr .frame
.enter: ld a,(ent_pos)
        or a
        jr z,.frame             ; no letter yet
.blank: cp 3
        jr nc,.shown
        call ent_slot
        ld (hl),' '
        inc a
        ld (ent_pos),a
        jr .blank
.shown: ld a,(ent_row)
        call hi_row
        jp .done
.trig:  call ent_dirs
        ld hl,ent_held
        ld b,(hl)
        ld (hl),a
        ld c,a                  ; held now
        ld a,b
        cpl
        and c
        ld e,a                  ; just pressed
        and ENT_TRIG
        jr z,.updown
        ld a,(ent_pos)
        cp 3
        jr nc,.updown
        ld a,(ent_letter)
        or a
        jr z,.updown            ; none picked yet
        call put_letter
        ld a,(ent_pos)
        cp 3
        jr z,.enter             ; the third taken by a button: done
        jp .frame
.updown:
        bit 0,e                 ; ENT_UP
        jr nz,.enter
        bit 1,e                 ; ENT_DOWN
        jr nz,.bs
        ld a,c
        and IN_LEFT|IN_RIGHT
        ld hl,ent_lr
        cp (hl)
        ld (hl),a
        jr nz,.turn
        ld hl,ent_count
        ld a,(hl)
        or a
        jp z,.frame             ; held from the start: no repeat
        dec (hl)
        jp nz,.frame
        ld a,(rep_frames)
        ld (hl),a
        jr .step
.turn:  ld a,(rep_delay)
        ld (ent_count),a
.step:  ld a,(ent_pos)
        cp 3
        jp nc,.frame            ; no letter to pick
        ld a,(ent_lr)
        ld hl,ent_letter
        cp IN_RIGHT
        jr z,.right
        cp IN_LEFT
        jp nz,.frame            ; neither, or both
        ld a,(hl)
        cp 'A'+1                ; A or none: to Z
        jr nc,.left
        ld a,'Z'+1
.left:  dec a
        jr .set
.right: ld a,(hl)
        inc a
        cp 'Z'+1
        jr nc,.wrap             ; past Z: to A
        cp 'A'
        jr nc,.set
.wrap:  ld a,'A'                ; none: A
.set:   ld (hl),a
        call new_letter
        jp .frame
.done:
        ifdef BIN
        call hsc_save           ; (the list shows meanwhile)
        endif
        ld a,(done_frames)
        ld b,a
.hold:  halt
        djnz .hold
        jp display_off
        assert ENT_UP == 1 && ENT_DOWN == 2

; Letter A taken into slot ent_pos; the next slot, with none picked (after
; the third: the cursor)
put_letter:
        call ent_slot
        ld (hl),a
        ld hl,ent_pos
        inc (hl)
        xor a
        ld (ent_letter),a
        ; fall through
; A new letter picked (or a new slot): shown at once, then blinking
new_letter:
        ld a,(blink_on)
        ld (blink_left),a
        ld a,1
        ld (blink_shown),a
        ; fall through
; Slot ent_pos shows ent_letter ("_" if none is picked), or nothing in the
; blink's hidden phase; after the third letter, the cursor "_" in a fourth
; place, blinking
show_entry:
        ld a,(ent_pos)
        cp 3
        jr nc,.cursor
        ld a,(ent_letter)
        or a
        jr nz,.letter
        ld a,'_'
.letter:
        ld c,a
        ld a,(blink_shown)
        or a
        ld a,' '
        jr z,.put
        ld a,c
.put:   call ent_slot
        ld (hl),a
        ld a,(ent_row)
        jp hi_row
.cursor:
        ld a,(ent_row)
        call hi_line
        ld a,(blink_shown)
        or a
        ld a,' '
        jr z,.c
        ld a,'_'
.c:     ld (egg_buf+HI_NAME+3),a
        jp hi_print

; HL = slot ent_pos of the new record's initials. Keeps AF.
ent_slot:
        push af
        ld hl,(ent_rec)
        ld a,(ent_pos)
        add a,HI_NAME
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        pop af
        ret

; A = a key just pressed (down at the last poll, up at the one before):
; 'A'..'Z', 8 (BS) or 13 (RETURN), else 0; the first found
ent_key:
        ld ix,key_state+2
        ld c,'A'-6              ; row 2 bit 0's letter (row 2: only A and B, bits 6 and 7)
        ld b,4                  ; rows 2..5
        ld a,0C0h
.row:   ld e,a                  ; the row's letter bits
        ld a,(ix+0)
        cpl
        and (ix+KEY_ROWS+2)
        and e
        jr nz,.bit
        inc ix
        ld a,c
        add a,8
        ld c,a
        ld a,0FFh
        djnz .row
        ld a,(key_state+7)      ; row 7: BS bit 5, RETURN bit 7
        cpl
        ld hl,key_prev+7
        and (hl)
        ld c,8
        bit 5,a
        jr nz,.ret
        ld c,13
        rla
        jr c,.ret
        xor a
        ret
.bit:   rra
        jr c,.ret
        inc c
        jr .bit
.ret:   ld a,c
        ret

; A = held at the last poll: ENT_UP, ENT_DOWN (straight: neither left nor
; right held), IN_LEFT, IN_RIGHT (the arrows, either joystick), ENT_TRIG
; (space, either joystick's button A or B)
ent_dirs:
        ld hl,key_state+KEY_ROWS
        ld a,(hl)
        inc hl
        and (hl)                ; (0: held, on either)
        cpl
        ld c,a                  ; bits 0..3 up, down, left, right; 4, 5 buttons A, B
        and 20h
        jr z,.nb
        set 4,c
.nb:    ld a,(key_state+KEY_ROW)
        cpl
        ld b,a                  ; bit 0 space, 4 left, 5 up, 6 down, 7 right
        rra
        jr nc,.ns
        set 4,c
.ns:    bit 4,b
        jr z,$+4
        set 2,c
        bit 5,b
        jr z,$+4
        set 0,c
        bit 6,b
        jr z,$+4
        set 1,c
        bit 7,b
        jr z,$+4
        set 3,c
        ld a,c
        and 0Ch
        ld a,c
        jr nz,.side
        and 1Fh
        ret
.side:  and 1Ch                 ; left or right held: no up, no down
        ret
        assert IN_LEFT == 04h && IN_RIGHT == 08h && ENT_TRIG == 10h
        assert KEY_ROW == 8 && KEY_SPACE == 01h && KEY_LEFT == 10h && KEY_RIGHT == 80h

        ifdef BIN
; The disk version: hi_table lives in TERRAFNT.HSC (U-boat Killer's way).
; Disk errors are silently ignored: the disk ROM's error handler (DISKVE)
; picks Abort, and the abort lands in disk_abort, which fails the call:
; through BREAKV under DOS 2, through DOS1_ABORT under DOS 1. The pointers
; and the handler sit in page 3, as the disk ROM holds page 1 meanwhile.

; At power-on, after HI_DEFAULTS: the file's table, if there's a disk ROM
; and the file is sound (its size, its check byte, hsc_check)
hsc_load:
        xor a
        ld (has_disk),a
        ld a,(H_PHYD)
        cp 0C9h
        ret z                   ; no disk ROM
        ld (has_disk),a
        ld hl,020Eh             ; ld c,2 / ret
        ld (disk_err_stub),hl
        ld a,0C9h
        ld (disk_err_stub+2),a
        ld hl,disk_err_stub
        ld (disk_err_vec),hl
        ld hl,disk_abort
        ld (disk_abort_vec),hl
        ld hl,disk_err_vec      ; the game never returns to BASIC,
        ld (DISKVE),hl          ; so these stay
        ld hl,disk_abort_vec
        ld (BREAKV),hl
        ld b,0
        ld c,F_DOSVER
        call bdos
        ld a,b
        cp 2
        jr nc,.dos2
        ld hl,disk_abort
        ld (DOS1_ABORT),hl
.dos2:  ld c,F_OPEN
        call hsc_open
        or a
        ret nz                  ; none (or a disk error)
        ld hl,(hsc_fcb+FCB_FILESIZE+2)
        ld a,h
        or l
        ret nz
        ld hl,(hsc_fcb+FCB_FILESIZE)
        ld de,HSC_SIZE
        sbc hl,de               ; (carry clear: or l)
        ret nz
        ld c,F_RDBLK
        call hsc_block
        or a
        ret nz
        call hsc_xor
        call hsc_sum
        ld hl,hsc_buf+HSC_SIZE-1
        cp (hl)
        ret nz
        call hsc_check
        ret nz
        ld hl,hsc_buf
        ld de,hi_table
        ld bc,HI_COUNT*HI_SIZE
        ldir
        ret

; Z: hsc_buf's table is sound: BCD digits, initials A..Z or spaces, each
; score at most the one above it
hsc_check:
        ld hl,hsc_buf
        ld c,HI_COUNT
.rec:   ld b,4
.dig:   ld a,(hl)
        and 0Fh
        cp 10
        jr nc,.bad
        ld a,(hl)
        cp 0A0h
        jr nc,.bad
        inc hl
        djnz .dig
        ld b,3
.let:   ld a,(hl)
        inc hl
        cp ' '
        jr z,.sp
        sub 'A'
        cp 'Z'-'A'+1
        jr nc,.bad
.sp:    djnz .let
        dec c
        jr nz,.rec
        ld hl,hsc_buf+HI_SIZE+3 ; record 1's highest byte
        ld c,HI_COUNT-1
.ord:   push hl
        ld a,l                  ; DE = the one above's
        sub HI_SIZE
        ld e,a
        ld a,h
        sbc a,0
        ld d,a
        ld b,4
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.ne
        dec hl
        dec de
        djnz .cmp
.ne:    pop hl
        jr c,.bad               ; the one above is lower
        ld de,HI_SIZE
        add hl,de
        dec c
        jr nz,.ord
        xor a
        ret
.bad:   or 1
        ret

; hi_table to the file, if there's a disk ROM
hsc_save:
        ld a,(has_disk)
        or a
        ret z
        ld hl,hi_table
        ld de,hsc_buf
        ld bc,HI_COUNT*HI_SIZE
        ldir
        call hsc_sum
        ld (hsc_buf+HSC_SIZE-1),a
        call hsc_xor
        ld c,F_CREATE
        call hsc_open
        or a
        ret nz
        ld c,F_WRBLK
        call hsc_block
        ld c,F_CLOSE            ; even if the write failed
        ld de,hsc_fcb
        jr bdos

; C = F_OPEN or F_CREATE: on a fresh FCB for the file, default drive; if
; it works (A = 0), 1-byte records from the start of the file
hsc_open:
        ld hl,hsc_fcb
        ld de,hsc_fcb+1
        push bc
        ld bc,FCB_LEN-1
        ld (hl),0
        ldir
        ld hl,HSC_NAME
        ld de,hsc_fcb+1
        ld bc,11
        ldir
        pop bc
        ld de,hsc_fcb
        call bdos
        or a
        ret nz
        ld hl,1
        ld (hsc_fcb+FCB_RECSIZE),hl
        dec l
        ld (hsc_fcb+FCB_RANDOM),hl
        ld (hsc_fcb+FCB_RANDOM+2),hl
        ret

; C = F_RDBLK or F_WRBLK: the whole file, to / from hsc_buf -> A = 0 if done
hsc_block:
        push bc
        ld de,hsc_buf
        ld c,F_SETDTA
        call bdos
        pop bc
        ld de,hsc_fcb
        ld hl,HSC_SIZE
        ; fall through

; C = the function, DE, HL: a BDOS call -> A, B, HL (A = FFh if a disk
; error aborted it). The disk ROM runs with IM 1 (the BIOS's interrupt
; handler, as under Disk BASIC: its timers, the motor's count), then IM 2
; again, and disk_timer calls H.TIMI for DISK_HOOK_SECS more (the drive
; motor goes off). Returns with interrupts enabled.
bdos:
        push ix
        push iy
        ld (disk_sp),sp
        im 1
        call BDOS
.back:  di
        im 2
        push af
        push hl
        call hook_arm
        pop hl
        pop af
        ei
        pop iy
        pop ix
        ret

; The abort vector: back to bdos's caller with A = FFh
disk_abort:
        ld sp,(disk_sp)
        ld a,0FFh
        jr bdos.back

; A = hsc_buf's check byte: HSC_KEY plus the table's bytes
hsc_sum:
        ld hl,hsc_buf
        ld b,HI_COUNT*HI_SIZE
        ld a,HSC_KEY
.add:   add a,(hl)
        inc hl
        djnz .add
        ret

; hsc_buf XORed with HSC_XOR + HSC_XOR_STEP * index (both ways)
hsc_xor:
        ld hl,hsc_buf
        ld b,HSC_SIZE
        ld a,HSC_XOR
.byte:  ld c,a
        xor (hl)
        ld (hl),a
        inc hl
        ld a,c
        add a,HSC_XOR_STEP
        djnz .byte
        ret
        endif

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
                dw EGG_SECS*60
                dw HI_LIST_MS*60/1000
                db HI_REPEAT_DELAY_MS*60/1000, HI_REPEAT_MS*60/1000, HI_DONE_MS*60/1000
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
                dw EGG_SECS*50
                dw HI_LIST_MS*50/1000
                db HI_REPEAT_DELAY_MS*50/1000, HI_REPEAT_MS*50/1000, HI_DONE_MS*50/1000
        assert RATES_50-RATES_60 == RATES_SIZE && BOOM_STAGES == 3
        assert HI_LIST_MS*60%1000 == 0 && HI_LIST_MS*50%1000 == 0 && HI_LIST_MS*50/1000 > 0
        assert HI_REPEAT_DELAY_MS*60%1000 == 0 && HI_REPEAT_DELAY_MS*50%1000 == 0 && HI_REPEAT_DELAY_MS*60/1000 < 256 && HI_REPEAT_DELAY_MS*50/1000 > 0
        assert HI_REPEAT_MS*60%1000 == 0 && HI_REPEAT_MS*50%1000 == 0 && HI_REPEAT_MS*60/1000 < 256 && HI_REPEAT_MS*50/1000 > 0
        assert HI_DONE_MS*60%1000 == 0 && HI_DONE_MS*50%1000 == 0 && HI_DONE_MS*60/1000 < 256 && HI_DONE_MS*50/1000 > 0
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
; The high score table at power-on (the user's): score, initials
        macro HI_REC val, name
        assert (val) > 0 && (val) < 100000000
        db ((val)/10%10)*16+(val)%10, ((val)/1000%10)*16+(val)/100%10
        db ((val)/100000%10)*16+(val)/10000%10, ((val)/10000000%10)*16+(val)/1000000%10
        db name
        endm
HI_DEFAULTS:    HI_REC 5000, "LTR"
                HI_REC 4800, "EHE"
                HI_REC 4500, "TEN"
                HI_REC 4000, "SAA"
                HI_REC 3500, "ALZ"
                HI_REC 3000, "SII"
                HI_REC 2500, "SES"
                HI_REC 2000, "UNT"
                HI_REC 1500, "MSO"
                HI_REC 1000, "EAO"
        assert $-HI_DEFAULTS == HI_COUNT*HI_SIZE
HI_HEAD:        db "HIGH SCORES",0
HI_HEAD_LEN     equ $-HI_HEAD-1
ENTRY_HEAD:     db "ENTER YOUR INITIALS",0
ENTRY_HEAD_LEN  equ $-ENTRY_HEAD-1
HISC_TEXT:      db "HI SCORE",0
HISC_LEN        equ $-HISC_TEXT-1
        assert HISC_LEN >= 8    ; (the score right-justified under it)
        ifdef BIN
HSC_NAME:       db "TERRAFNTHSC"
        endif
; The egg's version label, then its texts (egg_line: a length, then the
; text, egg_text-encoded), ending with a 0
EGG_LABEL:      db "VERSION "
EGG_LABEL_LEN   equ $-EGG_LABEL
EGG_TEXTS:
                lua allpass
                egg_line("JCCYC IS")
                egg_line("JUAN CARLOS CASTRO Y CASTRO")
                egg_line("WELCOME TO THE FRONT!")
                egg_end()
                endlua
                db 0
        assert EGG_LABEL_LEN+3+1+3+1+5 <= 32    ; "VERSION 255.255.65535"
        assert EGG_ROW+1+EGG_TEXT_LINES <= 24
        assert CREDIT_ROW >= EGG_ROW && URL_ROW >= EGG_ROW && BLINK_ROW >= EGG_ROW   ; (title_rows wipes them)
        assert LICENSE_ROW >= EGG_ROW && LICENSE_ROW+1 <= 23 && LICENSE_LEN <= 32
DEC_POWERS:     dw 10000, 1000, 100, 10, 1
PAUSE_TEXT:     db "PAUSED",0
PAUSE_LEN       equ $-PAUSE_TEXT-1
PAUSE_BLANK:    db "      ",0
        assert $-PAUSE_BLANK-1 == PAUSE_LEN
OVER_TEXT:      db "GAME OVER",0
OVER_LEN        equ $-OVER_TEXT-1
SPACE_TEXT:     db " ",0
BONUS_TEXT:     db "BONUS 000 POINTS",0     ; (its digits: the points)
BONUS_LEN       equ $-BONUS_TEXT-1
BONUS_DIGITS    equ 6               ; the points' first digit in it
BONUS_HALF      equ BONUS_LEN/2     ; printed in its first frame, the rest in the next

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

        if ($ & 0FFh) > 100h-13     ; (PIXEL_BIT and ROW_MASKS in one 256-byte page)
        ds 100h-($ & 0FFh),0FFh
        endif
PIXEL_BIT:      db 80h, 40h, 20h, 10h, 08h, 04h, 02h, 01h   ; a column's bit in its byte
ROW_MASKS:      db 1, 3, 7, 6, 4    ; eb_masks: another bullet's top E-2..E+2: the rows of E's 3 it covers

        include "build/sprites.inc"
        include "build/sfx.inc"
        include "build/path.inc"
        include "build/title.inc"
        include "build/font.inc"

code_end:
        ifdef BIN
        assert $ <= RAM_BASE
        else
        assert $ <= 0C000h
        ds 0C000h-$,0FFh        ; a 32 KB ROM
        endif
