# Terra Front — open issues

Problems found but not dealt with yet, each with what's known and when to
act. Remove an entry once it's fixed (the fix's commit says so).

## The Expert's frame budget: little room for new per-frame work

Found 2026-11-21. Small timing changes alter the R register and so the
game's random numbers, and each `make test` run then plays a different
game. Some of those games hit frames over the Expert's 16.67 ms and
dropped one (in the enemies' part, attract mode, a boss's bonus text, and
every wave begin in the test's wave-skipping part).

Cut since (CLAUDE.md lists the speed-ups): the worst frame `make profile`
finds is now about 14.6 ms on the Expert (it was 16.4 ms), and `make test`
drops no frame on any machine. The heaviest frames now are star steps with
two volleys and 2..5 enemy bullets in flight (attract mode, boss fights):
`move_bullets` 3.3..4.6 ms, `move_stars` 3.2..4.5, `eb_draw` 1.6..3.4,
plus attract mode's pseudo-player in `read_input` (about 1 ms). Other
routines' worst: `game_over` 4.7 (GAME OVER over a boss's bonus text),
`next_wave` 4.0 (a wave begin), `collide` 3.7 and `show_score` 3.4 (the
test's staged collisions and score writes).

Boss2 (2026-11-25, 0.9.5) raised the worst frame to about 15.7 ms (no
frame dropped on any machine): its fights' star steps with two volleys
and three enemy bullets (`move_stars` up to 5.1 ms: Boss2's 16 lines are
flagged, so their stars take `star`'s full way), its start
(`next_wave` 7.9 ms: `boss2_begin` draws its 256 VRAM bytes and loads
the enemy; could be split over two frames), its death (`move_bullets`
6.0 ms: `b2_erase`, 256 VRAM bytes, inside it).

**Decision:** the user's (2026-11-25): enough for now; apply these only
when a step really needs them (a frame over budget). The candidates:
Boss2's start and death split over two frames, its hidden stars
skipped, `eb_move`'s speed worked out every frame, `star`'s full way,
the per-bullet overhead left in `volley_px` and `bullet_px`.

## openMSX sometimes crashes during the headless test

Found 2026-11-21. `make test` (and `make profile`) under Xvfb sometimes
ends with openMSX crashing (exit 139, segmentation fault): the machine's
log stops early, with no FAIL or PASSED line, or the crash comes after
"ALL PASSED". It happens with the committed code too (3 of 4 parallel
Expert runs of commit dd69824). The crashes seen were near the test's
screenshots, and with extra breakpoints in the wave-begin code.

**Decision:** pending. Rerun the machine for now.

## Code space: the BIN's limit

Found 2026-11-22 (high scores, 0.9.2). Acted on 2026-11-25 (Boss2,
0.9.5), as planned: the ROM is a plain 32 KB cartridge (4000h..BFFFh,
page 2 switched by `enable_page2`), its code ending at 83F9h (about 15 KB
free); the BIN's RAM moved to CF00h (its IM 2 jump at D8D8h, under
`BIN_STACK_ROOM`), its code ending at C59Dh: about 2.4 KB under CF00h,
so the BIN runs out first. Past that (about 19.75 KB of code) the BIN
needs another layout (part of it in page 1's RAM).

**Decision:** the user's (2026-11-24): extend when a step needs it; no
need to squeeze code to stay in the limits.
