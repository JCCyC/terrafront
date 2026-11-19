; ---------------------------------------------------------------------------
; Terra Front - player ship step (MSX1, 16 KB ROM at 4000h)
;
; SCREEN 2, all black. The top and bottom STATUS_LINES pixel lines are kept
; out of the playfield (for the score and the reserve ships later). The
; player ship sits at the bottom of the playfield and moves left and right
; at SHIP_SPEED px/s (20% faster than MSX Galaga's 90 px/s, measured on the
; Expert: 1.5 px a frame at 60 Hz), its art reaching both screen edges.
; Fire shoots a 1x3 bullet straight up from the nose at BULLET_SPEED px/s,
; at most MAX_BULLETS in flight; a press with all of them in flight is
; ignored. Each shot plays a 0.25 s laser "cheeoom" on PSG channel A.
; Controls: left / right arrows and space, or either joystick (either
; button fires). Fire is edge-triggered: one shot per press.
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
MAX_BULLETS     equ 2           ; player bullets in flight at once

; ---- Layout ----------------------------------------------------------------

PLAY_TOP        equ STATUS_LINES            ; first playfield line
PLAY_BOTTOM     equ 191-STATUS_LINES        ; last playfield line

; SHIP_* come from build/sprites.inc (png2spr.py), SHOT_* from build/sfx.inc
; (sfx.py), included with the data at the end
SHIP_TOP        equ PLAY_BOTTOM-SHIP_ART_B  ; the sprite's first line (its art's last row on PLAY_BOTTOM)
SHIP_X_MAX      equ 256-SHIP_ART_W          ; ship_x is the art's left column: 0..SHIP_X_MAX
BULLET_START    equ SHIP_TOP+SHIP_ART_T-BULLET_H    ; a new bullet's top line: right above the nose
        assert BULLET_START >= PLAY_TOP
        assert SHIP_ART_L < 32              ; the EC bit's 32 px cover the left clip

; Sprite names (16x16 sprites: patterns in steps of 4)
NAME_SHIP       equ 0
NAME_BULLET     equ 4
SPR_PARK        equ 0C0h        ; a sprite's Y off screen (lines 193..208); below D0h, the end marker
SPR_END         equ 0D0h        ; Y that ends the sprite list
SPR_EC          equ 80h         ; colour byte: early clock, X shifted 32 px left

