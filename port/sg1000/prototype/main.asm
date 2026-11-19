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
previous_controls db
viewer_frame db
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
  ld (previous_controls),a
  ld (viewer_frame),a
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
  bit 5,a
  jr nz,preview_frame
  call physics_x
  call physics_y
  call animate
  jr frame_draw
preview_frame:
  call animation_viewer
frame_draw:
  call draw_sonic
  ld a,(controls)
  ld (previous_controls),a
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
  jr z,anim_spin
  ld a,(controls)
  bit 0,a
  jr z,not_looking_up
  ld a,$14
  jr anim_save
not_looking_up:
  bit 1,a
  jr z,not_looking_down
  ld hl,(xvel)
  ld a,h
  or l
  jr nz,anim_spin
  ld a,$07
  jr anim_save
not_looking_down:
  ld hl,(xvel)
  ld a,h
  or l
  jr nz,anim_running
  ; Original standing frame, with occasional idle animation frames.
  ld a,(frame_tick)
  cp 192
  jr c,anim_still
  rrca
  rrca
  rrca
  rrca
  and 3
  add a,$15
  jr anim_save
anim_still:
  ld a,$06
  jr anim_save
anim_running:
  ld a,(controls)
  bit 3,a
  jr z,check_brake_left
  bit 7,h
  jr nz,anim_brake
check_brake_left:
  bit 2,a
  jr z,anim_walk
  bit 7,h
  jr nz,anim_walk
  jr anim_brake
anim_brake:
  ld a,$13
  jr anim_save
anim_walk:
  ld a,(frame_tick)
  rrca
  rrca
  rrca
  and 7
  cp 6
  jr c,anim_save
  sub 6
  jr anim_save
anim_spin:
  ld a,(frame_tick)
  rrca
  rrca
  and 3
  add a,$08
anim_save:
  ld (frame_id),a
  ret

; Hold button 2 and tap left/right to inspect every frame, including
; frames for actions the prototype does not implement yet.
animation_viewer:
  ld a,(controls)
  ld b,a
  ld a,(previous_controls)
  cpl
  and b
  bit 3,a
  jr z,viewer_check_left
  ld a,(viewer_frame)
  inc a
  cp 42
  jr c,viewer_store
  xor a
  jr viewer_store
viewer_check_left:
  bit 2,a
  jr z,viewer_use
  ld a,(viewer_frame)
  or a
  jr nz,viewer_dec
  ld a,42
viewer_dec:
  dec a
viewer_store:
  ld (viewer_frame),a
viewer_use:
  ld a,(viewer_frame)
  ld (frame_id),a
  ret

draw_sonic:
  ; Each frame is 256 pattern bytes followed by 8 sprite colours.
  ld a,(frame_id)
  ld e,a
  ld a,(facing)
  or a
  ld a,e
  jr z,frame_index_ready
  add a,42
frame_index_ready:
  add a,a
  ld e,a
  ld d,0
  ld hl,frame_ptrs
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  push de
  ld hl,$7800
  call vdp_addr
  pop hl
  ld bc,256
  call vdp_copy
  push hl
  ld hl,$5B00
  call vdp_addr
  pop hl
  ; Two 16x16 layers in each 16x16 quadrant: four sprites per scanline.
  ld b,0
sprite_loop:
  ld a,(ypos+1)
  bit 2,b
  jr z,sprite_top
  add a,16
sprite_top:
  dec a
  out ($BE),a
  ld a,(xpos+1)
  bit 1,b
  jr z,sprite_left
  add a,16
sprite_left:
  out ($BE),a
  ld a,b
  add a,a
  add a,a
  out ($BE),a
  ld a,(hl)
  out ($BE),a
  inc hl
  inc b
  ld a,b
  cp 8
  jr nz,sprite_loop
  ld a,$D0
  out ($BE),a
  ret


; Graphics I, 16K VRAM, display enabled, no interrupt.
vdpregs:
.db $00,$C2,$06,$80,$00,$36,$07,$01
heights:
.INCBIN "build/sg1000/prototype/heights.bin"
ground_map:
.INCBIN "build/sg1000/prototype/ground.bin"
frame_ptrs:
.dw frame_data + 0
.dw frame_data + 264
.dw frame_data + 528
.dw frame_data + 792
.dw frame_data + 1056
.dw frame_data + 1320
.dw frame_data + 1584
.dw frame_data + 1848
.dw frame_data + 2112
.dw frame_data + 2376
.dw frame_data + 2640
.dw frame_data + 2904
.dw frame_data + 3168
.dw frame_data + 3432
.dw frame_data + 3696
.dw frame_data + 3960
.dw frame_data + 4224
.dw frame_data + 4488
.dw frame_data + 4752
.dw frame_data + 5016
.dw frame_data + 5280
.dw frame_data + 5544
.dw frame_data + 5808
.dw frame_data + 6072
.dw frame_data + 6336
.dw frame_data + 6600
.dw frame_data + 6864
.dw frame_data + 7128
.dw frame_data + 7392
.dw frame_data + 7656
.dw frame_data + 7920
.dw frame_data + 8184
.dw frame_data + 8448
.dw frame_data + 8712
.dw frame_data + 8976
.dw frame_data + 9240
.dw frame_data + 9504
.dw frame_data + 9768
.dw frame_data + 10032
.dw frame_data + 10296
.dw frame_data + 10560
.dw frame_data + 10824
.dw frame_data + 11088
.dw frame_data + 11352
.dw frame_data + 11616
.dw frame_data + 11880
.dw frame_data + 12144
.dw frame_data + 12408
.dw frame_data + 12672
.dw frame_data + 12936
.dw frame_data + 13200
.dw frame_data + 13464
.dw frame_data + 13728
.dw frame_data + 13992
.dw frame_data + 14256
.dw frame_data + 14520
.dw frame_data + 14784
.dw frame_data + 15048
.dw frame_data + 15312
.dw frame_data + 15576
.dw frame_data + 15840
.dw frame_data + 16104
.dw frame_data + 16368
.dw frame_data + 16632
.dw frame_data + 16896
.dw frame_data + 17160
.dw frame_data + 17424
.dw frame_data + 17688
.dw frame_data + 17952
.dw frame_data + 18216
.dw frame_data + 18480
.dw frame_data + 18744
.dw frame_data + 19008
.dw frame_data + 19272
.dw frame_data + 19536
.dw frame_data + 19800
.dw frame_data + 20064
.dw frame_data + 20328
.dw frame_data + 20592
.dw frame_data + 20856
.dw frame_data + 21120
.dw frame_data + 21384
.dw frame_data + 21648
.dw frame_data + 21912
frame_data:
.INCBIN "build/sg1000/prototype/sonic_frames.bin"
