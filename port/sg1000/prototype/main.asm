; SG-1000 Sonic movement sandbox, WLA-DX. All motion values are 8.8 fixed point.
.MEMORYMAP
  DEFAULTSLOT 0
  SLOTSIZE $8000
  SLOT 0 $0000
  SLOTSIZE $0400
  SLOT 1 $C000
.ENDME
.ROMBANKMAP
  BANKSTOTAL 1
  BANKSIZE $8000
  BANKS 1
.ENDRO
.RAMSECTION "state" SLOT 1
xpos dw
ypos dw
xvel dw
yvel dw
grounded db
jump_timer db
jump_latch db
facing db
frame_tick db
frame_id db
controls db
.ENDS
.BANK 0 SLOT 0
.ORG 0
  di
  jp init
.ORG $0038
  reti
.ORG $0066
  retn
.ORG $0100
init:
  di
  im 1
  ld sp,$C3F0
  xor a
  ld (xvel),a
  ld (xvel+1),a
  ld (yvel),a
  ld (yvel+1),a
  ld (jump_timer),a
  ld (jump_latch),a
  ld (facing),a
  ld (frame_tick),a
  ld hl,$1800             ; 24 pixels
  ld (xpos),hl
  ld hl,$8000             ; top y=128, ground y=160
  ld (ypos),hl
  ld a,1
  ld (grounded),a
  ; Graphics I: name $1800, colour $2000, pattern $0000,
  ; sprite attributes $1B00 and sprite patterns $3800.
  ld hl,vdpregs
  ld b,8
  ld c,0
reg_loop:
  ld a,(hl)
  out ($BF),a
  ld a,c
  or $80
  out ($BF),a
  inc hl
  inc c
  djnz reg_loop
  ; Clear all 16 KiB VRAM.
  ld hl,$4000
  call vdp_addr
  ld bc,$4000
clear_vram:
  xor a
  out ($BE),a
  dec bc
  ld a,b
  or c
  jr nz,clear_vram
  ; Character 1 is solid white; character 0 remains blank.
  ld hl,$4008
  call vdp_addr
  ld b,8
solid_tile:
  ld a,$FF
  out ($BE),a
  djnz solid_tile
  ld hl,$6000
  call vdp_addr
  ld a,$F1
  out ($BE),a
  ; Name table: black sky and white stair-stepped course.
  ld hl,$5800
  call vdp_addr
  ld hl,ground_map
  ld bc,768
  call vdp_copy
  call draw_sonic
main_loop:
  ; Poll vertical blank; status read acknowledges it. No interrupts required.
wait_vblank:
  in a,($BF)
  and $80
  jr z,wait_vblank
  in a,($DC)
  cpl
  ld (controls),a
  call physics_x
  call physics_y
  call animate
  call draw_sonic
  jr main_loop

; Set a VRAM write address from HL, already ORed with $4000.
vdp_addr:
  ld a,l
  out ($BF),a
  ld a,h
  out ($BF),a
  ret
vdp_copy:
  ld a,(hl)
  out ($BE),a
  inc hl
  dec bc
  ld a,b
  or c
  jr nz,vdp_copy
  ret

physics_x:
  ld a,(controls)
  bit 3,a                 ; right has priority when both are held
  jr nz,move_right
  bit 2,a
  jr nz,move_left
  ld hl,(xvel)
  ld a,h
  or l
  ret z
  bit 7,h
  jr nz,coast_left
  ld de,$0008
  or a
  sbc hl,de
  jr nc,save_vx
  ld hl,0
  jr save_vx
coast_left:
  ld de,$0008
  add hl,de
  bit 7,h
  jr nz,save_vx
  ld hl,0
  jr save_vx
move_right:
  xor a
  ld (facing),a
  ld hl,(xvel)
  bit 7,h
  jr nz,brake_right
  ld de,$0300
  or a
  sbc hl,de
  add hl,de
  jr nc,cap_right
  ld de,$0010
  add hl,de
  jr save_vx
cap_right:
  ld hl,$0300
  jr save_vx
brake_right:
  ld de,$0030
  add hl,de
  bit 7,h
  jr nz,save_vx
  ld hl,0
  jr save_vx
move_left:
  ld a,1
  ld (facing),a
  ld hl,(xvel)
  bit 7,h
  jr nz,accelerate_left
  ld a,h
  or l
  jr z,accelerate_left
  ld de,$0030
  or a
  sbc hl,de
  jr nc,save_vx
  ld hl,0
  jr save_vx