; Input bits (as the joystick's in PSG R14, 1 = pressed)
IN_LEFT         equ 04h
IN_RIGHT        equ 08h
IN_FIRE         equ 10h

; ---- Hardware and BIOS -----------------------------------------------------

VDP_DATA        equ 98h
VDP_ADDR        equ 99h
PSG_ADDR        equ 0A0h
PSG_WRITE       equ 0A1h
PSG_READ        equ 0A2h
PPI_B           equ 0A9h        ; the keyboard matrix row selected (read, bit = 0 when pressed)
PPI_C           equ 0AAh        ; bits 0..3 select the row; 4..7 cassette, CAPS LED, click (kept)

PSG_TONE_A      equ 0           ; R0, R1: channel A's tone period
PSG_NOISE       equ 6           ; the noise period
PSG_MIXER       equ 7           ; bits 0..5 = 1: tone / noise off; bits 6, 7 the I/O ports' direction
PSG_VOL_A       equ 8
PSG_IO_A        equ 14          ; the joystick port's lines (read)
PSG_IO_B        equ 15          ; selects the joystick port (write)
MIX_TONE_A      equ 01h         ; mixer bit: channel A's tone (0 = on)
MIX_ALL_OFF     equ 3Fh

KEY_ROW         equ 8           ; space bit 0, left bit 4, right bit 7
KEY_SPACE       equ 01h
KEY_LEFT        equ 10h
KEY_RIGHT       equ 80h

MSXID1          equ 002Bh       ; bit 7 set = 50 Hz
WRTVDP          equ 0047h
LDIRVM          equ 005Ch
INIGRP          equ 0072h
RDPSG           equ 0096h

RG1SAV          equ 0F3E0h
CLIKSW          equ 0F3DBh
FORCLR          equ 0F3E9h
BAKCLR          equ 0F3EAh
BDRCLR          equ 0F3EBh
GRPATR          equ 0F3CDh      ; SCREEN 2's sprite attribute table
GRPPAT          equ 0F3CFh      ; ... and sprite pattern table

; ---- RAM -------------------------------------------------------------------

; IM 2: a 257-byte table of IM2_HI at IM2_TABLE, so any data bus value
; gives the vector IM2_HI*257, where a jp to isr goes
IM2_TABLE       equ 0E800h
IM2_HI          equ 0E9h
IM2_JUMP        equ IM2_HI*257

        struct BULLET
Y               byte            ; top line, 0 = not in flight
X               byte
ACC             byte            ; Bresenham remainder
        ends

        org 0E000h
ram_start:
rates:                          ; copied from RATES_60 or RATES_50
fps:            ds 1
ship_whole:     ds 1            ; SHIP_SPEED / fps
ship_frac:      ds 1            ; ... and its remainder
bullet_whole:   ds 1
bullet_frac:    ds 1
shot_sound:     ds 2            ; SHOT_60 or SHOT_50
RATES_SIZE      equ $-rates

input:          ds 1            ; IN_* this frame
input_prev:     ds 1            ; ... and last frame (fire is edge-triggered)
ship_x:         ds 1            ; the art's left column, 0..SHIP_X_MAX
ship_acc:       ds 1            ; Bresenham remainder
bullets:        ds MAX_BULLETS*BULLET
sfx_ptr:        ds 2            ; the shot sound's next frame in its table, 0 = silent
psg_io:         ds 1            ; mixer bits 6..7 as the BIOS set them
sat_w:          ds 2            ; GRPATR with the VDP's write bit
sat_buf:        ds 3*4+1        ; ship, bullets, the end marker
SAT_SIZE        equ $-sat_buf
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

        ld hl,SHIP_PATTERN
        ld de,(GRPPAT)
        ld bc,32
        call LDIRVM
        ld hl,(GRPPAT)
        ld de,NAME_BULLET*8
        add hl,de
        ex de,hl
        ld hl,BULLET_PATTERN
        ld bc,32
        call LDIRVM

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

        ld a,SHIP_X_MAX/2       ; the ship in the middle
        ld (ship_x),a
        ld a,IN_FIRE            ; fire armed only once released
        ld (input_prev),a
        ld hl,(GRPATR)
        set 6,h
        ld (sat_w),hl
        ld a,SPR_END
        ld (sat_buf+SAT_SIZE-1),a

        call init_sound
        call build_sat

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
        call move_ship
        call move_bullets       ; first: a bullet gone this frame frees its slot
        call fire
        call sfx
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
; (either button fires); input_prev = the last frame's
read_input:
        ld a,(input)
        ld (input_prev),a
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
.k3:    ld b,03h                ; joystick 1: (R15 and AFh) or 03h
        ld e,0AFh
        call read_joy
        ld b,4Ch                ; joystick 2: (R15 and DFh) or 4Ch
        ld e,0DFh
        call read_joy
        ld a,c
        ld (input),a
        ret
        assert IN_LEFT == 04h && IN_RIGHT == 08h && IN_FIRE == 10h

; C |= the joystick's left, right and either button as IN_*; the port is
; selected in R15 by (R15 and E) or B
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
        ei
        cpl                     ; 1 = pressed: bit 2 left, 3 right, 4 A, 5 B
        ld b,a
        rrca                    ; button B onto A's bit
        or b
        and IN_LEFT|IN_RIGHT|IN_FIRE
        or c
        ld c,a
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

; Left or right while one of them is held (not both), the art kept on screen
move_ship:
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
        cp SHIP_X_MAX+1
        jr c,.set
        ld a,SHIP_X_MAX
        jr .set
.left:  sub b
        jr nc,.set
        xor a
.set:   ld (hl),a
        ret
        assert SHIP_X_MAX+(SHIP_SPEED+49)/50 < 256

; Each bullet in flight goes up; it's gone once its top leaves the playfield
move_bullets:
        ld ix,bullets
        ld c,MAX_BULLETS
.loop:  ld a,(ix+BULLET.Y)
        or a
        jr z,.next
        ld a,(bullet_whole)
        ld b,a
        push ix
        pop hl
        ld de,BULLET.ACC
        add hl,de
        ld a,(bullet_frac)
        ld d,a
        call bresenham          ; A = step
        ld b,a
        ld a,(ix+BULLET.Y)
        sub b
        cp PLAY_TOP             ; (no borrow: Y >= PLAY_TOP > a step)
        jr nc,.keep
        xor a                   ; gone
.keep:  ld (ix+BULLET.Y),a
.next:  ld de,BULLET
        add ix,de
        dec c
        jr nz,.loop
        ret
        assert PLAY_TOP > (BULLET_SPEED+49)/50

; A new press of fire, with a bullet slot free: a bullet from the nose,
; and the laser sound
fire:
        ld a,(input_prev)
        cpl
        ld b,a
        ld a,(input)
        and b
        and IN_FIRE
        ret z
        ld hl,bullets
        ld de,BULLET
        ld b,MAX_BULLETS
.find:  ld a,(hl)
        or a
        jr z,.free
        add hl,de
        djnz .find
        ret                     ; all in flight
.free:  ld (hl),BULLET_START    ; Y
        inc hl
        ld a,(ship_x)
        add a,SHIP_NOSE_DX
        ld (hl),a               ; X
        inc hl
        ld (hl),0               ; ACC
        ld hl,(shot_sound)      ; (re)start the sound
        ld (sfx_ptr),hl
        ret
        assert BULLET.Y == 0 && BULLET.X == 1 && BULLET.ACC == 2

; ---- Sprites ---------------------------------------------------------------

; sat_buf from the ship and the bullets (the end marker stays)
build_sat:
        ld hl,sat_buf
        ld (hl),SHIP_TOP-1      ; a sprite's first line is Y + 1
        inc hl
        ld c,SHIP_COLOR
        ld a,(ship_x)
        sub SHIP_ART_L
        jr nc,.x
        add a,32                ; left of 0: the early clock
        ld c,SHIP_COLOR|SPR_EC
.x:     ld (hl),a
        inc hl
        ld (hl),NAME_SHIP
        inc hl
        ld (hl),c
        inc hl
        ld de,bullets
        ld b,MAX_BULLETS
.bul:   ld a,(de)               ; Y
        inc de
        or a
        jr z,.park
        dec a
        ld (hl),a
        inc hl
        ld a,(de)               ; X
        ld (hl),a
        jr .rest
.park:  ld (hl),SPR_PARK
        inc hl
.rest:  inc hl
        inc de
        inc de
        ld (hl),NAME_BULLET
        inc hl
        ld (hl),BULLET_COLOR
        inc hl
        djnz .bul
        ret
        assert SAT_SIZE == (1+MAX_BULLETS)*4+1

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

; ---- Sound -----------------------------------------------------------------

; PSG register A = E
psg_write:
        out (PSG_ADDR),a
        ld a,e
        out (PSG_WRITE),a
        ret

; Mixer bits 6..7 kept from the BIOS (the I/O ports' direction); all
; channels off, the shot's noise period
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
        ld e,SHOT_NOISE
        ld a,PSG_NOISE
        jp psg_write

; One frame of the shot sound on channel A: volume, tone period, noise
; bit (sfx.py's table); its end marker silences the channel
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
        ld a,(psg_io)
        or MIX_ALL_OFF-MIX_TONE_A
        xor (hl)                ; the noise bit, if any, to 0 (on)
        ld e,a
        ld a,PSG_MIXER
        call psg_write
        inc hl
        ld (sfx_ptr),hl
        ret
.end:   ld e,0
        ld a,PSG_VOL_A
        call psg_write
        ld a,(psg_io)
        or MIX_ALL_OFF
        ld e,a
        ld a,PSG_MIXER
        call psg_write
        ld hl,0
        ld (sfx_ptr),hl
        ret

; ---- Data ------------------------------------------------------------------

RATES_60:       db 60, SHIP_SPEED/60, SHIP_SPEED%60, BULLET_SPEED/60, BULLET_SPEED%60
                dw SHOT_60
RATES_50:       db 50, SHIP_SPEED/50, SHIP_SPEED%50, BULLET_SPEED/50, BULLET_SPEED%50
                dw SHOT_50
        assert RATES_50-RATES_60 == RATES_SIZE

; The bullet: column 0, rows 0..BULLET_H-1 of a 16x16 pattern
BULLET_PATTERN:
        ds BULLET_H,80h
        ds 32-BULLET_H,0

        include "build/sprites.inc"
        include "build/sfx.inc"

        assert $ <= 8000h
        ds 8000h-$,0FFh         ; a 16 KB ROM
