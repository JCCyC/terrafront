# Headless check of the front. Env: LOGFILE, SYMFILE, SHOT (and SHOT with
# -call before .png: a call-up in flight).
# Driven by a breakpoint at main_loop (once a frame, before its halt: the
# frame's work is done, VRAM holds the previous frame's SAT).
after time 240 { fail "timeout" ; finish }
set save_settings_on_exit off
set throttle off

set log [open $::env(LOGFILE) w]
set fails 0
proc say {s} { puts $::log $s ; flush $::log }
proc fail {s} { incr ::fails ; say "FAIL: $s" }
proc ok {s} { say "ok: $s" }
proc check {cond s} { if {[uplevel 1 [list expr $cond]]} { ok $s } else { fail $s } }
proc finish {} {
	say [expr {$::fails ? "$::fails FAILED" : "ALL PASSED"}]
	close $::log
	exit
}
proc try {body} { if {[catch {uplevel #0 $body} e]} { fail "Tcl error: $e" ; finish } }

set f [open $::env(SYMFILE)]
while {[gets $f line] >= 0} {
	if {[regexp {^(\S+): EQU 0x([0-9A-Fa-f]+)} $line -> name val]} { set ::sym($name) [expr 0x$val] }
}
close $f
proc m {name {ofs 0}} { debug read memory [expr {$::sym($name) + $ofs}] }
proc rem {} { expr {[m call_rem] + 256*[m call_rem 1]} }
proc sat {i} { debug read VRAM [expr {0x1B00 + $i}] }
proc vol {} { debug read "PSG regs" 8 }
proc psg {r} { debug read "PSG regs" $r }

# Keyboard row 8: space 01h, left 10h, right 80h; C is row 3, 01h
proc down {bits} { keymatrixdown 8 $bits }
proc up {bits} { keymatrixup 8 $bits }
proc cdown {} { keymatrixdown 3 0x01 }
proc cup {} { keymatrixup 3 0x01 }
# The test keys 1..4: row 0, bits 1..4
proc kdown {k} { keymatrixdown 0 [expr {1 << $k}] }
proc kup {k} { keymatrixup 0 [expr {1 << $k}] }
# Joysticks: a breakpoint right after joy_r14's R14 read clears the held
# lines (bit 4 = button A, 5 = B) of port 1 (B = 03h) or 2 (B = 4Ch)
set joy(1) 0
set joy(2) 0
proc joydown {port bits} { set ::joy($port) $bits }
proc joyup {port} { set ::joy($port) 0 }
debug set_bp $sym(joy_r14.r14) {} {
	set p [expr {[reg B] == 0x03 ? 1 : 2}]
	if {$::joy($p)} { reg A [expr {[reg A] & ~$::joy($p) & 0xFF}] }
}
set VOL $sym(VOLLEY)
set W $sym(SHIP_ART_W)

set n 0
set steps {}        ;# list of {frame script}
proc at {frame body} { lappend ::steps [list $frame $body] }

# The death sound: kill_nth (re)starts it; death_frame checks channel C
# against the table every frame
set dnew 0 ; set didx -1 ; set druns {} ; set dstarts 0
set dbad 0 ; set dclash 0 ; set dframes 0 ; set dfirst ""
debug set_bp $sym(kill_nth.sound) {} { set ::dnew 1 }

set spawns 0
debug set_bp $sym(fire.free) {} { incr ::spawns }

proc frame {} {
	incr ::n
	set rest {}
	foreach s $::steps {
		if {[lindex $s 0] == $::n} { try [lindex $s 1] } else { lappend rest $s }
	}
	set ::steps $rest
	# every frame: never more than MAX_VOLLEYS in flight, the bullet's sound in step
	set live 0
	for {set i 0} {$i < $::sym(MAX_VOLLEYS)} {incr i} { if {[m volleys [expr {$i*$::VOL}]]} { incr live } }
	if {$live > $::maxlive} { set ::maxlive $live }
	if {[info exists ::track]} { try track_frame }
	if {[info exists ::bw]} { lappend ::bw [list [sat [expr {$::bwslot*4}]] [sat [expr {$::bwslot*4+2}]]] }
	try check_sat
	try star_frame
	try check_bitmap
	try call_frame
	try death_frame
	try form_frame
}
set maxlive 0

proc plan {} {
	set F [m fps]
	set ::F $F
	set ::bstart [expr {$::sym(BULLET_START)}]
	say "fps $F"
	set x0 [m ship_x]
	check {$x0 == $::sym(SHIP_X_MAX)/2} "ship starts in the middle (x $x0)"
	at 3 { check {[sat 0] == $::sym(SHIP_TOP) - 1} "ship sprite Y [sat 0] (art's last row on line 183)" }
	at 3 { check_reserves }
	at 3 { check_stars_start }
	at 3 { check_form_pick ; check_form_pattern }
	at 3 { check_cleared }

	# 1 s of right: SHIP_SPEED px (+-1 for the Bresenham remainder)
	set a 10
	at $a { set ::x0 [m ship_x] ; down 0x80 }
	at [expr {$a+$F}] {
		up 0x80
		set d [expr {[m ship_x] - $::x0}]
		check {abs($d - 108) <= 1} "ship moves $d px in 1 s (108 px/s)"
	}
	# both arrows: no move
	set a [expr {$a+$F+5}]
	at $a { set ::x0 [m ship_x] ; down 0x90 }
	at [expr {$a+20}] { up 0x90 ; check {[m ship_x] == $::x0} "left+right together: no move" }
	# 3 s of left: clamped at 0, the sprite clipped with the early clock
	set a [expr {$a+25}]
	at $a { down 0x10 }
	at [expr {$a+3*$F}] {
		up 0x10
		check {[m ship_x] == 0} "left edge: ship_x [m ship_x]"
	}
	at [expr {$a+3*$F+2}] {
		check {[sat 1] == 29 && [sat 3] == 0x8F} "left edge sprite: X [sat 1] colour [format %02X [sat 3]] (EC, art at column 0)"
	}
	# 3 s of right: clamped at SHIP_X_MAX, art's right column on 255
	set a [expr {$a+3*$F+5}]
	at $a { down 0x80 }
	at [expr {$a+3*$F}] {
		up 0x80
		check {[m ship_x] == $::sym(SHIP_X_MAX)} "right edge: ship_x [m ship_x]"
	}
	at [expr {$a+3*$F+2}] {
		check {[sat 1] == 244 && [sat 3] == 0x0F} "right edge sprite: X [sat 1] colour [format %02X [sat 3]]"
	}
	# back to the middle-ish, then one shot: spawn point, speed, removal, sound
	set a [expr {$a+3*$F+5}]
	at $a { down 0x10 }
	at [expr {$a+$F}] { up 0x10 }
	set a [expr {$a+$F+5}]
	at [expr {$a-3}] { put_star0 }
	at $a { set ::spawns 0 ; down 0x01 }
	at [expr {$a+1}] {
		up 0x01
		set y [m volleys 0] ; set x [m volleys 1]
		check {$y == $::bstart && $x == [m ship_x] + 4} "bullet spawns at nose: Y $y X $x (ship_x [m ship_x])"
		set ::track [list $y -1 0 0]   ;# start Y, frames moved (this one is the spawn), last Y, sound frames
		set ::sndframes 0
		set ::sndon 1
	}
	# with the sound and the bullet over: five presses in 8 frames -> two shots
	set a [expr {$a+2*$F}]
	at $a {
		check {$::spawns == 1} "one press, one shot ($::spawns)"
		check {$::star0_hid > 0 && [m stars 2]} "a star under a new bullet hides ($::star0_hid frames), then shows again"
		set ::spawns 0
		down 0x01
	}
	foreach k {1 3 5 7} { at [expr {$a+$k}] { up 0x01 } ; at [expr {$a+$k+1}] { down 0x01 } }
	at [expr {$a+9}] { up 0x01 }
	at [expr {$a+12}] {
		check {$::spawns == 2} "five quick presses: two shots ($::spawns)"
		check {$::maxlive == 2} "at most two bullets in flight ($::maxlive)"
	}
	# held fire: one shot
	set a [expr {$a+2*$F}]
	at $a { set ::spawns 0 ; down 0x01 }
	at [expr {$a+$F}] { up 0x01 ; check {$::spawns == 1} "fire held 1 s: one shot ($::spawns)" }
	plan_calls [expr {$a+$F+5}]
}

# The call-ups. Start: one ship, 4 in reserve.
proc plan_calls {a} {
	set F $::F
	at $a {
		check {[m front_mask] == 1 && [m reserves] == 4} "one ship in the front, 4 in reserve"
		set ::spawns 0
		joydown 2 0x10
	}
	# joystick 2's button A fires and doesn't call up
	at [expr {$a+2}] { joyup 2 }
	at [expr {$a+4}] {
		check {$::spawns == 1 && [m call_on] == 0 && [m reserves] == 4} "joystick 2 button A: a shot ($::spawns), no call-up"
	}
	set a [expr {$a+5}]
	# 1: a one-ship front at the far left: the longest flight, from the
	# right, glued on the right; the front held right meanwhile stays put,
	# fires a one-bullet volley, and moves once the ship is in
	at $a { down 0x10 }
	set a [expr {$a+3*$F}]
	at $a { up 0x10 }
	set a [expr {$a+3}]
	at $a { cdown ; down 0x80 ; set ::calls {} }
	at [expr {$a+1}] { cup }
	at [expr {$a+4}] { down 0x01 }
	at [expr {$a+5}] {
		up 0x01
		set v [volley_live]
		check {[llength $v] == 1 && [lrange [lindex $v 0] 1 end] == {4 0 0 0}} "a shot during a call-up: one bullet, from the front's ship ([lindex $v 0])"
	}
	at [expr {$a+$F/2}] {
		up 0x80
		check_call 0 247 $::W 2
		check {[m front_mask] == 3 && [m front_slots] == 2} "two ships in the front (mask [m front_mask])"
		check {[m ship_x] > 0} "the front moves again after the glue (ship_x [m ship_x])"
		check_reserves 3
	}
	# 2: a two-ship front at the far right: from the left, glued on the left
	set a [expr {$a+$F/2+3}]
	at $a { down 0x80 }
	set a [expr {$a+3*$F}]
	at $a {
		up 0x80
		check {[m ship_x] == 256 - 2*$::W} "two-ship front's right edge: ship_x [m ship_x]"
	}
	at [expr {$a+2}] {
		check {[sat 5] == 256 - $::W - 3 && [sat 7] == 0x0F} "second ship's sprite at the right edge: X [sat 5] colour [format %02X [sat 7]]"
		set ::throttle on   ;# for the picture of the flight
	}
	set a [expr {$a+3}]
	at $a { cdown ; down 0x10 ; set ::calls {} }
	at [expr {$a+1}] { cup }
	at [expr {$a+$F/2}] {
		up 0x10
		check_call 1 [expr {256 - 2*$::W}] [expr {256 - 3*$::W}] 3
		check {[m front_mask] == 7 && [m ship_x] < 256 - 3*$::W} "three ships, moved left after the glue (ship_x [m ship_x])"
		set ::throttle off
	}
	# 3: back to the far right, a third call-up (from the left) makes four
	set a [expr {$a+$F/2+3}]
	at $a { down 0x80 }
	set a [expr {$a+$F}]
	at $a { up 0x80 }
	# (by joystick 1's button B, which doesn't fire)
	set a [expr {$a+3}]
	at $a { joydown 1 0x20 ; set ::calls {} ; set ::spawns 0 }
	at [expr {$a+2}] { joyup 1 }
	at [expr {$a+$F/2}] {
		check {$::spawns == 0} "joystick 1 button B: no shot ($::spawns)"
		check_call 1 [expr {256 - 3*$::W}] [expr {256 - 4*$::W}] 4
		check {[m front_mask] == 15 && [m ship_x] == 256 - 4*$::W} "four ships glued: ship_x [m ship_x]"
		check_reserves 1
		set ::calls {}
		cdown
	}
	# 4: a full front: C does nothing
	at [expr {$a+$F/2+1}] { cup }
	at [expr {$a+$F/2+4}] {
		check {[m call_on] == 0 && [llength $::calls] == 0 && [m reserves] == 1} "C with four ships: no call-up, 1 in reserve"
		check_reserves 1
		joydown 1 0x10
	}
	# a volley from all four noses (joystick 1's button A)
	at [expr {$a+$F/2+5}] {
		joyup 1
		set x [m ship_x]
		set v [volley_live]
		set want [list [expr {$x+4}] [expr {$x+4+$::W}] [expr {$x+4+2*$::W}] [expr {$x+4+3*$::W}]]
		check {[llength $v] == 1 && [lrange [lindex $v 0] 1 end] == $want} "four-ship volley: [lindex $v 0] (want $want)"
	}
	# five quick presses: two volleys
	set a [expr {$a+$F/2+5+2*$F}]
	at $a { set ::spawns 0 ; down 0x01 }
	foreach k {1 3 5 7} { at [expr {$a+$k}] { up 0x01 } ; at [expr {$a+$k+1}] { down 0x01 } }
	at [expr {$a+9}] { up 0x01 }
	at [expr {$a+12}] { check {$::spawns == 2 && [llength [volley_live]] == 2} "four ships, five quick presses: two volleys ($::spawns)" }
	# the four-ship front's edges
	set a [expr {$a+15}]
	at $a { down 0x10 }
	set a [expr {$a+3*$F}]
	at $a { up 0x10 ; check {[m ship_x] == 0} "four-ship front's left edge: ship_x [m ship_x]" }
	set a [expr {$a+3}]
	at $a { down 0x80 }
	set a [expr {$a+3*$F}]
	at $a {
		up 0x80
		check {[m ship_x] == 256 - 4*$::W} "four-ship front's right edge: ship_x [m ship_x]"
		check {$::maxlive == 2} "at most two volleys in flight ($::maxlive)"
	}
	plan_kills [expr {$a+5}]
}

# The test keys: deaths, booms, holes, trims, the call-up rule on the
# front's span, an emptied front. Start: four ships at the right edge, 1 in
# reserve; the test gives the game more reserves (in RAM only: the status
# row isn't redrawn) so that the call-ups below can run.
proc plan_kills {a} {
	set F $::F
	at $a {
		check {[m front_mask] == 15 && [m ship_x] == 256 - 4*$::W} "kills start: four ships at the right edge"
		debug write memory $::sym(reserves) 3
		set ::bwslot 1 ; set ::bw {}
		kdown 2
	}
	at [expr {$a+1}] { kup 2 }
	# a volley while ship 2 dies: no bullet from it
	at [expr {$a+3}] { down 0x01 }
	at [expr {$a+4}] {
		up 0x01
		set x [m ship_x]
		set v [volley_live]
		set want [list [expr {$x+4}] 0 [expr {$x+4+2*$::W}] [expr {$x+4+3*$::W}]]
		check {[llength $v] == 1 && [lrange [lindex $v 0] 1 end] == $want} "a volley while ship 2 dies: [lindex $v 0] (want $want)"
	}
	at [expr {$a+25}] {
		set runs [boom_runs $::bw] ; unset ::bw
		set want [expr {$::F == 60 ? {12 6 16 4 20 5 parked} : {12 5 16 3 20 4 parked}}]
		check {$runs eq $want} "key 2: ship 2's boom in the SAT, name and frames: $runs (want $want)"
		check {[m front_mask] == 13 && [m front_slots] == 4 && [m ship_x] == 256 - 4*$::W} "ship 2 gone, a hole: mask [m front_mask], [m front_slots] slots, ship_x [m ship_x]"
		kdown 2
	}
	# key 2 again: the second ship is now slot 2; ship-gap-gap-ship can't call up
	at [expr {$a+26}] { kup 2 }
	at [expr {$a+46}] {
		check {[m front_mask] == 9 && [m front_slots] == 4} "key 2 again: ship-gap-gap-ship (mask [m front_mask], [m front_slots] slots)"
		set ::calls {} ; cdown
	}
	at [expr {$a+47}] { cup }
	at [expr {$a+50}] {
		check {[m call_on] == 0 && [llength $::calls] == 0 && [m reserves] == 3} "ship-gap-gap-ship: C does nothing (span 4, 3 in reserve)"
		kdown 4
	}
	# key 4 with two ships: nothing
	at [expr {$a+51}] { kup 4 }
	at [expr {$a+53}] {
		set st [list [m boom_stage 0] [m boom_stage 1] [m boom_stage 2] [m boom_stage 3]]
		check {[m front_mask] == 9 && $st == {0 0 0 0}} "key 4 with two ships: no death (mask [m front_mask], stages $st)"
		kdown 1
	}
	# key 1: the first ship dies, the front is trimmed to the last one
	at [expr {$a+54}] { kup 1 }
	at [expr {$a+74}] {
		check {[m front_mask] == 1 && [m front_slots] == 1 && [m front_w] == $::W && [m ship_x] == 256 - $::W} "key 1: trimmed to the last ship (mask [m front_mask], ship_x [m ship_x], [m front_w] px)"
		set ::calls {} ; cdown
	}
	at [expr {$a+75}] { cup }
	set b [expr {$a+74+$F/2}]
	at $b {
		check_call 1 [expr {256 - $::W}] [expr {256 - 2*$::W}] 2
		set ::calls {} ; cdown
	}
	at [expr {$b+1}] { cup }
	set b [expr {$b+$F/2}]
	at $b {
		check_call 1 [expr {256 - 2*$::W}] [expr {256 - 3*$::W}] 3
		check {[m front_mask] == 7} "three ships again (mask [m front_mask])"
		kdown 2
	}
	# ship-gap-ship calls up from the left ...
	at [expr {$b+1}] { kup 2 }
	at [expr {$b+26}] {
		check {[m front_mask] == 5 && [m front_slots] == 3} "key 2: ship-gap-ship (mask [m front_mask])"
		set ::calls {} ; cdown
	}
	at [expr {$b+27}] { cup }
	set b [expr {$b+26+$F/2}]
	at $b {
		check_call 1 [expr {256 - 3*$::W}] [expr {256 - 4*$::W}] 4
		check {[m front_mask] == 11 && [m reserves] == 0} "ship-gap-ship: one more from the left (mask [m front_mask])"
		debug write memory $::sym(reserves) 1
		kdown 1
	}
	# ... and, at the left edge, from the right
	at [expr {$b+1}] { kup 1 }
	at [expr {$b+26}] {
		check {[m front_mask] == 5 && [m ship_x] == 256 - 3*$::W} "key 1: trimmed to ship-gap-ship (mask [m front_mask], ship_x [m ship_x])"
		down 0x10
	}
	set b [expr {$b+26+3*$F}]
	at $b { up 0x10 ; check {[m ship_x] == 0} "ship-gap-ship at the left edge" }
	at [expr {$b+2}] { set ::calls {} ; cdown }
	at [expr {$b+3}] { cup }
	set b [expr {$b+2+$F/2}]
	at $b {
		check_call 0 [expr {256 - 3*$::W}] [expr {3*$::W}] 4
		check {[m front_mask] == 13 && [m reserves] == 0} "ship-gap-ship: one more from the right (mask [m front_mask])"
		kdown 3
	}
	# keys 3, 2, 1: all three die, the front is empty where its last died
	at [expr {$b+1}] { kup 3 }
	at [expr {$b+3}] { kdown 2 }
	at [expr {$b+4}] { kup 2 }
	at [expr {$b+6}] { kdown 1 }
	at [expr {$b+7}] { kup 1 }
	at [expr {$b+40}] {
		check {[m front_mask] == 0 && [m front_slots] == 0 && [m front_w] == 0 && [m ship_x] == 0} "keys 3, 2, 1: the front is empty at x [m ship_x]"
		set ::spawns 0
		down 0x81
	}
	at [expr {$b+41}] { up 0x01 }
	at [expr {$b+50}] {
		up 0x80
		check {[m ship_x] == 0 && $::spawns == 0 && [llength [volley_live]] == 0} "empty front: no move, no shot (ship_x [m ship_x], $::spawns shots)"
		set ::calls {} ; cdown
	}
	at [expr {$b+51}] { cup }
	at [expr {$b+54}] {
		check {[m call_on] == 0 && [llength $::calls] == 0} "empty front, no reserves: C does nothing"
		debug write memory $::sym(reserves) 1
		cdown
	}
	at [expr {$b+55}] { cup }
	set b [expr {$b+54+$F/2}]
	at $b {
		check_call 0 256 0 1
		check {[m front_mask] == 1 && [m ship_x] == 0} "empty front refilled where its last ship died (ship_x [m ship_x])"
		check {$::bitmap_bad == 0 && $::bitmap_lit > 0} "bitmap = the bullets in flight and the stars not in their bytes, colours too, every frame ($::bitmap_frames frames, $::bitmap_lit pixels seen; [expr {$::bitmap_bad ? "first wrong: $::bitmap_first" : "none wrong"}])"
		check {$::sat_bad == 0} "sprites = the front (ships and booms) and the incoming ship, every frame ($::sat_frames frames; [expr {$::sat_bad ? "first wrong: $::sat_first" : "none wrong"}])"
		check {$::coming_seen > 0} "the incoming ship's sprite showed on $::coming_seen frames"
		check_stars_end
		check_form_end
	}
	# the last death sound plays out
	at [expr {$b+5+$F*3/2}] {
		set want [expr {$::F == 60 ? 84 : 70}]
		check {$::dstarts >= 8 && $::didx == -1 && [lindex $::druns end] == $want} "death sound: $::dstarts starts, the last plays out in [lindex $::druns end] frames (want $want, 1.4 s; runs $::druns)"
		check {$::dbad == 0 && $::dframes > 0} "death sound on channel C = DEATH table, every frame ($::dframes frames playing, $::dclash with the shot's noise on too; [expr {$::dbad ? "first wrong: $::dfirst" : "none wrong"}])"
	}
	at [expr {$b+10+$F*3/2}] { screenshot_and_finish }
}

# The death sound, after a frame's work: started this frame -> the table's
# first row. Playing: R10 its volume, R4/R5 its tone, channel C's tone and
# noise on, R6 its noise period (even while the shot's noise is on: the
# death sound wins);
# at its end marker, or idle: R10 0, channel C's tone and noise off.
# A run's frames are counted, from its (re)start to its end marker.
proc death_frame {} {
	if {$::dnew} { set ::dnew 0 ; set ::didx 0 ; incr ::dstarts }
	set mix [psg 7]
	set got [list [psg 10] [psg 4] [psg 5] [psg 6] [expr {$mix & 0x24}]]
	if {$::didx >= 0} {
		set t [expr {$::sym(DEATH_$::F) + 4*$::didx}]
		set v [debug read memory $t]
		if {$v == 0} {
			lappend ::druns $::didx
			set ::didx -1
			set want [list 0 [lindex $got 1] [lindex $got 2] [lindex $got 3] 36]
		} else {
			incr ::dframes
			if {!($mix & 0x08)} { incr ::dclash }
			set want [list $v [debug read memory [expr {$t+2}]] [debug read memory [expr {$t+3}]] [debug read memory [expr {$t+1}]] 0]
			incr ::didx
		}
	} else {
		set want [list 0 [lindex $got 1] [lindex $got 2] [lindex $got 3] 36]
	}
	if {$got != $want} {
		if {!$::dbad} { set ::dfirst "frame $::n: R10 R4 R5 R6 mix-C $got, want $want" }
		incr ::dbad
	}
}

# A slot's SAT entries ({Y name} a frame) from the first boom name on:
# {name frames ...}, then "parked" if the sprite left afterwards
proc boom_runs {entries} {
	set r {}
	set last -1
	foreach e $entries {
		lassign $e y nm
		if {$y == 0xC0} { if {[llength $r]} { lappend r parked } ; break }
		if {$nm < $::sym(NAME_BOOM) && ![llength $r]} continue
		if {$nm == $last} { lset r end [expr {[lindex $r end] + 1}] } else { lappend r $nm 1 ; set last $nm }
	}
	return $r
}

# The volleys in flight: {Y x0 x1 x2 x3} each
proc volley_live {} {
	set r {}
	for {set i 0} {$i < $::sym(MAX_VOLLEYS)} {incr i} {
		set b [expr {$i*$::VOL}]
		if {[m volleys $b]} {
			set v [m volleys $b]
			for {set k 1} {$k <= 4} {incr k} { lappend v [m volleys [expr {$b+$k}]] }
			lappend r $v
		}
	}
	return $r
}

# The last call-up: from the left (1) or right (0), its first distance and
# glue point; flight frames, steps, a front that didn't move
proc check_call {left rem0 target slots} {
	if {[llength $::calls] != 1} { fail "one call-up expected, got [llength $::calls]" ; return }
	lassign [lindex $::calls 0] l r t frames steps frozen
	set S $::sym(CALL_SPEED)
	set want [expr {($r*$::F + $S - 1) / $S}]
	set side [expr {$l ? "left" : "right"}]
	check {$l == $left && $r == $rem0 && $t == $target} "call-up from the $side: $r px to fly, glued at $t"
	check {$frames == $want && $frames * 1000 <= 250 * $::F} "call-up flight: $frames frames ([format %.3f [expr {double($frames)/$::F}]] s, constant $S px/s)"
	set lo [expr {$S / $::F}]
	set ok 1
	foreach s [lrange $steps 0 end-1] { if {$s != $lo && $s != $lo+1} { set ok 0 } }
	check {$ok} "call-up steps $lo or [expr {$lo+1}] px a frame: $steps"
	check {$frozen} "the front stayed put during the call-up"
	check {[m front_slots] == $slots && [m front_w] == $slots*$::W} "front: $slots slots, [m front_w] px"
}

# Every frame: follow a call-up from its start to its glue
set incall 0
proc call_frame {} {
	set on [m call_on]
	if {$on && !$::incall} {
		set ::incall 1
		set ::cur [list [m call_left] [rem] [m call_target]]
		set ::curx [m ship_x]
		set ::lastrem [rem]
		set ::cursteps {}
		set ::curframes 0
		set ::curfrozen 1
	} elseif {$::incall} {
		incr ::curframes
		set rem [expr {$on ? [rem] : 0}]
		lappend ::cursteps [expr {$::lastrem - $rem}]
		set ::lastrem $rem
		if {[m ship_x] != $::curx && $on} { set ::curfrozen 0 }
		if {!$on} {
			set ::incall 0
			lappend ::calls [concat $::cur [list $::curframes $::cursteps $::curfrozen]]
		} elseif {$::shoot_call && [m call_left] && $rem < 120} {
			set ::shoot_call 0
			set ::pause on
			after realtime 0.3 { screenshot [regsub {\.png$} $::env(SHOT) {-call.png}] ; set ::pause off }
		}
	}
}
set calls {}
set shoot_call 1

# Every frame: VRAM's SAT is the last frame's front and incoming ship
set sat_bad 0
set sat_frames 0
set coming_seen 0
proc want_sat {} {
	set r {}
	set mask [m front_mask]
	set x [m ship_x]
	for {set i 0} {$i < 4} {incr i} {
		if {$mask >> $i & 1} {
			set sx [expr {$x + $i*$::W - $::sym(SHIP_ART_L)}]
			set st [m boom_stage $i]
			set nm [expr {$st ? $::sym(NAME_BOOM) + 4*($st - 1) : 0}]
			set col [expr {$st ? $::sym(BOOM_COLOR) : $::sym(SHIP_COLOR)}]
			lappend r [expr {$::sym(SHIP_TOP) - 1}] [expr {$sx < 0 ? $sx + 32 : $sx}] $nm [expr {$sx < 0 ? 0x80 | $col : $col}]
		} else { lappend r 0xC0 - - - }
	}
	if {[m call_on]} {
		set t [m call_target] ; set rem [rem]
		if {[m call_left]} {
			set sx [expr {$t - $rem - $::sym(COMING_L_ART_L)}] ; set nm 8
		} else {
			set sx [expr {$t + $rem - $::sym(COMING_R_ART_L)}] ; set nm 4
		}
		if {$sx > 255} {
			lappend r 0xC0 - - -
		} else {
			lappend r [expr {$::sym(SHIP_TOP) - 1}] [expr {$sx < 0 ? $sx + 32 : $sx}] $nm [expr {$sx < 0 ? 0x8F : 0x0F}]
		}
	} else { lappend r 0xC0 - - - }
	lappend r {*}[lrepeat 16 -]   ;# the formation: form_frame
	lappend r 0xD0
	return $r
}
proc check_sat {} {
	if {[info exists ::prev_sat]} {
		incr ::sat_frames
		set i 0
		foreach w $::prev_sat {
			set g [sat $i]
			if {$w ne "-" && $g != $w} {
				if {!$::sat_bad} { set ::sat_first "frame $::n byte $i: [format %02X $g], want [format %02X $w]" }
				incr ::sat_bad
				break
			}
			incr i
		}
		if {[sat 16] != 0xC0 && [sat 18] > 0} { incr ::coming_seen }
	}
	set ::prev_sat [want_sat]
}

# A bullet in flight in pixel (x, y)'s bitmap byte
proc bullet_in {x y} {
	foreach v [volley_live] {
		set t [lindex $v 0]
		if {$y < $t || $y >= $t + $::sym(BULLET_H)} continue
		foreach bx [lrange $v 1 end] { if {$bx && $bx/8 == $x/8} { return 1 } }
	}
	return 0
}

# The stars: {x y on} each
proc star_list {} {
	set r {}
	for {set i 0} {$i < $::sym(STARS)} {incr i} {
		set b [expr {$i*$::sym(STAR)}]
		lappend r [list [m stars [expr {$b+$::sym(STAR.X)}]] [m stars [expr {$b+$::sym(STAR.Y)}]] [m stars [expr {$b+$::sym(STAR.ON)}]]]
	}
	return $r
}

proc check_stars_start {} {
	set s [star_list]
	set ys [lsort -integer -unique [lmap e $s {lindex $e 1}]]
	check {[llength $s] == 15 && [llength $ys] == 15 && [lindex $ys 0] >= 8 && [lindex $ys end] <= 183} "15 stars on 15 playfield lines ($s)"
	set lit 0
	foreach e $s { lassign $e x y on ; if {$on} { incr lit } }
	check {$lit == 15} "all 15 stars drawn ($lit)"
}

# Every frame: all stars move together, 0 or 1 px left; one leaving column
# 0 comes back at 255 on a new line; the lines stay distinct, in the playfield
set star_bad 0 ; set star_first "" ; set star_moves {} ; set star_wraps 0 ; set star_skip 0
proc star_bad {s} { if {!$::star_bad} { set ::star_first "frame $::n: $s" } ; incr ::star_bad }
proc star_frame {} {
	set cur [star_list]
	set ys [lsort -integer -unique [lmap e $cur {lindex $e 1}]]
	if {[llength $ys] != 15 || [lindex $ys 0] < 8 || [lindex $ys end] > 183} { star_bad "lines $ys" }
	if {[info exists ::star_prev] && !$::star_skip} {
		set moved -1
		foreach p $::star_prev c $cur {
			lassign $p px py ; lassign $c cx cy
			set d [expr {($px - $cx) & 255}]
			if {$moved < 0} { set moved $d } elseif {$d != $moved} { star_bad "steps differ" }
			if {$d > 1} { star_bad "step $d" }
			if {$d == 1 && $px == 0} { incr ::star_wraps } elseif {$cy != $py} { star_bad "line changed without a wrap" }
		}
		if {$moved == 1} { lappend ::star_moves $::n }
	}
	set ::star_skip 0
	set ::star_prev $cur
}

proc check_stars_end {} {
	set gaps {}
	set prev ""
	foreach f $::star_moves { if {$prev ne ""} { lappend gaps [expr {$f - $prev}] } ; set prev $f }
	set want [expr {$::F / 10}]
	set g [lsort -integer -unique $gaps]
	check {$g == $want && [llength $::star_moves] > 100} "stars step 1 px every $want frames ([llength $::star_moves] steps, gaps seen: $g; 10 px/s)"
	check {$::star_wraps >= 15} "stars leaving column 0 come back at 255 on a free line ($::star_wraps)"
	check {$::star_bad == 0} "stars move together, lines distinct ([expr {$::star_bad ? $::star_first : "none wrong"}])"
	check {$::star_hidden > 0} "stars hidden in a bullet's byte on $::star_hidden star-frames"
}

# Star 0 moved onto a free spawn line of a bullet, at the ship's nose, so
# that the next volley draws over it (the test's own VRAM fix-up for its old
# place)
set star0_hid 0
proc put_star0 {} {
	lassign [lindex [star_list] 0] x y on
	if {$on} {
		set a [expr {($y/8)*256 + ($x & 0xF8) + $y%8}]
		debug write VRAM $a 0
		debug write VRAM [expr {0x2000 + $a}] 0xF1
	}
	set used [lmap e [lrange [star_list] 1 end] {lindex $e 1}]
	set ny -1
	for {set r 0} {$r < 3} {incr r} { set l [expr {$::bstart + $r}] ; if {$l ni $used} { set ny $l ; break } }
	if {$ny < 0} { fail "no free bullet line for star 0" ; return }
	set b $::sym(stars)
	debug write memory $b [expr {[m ship_x] + 4}]
	debug write memory [expr {$b+1}] $ny
	debug write memory [expr {$b+2}] 0
	set ::star_skip 1
	set ::bitmap_skip 1
}

# Every frame: the bitmap's playfield and top status rows (lines 0..183)
# hold exactly the volleys' bullets, BULLET_COLOR on black, and the stars
# not in a bullet's byte, STAR_COLOR on black; the rest of the playfield's
# colour bytes are BULLET_COLOR on black
set bitmap_bad 0
set bitmap_frames 0
set bitmap_lit 0
set star_hidden 0
set bitmap_skip 0
proc check_bitmap {} {
	if {$::n == 1} return   ;# before the main loop's first frame: no star drawn yet
	if {$::bitmap_skip} { set ::bitmap_skip 0 ; return }   ;# put_star0 just undrew star 0
	set bad0 {}
	set want [dict create]
	foreach v [volley_live] {
		set y [lindex $v 0]
		foreach x [lrange $v 1 end] {
			if {!$x} continue
			for {set r $y} {$r < $y + $::sym(BULLET_H)} {incr r} {
				set a [expr {($r/8)*256 + ($x/8)*8 + $r%8}]
				set b [expr {0x80 >> ($x%8)}]
				if {[dict exists $want $a]} { set b [expr {$b | [dict get $want $a]}] }
				dict set want $a $b
			}
		}
	}
	set starb [dict create]
	set i 0
	foreach e [star_list] {
		lassign $e x y on
		set hid [bullet_in $x $y]
		if {$hid} { incr ::star_hidden ; if {$i == 0} { incr ::star0_hid } }
		if {$on == $hid} { lappend bad0 "star $i on $on" }
		if {!$hid} {
			set a [expr {($y/8)*256 + ($x/8)*8 + $y%8}]
			dict set want $a [expr {0x80 >> ($x%8)}]
			dict set starb $a 1
		}
		incr i
	}
	set blk [debug read_block VRAM 0 [expr {23*256}]]
	set got [dict create]
	foreach p [regexp -all -indices -inline {[^\x00]} $blk] {
		set a [lindex $p 0]
		binary scan [string index $blk $a] cu b
		dict set got $a $b
	}
	incr ::bitmap_frames
	incr ::bitmap_lit [dict size $got]
	set bad $bad0
	dict for {a b} $want { if {![dict exists $got $a] || [dict get $got $a] != $b} { lappend bad $a } }
	dict for {a b} $got { if {![dict exists $want $a]} { lappend bad $a } }
	set cb [debug read_block VRAM 0x2100 [expr {22*256}]]
	foreach p [regexp -all -indices -inline {[^\xF1]} $cb] {
		set a [expr {[lindex $p 0] + 256}]
		binary scan [string index $cb [lindex $p 0]] cu c
		if {!([dict exists $starb $a] && $c == 0xE1)} { lappend bad "colour $a" }
	}
	dict for {a b} $starb {
		if {[debug read VRAM [expr {0x2000 + $a}]] != 0xE1} { lappend bad "star colour $a" }
	}
	if {[llength $bad]} {
		if {!$::bitmap_bad} { set ::bitmap_first "frame $::n at [lrange $bad 0 4]" }
		incr ::bitmap_bad
	}
}

# The bottom status row (lines 184..191): RESERVES ships, art from column
# RESERVE_X, every RESERVE_STEP px, white on black; nothing else on it
proc check_reserves {{count 4}} {
	set shape {}
	for {set r 0} {$r < 8} {incr r} { lappend shape [m RESERVE_SHAPE $r] }
	set w $::sym(RESERVE_ART_W)
	set bad {}
	set lit 0
	for {set y 0} {$y < 8} {incr y} {
		for {set x 0} {$x < 256} {incr x} {
			set want 0
			for {set i 0} {$i < $count} {incr i} {
				set dx [expr {$x - $::sym(RESERVE_X) - $i*($w + $::sym(RESERVE_GAP))}]
				if {$dx >= 0 && $dx < $w} { set want [expr {([lindex $shape $y] >> (7 - $dx)) & 1}] }
			}
			set a [expr {23*256 + ($x/8)*8 + $y}]
			set got [expr {([debug read VRAM $a] >> (7 - $x%8)) & 1}]
			if {$got} { incr lit ; set col [expr {[debug read VRAM [expr {0x2000 + $a}]] >> 4}] } else { set col 15 }
			if {$got != $want || $col != 15} { lappend bad "($x,$y)" }
		}
	}
	check {[llength $bad] == 0 && $lit > 0} "$count reserve ships at the bottom left, 1 px apart ($lit px lit; wrong: [lrange $bad 0 9])"
	set names {}
	for {set c 0} {$c < 32} {incr c} { if {[debug read VRAM [expr {0x1800 + 23*32 + $c}]] != 0xE0 + $c} { lappend names $c } }
	check {[llength $names] == 0} "bottom row's names are INIGRP's (wrong at: $names)"
}

# The single shot: its Y each frame, until gone; the PSG channel A volume
proc track_frame {} {
	lassign $::track y0 frames last snd
	set y [m volleys 0]
	if {$::sndon} {
		if {[vol] > 0} { incr ::sndframes } else {
			set ::sndon 0
			set want [expr {$::F == 60 ? 15 : 13}]
			check {$::sndframes == $want} "shot sound lasts $::sndframes frames ([format %.3f [expr {double($::sndframes)/$::F}]] s)"
		}
	}
	if {$y == 0} {
		if {$frames > 0} {
			set speed [expr {double($y0 - $last) * $::F / $frames}]
			check {abs($speed - 230) <= double($::F) / $frames} "bullet speed [format %.1f $speed] px/s over $frames frames"
			check {$last - 8 < 5} "bullet gone at the top (last top line $last)"
			set ::frames_done 1
		}
		if {!$::sndon} { unset ::track }
		return
	}
	incr frames
	if {$y < 8} { fail "bullet top above the playfield (line $y)" }
	set ::track [list $y0 $frames $y $snd]
}

proc screenshot_and_finish {} {
	# a bullet in flight for the picture
	down 0x01
	after time 0.1 {
		up 0x01
		set ::throttle on
		after realtime 0.1 {
			set ::pause on
			after realtime 0.3 { screenshot $::env(SHOT) ; set ::pause off ; finish }
		}
	}
}

# The splash, twice. Boot 1: space held from power-on, then let go, doesn't
# start; joystick 1's button A does; then a reset. Boot 2: the tables
# against title.py's picture, the blinking (every frame, and its times),
# other keys and button B mixing their times into entropy but not
# starting; space starts the game, and the plan above runs.
set ROOT [file dirname [file dirname $::env(SYMFILE)]]
set TITLE [exec sh -c "cd '$ROOT' && python3 title.py --raw"]
set BROW $sym(BLINK_ROW)
set phase 1
set sn 0
proc vdp_r1 {} { debug read "VDP regs" 1 }
# the blinking row's colours: 1 = the picture's, 0 = all black, -1 neither
proc blink_state {} {
	set pic 1 ; set blk 1
	set a [expr {0x2000 + $::BROW*256}]
	for {set i 0} {$i < 256} {incr i} {
		set v [debug read VRAM [expr {$a + $i}]]
		if {$v != "0x[lindex $::TITLE [expr {6144 + $::BROW*256 + $i}]]"} { set pic 0 }
		if {$v != 0x11} { set blk 0 }
	}
	expr {$pic ? 1 : ($blk ? 0 : -1)}
}
# VRAM's tables against the picture (the blinking row's colours as $shown)
proc check_title {shown what} {
	set bad {}
	for {set i 0} {$i < 12288} {incr i} {
		set w [expr 0x[lindex $::TITLE $i]]
		if {$i >= 6144 + $::BROW*256 && $i < 6144 + ($::BROW+1)*256 && !$shown} { set w 0x11 }
		set a [expr {$i < 6144 ? $i : 0x2000 + $i - 6144}]
		if {[debug read VRAM $a] != $w} { lappend bad [format %04X $a] ; if {[llength $bad] > 5} break }
	}
	check {[llength $bad] == 0} "splash $what: patterns and colours = images/title.png (wrong at: $bad)"
}
proc entropy {} { expr {[m entropy] + 256*[m entropy 1]} }
set blinks {}        ;# {state time} each splash frame
set frames_bad 0
proc splash_frame {} {
	incr ::sn
	set fr [m frames]
	if {$::sn > 1 && (($fr - $::last_fr) & 0xFF) != 1} { incr ::frames_bad }
	set ::last_fr $fr
	if {$::phase == 1} {
		if {$::sn == 4} { up 0x01 }
		if {$::sn == 8} { joydown 1 0x10 }
		if {$::sn == 12} { fail "joystick 1's button A doesn't start the game" ; finish }
		return
	}
	set F [m fps]
	lappend ::blinks [list [blink_state] [machine_info time]]
	if {$::sn == 3} {
		check {[vdp_r1] & 0x40} "splash: display on (R1 [format %02X [vdp_r1]])"
		check_title 1 "(text shown)"
	}
	if {$::sn == 5} { set ::e0 [entropy] ; keymatrixdown 2 0x40 }
	if {$::sn == 6} { set ::e1 [entropy] ; check {$::e1 != $::e0 && $::e1 != 0} "splash: A down mixes into entropy ([format %04X $::e0] -> [format %04X $::e1])" }
	if {$::sn == 9} { keymatrixup 2 0x40 }
	if {$::sn == 10} { set ::e2 [entropy] ; check {$::e2 != $::e1 && $::e2 != 0} "splash: A up mixes into entropy (-> [format %04X $::e2])" }
	if {$::sn == 13} { joydown 2 0x20 }
	if {$::sn == 14} { set ::e3 [entropy] ; check {$::e3 != $::e2} "splash: joystick 2's button B mixes into entropy, doesn't start (-> [format %04X $::e3])" ; joyup 2 }
	if {$::sn == 16} { cdown }
	if {$::sn == 17} { cup ; set ::e4 [entropy] ; check {$::e4 != $::e3} "splash: C mixes into entropy, doesn't start (-> [format %04X $::e4])" }
	if {$::sn > 1 && [lindex $::blinks end 0] == 0 && [lindex $::blinks end-1 0] == 1} {
		if {![info exists ::offchecked]} { set ::offchecked 1 ; check_title 0 "(text hidden)" }
	}
	if {$::sn == 3*$F} {
		say "splash: [expr {([m polls] + 256*[m polls 1]) / $::sn}] polls a frame"
		check_blinks $F
		down 0x01
	}
	if {$::sn == 3*$F + 4} { fail "space doesn't start the game" ; finish }
}
proc check_blinks {F} {
	set on [expr {$F*3/10}] ; set off [expr {$F/5}]
	set runs {} ; set times {}
	set prev "" ; set len 0
	foreach b $::blinks {
		lassign $b st t
		if {$st == -1} { fail "splash: the blinking row is neither the picture's nor black" ; return }
		if {$st != $prev && $prev ne ""} { lappend runs [list $prev $len] ; lappend times $t }
		if {$st != $prev} { set len 0 }
		set prev $st
		incr len
	}
	set bad 0
	foreach r $runs { lassign $r st len ; if {$len != ($st ? $on : $off)} { incr bad } }
	check {[llength $runs] >= 10 && $bad == 0 && [lindex $runs 0 0] == 1} "splash: text shown $on frames, hidden $off, in turn, from the start ($runs)"
	set tbad {}
	for {set i 2} {$i < [llength $times]} {incr i} {
		set d [expr {[lindex $times $i] - [lindex $times $i-2]}]
		if {abs($d - 0.5) > 0.002} { lappend tbad [format %.4f $d] }
	}
	check {[llength $tbad] == 0} "splash: blink period 0.5 s in emulated time (wrong: $tbad)"
	check {$::frames_bad == 0} "splash: the poll loop sees every frame, one at a time"
}
debug set_bp $sym(splash.blink) {} { try splash_frame }
# blank after the splash: the top status row, and the bottom one past the reserves
proc check_cleared {} {
	set bad {}
	for {set a 0} {$a < 256} {incr a} {
		if {[debug read VRAM $a] || [debug read VRAM [expr {0x2000 + $a}]] != 0x11} { lappend bad [format %04X $a] }
	}
	for {set a [expr {23*256 + $::sym(RESERVE_CELLS)*8}]} {$a < 6144} {incr a} {
		if {[debug read VRAM $a] || [debug read VRAM [expr {0x2000 + $a}]] != 0x11} { lappend bad [format %04X $a] }
	}
	check {[llength $bad] == 0} "after the splash: status rows blank (wrong: [lrange $bad 0 5])"
}

down 0x01            ;# boot 1: space held from power-on
set started 0
debug set_bp $sym(main_loop) {} {
	if {$::phase == 1} {
		check {$::sn >= 8} "joystick 1's button A starts the game; space held from power-on, then let go, didn't (splash frame $::sn)"
		joyup 1
		set ::phase 2 ; set ::sn 0
		reset
		return
	}
	if {!$::started} {
		check {$::sn == 3*[m fps]} "space starts the game (splash frame $::sn)"
		up 0x01
		set ::started 1 ; try plan
	}
	frame
}

# The formation, from the spec: its pairs (dx dy from its top left, in the
# picture images/formation-enemy-0-color-12.png, starting at column 25),
# starting with its top on line 66 (the loop centred between lines 8 and
# 168, the front's sprites); a loop at constant speed of four legs {dx dy}
# a cycle (FORM_TICKS / FORM_TICK_RATE s, path.py's CYCLE_SECS), 25 px east
# a cycle; x mod 272 (256 + a pair), a pair
# at 256..271 is at -16..-1 on screen (early clock)
set FPAIRS {{20 0} {55 8} {0 20} {35 28}}
set FLEGS {{35 -29} {60 29} {-35 29} {-35 -29}}
set FX0 25 ; set FY0 66 ; set FWRAP 272
# Path entries stepped after k frames (Bresenham: whole entries a frame)
proc form_ticks {k} { expr {$k * $::sym(FORM_TICK_RATE) / $::F} }
proc form_at {k} {
	# the formation's top left after k frames: {x (mod FWRAP) y}
	set T $::sym(FORM_TICKS)
	set tk [form_ticks $k]
	set cyc [expr {$tk / $T}]
	set s [expr {double($tk % $T) / $T}]
	set tot 0.0
	foreach l $::FLEGS { set tot [expr {$tot + hypot([lindex $l 0], [lindex $l 1])}] }
	set s [expr {$s * $tot}]
	set x 0.0 ; set y 0.0
	foreach l $::FLEGS {
		lassign $l dx dy
		set len [expr {hypot($dx, $dy)}]
		if {$s <= $len} { set x [expr {$x + $dx*$s/$len}] ; set y [expr {$y + $dy*$s/$len}] ; break }
		set s [expr {$s - $len}] ; set x [expr {$x + $dx}] ; set y [expr {$y + $dy}]
	}
	list [expr {($::FX0 + 25*$cyc + int(floor($x + 0.5))) % $::FWRAP}] [expr {$::FY0 + int(floor($y + 0.5))}]
}
# A pair's place from the SAT: {x (mod FWRAP) line name colour}
proc form_sat {i} {
	set b [expr {(5 + $i)*4}]
	set x [sat [expr {$b+1}]] ; set c [sat [expr {$b+3}]]
	if {$c & 0x80} { set x [expr {$x - 32}] }
	list [expr {$x < 0 ? $x + $::FWRAP : $x}] [expr {[sat $b] + 1}] [sat [expr {$b+2}]] $c
}
proc wdiff {a b} { expr {($a - $b + 3*$::FWRAP/2) % $::FWRAP - $::FWRAP/2} }

set form_bad 0 ; set form_first "" ; set form_frames 0 ; set form_err 0
set form_left 0 ; set form_right 0 ; set form_laps 0 ; set form_lapbad 0
set form_ymin 999 ; set form_ymax 0 ; set form_hist [dict create]
proc form_bad {s} { if {!$::form_bad} { set ::form_first "frame $::n: $s" } ; incr ::form_bad }
proc form_frame {} {
	if {$::n < 2} return
	# VRAM holds the SAT built after n - 2 frames' moves
	set k [expr {$::n - 2}]
	lassign [form_at $k] wx wy
	set p0 [form_sat 0]
	set x0 [expr {[lindex $p0 0] - [lindex $::FPAIRS 0 0]}]
	set y0 [expr {[lindex $p0 1] - [lindex $::FPAIRS 0 1]}]
	set e [expr {abs([wdiff $x0 $wx])}]
	if {abs($y0 - $wy) > $e} { set e [expr {abs($y0 - $wy)}] }
	if {$e > $::form_err} { set ::form_err $e }
	if {$e > 1} { form_bad "top left ($x0, $y0), want ($wx, $wy)" }
	if {$y0 < 8 || $y0 + 44 > $::sym(SHIP_TOP)} { form_bad "lines $y0..[expr {$y0+43}]" }
	if {$y0 < $::form_ymin} { set ::form_ymin $y0 }
	if {$y0 > $::form_ymax} { set ::form_ymax $y0 }
	set i 0
	foreach p $::FPAIRS {
		lassign [form_sat $i] x y nm c
		lassign $p dx dy
		if {[wdiff $x [expr {$x0 + $dx}]] != 0 || $y != $y0 + $dy} { form_bad "pair $i at ($x, $y), not at ($dx, $dy) from pair 0's place" }
		if {$nm != $::sym(NAME_ENEMY) || ($c & 0x7F) != [m form_color]} { form_bad "pair $i name $nm colour [format %02X $c]" }
		if {$x > 256} { incr ::form_left }   ;# -15..-1: partly in at the left
		if {$x < 256 && $x > 240} { incr ::form_right }
		incr i
	}
	# a cycle later: 25 px east, the same lines
	set tk [form_ticks $k]
	dict set ::form_hist $tk [list $x0 $y0]
	set tp [expr {$tk - $::sym(FORM_TICKS)}]
	if {[dict exists $::form_hist $tp]} {
		lassign [dict get $::form_hist $tp] px py
		incr ::form_laps
		if {[wdiff $x0 $px] != 25 || $y0 != $py} { incr ::form_lapbad ; form_bad "a cycle after ($px, $py): ($x0, $y0)" }
	}
	incr ::form_frames
}
# rand (16-bit xorshift 7/9/8): {h l} -> {h l byte}
proc xs {h l} {
	set h1 [expr {((($h & 1) << 7) | ($l >> 1)) ^ $h}]
	set l1 [expr {((($l & 1) << 7) | ($h1 >> 1)) ^ $l}]
	set h2 [expr {$l1 ^ $h1}]
	list $h2 $l1 $h2
}
# The enemy and colour the game picked: rand seeded from entropy, the
# enemy (rand & 15) < 10, then the colour's index (rand & 15) < 9 into
# the spec's list
proc check_form_pick {} {
	set COLS {2 3 5 7 8 9 10 11 13}
	set h [m entropy 1] ; set l [m entropy]
	if {!$h && !$l} { set l 1 }
	while 1 { lassign [xs $h $l] h l r ; if {($r & 15) < 10} break }
	set e [expr {$r & 15}]
	while 1 { lassign [xs $h $l] h l r ; if {($r & 15) < 9} break }
	set c [lindex $COLS [expr {$r & 15}]]
	check {[m form_enemy] == $e && [m form_color] == $c} "formation picked from entropy [format %04X [entropy]]: enemy [m form_enemy], colour [m form_color] (want enemy $e, colour $c)"
}
proc check_form_pattern {} {
	set a [expr {0x3800 + $::sym(NAME_ENEMY)*8}]
	set e [m form_enemy]
	set bad {}
	for {set i 0} {$i < 32} {incr i} {
		if {[debug read VRAM [expr {$a + $i}]] != [m ENEMY_PATTERN [expr {$e*32 + $i}]]} { lappend bad $i }
		if {$i < 16 && [debug read VRAM [expr {$a + $i}]] != [debug read VRAM [expr {$a + $i + 16}]]} { lappend bad "half $i" }
	}
	check {[llength $bad] == 0} "the formation's pair in VRAM: enemy [m form_enemy], twice side by side (wrong: $bad)"
}
proc check_form_end {} {
	check {$::form_bad == 0 && $::form_frames > 10*$::F} "formation = the spec's loop ([format %.3f [expr {double($::sym(FORM_TICKS)) / $::sym(FORM_TICK_RATE)}]] s, constant speed, 25 px east a cycle), pairs in the picture's layout, colour [m form_color], every frame ($::form_frames frames, off by $::form_err px at most; [expr {$::form_bad ? "first wrong: $::form_first" : "none wrong"}])"
	check {$::form_laps > 0 && $::form_lapbad == 0} "a cycle later the formation is 25 px east on the same lines ($::form_laps frames checked)"
	check {$::form_ymin >= 8 && $::form_ymax + 44 <= $::sym(SHIP_TOP) && $::form_ymin <= 39 && $::form_ymax >= 93} "formation's top from line $::form_ymin to $::form_ymax: between the status area and the front's sprites"
	check {$::form_left > 0 && $::form_right > 0} "pairs leaving the right edge ($::form_right pair-frames) come back in from the left, early clock ($::form_left)"
}
