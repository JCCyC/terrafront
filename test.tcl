# Headless check of the front. Env: LOGFILE, SYMFILE, SHOT (and SHOT with
# -call before .png: a call-up in flight), IMAGE (the game's file, under
# SYMFILE's project dir: terrafnt.rom, the default, or the disk's
# terrafnt.bin, with SYMFILE build/terrafnt-bin.sym).
# Driven by a breakpoint at main_loop (once a frame, before its halt: the
# frame's work is done, VRAM holds the previous frame's SAT).
after time 600 { fail "timeout" ; finish }
set save_settings_on_exit off
set throttle off

set log [open $::env(LOGFILE) w]
set fails 0
proc say {s} { puts $::log $s ; flush $::log }
proc fail {s} { incr ::fails ; say "FAIL: $s" }
proc ok {s} { say "ok: $s" }
proc check {cond s} { if {[uplevel 1 [list expr $cond]]} { ok $s } else { fail $s } }
proc finish {} {
	say [format "emulated time %.1f s" [machine_info time]]
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
# Breakpoints go by address, not slot: while the BIOS boots, page 1 holds
# MSX BASIC's ROM, whose code can pass the game's addresses. cart_bp's
# body runs only when the game is there ("AB" at CODE_BASE: 4000h, the
# cartridge in page 1; the BIN: 8000h, BLOADed into page 2's RAM).
proc cart {} { expr {[debug read memory $::sym(CODE_BASE)] == 0x41 && [debug read memory [expr {$::sym(CODE_BASE) + 1}]] == 0x42} }
proc cart_bp {addr cond body} { debug set_bp $addr $cond [list if {[cart]} $body] }
proc rem {} { expr {[m call_rem] + 256*[m call_rem 1]} }
proc sat {i} { debug read VRAM [expr {0x1B00 + $i}] }
# Byte b of SAT entry e as built (0..12: the front's slots, the incoming
# ship, the enemies), where the SAT shown has it (every other frame the
# list is reversed: ::flipp, the SAT shown's)
proc sate {e b} { sat [expr {($::flipp ? 12 - $e : $e)*4 + $b}] }
set flipp 0
proc vol {} { debug read "PSG regs" 8 }
proc psg {r} { debug read "PSG regs" $r }

# Keyboard row 8: space 01h, left 10h, right 80h; C is row 3, 01h
proc down {bits} { keymatrixdown 8 $bits }
proc up {bits} { keymatrixup 8 $bits }
proc cdown {} { keymatrixdown 3 0x01 }
proc cup {} { keymatrixup 3 0x01 }
# Ships killed by the test: tkill k.. makes the front's kth living ships
# (1.., from the left) start to die this frame, before move_bullets (a
# breakpoint there calls ship_dies, the game's own, once per ship, from
# the highest k down, so that a kill doesn't renumber the rest); a k with
# no such ship does nothing (ship_dies's breakpoint doesn't fire when the
# PC is set to it: its work, on_ship_dies, is done here)
set tkills {}
proc tkill {args} { set ::tkills [lsort -integer -decreasing -unique [concat $::tkills $args]] }
cart_bp $sym(move_bullets) {} {
	while {[llength $::tkills]} {
		set k [lindex $::tkills 0] ; set ::tkills [lrange $::tkills 1 end]
		set slot -1
		for {set i 0} {$i < 4} {incr i} {
			if {([m front_mask] >> $i & 1) && ![m boom_stage $i] && [incr k -1] == 0} { set slot $i ; break }
		}
		if {$slot < 0} continue
		set sp [expr {[reg sp] - 2}]
		poke16 $sp $::sym(move_bullets) ; reg sp $sp
		reg HL [expr {$::sym(boom_stage) + $slot}]
		reg pc $::sym(ship_dies)
		on_ship_dies
		break
	}
}
# Joysticks: a breakpoint right after joy_r14's R14 read clears the held
# lines (bit 4 = button A, 5 = B) of port 1 (B = 03h) or 2 (B = 4Ch)
set joy(1) 0
set joy(2) 0
proc joydown {port bits} { set ::joy($port) $bits }
proc joyup {port} { set ::joy($port) 0 }
cart_bp $sym(joy_r14.r14) {} {
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
cart_bp $sym(death_start) {} { incr ::dnew }  ;# each call (two booms can start in one frame)
# The break sound: brk_start (re)starts it; brk_frame checks channel B
set bnew 0 ; set bidx -1 ; set bruns {} ; set bstarts 0
set bbad 0 ; set bframes 0 ; set bfirst ""
set brk_all 0 ; set brk_seen 0
cart_bp $sym(brk_start) {} { incr ::bnew ; incr ::brk_all }  ;# each call (two pairs can break up in one frame)
# The bonus ship: BONUS_WAVES (2) waves in a row finished (next_wave.done:
# the frame's work that made the last enemy gone) with no ship lost
# (ship_dies) gain a reserve ship, if under RESERVE_MAX (4) and not game
# over; that frame the reserve shows it and the happy beep starts
# (bonus_start), every frame of it on channel A as the BONUS table (tone
# only), the shot (if one runs) unheard
set blost 0 ; set bstreak 0 ; set bwant {} ; set bseq {} ; set bonew 0
set bonus_bad 0 ; set bonus_first "" ; set b_awards 0 ; set b_vram 0
set beepidx -1 ; set beepruns {} ; set beepframes 0 ; set beepshot 0
proc bonus_bad {s} { if {!$::bonus_bad} { set ::bonus_first "frame $::n: $s" } ; incr ::bonus_bad }
cart_bp $sym(new_game) {} { set ::blost 0 ; set ::bstreak 0 }
cart_bp $sym(bonus_start) {} { incr ::bonew }
cart_bp $sym(next_wave.done) {} {
	set lost $::blost ; set ::blost 0 ; set award 0 ; set r [m reserves]
	if {$lost} { set what lost ; set ::bstreak 0 } else {
		incr ::bstreak ; set what $::bstreak
		if {$::bstreak >= $::sym(BONUS_WAVES)} {
			set ::bstreak 0
			if {[m over_on]} { set what over } elseif {$r < $::sym(RESERVE_MAX)} { set award 1 ; set what "+1" } else { set what full }
		}
	}
	set ::bwant [list [expr {$r + $award}] $award]
	lappend ::bseq "[m wave_n]:$what"
}
proc bonus_frame {} {
	if {[llength $::bwant]} {
		lassign $::bwant r a
		if {[m reserves] != $r || $::bonew != $a} { bonus_bad "a wave finished: [m reserves] in reserve, $::bonew beeps, want $r, $a" }
		if {$a} {
			incr ::b_awards
			set bad [reserves_bad $r]
			if {[llength $bad]} { bonus_bad "the reserve after a bonus ship isn't $r ships (wrong: [lrange $bad 0 5])" } else { incr ::b_vram }
		}
		set ::bwant {}
	} elseif {$::bonew} { bonus_bad "$::bonew beeps with no wave finished" }
	if {$::bonew} { set ::beepidx 0 ; set ::bonew 0 }
	if {$::beepidx < 0} return
	set mix [psg 7]
	set t [expr {$::sym(BONUS_$::F) + 3*$::beepidx}]
	set v [debug read memory $t]
	if {$v == 0} {
		lappend ::beepruns $::beepidx ; set ::beepidx -1
		if {[vol] && ![m sfx_ptr] && ![m sfx_ptr 1]} { bonus_bad "the beep over, channel A at volume [vol], no shot playing" }
		return
	}
	set got [list [vol] [psg 0] [psg 1] [expr {$mix & 0x09}]]
	set want [list $v [debug read memory [expr {$t+1}]] [debug read memory [expr {$t+2}]] 8]
	if {$got != $want} { bonus_bad "the beep's frame $::beepidx: R8 R0 R1 mix-A $got, want $want" }
	if {[m sfx_ptr] || [m sfx_ptr 1]} { incr ::beepshot }
	incr ::beepframes ; incr ::beepidx
}

# Hits are off (volley_hits returns at once) until the enemies' part
set nohits 1 ; set nohits_was 1
cart_bp $sym(volley_hits) {} {
	if {$::nohits} { reg pc [peek16 [reg sp]] ; reg sp [expr {[reg sp] + 2}] }
}

set spawns 0
set fresh -1        ;# the volley slot fire filled this frame
# The front as the game has it: {front_mask ship_x {boom_stage 0..3}}
proc front_now {} {
	set st {}
	for {set k 0} {$k < 4} {incr k} { lappend st [m boom_stage $k] }
	list [m front_mask] [m ship_x] $st
}
cart_bp $sym(fire.free) {} {
	incr ::spawns ; set ::fresh [expr {([reg HL] - $::sym(volleys)) / $::sym(VOLLEY)}]
	set ::fsnap [front_now]     ;# the front the volley comes from
}
# The front when collide begins (after the moves, call-up and trims)
set cfront {0 0 {0 0 0 0}}
cart_bp $sym(collide) {} { set ::cfront [front_now] ; set ::in_col 1 }

# The score, from the spec: a break-up 50 points, a free enemy's death
# (shot or crashing) 100, times the front's share by its living ships
# (1: 100%, 2: 80%, 3: 60%, 4: 50%; none as one): those before the hit
# (a bullet's: the front then; a crash's: as collide began). Each
# score_add call (a breakpoint) against the front then; every frame the
# calls against the enemies' state changes (pairs broken, enemies booming),
# the score in RAM (BCD) against the model's sum (99999999 at most), and
# on frames it changed (and the next) its cells on the top status row
set SHARES {100 100 80 60 50}
set sc_boss 0
set score_model 0 ; set sc_calls {} ; set in_col 0 ; set sc_prev {}
set sc_bad 0 ; set sc_first "" ; set sc_shown 0 ; set sc_hist [dict create] ; set sc_vram 0
proc sc_bad {s} { if {!$::sc_bad} { set ::sc_first "frame $::n: $s" } ; incr ::sc_bad }
proc living {fr} {
	lassign $fr mask x st
	set a 0
	for {set k 0} {$k < 4} {incr k} { if {($mask >> $k & 1) && [lindex $st $k] == 0} { set a [expr {$a | 1 << $k}] } }
	return $a
}
proc ships_in {a} { set c 0 ; for {set k 0} {$k < 4} {incr k} { incr c [expr {$a >> $k & 1}] } ; return $c }
# (the boss's bonus: with the front's living ships as it died, kept in
# boss_alive; boss_frame checks that against its death)
cart_bp $sym(score_add) {} {
	if {!$::started} return
	set kind [expr {[reg B] == $::sym(PTS_BREAK) ? "break" : ([reg B] == $::sym(PTS_FREE) ? "free" : ([reg B] == $::sym(PTS_BOSS) ? "boss" : "?[reg B]"))}]
	if {$kind eq "boss"} {
		set want [m boss_alive] ; set col 0
	} else {
		set want [living [expr {$::in_col ? $::cfront : [front_now]}]] ; set col $::in_col
	}
	if {[reg A] != $want} { sc_bad "score_add ($kind, [expr {$col ? "a crash" : "a bullet"}]) with ships [reg A], want $want" }
	lappend ::sc_calls [list $kind [ships_in $want] $col]
}
proc score_str {v} { format %8d $v }
proc score_ram {} {
	set v 0
	for {set k 3} {$k >= 0} {incr k -1} { set v [expr {$v*100 + [scan [format %02x [m score $k]] %d]}] }
	return $v
}
proc score_vram_bad {} { text_bad $::sym(SCORE_ROW) $::sym(SCORE_COL) [score_str $::score_model] $::sym(SCORE_LEN) }
proc en_sts {} { set l {} ; for {set i 0} {$i < 8} {incr i} { lappend l [m enemies [expr {$i*$::sym(EN) + $::sym(EN.ST)}]] } ; return $l }
set cheat_wipe 0 ; set b2_vanished 0
cart_bp $sym(cheat_boss) {} { set ::cheat_wipe 1 }
proc score_frame {} {
	set now [en_sts]
	set breaks 0 ; set frees 0
	if {[llength $::sc_prev]} {
		set f0 [m boom_frames]
		for {set i 0} {$i < 8} {incr i} {
			set p [lindex $::sc_prev $i] ; set c [lindex $now $i]
			# (a pair gone at once, Boss2's vanish, isn't a break)
			if {$i % 2 == 0 && $p == 0 && $c != 0 && $c != 5} { incr breaks }
			# a boom begun this frame: its first image, its full count (Boss2
			# moves a free or booming enemy to another record)
			if {$c == 2 && [m enemies [expr {$i*$::sym(EN) + $::sym(EN.LEFT)}]] == $f0} { incr frees }
		}
	}
	if {$::cheat_wipe} { set breaks 0 ; set frees 0 ; set ::cheat_wipe 0 }   ;# (the cheat key 1: the wave's enemies gone, no points)
	set vanish $::b2_vanished ; set ::b2_vanished 0   ;# (Boss2 died: its enemies gone, hit or not this frame)
	set nb 0 ; set nf 0 ; set ::sc_boss 0 ; set old $::score_model
	foreach c $::sc_calls {
		lassign $c kind ships col
		set pct [lindex $::SHARES $ships]
		if {$kind eq "break"} { incr nb ; set pts [expr {50*$pct/100}] } elseif {$kind eq "free"} { incr nf ; set pts [expr {100*$pct/100}] } elseif {$kind eq "boss"} { incr ::sc_boss ; set pts [expr {500*$pct/100}] } else { sc_bad "score_add with B = $kind" ; continue }
		dict incr ::sc_hist "$kind/$ships[expr {$col ? "/crash" : ""}]"
		set ::score_model [expr {$::score_model + $pts > 99999999 ? 99999999 : $::score_model + $pts}]
	}
	if {!$vanish && ($nb != $breaks || $nf != $frees)} { sc_bad "$nb break-up and $nf free scores, want $breaks and $frees (states [lrange $::sc_prev 0 end] -> $now)" }
	if {[score_ram] != $::score_model} { sc_bad "score [score_ram] in RAM, want $::score_model" }
	if {[m score_dirty]} { sc_bad "the score changed but wasn't shown" }
	if {$::score_model != $old || $::sc_shown} {
		set bad [score_vram_bad]
		if {[llength $bad]} { sc_bad "the score's cells aren't \"[score_str $::score_model]\" (wrong: [lrange $bad 0 5])" }
		incr ::sc_vram
	}
	set ::sc_shown [expr {$::score_model != $old}]
	set ::sc_calls {} ; set ::in_col 0
}
proc score_end {} {
	set h {}
	foreach k [lsort [dict keys $::sc_hist]] { lappend h "$k: [dict get $::sc_hist $k]" }
	check {$::sc_bad == 0 && [llength [dict filter $::sc_hist key break/*]] && [llength [dict filter $::sc_hist key free/?]] && [llength [dict filter $::sc_hist key */crash]]} "the score: every score_add with the front's living ships before the hit, one a pair broken and one an enemy booming, the score in RAM the spec's sum every frame, its cells on the top status row's right on the $::sc_vram frames it changed and the next (kind/ships, /crash for a crash: $h; [expr {$::sc_bad ? "first wrong: $::sc_first" : "none wrong"}])"
}

proc frame {} {
	incr ::n
	if {!$::attr} {
		try score_frame     ;# (before the steps and stagings: they may write the enemies)
		try bonus_frame     ;# (before them: they may write the reserve)
	}
	set due {} ; set rest {}
	foreach s $::steps { if {[lindex $s 0] == $::n} { lappend due $s } else { lappend rest $s } }
	set ::steps $rest   ;# (before running them: a step may plan more)
	foreach s $due { try [lindex $s 1] }
	# every frame: never more than MAX_VOLLEYS in flight, the bullet's sound in step
	set live 0
	for {set i 0} {$i < $::sym(MAX_VOLLEYS)} {incr i} { if {[m volleys [expr {$i*$::VOL}]]} { incr live } }
	if {$live > $::maxlive} { set ::maxlive $live }
	if {[info exists ::track]} { try track_frame }
	if {[info exists ::emptywatch]} { try empty_frame }
	if {$::ostate ne ""} { try over_frame }
	if {[info exists ::bw]} { lappend ::bw [list [sate $::bwslot 0] [sate $::bwslot 2]] }
	if {$::eb_expect ne ""} { eb_bad "a roll for a bullet hit, with room and enemies able to shoot ($::eb_expect), but none fired" ; set ::eb_expect "" }
	set ::eb_rolled_now $::eb_rolled ; set ::eb_rolled 0
	if {$::bwatch} { try boss_frame }   ;# (before eb_frame: its spawns)
	if {$::ebon} { try eb_frame }
	if {[info exists ::lv_on]} { try lv_frame }
	if {$::cs_on} { try cs_frame }
	if {$::nocheck && $::ebon} { try check_bitmap }
	if {!$::nocheck} {
		try vis_frame
		try check_sat
		try star_frame
		try check_bitmap
		try call_frame
		try death_frame
		try brk_frame
		try form_frame
		try enemy_frame
	}
	if {$::ephase} { try aim_frame }
	if {$::attr} { try attract_frame }
	set ::sc_prev [en_sts]     ;# (after the steps and stagings that write the enemies)
	set ::nohits_was $::nohits
	set fr [m frames]
	if {[info exists ::last_frames] && (($fr - $::last_frames) & 255) != 1} { incr ::dropped ; if {$::ephase} { incr ::edropped ; lappend ::edrops $::n } }
	set ::last_frames $fr
}
set dropped 0 ; set edropped 0 ; set edrops {} ; set ephase 0 ; set flip_bad 0 ; set nocheck 0
set ostate ""
set maxlive 0

proc plan {} {
	set F [m fps]
	set ::F $F
	set ::wdelay [expr {$::sym(WAVE_DELAY_MS) * $F / 1000}]
	set ::bstart [expr {$::sym(BULLET_START)}]
	ship_px_init
	set ::ebon 1
	say "fps $F"
	set x0 [m ship_x]
	check {$x0 == $::sym(SHIP_X_MAX)/2} "ship starts in the middle (x $x0)"
	at 3 { check {[sate 0 0] == $::sym(SHIP_TOP) - 1} "ship sprite Y [sate 0 0] (art's last row on line 183)" }
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
		check {[sate 0 1] == 29 && [sate 0 3] == 0x8F} "left edge sprite: X [sate 0 1] colour [format %02X [sate 0 3]] (EC, art at column 0)"
	}
	# 3 s of right: clamped at SHIP_X_MAX, art's right column on 255
	set a [expr {$a+3*$F+5}]
	at $a { down 0x80 }
	at [expr {$a+3*$F}] {
		up 0x80
		check {[m ship_x] == $::sym(SHIP_X_MAX)} "right edge: ship_x [m ship_x]"
	}
	at [expr {$a+3*$F+2}] {
		check {[sate 0 1] == 244 && [sate 0 3] == 0x0F} "right edge sprite: X [sate 0 1] colour [format %02X [sate 0 3]]"
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
	plan_pause [expr {$a+$F+5}]
}

# The pause, with a volley in flight and its sound playing: F1 pressed
# (and let go): the next frame the main loop stops; 1 s on, PAUSED centred
# on the top status row (white), the PSG silent (R8..R10), nothing moved
# (the volley, the front, the stars, the formation, the sound's place), no
# main loop pass; STOP pressed: the frame after the main loop's next pass,
# the text gone (the row as before), the volley one frame's step on, the
# sound one table entry on and heard again
proc pause_snap {} {
	list [m volleys 0] [m volleys 1] [m ship_x] [star_list] [w16 form_x] [w16 form_tick] [w16 sfx_ptr] [en_sts]
}
proc plan_pause {a} {
	at $a { down 0x01 }
	at [expr {$a+1}] { up 0x01 }
	at [expr {$a+3}] {
		set ::psnap [pause_snap] ; set ::pn $::n ; set ::pmid 0
		keymatrixdown 6 0x20
		after time 0.1 { keymatrixup 6 0x20 }
		after time 1.0 { try pause_mid }
	}
	at [expr {$a+4}] {
		set bad [lw_bad "L1 W1"]
		lassign $::psnap y0 x0 sx st fx ft sp
		set step [m bullet_step]
		check {$::pmid && ![llength $bad] && [m volleys 0] == $y0 - $step && [m volleys 1] == $x0 && [m ship_x] == $sx && [w16 sfx_ptr] == $sp + 4 && [vol] > 0} "STOP ends the pause: PAUSED gone (wrong: [lrange $bad 0 5]), the volley one step on (Y [m volleys 0], from $y0 by $step), the shot sound one entry on and heard (volume [vol])"
		unset ::last_frames    ;# (the pause's frames aren't dropped ones)
	}
	plan_calls [expr {$a+10}]
}
proc pause_mid {} {
	set ::pmid 1
	set bad [text_bad $::sym(PAUSE_ROW) $::sym(PAUSE_COL) "PAUSED" 6]
	check {$::sym(PAUSE_COL) == 13 && ![llength $bad]} "F1 pauses: PAUSED centred on the top status row, white (wrong: [lrange $bad 0 5])"
	check {[psg 8] == 0 && [psg 9] == 0 && [psg 10] == 0} "paused: the PSG silent (R8..R10 [psg 8] [psg 9] [psg 10])"
	check {$::n == $::pn && [pause_snap] eq $::psnap} "paused 1 s: no main loop pass, nothing moved"
	keymatrixdown 7 0x10
	after time 0.1 { keymatrixup 7 0x10 }
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
		check {[sate 1 1] == 256 - $::W - 3 && [sate 1 3] == 0x0F} "second ship's sprite at the right edge: X [sate 1 1] colour [format %02X [sate 1 3]]"
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

# Kills (tkill): deaths, booms, holes, trims, the call-up rule on the
# front's span, an emptied front. Start: four ships at the right edge, 1 in
# reserve; the test gives the game more reserves (in RAM only: the status
# row isn't redrawn) so that the call-ups below can run.
proc plan_kills {a} {
	set F $::F
	at $a {
		check {[m front_mask] == 15 && [m ship_x] == 256 - 4*$::W} "kills start: four ships at the right edge"
		debug write memory $::sym(reserves) 3
		set ::bwslot 1 ; set ::bw {}
		tkill 2
	}
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
		check {$runs eq $want} "kill 2: ship 2's boom in the SAT, name and frames: $runs (want $want)"
		check {[m front_mask] == 13 && [m front_slots] == 4 && [m ship_x] == 256 - 4*$::W} "ship 2 gone, a hole: mask [m front_mask], [m front_slots] slots, ship_x [m ship_x]"
		tkill 2
	}
	# kill 2 again: the second ship is now slot 2; ship-gap-gap-ship can't call up
	at [expr {$a+46}] {
		check {[m front_mask] == 9 && [m front_slots] == 4} "kill 2 again: ship-gap-gap-ship (mask [m front_mask], [m front_slots] slots)"
		set ::calls {} ; cdown
	}
	at [expr {$a+47}] { cup }
	at [expr {$a+50}] {
		check {[m call_on] == 0 && [llength $::calls] == 0 && [m reserves] == 3} "ship-gap-gap-ship: C does nothing (span 4, 3 in reserve)"
		tkill 4
	}
	# kill 4 with two ships: nothing
	at [expr {$a+53}] {
		set st [list [m boom_stage 0] [m boom_stage 1] [m boom_stage 2] [m boom_stage 3]]
		check {[m front_mask] == 9 && $st == {0 0 0 0}} "kill 4 with two ships: no death (mask [m front_mask], stages $st)"
		tkill 1
	}
	# kill 1: the first ship dies, the front is trimmed to the last one
	at [expr {$a+74}] {
		check {[m front_mask] == 1 && [m front_slots] == 1 && [m front_w] == $::W && [m ship_x] == 256 - $::W} "kill 1: trimmed to the last ship (mask [m front_mask], ship_x [m ship_x], [m front_w] px)"
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
		tkill 2
	}
	# ship-gap-ship calls up from the left ...
	at [expr {$b+26}] {
		check {[m front_mask] == 5 && [m front_slots] == 3} "kill 2: ship-gap-ship (mask [m front_mask])"
		set ::calls {} ; cdown
	}
	at [expr {$b+27}] { cup }
	set b [expr {$b+26+$F/2}]
	at $b {
		check_call 1 [expr {256 - 3*$::W}] [expr {256 - 4*$::W}] 4
		check {[m front_mask] == 11 && [m reserves] == 0} "ship-gap-ship: one more from the left (mask [m front_mask])"
		debug write memory $::sym(reserves) 1
		tkill 1
	}
	# ... and, at the left edge, from the right
	at [expr {$b+26}] {
		check {[m front_mask] == 5 && [m ship_x] == 256 - 3*$::W} "kill 1: trimmed to ship-gap-ship (mask [m front_mask], ship_x [m ship_x])"
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
		debug write memory $::sym(reserves) 1
		tkill 3
	}
	# kills 3, 2, 1: all three die; the frame the front is empty (where its
	# last died), the last reserve (1, written in RAM) is called up by
	# itself, no C pressed (empty_frame)
	at [expr {$b+3}] { tkill 2 }
	at [expr {$b+6}] { tkill 1 }
	at [expr {$b+7}] { set ::calls {} ; set ::emptywatch 1 }
	at [expr {$b+40}] { if {[info exists ::emptywatch]} { fail "kills 3, 2, 1: the front never emptied (mask [m front_mask])" ; unset ::emptywatch } }
	# the last death sound plays out
	at [expr {$b+5+$F*3/2}] {
		set want [expr {$::F == 60 ? 84 : 70}]
		check {$::dstarts >= 8 && $::didx == -1 && [lindex $::druns end] == $want} "death sound: $::dstarts starts, the last plays out in [lindex $::druns end] frames (want $want, 1.4 s; runs $::druns)"
		check {$::dbad == 0 && $::dframes > 0} "death sound on channel C = DEATH table, every frame ($::dframes frames playing, $::dclash with the shot's noise on too; [expr {$::dbad ? "first wrong: $::dfirst" : "none wrong"}])"
	}
	at [expr {$b+8+$F*3/2}] { plan_enemies }
}

# Every frame from kills 3, 2, 1 on: the frame the front is empty, a
# call-up starts by itself (the last reserve); meanwhile the front can't
# move or shoot (right held, fire pressed); it lands where the last died
proc empty_frame {} {
	if {[m front_mask]} return
	unset ::emptywatch
	check {[m front_slots] == 0 && [m front_w] == 0 && [m ship_x] == 0} "kills 3, 2, 1: the front is empty at x [m ship_x]"
	check {[m call_on] && ![m call_left] && [rem] == 256 && [m call_target] == 0 && [m reserves] == 0} "the front emptied: a call-up starts that frame by itself, no C pressed (on [m call_on], from the [expr {[m call_left] ? "left" : "right"}], [rem] px, target [m call_target], [m reserves] left in reserve)"
	set ::spawns 0
	down 0x80
	at [expr {$::n+1}] { down 0x01 }
	at [expr {$::n+2}] { up 0x01 }
	at [expr {$::n+4}] { up 0x80 }
	at [expr {$::n+$::F/2}] {
		check_call 0 256 0 1
		check {[m front_mask] == 1 && [m ship_x] == 0 && $::spawns == 0} "empty front refilled where its last ship died (ship_x [m ship_x]); meanwhile no move, no shot ($::spawns shots)"
	}
}

# Every frame-by-frame summary, at the end
proc final_checks {} {
	check {$::bitmap_bad == 0 && $::bitmap_lit > 0 && $::bitmap_shared > 0} "bitmap = the bullets in flight (volleys' and enemies'; a byte two share holds both) and the stars not in their bytes, colours too, every frame ($::bitmap_frames frames, $::bitmap_lit pixels seen, $::bitmap_shared frames with a shared byte; [expr {$::bitmap_bad ? "first wrong: $::bitmap_first" : "none wrong"}])"
	check {$::sat_bad == 0} "sprites = the front (ships and booms), the incoming ship and the enemies (pairs, free, booming, gone; rotated), every frame ($::sat_frames frames; [expr {$::sat_bad ? "first wrong: $::sat_first" : "none wrong"}])"
	check {$::coming_seen > 0} "the incoming ship's sprite showed on $::coming_seen frames"
	check_stars_end
	check_form_end
	check {$::dbad == 0 && $::dframes > 0} "death sound on channel C = DEATH table, every frame, enemies' booms too ($::dframes frames playing; [expr {$::dbad ? "first wrong: $::dfirst" : "none wrong"}])"
	say "frames dropped (the main loop late for a frame): $::dropped in all"
}

# The death sound, after a frame's work: started this frame -> the table's
# first row. Playing: R10 its volume, R4/R5 its tone, channel C's tone and
# noise on, R6 its noise period (even while the shot's noise is on: the
# death sound wins);
# at its end marker, or idle: R10 0, channel C's tone and noise off.
# A run's frames are counted, from its (re)start to its end marker.
proc death_frame {} {
	if {$::dnew} { set ::didx 0 ; incr ::dstarts $::dnew ; set ::dnew 0 }
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
			set col [expr {$st ? $::sym(BOOM_COLOR) : [m invul] ? $::sym(INVUL_COLOR) : $::sym(SHIP_COLOR)}]
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
			set cc [expr {[m invul] ? $::sym(INVUL_COLOR) : $::sym(COMING_COLOR)}]
			lappend r [expr {$::sym(SHIP_TOP) - 1}] [expr {$sx < 0 ? $sx + 32 : $sx}] $nm [expr {$sx < 0 ? 0x80 | $cc : $cc}]
		}
	} else { lappend r 0xC0 - - - }
	# the enemies, from RAM, rotated (form_frame checks the pairs against the loop)
	set ents {}
	for {set p 0} {$p < 4} {incr p} {
		lassign [en_state [expr {2*$p}]] st
		if {$st == 0} {
			lassign [en_state [expr {2*$p}]] st l xf x yf y
			lappend ents [en_ent $x $y 0 $::sym(NAME_ENEMY)] [list 0xC0 0 0 0]
			continue
		}
		foreach i [list [expr {2*$p}] [expr {2*$p+1}]] {
			lassign [en_state $i] st l xf x yf y
			if {$st == 1} {
				lappend ents [en_ent $x $y 0 $::sym(NAME_ENEMY1)]
			} elseif {$st < 5} {
				lappend ents [en_ent $x $y $::sym(SHIP_ART_L) [expr {$::sym(NAME_BOOM) + 4*($st - 2)}]]
			} else { lappend ents [list 0xC0 0 0 0] }
		}
	}
	set rot [m enemy_rot]
	for {set j 0} {$j < 8} {incr j} { lappend r {*}[lindex $ents [expr {($rot + $j) % 8}]] }
	# every other frame reversed, entry by entry; the enemies' turn moves on
	# with the straight ones
	if {[m sat_flip]} {
		set rr {}
		for {set e 12} {$e >= 0} {incr e -1} { lappend rr {*}[lrange $r [expr {4*$e}] [expr {4*$e+3}]] }
		set r $rr
	}
	if {[info exists ::lastflip]} {
		if {[m sat_flip] == $::lastflip} { incr ::flip_bad }
		if {[m sat_flip] && $rot != $::lastrot || ![m sat_flip] && $rot != ($::lastrot + 7) % 8} { incr ::flip_bad }
	}
	set ::lastflip [m sat_flip] ; set ::lastrot $rot
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
		if {[sate 4 0] != 0xC0 && [sate 4 2] > 0} { incr ::coming_seen }
	}
	set ::prev_sat [want_sat]
}