accelerate_left:
  ld de,$FD00             ; -3 px/frame
  or a
  sbc hl,de
  add hl,de
  jp m,cap_left
  ld de,$0010
  or a
  sbc hl,de
  jr save_vx
cap_left:
  ld hl,$FD00
save_vx:
  ld (xvel),hl
  ld de,(xpos)
  add hl,de
  ; Detect 16-bit underflow/overflow using the velocity sign and carry.
  push af
  ld a,(xvel+1)
  bit 7,a
  jr z,check_positive_edge
  pop af
  jr nc,left_edge
  jr check_right_limit
check_positive_edge:
  pop af
  jr c,right_edge
check_right_limit:
  ld a,h
  cp 233
  jr nc,right_edge
  ld (xpos),hl
  ret
left_edge:
  ld hl,0
  ld (xpos),hl
  ld (xvel),hl
  ret
right_edge:
  ld hl,$E800
  ld (xpos),hl
  ld hl,0
  ld (xvel),hl
  ret

physics_y:
  ; Release latch permits a new jump after landing.
  ld a,(controls)
  bit 4,a
  jr nz,jump_pressed
  xor a
  ld (jump_latch),a
  ld (jump_timer),a
  jr gravity
jump_pressed:
  ld a,(jump_timer)
  or a
  jr nz,hold_jump
  ld a,(jump_latch)
  or a
  jr nz,gravity
  ld a,(grounded)
  or a
  jr z,gravity
  ld a,1
  ld (jump_latch),a
  xor a
  ld (grounded),a
  ld a,16
  ld (jump_timer),a
hold_jump:
  ld hl,$FC80             ; -3.5 px/frame, held for up to 16 ticks
  ld (yvel),hl
  ld a,(jump_timer)
  dec a
  ld (jump_timer),a
  jr move_y
 gravity:
  ld a,(grounded)
  or a
  jr nz,follow_floor
  ld hl,(yvel)
  ld de,$0038
  add hl,de
  bit 7,h
  jr nz,store_yvel
  ld de,$0800
  or a
  sbc hl,de
  add hl,de
  jr c,store_yvel
  ld hl,$0800
store_yvel:
  ld (yvel),hl
move_y:
  ld hl,(ypos)
  ld de,(yvel)
  add hl,de
  ld (ypos),hl
  ; Only land while descending; stand on the floor at Sonic's centre.
  ld hl,(yvel)
  bit 7,h
  ret nz
  call get_floor
  ld hl,(ypos)
  ld a,h
  add a,32
  cp c
  ret c
follow_floor:
  call get_floor
  ld a,c
  sub 32
  ld h,a
  ld l,0
  ld (ypos),hl
  ld hl,0
  ld (yvel),hl
  ld a,1
  ld (grounded),a
  ret
get_floor:
  ld a,(xpos+1)
  add a,12
  srl a
  srl a
  srl a
  ld e,a
  ld d,0
  ld hl,heights
  add hl,de
  ld c,(hl)
  ret

animate:
  ld a,(frame_tick)
  inc a
  ld (frame_tick),a
  ld a,(grounded)
  or a
  jr nz,anim_ground
  ld a,7                 ; rolling/jump frame 08
  ld (frame_id),a
  ret
anim_ground:
  ld hl,(xvel)
  ld a,h
  or l
  jr nz,anim_run
  ld a,6                 ; standing frame 06
  ld (frame_id),a
  ret
anim_run:
  ld a,(frame_tick)
  rrca
  rrca
  rrca
  and 7
  cp 6
  jr c,anim_save
  sub 6
anim_save:
  ld (frame_id),a
  ret

draw_sonic:
  ; Select patterns and colours for animation frame and facing.
  ld a,(facing)
  add a,a
  add a,a
  add a,a
  ld b,a
  ld a,(frame_id)
  add a,b
  add a,a
  ld e,a
  ld d,0
  ld hl,pattern_ptrs
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  push de
  ld hl,$7800
  call vdp_addr
  pop hl
  ld bc,96
  call vdp_copy
  ld a,(facing)
  add a,a
  add a,a
  add a,a
  ld b,a
  ld a,(frame_id)
  add a,b
  add a,a
  ld e,a
  ld d,0
  ld hl,colour_ptrs
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  ex de,hl
  push hl
  ld hl,$5B00
  call vdp_addr
  pop hl
  ; Original 12 tiles are in 8x16 pairs, three columns by two rows.
  ; Emit 12 8x8 hardware sprites, no more than 3 per scanline.
  ld b,0
sprite_loop:
  ld a,b
  and 1
  add a,a
  add a,a
  add a,a
  ld c,a
  ld a,b
  cp 6
  jr c,sprite_y_ready
  ld a,c
  add a,16
  ld c,a
