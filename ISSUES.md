# Terra Front — open issues

Problems found but not dealt with yet, each with what's known and when to
act. Remove an entry once it's fixed (the fix's commit says so).

## A frame dropped at each wave begin in the test's wave-skipping part (Expert)

Found 2026-11-21, while adding the boss. On the Gradiente Expert (60 Hz),
every wave begin in `test.tcl`'s fast wave-skipping part (`wave_step` /
`wave_after`, waves 3..21) drops one frame: 19 in all, after a boss or
not. It was there before the boss too (commit 9dd2773 drops the same 19).
No check covers those frames; the summary line "frames dropped ... in all"
only reports them.

Likely cause, partly the test's own: `wave_step` puts 3 enemy bullets in
flight the frame before each begin, two of them sharing bitmap bytes
(`eb_draw`'s slow path). The begin frame's own work is `load_formation`
(the BIOS's slow LDIRVM) plus `level_text` printing 8 cells. A wave begin
in natural play (wave 2, in the enemies' part) dropped no frame.

**Decision:** leave it alone; act only if it causes bigger problems:
frame drops in real play, or a change that makes wave begins heavier
(more text or pattern loads in the same frame). The boss's end was split
over two frames (`BS_END`, then `BS_NEXT`) for this reason.
