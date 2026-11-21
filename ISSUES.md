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

**Decision:** pending (the user's): enough for now, or more (the next
candidates: `eb_move`'s speed worked out every frame, `star`'s full way,
the per-bullet overhead left in `volley_px` and `bullet_px`).

## openMSX sometimes crashes during the headless test

Found 2026-11-21. `make test` (and `make profile`) under Xvfb sometimes
ends with openMSX crashing (exit 139, segmentation fault): the machine's
log stops early, with no FAIL or PASSED line, or the crash comes after
"ALL PASSED". It happens with the committed code too (3 of 4 parallel
Expert runs of commit dd69824). The crashes seen were near the test's
screenshots, and with extra breakpoints in the wave-begin code.

**Decision:** pending. Rerun the machine for now.