sprite_y_ready:
  ld a,(ypos+1)
  add a,c
  dec a                   ; TMS sprite Y is top minus one
  out ($BE),a
  ld a,b
  cp 6
  jr c,column_in_first_half
  sub 6
column_in_first_half:
  srl a
  add a,a
  add a,a
  add a,a
  ld c,a
  ld a,(xpos+1)
  add a,c
  out ($BE),a
  ld a,b
  out ($BE),a
  ld a,(hl)
  out ($BE),a
  inc hl
  inc b
  ld a,b
  cp 12
  jr nz,sprite_loop
  ld a,$D0
  out ($BE),a
  ret


; Graphics I, 16K VRAM, display enabled, no interrupt.
vdpregs:
.db $00,$C0,$06,$80,$00,$36,$07,$01
heights:
.INCBIN "build/sg1000/prototype/heights.bin"
ground_map:
.INCBIN "build/sg1000/prototype/ground.bin"
pattern_ptrs:
.dw r00p,r01p,r02p,r03p,r04p,r05p,r06p,r08p
.dw l00p,l01p,l02p,l03p,l04p,l05p,l06p,l08p
colour_ptrs:
.dw r00c,r01c,r02c,r03c,r04c,r05c,r06c,r08c
.dw l00c,l01c,l02c,l03c,l04c,l05c,l06c,l08c
r00p:
.INCBIN "build/sg1000/prototype/sonic/sonic_00_r.patterns"
r00c:
.INCBIN "build/sg1000/prototype/sonic/sonic_00_r.colours"
r01p:
.INCBIN "build/sg1000/prototype/sonic/sonic_01_r.patterns"
r01c:
.INCBIN "build/sg1000/prototype/sonic/sonic_01_r.colours"
r02p:
.INCBIN "build/sg1000/prototype/sonic/sonic_02_r.patterns"
r02c:
.INCBIN "build/sg1000/prototype/sonic/sonic_02_r.colours"
r03p:
.INCBIN "build/sg1000/prototype/sonic/sonic_03_r.patterns"
r03c:
.INCBIN "build/sg1000/prototype/sonic/sonic_03_r.colours"
r04p:
.INCBIN "build/sg1000/prototype/sonic/sonic_04_r.patterns"
r04c:
.INCBIN "build/sg1000/prototype/sonic/sonic_04_r.colours"
r05p:
.INCBIN "build/sg1000/prototype/sonic/sonic_05_r.patterns"
r05c:
.INCBIN "build/sg1000/prototype/sonic/sonic_05_r.colours"
r06p:
.INCBIN "build/sg1000/prototype/sonic/sonic_06_r.patterns"
r06c:
.INCBIN "build/sg1000/prototype/sonic/sonic_06_r.colours"
r08p:
.INCBIN "build/sg1000/prototype/sonic/sonic_08_r.patterns"
r08c:
.INCBIN "build/sg1000/prototype/sonic/sonic_08_r.colours"
l00p:
.INCBIN "build/sg1000/prototype/sonic/sonic_00_l.patterns"
l00c:
.INCBIN "build/sg1000/prototype/sonic/sonic_00_l.colours"
l01p:
.INCBIN "build/sg1000/prototype/sonic/sonic_01_l.patterns"
l01c:
.INCBIN "build/sg1000/prototype/sonic/sonic_01_l.colours"
l02p:
.INCBIN "build/sg1000/prototype/sonic/sonic_02_l.patterns"
l02c:
.INCBIN "build/sg1000/prototype/sonic/sonic_02_l.colours"
l03p:
.INCBIN "build/sg1000/prototype/sonic/sonic_03_l.patterns"
l03c:
.INCBIN "build/sg1000/prototype/sonic/sonic_03_l.colours"
l04p:
.INCBIN "build/sg1000/prototype/sonic/sonic_04_l.patterns"
l04c:
.INCBIN "build/sg1000/prototype/sonic/sonic_04_l.colours"
l05p:
.INCBIN "build/sg1000/prototype/sonic/sonic_05_l.patterns"
l05c:
.INCBIN "build/sg1000/prototype/sonic/sonic_05_l.colours"
l06p:
.INCBIN "build/sg1000/prototype/sonic/sonic_06_l.patterns"
l06c:
.INCBIN "build/sg1000/prototype/sonic/sonic_06_l.colours"
l08p:
.INCBIN "build/sg1000/prototype/sonic/sonic_08_l.patterns"
l08c:
.INCBIN "build/sg1000/prototype/sonic/sonic_08_l.colours"
