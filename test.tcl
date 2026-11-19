# Headless check of the player ship step. Env: LOGFILE, SYMFILE, SHOT.
# Driven by a breakpoint at main_loop (once a frame, before its halt: the
# frame's work is done, VRAM holds the previous frame's SAT).
after time 120 { fail "timeout" ; finish }
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

# Keyboard row 8: space 01h, left 10h, right 80h
proc down {bits} { keymatrixdown 8 $bits }
proc up {bits} { keymatrixup 8 $bits }

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
	# every frame: never more than MAX_BULLETS in flight, the bullet's sound in step
	set live 0
	for {set i 0} {$i < 2} {incr i} { if {[m bullets [expr {$i*3}]]} { incr live } }
	if {$live > $::maxlive} { set ::maxlive $live }
	if {[info exists ::track]} { try track_frame }
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
		set y [m bullets 0] ; set x [m bullets 1]
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
	at [expr {$a+$F+3}] { screenshot_and_finish }
}

# The single shot: its Y each frame, until gone; the PSG channel A volume
proc track_frame {} {
	lassign $::track y0 frames last snd
	set y [m bullets 0]
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
