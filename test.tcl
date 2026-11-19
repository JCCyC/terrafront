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
proc sat {i} { debug read VRAM [expr {0x1B00 + $i}] }
proc vol {} { debug read "PSG regs" 8 }

# Keyboard row 8: space 01h, left 10h, right 80h; C is row 3, 01h
proc down {bits} { keymatrixdown 8 $bits }
proc up {bits} { keymatrixup 8 $bits }
proc cdown {} { keymatrixdown 3 0x01 }
proc cup {} { keymatrixup 3 0x01 }
# Joysticks: a breakpoint right after read_joy's R14 read clears the held
# lines (bit 4 = button A, 5 = B) of port 1 (B = 03h) or 2 (B = 4Ch)
set joy(1) 0
set joy(2) 0
proc joydown {port bits} { set ::joy($port) $bits }
proc joyup {port} { set ::joy($port) 0 }
debug set_bp $sym(read_joy.r14) {} {
	set p [expr {[reg B] == 0x03 ? 1 : 2}]
	if {$::joy($p)} { reg A [expr {[reg A] & ~$::joy($p) & 0xFF}] }
}
set VOL $sym(VOLLEY)
set W $sym(SHIP_ART_W)

set n 0
set steps {}        ;# list of {frame script}
proc at {frame body} { lappend ::steps [list $frame $body] }

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
	try check_sat
	try check_bitmap
	try call_frame
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
		check {$::bitmap_bad == 0 && $::bitmap_lit > 0} "bitmap = the bullets in flight, every frame ($::bitmap_frames frames, $::bitmap_lit bullet pixels seen; [expr {$::bitmap_bad ? "first wrong: $::bitmap_first" : "none wrong"}])"
		check {$::sat_bad == 0} "sprites = the front and the incoming ship, every frame ($::sat_frames frames; [expr {$::sat_bad ? "first wrong: $::sat_first" : "none wrong"}])"
		check {$::coming_seen > 0} "the incoming ship's sprite showed on $::coming_seen frames"
	}
	at [expr {$a+10}] { screenshot_and_finish }
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
		set ::cur [list [m call_left] [m call_rem] [m call_target]]
		set ::curx [m ship_x]
		set ::lastrem [m call_rem]
		set ::cursteps {}
		set ::curframes 0
		set ::curfrozen 1
	} elseif {$::incall} {
		incr ::curframes
		set rem [expr {$on ? [m call_rem] : 0}]
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
			lappend r [expr {$::sym(SHIP_TOP) - 1}] [expr {$sx < 0 ? $sx + 32 : $sx}] 0 [expr {$sx < 0 ? 0x8F : 0x0F}]
		} else { lappend r 0xC0 - - - }
	}
	if {[m call_on]} {
		set t [m call_target] ; set rem [m call_rem]
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

# Every frame: the bitmap's playfield and top status rows (lines 0..183)
# hold exactly the volleys' bullets, BULLET_COLOR on black
set bitmap_bad 0
set bitmap_frames 0
set bitmap_lit 0
proc check_bitmap {} {
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
	set blk [debug read_block VRAM 0 [expr {23*256}]]
	set got [dict create]
	foreach p [regexp -all -indices -inline {[^\x00]} $blk] {
		set a [lindex $p 0]
		binary scan [string index $blk $a] cu b
		dict set got $a $b
	}
	incr ::bitmap_frames
	incr ::bitmap_lit [dict size $got]
	set bad {}
	dict for {a b} $want { if {![dict exists $got $a] || [dict get $got $a] != $b} { lappend bad $a } }
	dict for {a b} $got { if {![dict exists $want $a]} { lappend bad $a } }
	foreach a [dict keys $want] {
		if {[debug read VRAM [expr {0x2000 + $a}]] != 0xF1} { lappend bad "colour $a" }
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

set started 0
debug set_bp $sym(main_loop) {} {
	if {!$::started} { set ::started 1 ; try plan }
	frame
}
