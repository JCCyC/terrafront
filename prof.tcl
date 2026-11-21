# Per-frame profile of the main loop, run with test.tcl (after it: it uses
# its sym, m, n, cart_bp and finish): every frame, the time from after the halt to
# the next halt, split by the main loop's calls (from the listing). To
# PROFOUT: each routine's worst frame and mean; the frames over PROFMS ms;
# the 40 heaviest frames with their state and their routines of 0.3 ms or
# more. Restarts' frames (over 100 ms) are left out of the maxima.
set pf_out [open $env(PROFOUT) w]
set pf_thr [expr {$env(PROFMS) / 1000.0}]
set f [open $env(PROFLST)] ; set lines [split [read $f] \n] ; close $f
set in 0 ; set pf_pts {}
foreach l $lines {
	if {[regexp {^\s*\d+\s+([0-9A-F]{4})\s+main_loop:} $l]} { set in 1 ; continue }
	if {!$in} continue
	if {[regexp {^\s*\d+\s+([0-9A-F]{4})\s+76\s+halt} $l -> a]} { set pf_halt 0x$a ; continue }
	if {[regexp {^\s*\d+\s+([0-9A-F]{4})\s+CD [0-9A-F]{2} [0-9A-F]{2}\s+(?:\.\w+:)?\s*call (\w+)} $l -> a nm]} { lappend pf_pts [list 0x$a $nm] }
	if {[regexp {jr main_loop} $l]} break
}
set pf_t0 -1 ; set pf_seg {} ; set pf_last "" ; set pf_lt 0 ; set pf_frames 0 ; set pf_top {}
proc pf_mark {nm} {
	if {$::pf_t0 < 0} return
	set t [machine_info time]
	if {$::pf_last ne ""} { lappend ::pf_seg $::pf_last [expr {($t - $::pf_lt)*1000}] }
	set ::pf_last $nm ; set ::pf_lt $t
}
proc pf_ctx {} {
	set v 0 ; for {set i 0} {$i < $::sym(MAX_VOLLEYS)} {incr i} { if {[debug read memory [expr {$::sym(volleys) + $i*$::sym(VOLLEY)}]]} { incr v } }
	set e 0 ; for {set i 0} {$i < $::sym(EB_N)} {incr i} { if {[debug read memory [expr {$::sym(ebullets) + 2*$i}]]} { incr e } }
	return "frame $::n attract [m attract] star_step [m star_step] volleys $v ebullets $e call_on [m call_on] front_mask [m front_mask] boss_st [m boss_st] mid_text [m mid_text]"
}
cart_bp $pf_halt {} {
	if {$::pf_t0 >= 0} {
		pf_mark end
		set w [expr {([machine_info time] - $::pf_t0)*1000}]
		incr ::pf_frames
		set segs {}
		foreach {k d} $::pf_seg {
			if {$d >= 0.3} { lappend segs "$k [format %.2f $d]" }
			if {$w < 100} {
				if {![info exists ::pf_max($k)] || $d > [lindex $::pf_max($k) 0]} { set ::pf_max($k) [list $d [pf_ctx]] }
				set ::pf_sum($k) [expr {[info exists ::pf_sum($k)] ? $::pf_sum($k) + $d : $d}]
			}
		}
		if {$w < 100} {
			set rec [list [format %.2f $w] [pf_ctx] $segs]
			if {$w > $::pf_thr*1000} { puts $::pf_out "OVER $rec" }
			lappend ::pf_top $rec
			if {[llength $::pf_top] > 200} { set ::pf_top [lrange [lsort -real -decreasing -index 0 $::pf_top] 0 39] }
		}
	}
	set ::pf_t0 -1
}
cart_bp [expr {$pf_halt + 1}] {} { set ::pf_t0 [machine_info time] ; set ::pf_seg {} ; set ::pf_last "" }
foreach p $pf_pts { lassign $p a nm ; cart_bp $a {} [list pf_mark $nm] }
rename finish pf_finish0
proc finish {} {
	puts $::pf_out "frames $::pf_frames (ms; a frame is [format %.2f [expr {1000.0/[m fps]}]])"
	foreach k [lsort [array names ::pf_max]] { puts $::pf_out [format "MAX %-14s %5.2f  mean %5.2f  at %s" $k [lindex $::pf_max($k) 0] [expr {$::pf_sum($k)/$::pf_frames}] [lindex $::pf_max($k) 1]] }
	foreach r [lrange [lsort -real -decreasing -index 0 $::pf_top] 0 39] { puts $::pf_out "TOP $r" }
	close $::pf_out
	pf_finish0
}