# A bullet in flight (a volley's or an enemy's) in pixel (x, y)'s bitmap byte
proc bullet_in {x y} {
	foreach v [volley_live] {
		set t [lindex $v 0]
		if {$y < $t || $y >= $t + $::sym(BULLET_H)} continue
		foreach bx [lrange $v 1 end] { if {$bx && $bx/8 == $x/8} { return 1 } }
	}
	foreach b [eb_list] {
		lassign $b t bx
		if {$t && $y >= $t && $y < $t + $::sym(BULLET_H) && $bx/8 == $x/8} { return 1 }
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

# Every frame: the bitmap's playfield rows (lines 8..183; the top status
# row holds the level text, checked as each wave begins) hold exactly the volleys' and the enemies' bullets, BULLET_COLOR on black
# (a byte two share: both), and the stars
# not in a bullet's byte, STAR_COLOR on black; the rest of the playfield's
# colour bytes are BULLET_COLOR on black
set bitmap_bad 0
set bitmap_frames 0
set bitmap_lit 0
set star_hidden 0
set bitmap_skip 0
set bitmap_shared 0
# The middle text's cells (the boss's bonus; checked by boss_frame), as it
# shows now and as it showed last frame (the frame it goes, the bullets in
# them are drawn only from the next on), are left out
set mid_prev {}
proc mid_cells {} {
	set r {}
	if {[m mid_text]} {
		for {set x [m mid_x0]} {$x < [m mid_x0] + [m mid_w]} {incr x 8} { lappend r $x }
	}
	return $r
}
# Pixel (x, y) in Boss2's cells (lines 8..23, columns 96..159)
proc in_b2 {x y} { expr {$y >= 8 && $y < 24 && $x >= 96 && $x < 160} }
set b2_bitmaps 0
proc check_bitmap {} {
	set mid [lsort -unique [concat [mid_cells] $::mid_prev]]
	set ::mid_prev [mid_cells]
	set midrow [expr {$::sym(OVER_ROW)*8}]
	if {$::n == 1} return   ;# before the main loop's first frame: no star drawn yet
	if {$::bitmap_skip} { set ::bitmap_skip 0 ; return }   ;# put_star0 just undrew star 0
	set bad0 {}
	set want [dict create]
	set b2 [m b2_shown]     ;# (Boss2 in the bitmap: its cells kept from stars and bullets)
	set bl {}
	foreach v [volley_live] {
		set y [lindex $v 0]
		foreach x [lrange $v 1 end] { if {$x} { lappend bl [list $y $x] } }
	}
	foreach b [eb_list] { if {[lindex $b 0]} { lappend bl $b } }
	set shared 0
	foreach e $bl {
		lassign $e y x
		for {set r $y} {$r < $y + $::sym(BULLET_H)} {incr r} {
			if {$b2 && [in_b2 $x $r]} continue
			set a [expr {($r/8)*256 + ($x/8)*8 + $r%8}]
			set b [expr {0x80 >> ($x%8)}]
			if {[dict exists $want $a]} { set b [expr {$b | [dict get $want $a]}] ; set shared 1 }
			dict set want $a $b
		}
	}
	incr ::bitmap_shared $shared
	set starb [dict create]
	set i 0
	foreach e [star_list] {
		lassign $e x y on
		if {$y >= $midrow && $y < $midrow + 8 && ($x & 0xF8) in $mid} { incr i ; continue }
		if {$b2 && [in_b2 $x $y]} { if {$on} { lappend bad0 "star $i shown in Boss2's cells" } ; incr i ; continue }
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
	set blk [debug read_block VRAM 256 [expr {22*256}]]
	set got [dict create]
	foreach p [regexp -all -indices -inline {[^\x00]} $blk] {
		set a [expr {[lindex $p 0] + 256}]
		binary scan [string index $blk [lindex $p 0]] cu b
		dict set got $a $b
	}
	incr ::bitmap_frames
	incr ::bitmap_lit [dict size $got]
	foreach x $mid {
		for {set y 0} {$y < 8} {incr y} {
			set a [expr {$::sym(OVER_ROW)*256 + $x + $y}]
			dict unset want $a ; dict unset got $a
		}
	}
	set bad $bad0
	set b2col [dict create]
	if {$b2} {
		# its cells: BOSS2_PAT, and BOSS2_COL with its colour in the body's
		set bc [expr {[m boss_color] << 4}]
		for {set i 0} {$i < 128} {incr i} {
			set a [expr {256*(1 + $i/64) + 96 + $i%64}]
			if {[debug read VRAM $a] != [m BOSS2_PAT $i]} { lappend bad "Boss2 $a" }
			set c [m BOSS2_COL $i] ; if {$c < 16} { set c [expr {$c | $bc}] }
			dict set b2col $a $c
			dict unset want $a ; dict unset got $a
		}
		incr ::b2_bitmaps
	}
	dict for {a b} $want { if {![dict exists $got $a] || [dict get $got $a] != $b} { lappend bad $a } }
	dict for {a b} $got { if {![dict exists $want $a]} { lappend bad $a } }
	set cb [debug read_block VRAM 0x2100 [expr {22*256}]]
	foreach p [regexp -all -indices -inline {[^\xF1]} $cb] {
		set a [expr {[lindex $p 0] + 256}]
		binary scan [string index $cb [lindex $p 0]] cu c
		if {[dict exists $b2col $a]} continue
		if {!([dict exists $starb $a] && $c == 0xE1)} { lappend bad "colour $a" }
	}
	dict for {a c} $b2col { if {[debug read VRAM [expr {0x2000 + $a}]] != $c} { lappend bad "Boss2 colour $a" } }
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
	set bad [reserves_bad $count lit]
	check {[llength $bad] == 0 && $lit > 0} "$count reserve ships at the bottom left, 1 px apart ($lit px lit; wrong: [lrange $bad 0 9])"
	set names {}
	for {set c 0} {$c < 32} {incr c} { if {[debug read VRAM [expr {0x1800 + 23*32 + $c}]] != 0xE0 + $c} { lappend names $c } }
	check {[llength $names] == 0} "bottom row's names are INIGRP's (wrong at: $names)"
}
proc reserves_bad {count {litvar ""}} {
	if {$litvar ne ""} { upvar 1 $litvar lit }
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
	return $bad
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
	score_end
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
set TITLE [exec sh -c "cd '$ROOT' && ../.venv/bin/python title.py --raw"]
set FONT [exec sh -c "cd '$ROOT' && ../.venv/bin/python font.py --raw"]
set BROW $sym(BLINK_ROW)
# the text, from the ROM, centred on BLINK_ROW in font.py's glyphs (rows
# on the cell's lines 0..5, 6..7 blank), white on black: TITLE_ON; its
# cells' colours black instead: TITLE_OFF
# the game's file, as the machine runs it from CODE_BASE on (the BIN after
# its BLOAD header)
set f [open $ROOT/[expr {[info exists ::env(IMAGE)] ? $::env(IMAGE) : "terrafnt.rom"}] rb] ; set rom [read $f] ; close $f
if {[string index $rom 0] eq "\xFE"} { set rom [string range $rom 7 end] }
set a [expr {$sym(PRESS_TEXT) - $sym(CODE_BASE)}]
set PRESS [string range $rom $a [expr {[string first "\0" $rom $a] - 1}]]
check {$PRESS eq "PRESS SPACE OR FIRE TO BEGIN"} "splash: the text is \"$PRESS\""
check {[lrange $FONT 0 5] eq {00 00 00 00 00 00} && [lsearch -not $FONT 00] >= 0} "font: the space glyph is blank (ink is the PNG's black), others aren't"
# the credit and the URL above it, centred on their rows, never blinking
proc rom_text {name} {
	set a [expr {$::sym($name) - $::sym(CODE_BASE)}]
	string range $::rom $a [expr {[string first "\0" $::rom $a] - 1}]
}
set CREDIT [rom_text CREDIT_TEXT]
set URL [rom_text URL_TEXT]
check {$CREDIT eq "(C) 2026 JCCYC" && $URL eq "HTTPS://RETROPOLIS.COM.BR"} "splash: the credit is \"$CREDIT\", the URL \"$URL\""
set TITLE_RAW $TITLE
# text str centred on character row `row` in TITLE_ON (and in TITLE_OFF,
# with its colours black if blinks)
proc overlay {str row blinks} {
	set col [expr {(32 - [string length $str]) / 2}]
	for {set i 0} {$i < [string length $str]} {incr i} {
		scan [string index $str $i] %c c
		set p [expr {$row*256 + ($col + $i)*8}]
		for {set y 0} {$y < 8} {incr y} {
			set g [expr {$y < 6 ? [lindex $::FONT [expr {($c - 32)*6 + $y}]] : "00"}]
			set w [format %02x [expr {$::sym(TEXT_COLOR)*16 + 1}]]
			set ::TITLE_ON [lreplace $::TITLE_ON [expr {$p + $y}] [expr {$p + $y}] $g]
			set ::TITLE_OFF [lreplace $::TITLE_OFF [expr {$p + $y}] [expr {$p + $y}] $g]
			set ::TITLE_ON [lreplace $::TITLE_ON [expr {6144 + $p + $y}] [expr {6144 + $p + $y}] $w]
			set ::TITLE_OFF [lreplace $::TITLE_OFF [expr {6144 + $p + $y}] [expr {6144 + $p + $y}] [expr {$blinks ? 11 : $w}]]
		}
	}
}
# The high score table as the test expects it: {score initials} each, best
# first (the user's, at power-on; the disk version's, the file the test
# puts on the disk)
set HI_DEFAULTS {{5000 LTR} {4800 EHE} {4500 TEN} {4000 SAA} {3500 ALZ} {3000 SII} {2500 SES} {2000 UNT} {1500 MSO} {1000 EAO}}
set hi $HI_DEFAULTS
# Table t (a VRAM list: 6144 pattern bytes, then 6144 colour bytes) with
# str in font.py's glyphs from character row `row`, column col, white on black
proc paint {t str row col} {
	set w [format %02x [expr {$::sym(TEXT_COLOR)*16 + 1}]]
	for {set i 0} {$i < [string length $str]} {incr i} {
		scan [string index $str $i] %c c
		set p [expr {$row*256 + ($col + $i)*8}]
		for {set y 0} {$y < 8} {incr y} {
			set g [expr {$y < 6 ? [lindex $::FONT [expr {($c - 32)*6 + $y}]] : "00"}]
			set t [lreplace $t [expr {$p + $y}] [expr {$p + $y}] $g]
			set t [lreplace $t [expr {6144 + $p + $y}] [expr {6144 + $p + $y}] $w]
		}
	}
	return $t
}
# TITLE: the picture with "HI SCORE" on HISC_ROW and the table's best score
# on the row under it, right-justified; TITLE_ON / TITLE_OFF: with the
# title's text (shown / the blinking line hidden)
proc build_titles {} {
	set top [lindex $::hi 0 0]
	set r $::sym(HISC_ROW)
	set ::TITLE [paint [paint [expr {$::cheat ? [cheat_colours $::TITLE_RAW] : $::TITLE_RAW}] "HI SCORE" $r 24] $top [expr {$r + 1}] [expr {32 - [string length $top]}]]
	set ::TITLE_ON $::TITLE
	set ::TITLE_OFF $::TITLE
	overlay $::CREDIT $::sym(CREDIT_ROW) 0
	overlay $::URL $::sym(URL_ROW) 0
	overlay $::PRESS $::BROW 1
}
# Cheat mode's title: the picture's colour bytes on rows 0..EGG_ROW-1 with
# each nibble LOGO_COLOR made CHEAT_LOGO_COLOR
set cheat 0
proc cheat_colours {t} {
	set from $::sym(LOGO_COLOR) ; set to $::sym(CHEAT_LOGO_COLOR)
	for {set i 6144} {$i < 6144 + $::sym(EGG_ROW)*256} {incr i} {
		set v [expr 0x[lindex $t $i]] ; set h [expr {$v >> 4}] ; set l [expr {$v & 15}]
		if {$h == $from} { set h $to } ; if {$l == $from} { set l $to }
		set t [lreplace $t $i $i [format %02x [expr {$h*16 + $l}]]]
	}
	return $t
}
build_titles
# The easter egg (the spec's texts; the version from the ROM's version
# bytes) and the license (decoded from the ROM, so a licensed copy passes)
set EGG_LINES {"JCCYC IS" "JUAN CARLOS CASTRO Y CASTRO" "WELCOME TO THE FRONT!"}
proc rom_byte {ofs} { scan [string index $::rom $ofs] %c v ; return $v }
set VERSION "[rom_byte 16].[rom_byte 17].[expr {[rom_byte 18] + 256*[rom_byte 19]}]"
check {$VERSION eq "$sym(VERSION_MAJOR).$sym(VERSION_MINOR).$sym(VERSION_PATCH)"} "the version bytes at CODE_BASE+10h: $VERSION"
set LICENSE {}
for {set l 0} {$l < 2} {incr l} {
	set t ""
	for {set i 0} {$i < $sym(LICENSE_LEN)} {incr i} {
		append t [format %c [expr {[rom_byte [expr {$sym(LICENSE_TEXT) - $sym(CODE_BASE) + $l*$sym(LICENSE_LEN) + $i}]] ^ (($sym(EGG_KEY) + $i*$sym(EGG_KEY_STEP)) & 0xFF)}]]
	}
	lappend LICENSE [string trimright $t]
}
say "the license lines: \"[lindex $LICENSE 0]\" / \"[lindex $LICENSE 1]\""
check {$sym(LICENSE_TEXT) == $sym(CODE_BASE) + 0x14} "the license lines at CODE_BASE+14h"
set plain {}
foreach t [concat $EGG_LINES $LICENSE] { if {[string length [string trim $t]] > 3 && [string first $t $rom] >= 0} { lappend plain $t } }
check {![llength $plain]} "the egg's and the license's texts aren't in the game's file in plain (found: $plain)"
# Text str in font.py's glyphs on character row `row` from column col, over
# ncells cells (blank cells past its end): the VRAM addresses wrong
# (patterns: glyph rows on lines 0..5, 6..7 blank; colours TEXT_COLOR on black)
proc text_bad {row col str ncells} {
	set bad {}
	set cc [expr {$::sym(TEXT_COLOR)*16 + 1}]
	for {set k 0} {$k < $ncells} {incr k} {
		scan [expr {$k < [string length $str] ? [string index $str $k] : " "}] %c ch
		set a [expr {$row*256 + ($col + $k)*8}]
		for {set y 0} {$y < 8} {incr y} {
			set p [expr {$y < 6 ? "0x[lindex $::FONT [expr {($ch - 32)*6 + $y}]]" : 0}]
			if {[debug read VRAM [expr {$a + $y}]] != $p} { lappend bad [format %04X [expr {$a + $y}]] }
			if {[debug read VRAM [expr {0x2000 + $a + $y}]] != $cc} { lappend bad [format %04X [expr {0x2000 + $a + $y}]] }
		}
	}
	return $bad
}
# The level and wave for wave w (0 the first): a level is 10 waves
proc lw_str {w} { set l [expr {$w/10 + 1}] ; if {$l > 255} { set l 255 } ; return "L$l W[expr {$w%10 + 1}]" }
# The top status row: text str from its left over LW_LEN cells (blank past
# its end), the rest of the row blank: the addresses wrong
proc lw_bad {str} {
	set bad [text_bad $::sym(LW_ROW) $::sym(LW_COL) $str $::sym(LW_LEN)]
	for {set a [expr {$::sym(LW_LEN)*8}]} {$a < $::sym(SCORE_COL)*8} {incr a} {
		if {[debug read VRAM $a] || [debug read VRAM [expr {0x2000 + $a}]] != 0x11} { lappend bad [format %04X $a] }
	}
	concat $bad [score_vram_bad]
}
# The title's tables with text str on the top status row from its left
# (the last game's level and wave) and score sc right-aligned on its right
# (the last game's; its leading blanks not printed): TITLE_ON's
proc title_with {str sc {base ""}} {
	set t [expr {$base eq "" ? $::TITLE_ON : $base}]
	set cells {}
	for {set k 0} {$k < [string length $str]} {incr k} { lappend cells [expr {$::sym(LW_COL) + $k}] [string index $str $k] }
	for {set k 0} {$k < [string length $sc]} {incr k} { lappend cells [expr {32 - [string length $sc] + $k}] [string index $sc $k] }
	foreach {col c} $cells {
		scan $c %c ch
		set p [expr {$::sym(LW_ROW)*256 + $col*8}]
		for {set y 0} {$y < 8} {incr y} {
			set g [expr {$y < 6 ? [lindex $::FONT [expr {($ch - 32)*6 + $y}]] : "00"}]
			set t [lreplace $t [expr {$p + $y}] [expr {$p + $y}] $g]
			set t [lreplace $t [expr {6144 + $p + $y}] [expr {6144 + $p + $y}] [format %02x [expr {$::sym(TEXT_COLOR)*16 + 1}]]]
		}
	}
	return $t
}
set phase 1
set sn 0
proc vdp_r1 {} { debug read "VDP regs" 1 }
# the blinking row's colours: 1 = the text shown, 0 = hidden, -1 neither
proc blink_state {} {
	set on 1 ; set off 1
	set a [expr {0x2000 + $::BROW*256}]
	for {set i 0} {$i < 256} {incr i} {
		set v [debug read VRAM [expr {$a + $i}]]
		set j [expr {6144 + $::BROW*256 + $i}]
		if {$v != "0x[lindex $::TITLE_ON $j]"} { set on 0 }
		if {$v != "0x[lindex $::TITLE_OFF $j]"} { set off 0 }
	}
	expr {$on ? 1 : ($off ? 0 : -1)}
}
# VRAM's tables against the picture and the text ($shown or hidden)
proc check_title {shown what {lw ""} {sc ""}} {
	set bad {}
	set want [expr {$lw ne "" ? [title_with $lw $sc] : ($shown ? $::TITLE_ON : $::TITLE_OFF)}]
	for {set i 0} {$i < 12288} {incr i} {
		set w [expr 0x[lindex $want $i]]
		set a [expr {$i < 6144 ? $i : 0x2000 + $i - 6144}]
		if {[debug read VRAM $a] != $w} { lappend bad [format %04X $a] ; if {[llength $bad] > 5} break }
	}
	check {[llength $bad] == 0} "splash $what: patterns and colours = images/title.png and \"$::CREDIT\", \"$::URL\", \"$::PRESS\" in images/font.png, centred on rows $::sym(CREDIT_ROW), $::sym(URL_ROW), $::BROW[expr {$lw ne "" ? ", \"$lw\" on the top status row's left and \"$sc\" on its right" : ""}] (wrong at: $bad)"
}
# The egg and the license. TITLE (the picture alone) with the lines {row
# str ...} centred on their rows (odd lengths half a cell left), white on
# black, and the top status row's level, wave and score (title_with)
proc title_lines {lines lw sc} {
	set t $::TITLE
	set w [format %02x [expr {$::sym(TEXT_COLOR)*16 + 1}]]
	foreach {row str} $lines {
		set col [expr {(32 - [string length $str]) / 2}]
		for {set i 0} {$i < [string length $str]} {incr i} {
			scan [string index $str $i] %c c
			set p [expr {$row*256 + ($col + $i)*8}]
			for {set y 0} {$y < 8} {incr y} {
				set g [expr {$y < 6 ? [lindex $::FONT [expr {($c - 32)*6 + $y}]] : "00"}]
				set t [lreplace $t [expr {$p + $y}] [expr {$p + $y}] $g]
				set t [lreplace $t [expr {6144 + $p + $y}] [expr {6144 + $p + $y}] $w]
			}
		}
	}
	title_with $lw $sc $t
}
# VRAM's tables against want: the addresses wrong (6 at most)
proc vram_bad {want} {
	set bad {}
	for {set i 0} {$i < 12288} {incr i} {
		set a [expr {$i < 6144 ? $i : 0x2000 + $i - 6144}]
		if {[debug read VRAM $a] != "0x[lindex $want $i]"} { lappend bad [format %04X $a] ; if {[llength $bad] > 5} break }
	}
	return $bad
}
proc egg_want {} {
	set r $::sym(EGG_ROW)
	set l [list $r "VERSION $::VERSION"]
	foreach t $::EGG_LINES { incr r ; lappend l $r $t }
	title_lines $l $::lw_last $::score_last
}
proc lic_want {} { title_lines [list $::sym(LICENSE_ROW) [lindex $::LICENSE 0] [expr {$::sym(LICENSE_ROW) + 1}] [lindex $::LICENSE 1]] $::lw_last $::score_last }
proc w16 {name} { expr {[m $name] + 256*[m $name 1]} }
proc ctrl {d} { if {$d} { keymatrixdown 6 0x02 } else { keymatrixup 6 0x02 } }
proc vkey {d} { if {$d} { keymatrixdown 5 0x08 } else { keymatrixup 5 0x08 } }
# The title after attract mode 4, ended by Ctrl-V (still held): the egg
# up from the start, over the picture in place of the title's text, the
# top row as it was; for EGG_SECS (no blink), then the title's text, its
# blink from the start. V alone, CTRL alone: nothing. Ctrl-V: the egg; a
# Ctrl-V (CTRL released and pressed) while it's up doesn't restart it;
# with CTRL held all along, 3 more V presses: the license (two taps, CTRL
# released and pressed, two taps: still the egg; one more: the license).
# It stays with CTRL held EGG_SECS + 1 s, the title's count stopped;
# CTRL released, space: the title's text back, its count from the start,
# no game. Again, taken away by joystick 1's button A. Then Ctrl-V and
# joystick 1's button A, Ctrl-V and space: each takes the egg away (the
# title's text back), starting nothing; then space starts the game.
proc egg_dismissed {what} {
	set bad [vram_bad [title_with $::lw_last $::score_last]]
	check {![w16 egg_left] && ![m lic_state] && ![llength $bad]} "$what during the egg: the egg gone, the title's text back, no game (wrong: $bad)"
}
proc egg_frame {} {
	set F [m fps] ; set E [expr {$::sym(EGG_SECS)*$F}] ; set n $::sn
	if {$n == 1} {
		check {[w16 egg_left] == $E && ![m lic_state] && ![m egg_now]} "attract mode's Ctrl-V: the title with the egg up for $::sym(EGG_SECS) s ([w16 egg_left] frames; want $E)"
		ctrl 0 ; vkey 0
	}
	if {$n == 3 || $n == 2*$F || $n == $E} {
		set bad [vram_bad [egg_want]]
		check {![llength $bad] && ([vdp_r1] & 0x40)} "the egg at title frame $n: \"VERSION $::VERSION\", [join $::EGG_LINES " / "] centred on rows $::sym(EGG_ROW).., over the picture, the top row as it was (\"$::lw_last\", \"$::score_last\"), no blink (wrong: $bad)"
	}
	if {$n == $E + 1} {
		set bad [vram_bad [title_with $::lw_last $::score_last]]
		check {![llength $bad] && ![w16 egg_left] && [m blink_shown] && [m blink_left] == [m blink_on]} "the egg gone after exactly $::sym(EGG_SECS) s: the title's text back, its blink from the start (wrong: $bad)"
	}
	set B [expr {$E + 5}]
	switch -- [expr {$n - $B}] {
		0 { vkey 1 } 3 { vkey 0 } 5 { ctrl 1 } 8 { ctrl 0 }
		10 { check {![w16 egg_left] && ![m lic_state]} "V alone, CTRL alone: no egg" }
		15 { ctrl 1 } 17 { vkey 1 } 19 { vkey 0 }
		21 { check {[w16 egg_left] == $E - 3} "Ctrl-V (V last): the egg again ([w16 egg_left] frames left; want [expr {$E - 3}])" }
		23 { vkey 1 } 25 { vkey 0 } 27 { vkey 1 } 29 { vkey 0 }
		31 { ctrl 0 } 33 { ctrl 1 } 35 { vkey 1 } 37 { vkey 0 } 39 { vkey 1 } 41 { vkey 0 }
		43 {
			check {[w16 egg_left] == $E - 25 && ![m lic_state]} "two taps, CTRL released and pressed, two taps: still the egg, not restarted ([w16 egg_left] frames left; want [expr {$E - 25}])"
			set bad [vram_bad [egg_want]]
			check {![llength $bad]} "the egg still shown (wrong: $bad)"
		}
		45 { vkey 1 } 47 { vkey 0 }
		51 {
			set bad [vram_bad [lic_want]]
			check {[m lic_state] == 1 && ![w16 egg_left] && ![llength $bad]} "a third tap: the license (\"[join $::LICENSE {" / "}]\") centred on rows $::sym(LICENSE_ROW) and [expr {$::sym(LICENSE_ROW) + 1}] over the picture, the egg gone (wrong: $bad)"
			set ::tl0 [w16 title_left]
		}
	}
	set L [expr {$B + 51 + ($::sym(EGG_SECS) + 1)*$F}]
	switch -- [expr {$n - $L}] {
		0 {
			set bad [vram_bad [lic_want]]
			check {[m lic_state] == 1 && [w16 title_left] == $::tl0 && ![llength $bad]} "the license still up after $::sym(EGG_SECS) + 1 s with CTRL held, the title's count stopped ([w16 title_left] frames left; want $::tl0; wrong: $bad)"
			ctrl 0
		}
		3 { check {[m lic_state] == 2} "all released: the license armed" ; down 0x01 }
		6 {
			set bad [vram_bad [title_with $::lw_last $::score_last]]
			check {![m lic_state] && ![llength $bad] && [w16 title_left] == 20*$F - 2} "space: the license gone, the title's text back, its count from the start ([w16 title_left] frames left; want [expr {20*$F - 2}]), no game (wrong: $bad)"
		}
		8 { up 0x01 }
		10 { ctrl 1 } 11 { vkey 1 } 13 { vkey 0 }
		15 { vkey 1 } 17 { vkey 0 } 19 { vkey 1 } 21 { vkey 0 } 23 { vkey 1 } 25 { vkey 0 }
		27 { check {[m lic_state] == 1} "Ctrl-V and three taps: the license again" ; ctrl 0 }
		30 { joydown 1 0x10 }
		33 { check {![m lic_state] && [m blink_shown]} "joystick 1's button A: the license gone, no game" ; joyup 1 }
		36 { ctrl 1 ; vkey 1 } 38 { ctrl 0 ; vkey 0 }
		40 { check {[w16 egg_left] > 0} "Ctrl-V: the egg" ; joydown 1 0x10 }
		43 { egg_dismissed "joystick 1's button A" ; joyup 1 }
		46 { ctrl 1 ; vkey 1 } 48 { ctrl 0 ; vkey 0 }
		50 { check {[w16 egg_left] > 0} "Ctrl-V: the egg" ; down 0x01 }
		53 { egg_dismissed "space" ; up 0x01 }
		56 { down 0x01 ; set ::press_sn $n }
		60 { fail "space after the egg doesn't start the game" ; finish }
	}
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
	if {$::phase == 3} {
		if {$::tnext eq "egg"} { egg_frame ; return }
		if {$::sn == 1} { up 0x01 ; joyup 1 ; joyup 2 }
		if {$::sn == 3} {
			check {[vdp_r1] & 0x40} "back at the title after $::twhy: display on (R1 [format %02X [vdp_r1]])"
			check_title 1 "after $::twhy (text shown; the last game's level, wave and score kept)" $::lw_last $::score_last
			check {[sat 0] == 0xD0} "back at the title: no sprites (the SAT's first Y [format %02X [sat 0]])"
		}
		if {$::sn == 1} { try hi_title_start }
		if {$::sn == 20*[m fps] + 1} { list_check "after $::twhy" }
		if {$::tnext eq "press"} {
			if {$::sn == 6} { down 0x01 }
			if {$::sn == 9} { fail "space doesn't start a new game after $::twhy" ; finish }
		} elseif {$::tnext eq "list"} { try list_frame } elseif {$::tnext eq "cheat"} { try cheat_frame } elseif {$::sn > 27*[m fps]} { fail "the title left alone 20 s, the list 7 s after $::twhy: no attract mode" ; finish }
		return
	}
	set F [m fps]
	lappend ::blinks [list [blink_state] $::isr_time]
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
cart_bp $sym(splash.blink) {} { try splash_frame }
# the frame's time: its interrupt's (not when the poll loop sees it)
set isr_time 0
cart_bp $sym(isr) {} { if {$::phase == 2 && $::sn < 3*[m fps]} { set ::isr_time [machine_info time] } }
# after the splash: "L1 W1" on the top status row's left, the score 0 on
# its right, the rest of it blank, and the bottom one past the reserves
proc check_cleared {} {
	set bad [lw_bad "L1 W1"]
	if {[score_ram] || $::score_model} { lappend bad "score [score_ram] (model $::score_model)" }
	for {set a [expr {23*256 + $::sym(RESERVE_CELLS)*8}]} {$a < 6144} {incr a} {
		if {[debug read VRAM $a] || [debug read VRAM [expr {0x2000 + $a}]] != 0x11} { lappend bad [format %04X $a] }
	}
	check {[llength $bad] == 0} "after the splash: \"L1 W1\" on the top status row's left, white on black, the score \"0\" on its right (its last cell), the rest of the status rows blank (wrong: [lrange $bad 0 5])"
}

down 0x01            ;# boot 1: space held from power-on
set started 0
cart_bp $sym(main_loop) {} {
	if {$::phase == 1} {
		check {$::sn >= 8} "joystick 1's button A starts the game; space held from power-on, then let go, didn't (splash frame $::sn)"
		try hi_boot1
		joyup 1
		set ::phase 2 ; set ::sn 0
		reset
		return
	}
	if {$::phase == 3} {
		if {[m attract]} { try attract_begin } else {
			check {$::sn == $::press_sn && $::tnext in {press egg list cheat}} "after $::twhy, a new press of space starts a new game (splash frame $::sn; want $::press_sn)"
			up 0x01
			set ::phase 4
			try new_game_checks
		}
	}
	if {!$::started} {
		check {$::sn == 3*[m fps]} "space starts the game (splash frame $::sn)"
		try hi_boot2
		up 0x01
		set ::started 1 ; try plan
	}
	frame
}

# The formation, from the spec: its pairs (dx dy from its top left, in the
# picture images/formation-enemy-0-color-12.png, starting at column 25),
# starting with its top on line 46 (its highest 18 lines under line 8, the
# playfield's first); a loop at constant speed of four legs {dx dy}
# a cycle (FORM_TICKS / FORM_TICK_RATE s, path.py's CYCLE_SECS), 25 px east
# a cycle; x mod 272 (256 + a pair), a pair
# at 256..271 is at -16..-1 on screen (early clock)
set FPAIRS {{20 0} {55 8} {0 20} {35 28}}
set FLEGS {{35 -20} {60 20} {-35 20} {-35 -20}}
set FX0 25 ; set FY0 46 ; set FWRAP 272
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
# Pair p's place from the SAT (built with the enemies' rotation last
# frame): {x (mod FWRAP) line name colour}
proc form_sat {p} {
	set b [expr {(5 + ((2*$p - $::rotp) & 7))}]
	if {$::flipp} { set b [expr {12 - $b}] }
	set b [expr {$b*4}]
	set x [sat [expr {$b+1}]] ; set c [sat [expr {$b+3}]]
	if {$c & 0x80} { set x [expr {$x - 32}] }
	list [expr {$x < 0 ? $x + $::FWRAP : $x}] [expr {[sat $b] + 1}] [sat [expr {$b+2}]] $c
}
proc wdiff {a b} { expr {($a - $b + 3*$::FWRAP/2) % $::FWRAP - $::FWRAP/2} }

set form_bad 0 ; set form_first "" ; set form_frames 0 ; set form_err 0
set form_left 0 ; set form_right 0 ; set form_laps 0 ; set form_lapbad 0
set form_ymin 999 ; set form_ymax 0 ; set form_hist [dict create]
set wave0 0 ; set form_w2 0 ; set form_skip 0
proc form_bad {s} { if {!$::form_bad} { set ::form_first "frame $::n: $s" } ; incr ::form_bad }
proc form_frame {} {
	if {$::n < 2 || $::n <= $::form_skip} return
	# VRAM holds the SAT built after n - 2 frames' moves (since the wave
	# began: ::wave0, the frame whose work started it)
	set k [expr {$::n - 2 - $::wave0}]
	lassign [form_at $k] wx wy
	# the pairs still whole when the SAT shown was built
	set intact {}
	for {set p 0} {$p < 4} {incr p} { if {[lindex $::eprev [expr {2*$p}] 0] == 0} { lappend intact $p } }
	if {![llength $intact]} return
	set q [lindex $intact 0]
	set p0 [form_sat $q]
	set x0 [expr {([lindex $p0 0] - [lindex $::FPAIRS $q 0]) % $::FWRAP}]
	set y0 [expr {[lindex $p0 1] - [lindex $::FPAIRS $q 1]}]
	set e [expr {abs([wdiff $x0 $wx])}]
	if {abs($y0 - $wy) > $e} { set e [expr {abs($y0 - $wy)}] }
	if {$e > $::form_err} { set ::form_err $e }
	if {$e > 1} { form_bad "top left ($x0, $y0), want ($wx, $wy)" }
	if {$y0 < 8 || $y0 + 44 > $::sym(SHIP_TOP)} { form_bad "lines $y0..[expr {$y0+43}]" }
	if {$y0 < $::form_ymin} { set ::form_ymin $y0 }
	if {$y0 > $::form_ymax} { set ::form_ymax $y0 }
	foreach i $intact {
		lassign [form_sat $i] x y nm c
		lassign [lindex $::FPAIRS $i] dx dy
		if {[wdiff $x [expr {$x0 + $dx}]] != 0 || $y != $y0 + $dy} { form_bad "pair $i at ($x, $y), not at ($dx, $dy) from pair 0's place" }
		if {$nm != $::sym(NAME_ENEMY) || ($c & 0x7F) != [m form_color]} { form_bad "pair $i name $nm colour [format %02X $c]" }
		if {$x > 256} { incr ::form_left }   ;# -15..-1: partly in at the left
		if {$x < 256 && $x > 240} { incr ::form_right }
	}
	# a cycle later: 25 px east, the same lines
	if {$::wave0} { incr ::form_w2 }
	set tk [form_ticks $k]
	if {[llength $intact] < 4} { incr ::form_frames ; return }   ;# (the laps: with all four)
	dict set ::form_hist $tk [list $x0 $y0]
	set tp [expr {$tk - $::sym(FORM_TICKS)}]
	if {[dict exists $::form_hist $tp]} {
		lassign [dict get $::form_hist $tp] px py
		incr ::form_laps
		if {[wdiff $x0 $px] != 25 || $y0 != $py} { incr ::form_lapbad ; form_bad "a cycle after ($px, $py): ($x0, $y0)" }
	}
	incr ::form_frames
}
# The waves' enemies and colours, in turn: wave w (0 first) is enemy
# w mod 10 in colour COLS[w mod 9]
set COLS {2 3 5 7 8 9 10 11 13}
proc check_form_pick {} {
	check {[m form_enemy] == 0 && [m form_cidx] == 0 && [m form_color] == 2} "the first wave: enemy [m form_enemy], colour [m form_color] (index [m form_cidx]; want enemy 0, colour 2)"
}
# The wave's enemy's patterns in VRAM, against ENEMY_PATTERN: wrong bytes
proc form_pattern_bad {{e ""}} {
	if {$e eq ""} { set e [m form_enemy] }
	set bad {}
	set a [expr {0x3800 + $::sym(NAME_ENEMY)*8}]
	for {set i 0} {$i < 32} {incr i} {
		if {[debug read VRAM [expr {$a + $i}]] != [m ENEMY_PATTERN [expr {$e*32 + $i}]]} { lappend bad "pair $i" }
		if {$i < 16 && [debug read VRAM [expr {$a + $i}]] != [debug read VRAM [expr {$a + $i + 16}]]} { lappend bad "half $i" }
	}
	set a [expr {0x3800 + $::sym(NAME_ENEMY1)*8}]
	for {set i 0} {$i < 32} {incr i} {
		set w [expr {$i < 16 ? [m ENEMY_PATTERN [expr {$e*32 + $i}]] : 0}]
		if {[debug read VRAM [expr {$a + $i}]] != $w} { lappend bad "lone $i" }
	}
	if {[m form_art_t] != [m ENEMY_ROWS [expr {2*$e}]] || [m form_art_b] != [m ENEMY_ROWS [expr {2*$e+1}]]} { lappend bad "art rows" }
	return $bad
}
# The wave's enemy's art for the model: ::erows, ::art_t, ::art_b
proc load_art {} {
	set e [m form_enemy]
	set ::erows {}
	for {set i 0} {$i < 16} {incr i} { lappend ::erows [m ENEMY_PATTERN [expr {$e*32 + $i}]] }
	set ::art_t [m ENEMY_ROWS [expr {2*$e}]] ; set ::art_b [m ENEMY_ROWS [expr {2*$e+1}]]
}
proc check_form_pattern {} {
	set bad [form_pattern_bad]
	check {[llength $bad] == 0} "enemy [m form_enemy] in VRAM: the formation's pair (twice side by side), the lone one (left 8 columns), its art's rows (wrong: $bad)"
	load_art
}
proc check_form_end {} {
	check {$::form_bad == 0 && $::form_frames > 10*$::F} "formation = the spec's loop ([format %.3f [expr {double($::sym(FORM_TICKS)) / $::sym(FORM_TICK_RATE)}]] s, constant speed, 25 px east a cycle), pairs in the picture's layout, colour [m form_color], every frame ($::form_frames frames, off by $::form_err px at most; [expr {$::form_bad ? "first wrong: $::form_first" : "none wrong"}])"
	check {$::form_laps > 0 && $::form_lapbad == 0} "a cycle later the formation is 25 px east on the same lines ($::form_laps frames checked)"
	check {$::form_ymin >= 8 && $::form_ymax + 44 <= $::sym(SHIP_TOP) && $::form_ymin <= 28 && $::form_ymax >= 64} "formation's top from line $::form_ymin to $::form_ymax (the spec: 26..66): between the status area and the front's sprites"
	check {$::form_w2 > $::F} "the second wave's formation checked too ($::form_w2 frames)"
	check {$::form_left > 0 && $::form_right > 0} "pairs leaving the right edge ($::form_right pair-frames) come back in from the left, early clock ($::form_left)"
}

# ---- The enemies: hits, break-ups, free flight, booms ----------------------
# Enemy i's record: {ST LEFT XF X YF Y DIR}
proc en_state {i} {
	set b [expr {$::sym(enemies) + $i*$::sym(EN)}]
	set r {}
	foreach f {ST LEFT XF X YF Y DIR} { lappend r [debug read memory [expr {$b + $::sym(EN.$f)}]] }
	lset r 3 [expr {[lindex $r 3] + 256*[debug read memory [expr {$b + $::sym(EN.X) + 1}]]}]
	return $r
}
proc screen_x {x} { expr {$x < 256 ? $x : $x - $::FWRAP} }
# A SAT entry: name nm at column x (mod FWRAP) less ofs, line y, the formation's colour
proc en_ent {x y ofs nm} {
	set sx [expr {[screen_x $x] - $ofs}]
	set c [m form_color]
	if {$sx < 0} { set sx [expr {$sx + 32}] ; set c [expr {$c | 0x80}] }
	list [expr {$y - 1}] $sx $nm $c
}
# Direction d's velocity {vx vy}, 1/256 px a frame (path.py's table)
proc vel {d} {
	set a [expr {$::sym(FREE_VEL_$::F) + 4*$d}]
	set r {}
	foreach o {0 2} {
		set v [expr {[debug read memory [expr {$a+$o}]] + 256*[debug read memory [expr {$a+$o+1}]]}]
		lappend r [expr {$v >= 32768 ? $v - 65536 : $v}]
	}
	return $r
}
# The table: every direction at the loop's speed (the square legs' too:
# the loop is at one speed), d * 5.625 degrees clockwise from east
proc check_vel_table {} {
	set tot 0.0
	foreach l $::FLEGS { set tot [expr {$tot + hypot([lindex $l 0], [lindex $l 1])}] }
	set cyc [expr {double($::sym(FORM_TICKS)) / $::sym(FORM_TICK_RATE)}]
	set sq [expr {hypot(35, 20)}]
	set want [expr {$sq / ($cyc * $sq / $tot)}]
	set bad {} ; set lo 1e9 ; set hi 0
	for {set d 0} {$d < 64} {incr d} {
		lassign [vel $d] vx vy
		set sp [expr {hypot($vx, $vy) * $::F / 256.0}]
		if {$sp < $lo} { set lo $sp } ; if {$sp > $hi} { set hi $sp }
		set ang [expr {atan2($vy, $vx) * 180 / acos(-1)}]
		set da [expr {fmod($ang - $d*5.625 + 540, 360) - 180}]
		if {abs($sp - $want) > 0.3 || abs($da) > 0.3} { lappend bad $d }
	}
	check {[llength $bad] == 0} "free enemies' velocities: 64 directions at the square legs' speed ([format %.2f $want] px/s; [format %.2f $lo]..[format %.2f $hi]; wrong: $bad)"
}
# Enemy art (::erows) at column x (mod FWRAP), top line y: a pixel in
# pixel column col on lines lo..hi
proc art_hit {x y col lo hi} {
	set c [expr {$col - [screen_x $x]}]
	if {$c < 0 || $c > 7} { return 0 }
	set a [expr {$lo > $y ? $lo : $y}] ; set b [expr {$hi < $y + 15 ? $hi : $y + 15}]
	for {set r $a} {$r <= $b} {incr r} {
		if {([lindex $::erows [expr {$r - $y}]] >> (7 - $c)) & 1} { return 1 }
	}
	return 0
}
proc all_volleys {} {
	set r {}
	for {set i 0} {$i < $::sym(MAX_VOLLEYS)} {incr i} {
		set b [expr {$i*$::VOL}]
		set v {}
		for {set k 0} {$k <= 4} {incr k} { lappend v [m volleys [expr {$b+$k}]] }
		lappend r $v
	}
	return $r
}

set eprev {} ; set rotp 0 ; set vprev {}
set hits 0 ; set breaks 0 ; set booms_n 0 ; set hit_bad 0 ; set hit_first ""
set mot_bad 0 ; set mot_first "" ; set freeframes 0
set btop 0 ; set bbottom 0 ; set nonmirror 0 ; set dirs {} ; set bdirs {}
set wgone -1 ; set wwaited 0
set waves 0 ; set wenemy 0 ; set wcidx 0 ; set gone_sts {} ; set wave_bad 0 ; set wave_first ""
proc wave_bad {s} { if {!$::wave_bad} { set ::wave_first "frame $::n: $s" } ; incr ::wave_bad }
proc hit_bad {s} { if {!$::hit_bad} { set ::hit_first "frame $::n: $s" } ; incr ::hit_bad }
proc mot_bad {s} { if {!$::mot_bad} { set ::mot_first "frame $::n: $s" } ; incr ::mot_bad }

# One bullet at column col over lines lo..hi against the living enemies (st,
# left: the model's states, changed by the hit), in order: 1 if it hit
proc hit_one {col lo hi} {
	upvar st st left left broken broken
	for {set i 0} {$i < 8} {incr i} {
		set s [lindex $st $i]
		if {$s > 1} continue
		lassign [lindex $::eprev $i] - - - x - y
		if {![art_hit $x $y $col $lo $hi]} continue
		if {$s == 0} {
			set p [expr {$i & ~1}]
			lset st $p 1 ; lset st [expr {$p+1}] 1
			lappend broken $p [expr {$p+1}]
			incr ::breaks
			say "frame $::n: pair [expr {$p/2}] broke up (wave $::waves, phase $::ephase)"
		} else {
			lset st $i 2 ; lset left $i [m boom_frames]
			incr ::booms_n
		}
		incr ::hits
		return 1
	}
	return 0
}

# Every frame: the enemies and the volleys against a model of the frame
# from the last frame's state: booms on, the hits (old volleys by the lines
# they covered, then a new volley at its spawn lines), then the free
# enemies' flight (exact, in 1/256 px) with their bounces
proc enemy_frame {} {
	set cur {}
	for {set i 0} {$i < 8} {incr i} { lappend cur [en_state $i] }
	set vols [all_volleys]
	if {[llength $::eprev]} { enemy_model $cur $vols }
	if {!$::waves} { for {set i 0} {$i < 8} {incr i} { lappend ::sthist($i) [lindex $cur $i 0] } }
	set ::eprev $cur ; set ::vprev $vols
	set ::rotp [m enemy_rot]
	set ::flipp [m sat_flip]
	set ::fresh -1
}
proc enemy_model {cur vols} {
	set st {} ; set left {}
	foreach e $::eprev { lappend st [lindex $e 0] ; lappend left [lindex $e 1] }
	for {set i 0} {$i < 8} {incr i} {
		set s [lindex $st $i]
		if {$s >= 2 && $s < 5} {
			set l [expr {[lindex $left $i] - 1}]
			if {!$l} { incr s ; if {$s < 5} { set l [m boom_frames [expr {$s - 2}]] } }
			lset st $i $s ; lset left $i $l
		}
	}
	set broken {}
	if {!$::nohits_was} {
		set step [m bullet_step]
		set want $::vprev
		for {set v 0} {$v < 2} {incr v} {
			set xs [lassign [lindex $::vprev $v] y]
			if {!$y} continue
			set lo [expr {$y - $step}] ; set hi [expr {$y + 2}] ; set nb 0
			for {set k 0} {$k < 4} {incr k} {
				set x [lindex $xs $k]
				if {!$x} continue
				if {[hit_one $x $lo $hi]} { lset xs $k 0 } else { incr nb }
			}
			lset want $v [concat [expr {!$nb || $lo < 8 ? 0 : $lo}] $xs]
		}
		if {$::fresh >= 0} {
			lassign $::fsnap mask fx fst ; set xs {} ; set nb 0
			set y $::bstart
			for {set k 0} {$k < 4} {incr k} {
				set x 0
				if {($mask >> $k & 1) && ![lindex $fst $k]} { set x [expr {$fx + 4 + $k*$::W}] }
				if {$x && [hit_one $x $y [expr {$y + 2}]]} { set x 0 }
				if {$x} { incr nb }
				lappend xs $x
			}
			lset want $::fresh [concat [expr {$nb ? $y : 0}] $xs]
		}
		for {set v 0} {$v < 2} {incr v} {
			set w [lindex $want $v] ; set g [lindex $vols $v]
			if {([lindex $w 0] == 0 && [lindex $g 0] != 0) || ([lindex $w 0] != 0 && $w ne $g)} { hit_bad "volley $v: $g, want $w" }
		}
	}
	# every enemy gone: the frame's work that made it so starts the wait;
	# WAVE_DELAY_MS (::wdelay frames) later a frame's work begins the next
	# wave (enemy and colour the next in their lists), all in their pairs
	# at the loop's start; till then all stay gone, the wave unchanged
	if {[lsearch -not -exact $st 5] < 0 && $::wgone < 0} {
		set ::wgone $::n ; set ::gone_sts $st
		if {[m wave_wait] != $::wdelay} { wave_bad "the last one gone: wave_wait [m wave_wait], want $::wdelay" }
	}
	if {$::wgone >= 0 && $::n - $::wgone < $::wdelay} {
		if {[m form_enemy] != $::wenemy || [lsearch -not -exact [lmap e $cur {lindex $e 0}] 5] >= 0} { wave_bad "frame [expr {$::n - $::wgone}] of the wait: enemy [m form_enemy], states [lmap e $cur {lindex $e 0}]" }
		incr ::wwaited
	} elseif {$::wgone >= 0} {
		set ::wgone -1
		if {!$::waves} { for {set i 0} {$i < 8} {incr i} { lappend ::sthist($i) 5 } }
		incr ::waves
		if {$::waves == 1} { set ::coll_w1 $::coll ; set ::breaks_w1 $::breaks ; set ::bstarts_w1 $::bstarts }
		set ::wave0 [expr {$::n - 1}]
		set ::form_hist [dict create]
		set ::wenemy [expr {($::wenemy + 1) % 10}] ; set ::wcidx [expr {($::wcidx + 1) % 9}]
		if {[m form_enemy] != $::wenemy || [m form_cidx] != $::wcidx || [m form_color] != [lindex $::COLS $::wcidx]} {
			wave_bad "wave $::waves: enemy [m form_enemy], colour [m form_color], want enemy $::wenemy, colour [lindex $::COLS $::wcidx]"
		}
		set bad [form_pattern_bad]
		if {[llength $bad]} { wave_bad "wave $::waves: VRAM patterns wrong: $bad" }
		if {[m form_tick] || [m form_tick 1] || [m form_acc] || [m form_x] != $::FX0 || [m form_x 1]} { wave_bad "wave $::waves: the loop not at its start" }
		if {[m wave_n] != $::waves} { wave_bad "wave $::waves: wave_n [m wave_n]" }
		set bad [lw_bad [lw_str $::waves]]
		if {[llength $bad]} { wave_bad "wave $::waves: the top status row isn't \"[lw_str $::waves]\" (wrong: [lrange $bad 0 5])" }
		load_art
		set st {0 0 0 0 0 0 0 0}
		say "wave $::waves began at frame $::n: enemy [m form_enemy], colour [m form_color]"
	} elseif {[m form_enemy] != $::wenemy} { wave_bad "a new wave (enemy [m form_enemy]) with enemies left: $st" }
	for {set i 0} {$i < 8} {incr i} {
		lassign [lindex $::eprev $i] ps pl pxf px pyf py pd
		lassign [lindex $cur $i] cs cl cxf cx cyf cy cd
		set s [lindex $st $i]
		if {$s == 1 && $cs == 2} {
			# (free and moved: whether it touched the front, below)
		} elseif {$cs != $s || ($s >= 2 && $s < 5 && $cl != [lindex $left $i])} { hit_bad "enemy $i state $cs/$cl, want $s/[lindex $left $i]" ; continue }
		if {$s == 0} {
			if {$i & 1} {
				lassign [lindex $cur [expr {$i-1}]] - - - lx - ly
				if {$cx != ($lx + 8) % $::FWRAP || $cy != $ly} { mot_bad "enemy $i at ($cx, $cy), its pair's left one at ($lx, $ly)" }
			}
			continue
		}
		if {$s >= 2} {
			if {$s < 5 && ($cx != $px || $cy != $py || $cxf != $pxf || $cyf != $pyf)} { mot_bad "booming enemy $i moved" }
			continue
		}
		# free: from its pair's place with no fraction if it broke away now
		if {$i in $broken} {
			set pxf 0 ; set pyf 0 ; set pd $cd ; lappend ::dirs $cd
			if {!($cd & 31)} { mot_bad "enemy $i broke away level (direction $cd)" }
		}
		lassign [vel $pd] vx vy
		set x24 [expr {($px*256 + $pxf + $vx) % ($::FWRAP*256)}]
		set y16 [expr {$py*256 + $pyf + $vy}]
		set yi [expr {$y16 >> 8}]
		if {$yi + $::art_t < 8} {
			set y16 [expr {(8 - $::art_t)*256}]
			if {$cd < 1 || $cd > 31} { mot_bad "enemy $i off the top, direction $cd isn't down" }
			incr ::btop ; if {$cd != (64 - $pd) % 64} { incr ::nonmirror }
		} elseif {$yi + $::art_b > 183} {
			set y16 [expr {(183 - $::art_b)*256}]
			set ua [expr {360.0 - $cd*360.0/64}]
			if {$cd < 33 || $ua < $::sym(BOUNCE_MIN_DEG) || $ua > 180 - $::sym(BOUNCE_MIN_DEG)} { mot_bad "enemy $i off the bottom, direction $cd isn't up $::sym(BOUNCE_MIN_DEG)..[expr {180 - $::sym(BOUNCE_MIN_DEG)}] degrees" }
			lappend ::bdirs $cd
			incr ::bbottom ; if {$cd != (64 - $pd) % 64} { incr ::nonmirror }
		} elseif {$cd != $pd} { mot_bad "enemy $i turned ($pd -> $cd) away from a line" }
		set w [list [expr {$x24 & 255}] [expr {$x24 >> 8}] [expr {$y16 & 255}] [expr {$y16 >> 8}]]
		set g [list $cxf $cx $cyf $cy]
		if {$w ne $g} { mot_bad "enemy $i (xf x yf y) $g, want $w (direction $pd)" }
		if {$cy + $::art_t < 8 || $cy + $::art_b > 183} { mot_bad "enemy $i's art off the playfield (line $cy)" }
		incr ::freeframes
	}
	collide_model $cur $st $left
}

# The ship's pixels, from SHIP_PATTERN (16x16 sprite layout): "row,column"
# of the sprite
proc ship_px_init {} {
	set ::spx [dict create]
	for {set r 0} {$r < 16} {incr r} {
		for {set c 0} {$c < 16} {incr c} {
			set b [m SHIP_PATTERN [expr {$c < 8 ? $r : 16 + $r}]]
			if {($b >> (7 - ($c & 7))) & 1} { dict set ::spx "$r,$c" 1 }
		}
	}
}
# The front's slots (in alive) that the enemy art (::erows) at column x (mod
# FWRAP), top line y touches (a pixel on a pixel), the front's slot 0's art
# at column sx0
proc touches {x y sx0 alive} {
	set ex [screen_x $x]
	set r {}
	foreach k $alive {
		set sx [expr {$sx0 + $k*$::W - $::sym(SHIP_ART_L)}]
		set hit 0
		for {set j 0} {$j < 16 && !$hit} {incr j} {
			set sr [expr {$y + $j - $::sym(SHIP_TOP)}]
			if {$sr < 0 || $sr > 15} continue
			set e [lindex $::erows $j]
			for {set c 0} {$c < 8} {incr c} {
				if {!(($e >> (7 - $c)) & 1)} continue
				if {[dict exists $::spx "$sr,[expr {$ex + $c - $sx}]"]} { set hit 1 ; break }
			}
		}
		if {$hit} { lappend r $k }
	}
	return $r
}
# The enemy's art box and a living slot's ship's art box overlap
proc boxes_meet {x y sx0 alive} {
	set ex [screen_x $x]
	foreach k $alive {
		set sx [expr {$sx0 + $k*$::W}]
		if {$ex + 7 >= $sx && $ex <= $sx + $::W - 1 && $y + $::art_b >= $::sym(SHIP_TOP) && $y + $::art_t <= $::sym(SHIP_TOP) + 15} { return 1 }
	}
	return 0
}
# The collisions, after the moves: each free enemy (the model's, at its new
# place) against the ships living when collide began; every enemy and ship
# that touch: the enemy booms (image 1, its full count), the ship dies
# (likewise); the other ships as they were
set breaks_w1 0 ; set bstarts_w1 0 ; set coll_w1 0 ; set coll 0 ; set coll_ships 0 ; set coll_multi 0 ; set coll_shared 0 ; set coll_near 0
set coll_bad 0 ; set coll_first ""
proc coll_bad {s} { if {!$::coll_bad} { set ::coll_first "frame $::n: $s" } ; incr ::coll_bad }
proc collide_model {cur st left} {
	lassign $::cfront cmask cx0 cst
	set alive {}
	for {set k 0} {$k < 4} {incr k} { if {($cmask >> $k & 1) && ![lindex $cst $k]} { lappend alive $k } }
	set killed {}
	set f0 [m boom_frames]
	for {set i 0} {$i < 8} {incr i} {
		if {[lindex $st $i] != 1} continue
		lassign [lindex $cur $i] cs cl - x - y
		set t [touches $x $y $cx0 $alive]
		if {[llength $t]} {
			incr ::coll
			if {[llength $t] > 1} { incr ::coll_multi }
			foreach k $t { if {$k in $killed} { incr ::coll_shared } else { lappend killed $k } }
			if {$cs != 2 || $cl != $f0} { coll_bad "enemy $i at ($x, $y) touches ships $t (front at $cx0): state $cs/$cl, want 2/$f0" }
		} else {
			if {[boxes_meet $x $y $cx0 $alive]} { incr ::coll_near }
			if {$cs != 1} { coll_bad "enemy $i at ($x, $y) touches no ship (front at $cx0, living $alive): state $cs" }
		}
	}
	foreach k $alive {
		set g [list [m boom_stage $k] [m boom_left $k]]
		if {$k in $killed} {
			if {$g ne [list 1 $f0]} { coll_bad "ship $k touched: boom $g, want 1 $f0" }
		} elseif {[lindex $g 0]} { coll_bad "ship $k untouched: boom $g" }
	}
	incr ::coll_ships [llength $killed]
}

# The break sound, after a frame's work, as death_frame: channel B's
# volume, tone and mixer bits against the BREAK table; its noise period
# too while the death sound is silent (else the death sound's wins)
proc brk_frame {} {
	if {$::bnew} { incr ::bstarts $::bnew ; set ::bnew 0 ; set ::bidx 0 }
	set mix [psg 7]
	set got [list [psg 9] [psg 2] [psg 3] [expr {$mix & 0x12}]]
	if {$::bidx >= 0} {
		set t [expr {$::sym(BREAK_$::F) + 4*$::bidx}]
		set v [debug read memory $t]
		if {$v == 0} {
			lappend ::bruns $::bidx
			set ::bidx -1
			set want [list 0 [lindex $got 1] [lindex $got 2] 18]
		} else {
			incr ::bframes
			set want [list $v [debug read memory [expr {$t+2}]] [debug read memory [expr {$t+3}]] 0]
			if {![psg 10] && [psg 6] != [debug read memory [expr {$t+1}]]} { lappend got "R6 [psg 6]" }
			incr ::bidx
		}
	} else {
		set want [list 0 [lindex $got 1] [lindex $got 2] 18]
	}
	if {$got ne $want} {
		if {!$::bbad} { set ::bfirst "frame $::n: R9 R2 R3 mix-B $got, want $want" }
		incr ::bbad
	}
}

# The enemies' part. One ship at the left edge, no reserves. Hits on.
# 1: aim at the pairs (the test holds the arrows toward the nearest
# enemy still in a pair, and fires every 4 frames) until every pair has
# broken up; 2: 6 s without firing, the free enemies flying and bouncing
# (a screenshot); 3: aim at the free enemies until all are gone.
proc plan_enemies {} {
	check_vel_table
	# three call-ups first (reserves written in RAM): a four-ship front, so
	# that the enemies crowd its lines
	debug write memory $::sym(reserves) 3
	foreach k {0 20 40} {
		at [expr {$::n + $k + 1}] { cdown }
		at [expr {$::n + $k + 2}] { cup }
	}
	at [expr {$::n + 60}] {
		check {[m front_mask] == 15} "four ships for the enemies' part (mask [m front_mask])"
		start_enemies
	}
}
proc start_enemies {} {
	set ::nohits 0
	set ::ebhits 1 ; set ::ebk0 $::eb_kills
	set ::ephase 1
	set ::edead [expr {$::n + 100*$::F}]
	set ::dstarts0 $::dstarts
	# the art column with the most pixels: where to aim
	set best 0 ; set bc 0
	for {set c 0} {$c < 8} {incr c} {
		set k 0
		foreach r $::erows { incr k [expr {($r >> (7 - $c)) & 1}] }
		if {$k > $best} { set best $k ; set bc $c }
	}
	set ::aimcol $bc
}
proc keys {bits} {
	foreach b {0x01 0x10 0x80} { if {$bits & $b} { down $b } else { up $b } }
}
proc aim_frame {} {
	set sts {}
	for {set i 0} {$i < 8} {incr i} { lappend sts [lindex $::eprev $i 0] }
	if {$::ephase == 1 && 0 ni $sts} {
		say "every pair broke up by frame $::n"
		set ::ephase 2 ; set ::e2end [expr {$::n + 6*$::F}]
		set ::throttle on
		after realtime 0.1 {
			set ::pause on
			after realtime 0.3 { screenshot [regsub {\.png$} $::env(SHOT) {-enemies.png}] ; set ::pause off ; set ::throttle off }
		}
	}
	# (enemy bullets kill ships too: reserves kept, so that the game isn't over)
	if {$::ebhits && [m reserves] < 2} { debug write memory $::sym(reserves) 3 }
	if {$::ephase == 2} {
		keys 0
		if {$::n >= $::e2end} { set ::ephase 3 }
		return
	}
	# every enemy gone (the wait for the next wave on): stop firing; the
	# next wave flies 2 s before the staged collisions
	if {$::ephase < 4 && ($::waves || $::wgone >= 0) || $::n > $::edead} {
		set ::ephase 4 ; set ::e4end [expr {$::n + $::wdelay + 2*$::F}]
		set ::ebhits 0      ;# (the staged collisions and bounces count the ships' deaths)
	}
	if {$::ephase >= 4} {
		keys 0
		if {$::cheld} { cup ; set ::cheld 0 }
		if {$::ephase == 6} { stage_bounces ; set ::ephase 7 ; at [expr {$::n + $::F}] { set ::ephase 0 ; enemy_end } }
		if {$::ephase == 4 && $::n >= $::e4end && ![m call_on] && ![llength [volley_live]]} {
			set ::ephase 5
			stage_collisions
		}
		return
	}
	refill
	set want [expr {$::ephase == 1 ? 0 : 1}]
	set nose [expr {[m ship_x] + 4}]
	set bd 999 ; set dx 0
	for {set i 0} {$i < 8} {incr i} {
		lassign [lindex $::eprev $i] s - - x - y
		if {$s != $want} continue
		if {$want && $y + $::art_b > 150} continue
		set c [expr {[screen_x $x] + $::aimcol}]
		if {$c < 4 || $c > 250} continue
		if {abs($c - $nose) < $bd} { set bd [expr {abs($c - $nose)}] ; set dx [expr {$c - $nose}] }
	}
	set k [expr {$dx < -1 ? 0x10 : ($dx > 1 ? 0x80 : 0)}]
	# at the pairs: one volley at a time, aimed (so that the last pair's
	# break-up leaves free enemies for the next phase)
	if {$::n % 4 < 2 && ($::ephase == 3 || (!$k && $bd < 999 && ![llength [volley_live]]))} { set k [expr {$k | 0x01}] }
	keys $k
}
# While the test hunts: the front kept full, a call-up (reserves written in
# RAM) whenever the front spans fewer than 4 slots and none is flying
set cheld 0 ; set refills 0
proc refill {} {
	if {$::cheld} { cup ; set ::cheld 0 ; return }
	if {![m call_on] && [m front_slots] < 4} {
		debug write memory $::sym(reserves) 3
		cdown ; set ::cheld 1 ; incr ::refills
	}
}

# The staged collisions: the test writes a four-ship front at column 100
# and four free enemies flying straight down (direction 16), placed so
# that after their next move enemy 0 touches ships 1 and 2, enemies 2 and
# 3 both touch ship 3 only, and enemy 1's art box overlaps a ship's art
# box with no pixel on one of its pixels (the wave's own enemy's art; the
# rest of the wave in its pairs)
proc stage_collisions {} {
	set sx0 100 ; set alive {0 1 2 3}
	lassign [vel 16] vx vy
	set a {} ; set b {} ; set d {}
	for {set y [expr {$::sym(SHIP_TOP) - $::art_b}]} {$y + $::art_b <= 183} {incr y} {
		for {set x [expr {$sx0 - 8}]} {$x <= $sx0 + 4*$::W} {incr x} {
			set t [touches $x $y $sx0 $alive]
			if {$t eq {1 2} && ![llength $a]} { set a [list $x $y] }
			if {$t eq {3}} { lappend b [list $x $y] }
			if {![llength $t] && ![llength $d] && [boxes_meet $x $y $sx0 $alive]} { set d [list $x $y] }
		}
	}
	if {![llength $a] || [llength $b] < 2 || ![llength $d]} {
		fail "staged collisions: no placement found (two ships $a, ship 3 [llength $b], a near miss $d)"
		set ::ephase 0 ; enemy_end ; return
	}
	set place [list 0 $a 1 $d 2 [lindex $b 0] 3 [lindex $b end]]
	say "staged collisions (after the move): $place"
	# the score 99999890 (written): the three crashes' 3 x 50 reach the cap
	foreach k {0 1 2 3} v {0x90 0x98 0x99 0x99} { debug write memory [expr {$::sym(score) + $k}] $v }
	set ::score_model 99999890
	foreach {i at} $place {
		lassign $at x y
		set x [expr {($x - ($vx >> 8)) % $::FWRAP}] ; set y [expr {$y - ($vy >> 8)}]
		set r [expr {$::sym(enemies) + $i*$::sym(EN)}]
		foreach {f v} [list ST 1 LEFT 0 XF 0 X [expr {$x & 255}] YF 0 Y $y DIR 16] { debug write memory [expr {$r + $::sym(EN.$f)}] $v }
		debug write memory [expr {$r + $::sym(EN.X) + 1}] [expr {$x >> 8}]
	}
	for {set i 4} {$i < 8} {incr i} { debug write memory [expr {$::sym(enemies) + $i*$::sym(EN) + $::sym(EN.ST)}] 0 }
	foreach {v k} {15 front_mask 4 front_slots 36 front_w 100 ship_x} { debug write memory $::sym($k) $v }
	# (reserves, so that the near miss's enemy, flying on, can't end the game)
	debug write memory $::sym(reserves) 3
	for {set k 0} {$k < 4} {incr k} { debug write memory [expr {$::sym(boom_stage) + $k}] 0 ; debug write memory [expr {$::sym(boom_left) + $k}] 0 }
	# the next frame's model from the enemies as the test wrote them
	set ::eprev {}
	for {set i 0} {$i < 8} {incr i} { lappend ::eprev [en_state $i] }
	set ::form_skip [expr {$::n + 2}]   ;# (the SAT shown till then: from before the writes)
	set ::c0 [list $::coll $::coll_ships $::coll_multi $::coll_shared $::coll_near]
	at [expr {$::n + 1}] {
		set sts {} ; set bs {}
		for {set i 0} {$i < 4} {incr i} { lappend sts [lindex [en_state $i] 0] ; lappend bs [m boom_stage $i] }
		set sb [score_vram_bad]
		check {[score_ram] == 99999999 && $::score_model == 99999999 && ![llength $sb]} "staged collisions: from 99999890 (written), the crashes' points (3 x 50, a four-ship front) stop at 99999999 (RAM [score_ram]; its cells wrong: [lrange $sb 0 5])"
		check {$sts eq {2 1 2 2} && $bs eq {0 1 1 1} && $::dnew == 6} "staged collisions, the next frame: enemy 0 across ships 1 and 2, enemies 2 and 3 on ship 3, enemy 1 near ship art but not on it: enemies' states $sts (want 2 1 2 2), the ships' booms $bs (want 0 1 1 1), $::dnew death sound starts (want 6: 3 enemies, 3 ships)"
	}
	at [expr {$::n + 2}] {
		# (the staged frame's model ran: its counts since the staging)
		set d {}
		foreach v [list $::coll $::coll_ships $::coll_multi $::coll_shared $::coll_near] c $::c0 { lappend d [expr {$v - $c}] }
		check {$d eq {3 3 1 1 1}} "staged collisions as modelled: 3 enemies touched 3 ships, one across two ships, one ship touched by two enemies (dying once), one near miss (got $d)"
	}
	at [expr {$::n + $::F}] { set ::ephase 6 }
}

# The staged bounces (free flight's own may all end on the front first):
# enemies 0 and 2 (gone by now) written free at column 200, away from the
# front, one 2 lines under the top line flying straight up, one 2 lines
# over the bottom line flying straight down; the model checks the bounces
proc stage_bounces {} {
	set top [expr {$::sym(PLAY_TOP) - $::art_t + 2}]
	set bot [expr {183 - $::art_b - 2}]
	foreach {i y d} [list 0 $top 48 2 $bot 16] {
		set r [expr {$::sym(enemies) + $i*$::sym(EN)}]
		foreach {f v} [list ST 1 LEFT 0 XF 0 X 200 YF 0 Y $y DIR $d] { debug write memory [expr {$r + $::sym(EN.$f)}] $v }
		debug write memory [expr {$r + $::sym(EN.X) + 1}] 0
	}
	set ::eprev {}
	for {set i 0} {$i < 8} {incr i} { lappend ::eprev [en_state $i] }
	set ::b0 [list $::btop $::bbottom]
	at [expr {$::n + 5}] { check {$::btop > [lindex $::b0 0] && $::bbottom > [lindex $::b0 1]} "staged bounces: one at the top, one at the bottom (as modelled)" }
}

# A boom's states from the enemy's history: from EN_BOOM on, {state frames ...}
proc st_runs {h} {
	set r {} ; set last -1
	foreach s $h {
		if {$s < 2 && ![llength $r]} continue
		if {$s == $last} { lset r end [expr {[lindex $r end] + 1}] } else { lappend r $s 1 ; set last $s }
	}
	return $r
}
proc enemy_end {} {
	set sts $::gone_sts
	check {$::breaks_w1 == 4} "bullets broke up all 4 pairs of the first wave ($::breaks_w1; $::breaks with the second wave's)"
	check {$sts eq {5 5 5 5 5 5 5 5}} "bullets and the front blew up all 8 free enemies, all gone ($::booms_n by bullets, $::coll_w1 touching the front; states $sts)"
	check {$::coll_bad == 0 && $::coll > 0} "collisions = the model (each free enemy after its move against the ships living, a pixel on a pixel; both blow up, the rest as they were) every frame ($::coll enemies touched $::coll_ships ships, $::coll_w1 in the first wave; $::coll_near near misses; $::refills call-ups to refill the front; [expr {$::coll_bad ? "first wrong: $::coll_first" : "none wrong"}])"
	check {$::waves == 1 && $::wave_bad == 0 && $::wwaited == $::wdelay} "the last one gone, the second wave: enemy 1, colour 3, its patterns in VRAM, the loop from its start, $::wdelay frames later (0.7 s; all gone for $::wwaited frames first; $::waves waves; enemy [m form_enemy], colour [m form_color]; [expr {$::wave_bad ? "first wrong: $::wave_first" : "none wrong"}])"
	check {$::hit_bad == 0 && $::hits > 0} "hits = the model (each bullet against the enemies' art on the lines it covered, the first enemy hit, the bullet gone; pairs break, free ones boom) every frame ($::hits hits; [expr {$::hit_bad ? "first wrong: $::hit_first" : "none wrong"}])"
	check {$::mot_bad == 0 && $::freeframes > 0} "free enemies = the model (velocity table, wrap, stopped at lines 8 / 183 and turned away) every frame, booms stationary ($::freeframes enemy-frames; [expr {$::mot_bad ? "first wrong: $::mot_first" : "none wrong"}])"
	check {$::btop > 0 && $::bbottom > 0 && $::nonmirror > 0} "bounces: $::btop at the top, $::bbottom at the bottom (directions [lsort -integer -unique $::bdirs], each $::sym(BOUNCE_MIN_DEG)..[expr {180 - $::sym(BOUNCE_MIN_DEG)}] degrees up), $::nonmirror not a mirror's"
	# (at least 4 different: 7 or 8 random picks of 62 have fewer about
	# 1 in 3000 games, simulated; at least 5 failed about 1 in 300)
	check {[llength [lsort -unique $::dirs]] >= 4 && [lsearch -exact $::dirs 0] < 0 && [lsearch -exact $::dirs 32] < 0} "break-up directions at random, never level (0, 32): $::dirs"
	check {$::flip_bad == 0} "the SAT reversed every other frame, the enemies' turn one back every two ($::flip_bad wrong)"
	set want [expr {$::F == 60 ? {2 6 3 4 4 5 5} : {2 5 3 3 4 4 5}}]
	set bad {}
	for {set i 0} {$i < 8} {incr i} {
		set r [lrange [st_runs $::sthist($i)] 0 6]
		if {$r ne $want} { lappend bad "$i: $r" }
	}
	check {[llength $bad] == 0} "each enemy's boom: images 1..3 for [lindex $want 1]/[lindex $want 3]/[lindex $want 5] frames, then gone (wrong: $bad)"
	set bf [expr {$::F == 60 ? 48 : 40}]
	check {$::bstarts_w1 == 4 && $bf in $::bruns && $::bidx == -1} "break sound: $::bstarts_w1 starts in the first wave, played out in $bf frames (0.8 s; runs $::bruns)"
	check {$::bbad == 0 && $::bframes > 0} "break sound on channel B = BREAK table every frame, its noise period while the death sound is silent ($::bframes frames; [expr {$::bbad ? "first wrong: $::bfirst" : "none wrong"}])"
	set ebk [expr {$::eb_kills - $::ebk0}]
	check {$::dstarts - $::dstarts0 == $::booms_n + $::coll + $::coll_ships + $ebk} "a booming enemy, a ship touched and a ship hit by an enemy bullet (re)start the death sound ([expr {$::dstarts - $::dstarts0}] starts; $::booms_n + $::coll + $::coll_ships + $ebk)"
	check {$::vis_bad == 0 && $::frontcrowd > 0} "lines with 5..7 sprites: no sprite dropped two frames running ($::crowded crowded line-frames, $::frontcrowd frames with the front's lines crowded, $::overcrowded line-frames with 8 or more; $::vis_bad wrong)"
	check {$::edropped == 0} "no frame dropped while the enemies are hit and fly, a new wave too ($::edropped: frames $::edrops)"
	set ::nocheck 1
	set ::wseq {}
	# the bonus ships: 2 in reserve (RAM); wave 2 lost ships (the staged
	# collisions), the rest none but the one tkill 1 kills in wave 10
	debug write memory $::sym(reserves) 2
	set ::bwatch 1
	wave_step
}
# The lists' turns: the test makes every enemy gone (EN.ST = EN_GONE in
# RAM); the next frame's work starts the wait, and ::wdelay frames later
# a frame's work begins the next wave (not one frame sooner); 19 of them
# (waves 2..20: both lists wrap). The frame before each begins, the test
# puts 3 enemy bullets in flight (the model: gone the frame after).
proc wave_step {} {
	# wave 4's bonus ship: a shot sounding as it comes (the beep wins)
	if {$::waves == 3} { down 0x01 ; at [expr {$::n + 2}] { up 0x01 } }
	at [expr {$::n + 1}] {
		for {set i 0} {$i < 8} {incr i} { debug write memory [expr {$::sym(enemies) + $i*$::sym(EN) + $::sym(EN.ST)}] 5 }
	}
	at [expr {$::n + 1 + $::wdelay}] {
		eb_set [eb_some 3]     ;# (in flight as the next wave, or the boss, begins: they must go)
		if {[m form_enemy] != ($::waves % 10) || [m wave_wait] != 1} { wave_bad "wave [expr {$::waves + 1}]: began before its wait was over (enemy [m form_enemy], wave_wait [m wave_wait])" }
	}
	# after waves 5 and 10 of a level, the boss (boss_frame: the next wave
	# once it's over)
	if {$::waves % 10 == 4 || $::waves % 10 == 9} {
		at [expr {$::n + 2 + $::wdelay}] {
			if {[m boss_st] != 1 || [m form_enemy] != $::waves % 10} { wave_bad "wave [expr {$::waves + 1}]'s end: no boss (boss_st [m boss_st], enemy [m form_enemy])" ; wave_after }
		}
	} else { at [expr {$::n + 2 + $::wdelay}] wave_after }
}
# A wave began this frame (its enemy, colour, patterns, level text; the next)
proc wave_after {} {
	incr ::waves
	set w $::waves
	set we [expr {$w % 10}] ; set wc [expr {$w % 9}]
	set sts {}
	for {set i 0} {$i < 8} {incr i} { lappend sts [lindex [en_state $i] 0] }
	set bad [form_pattern_bad]
	if {[m form_enemy] != $we || [m form_cidx] != $wc || [m form_color] != [lindex $::COLS $wc] || $sts ne {0 0 0 0 0 0 0 0} || [llength $bad]} {
		wave_bad "wave $w: enemy [m form_enemy], colour [m form_color], states $sts, VRAM wrong: $bad (want enemy $we, colour [lindex $::COLS $wc])"
	}
	if {[m wave_n] != $w} { wave_bad "wave $w: wave_n [m wave_n]" }
	set bad [lw_bad [lw_str $w]]
	if {[llength $bad]} { wave_bad "wave $w: the top status row isn't \"[lw_str $w]\" (wrong: [lrange $bad 0 5])" }
	lappend ::wseq "[m form_enemy]/[m form_color]"
	if {$w == 9} { tkill 1 }   ;# (wave 10: a ship lost)
	if {$w < 20} { wave_step } else {
		check {[llength [lw_bad "L3 W1"]] == 0 && [lw_str 9] eq "L1 W10" && [lw_str 10] eq "L2 W1"} "wave 21: \"L3 W1\" on the top status row's left, the rest blank but the score (\"L2 W10\"'s last cell gone)"
		set want {1:lost 2:1 3:+1 4:1 5:+1 6:1 7:+1 8:1 9:lost 10:1 11:+1 12:1 13:full 14:1 15:full 16:1 17:full 18:1 19:full}
		set got [lrange $::bseq end-18 end]
		set bf [expr {$::F == 60 ? 15 : 13}]
		# (+1 or full: by the reserve then, which the run's randomness can
		# change, e.g. a forced call-up as the test writes the reserve;
		# bonus_frame checks each against RAM)
		set gotb [string map {+1 B full B} $got] ; set wantb [string map {+1 B full B} $want]
		check {$gotb eq $wantb && [lsearch $got *:full] >= 0 && $::bonus_bad == 0 && $::b_awards >= 3 && $::b_vram == $::b_awards && [lsort -unique $::beepruns] eq $bf && [llength $::beepruns] == $::b_awards && $::beepshot > 0} "bonus ships: 2 waves in a row with no ship lost, a reserve ship more (none at RESERVE_MAX; a ship lost starts the count again), shown in the reserve that frame, the happy beep on channel A as the BONUS table every frame ($bf frames, [format %.2f [expr {double($bf)/$::F}]] s; $::beepshot of them over a shot) (waves 2..20 at wave_n:streak/lost/+1/full: $got; $::b_awards bonus ships, beeps $::beepruns; [expr {$::bonus_bad ? "first wrong: $::bonus_first" : "none wrong"}])"
		check {$::wave_bad == 0} "waves 3..21 (enemy/colour; the level and wave on the top status row: L1 W1 .. L1 W10, L2 W1 ..): $::wseq ([expr {$::wave_bad ? "first wrong: $::wave_first" : "none wrong"}])"
		boss_end
		at [expr {$::n + 3}] plan_eb_levels    ;# (after this wave's wipe of the test's bullets)
	}
}

# Every frame: which sprites the VDP drops (past the 4th on a line, in the
# SAT shown's order); a sprite (front slot, incoming ship, enemy entry)
# dropped on a line with 5..7 sprites must show there the next frame
set vis_bad 0 ; set crowded 0 ; set overcrowded 0 ; set frontcrowd 0 ; set vprevhid [dict create]
proc vis_frame {} {
	set lines [dict create]
	for {set k 0} {$k < 13} {incr k} {
		set y [sat [expr {4*$k}]]
		if {$y == 0xD0} break
		set e [expr {$::flipp ? 12 - $k : $k}]
		set o [expr {$e < 5 ? $e : 5 + ($::rotp + $e - 5) % 8}]
		for {set l [expr {$y + 1}]} {$l <= $y + 16 && $l < 192} {incr l} { dict lappend lines $l $o }
	}
	set hid [dict create] ; set fc 0
	dict for {l objs} $lines {
		set c [llength $objs]
		if {$c <= 4} continue
		incr ::crowded
		if {$l >= 168} { set fc 1 }
		if {$c > 7} { incr ::overcrowded ; continue }
		foreach o [lrange $objs 4 end] {
			if {[dict exists $::vprevhid "$o,$l"]} { incr ::vis_bad }
			dict set hid "$o,$l" 1
		}
	}
	incr ::frontcrowd $fc
	set ::vprevhid $hid
}


# ---- The boss ----------------------------------------------------------------
# From the spec: after waves 5 and 10 of a level, the boss (images/boss1.png,
# 64 x 16, four sprites; its art from BOSS_PATTERN) on the playfield's
# first lines, cruising left and right, bumping into the playfield's edges
# (columns 0..192), one way in 6 s (32 px/s, from the left end going right); its
# bullets rain from a random column of its lower edge (their top on line
# 24) at the last wave's speed, at the rate that keeps 5 in flight: one
# every gap px they move (gap = ceil((158 + the longest step - 1) / 5): a
# bullet goes after 158 px); it starts in FORM_COLOR_REDDENING's first
# colour, every 10 hits the next; 10 hits in the last: it dies, booming as
# 8 ship booms side by side (in its colour, the ship's boom frame counts);
# then "BONUS ddd POINTS" (500 by the front's share as it died) in the
# screen's middle for 2 s; then the points, and the next wave.
set REDDEN {5 7 3 2 10 11 9 8 13}
set bwatch 0 ; set bosses 0 ; set bshots_now 0 ; set boffs {} ; set bfront_n {4 1 2 3}
set bbad 0 ; set bfirst "" ; set bm {} ; set bhist {} ; set bres {} ; set bdead_alive -1
proc bbad {s} { if {!$::bbad} { set ::bfirst "frame $::n: $s" } ; incr ::bbad }
proc bpx {x l} {
	# the boss's art pixel in its column x (0..63), row l
	expr {([m BOSS_PATTERN [expr {($x >> 3)*16 + $l}]] >> (7 - $x % 8)) & 1}
}
proc bstep_x {k} {
	set d [expr {32*$k / $::F}] ; set p [expr {$d % 384}]
	expr {$p <= 192 ? $p : 384 - $p}
}
proc bgap {} {
	set pct $::sym(BOSS_EB_PCT)
	set smax [expr {(230*$pct + 100*$::F - 1) / (100*$::F)}]
	expr {(158 + $smax - 1 + 4) / 5}
}
# the boss's bullet fired: its place (HL), under its art, from one of its columns
cart_bp $sym(boss_fire.shoot) {} {
	if {!$::started} return
	set hl [reg HL]
	set b [list [debug read memory $hl] [debug read memory [expr {$hl+1}]]]
	set o [expr {[lindex $b 1] - [m boss_x]}]
	if {[lindex $b 0] != 24 || $o < 0 || $o > 63} { bbad "a boss bullet at $b (boss at [m boss_x])" }
	lappend ::boffs $o
	lappend ::eb_spawned $b
	incr ::bshots_now
}
cart_bp $sym(boss_dies) {} {
	if {$::started} {
		set ::bdead_alive [living [front_now]]
		if {[m boss_kind]} { set ::b2_vanished 1 ; set ::b2_ebwipe 1 }   ;# (Boss2: its enemies and bullets gone at once)
	}
}
proc vols {} {
	set r {}
	for {set i 0} {$i < $::sym(MAX_VOLLEYS)} {incr i} {
		set v {} ; for {set k 0} {$k <= 4} {incr k} { lappend v [m volleys [expr {$i*$::VOL + $k}]] }
		lappend r $v
	}
	return $r
}
# The boss's SAT entries ({x name colour}, sorted) in the SAT shown, and as
# its state {st x colour} wants them
proc boss_sat_got {} {
	set r {}
	for {set e 0} {$e < 13} {incr e} { if {[sat [expr {4*$e}]] == 7 && [sat [expr {4*$e+2}]] >= 32} { lappend r [list [sat [expr {4*$e+1}]] [sat [expr {4*$e+2}]] [sat [expr {4*$e+3}]]] } }
	lsort $r
}
proc boss_sat_want {st x c} {
	set r {}
	if {$st >= 1 && $st <= 4} {
		set nm [expr {$st == 1 ? 32 : 48 + 16*($st - 2)}]
		for {set k 0} {$k < 4} {incr k} { lappend r [list [expr {$x + 16*$k}] [expr {$nm + 4*$k}] $c] }
	}
	lsort $r
}
proc set_front {k x} {
	foreach {v f} [list [expr {(1 << $k) - 1}] front_mask $k front_slots [expr {$k*$::W}] front_w $x ship_x] { debug write memory $::sym($f) $v }
	for {set i 0} {$i < 4} {incr i} { debug write memory [expr {$::sym(boom_stage) + $i}] 0 ; debug write memory [expr {$::sym(boom_left) + $i}] 0 }
}
# Every frame of the waves' part: the boss against the model (::bm: its
# state after the last frame's work), the test fighting it
proc boss_frame {} {
	set st [m boss_st]
	if {![llength $::bm]} {
		if {$st} { bbad "a boss with none expected (wave [m wave_n])" }
		set ::bm [list 0] ; return
	}
	lassign $::bm pst px pc pk
	# the SAT shown: built after the last frame's work (Boss2 fighting: in
	# the bitmap, none)
	set sw [expr {$pst && !($pst == 1 && $pk ne "" && $pk) ? [boss_sat_want $pst $px $pc] : {}}]
	set sg [boss_sat_got]
	if {$sg ne $sw} { bbad "the SAT's boss entries $sg, want $sw" }
	if {$pst == 0} {
		if {!$st} return
		# it began this frame (instead of the next wave)
		incr ::bosses
		set ::b0 $::n ; set ::bacc 0 ; set ::bgap [bgap] ; set ::bdrop0 $::dropped
		set ::bhits 0 ; set ::bcidx 0 ; set ::bshots 0 ; set ::bmin 9 ; set ::bmax 0 ; set ::bhist {} ; set ::btext 0 ; set ::bdead_alive -1
		set ::bwave [list [m form_enemy] [m wave_n] [m level]]
		if {[m boss_kind]} { b2_begin $st ; return }
		set bad {}
		for {set i 0} {$i < 16*32} {incr i} {
			if {[debug read VRAM [expr {0x3800 + 32*8 + $i}]] != [m BOSS_PATTERN $i]} { lappend bad $i ; break }
		}
		if {[m boss_x] != 0 || [m boss_dir] || [m boss_hits] || [m boss_cidx] || [m boss_color] != 5 || [m boss_gap] != $::bgap || $st != 1 || [m form_enemy] % 5 != 4 || [llength $bad]} {
			bbad "boss [expr {$::bosses}] began: st $st x [m boss_x] dir [m boss_dir] hits [m boss_hits]/[m boss_cidx] colour [m boss_color] gap [m boss_gap] (want 0 0 0/0 5 $::bgap), after wave [expr {[m form_enemy] + 1}], patterns wrong at $bad"
		}
		set ::bm [list 1 [m boss_x] [m boss_color] 0]   ;# (as this frame's SAT has it: before the writes)
		# the fight: a front of 4, 1, 2, 3 ships (bosses 1..4); boss 1
		# fought all through (the score 0 first), the others with 1 hit left
		set k [lindex $::bfront_n [expr {($::bosses - 1) % 4}]]
		set_front $k [expr {[m boss_x] + 32 - $k*$::W/2}]
		if {$::bosses == 1} {
			foreach i {0 1 2 3} { debug write memory [expr {$::sym(score) + $i}] 0 }
			debug write memory $::sym(score_dirty) 1
			set ::score_model 0 ; set ::sc_shown 1
		} else {
			debug write memory $::sym(boss_hits) 9 ; debug write memory $::sym(boss_cidx) 8 ; debug write memory $::sym(boss_color) 13
			set ::bhits 9 ; set ::bcidx 8
		}
		set ::bvprev [vols]
		set ::bshots_now 0
		set ::brk_seen $::brk_all
		return
	}
	set k [expr {$::n - $::b0}]
	if {$pst == 1 && $pk} { b2_frame $st }
	if {$pst == 1 && !$pk} {
		# this frame's hits: each bullet of the last frame's volleys, in
		# order, over the lines it covered (its new top to its old bottom)
		# against the art where the boss showed
		set step [m bullet_step]
		set mst 1 ; set gone {}
		set vi 0
		foreach v $::bvprev {
			lassign $v y
			if {$y} {
				for {set j 1} {$j <= 4} {incr j} {
					set x [lindex $v $j]
					if {!$x || $mst != 1} continue
					set c [expr {$x - $px}]
					if {$c < 0 || $c > 63} continue
					set hit 0
					for {set l [expr {$y - $step}]} {$l <= $y + 2} {incr l} {
						if {$l >= 8 && $l < 24 && [bpx $c [expr {$l - 8}]]} { set hit 1 ; break }
					}
					if {!$hit} continue
					lappend gone [list $vi $j $y $x]
					incr ::bhits_all
					if {[incr ::bhits] == 10} {
						set ::bhits 0
						if {[incr ::bcidx] == 9} { set mst 2 }
					}
				}
			}
			incr vi
		}
		set cur [vols]
		foreach g $gone {
			lassign $g vi j y x
			set v [lindex $cur $vi]
			if {[lindex $v 0] == $y - $step && [lindex $v $j] == $x} { bbad "a bullet that hit the boss flies on ($v)" }
		}
		set wc [expr {$mst == 1 ? [lindex $::REDDEN $::bcidx] : 13}]
		if {$st != $mst || ($mst == 1 && ([m boss_hits] != $::bhits || [m boss_cidx] != $::bcidx)) || [m boss_color] != $wc} {
			bbad "the boss after its hits: st $st hits [m boss_hits]/[m boss_cidx] colour [m boss_color], want $mst $::bhits/$::bcidx $wc"
		}
		if {$mst == 2 && $::bdead_alive != [m boss_alive]} { bbad "the boss died with the front's living ships $::bdead_alive, boss_alive [m boss_alive]" }
		# its rain: one every gap px the bullets moved, while it fights
		set want 0
		if {$mst == 1} {
			incr ::bacc [m eb_step]
			if {$::bacc >= $::bgap} { incr ::bacc -$::bgap ; set want 1 }
		}
		if {$::bshots_now != $want} { bbad "$::bshots_now boss bullets fired, want $want (acc $::bacc, gap $::bgap)" }
		# each hit (re)starts the break sound
		if {$::brk_all - $::brk_seen != [llength $gone]} { bbad "[expr {$::brk_all - $::brk_seen}] break sound starts, want [llength $gone] (one a hit)" }
		incr ::bbrk [llength $gone]
		incr ::bshots $::bshots_now
		set live [eb_live]
		if {$live > 5} { bbad "$live boss bullets in flight" }
		if {$::bshots > 5 && $mst == 1} {
			if {$live < $::bmin} { set ::bmin $live }
			if {$live > $::bmax} { set ::bmax $live }
		}
		# its move: 32 px/s, back from either end
		if {$mst == 1 && [m boss_x] != [bstep_x $k]} { bbad "the boss at [m boss_x], want [bstep_x $k] ([format %.2f [expr {double($k)/$::F}]] s in)" }
		if {$mst == 1} { boss_hunt } else { keys 0 }
	}
	set ::bshots_now 0
	if {$st >= 2} { lappend ::bhist $st }
	# its bonus text
	set pts [expr {500*[lindex $::SHARES [ships_in [m boss_alive]]]/100}]
	if {$st == $::sym(BS_BONUS) && ![m over_text]} {
		# (its first frame: its first BONUS_HALF cells only, the others
		# not its yet: the bitmap model has them)
		set txt "BONUS $pts POINTS" ; set nc 16
		if {!$::btext} { set nc $::sym(BONUS_HALF) ; set txt [string range $txt 0 $nc-1] }
		incr ::btext
		set bad [text_bad $::sym(OVER_ROW) 8 $txt $nc]
		set mw [expr {$::btext == 1 ? 8*$::sym(BONUS_HALF) : 128}]
		if {[llength $bad] || ![m mid_text] || [m mid_x0] != 64 || [m mid_w] != $mw} { bbad "the bonus text's frame $::btext isn't \"$txt\" in row 12 from column 8 (wrong: [lrange $bad 0 3]; mid [m mid_text] [m mid_x0] [m mid_w])" }
	}
	if {$pst == $::sym(BS_BONUS) && $st != $::sym(BS_BONUS)} {
		# its end: the text gone, the points; the next wave the next frame
		set bad [text_bad $::sym(OVER_ROW) 8 "" 16]
		if {[llength $bad] || [m mid_text]} { bbad "the bonus text not gone (wrong: [lrange $bad 0 3])" }
		if {$::sc_boss != 1} { bbad "$::sc_boss boss scores at its end" }
		if {$st != $::sym(BS_NEXT)} { bbad "the bonus over: boss_st $st, want $::sym(BS_NEXT) (the next wave next frame)" }
		eb_set [eb_some 3]     ;# (in flight as the next wave begins: they must go)
		set ::bm [list $st 0 0]
		return
	} elseif {$::sc_boss} { bbad "$::sc_boss boss scores in state $st" }
	if {$pst == $::sym(BS_NEXT)} {
		if {$st} { bbad "the next wave not begun after the bonus (boss_st $st)" }
		set F $::F
		set runs [st_runs $::bhist]
		set want [list 2 [expr {$F == 60 ? 6 : 5}] 3 [expr {$F == 60 ? 4 : 3}] 4 [expr {$F == 60 ? 5 : 4}] $::sym(BS_GAP) 1 $::sym(BS_BONUS) [expr {2*$F}] $::sym(BS_NEXT) 1]
		lassign $::bwave we wn wl
		set ok [expr {$runs eq $want && $::btext == 2*$F && ($::bshots <= 5 || $::bmin >= 4 && $::bmax == 5) && $::dropped == $::bdrop0}]
		lappend ::bres [list $::bosses [ships_in [m boss_alive]] $pts $k $ok]
		if {$::bosses == 1} {
			set ::b1 [list $runs $want $::bhits_all $::bshots $::bmin $::bmax $::btext [expr {$::dropped - $::bdrop0}] $::score_model]
		}
		if {!$ok} { bbad "boss $::bosses: states $runs (want $want), text $::btext frames, $::bmin..$::bmax bullets in flight, [expr {$::dropped - $::bdrop0}] frames dropped" }
		set ::bm [list 0]
		wave_after
		return
	}
	if {$st == 0 && $pst != 7} { bbad "the boss gone in state $pst" }
	set ::bvprev [vols]
	set ::bm [list $st [m boss_x] [m boss_color] [m boss_kind]]
	set ::brk_seen $::brk_all
}
set bhits_all 0 ; set bbrk 0
# The test fights the boss: the front's middle under the boss's, fire
# pressed every other frame
proc boss_hunt {} {
	set t [expr {[m boss_x] + 32 - [m front_w]/2}]
	set x [m ship_x]
	set k [expr {$x < $t - 1 ? 0x80 : ($x > $t + 1 ? 0x10 : 0)}]
	if {$::n % 2} { set k [expr {$k | 0x01}] }
	keys $k
}
proc boss_end {} {
	set ::bwatch 0
	set offs [lsort -integer -unique $::boffs]
	check {$::bbad == 0 && $::bosses == 4} "bosses after waves 5, 10, 15 and 20 = the model every frame: its sprites (patterns, colour, place), 32 px/s between columns 0 and 192, its rain (one every gap px at 70% of 230 px/s whatever the wave, 5 in flight at most, 4 or 5 once it's going), the hits (each bullet on its art: gone, the break sound (re)started ($::bbrk starts); every 10 the next colour of 5 7 3 2 10 11 9 8 13; 10 in 13: it dies), its booms, \"BONUS ddd POINTS\" for 2 s, its points by the front's share as it died, the next wave ($::bosses bosses: {boss ships points frames ok} $::bres; [expr {$::bbad ? "first wrong: $::bfirst" : "none wrong"}])"
	lassign $::b1 runs want hits shots mn mx txt drop sc
	check {$hits == 90 && $sc == 250 && [llength $offs] >= 32 && [lindex $offs 0] >= 0 && [lindex $offs end] <= 63} "boss 1, fought through by a 4-ship front: 90 hits ([expr {$hits}]), states $runs (want $want), $shots bullets from [llength $offs] of its 64 columns ($mn..$mx in flight), the bonus text $txt frames, the score 0 + 250 = $sc, $drop frames dropped"
	b2_end
}

# ---- Boss2 -------------------------------------------------------------------
# From the spec: after wave 10 of a level (bosses 2 and 4 here) Boss2
# (images/boss2.png) instead of the boss: still, in the bitmap at the
# playfield's top, centred (columns 96..159, lines 8..23), in the boss's
# first colour (its white stays white). Under it, 8 blank lines between,
# a line of 3 pairs of one random enemy (6 enemies at most), each pair a
# random colour of the waves', 8 blank px between pairs' arts, swerving
# left and right at a constant speed, a 4-pair line's (its range, a slot
# less than the 3 pairs', in 0.5 s): at its left end the leftmost art
# pixel on column 56, at its right end the rightmost on 199 (from its
# middle, going right). 4 living enemies or fewer: a new pair (17 at most)
# in a free slot of the line, coming down from above the screen in 0.5 s,
# the line still meanwhile, one at a time (not hit before its art is all
# on screen, not shooting while it comes). Its pairs break up and fly as
# a wave's; its hits and colours as the boss's; a bullet of the enemies'
# (wave 1's: 70%, at most 3 in flight) may come from it, line 24, any of
# its columns. Its death: every enemy and bullet gone at once; then as the
# boss. The test fights it as the boss, and makes free enemies gone once
# their art passes line 120 (so they never reach the front, and spawns
# come); its points from the enemies are written off at its death (the
# score as it began), so the bonuses add up as before.
set b2res {} ; set b2_shots 0 ; set b2cols {} ; set b2slots {}
proc b2px {x l} { expr {([m BOSS2_PATTERN [expr {($x >> 3)*16 + $l}]] >> (7 - $x % 8)) & 1} }
proc b2_enemy {} { expr {([m form_rows] + 256*[m form_rows 1] - $::sym(ENEMY_PATTERN)) / 32} }
proc b2_ens {} {
	set r {}
	for {set i 0} {$i < 8} {incr i} { lassign [en_state $i] st - - x - y ; lappend r [list $st $x $y] }
	return $r
}
proc b2_snap {} { list [m b2_desc] [m b2_spawned] [b2_ens] }
# the line's place after m frames of swerving
proc b2_pos_at {m} {
	set R $::b2R
	set p [expr {($R/2 + $m*2*$::b2Rs/$::F) % (2*$R)}]
	expr {$p <= $R ? $p : 2*$R - $p}
}
# 1: an enemy (in a pair or free; its art box all on screen) of ens has a
# pixel of its art in column x on one of lines lo..hi
proc b2_en_on {ens x lo hi} {
	foreach en $ens {
		lassign $en st ex ey
		if {$st > 1 || $ey > 200} continue
		set c [expr {$x - [screen_x $ex]}]
		if {$c < 0 || $c > 7} continue
		for {set l $lo} {$l <= $hi} {incr l} {
			set r [expr {$l - $ey}]
			if {$r >= 0 && $r < 16 && ([m ENEMY_PATTERN [expr {$::b2e*32 + $r}]] >> (7 - $c) & 1)} { return 1 }
		}
	}
	return 0
}
# The pairs at their slots' places (the one coming down drem lines above)
proc b2_places {pos desc drem} {
	set bad {}
	for {set p 0} {$p < 3} {incr p} {
		lassign [en_state [expr {2*$p}]] st - - x - y
		if {$st} continue
		lassign [en_state [expr {2*$p+1}]] st1 - - x1 - y1
		set s [m b2_slot $p]
		set wx [expr {$::b2x0 + $pos + $s*$::b2step}]
		set wy [expr {$desc == $p + 1 ? ($::b2land - $drem) & 255 : $::b2land}]
		if {$st1 || $x != $wx || $x1 != $wx + 8 || $y != $wy || $y1 != $wy} { lappend bad "pair $p (slot $s) at $x,$y $x1,$y1, want $wx,$wy" }
	}
	return $bad
}
proc b2_bcd {v} {
	for {set k 0} {$k < 4} {incr k} { debug write memory [expr {$::sym(score) + $k}] [expr {[scan [format %02d [expr {$v % 100}]] %x]}] ; set v [expr {$v / 100}] }
}
proc b2_begin {st} {
	set e [b2_enemy] ; set ::b2e $e
	set l [m ENEMY_COLS [expr {2*$e}]] ; set r [m ENEMY_COLS [expr {2*$e+1}]] ; set t [m ENEMY_ROWS [expr {2*$e}]]
	set W [expr {9 + $r - $l}]
	# 3 slots; the speed a 4-pair line's: its range (one slot less) in 0.5 s
	set ::b2step [expr {$W + 8}] ; set ::b2R [expr {144 - 3*$W - 16}] ; set ::b2x0 [expr {56 - $l}]
	set ::b2Rs [expr {$::b2R - $::b2step}]
	set ::b2land [expr {32 - $t}] ; set ::b2dfull [expr {$::b2land + 16}]
	set ::b2m 0 ; set ::b2dk 0 ; set ::b2n 0 ; set ::b2lands {} ; set ::b2removed 0 ; set ::b2def 0 ; set ::b2maybe 0
	set ::b2waits 0 ; set ::b2s0 $::score_model ; set ::b2h 0
	set bad [form_pattern_bad $e]
	set cols {}
	for {set p 0} {$p < 3} {incr p} {
		set c0 [m enemies [expr {2*$p*$::sym(EN) + $::sym(EN.COL)}]] ; set c1 [m enemies [expr {(2*$p+1)*$::sym(EN) + $::sym(EN.COL)}]]
		if {$c0 != $c1 || $c0 ni $::COLS || [m b2_slot $p] != $p} { lappend bad "pair $p colour $c0/$c1 slot [m b2_slot $p]" }
		lappend cols $c0
	}
	if {[en_sts] ne {0 0 0 0 0 0 5 5}} { lappend bad "states [en_sts]" }
	if {$::b2x0 + $l != 56 || $::b2x0 + $::b2R + 2*$::b2step + 8 + $r != 199} { lappend bad "the line's ends" }
	set bad [concat $bad [b2_places [b2_pos_at 0] 0 0]]
	if {$st != 1 || [m boss_x] != 96 || [m boss_hits] || [m boss_cidx] || [m boss_color] != 5 || ![m b2_shown] || [m b2_pos] != $::b2R/2 || [m b2_dir] || [m b2_desc] || [m b2_spawned] || [m form_enemy] != 9 || [llength $bad]} {
		bbad "Boss2 ($::bosses) began: st $st x [m boss_x] hits [m boss_hits]/[m boss_cidx] colour [m boss_color] shown [m b2_shown] pos [m b2_pos] (want [expr {$::b2R/2}]) dir [m b2_dir] desc [m b2_desc] spawned [m b2_spawned] after wave [expr {[m form_enemy] + 1}]; wrong: $bad"
	}
	set ::bm [list 1 [m boss_x] [m boss_color] 1]
	# the fight: Boss2's first fought all through, the second with 1 hit left
	set k [lindex $::bfront_n [expr {($::bosses - 1) % 4}]]
	set_front $k [expr {[m boss_x] + 32 - $k*$::W/2}]
	if {$::bosses > 2} {
		debug write memory $::sym(boss_hits) 9 ; debug write memory $::sym(boss_cidx) 8 ; debug write memory $::sym(boss_color) 13
		for {set i 0} {$i < 128} {incr i} {
			set c [m BOSS2_COL $i] ; if {$c < 16} { set c [expr {$c | 0xD0}] }
			debug write VRAM [expr {0x2000 + 256*(1 + $i/64) + 96 + $i%64}] $c
		}
		set ::b2h 89
	}
	set ::bvprev [vols]
	set ::bshots_now 0
	set ::brk_seen $::brk_all
	set ::b2p [b2_snap]
	lappend ::b2cols $cols
}
proc b2_frame {st} {
	lassign $::b2p desc0 sp0 ens0
	set sts [en_sts]
	# the hits: the last frame's bullets on its art, over the lines each
	# covered (an enemy's art there too, in front of it: maybe the enemy's)
	set step [m bullet_step]
	set hnow [expr {$st == 1 ? 10*[m boss_cidx] + [m boss_hits] : 90}]
	set def 0 ; set maybe 0 ; set defs {}
	foreach v $::bvprev {
		set y [lindex $v 0] ; if {!$y} continue
		foreach x [lrange $v 1 end] {
			if {!$x} continue
			set c [expr {$x - 96}] ; if {$c < 0 || $c > 63} continue
			set lo [expr {$y - $step}] ; set hi [expr {$y + 2}]
			set ba 0
			for {set l $lo} {$l <= $hi} {incr l} { if {$l >= 8 && $l < 24 && [b2px $c [expr {$l - 8}]]} { set ba 1 ; break } }
			if {!$ba} continue
			if {[b2_en_on $ens0 $x $lo $hi]} { incr maybe } else { incr def ; lappend defs [list $y $x] }
		}
	}
	set left [expr {90 - $::b2h}] ; set d [expr {$hnow - $::b2h}]
	set lo [expr {$def < $left ? $def : $left}] ; set hi [expr {$def + $maybe < $left ? $def + $maybe : $left}]
	if {$d < $lo || $d > $hi} { bbad "Boss2: $d hits, want $lo..$hi ($def on its art alone, $maybe with an enemy's)" }
	incr ::b2def $def ; incr ::b2maybe $maybe
	if {$st == 1} {
		foreach g $defs {
			lassign $g y x
			foreach v [vols] { if {[lindex $v 0] == $y - $step && $x in [lrange $v 1 end]} { bbad "a bullet that hit Boss2 flies on ($v)" } }
		}
	}
	# the break sound: each hit, each pair broken up
	set brk 0
	for {set i 0} {$i < 8} {incr i 2} { if {[lindex $ens0 $i 0] == 0 && [lindex $sts $i] ni {0 5}} { incr brk } }
	if {$::brk_all - $::brk_seen != $d + $brk} { bbad "Boss2: [expr {$::brk_all - $::brk_seen}] break sound starts, want [expr {$d + $brk}] ($d hits, $brk pairs broken)" }
	set ::b2h $hnow
	if {$::bshots_now} { bbad "Boss2 rained the boss's bullets" }
	if {$st != 1} {
		# it died: every enemy and bullet gone that frame (but a volley fired after it)
		set vl [volley_live]
		set vbad [expr {[llength $vl] > 1 || ([llength $vl] && [lindex $vl 0 0] != $::sym(BULLET_START))}]
		if {[en_sts] ne {5 5 5 5 5 5 5 5} || [m b2_shown] || [eb_live] || [m b2_desc] || $vbad || [m boss_color] != 13 || $::bdead_alive != [m boss_alive]} {
			bbad "Boss2 died: states [en_sts], shown [m b2_shown], [eb_live] enemy bullets, volleys $vl, desc [m b2_desc], colour [m boss_color], alive [m boss_alive] (want $::bdead_alive)"
		}
		lappend ::b2res [list $::bosses $::b2e $::b2n [lsort -unique $::b2lands] $::b2removed $::b2waits [expr {$::score_model - $::b2s0}] $::b2def $::b2maybe]
		b2_bcd $::b2s0 ; debug write memory $::sym(score_dirty) 1
		set ::score_model $::b2s0 ; set ::sc_shown 1
		keys 0
		return
	}
	if {[m boss_color] != [lindex $::REDDEN [m boss_cidx]] || [m boss_hits] > 9} { bbad "Boss2: hits [m boss_hits]/[m boss_cidx], colour [m boss_color]" }
	# the swerve (frames with no pair coming down at their start)
	set desc [m b2_desc] ; set sp [m b2_spawned]
	if {[lrange $sts 6 7] ne {5 5}} { bbad "Boss2: enemies 6 and 7 not gone ([en_sts]): at most 6 enemies" }
	if {$desc0 == 0} { incr ::b2m }
	set pos [m b2_pos]
	if {$pos != [b2_pos_at $::b2m]} { bbad "Boss2's line at [m b2_pos], want [b2_pos_at $::b2m] (after $::b2m frames)" }
	if {$desc0} {
		# coming down: 0.5 s from B2_DESC_FROM above line 0 (shot: over)
		set p [expr {$desc0 - 1}]
		if {[lindex $sts [expr {2*$p}]] != 0} {
			if {$desc} { bbad "Boss2's spawn broken up, still coming down" }
		} else {
			incr ::b2dk
			set rem [expr {$::b2dfull - $::b2dk*2*$::b2dfull/$::F}]
			if {$rem <= 0} {
				lappend ::b2lands $::b2dk
				if {$desc || [m b2_drem]} { bbad "Boss2's spawn landed: desc $desc, drem [m b2_drem]" }
			} elseif {$desc != $desc0 || [m b2_drem] != $rem} { bbad "Boss2's spawn: desc $desc drem [m b2_drem], want $desc0 $rem (frame $::b2dk)" }
		}
		if {$sp != $sp0} { bbad "Boss2 spawned while one came down" }
	} elseif {$sp != $sp0} {
		set p [expr {$desc - 1}]
		set live 0
		for {set i 0} {$i < 8} {incr i} { if {$i/2 != $p && [lindex $sts $i] < 2} { incr live } }
		set c0 [m enemies [expr {2*$p*$::sym(EN) + $::sym(EN.COL)}]] ; set c1 [m enemies [expr {(2*$p+1)*$::sym(EN) + $::sym(EN.COL)}]]
		set s [m b2_slot $p] ; set taken {}
		for {set q 0} {$q < 3} {incr q} { if {$q != $p && [lindex $sts [expr {2*$q}]] == 0} { lappend taken [m b2_slot $q] } }
		if {$sp != $sp0 + 1 || $sp0 >= 17 || $p < 0 || $p > 2 || $s > 2 || $live > 4 || [lrange $sts [expr {2*$p}] [expr {2*$p+1}]] ne {0 0} || $c0 != $c1 || $c0 ni $::COLS || $s in $taken || [m b2_drem] != $::b2dfull} {
			bbad "Boss2's spawn $sp: pair $p, $live others living, states [lrange $sts [expr {2*$p}] [expr {2*$p+1}]], colours $c0/$c1, slot $s (taken: $taken), drem [m b2_drem] (want $::b2dfull)"
		}
		set ::b2dk 0 ; incr ::b2n ; lappend ::b2slots $s
	} else {
		# none: due (4 living or fewer, spawns left) only if no record
		# pair could be freed (enemies still booming)
		set live 0 ; foreach c $sts { if {$c < 2} { incr live } }
		if {$sp0 < 17 && $live <= 4} {
			set both 0 ; set half 0
			for {set p 0} {$p < 3} {incr p} {
				set g [expr {([lindex $sts [expr {2*$p}]] == 5) + ([lindex $sts [expr {2*$p+1}]] == 5)}]
				if {$g == 2} { incr both } elseif {$g == 1} { incr half }
			}
			if {$both || $half >= 2} { bbad "Boss2: no spawn with $live living (states $sts)" }
			incr ::b2waits
		}
	}
	set bad [b2_places $pos $desc [m b2_drem]]
	if {[llength $bad]} { bbad "Boss2's pairs: $bad" }
	# the test fights it, and takes free enemies off past line 120
	boss_hunt
	set ab [m form_art_b]
	for {set i 0} {$i < 8} {incr i} {
		lassign [en_state $i] est - - - - ey
		if {$est == 1 && $ey + $ab > 120} { debug write memory [expr {$::sym(enemies) + $i*$::sym(EN) + $::sym(EN.ST)}] 5 ; incr ::b2removed }
	}
	set ::b2p [b2_snap]
}
proc b2_end {} {
	set F $::F
	set ok 1
	foreach r $::b2res {
		lassign $r boss e n lands removed waits pts def maybe
		if {$lands ne "" && $lands ne [expr {$F/2}]} { set ok 0 }
	}
	lassign [lindex $::b2res 0] - - n1
	check {[llength $::b2res] == 2 && [lindex $::b2res 0 0] == 2 && [lindex $::b2res 1 0] == 4 && $ok && $n1 == 17 && [llength [lsort -unique $::b2slots]] >= 2 && $::b2_bitmaps > 0 && $::b2_shots > 0} "Boss2 after wave 10 (bosses 2 and 4): in the bitmap (its art, its colours every frame), its line of 3 pairs of a random enemy (random colours; enemies 6 and 7 gone), swerving at a 4-pair line's speed (its range in 0.5 s) between columns 56 and 199, spawns (4 living or fewer, a free slot, coming down in [expr {$F/2}] frames, the line still, one at a time, 17 at most; the free slots each picked), its hits and colours, its bullets ($::b2_shots from it), its death (every enemy and bullet gone that frame) ({boss enemy spawns landings-frames taken-off waits points hits-alone hits-maybe}: $::b2res; colours $::b2cols; slots $::b2slots)"
}

# ---- The enemies' bullets ---------------------------------------------------
# From the spec: wave w (0 the first): speed 70% of the player's bullet's
# (230 px/s) in the first wave, +7% a wave, from the 8th on 119%; at most
# 3 in flight in waves 1..3, 4 in 4..6, 5 from the 7th on. A roll every
# 0.25 s; one in 4 fires, from a random enemy (in a pair or free) whose
# art's last row is at least 8 lines above the front's art's first, if
# fewer than the most are in flight.
proc eb_spec {w} {
	if {$w eq "boss"} { return [list $::sym(BOSS_EB_PCT) $::sym(EB_N)] }
	set pct [expr {70 + 7*($w < 7 ? $w : 7)}]
	set mx [expr {$w < 3 ? 3 : ($w < 6 ? 4 : 5)}]
	list $pct $mx
}
# The slots: {Y X} each (Y 0: none)
proc eb_list {} {
	set r {}
	for {set i 0} {$i < $::sym(EB_N)} {incr i} { lappend r [list [m ebullets [expr {2*$i}]] [m ebullets [expr {2*$i+1}]]] }
	return $r
}
proc eb_live {} { set k 0 ; foreach b [eb_list] { if {[lindex $b 0]} { incr k } } ; return $k }
# The enemies that can shoot, from RAM now: their bullets' places {Y X}
# (under the art's last row, the art's column EB_DX, on screen)
proc eb_cands {} {
	set ab [m form_art_b]
	set last [expr {$::sym(SHIP_TOP) + $::sym(SHIP_ART_T) - 8}]
	set desc [m b2_desc]
	set r {}
	for {set i 0} {$i < 8} {incr i} {
		lassign [en_state $i] st - - x - y
		if {$st > 1 || $y + $ab > $last} continue
		if {$desc && $i/2 == $desc - 1} continue   ;# (Boss2's spawn coming down)
		set c [expr {[screen_x $x] + $::sym(EB_DX)}]
		if {$c < 0 || $c > 255} continue
		lappend r [list [expr {$y + $ab + 1}] $c]
	}
	# Boss2 fighting: one more, at line 24, from any of its columns (b2)
	if {[m boss_st] == 1 && [m boss_kind]} { lappend r b2 }
	return $r
}
set b2_ebwipe 0
set ebon 0 ; set eb_bad 0 ; set eb_first "" ; set eb_force 0 ; set eb_expect "" ; set eb_cands {}
set eb_rolls {} ; set eb_nat 0 ; set eb_nathit 0 ; set eb_full 0 ; set eb_none 0 ; set eb_spawns 0
set eb_spawned {} ; set eb_prev {} ; set eb_w 0 ; set eb_epoch -1 ; set eb_S 0 ; set eb_k 0
set eb_speed [dict create] ; set eb_ranks [dict create] ; set eb_last "" ; set eb_rolled 0 ; set eb_rolled_now 0
set eb_gone 0 ; set eb_maxseen [dict create] ; set eb_frames 0 ; set cs_on 0 ; set lv_res {}
proc eb_bad {s} { if {!$::eb_bad} { set ::eb_first "frame $::n: $s" } ; incr ::eb_bad }
# A new wave begun (next_wave): the next frame, every enemy bullet goes
set eb_fresh 0 ; set eb_began 0 ; set eb_wipe 0 ; set eb_wiped 0 ; set eb_wipes 0
cart_bp $sym(next_wave.go) {} { if {$::started} { set ::eb_began 1 } }
# Enemy bullets hit the front's ships only while ::ebhits (else eb_hit
# returns at once, no hit: the parts before the enemies' and after it don't
# expect ships to die). The front as eb_move begins ({on front}) and as
# fire begins (after eb_move: {front, boom_left 0..3}) for the model.
set ebhits 0 ; set ebsnap "" ; set ebpost "" ; set eb_kills 0 ; set eb_shiphits 0 ; set ebk0 0
set ebs_bad 0 ; set ebs_first "" ; set ebs_near 0
proc ebs_bad {s} { if {!$::ebs_bad} { set ::ebs_first "frame $::n: $s" } ; incr ::ebs_bad }
cart_bp $sym(eb_hit) {} {
	if {$::started && !$::ebhits} { reg pc [peek16 [reg sp]] ; reg sp [expr {[reg sp] + 2}] ; reg F [expr {[reg F] & 0xFE}] }
}
cart_bp $sym(eb_move) {} { if {$::started} { set ::ebsnap [list $::ebhits [front_now]] } }
cart_bp $sym(fire) {} {
	if {$::started} {
		set l {} ; for {set k 0} {$k < 4} {incr k} { lappend l [m boom_left $k] }
		set ::ebpost [list [front_now] $l]
	}
}
# The front's ship (in alive, slot 0's art at column sx0) whose art has a
# pixel in column x on one of lines lo..hi, or -1
proc eb_ship_hit {x lo hi sx0 alive} {
	foreach k $alive {
		set c [expr {$x - ($sx0 + $k*$::W)}]
		if {$c < 0 || $c >= $::W} continue
		incr c $::sym(SHIP_ART_L)
		for {set l $lo} {$l <= $hi} {incr l} {
			if {[dict exists $::spx "[expr {$l - $::sym(SHIP_TOP)}],$c"]} { return $k }
		}
		if {$hi >= $::sym(SHIP_TOP)} { incr ::ebs_near }
	}
	return -1
}
# The roll (A, after rand): the decision against the model
cart_bp $sym(enemy_fire.rolled) {} { try eb_roll }
proc eb_roll {} {
	if {!$::started} return     ;# (the MSX2 BIOS boots with ROM code at these addresses too)
	if {$::eb_force} { reg A [expr {[reg A] & 0xFC}] } else { incr ::eb_nat }
	set a [reg A]
	if {$::ebon} { lappend ::eb_rolls $::n }
	set ::eb_rolled 1
	set ::eb_last ""
	if {$a & 3} return
	if {!$::eb_force} { incr ::eb_nathit }
	set n [eb_live]
	lassign [eb_spec [expr {[m boss_st] ? 0 : [m wave_n]}]] - mx   ;# (a boss: wave 1's most)
	set c [eb_cands]
	set ::eb_cands $c
	if {$n >= $mx} { incr ::eb_full ; set ::eb_last [list full $n $mx] ; return }
	if {![llength $c]} { incr ::eb_none ; set ::eb_last [list none $n $mx] ; return }
	set ::eb_expect $c
	set ::eb_last [list spawn $n $mx]
}
# The bullet fired: its place {Y X} (at HL), one of the model's
cart_bp $sym(enemy_fire.shoot) {} { try eb_shoot }
proc eb_shoot {} {
	if {!$::started} return
	set hl [reg HL]
	set b [list [debug read memory $hl] [debug read memory [expr {$hl+1}]]]
	set k [lsearch -exact $::eb_expect $b]
	if {$k < 0 && "b2" in $::eb_expect && [lindex $b 0] == 24 && [lindex $b 1] >= 96 && [lindex $b 1] < 160} {
		set k [lsearch -exact $::eb_expect b2] ; incr ::b2_shots
	}
	if {$k < 0} { eb_bad "a bullet at $b, not from an enemy able to shoot ($::eb_expect; last roll $::eb_last)" ; return }
	dict incr ::eb_ranks "$k/[llength $::eb_expect]"
	set ::eb_expect ""
	incr ::eb_spawns
	lappend ::eb_spawned $b
}
# Every frame: the slots from last frame's, each moved down this frame's
# step (gone if it hit a ship, with ::ebhits on: a pixel of the ship's art
# in its column on a line from its old top to its new bottom, the front as
# eb_move began; gone once its bottom would pass line 183), then a new one in the
# first free slot; the step: Bresenham at the wave's speed (the wave as
# when the step was worked out: last frame's end), exact; at most the
# wave's most in flight
proc eb_frame {} {
	set cur [eb_list]
	set step [m eb_step]
	set w $::eb_w
	if {[llength $::eb_prev]} {
		incr ::eb_frames
		set fresh $::eb_fresh
		lassign [eb_spec $w] pct mx
		set v [expr {230*$pct}] ; set U [expr {100*$::F}]
		if {$w != $::eb_epoch} { set ::eb_epoch $w ; set ::eb_S 0 ; set ::eb_k 0 }
		incr ::eb_S $step ; incr ::eb_k
		if {abs($::eb_S*$U - $::eb_k*$v) >= $U} { eb_bad "wave $w: $::eb_S px in $::eb_k frames, want [format %.2f [expr {double($::eb_k)*$v/$U}]]" }
		dict set ::eb_speed $w [list $::eb_S $::eb_k]
		set want {}
		set wiped 0
		set alive {} ; set killed {} ; set sx0 0
		lassign $::ebsnap on fr
		if {$on ne "" && $on} {
			lassign $fr mk sx0 st
			for {set k 0} {$k < 4} {incr k} { if {($mk >> $k & 1) && ![lindex $st $k]} { lappend alive $k } }
		}
		set b2w $::b2_ebwipe ; set ::b2_ebwipe 0
		foreach p $::eb_prev {
			lassign $p y x
			if {$y && ($::eb_wipe || $b2w)} { set y 0 ; incr wiped }
			if {$y && [llength $alive]} {
				set k [eb_ship_hit $x $y [expr {$y + $step + 2}] $sx0 $alive]
				if {$k >= 0} { set y 0 ; incr ::eb_shiphits ; if {$k ni $killed} { lappend killed $k } }
			}
			if {$y} { set y [expr {$y + $step}] ; if {$y + 2 > 183} { set y 0 ; incr ::eb_gone } }
			lappend want [list $y $x]
		}
		if {$wiped && !$fresh} { incr ::eb_wipes ; incr ::eb_wiped $wiped }
		foreach b $::eb_spawned {
			set k [lsearch -index 0 -exact $want 0]
			if {$k < 0} { eb_bad "a bullet fired with no free slot" ; break }
			lset want $k $b
		}
		foreach wb $want cb $cur {
			if {$fresh} break
			if {[lindex $wb 0] == 0 ? [lindex $cb 0] != 0 : $wb ne $cb} { eb_bad "slots $cur, want $want (step $step)" ; break }
		}
		# the ships the bullets hit start to die (boom image 1, its full
		# count) in eb_move; the other living ones don't
		if {!$fresh && [llength $alive]} {
			lassign $::ebpost pf pl
			set f0 [m boom_frames]
			foreach k $alive {
				set g [list [lindex $pf 2 $k] [lindex $pl $k]]
				if {$k in $killed} {
					if {$g ne [list 1 $f0]} { ebs_bad "ship $k hit by an enemy bullet: boom $g, want 1 $f0" }
				} elseif {[lindex $g 0]} { ebs_bad "ship $k not hit: boom $g" }
			}
			if {[lrange $pf 0 1] ne [lrange $fr 0 1]} { ebs_bad "the front moved in eb_move: $fr -> $pf" }
			incr ::eb_kills [llength $killed]
		}
		set n [eb_live]
		lassign [eb_spec [m wave_n]] - mx2
		if {[m boss_st] || $::eb_began} { set mx2 $::sym(EB_N) }   ;# (the boss's, till the next wave's wipe)
		if {$n > $mx2} { eb_bad "$n in flight, wave [m wave_n]'s most $mx2" }
		if {![dict exists $::eb_maxseen $mx2] || $n > [dict get $::eb_maxseen $mx2]} { dict set ::eb_maxseen $mx2 $n }
	}
	foreach b $cur { lassign $b y ; if {$y && ($y < 8 || $y + 2 > 183)} { eb_bad "a bullet at line $y" } }
	set ::eb_spawned {}
	set ::eb_fresh 0
	set ::ebsnap ""
	set ::eb_wipe $::eb_began ; set ::eb_began 0
	set ::eb_prev $cur
	set ::eb_w [expr {[m boss_st] ? "boss" : [m wave_n]}]   ;# (what eb_speed sees next frame)
}
# The test's own enemy bullets (slots in order; {Y X}, the rest none), the
# ones drawn now taken off the bitmap first
proc eb_set {bs} {
	foreach b [eb_list] {
		lassign $b y x
		if {!$y} continue
		for {set r $y} {$r < $y + 3} {incr r} { debug write VRAM [expr {($r/8)*256 + ($x/8)*8 + $r%8}] 0 }
	}
	for {set i 0} {$i < $::sym(EB_N)} {incr i} {
		lassign [expr {$i < [llength $bs] ? [lindex $bs $i] : {0 0}}] y x
		debug write memory [expr {$::sym(ebullets) + 2*$i}] $y
		debug write memory [expr {$::sym(ebullets) + 2*$i + 1}] $x
	}
	set ::eb_prev [eb_list]
	set ::eb_fresh 1     ;# (eb_frame, if it runs after this frame: nothing to compare)
	set ::bitmap_skip 1
}
# k bullets for eb_set, on lines no star is on (so that their erase next
# frame takes no star's pixel); the first two in one byte column, a line
# apart (bytes they share)
proc eb_some {k} {
	set used [lmap e [star_list] {lindex $e 1}]
	for {set y 12} {$y < 80} {incr y} {
		set ok 1
		for {set r $y} {$r < $y + 4} {incr r} { if {$r in $used} { set ok 0 } }
		if {$ok} break
	}
	set r {}
	foreach b [list [list $y 18] [list [expr {$y+1}] 20] [list $y 60] [list $y 100] [list $y 140]] { if {[llength $r] < $k} { lappend r $b } }
	return $r
}

# The levels (after the waves; of the per-frame models only the enemy
# bullets' and the bitmap's on): the wave now (21: the speed and most as
# the 8th's / 7th's), then waves 1..8 (wave_n written); rolls forced to
# hit. At each: the bullets in flight set to one fewer than the most (two
# sharing bytes): the next roll fires; then set to the most: the next
# roll doesn't.
proc plan_eb_levels {} {
	check {[m wave_n] == 20} "after 21 waves, the wave counter at 20 (wave_n [m wave_n])"
	set ::eb_force 1
	set ::lv_list {20 0 1 2 3 4 5 6 7}
	lv_next
}
proc lv_next {} {
	if {![llength $::lv_list]} { unset ::lv_on ; eb_clear_stage ; return }
	set ::lv_list [lassign $::lv_list w]
	set ::lv_w $w
	debug write memory $::sym(wave_n) $w
	set ::eb_w $w    ;# (eb_frame ran: the next frame's step is this wave's)
	eb_set {}
	set ::lv_on wait1
}
proc lv_frame {} {
	if {!$::eb_rolled_now} return
	lassign [eb_spec $::lv_w] pct mx
	switch $::lv_on {
		wait1 { eb_set [eb_some [expr {$mx - 1}]] ; set ::lv_on wait2 }
		wait2 {
			set ::lv_spawn $::eb_last
			eb_set [eb_some $mx] ; set ::lv_on wait3
		}
		wait3 {
			set ok [expr {[lindex $::lv_spawn 0] eq "spawn" && [lindex $::lv_spawn 1] == $mx - 1 && [lindex $::eb_last 0] eq "full" && [lindex $::eb_last 1] == $mx}]
			lassign [dict get $::eb_speed $::lv_w] S k
			set sp [expr {double($S) * $::F / $k}]
			lappend ::lv_res "wave [expr {$::lv_w + 1}] [format %.1f $sp] px/s"
			check {$ok && $k >= $::F/2 && abs($sp - 2.3*$pct) * $k < $::F} "enemy bullets, wave [expr {$::lv_w + 1}]: [format %.1f $sp] px/s over $k frames (want [expr {23*$pct/10.0}], $pct%); $mx in flight at most: with [expr {$mx-1}] a hit roll fires ($::lv_spawn), with $mx not ($::eb_last)"
			lv_next
		}
	}
}
# The 8-line rule at its edge: every enemy free, flying level (direction
# 0), its art's last row on line 161 (7 lines over the front's art's first,
# 168), enemy 5's on 160 (8 lines over): rolls forced to hit, only enemy 5
# shoots; then enemy 5 on 161 too: none does
proc eb_clear_stage {} {
	set e [m form_enemy] ; set ab [m ENEMY_ROWS [expr {2*$e+1}]]
	for {set i 0} {$i < 8} {incr i} {
		set y [expr {($i == 5 ? 160 : 161) - $ab}]
		set x [expr {$i == 5 ? 10 : 40 + 28*$i}]
		set r [expr {$::sym(enemies) + $i*$::sym(EN)}]
		foreach {f v} [list ST 1 LEFT 0 XF 0 X $x YF 0 Y $y DIR 0] { debug write memory [expr {$r + $::sym(EN.$f)}] $v }
		debug write memory [expr {$r + $::sym(EN.X) + 1}] 0
	}
	eb_set {}
	set ::cs0 $::eb_spawns
	set ::cs_bad 0 ; set ::cs_rolls 0
	set ::cs_on 1
	set ::eb_rolled_now 0    ;# (this frame's roll was before the writes)
	at [expr {$::n + 3*$::F/2}] {
		set ::cs_on 0
		set s [expr {$::eb_spawns - $::cs0}]
		check {$s >= 3 && $::cs_rolls >= 5 && !$::cs_bad} "enemy bullets: of enemies whose art's last row is on line 161 or 160, only the one on 160 (8 lines over the front's art) shoots ($s bullets in $::cs_rolls rolls; $::cs_bad with others able)"
		set e [m form_enemy] ; set ab [m ENEMY_ROWS [expr {2*$e+1}]]
		debug write memory [expr {$::sym(enemies) + 5*$::sym(EN) + $::sym(EN.Y)}] [expr {161 - $ab}]
		set ::cs1 [list $::eb_spawns $::eb_none]
		at [expr {$::n + $::F}] {
			set s [expr {$::eb_spawns - [lindex $::cs1 0]}] ; set z [expr {$::eb_none - [lindex $::cs1 1]}]
			check {$s == 0 && $z >= 3} "enemy bullets: every enemy too close to the front (art's last row on 161): none shoots ($s bullets; $z hit rolls with none able)"
			set ::eb_force 0
			stage_eb_hits
		}
	}
}
# Enemy bullets on ships, staged (the bullets written in RAM, all 5 slots:
# no new one): a four-ship front at a column where no star is in the
# bullets' bitmap bytes; next frame: one on ship 0's nose and one on
# ship 1's art's column 0, deep (row 10 on), hit them; one in ship 2's
# column 0 over rows 0..7 (none of its pixels there) misses, flying on; two
# on ship 3 (its nose, its column 8) hit it, dying once: ships 0, 1 and 3
# die, 3 death sound starts
proc stage_eb_hits {} {
	if {[m call_on]} { at [expr {$::n + 1}] stage_eb_hits ; return }
	set T $::sym(SHIP_TOP) ; set W $::W ; set nose $::sym(SHIP_NOSE_DX)
	set stars [star_list]
	for {set sx0 40} {$sx0 < 200} {incr sx0} {
		set bs [list [list [expr {$T - 4}] [expr {$sx0 + $nose}]] [list [expr {$T + 9}] [expr {$sx0 + $W}]] \
			[list [expr {$T - 2}] [expr {$sx0 + 2*$W}]] [list [expr {$T - 4}] [expr {$sx0 + 3*$W + $nose}]] \
			[list [expr {$T + 9}] [expr {$sx0 + 3*$W + 8}]]]
		set ok 1
		foreach b $bs {
			lassign $b y x
			foreach e $stars {
				lassign $e sx sy
				if {$sy >= $y && $sy <= $y + 12 && ($sx/8 == $x/8 || ($sx-1)/8 == $x/8)} { set ok 0 }
			}
		}
		if {$ok} break
	}
	if {!$ok} { fail "enemy bullets on ships, staged: no column free of stars" ; eb_stage_end ; return }
	foreach {v k} [list 15 front_mask 4 front_slots [expr {4*$W}] front_w $sx0 ship_x 3 reserves] { debug write memory $::sym($k) $v }
	for {set k 0} {$k < 4} {incr k} { debug write memory [expr {$::sym(boom_stage) + $k}] 0 ; debug write memory [expr {$::sym(boom_left) + $k}] 0 }
	eb_set $bs
	set ::ebstage $bs
	set ::ebhits 1 ; set ::dnew 0
	say "staged enemy bullets on the front at column $sx0: $bs"
	at [expr {$::n + 1}] {
		set ::ebhits 0
		set st {} ; set lf {}
		for {set k 0} {$k < 4} {incr k} { lappend st [m boom_stage $k] ; lappend lf [m boom_left $k] }
		set f0 [m boom_frames]
		set c [lindex $::ebstage 2]
		set want {}
		foreach b $::ebstage { lappend want [list 0 [lindex $b 1]] }
		lset want 2 0 [expr {[lindex $c 0] + [m eb_step]}]
		set got [eb_list]
		check {$st eq {1 1 0 1} && $lf eq [list $f0 $f0 0 $f0] && $got eq $want && $::dnew == 3} "enemy bullets on ships, staged, the next frame: ship 0 hit on its nose, ship 1 low on its art's column 0, ship 3 by two bullets (dying once) blow up; one in ship 2's column 0 over rows without pixels flies on: booms $st/$lf (want 1 1 0 1, $f0 frames), bullets $got (want $want), $::dnew death sound starts (want 3)"
		eb_stage_end
	}
}
proc eb_stage_end {} {
	eb_end
	final_checks
	plan_over 1
}
proc cs_frame {} {
	if {!$::cs_on || !$::eb_rolled_now} return
	incr ::cs_rolls
	# (enemy 5 alone, as it was at the roll: its bullet's top on line 161)
	if {[llength $::eb_cands] != 1 || [lindex $::eb_cands 0 0] != 161} { incr ::cs_bad }
}
proc eb_end {} {
	check {$::ebs_bad == 0} "enemy bullets on ships = the model every frame with hits on: a ship whose art has a pixel in a bullet's column on a line it covered (its old top to its new bottom) blows up, once, the bullet gone; the others unchanged ($::eb_shiphits bullets hit, $::eb_kills ships; $::ebs_near passed a living ship's art box missing it; [expr {$::ebs_bad ? "first wrong: $::ebs_first" : "none wrong"}])"
	check {$::eb_bad == 0 && $::eb_frames > 10*$::F} "enemy bullets = the model every frame: each down the wave's speed (Bresenham, exact), gone past line 183, a new one from an enemy able to shoot, under its art, in the first free slot; never more than the wave's most ($::eb_frames frames, $::eb_spawns fired, $::eb_gone gone at the bottom; [expr {$::eb_bad ? "first wrong: $::eb_first" : "none wrong"}])"
	set r $::eb_rolls ; set bad 0
	set n0 [lindex $r 0]
	for {set k 1} {$k < [llength $r]} {incr k} { if {abs(4*([lindex $r $k] - $n0) - $k*$::F) >= 4} { incr bad } }
	set gaps [lsort -integer -unique [lmap a [lrange $r 0 end-1] b [lrange $r 1 end] {expr {$b - $a}}]]
	check {[llength $r] > 100 && $bad == 0} "enemy bullets: a roll every 0.25 s ([llength $r] rolls, gaps $gaps frames, none a frame or more off)"
	check {$::eb_wipes >= 19 && $::eb_wiped >= 57} "enemy bullets: all of the last wave's gone (erased) the frame the new wave shows ($::eb_wiped bullets at $::eb_wipes new waves)"
	set fr [expr {double($::eb_nathit) / $::eb_nat}]
	check {$::eb_nat > 100 && $fr > 0.15 && $fr < 0.35} "enemy bullets: one roll in 4 hits ($::eb_nathit of $::eb_nat: [format %.3f $fr]; $::eb_full hit rolls with the most in flight, $::eb_none with no enemy able)"
	check {[dict size $::eb_ranks] >= 6} "enemy bullets: the shooter at random among those able (pick/able: $::eb_ranks)"
	set sp {}
	foreach w {0 1} { if {[dict exists $::eb_speed $w]} { lassign [dict get $::eb_speed $w] S k ; lappend sp "wave [expr {$w+1}] [format %.1f [expr {double($S)*$::F/$k}]] px/s" } }
	say "enemy bullets in play: $sp; most in flight seen per cap: $::eb_maxseen; levels: $::lv_res"
}

# Game over, twice, after the waves (per-frame models off). 1: the test
# leaves 1 reserve (RAM) and kills the front (tkill 1 2 3 4): the
# last reserve is called up by itself, no game over; killed again: GAME
# OVER that frame, and the game runs on (the front can't move, shoot or
# call up; the formation and stars move); space and joystick 2's button A
# pressed one frame before 3 s and held past it change nothing; back to
# the title after exactly 10 s. A new game: as at power-on. 2 and 3: no
# reserves, the front killed: GAME OVER; a press of joystick 1's button A
# (2) or space (3) seen exactly at 3 s: the title at once. Then a fourth
# game, for the screenshot.
set a [expr {$sym(OVER_TEXT) - $sym(CODE_BASE)}]
set OVER [string range $rom $a [expr {[string first "\0" $rom $a] - 1}]]
check {$OVER eq "GAME OVER"} "game over: the text is \"$OVER\""
# The screen's middle row (OVER_ROW, in the playfield): the text centred in
# font.py's glyphs, white on black ($shown: the addresses wrong), or not
# there (no letter's cell holds its glyph: the letters wrong)
set OCOL [expr {(32 - [string length $OVER]) / 2}]
check {$OCOL == $sym(OVER_COL) && $sym(OVER_ROW) == 12} "game over: the text's cells: row $sym(OVER_ROW) (lines 96..103, the screen's middle), from column $OCOL"
proc over_text_bad {shown} {
	if {$shown} { return [text_bad $::sym(OVER_ROW) $::OCOL $::OVER [string length $::OVER]] }
	set bad {}
	for {set k 0} {$k < [string length $::OVER]} {incr k} {
		if {[string index $::OVER $k] eq " "} continue
		if {![llength [text_bad $::sym(OVER_ROW) [expr {$::OCOL + $k}] [string index $::OVER $k] 1]]} { lappend bad [string index $::OVER $k] }
	}
	return $bad
}
proc check_over_text {shown what} {
	set bad [over_text_bad $shown]
	check {[llength $bad] == 0} "$what (wrong at: [lrange $bad 0 5])"
}
# During game over 1: star 0 moved onto a free line of the text's glyph
# rows, near its right end, and an enemy bullet over its middle: both fly
# through the text (the star left, the bullet down) not drawn in its
# cells, and show again past them
proc over_stage {} {
	lassign [lindex [star_list] 0] x y on
	if {$on} {
		set a [expr {($y/8)*256 + ($x & 0xF8) + $y%8}]
		debug write VRAM $a 0
		debug write VRAM [expr {0x2000 + $a}] 0xF1
	}
	set used [lmap e [lrange [star_list] 1 end] {lindex $e 1}]
	set ny -1
	for {set l [expr {$::sym(OVER_ROW)*8}]} {$l < $::sym(OVER_ROW)*8 + 6} {incr l} { if {$l ni $used} { set ny $l ; break } }
	if {$ny < 0} { fail "game over: no free line for star 0 in the text's row" ; return }
	set b $::sym(stars)
	debug write memory $b [expr {($::OCOL + [string length $::OVER])*8 - 3}]
	debug write memory [expr {$b+1}] $ny
	debug write memory [expr {$b+2}] 0
	eb_set [list [list [expr {$::sym(OVER_ROW)*8 - 6}] [expr {$::OCOL*8 + 36}]]]
	set ::ostage 1 ; set ::os_star 0 ; set ::os_eb 0 ; set ::os_star_out 0 ; set ::os_eb_out 0 ; set ::os_bad {}
}
# Every frame of game over (1: with over_stage's star and bullet)
set otext_bad 0 ; set otext_frames 0 ; set ostage 0
proc over_on_frame {} {
	incr ::otext_frames
	set bad [over_text_bad 1]
	if {[llength $bad] && !$::otext_bad} { set ::otext_first "frame [expr {$::n - $::N0}]: [lrange $bad 0 5]" }
	if {[llength $bad]} { incr ::otext_bad }
	if {!$::ostage} return
	set x0 [expr {$::OCOL*8}] ; set x1 [expr {$x0 + [string length $::OVER]*8}]
	lassign [lindex [star_list] 0] x y on
	set a [expr {($y/8)*256 + ($x & 0xF8) + $y%8}]
	if {$x >= $x0 && $x < $x1} { incr ::os_star ; if {$on} { lappend ::os_bad "star shown at $x" } } elseif {$x < $x0 && ![bullet_in $x $y]} {
		if {!$on || [debug read VRAM $a] != (0x80 >> ($x%8)) || [debug read VRAM [expr {0x2000 + $a}]] != 0xE1} { lappend ::os_bad "star not shown at $x" } else { incr ::os_star_out }
	}
	lassign [lindex [eb_list] 0] t bx
	set r0 [expr {$::sym(OVER_ROW)*8}]
	if {$t && $t + 2 >= $r0 && $t < $r0 + 8} { incr ::os_eb } elseif {$t >= $r0 + 8} {
		set ok 1
		for {set r $t} {$r < $t + 3} {incr r} { if {!([debug read VRAM [expr {($r/8)*256 + ($bx & 0xF8) + $r%8}]] & (0x80 >> ($bx%8)))} { set ok 0 } }
		if {$ok} { incr ::os_eb_out } else { lappend ::os_bad "bullet not shown at line $t" }
	}
}
proc kill_all {} { tkill 1 2 3 4 }
proc plan_over {g} {
	set ::ebon 0     ;# (the per-frame enemy bullet model: not across the restarts)
	if {[m call_on]} { at [expr {$::n+1}] [list plan_over $g] ; return }
	set ::games $g
	debug write memory $::sym(reserves) [expr {$g == 1 ? 1 : 0}]
	if {$g == 2} { score_write [lindex $::hi end 0] }   ;# (a tie with the table's last: short of it)
	if {$g == 3} { stage_bonus_over ; return }
	set ::ostate [expr {$g == 1 ? "kill" : "wait"}]
	kill_all
}
# Game over 3 comes during a boss's bonus text: the boss written in its
# frame after its last boom (BS_GAP; a one-ship front as it died: 500 points);
# the next frame its text shows; then the front killed: GAME OVER takes its
# place (the text's other cells blank), the bonus runs on unseen: 2 s after
# its text came, the points and the next wave (L1 W2), GAME OVER intact
set obonus 0
proc stage_bonus_over {} {
	foreach {f v} [list boss_st $::sym(BS_GAP) boss_left 1 boss_alive 1 boss_x 96 boss_color 13] { debug write memory $::sym($f) $v }
	set ::obonus 1 ; set ::ob0 $::n ; set ::osc0 $::score_model
	at [expr {$::n + 1}] {
		set h [string range "BONUS 500 POINTS" 0 $::sym(BONUS_HALF)-1]
		set bad [text_bad $::sym(OVER_ROW) 8 $h $::sym(BONUS_HALF)]
		check {![llength $bad] && [m bonus_text] && [m boss_st] == $::sym(BS_BONUS)} "game over 3, staged: the boss's frame after its last boom over, \"$h\" (its first half; one ship) in the screen's middle (wrong: [lrange $bad 0 5])"
	}
	at [expr {$::n + 2}] {
		set bad [text_bad $::sym(OVER_ROW) 8 "BONUS 500 POINTS" 16]
		check {![llength $bad] && [m bonus_text] && [m boss_st] == $::sym(BS_BONUS)} "game over 3, staged: the next frame, all of \"BONUS 500 POINTS\" (wrong: [lrange $bad 0 5])"
		set ::ostate wait
		kill_all
	}
	at [expr {$::n + 1 + 2*$::F}] {
		set ::obonus_mid [list [m boss_st] [m form_enemy] [expr {$::score_model - $::osc0}]]
	}
	at [expr {$::n + 2 + 2*$::F}] {
		set ::obonus_end [list {*}$::obonus_mid [m boss_st] [m form_enemy]]
	}
}
# Every frame from plan_over until game over begins
proc over_frame {} {
	switch $::ostate {
		kill {
			if {[m front_mask]} return
			check {[m call_on] && [m reserves] == 0 && ![m over_on]} "game over 1, first: the front emptied with 1 in reserve: called up by itself, no game over (call_on [m call_on], over_on [m over_on])"
			check_over_text 0 "... no \"$::OVER\" in the screen's middle"
			set ::ostate land
		}
		land {
			if {[m call_on] || ![m front_mask]} return
			kill_all
			set ::ostate wait
		}
		wait {
			if {[m front_mask]} return
			set ::N0 $::n ; set ::odropped $::dropped ; set ::ostate on
			check {![m call_on] && [m reserves] == 0 && [m over_on]} "game over $::games: the front emptied with none in reserve (frame $::n): no call-up, game over (call_on [m call_on], over_on [m over_on])"
			check_over_text 1 "game over $::games: \"$::OVER\" centred on the screen's middle row, white on black, from that frame"
			if {$::obonus} {
				set bad [text_bad $::sym(OVER_ROW) 8 "   $::OVER" 16]
				check {![llength $bad] && ![m bonus_text] && [m boss_st] == $::sym(BS_BONUS)} "game over 3, during the boss's bonus text: \"$::OVER\" in its place, its other cells blank, the bonus running on (boss_st [m boss_st]; wrong: [lrange $bad 0 5])"
			}
			set ::otext_bad 0 ; set ::otext_frames 0 ; set ::ostage 0
			if {$::games == 1} over_plan_10 else over_plan_skip
		}
		on { over_on_frame }
	}
}
proc over_plan_10 {} {
	set N0 $::N0 ; set F $::F
	set ::ox [m ship_x] ; set ::ostar [m stars $::sym(STAR)]   ;# (star 1: over_stage moves star 0)
	set ::oform [list [m form_tick] [m form_tick 1] [m form_x]]
	set ::owant [expr {10*$F}]
	set ::owhy "10 s; space and joystick 2's button A pressed one frame before 3 s and held past it ignored"
	at [expr {$N0+$F}] {
		over_stage
		set ::spawns 0 ; down 0x81 ; cdown
		set ::throttle on
		after realtime 0.1 {
			set ::pause on
			after realtime 0.3 { screenshot [regsub {\.png$} $::env(SHOT) {-over.png}] ; set ::pause off ; set ::throttle off }
		}
	}
	at [expr {$N0+$F+1}] { up 0x01 ; cup }
	at [expr {$N0+2*$F}] {
		up 0x80
		check {[m ship_x] == $::ox && $::spawns == 0 && [llength [volley_live]] == 0 && ![m call_on] && [m front_mask] == 0 && [m reserves] == 0} "game over: right, fire and C do nothing (ship_x [m ship_x], $::spawns shots, call_on [m call_on], mask [m front_mask])"
		check {[list [m form_tick] [m form_tick 1] [m form_x]] ne $::oform && [m stars $::sym(STAR)] != $::ostar} "game over: the game runs on (the formation and the stars move)"
	}
	at [expr {$N0+3*$F-2}] { down 0x01 ; joydown 2 0x10 }
	at [expr {$N0+3*$F+5}] { up 0x01 ; joyup 2 }
	at [expr {$N0+10*$F-1}] {
		check {[m over_on]} "game over: still on in its last frame"
		check_over_text 1 "game over: \"$::OVER\" still shows in its last frame"
	}
	at [expr {$N0+10*$F+2}] { if {$::ostate eq "on"} { fail "game over: no return to the title after 10 s" ; finish } }
}
proc over_plan_skip {} {
	set ::owant [expr {3*$::F}]
	if {$::games == 2} {
		set ::owhy "joystick 1's button A pressed, seen exactly at 3 s: at once"
		at [expr {$::N0+3*$::F-1}] { joydown 1 0x10 }
	} else {
		set ::owhy "space pressed, seen exactly at 3 s: at once"
		at [expr {$::N0+3*$::F-1}] { down 0x01 }
	}
	at [expr {$::N0+3*$::F+2}] { if {$::ostate eq "on"} { fail "game over $::games: fire at 3 s didn't return to the title" ; finish } }
}
# Game over's end (restart): frames from the one it began in to this one
# (whose work stops here)
cart_bp $sym(restart) {} { if {$::attr} { try attract_restart } else { try over_restart } }
proc over_restart {} {
	set k [expr {$::n - $::N0 + 1}]
	set ::lw_last "L[m level] W[expr {[m form_enemy] + 1}]"
	set bad [lw_bad $::lw_last]
	set lwant [expr {$::games == 6 ? "L1 W5" : $::games == 2 || $::games >= 4 ? "L1 W1" : ($::games == 3 ? "L1 W2" : "L3 W[expr {[m form_enemy] + 1}]")}]
	if {$::obonus} {
		check {$::obonus_end eq [list $::sym(BS_NEXT) 0 500 0 1]} "game over 3: the boss's bonus over 2 s after its text came, under GAME OVER: its 500 points, the next frame the next wave, L1 W2 (boss_st, enemy, points; boss_st, enemy the next frame: $::obonus_end)"
		set ::obonus 0
	}
	check {[llength $bad] == 0 && $::lw_last eq $lwant} "game over $::games: \"$::lw_last\" (want \"$lwant\") on the top status row's left, the score \"$::score_model\" on its right (wrong: [lrange $bad 0 5])"
	check {$::otext_bad == 0 && $::otext_frames >= $k - 1} "game over $::games: \"$::OVER\" intact every frame of it ($::otext_frames frames; [expr {$::otext_bad ? "first wrong: $::otext_first" : "none wrong"}])"
	if {$::ostage} {
		check {$::os_bad eq "" && $::os_star > 0 && $::os_star_out > 0 && $::os_eb > 0 && $::os_eb_out > 0} "game over: a star and an enemy bullet through the text, not drawn in its cells ($::os_star / $::os_eb frames), shown past them ($::os_star_out / $::os_eb_out frames; wrong: [lrange $::os_bad 0 3])"
		set ::ostage 0
	}
	check {$::ostate eq "on" && $k == $::owant} "game over $::games: back to the title $k frames after it began (want $::owant: $::owhy)"
	check {$::dropped == $::odropped} "game over $::games: the game ran every frame of it ([expr {$::dropped - $::odropped}] dropped)"
	set ::ostate "" ; set ::phase 3 ; set ::sn 0
	set ::twhy "game over $::games" ; set ::tnext [lindex {"" press press wait list cheat press} $::games] ; set ::press_sn 6
	set ::score_last [string trim [score_str $::score_model]]
	set ::score_model 0 ; set ::sc_calls {} ; set ::sc_shown 0
	unset -nocomplain ::last_frames
}
# A new game after a game over, before its first frame: as at power-on
proc new_game_checks {} {
	set en {}
	for {set i 0} {$i < 8} {incr i} { lappend en [lindex [en_state $i] 0] }
	set st {}
	for {set k 0} {$k < 4} {incr k} { lappend st [m boom_stage $k] }
	check {[m front_mask] == 1 && [m ship_x] == $::sym(SHIP_X_MAX)/2 && $st eq {0 0 0 0} && [m reserves] == 4 && ![m call_on] && ![m over_on] && ![m volleys] && ![m volleys $::VOL] && ![m boss_st] && ![m mid_text] && ![m bonus_text]} "new game $::games: one ship in the middle, 4 in reserve, nothing flying, no boss, not over (mask [m front_mask], ship_x [m ship_x], [m reserves] in reserve, boss_st [m boss_st])"
	set bad [form_pattern_bad]
	check {[m form_enemy] == 0 && [m form_cidx] == 0 && [m form_color] == 2 && ![m wave_wait] && $en eq {0 0 0 0 0 0 0 0} && [llength $bad] == 0} "new game $::games: the first wave again (enemy [m form_enemy], colour [m form_color], states $en; VRAM wrong: $bad)"
	check {[psg 8] == 0 && [psg 9] == 0 && [psg 10] == 0} "new game $::games: silent"
	check_cleared
	check_reserves 4
	at [expr {$::n+3}] {
		set x [expr {$::sym(SHIP_X_MAX)/2 - $::sym(SHIP_ART_L)}] ; set y [expr {$::sym(SHIP_TOP) - 1}]
		check {[sat 0] == $y && [sat 1] == $x || [sat 48] == $y && [sat 49] == $x} "new game $::games: the ship's sprite in the middle"
	}
	if {$::games < 3} { at [expr {$::n+$::F}] { plan_over [expr {$::games + 1}] } } else {
		# Ctrl-V in a game: nothing (no egg for the next title, the game on)
		at [expr {$::n+5}] { ctrl 1 ; vkey 1 }
		at [expr {$::n+10}] { ctrl 0 ; vkey 0 }
		at [expr {$::n+12}] { check {![m egg_now] && ![m over_on] && [m front_mask] == 1} "Ctrl-V in a game: nothing" }
		# the cheat keys 1..4 before cheat mode: nothing
		if {$::games < 5} {
			at [expr {$::n+14}] { keymatrixdown 0 0x1E }
			at [expr {$::n+17}] { keymatrixup 0 0x1E }
			at [expr {$::n+19}] { check {![m cheat_on] && ![m boss_st] && [m form_enemy] == 0 && [m reserves] == 4 && ![m invul] && [m front_mask] == 1 && ![m boom_stage]} "new game $::games: the cheat keys 1..4 out of cheat mode: nothing (boss_st [m boss_st], enemy [m form_enemy], [m reserves] in reserve, invul [m invul], front [m front_mask], boom [m boom_stage])" }
		}
		if {$::games == 3} { at [expr {$::n+$::F}] { hi_game 4 } } elseif {$::games == 4} { at [expr {$::n+$::F}] { hi_game 5 } } elseif {$::games == 5} { at [expr {$::n+20}] cheat_game } else {
			at [expr {$::n+8*$::F}] { hi_end ; screenshot_and_finish }
		}
	}
}

# Attract mode. After game over 3 the title is left alone: 20 s on
# (TITLE_WAIT_MS), attract mode, a pseudo-game: the top status row as the
# title had it (the last game's level, wave and score) every frame, silent
# every frame (R8..R10 0, the mixer all off), the front moving both ways
# and shooting; every 5 s a call-up roll (attract_cpu.roll, a breakpoint):
# heads (1 in 2), a call-up starts that frame if one can (none flying, a
# reserve, a span under 4; as call_up began: a breakpoint's snapshot), and
# none starts otherwise but by itself (the front empty); C does nothing
# (held 1 s in the first; CTRL alone and V alone, 0.5 s each, in the
# second). Four times: the first plays its 40 s (or till game over's 10 s,
# if it comes first), then the title (left alone again); the second ends
# at joystick 1's button A, the third at space, pressed 3 s and 2 s in,
# that frame, the fourth at Ctrl-V 2 s in; then the title with the egg up
# (egg_frame), and a press of space, a new game as at power-on (Ctrl-V in
# it: nothing).
set attr 0 ; set attracts 0 ; set tnext press ; set twhy "" ; set press_sn 6
proc top_want {} {
	set t [title_with $::lw_last $::score_last]
	set ::topwant {}
	foreach v [concat [lrange $t 0 255] [lrange $t 6144 6399]] { lappend ::topwant [expr 0x$v] }
}
proc top_bad {} {
	set bad {}
	for {set i 0} {$i < 256} {incr i} {
		if {[debug read VRAM $i] != [lindex $::topwant $i]} { lappend bad [format %04X $i] }
		if {[debug read VRAM [expr {0x2000 + $i}]] != [lindex $::topwant [expr {256 + $i}]]} { lappend bad [format %04X [expr {0x2000 + $i}]] }
	}
	return $bad
}
proc att_bad {s} { if {!$::att_bad} { set ::att_first "frame $::an: $s" } ; incr ::att_bad }
cart_bp $sym(attract_cpu.roll) {} {
	if {!$::attr} return
	# (attract 1: until a roll has called one up, a roll that can is made
	# heads; not with a ship dying: its boom ending this frame could empty
	# the front, and the call-up be the empty front's)
	set dying 0 ; for {set k 0} {$k < 4} {incr k} { if {[m boom_stage $k]} { set dying 1 } }
	if {$::attracts == 1 && !$::acalls && ![m call_on] && [m reserves] && [m front_slots] < 4 && [m front_mask] && !$dying} {
		reg A [expr {[reg A] & ~($::sym(ATTRACT_CALL_CHANCE) - 1) & 0xFF}] ; incr ::aforce
	}
	lappend ::arolls $::an ; set ::aroll [expr {([reg A] & ($::sym(ATTRACT_CALL_CHANCE) - 1)) == 0}]
}
cart_bp $sym(call_up) {} {
	if {$::attr} { set ::asnap [list [m call_on] [m reserves] [m front_slots] [m front_mask]] }
}
# Dodges: the threat tried (attract_dodge.threat: DE, its column) and the
# target set for the last one (attract_dodge.set: A) against the rule: the
# front ATTRACT_DODGE_MARGIN px clear of it, away from it (right if it's
# left of the front's middle or on it), else the other side, clamped
cart_bp $sym(attract_dodge.threat) {} {
	if {$::attr} { set c [reg HL] ; if {$c > 32767} { incr c -65536 } ; set ::athreat [list $c [m att_tw] [m ship_x] [m front_w]] }
}
cart_bp $sym(attract_dodge.set) {} { if {$::attr} { try dodge_check } }
proc on_ship_dies {} { set ::blost 1 ; if {$::attr} { incr ::adeaths } }
cart_bp $sym(ship_dies) {} on_ship_dies
proc dodge_check {} {
	set M $::sym(ATTRACT_DODGE_MARGIN)
	lassign $::athreat c tw x w
	set c1 [expr {$c + $tw}]
	set threat [expr {$c - $M <= $x + $w - 1 && $c1 + $M >= $x}]
	set R [expr {$c1 + $M + 1}] ; set L [expr {$c - $M - $w}]
	set rfit [expr {$R >= 0 && $R + $w <= 256}]
	if {$c + $c1 <= 2*$x + $w - 1} { set t [expr {$rfit ? $R : $L}] } else { set t [expr {$L >= 0 ? $L : $R}] }
	set t [expr {$t < 0 ? 0 : ($t > 255 ? 255 : $t)}]
	incr ::adodges
	if {!$threat || [reg A] != $t} { att_bad "a dodge of columns $c..$c1 (front at $x, $w px): target [reg A], want $t[expr {$threat ? "" : " (not a threat)"}]" }
	# where it leads, the front is clear of it (or at an edge)
	set e [expr {$t > 256 - $w ? 256 - $w : $t}]
	if {$c - $M <= $e + $w - 1 && $c1 + $M >= $e} { incr ::adodge_edge }
}
# The main loop's first frame in attract mode (before its work)
proc attract_begin {} {
	incr ::attracts
	set F [m fps]
	check {$::sn == 27*$F} "the title left alone after $::twhy: attract mode $::attracts after $::sn frames (want [expr {27*$F}]: the title 20 s, the high score list 7 s)"
	check {[vdp_r1] & 0x40} "attract mode $::attracts: display on (R1 [format %02X [vdp_r1]])"
	# runs 2, 4, ...: a boss instead of wave 1, Boss1 and Boss2 in turn
	set boss [expr {$::attracts % 2 ? 0 : ($::attracts % 4 ? 1 : 2)}]
	top_want
	set bad [top_bad]
	for {set a 256} {$a < 23*256} {incr a} {
		set i [expr {($a >> 8) - 1}] ; set c [expr {($a & 255) - 96}]
		if {$boss == 2 && $i < 2 && $c >= 0 && $c < 64} {
			if {[debug read VRAM $a] != [m BOSS2_PAT [expr {64*$i + $c}]]} { lappend bad "Boss2 [format %04X $a]" }
		} elseif {[debug read VRAM $a]} { lappend bad [format %04X $a] }
	}
	check {![llength $bad]} "attract mode $::attracts: the top status row as the title had it (\"$::lw_last\" on its left, \"$::score_last\" on its right), the bitmap below it blank[expr {$boss == 2 ? " but Boss2's art" : ""}] (wrong: [lrange $bad 0 5])"
	set st {} ; for {set k 0} {$k < 4} {incr k} { lappend st [m boom_stage $k] }
	set left [expr {[m att_left] + 256*[m att_left 1]}]
	check {[m front_mask] == 1 && [m ship_x] == $::sym(SHIP_X_MAX)/2 && $st eq {0 0 0 0} && [m reserves] == 4 && ![m over_on] && $left == 40*$F && [m level] == 1} "attract mode $::attracts: as a new game (one ship in the middle, 4 in reserve, level 1), for [expr {$left/$F}] s"
	if {$boss == 0} {
		check {[m form_enemy] == 0 && [m form_color] == 2 && [m wave_n] == 0 && ![m boss_st]} "attract mode $::attracts: the first wave (enemy [m form_enemy], colour [m form_color], wave_n [m wave_n], boss_st [m boss_st])"
	} else {
		set w [expr {$boss == 1 ? $::sym(ATTRACT_BOSS1) : $::sym(BOSS2_AFTER)}]
		set gone 1 ; set kinds {}
		set kinds [en_sts]
		if {$boss == 1} { set gone [expr {[lsort -unique $kinds] eq [list $::sym(EN_GONE)]}] }
		check {[m boss_st] == $::sym(BS_FIGHT) && ([m boss_kind] != 0) == ($boss == 2) && [m form_enemy] == $w - 1 && [m wave_n] == $w - 1 && [m form_cidx] == ($w - 1) % $::sym(FORM_COLORS_N) && $gone && [m b2_shown] == ($boss == 2)} "attract mode $::attracts: Boss$boss instead of the first wave, as after wave $w (boss_st [m boss_st], boss_kind [m boss_kind], form_enemy [m form_enemy], wave_n [m wave_n], form_cidx [m form_cidx], enemies' states $kinds, b2_shown [m b2_shown])"
	}
	check_reserves 4
	set ::attr 1 ; set ::an 0 ; set ::att_bad 0 ; set ::att_first ""
	set ::arolls {} ; set ::aroll -1 ; set ::aheads 0 ; set ::acalls 0 ; set ::aforced 0
	set ::ax [m ship_x] ; set ::alefts 0 ; set ::arights 0 ; set ::axmin 255 ; set ::axmax 0
	set ::spawns 0 ; set ::aover -1 ; set ::aquit_at -1 ; set ::adropped $::dropped
	set ::adodges 0 ; set ::adodge_edge 0 ; set ::adeaths 0 ; set ::aoverframes 0 ; set ::astaged 0 ; set ::aforce 0
	unset -nocomplain ::asnap
	set ::ebhits 1       ;# (enemy bullets kill ships: a real pseudo-game)
	set ::phase 4
}
# Every main loop frame in attract mode (::an: frames so far; after frame
# ::an-1's work)
proc attract_frame {} {
	incr ::an
	set F $::F
	set ::sc_calls {} ; set ::in_col 0     ;# (score_add's checks stand; the score isn't shown)
	if {[psg 8] || [psg 9] || [psg 10] || ([psg 7] & 0x3F) != 0x3F} { att_bad "not silent (R7 [format %02X [psg 7]], R8..R10 [psg 8] [psg 9] [psg 10])" }
	set bad [top_bad]
	if {[llength $bad]} { att_bad "the top status row changed (at [lrange $bad 0 3])" }
	set x [m ship_x]
	if {$x > $::ax} { incr ::arights } elseif {$x < $::ax} { incr ::alefts }
	set ::ax $x
	if {$x < $::axmin} { set ::axmin $x } ; if {$x > $::axmax} { set ::axmax $x }
	if {[m over_on] && $::aover < 0} { set ::aover $::an }
	if {[m over_on]} {
		incr ::aoverframes
		if {[m over_text]} { att_bad "game over in attract mode flagged as showing GAME OVER" }
		set bad [over_text_bad 0]
		if {[llength $bad]} { att_bad "GAME OVER's letters show in attract mode ($bad)" }
	}
	# attract 1: no game over by 25 s, one staged (no reserve, every ship
	# booming, once no call-up flies)
	if {$::attracts == 1 && $::an >= 25*$F && $::aover < 0 && !$::astaged && ![m call_on]} {
		set ::astaged 1
		debug write memory $::sym(reserves) 0
		for {set k 0} {$k < 4} {incr k} {
			if {([m front_mask] >> $k & 1) && ![m boom_stage $k]} {
				debug write memory [expr {$::sym(boom_stage) + $k}] 1
				debug write memory [expr {$::sym(boom_left) + $k}] 1
			}
		}
	}
	if {[info exists ::asnap]} {
		lassign $::asnap con res slots mask
		set started [expr {[m call_on] && !$con}]
		set can [expr {!$con && $res > 0 && $slots < 4}]
		set heads [expr {$::aroll == 1}]
		if {$heads} { incr ::aheads }
		set want [expr {$can && ($heads || $mask == 0)}]
		if {$started != $want} { att_bad "a call-up [expr {$started ? "started" : "didn't start"}] (roll [expr {$::aroll < 0 ? "none" : ($heads ? "heads" : "tails")}], call_on $con, $res in reserve, span $slots, mask $mask before)" }
		if {$started} {
			if {[m reserves] != $res - 1} { att_bad "a call-up: [m reserves] in reserve, want [expr {$res - 1}]" }
			if {$mask} { incr ::acalls } else { incr ::aforced }
		}
		unset ::asnap
	}
	set ::aroll -1
	if {$::attracts == 1} {
		if {$::an == 2*$F} { cdown }
		if {$::an == 3*$F} { cup }
		if {$::an == 4*$F} { keymatrixdown 6 0x20 } elseif {$::an == 4*$F + $F/2} { keymatrixup 6 0x20 }
		if {$::an == 5*$F} { keymatrixdown 7 0x10 } elseif {$::an == 5*$F + $F/2} { keymatrixup 7 0x10 }
	} elseif {$::attracts == 2} {
		if {$::an == $F} { ctrl 1 } elseif {$::an == $F + $F/2} { ctrl 0 } elseif {$::an == 2*$F} { vkey 1 } elseif {$::an == 2*$F + $F/2} { vkey 0 }
		if {$::an == 3*$F} { joydown 1 0x10 ; set ::aquit_at $::an }
	} elseif {$::attracts == 3} {
		if {$::an == 2*$F} { down 0x01 ; set ::aquit_at $::an }
	} elseif {$::an == 2*$F} { ctrl 1 ; vkey 1 ; set ::aquit_at $::an }
	if {$::an > 40*$F + 2} { fail "attract mode $::attracts: still on after 40 s" ; finish }
}
# Attract mode's end (restart): ::an frames into it (the last one's work stops here)
proc attract_restart {} {
	set F $::F
	set want [expr {40*$F}] ; set why "40 s"
	if {$::aover >= 0 && $::aover - 1 + 10*$F < $want} { set want [expr {$::aover - 1 + 10*$F}] ; set why "game over's 10 s (it began [expr {$::aover - 1}] frames in)" }
	if {$::aquit_at >= 0} { set want $::aquit_at ; set why [lindex {"" "" "joystick 1's button A pressed (CTRL alone and V alone before it ignored)" "space pressed" "Ctrl-V pressed"} $::attracts] }
	check {$::an == $want} "attract mode $::attracts: back to the title [format %.2f [expr {double($::an)/$F}]] s in ($::an frames; want $want: $why)"
	set nrolls [expr {$::an / (5*$F)}]
	set rbad {} ; set k 0
	foreach r $::arolls { incr k ; if {$r != $k*5*$F} { lappend rbad $r } }
	check {[llength $::arolls] == $nrolls && ![llength $rbad]} "attract mode $::attracts: a call-up roll every 5 s ($::arolls; want $nrolls, at multiples of [expr {5*$F}])"
	check {$::att_bad == 0} "attract mode $::attracts: silent, the top status row unchanged, every frame; a call-up exactly on the rolls' heads that could ($::aheads heads, $::acalls call-ups by them, $::aforced by an empty front[expr {$::attracts == 1 ? "; C held 1 s, F1 and STOP 0.5 s each ignored: no pause" : ""}]; [expr {$::att_bad ? "first wrong: $::att_first" : "none wrong"}])"
	if {$::attracts == 1} {
		check {$::aover >= 0 && $::aoverframes > 0} "attract mode 1: game over ([expr {$::astaged ? "staged at 25 s" : "by itself"}], [expr {$::aover - 1}] frames in): no GAME OVER shown on its $::aoverframes frames, back to the title 10 s on (above)"
	}
	say "attract mode $::attracts: $::adodges dodges ($::adodge_edge of them can't clear it: an edge), $::adeaths ships lost in [format %.1f [expr {double($::an)/$F}]] s"
	check {$::dropped == $::adropped} "attract mode $::attracts: no frame dropped ([expr {$::dropped - $::adropped}])"
	if {$::attracts == 1} {
		check {$::alefts > 0 && $::arights > 0 && $::axmax - $::axmin >= 100 && $::spawns > 10 && $::aheads > 0 && $::acalls > 0 && $::adodges > 0} "attract mode 1: dodges ($::adodges, each target as the rule), the front moves both ways ($::alefts frames left, $::arights right, columns $::axmin..$::axmax) and shoots ($::spawns volleys); call-ups by the rolls ($::acalls of $::aheads heads in [llength $::arolls] rolls; $::aforce made heads by the test)"
	}
	set ::attr 0 ; set ::ebhits 0 ; set ::phase 3 ; set ::sn 0
	check {[m egg_now] == ($::attracts == 4 ? $::sym(IN_EGG) : 0)} "attract mode $::attracts: the title [expr {$::attracts == 4 ? "with" : "without"}] the egg (egg_now [m egg_now])"
	set ::twhy "attract mode $::attracts" ; set ::tnext [expr {$::attracts < 4 ? "wait" : "egg"}]
	set ::sc_calls {} ; set ::in_col 0 ; set ::bwant {} ; set ::bonew 0 ; set ::eb_expect ""
	unset -nocomplain ::last_frames ::asnap
}

# ---- High scores ------------------------------------------------------------
#
# The table (::hi, the test's model): the user's at power-on; in the disk
# version, TERRAFNT.HSC on the disk: boot 1 with a file whose check byte is
# wrong (not loaded: the defaults), boot 2 with a sound one (loaded: its
# table, one record unlike the defaults). The title shows "HI SCORE" and the
# best score right-justified on rows 17 and 18 (build_titles); 20 s on, the
# list for 7 s (list_check, every time the title is left alone), then
# attract mode. Game 1's 1450 enters it (tenth; G typed, RETURN); games 2 and 3
# fall short: game 2's score written as the table's last (a tie), game
# 3's 500; hi_enter is never called in attract mode. Game 4:
# 3500 written, a tie with ALZ: sixth, under it; space skips its game over at 3 s, A held from game over
# (not typed); the entry: the list under "ENTER YOUR INITIALS" with "___",
# the slot's blink (blink_on / blink_off frames), RETURN with no letter:
# nothing; J, C, BS, X typed, RETURN: "JX "; the list stays done_frames
# (1 s); the title (the best still 5000), left alone: the list; Ctrl-V on
# it: the title with the egg up, its 20 s from the start; 20 s on the
# list again, space 3 s in starts game 5. Game 5: 12345678 written, the
# best: joystick 1's right held from game over (nothing picked), then held:
# A at once, B after rep_delay (0.4 s), C rep_frames (0.1 s) later;
# joystick 1's A takes it; joystick 2's left: Z, again: Y, its B takes it;
# down takes Y back; up-right (diagonal): no end, right picks Z; space takes
# it; joystick 2's right: A (none: A); joystick 1's A takes the third: the
# entry ends: "CZA". The title: "12345678" under HI SCORE. The disk version:
# the file on the disk decoded (as the game wrote it) = the table, and the
# drive's LED off some seconds after the save.
set BIN [string match *.bin [expr {[info exists ::env(IMAGE)] ? $::env(IMAGE) : ""}]]
proc hi_ram {} {
	set l {}
	for {set k 0} {$k < $::sym(HI_COUNT)} {incr k} {
		set a [expr {$k*$::sym(HI_SIZE)}]
		set d ""
		for {set i 3} {$i >= 0} {incr i -1} { append d [format %02x [m hi_table [expr {$a + $i}]]] }
		set nm ""
		for {set i 0} {$i < 3} {incr i} { append nm [format %c [m hi_table [expr {$a + $::sym(HI_NAME) + $i}]]] }
		lappend l [list [scan $d %d] $nm]
	}
	return $l
}
# a line of the list: " 1. LTR     5000"
proc hi_line {k tbl} {
	lassign [lindex $tbl $k] sc nm
	format "%2d. %-3s %8s" [expr {$k + 1}] $nm $sc
}
# The list's screen: the top status row as the title had it (or, game: as
# the game had it: the level and wave over LW_LEN cells, the score over
# SCORE_LEN, both white, blanks too), heading head centred on HI_ROW, table
# tbl's lines from HI_LIST_ROW, the rest black
proc list_want {head {tbl ""} {game 0}} {
	if {$tbl eq ""} { set tbl $::hi }
	if {$game} {
		set t [concat [lrepeat 6144 00] [lrepeat 6144 11]]
		set t [paint $t [format %-$::sym(LW_LEN)s $::lw_last] $::sym(LW_ROW) $::sym(LW_COL)]
		set t [paint $t [score_str $::score_last] $::sym(SCORE_ROW) $::sym(SCORE_COL)]
	} else {
		set t [title_with $::lw_last $::score_last]
		set t [concat [lrange $t 0 255] [lrepeat 5888 00] [lrange $t 6144 6399] [lrepeat 5888 11]]
	}
	set t [paint $t $head $::sym(HI_ROW) [expr {(32 - [string length $head])/2}]]
	for {set k 0} {$k < [llength $tbl]} {incr k} { set t [paint $t [hi_line $k $tbl] [expr {$::sym(HI_LIST_ROW) + $k}] $::sym(HI_COL)] }
	return $t
}
proc list_check {what} {
	set F [m fps]
	set bad [vram_bad [list_want "HIGH SCORES"]]
	check {![llength $bad] && [w16 list_left] == 7*$F && ([vdp_r1] & 0x40) && ![w16 egg_left]} "$what, the title left alone 20 s: the high score list (\"HIGH SCORES\"; [join [lmap e $::hi {join $e " "}] ", "]) in place of the picture, the top status row kept, display on, for 7 s ([w16 list_left] frames; wrong: $bad)"
}
# The disk version's file: tbl's records (4 BCD bytes, the lowest first;
# three letters), a check byte (HSC_KEY + their bytes; + bad), all XORed
# with HSC_XOR + HSC_XOR_STEP * index
proc hsc_bytes {tbl {bad 0}} {
	set b {}
	foreach e $tbl {
		lassign $e sc nm
		set d [format %08d $sc]
		for {set k 0} {$k < 4} {incr k} { lappend b [expr 0x[string range $d [expr {6 - 2*$k}] [expr {7 - 2*$k}]]] }
		foreach c [split $nm ""] { scan $c %c v ; lappend b $v }
	}
	set s $::sym(HSC_KEY) ; foreach v $b { set s [expr {($s + $v) & 255}] }
	lappend b [expr {($s + $bad) & 255}]
	set out "" ; set i 0
	foreach v $b { append out [binary format c [expr {$v ^ (($::sym(HSC_XOR) + $i*$::sym(HSC_XOR_STEP)) & 255)}]] ; incr i }
	return $out
}
# ... its table (or "bad: why")
proc hsc_table {data} {
	set n [expr {$::sym(HI_COUNT)*$::sym(HI_SIZE) + 1}]
	if {[string length $data] != $n} { return "bad: [string length $data] bytes" }
	binary scan $data cu* v
	set b {}
	for {set i 0} {$i < $n} {incr i} { lappend b [expr {[lindex $v $i] ^ (($::sym(HSC_XOR) + $i*$::sym(HSC_XOR_STEP)) & 255)}] }
	set s $::sym(HSC_KEY) ; foreach x [lrange $b 0 end-1] { set s [expr {($s + $x) & 255}] }
	if {$s != [lindex $b end]} { return "bad: check byte" }
	set l {}
	for {set k 0} {$k < $::sym(HI_COUNT)} {incr k} {
		set a [expr {$k*$::sym(HI_SIZE)}]
		set d "" ; for {set i 3} {$i >= 0} {incr i -1} { append d [format %02x [lindex $b [expr {$a + $i}]]] }
		set nm "" ; for {set i 4} {$i < 7} {incr i} { append nm [format %c [lindex $b [expr {$a + $i}]]] }
		lappend l [list [scan $d %d] $nm]
	}
	return $l
}
set HSC_DIR [file join $ROOT build hsc-[pid]]
proc hsc_put {data} {
	file mkdir $::HSC_DIR
	set f [open [file join $::HSC_DIR TERRAFNT.HSC] wb] ; puts -nonewline $f $data ; close $f
	diskmanipulator import diska [file join $::HSC_DIR TERRAFNT.HSC]
}
set HI_DISK [lreplace $HI_DEFAULTS 8 9 {1500 DSK} {1100 HSC}]
# (import doesn't replace a file: boot 2 gets a fresh copy of the disk)
if {$BIN} {
	file mkdir $HSC_DIR
	file copy -force $::env(DISK) [file join $HSC_DIR boot2.dsk]
	hsc_put [hsc_bytes $HI_DISK 1]
}
proc hi_boot1 {} {
	check {[hi_ram] eq $::HI_DEFAULTS} "boot 1: the high score table at power-on: the user's ([join [lmap e [hi_ram] {join $e " "}] ", "])[expr {$::BIN ? "; TERRAFNT.HSC with a wrong check byte not taken" : ""}]"
	if {$::BIN} {
		diska [file join $::HSC_DIR boot2.dsk]
		file delete [file join $::HSC_DIR TERRAFNT.HSC]
		hsc_put [hsc_bytes $::HI_DISK]
	}
}
proc hi_boot2 {} {
	if {$::BIN} {
		check {[hi_ram] eq $::HI_DISK} "boot 2: TERRAFNT.HSC's table taken (its last two records: [join [lmap e [lrange [hi_ram] 8 9] {join $e " "}] ", "])"
		set ::hi $::HI_DISK
	} else {
		check {[hi_ram] eq $::HI_DEFAULTS} "boot 2: the user's table"
	}
	build_titles
	set F [m fps]
	check {[w16 list_frames] == 7*$F && [m rep_delay] == $F*2/5 && [m rep_frames] == $F/10 && [m done_frames] == $F} "high scores: the list 7 s ([w16 list_frames] frames), a letter's repeat after 0.4 s ([m rep_delay]), then every 0.1 s ([m rep_frames]), the entry's end shown 1 s ([m done_frames])"
}
# the boot's splash checked the title (TITLE_ON) with the HI SCORE lines
set hi_calls 0 ; set entries 0 ; set en 0 ; set holds 0 ; set eblinks {}
cart_bp $sym(hi_enter) {} {
	if {[m attract]} { fail "hi_enter called in attract mode" }
	incr ::hi_calls
}
cart_bp $sym(enter_initials) {} { incr ::entries ; set ::en 0 ; set ::holds 0 ; set ::eblinks {} ; set ::entry_game $::games }
set entry_game 0
cart_bp $sym(enter_initials.frame) {} { try entry_frame }
cart_bp $sym(enter_initials.hold) {} { incr ::holds ; if {$::holds == 1} { try entry_done } }
proc score_write {v} {
	set d [format %08d $v]
	for {set k 0} {$k < 4} {incr k} { debug write memory [expr {$::sym(score) + $k}] [expr 0x[string range $d [expr {6 - 2*$k}] [expr {7 - 2*$k}]]] }
	debug write memory $::sym(score_dirty) 1
	set ::score_model $v ; set ::sc_shown 1
}
# Games 4 and 5: the score written, no reserve, the front killed
proc hi_game {g} {
	set ::ebon 0
	if {[m call_on]} { at [expr {$::n+1}] [list hi_game $g] ; return }
	set ::games $g
	score_write [expr {$g == 4 ? 3500 : 12345678}]
	debug write memory $::sym(reserves) 0
	set ::ostate wait
	kill_all
	if {$g == 4} { at [expr {$::n + 2*$::F}] { keymatrixdown 2 0x40 } } else { at [expr {$::n + 2*$::F}] { joydown 1 0x08 } }
}
# the table with the new record (rank r, initials nm) in, the last gone
proc hi_with {sc nm} {
	set r 0
	foreach e $::hi { if {$sc > [lindex $e 0]} break ; incr r }
	return [list $r [lrange [linsert $::hi $r [list $sc $nm]] 0 end-1]]
}
proc ent_name {} {
	set a [expr {[m ent_rec] + 256*[m ent_rec 1] + $::sym(HI_NAME)}]
	set nm "" ; for {set i 0} {$i < 3} {incr i} { append nm [format %c [debug read memory [expr {$a + $i}]]] }
	return $nm
}
proc ent_is {pos name letter what} {
	set l [m ent_letter]
	set got [list [m ent_pos] [ent_name] [expr {$l ? [format %c $l] : "none"}]]
	check {$got eq [list $pos $name $letter]} "initials: $what (slot, initials, letter picked: $got; want [list $pos $name $letter])"
}
# One entry frame (before its halt: the last one's work done; ::en 1..)
proc entry_frame {} {
	incr ::en
	set e $::en ; set F $::F
	if {$::games == 1} {
		if {$e == 1} {
			lassign [hi_with 1450 "___"] r t
			set bad [vram_bad [list_want "ENTER YOUR INITIALS" $t 1]]
			check {$r == 9 && [m ent_row] == 9 && ![llength $bad]} "game 1: 1450, tenth: the initials, the last gone (wrong: $bad)"
		}
		switch $e {
			3 { keymatrixdown 3 0x10 } 5 { keymatrixup 3 0x10 }
			7 { keymatrixdown 7 0x80 }
			9 { fail "game 1: RETURN didn't end the initials" ; finish }
		}
		return
	}
	if {$::games == 4} {
		lassign [hi_with 3500 "___"] r t
		if {$e == 1} {
			set ::ent_r $r ; set ::ent_t $t
			check {$r == 5 && [m ent_row] == 5} "game 4: 3500, a tie with ALZ's: sixth, under it (rank [m ent_row])"
			set bad [vram_bad [list_want "ENTER YOUR INITIALS" $t 1]]
			check {![llength $bad] && ([vdp_r1] & 0x40) && [sat 0] == 0xD0} "game 4: the initials: \"ENTER YOUR INITIALS\" and the list with \" 6. ___     3500\", the rest a place down, the last gone; the top status row kept, display on, no sprites (wrong: $bad)"
		}
		# the first slot's "_": blinking from the start
		if {$e <= 60} {
			set a [expr {($::sym(HI_LIST_ROW) + $r)*256 + ($::sym(HI_COL) + 4)*8}]
			set g {} ; for {set y 0} {$y < 6} {incr y} { lappend g [format %02x [debug read VRAM [expr {$a + $y}]]] }
			lappend ::eblinks [expr {$g eq [lrange $::FONT [expr {(95 - 32)*6}] [expr {(95 - 32)*6 + 5}]] ? 1 : ($g eq {00 00 00 00 00 00} ? 0 : -1)}]
		}
		if {$e == 61} {
			set runs {} ; set prev "" ; set len 0
			foreach b $::eblinks { if {$b != $prev && $prev ne ""} { lappend runs [list $prev $len] ; set len 0 } ; set prev $b ; incr len }
			set on [m blink_on] ; set off [m blink_off] ; set bad 0
			foreach rn $runs { lassign $rn st len ; if {$st < 0 || $len != ($st ? $on : $off)} { incr bad } }
			check {[llength $runs] >= 3 && !$bad && [lindex $runs 0 0] == 1} "game 4: the first slot's \"_\" blinks, shown $on frames, hidden $off, from the start ($runs); A held from game over: not typed"
			ent_is 0 "___" none "A held from before, released: nothing typed"
		}
		switch $e {
			10 { keymatrixup 2 0x40 }
			62 { keymatrixdown 7 0x80 } 64 { keymatrixup 7 0x80 }
			66 { ent_is 0 "[expr {[m blink_shown] ? "_" : " "}]__" none "RETURN with no letter: nothing" }
			70 { keymatrixdown 3 0x80 } 72 { keymatrixup 3 0x80 }
			73 { ent_is 1 "J__" none "J typed" }
			74 { keymatrixdown 3 0x01 } 76 { keymatrixup 3 0x01 }
			77 { ent_is 2 "JC_" none "C typed" }
			78 { keymatrixdown 7 0x20 } 80 { keymatrixup 7 0x20 }
			81 { ent_is 1 "J[expr {[m blink_shown] ? "C" : " "}]_" C "BS: C taken back, picked" }
			82 { keymatrixdown 5 0x20 } 84 { keymatrixup 5 0x20 }
			85 { ent_is 2 "JX_" none "X typed in its place" }
			86 { keymatrixdown 7 0x80 }
			90 { fail "game 4: RETURN didn't end the initials" ; finish }
		}
		return
	}
	set D [m rep_delay] ; set R [m rep_frames]
	set T [expr {5 + $D + $R + 5}]
	if {$e == 1} {
		lassign [hi_with 12345678 "___"] r t
		up 0x01
		set bad [vram_bad [list_want "ENTER YOUR INITIALS" $t 1]]
		check {$r == 0 && [m ent_row] == 0 && ![llength $bad]} "game 5: 12345678, the best: the initials on the list's first line, the rest a place down (wrong: $bad)"
	}
	switch -- $e {
		3 { ent_is 0 "___" none "joystick 1's right held from game over: nothing picked" ; joyup 1 }
		5 { joydown 1 0x08 }
		6 { ent_is 0 "A__" A "right: A at once" }
	}
	if {$e == 5 + $D} { ent_is 0 "[expr {[m blink_shown] ? "A" : " "}]__" A "right held 0.4 s less a frame: still A" }
	if {$e == 6 + $D} { ent_is 0 "[expr {[m blink_shown] ? "B" : " "}]__" B "right held 0.4 s: B" }
	if {$e == 5 + $D + $R} { ent_is 0 "[expr {[m blink_shown] ? "B" : " "}]__" B "0.1 s less a frame on: still B" }
	if {$e == 6 + $D + $R} { ent_is 0 "[expr {[m blink_shown] ? "C" : " "}]__" C "0.1 s on: C" ; joyup 1 }
	switch -- [expr {$e - $T}] {
		-2 { ent_is 0 "[expr {[m blink_shown] ? "C" : " "}]__" C "right released: still C" }
		0 { joydown 1 0x10 } 2 { joyup 1 }
		3 { ent_is 1 "C__" none "joystick 1's A: C taken" }
		5 { joydown 2 0x04 } 6 { ent_is 1 "C[expr {[m blink_shown] ? "Z" : " "}]_" Z "joystick 2's left, none picked: Z" } 7 { joyup 2 }
		9 { joydown 2 0x04 } 10 { ent_is 1 "C[expr {[m blink_shown] ? "Y" : " "}]_" Y "left again: Y" } 11 { joyup 2 }
		13 { joydown 2 0x20 } 15 { joyup 2 }
		16 { ent_is 2 "CY_" none "joystick 2's B: Y taken" }
		18 { joydown 1 0x02 } 20 { joyup 1 }
		21 { ent_is 1 "C[expr {[m blink_shown] ? "Y" : " "}]_" Y "down: Y taken back" }
		23 { joydown 1 0x09 } 24 { ent_is 1 "C[expr {[m blink_shown] ? "Z" : " "}]_" Z "up-right (a diagonal): no end, right picks Z" } 25 { joyup 1 }
		27 { down 0x01 } 29 { up 0x01 }
		30 { ent_is 2 "CZ_" none "space: Z taken" }
		32 { joydown 2 0x08 } 33 { ent_is 2 "CZ[expr {[m blink_shown] ? "A" : " "}]" A "right, none picked: A" } 34 { joyup 2 }
		36 { joydown 1 0x10 }
		38 { fail "game 5: the third letter taken didn't end the initials" ; finish }
	}
}
# The entry's end (the first frame of its hold; RETURN, if it ended it, let go)
proc entry_done {} {
	keymatrixup 7 0x80
	if {$::games == 1} { set sc 1450 ; set nm "G  " ; set want 7 } elseif {$::games == 4} { set sc 3500 ; set nm "JX " ; set want 86 } else { set sc 12345678 ; set nm "CZA" ; set want [expr {5 + [m rep_delay] + [m rep_frames] + 5 + 36}] }
	lassign [hi_with $sc $nm] r t
	set bad [vram_bad [list_want "ENTER YOUR INITIALS" $t 1]]
	check {$::en == $want && [hi_ram] eq $t && ![llength $bad]} "game $::games: the initials \"$nm\" in at entry frame $::en (want $want): the table [join [lmap e [hi_ram] {join $e " "}] ", "], shown (wrong: $bad)"
	set ::hi $t
	build_titles
}
# The title after a game over (its first frame): the entry's hold over
set short_checked 0
proc hi_title_start {} {
	if {$::games == 6} {
		check {$::hi_calls == 5 && $::entries == 3 && [hi_ram] eq $::hi} "game 6, in cheat mode: $::score_last points, the best, but no high score entry (hi_enter calls $::hi_calls), the table unchanged"
		return
	}
	if {$::entry_game != $::games} {
		if {$::games in {2 3} && $::short_checked != $::games} {
			set ::short_checked $::games
			check {[hi_ram] eq $::hi} "game $::games: $::score_last points, short of the table (its last: [lindex $::hi end 0][expr {$::games == 2 ? ", a tie" : ""}]): no initials, straight to the title, the table unchanged"
		}
		return
	}
	if {$::holds == -1} return
	check {$::entries == ($::games == 1 ? 1 : $::games - 2) && $::holds == [m done_frames] && ![m over_on]} "game $::games: the list stayed [m done_frames] frames ($::holds) after the initials; then the title (the best: [lindex $::hi 0 0]; checked on its third frame)"
	set ::holds -1
}
# The title after game 4: left alone, the list (list_check); Ctrl-V 2 s
# into it: the title with the egg up, its count from the start; 20 s on
# the list again; space 3 s into it: game 5
set lv_sn -1
proc list_frame {} {
	set F [m fps] ; set n $::sn ; set L [expr {20*$F + 1}]
	if {$n == $L + 2*$F} { ctrl 1 ; vkey 1 ; set ::lv_sn $n }
	if {$::lv_sn < 0} return
	set k [expr {$n - $::lv_sn}] ; set E [expr {$::sym(EGG_SECS)*$F}]
	if {$k == 2} { ctrl 0 ; vkey 0 }
	if {$k == 3} {
		set bad [vram_bad [egg_want]]
		check {![w16 list_left] && [w16 egg_left] == $E - 2 && [w16 title_left] == 20*$F - 2 && ![llength $bad] && ![m egg_now]} "Ctrl-V on the high score list: the title with the egg up ([w16 egg_left] frames left), its 20 s from the start ([w16 title_left] frames left) (wrong: $bad)"
	}
	if {$k == 20*$F + 1} { list_check "after the list's Ctrl-V" }
	if {$k == 23*$F + 1} { down 0x01 ; set ::press_sn $n }
	if {$k == 23*$F + 4} { fail "space on the high score list doesn't start a game" ; finish }
}
proc hi_end {} {
	check {$::hi_calls == 5 && $::entries == 3 && [hi_ram] eq $::hi} "high scores: hi_enter at every game's end ($::hi_calls), never in attract mode; the initials only for games 1, 4 and 5 ($::entries); the table as the model"
	if {!$::BIN} return
	set out [file join $::HSC_DIR out]
	file mkdir $out
	diskmanipulator export diska $out
	set p [lindex [glob -nocomplain -directory $out terrafnt.hsc TERRAFNT.HSC] 0]
	if {$p ne ""} { set f [open $p rb] ; set d [read $f] ; close $f ; set got [hsc_table $d] } else { set got "bad: no file" }
	check {$got eq $::hi} "the disk's TERRAFNT.HSC, as the game wrote it: [expr {[string match bad:* $got] ? $got : [join [lmap e $got {join $e " "}] ", "]}]"
	check {[info exists ::led_FDD] && !$::led_FDD} "the drive's LED off 8 s into the game after the save ([expr {[info exists ::led_FDD] ? $::led_FDD : "no ::led_FDD"}])"
	file delete -force $::HSC_DIR
}

# Cheat mode. The title after game 5: CHEAT typed without CTRL; with CTRL
# held: C H E A, CTRL released and pressed, T; C H E X A T; neither turns
# it on; C H C H E A T does (a wrong C counts as the first letter): the
# logo in CHEAT_LOGO_COLOR. Then space: game 6.
set CHEAT_KEYS {C {3 0x01} H {3 0x20} E {3 0x04} A {2 0x40} T {5 0x02} X {5 0x20}}
set cheat_plan {}
proc cheat_type {word} { foreach c [split $word ""] { lappend ::cheat_plan [list key $c] } }
cheat_type CHEAT
lappend cheat_plan {check 0 "CHEAT typed without CTRL"} {ctrl 1}
cheat_type CHEA
lappend cheat_plan {ctrl 0} {ctrl 1}
cheat_type T
lappend cheat_plan {check 0 "CTRL held: C H E A, CTRL released and pressed, T"}
cheat_type CHEXAT
lappend cheat_plan {check 0 "CTRL held: C H E X A T"}
cheat_type CHCHEAT
lappend cheat_plan {on} {ctrl 0}
proc cheat_frame {} {
	set n $::sn
	if {$n >= 10 && ($n - 10) % 4 == 2} { foreach {k rb} $::CHEAT_KEYS { keymatrixup {*}$rb } }
	if {$n < 10 || ($n - 10) % 4} return
	set i [expr {($n - 10) / 4}]
	if {$i == 0} { check {![m cheat_on]} "cheat mode off at power-on" }
	if {$i >= [llength $::cheat_plan]} {
		if {$i == [llength $::cheat_plan]} { down 0x01 ; set ::press_sn $n }
		return
	}
	set st [lindex $::cheat_plan $i]
	switch [lindex $st 0] {
		key {
			lassign [dict get $::CHEAT_KEYS [lindex $st 1]] row bit
			keymatrixdown $row $bit
		}
		ctrl { ctrl [lindex $st 1] }
		check { check {![m cheat_on] && ![m cheat_step]} "cheat mode: [lindex $st 2]: still off" }
		on {
			set ::cheat 1 ; build_titles
			set want [title_with $::lw_last $::score_last]
			set bad {}
			foreach base {0 6144} {
				for {set i [expr {$base + 256}]} {$i < $base + $::sym(EGG_ROW)*256} {incr i} {
					set a [expr {$base ? 0x2000 + $i - 6144 : $i}]
					if {[debug read VRAM $a] != "0x[lindex $want $i]"} { lappend bad [format %04X $a] ; if {[llength $bad] > 5} break }
				}
			}
			check {[m cheat_on] == $::sym(CHEAT_MASK) && ![llength $bad]} "cheat mode: CTRL held, C H C H E A T: on (cheat_on [m cheat_on]); the logo in colour $::sym(CHEAT_LOGO_COLOR) (rows 1..[expr {$::sym(EGG_ROW) - 1}] wrong: $bad)"
		}
	}
}
# Game 6, in cheat mode: key 3 makes the front invulnerable (green;
# staged: enemy bullets and a free enemy on its ships pass through), key 4
# kills a random living ship (twice), key 1 goes to the level's next boss
# (L1 W5's), key 3 again: vulnerable (its colour back), key 4 kills one
# more, key 2 gives a reserve ship; then game over with the best score:
# no entry
proc key0 {bit} {
	keymatrixdown 0 $bit
	at [expr {$::n+2}] [list keymatrixup 0 $bit]
}
# The SAT shown's colours of the front's ships (not booming)
proc ship_cols {} {
	set r {}
	for {set e 0} {$e < 32} {incr e} {
		if {[sat [expr {4*$e}]] == $::sym(SHIP_TOP) - 1 && [sat [expr {4*$e + 2}]] == $::sym(NAME_SHIP)} { lappend r [expr {[sat [expr {4*$e + 3}]] & 15}] }
	}
	return $r
}
proc booming {} {
	set r {}
	for {set k 0} {$k < 4} {incr k} { if {[m boom_stage $k]} { lappend r $k } }
	return $r
}
proc cheat_game {} {
	set ::nocheck 1 ; set ::ebon 0   ;# (the cheats: the per-frame models don't follow them)
	check {[m cheat_on] == $::sym(CHEAT_MASK)} "cheat mode still on in a new game"
	check {![m invul]} "game 6: not invulnerable at its start"
	key0 0x08
	at [expr {$::n+5}] {
		set c [ship_cols]
		check {[m invul] && $c eq [list $::sym(INVUL_COLOR)]} "cheat mode: key 3 in a game: invulnerable (invul [m invul]), the ship in colour $::sym(INVUL_COLOR) (the SAT's: $c)"
		cheat_stage
	}
}
# A four-ship front at column 100, invulnerable; enemy 0 free, flying
# straight down, placed so that after its next move it is on ship 1's art;
# enemy bullets on ship 0's nose, ship 1's art's column 0 (deep), ship 3's
# nose and column 8: next frame no ship dies, the enemy flies on (on the
# ship's art), the bullet on ship 0's nose flies on
proc cheat_stage {} {
	if {[m call_on]} { at [expr {$::n + 1}] cheat_stage ; return }
	load_art
	set sx0 100 ; set T $::sym(SHIP_TOP) ; set W $::W ; set nose $::sym(SHIP_NOSE_DX)
	lassign [vel 16] vx vy
	set a {}
	for {set y [expr {$T - $::art_b}]} {$y + $::art_b <= 183 && ![llength $a]} {incr y} {
		for {set x [expr {$sx0 + $W - 8}]} {$x <= $sx0 + 2*$W} {incr x} {
			if {[touches $x $y $sx0 {0 1 2 3}] eq {1}} { set a [list $x $y] ; break }
		}
	}
	if {![llength $a]} { fail "invulnerability, staged: no placement on ship 1 found" ; return }
	set_front 4 $sx0
	lassign $a x y
	set x0 [expr {($x - ($vx >> 8)) % $::FWRAP}] ; set y0 [expr {$y - ($vy >> 8)}]
	set r $::sym(enemies)
	foreach {f v} [list ST $::sym(EN_FREE) LEFT 0 XF 0 X [expr {$x0 & 255}] YF 0 Y $y0 DIR 16] { debug write memory [expr {$r + $::sym(EN.$f)}] $v }
	debug write memory [expr {$r + $::sym(EN.X) + 1}] [expr {$x0 >> 8}]
	debug write memory [expr {$::sym(enemies) + $::sym(EN) + $::sym(EN.ST)}] $::sym(EN_GONE)
	set bs [list [list [expr {$T - 4}] [expr {$sx0 + $nose}]] [list [expr {$T + 9}] [expr {$sx0 + $W}]] \
		[list [expr {$T - 4}] [expr {$sx0 + 3*$W + $nose}]] [list [expr {$T + 9}] [expr {$sx0 + 3*$W + 8}]]]
	eb_set $bs
	set ::cs_eb0 [lindex $bs 0]
	say "invulnerability staged: a four-ship front at column $sx0, enemy 0 on ship 1 after its move ($a), enemy bullets $bs"
	at [expr {$::n + 1}] {
		set e [en_state 0]
		lassign $e st l xf x yf y
		set t [touches $x $y 100 {0 1 2 3}]
		lassign $::cs_eb0 by bx
		set b0 [lindex [eb_list] 0]
		set want [list [expr {$by + [m eb_step]}] $bx]
		check {[booming] eq {} && [m front_mask] == 15 && $st == $::sym(EN_FREE) && $t ne {} && $b0 eq $want} "invulnerable, staged, the next frame: no ship dies (booming: [booming]), enemy 0 flies on on the ships' art (state $st, touching ships $t), the bullet on ship 0's nose flies on ($b0, want $want)"
	}
	at [expr {$::n + 3}] {
		set c [ship_cols]
		check {[booming] eq {} && $c eq [lrepeat 4 $::sym(INVUL_COLOR)]} "invulnerable: the four ships in colour $::sym(INVUL_COLOR), none blown up (the SAT's: $c; booming: [booming])"
		key0 0x10
	}
	at [expr {$::n + 8}] {
		set ::cs_b1 [booming]
		check {[llength $::cs_b1] == 1 && [m invul] && [m front_mask] == 15 && [m boom_stage [lindex $::cs_b1 0]] == 1} "cheat mode: key 4, invulnerable: one ship of the front blows up (booming: $::cs_b1)"
		key0 0x10
	}
	at [expr {$::n + 13}] {
		set b [booming]
		check {[llength $b] == 2 && [lindex $::cs_b1 0] in $b} "cheat mode: key 4 again: another living ship blows up (booming: $b; the first $::cs_b1)"
		key0 0x02
	}
	at [expr {$::n + 18}] {
		check {[m boss_st] && [m form_enemy] == 4 && [lw_bad "L1 W5"] eq ""} "cheat mode: key 1 in a game: the boss after wave 5 (boss_st [m boss_st], enemy [m form_enemy]), \"L1 W5\" shown"
	}
	# (the two booms over: two ships left; the boss's bullets wiped, so
	# that none reaches the front before the checks)
	at [expr {$::n + 32}] { eb_set {} ; key0 0x08 }
	at [expr {$::n + 37}] {
		set c [ship_cols]
		set fm [m front_mask]
		check {![m invul] && ($fm & 1) + ($fm >> 1 & 1) + ($fm >> 2 & 1) + ($fm >> 3 & 1) == 2 && [booming] eq {} && $c eq [lrepeat 2 $::sym(SHIP_COLOR)]} "cheat mode: key 3 again: not invulnerable (invul [m invul]), the two ships left (front [m front_mask]) in colour $::sym(SHIP_COLOR) again (the SAT's: $c)"
		key0 0x10
	}
	at [expr {$::n + 40}] {
		set b [booming]
		check {[llength $b] == 1} "cheat mode: key 4, not invulnerable: one ship of the front blows up (booming: $b)"
		key0 0x04
	}
	at [expr {$::n + 44}] {
		check {[m reserves] == 5} "cheat mode: key 2 in a game: a reserve ship ([m reserves] in reserve)"
		set ::games 6
		score_write 99999998
		debug write memory $::sym(reserves) 0
		set ::ostate wait
		kill_all
	}
}
