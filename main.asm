; ---------------------------------------------------------------------------
; Terra Front - the front (MSX1, 16 KB ROM at 4000h)
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
; call-up lands there.
; Controls: left / right arrows, space (fire), C (call-up); or either
; joystick (button A fires, B calls up). Test keys 1..4 kill the front's
; first..fourth ship. Fire, call-up and the test keys are edge-triggered:
; one action per press.
; Speeds are Bresenham on frames (whole pixels plus a remainder per frame,
; per frame rate), so they're the same in px/s at 50 and 60 Hz.
; ---------------------------------------------------------------------------

; ---- Version ---------------------------------------------------------------

; Stored at 4010h, right after the cartridge header: major, minor (bytes),
; patch (word, little-endian)
VERSION_MAJOR   equ 0
VERSION_MINOR   equ 1
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
CALL_TIME_MS    equ 250         ; a call-up's flight from the far edge takes at most this
RESERVE_X       equ 0           ; the first reserve ship's art's left column
RESERVE_GAP     equ 1           ; black pixels between two reserve ships
BOOM1_60        equ 6           ; frames each boom image shows, at 60 Hz ...
BOOM2_60        equ 4
BOOM3_60        equ 5
BOOM1_50        equ 5           ; ... and at 50 Hz
BOOM2_50        equ 3
BOOM3_50        equ 4

; ---- Layout ----------------------------------------------------------------

PLAY_TOP        equ STATUS_LINES            ; first playfield line
PLAY_BOTTOM     equ 191-STATUS_LINES        ; last playfield line

; SHIP_* come from build/sprites.inc (png2spr.py), SHOT_* from build/sfx.inc
; (sfx.py), included with the data at the end
SHIP_TOP        equ PLAY_BOTTOM-SHIP_ART_B  ; the sprite's first line (its art's last row on PLAY_BOTTOM)
SHIP_X_MAX      equ 256-SHIP_ART_W          ; one ship: ship_x is the art's left column, 0..SHIP_X_MAX
BULLET_START    equ SHIP_TOP+SHIP_ART_T-BULLET_H    ; a new bullet's top line: right above the nose
        assert BULLET_START >= PLAY_TOP
        assert SHIP_ART_L < 32              ; the EC bit's 32 px cover the left clip
        assert FRONT_MAX*SHIP_ART_W <= 128  ; a front left of the middle has room on its right

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
RESERVE_CELLS   equ (RESERVE_X+(RESERVES-1)*RESERVE_STEP+RESERVE_ART_W-1)/8+1
RESERVE_VRAM    equ RESERVE_ROW*32*8    ; the row's first cell, from GRPCGP / GRPCOL
        assert RESERVE_X+(RESERVES-1)*RESERVE_STEP+RESERVE_ART_W <= 256

; Sprite names (16x16 sprites: patterns in steps of 4)
NAME_SHIP       equ 0
NAME_COMING_R   equ 4           ; the ship coming in from the right, its woosh lines behind
NAME_COMING_L   equ 8           ; ... from the left
NAME_BOOM       equ 12          ; the boom images: 12, 16, 20
BOOM_STAGES     equ 3
SPR_PARK        equ 0C0h        ; a sprite's Y off screen (lines 193..208); below D0h, the end marker
SPR_END         equ 0D0h        ; Y that ends the sprite list
SPR_EC          equ 80h         ; colour byte: early clock, X shifted 32 px left

