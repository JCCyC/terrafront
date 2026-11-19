# How MSX Galaga draws 40 enemies without flicker

Notes from reverse-engineering the user's own Galaga cartridge dump (`galaga.rom`, 16 KB ROM
mirrored to 32 KB, SHA-1 5bcb197a…). The findings come from openMSX traces on the Gradiente Expert
(2026-11-18): VRAM and RAM dumps, breakpoints on the BIOS VRAM routines, and `debug disasm`.
Addresses are ROM/RAM addresses in this dump.

## Screen setup

SCREEN 2. Names at 1800h, patterns at 0000h, colours at 2000h (all three thirds), SAT at 1B00h,
sprite patterns at 3800h, 16×16 sprites (R1 = E2h).

## 1. The formation is background tiles, not sprites

- Only the enemies flying in or diving, the player ship and the shots are sprites. An enemy
  sitting in the formation is 2×2 (or 3×2 when shifted) **characters**. Tiles have no per-line
  limit, so 10 enemies on one row never flicker, and each 8-px line of a tile can have its own
  two colours (sprites have one).
- Each band of the formation (two character rows, 16 px) is split into a left and right half of
  12 cells. Each half owns a fixed block of **24 characters** (12 cells × 2 rows) in its third of
  the pattern table (e.g. band 1 left = 0500h, right = 05C0h, …). 4 bands × 2 halves = 8 chunks.
  The table of chunks is at 4852h (8 bytes each).
- **Software sprites into a RAM buffer.** For each chunk, a task clears a 192-byte buffer
  (E800h) and, for each live enemy in the half-row (5 at most), copies its pre-shifted graphic in.
  The enemy's X & 7 picks the shift: each shifted copy is 3 cells × 2 rows = 48 bytes, so 8
  shifts = 384 bytes per animation frame. The copies live in RAM at E900h/EC00h (two enemy
  types × two flap frames). Enemies are drawn left to right, so only the leftmost cell of each
  graphic is ORed (it may hold the previous enemy's right edge). The other two cells are copied
  with plain `ldir`.
- A 24-byte name buffer (E8D0h) gets, per cell, either one of the chunk's own characters or 0
  (empty).
- **One chunk per 2 frames.** Every second frame, one chunk goes up: 192 pattern bytes plus
  2 × 12 name bytes (≈216 bytes, by BIOS LDIRVM). All 8 chunks take ~17 frames, so each enemy's
  tile image refreshes ~3.5 times a second. The formation moves slowly ("sway" and
  "breathing", ±2 px per enemy per cycle from bit tables at 489Ah/48A2h), so nobody notices
  the low update rate or that the rows update at different moments.
- Since each chunk has its own characters, rewriting them touches nothing else on screen. The
  name table only changes for the chunk being refreshed.
- The boss row (top) uses 2×2 fixed characters (90h–9Fh, table 48AAh: variants for animation
  and for a boss already hit once, which changes colour), placed by name writes.
- Bullet-vs-formation hits are worked out from the enemies' grid positions, not the hardware
  collision flag.

## 2. The star field costs 12 VRAM byte writes a frame

- Characters 20h–27h are two **vertical strips**: 20h–23h (4 cells = 32 px tall) and 24h–27h.
  The name table lays these runs down many columns with different vertical phases, and the
  layout repeats down the screen, so 2 strips look like a field of scattered stars. The
  colour is 60h (dark red on transparent), the same in all three thirds.
- Each strip's pattern holds **a single pixel** (bit 5). The ISR (4079h) erases the old pixel
  (WRTVRM 0) and writes the new one (WRTVRM 20h) at row `pos >> 3` in all three thirds:
  12 single-byte writes a frame.
- The two strips move at different speeds (the second is `speed sra 1`), which gives two
  parallax layers. The speed is signed and fractional (position in 1/8 px), so the stars can
  slow down, stop and reverse, as when the ship is captured.
- Formation tiles simply cover the star characters in their cells.

## 3. Sprites: flicker only where it can't be avoided

- The game builds the SAT in RAM (E780h). On even frames it uploads it as is; on odd frames it
  copies the 32 entries to E700h in **reverse order** (a push loop) and uploads that. With 5+
  sprites on a line, the dropped one alternates (30 Hz flicker) instead of one vanishing for
  good. Unused entries have Y = E0h (off screen), not D0h.
- There are few sprites to begin with (≤ ~8 divers + ship + shots), since the formation is tiles.

## 4. Frame structure

- INIT clears E000h–EFFFh, hooks H.TIMI (FD9Ah) with `jp 403Eh`, turns the screen on and
  sits in `jr $`. **The whole game runs in the interrupt.**
- The ISR resets SP to E700h, reads the VDP status, **turns the VDP interrupt off (R1 = C2h)**,
  does its work, then turns it back on (R1 = E2h) and returns to `jr $`. If a frame runs
  long, the next interrupt is held pending and fires as soon as it's re-enabled: the game
  slows down for a frame but never re-enters itself.
- Fixed per-frame work: SAT upload, stars, sound driver (6FFEh), input (PSG R14 + SNSMAT).
  Then it hands control to **cooperative tasks**: 11 coroutines with 32-byte stacks at E500h.
  `call 4147h` is "yield until next frame": it saves the task's SP in its slot and returns to
  the ISR. The formation refresher, enemy scripts and so on are each a straight-line loop with
  a yield in it.
- Measured on the Expert (60 Hz, 59,659 T a frame), 3000 gameplay frames: ISR mean 46.7k T,
  minimum 25.8k, maximum 82.1k; 60 frames (2%) ran over, so there is occasional slowdown.
  Heavy jobs are spread over alternate frames (formation chunk on even frames).

## Takeaways for a new shmup

1. Put anything that moves in a group, slowly or on a grid (formations, slow enemies,
   turrets, big bosses) in **tiles**, drawn into RAM buffers from pre-shifted graphics, with a
   private character block per screen region. Keep hardware sprites for the few fast things
   (player, shots, divers).
2. **Refresh tile objects round-robin**, a slice per frame, not all of them every frame.
3. Star field: a handful of one-pixel strip characters, scattered by the name table and moved
   by rewriting single bytes.
4. Rotate the SAT order every frame for whatever sprites remain.
5. Run everything off the frame interrupt with per-task coroutines, mask the VDP interrupt
   while working, and spread heavy jobs across alternate frames.