; Input bits (as the joystick's in PSG R14, 1 = pressed)
IN_LEFT         equ 04h
IN_RIGHT        equ 08h
IN_FIRE         equ 10h
IN_CALL         equ 80h

; ---- Hardware and BIOS -----------------------------------------------------

VDP_DATA        equ 98h
VDP_ADDR        equ 99h
PSG_ADDR        equ 0A0h
PSG_WRITE       equ 0A1h
PSG_READ        equ 0A2h
PPI_B           equ 0A9h        ; the keyboard matrix row selected (read, bit = 0 when pressed)
PPI_C           equ 0AAh        ; bits 0..3 select the row; 4..7 cassette, CAPS LED, click (kept)

PSG_TONE_A      equ 0           ; R0, R1: channel A's tone period
PSG_TONE_C      equ 4           ; R4, R5: channel C's
PSG_NOISE       equ 6           ; the noise period
PSG_MIXER       equ 7           ; bits 0..5 = 1: tone / noise off; bits 6, 7 the I/O ports' direction
PSG_VOL_A       equ 8
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
KEY_ROW_NUM     equ 0           ; keys 0..7 on bits 0..7
KEYS_KILL       equ 1Eh         ; the test keys 1..4

MSXID1          equ 002Bh       ; bit 7 set = 50 Hz
WRTVDP          equ 0047h
FILVRM          equ 0056h
LDIRVM          equ 005Ch
INIGRP          equ 0072h
RDPSG           equ 0096h

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
IM2_TABLE       equ 0E800h
IM2_HI          equ 0E9h
IM2_JUMP        equ IM2_HI*257

        struct VOLLEY
Y               byte            ; the bullets' top line, 0 = not in flight
X               block FRONT_MAX ; each front slot's bullet's column, 0 = none
        ends

        org 0E000h
ram_start:
rates:                          ; copied from RATES_60 or RATES_50
fps:            ds 1
ship_whole:     ds 1            ; SHIP_SPEED / fps
ship_frac:      ds 1            ; ... and its remainder
bullet_whole:   ds 1
bullet_frac:    ds 1
call_whole:     ds 1
call_frac:      ds 1
shot_sound:     ds 2            ; SHOT_60 or SHOT_50
death_sound:    ds 2            ; DEATH_60 or DEATH_50
boom_frames:    ds BOOM_STAGES  ; frames each boom image shows
RATES_SIZE      equ $-rates

input:          ds 1            ; IN_* this frame
input_prev:     ds 1            ; ... and last frame (fire is edge-triggered)
kill_keys:      ds 1            ; the test keys 1..4 held (bits 1..4) this frame
kill_prev:      ds 1            ; ... and last frame
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
volleys:        ds MAX_VOLLEYS*VOLLEY
bullet_acc:     ds 1            ; Bresenham remainder, one for all (volleys keep their spacing)
bullet_step:    ds 1            ; this frame's px
pat_hi:         ds 1            ; GRPCGP's high byte with the VDP's write bit
sfx_ptr:        ds 2            ; the shot sound's next frame in its table, 0 = silent
death_ptr:      ds 2            ; the death sound's next frame in its table, 0 = silent
shot_mix:       ds 1            ; mixer bits the shot sound switches on now
death_mix:      ds 1            ; ... and the death sound
psg_io:         ds 1            ; mixer bits 6..7 as the BIOS set them
sat_w:          ds 2            ; GRPATR with the VDP's write bit
sat_buf:        ds (FRONT_MAX+1)*4+1    ; the front's slots, the incoming ship, the end marker
SAT_SIZE        equ $-sat_buf
reserve_buf:    ds (RESERVE_CELLS+1)*8  ; the reserve ships' cells' patterns (+1: a ship's spill)
RAM_SIZE        equ $-ram_start
        assert $ <= IM2_TABLE

; ---- Cartridge header -------------------------------------------------------

        output "terrafnt.rom"
        org 4000h
        db "AB"
        dw init
        ds 12,0
        assert $ == 4010h
        db VERSION_MAJOR, VERSION_MINOR
        dw VERSION_PATCH

; ---- Init ------------------------------------------------------------------

init:
        ld a,BG_COLOR
        ld (FORCLR),a
        ld (BAKCLR),a
        ld (BDRCLR),a
        xor a
        ld (CLIKSW),a
        call INIGRP             ; SCREEN 2, all black, sprites cleared

        ld a,(RG1SAV)
        or 02h                  ; 16x16 sprites
        ld b,a
        ld c,1
        call WRTVDP

        ld hl,SHIP_PATTERN      ; the six ship patterns follow each other
        ld de,(GRPPAT)
        ld bc,(3+BOOM_STAGES)*32
        call LDIRVM
        assert COMING_R_PATTERN == SHIP_PATTERN+32 && COMING_L_PATTERN == SHIP_PATTERN+64
        assert BOOM_PATTERN == SHIP_PATTERN+96
        assert NAME_SHIP == 0 && NAME_COMING_R == 4 && NAME_COMING_L == 8 && NAME_BOOM == 12

        ld hl,(GRPCOL)          ; the playfield's bitmap: the bullets' colour
        ld de,PLAY_TOP/8*256
        add hl,de
        ld bc,(PLAY_BOTTOM+1-PLAY_TOP)/8*256
        ld a,BULLET_COLOR*16+BG_COLOR
        call FILVRM
        assert PLAY_TOP%8 == 0 && (PLAY_BOTTOM+1)%8 == 0

        ld hl,ram_start         ; RAM starts as anything
        ld de,ram_start+1
        ld bc,RAM_SIZE-1
        ld (hl),0
        ldir

        ld hl,RATES_60
        ld a,(MSXID1)
        rla
        jr nc,.hz60
        ld hl,RATES_50
.hz60:  ld de,rates
        ld bc,RATES_SIZE
        ldir

        ld a,SHIP_X_MAX/2       ; one ship in the middle
        ld (ship_x),a
        ld a,1
        ld (front_mask),a
        ld (front_slots),a
        ld a,SHIP_ART_W
        ld (front_w),a
        ld a,RESERVES
        ld (reserves),a
        ld a,IN_FIRE|IN_CALL    ; armed only once released (read_input moves it to input_prev)
        ld (input),a
        ld a,KEYS_KILL
        ld (kill_keys),a
        ld a,(GRPCGP+1)         ; (SCREEN 2's pattern table: at 0000h or 2000h)
        or 40h
        ld (pat_hi),a
        ld hl,(GRPATR)
        set 6,h
        ld (sat_w),hl
        ld a,SPR_END
        ld (sat_buf+SAT_SIZE-1),a

        call init_sound
        call build_sat
        ld a,RESERVES
        call draw_reserves

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

main_loop:
        halt
        call upload_sat         ; last frame's sprites, in vertical blank
        call read_input
        call booms              ; before kill: a new boom's first image shows its full count
        call kill
        call move_bullets       ; first: in vertical blank, and a volley gone frees its slot
        call fire
        call call_up            ; before move_ship: the front stays put while one runs
        call move_ship
        call sfx
        call death              ; after sfx: its noise period wins over the shot's
        call build_sat
        jr main_loop

; The frame interrupt: reading the VDP's status acknowledges it
isr:    push af
        in a,(VDP_ADDR)
        pop af
        ei
        reti

; ---- Input -----------------------------------------------------------------

; input = IN_* from the keyboard (arrows, space) and both joysticks
; (button A fires, B calls up); input_prev = the last frame's
read_input:
        ld a,(input)
        ld (input_prev),a
        ld a,(kill_keys)
        ld (kill_prev),a
        in a,(PPI_C)            ; keyboard row KEY_ROW_NUM: the test keys
        and 0F0h
        or KEY_ROW_NUM
        out (PPI_C),a
        in a,(PPI_B)
        cpl
        and KEYS_KILL
        ld (kill_keys),a
        ld c,0
        in a,(PPI_C)            ; keyboard row KEY_ROW
        and 0F0h
        or KEY_ROW
        out (PPI_C),a
        in a,(PPI_B)
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
.k3:    in a,(PPI_C)            ; keyboard row KEY_ROW_C
        and 0F0h
        or KEY_ROW_C
        out (PPI_C),a
        in a,(PPI_B)
        and KEY_C
        jr nz,.k4
        set 7,c                 ; IN_CALL
.k4:    ld b,03h                ; joystick 1: (R15 and AFh) or 03h
        ld e,0AFh
        call read_joy
        ld b,4Ch                ; joystick 2: (R15 and DFh) or 4Ch
        ld e,0DFh
        call read_joy
        ld a,c
        ld (input),a
        ret
        assert IN_LEFT == 04h && IN_RIGHT == 08h && IN_FIRE == 10h && IN_CALL == 80h

; C |= the joystick's left, right, button A (fire) and B (call-up) as IN_*;
; the port is selected in R15 by (R15 and E) or B
read_joy:
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
        cpl                     ; 1 = pressed: bit 2 left, 3 right, 4 A, 5 B
        ld b,a
        and IN_LEFT|IN_RIGHT|IN_FIRE    ; button A fires
        or c
        ld c,a
        bit 5,b                 ; button B calls up
        ret z
        set 7,c                 ; IN_CALL
        ret

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

; Each volley in flight goes up BULLET_SPEED px/s; it's gone once its top
; leaves the playfield. All are erased first, then drawn, so one's erase
; never takes a pixel of another's.
move_bullets:
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
        sub b
        cp PLAY_TOP             ; (no borrow: Y >= PLAY_TOP > a step)
        jr nc,.keep
        xor a                   ; gone
.keep:  ld (ix+VOLLEY.Y),a
.enext: ld de,VOLLEY
        add ix,de
        pop bc
        djnz .erase
        ld ix,volleys
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
        assert PLAY_TOP > (BULLET_SPEED+49)/50

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
        ld c,1
        call volley_px
        ld hl,(shot_sound)      ; (re)start the sound
        ld (sfx_ptr),hl
        ret
        assert VOLLEY.Y == 0 && VOLLEY.X == 1 && SHIP_NOSE_DX > 0

; ---- Bitmap bullets --------------------------------------------------------

; The volley at IX (top line Y) drawn (C nonzero) or erased (C = 0) in the
; bitmap; the cells hold nothing else, since a volley's bullets are
; SHIP_ART_W > 8 px apart and volleys at least a frame's step + BULLET_H
; lines apart. Keeps IX.
volley_px:
        ld e,(ix+VOLLEY.Y)
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
        ld b,a
        ld a,80h                ; the column's bit in its byte
        jr z,.bit
.sh:    rrca
        djnz .sh
.bit:   ld c,a
.px:    call bullet_px
        pop hl
        pop de
        pop bc
.next:  inc hl
        djnz .b
        ret
        assert SHIP_ART_W > 8

; Lines E..E+BULLET_H-1 of the bitmap at pixel column D's cell := C (outside
; vertical blank too: 40 T between the VRAM writes)
bullet_px:
        ld b,BULLET_H
.cell:  ld a,e                  ; byte (E/8)*256 + (D and F8h) + E%8
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

; ---- Call-up ---------------------------------------------------------------

; A new press of C, with no call-up running, a reserve ship and a front
; spanning under FRONT_MAX slots: one ship leaves the reserve and comes in
; from the right if the front's middle is left of the screen's (or on it),
; else from the left, to glue on to that side of the front (an empty front:
; to where its last ship died). While one runs, it flies CALL_SPEED px/s;
; on arrival it joins the front (and move_ship moves it).
call_up:
        ld a,(call_on)
        or a
        jr nz,.fly
        ld a,(input_prev)
        cpl
        ld b,a
        ld a,(input)
        and b
        and IN_CALL
        ret z
        ld a,(reserves)
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

; New presses of the test keys 1..4: the front's first..fourth living ship
; (counted from the left) starts to die; from 4 down, so that a kill doesn't
; renumber the keys still to do
kill:
        ld a,(kill_prev)
        cpl
        ld b,a
        ld a,(kill_keys)
        and b
        ret z
        add a,a
        add a,a
        add a,a                 ; key 4 on bit 7
        ld c,a
        ld b,4
.key:   sla c
        jr nc,.next
        push bc
        call kill_nth
        pop bc
.next:  djnz .key
        ret
        assert KEYS_KILL == 1Eh

; The front's Bth living ship (1..) starts to die, if there is one
kill_nth:
        call alive_mask
        ld hl,boom_stage
.s:     or a
        ret z                   ; no more living ships
        rra
        jr nc,.next
        djnz .next              ; not the Bth yet
        ld (hl),1
        ld de,FRONT_MAX
        add hl,de
        ld a,(boom_frames)
        ld (hl),a               ; boom_left
.sound: ld hl,(death_sound)     ; (re)start the death sound (test.tcl: it starts here)
        ld (death_ptr),hl
        ret
.next:  inc hl
        jr .s

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
        ld hl,sat_buf
        ld ix,boom_stage
        ld a,(front_mask)
        ld d,a
        ld a,(ship_x)
        ld e,a                  ; this slot's art's left column
        ld b,FRONT_MAX
.slot:  ld c,SHIP_COLOR
        rr d
        jr nc,.park
        ld (hl),SHIP_TOP-1      ; a sprite's first line is Y + 1
        inc hl
        ld a,e
        sub SHIP_ART_L
        jr nc,.x
        add a,32                ; left of 0: the early clock
        ld c,SHIP_COLOR|SPR_EC
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
        ld a,l
        ld c,COMING_COLOR
        bit 7,h
        jr z,.cx
        add a,32                ; left of 0 (down to -16): the early clock
        ld c,COMING_COLOR|SPR_EC
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
        ret
.nocall:
        ld (hl),SPR_PARK
        ret
        assert COMING_L_ART_L <= 16 && COMING_R_ART_L+SHIP_ART_W <= 16
        assert SAT_SIZE == (FRONT_MAX+1)*4+1

; sat_buf to the VDP; right after halt, so OTIR is safe (vertical blank)
upload_sat:
        ld hl,(sat_w)
        di
        ld a,l
        out (VDP_ADDR),a
        ld a,h
        out (VDP_ADDR),a
        ei
        ld hl,sat_buf
        ld bc,SAT_SIZE*256+VDP_DATA
        otir
        ret

; ---- Status area -----------------------------------------------------------

; A (0..RESERVES) reserve ships in the bottom status area, from its left
; (the rest of RESERVE_CELLS blank), through the BIOS's VRAM routines
draw_reserves:
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
.show:  ld hl,(GRPCGP)
        ld de,RESERVE_VRAM
        add hl,de
        ex de,hl
        ld hl,reserve_buf
        ld bc,RESERVE_CELLS*8
        call LDIRVM
        ld hl,(GRPCOL)
        ld de,RESERVE_VRAM
        add hl,de
        ld bc,RESERVE_CELLS*8
        ld a,RESERVE_COLOR*16+BG_COLOR
        jp FILVRM

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
        ld a,PSG_VOL_C
        jp psg_write

; The mixer: all off but what the shot and death sounds switch on
; (shot_mix, death_mix; channels A and C, so no bit in both), the I/O
; ports' direction bits kept. Keeps HL.
mixer:  ld a,(shot_mix)
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

; One frame of the shot sound on channel A: volume, tone period, noise
; bit (sfx.py's table; with the noise on, the noise period is the shot's
; unless the death sound plays: it shares R6 and wins); its end marker
; silences the channel
sfx:
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
        jr mixer
.end:   ld hl,0
        ld (sfx_ptr),hl
        ld a,l
        ld (shot_mix),a
        ld e,a
        ld a,PSG_VOL_A
        call psg_write
        jr mixer
        assert ((SHOT_NOISE_BIT|MIX_TONE_A) & DEATH_MIX) == 0

; One frame of the death sound on channel C: volume, noise period, tone
; period (sfx.py's table), tone and noise on; its end marker silences the
; channel and switches them off
death:
        ld hl,(death_ptr)
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
        ld a,PSG_TONE_C
        call psg_write
        inc hl
        ld e,(hl)
        ld a,PSG_TONE_C+1
        call psg_write
        inc hl
        ld a,DEATH_MIX
.put:   ld (death_ptr),hl
        ld (death_mix),a
        ld e,d
        ld a,PSG_VOL_C
        call psg_write
        jp mixer
.end:   ld hl,0
        xor a
        jr .put

; ---- Data ------------------------------------------------------------------

RATES_60:       db 60, SHIP_SPEED/60, SHIP_SPEED%60, BULLET_SPEED/60, BULLET_SPEED%60
                db CALL_SPEED/60, CALL_SPEED%60
                dw SHOT_60, DEATH_60
                db BOOM1_60, BOOM2_60, BOOM3_60
RATES_50:       db 50, SHIP_SPEED/50, SHIP_SPEED%50, BULLET_SPEED/50, BULLET_SPEED%50
                db CALL_SPEED/50, CALL_SPEED%50
                dw SHOT_50, DEATH_50
                db BOOM1_50, BOOM2_50, BOOM3_50
        assert RATES_50-RATES_60 == RATES_SIZE && BOOM_STAGES == 3

        include "build/sprites.inc"
        include "build/sfx.inc"

        assert $ <= 8000h
        ds 8000h-$,0FFh         ; a 16 KB ROM
