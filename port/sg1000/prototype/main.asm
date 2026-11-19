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
xpage db
ypage db
camera_x db
camera_y db
rolling db
idle_timer db
idle_phase db
sprite_draw_y db
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
  ld (xpage),a
  ld (ypage),a
  ld (rolling),a
  ld (idle_timer),a
  ld (idle_phase),a
  ld a,$FF
  ld (camera_x),a
  ld (camera_y),a
  ld hl,$1800             ; 24 pixels
  ld (xpos),hl
  ld hl,$B000             ; world top y=176, ground y=208
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
  out ($BE),a              ; characters 0-7
  out ($BE),a              ; characters 8-15
  ; Upload the original SMS world-map glyphs, reduced to white pixels.
  ld hl,$4040             ; character 8
  call vdp_addr
  ld hl,menu_font_patterns
  ld bc,64
  call vdp_copy
  ld hl,$4010             ; character 2: selection arrow
  call vdp_addr
  ld hl,menu_arrow
  ld bc,8
  call vdp_copy
  ; Terminate the hardware sprite list while the menu is visible.
  ld hl,$5B00
  call vdp_addr
  ld a,$D0
  out ($BE),a
  call zone_menu
  call update_camera
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
  call update_camera
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

; Single choice menu. Require a fresh button press and release so choosing
; with button 1 cannot cause a jump (or button 2 start the frame viewer).
zone_menu:
  ld hl,$590A             ; row 8, column 10
  call vdp_addr
  ld hl,menu_title
  ld bc,11
  call vdp_copy
  ld hl,$598D             ; row 12, column 13
  call vdp_addr
  ld hl,menu_test
  ld bc,6
  call vdp_copy
menu_wait_initial_release:
  call menu_poll
  and $30
  jr nz,menu_wait_initial_release
menu_wait_press:
  call menu_poll
  and $30
  jr z,menu_wait_press
menu_wait_release:
  call menu_poll
  and $30
  jr nz,menu_wait_release
  ret
menu_poll:
  in a,($BF)
  and $80
  jr z,menu_poll
  in a,($DC)
  cpl
  ret

menu_title:
.db 8,9,10,11,0,12,11,13,11,14,15 ; ZONE SELECT
menu_test:
.db 2,0,15,11,12,15               ; > TEST
menu_arrow:
.db $00,$40,$60,$70,$60,$40,$00,$00
menu_font_patterns:
.INCBIN "build/sg1000/prototype/menu_font.bin"

physics_x:
  ; Down while grounded and moving enters a persistent roll.
  ld a,(rolling)
  or a
  jr nz,roll_physics
  ld a,(grounded)
  or a
  jr z,normal_movement
  ld a,(controls)
  bit 1,a
  jr z,normal_movement
  ld hl,(xvel)
  bit 7,h
  jr z,roll_check_speed
  xor a
  sub l
  ld l,a
  ld a,0
  sbc a,h
  ld h,a
roll_check_speed:
  ld a,h
  or a
  jr nz,enter_roll
  ld a,l
  cp $80
  jr c,normal_movement
enter_roll:
  ld a,1
  ld (rolling),a
roll_physics:
  ; No regular acceleration or steering while rolling. The height table
  ; indicates whether the next 8-pixel column is downhill in travel direction.
  call rolling_downhill
  or a
  jr nz,roll_maintain_speed
  ld hl,(xvel)
  bit 7,h
  jr nz,roll_slow_left
  ld de,$0010
  or a
  sbc hl,de
  jr c,roll_stop
  ld a,h
  or l
  jr z,roll_stop
  jp save_vx
roll_slow_left:
  ld de,$0010
  add hl,de
  bit 7,h
  jp nz,save_vx
roll_stop:
  xor a
  ld (rolling),a
  ld hl,0
  jp save_vx
roll_maintain_speed:
  ld hl,(xvel)
  jp save_vx
normal_movement:
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
  ; Integrate signed 8.8 velocity into a 16.8-bit world position.
  ld a,h
  bit 7,a
  jr nz,x_integrate_negative
  ld de,(xpos)
  add hl,de
  ld (xpos),hl
  ld a,(xpage)
  adc a,0
  ld (xpage),a
  jr check_right_limit
x_integrate_negative:
  ld de,(xpos)
  add hl,de
  ld (xpos),hl
  ld a,(xpage)
  adc a,$FF
  ld (xpage),a
  cp $FF
  jr z,left_edge
check_right_limit:
  ; Sprite's left edge is limited to world x=744 (768 - 24).
  ld a,(xpage)
  cp 2
  jr c,x_done
  jr nz,right_edge
  ld a,(xpos+1)
  cp 233
  jr nc,right_edge
x_done:
  ret
left_edge:
  xor a
  ld (xpage),a
  ld hl,0
  ld (xpos),hl
  ld (xvel),hl
  ret
right_edge:
  ld a,2
  ld (xpage),a
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
  ld (rolling),a
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
  ld hl,(yvel)
  bit 7,h
  jr nz,y_integrate_negative
  ld de,(ypos)
  add hl,de
  ld (ypos),hl
  ld a,(ypage)
  adc a,0
  ld (ypage),a
  jr check_landing
 y_integrate_negative:
  ld de,(ypos)
  add hl,de
  ld (ypos),hl
  ld a,(ypage)
  adc a,$FF
  ld (ypage),a
check_landing:
  ; Only land while descending; stand on the floor at Sonic's centre.
  ld hl,(yvel)
  bit 7,h
  ret nz
  call get_floor
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld de,32
  add hl,de
  or a
  sbc hl,bc
  ret c
follow_floor:
  call get_floor
  ld h,b
  ld l,c
  ld de,32
  or a
  sbc hl,de
  ld a,h
  ld (ypage),a
  ld h,l
  ld l,0
  ld (ypos),hl
  ld hl,0
  ld (yvel),hl
  ld a,1
  ld (grounded),a
  ret
get_floor:
  ; 16-bit world x at Sonic's centre, divided by eight.
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,12
  add hl,de
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  add hl,hl
  ld de,heights
  add hl,de
  ld c,(hl)
  inc hl
  ld b,(hl)
  ret

; Return A=1 when the next terrain column in the direction of travel is
; lower (a larger Y value). Flat and uphill return 0. Clamped at world edges.
rolling_downhill:
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,12
  add hl,de
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld a,l
  ld d,a
  ld a,(xvel+1)
  bit 7,a
  jr nz,roll_check_left_edge
  ld a,d
  cp 95
  jr nc,not_downhill
  jr roll_fetch_floor
roll_check_left_edge:
  ld a,d
  or a
  jr z,not_downhill
roll_fetch_floor:
  add hl,hl
  ld de,heights
  add hl,de
  ld c,(hl)
  inc hl
  ld b,(hl)
  ld a,(xvel+1)
  bit 7,a
  jr nz,roll_read_left_floor
  inc hl
  jr roll_read_next_floor
roll_read_left_floor:
  dec hl
  dec hl
  dec hl
roll_read_next_floor:
  ld e,(hl)
  inc hl
  ld d,(hl)
  ex de,hl
  or a
  sbc hl,bc
  jr c,not_downhill
  ld a,h
  or l
  jr z,not_downhill
  ld a,1
  ret
not_downhill:
  xor a
  ret

; Camera coordinates are in 8-pixel tiles. The 9918 has no fine-scroll
; register; redraw the name table only when a tile boundary is crossed.
update_camera:
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,104
  or a
  sbc hl,de
  jr nc,camera_x_nonnegative
  ld hl,0
camera_x_nonnegative:
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld a,l
  cp 65
  jr c,camera_x_ready
  ld a,64
camera_x_ready:
  ld c,a
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld de,72
  or a
  sbc hl,de
  jr nc,camera_y_nonnegative
  ld hl,0
camera_y_nonnegative:
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld a,l
  cp 25
  jr c,camera_y_ready
  ld a,24
camera_y_ready:
  ld b,a
  ld a,(camera_x)
  cp c
  jr nz,camera_changed
  ld a,(camera_y)
  cp b
  ret z
camera_changed:
  ld a,c
  ld (camera_x),a
  ld a,b
  ld (camera_y),a
  ; world map address = base + camera_y * 96 + camera_x
  ld l,b
  ld h,0
  add hl,hl                ; * 2
  add hl,hl                ; * 4
  add hl,hl                ; * 8
  add hl,hl                ; * 16
  add hl,hl                ; * 32
  ld d,h
  ld e,l
  add hl,hl                ; * 64
  add hl,de                ; * 96
  ld e,c
  ld d,0
  add hl,de
  ld de,ground_map
  add hl,de
  push hl
  ld hl,$5800
  call vdp_addr
  pop hl
  ld b,24
camera_row:
  ld c,32
camera_col:
  ld a,(hl)
  out ($BE),a
  inc hl
  dec c
  jr nz,camera_col
  ld de,64
  add hl,de
  djnz camera_row
  ret

animate:
  ld a,(frame_tick)
  inc a
  ld (frame_tick),a
  ld a,(grounded)
  or a
  jr z,anim_air
  ld a,(rolling)
  or a
  jr z,anim_not_rolling
  call reset_idle
  jp anim_spin
anim_not_rolling:
  ld hl,(xvel)
  ld a,h
  or l
  jr nz,anim_moving
  ; Looking is allowed only when standing still, with no movement requested.
  ld a,(controls)
  and $0C
  jr nz,anim_standing
  ld a,(controls)
  bit 0,a
  jr z,check_look_down
  call reset_idle
  ld a,$14
  jp anim_save
check_look_down:
  bit 1,a
  jr z,anim_idle
  call reset_idle
  ld a,$07
  jp anim_save
anim_standing:
  call reset_idle
  ld a,$06
  jp anim_save
anim_idle:
  ; A fresh standing delay precedes the SMS bored sequence. The original
  ; sequence is 16,15,16,17, not the unrelated frame 18.
  ld a,(idle_timer)
  cp 180
  jr nc,anim_bored
  inc a
  ld (idle_timer),a
  ld a,$06
  jp anim_save
anim_bored:
  ld a,(idle_phase)
  inc a
  and $3F
  ld (idle_phase),a
  cp 16
  jr c,idle_frame_16
  cp 34
  jr c,idle_frame_15
  cp 50
  jr c,idle_frame_16
  ld a,$17
  jp anim_save
idle_frame_15:
  ld a,$15
  jp anim_save
idle_frame_16:
  ld a,$16
  jp anim_save
anim_air:
  call reset_idle
  jr anim_spin
anim_moving:
  call reset_idle
  ld hl,(xvel)
  ld a,(controls)
  bit 3,a
  jr z,check_brake_left
  bit 7,h
  jr nz,anim_brake
check_brake_left:
  bit 2,a
  jr z,anim_speed
  bit 7,h
  jr nz,anim_speed
  jr anim_brake
anim_brake:
  ld a,$13
  jp anim_save
anim_speed:
  ; 0D-10 are the SMS fast-running cycle. Select by speed magnitude.
  bit 7,h
  jr z,anim_abs_ready
  xor a
  sub l
  ld l,a
  ld a,0
  sbc a,h
  ld h,a
anim_abs_ready:
  ld a,h
  cp 2
  jr c,anim_walk
  ld a,(frame_tick)
  rrca
  rrca
  and 3
  add a,$0D
  jp anim_save
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
reset_idle:
  xor a
  ld (idle_timer),a
  ld (idle_phase),a
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
  ; Position short crouch/rolling frames at the feet, without changing the
  ; world position or collision box. Their art occupies only the upper 23/24
  ; rows; the normal standing frame fills all 32 rows. Keep airborne spin
  ; centred at its original position.
  ld a,(camera_y)
  add a,a
  add a,a
  add a,a
  ld c,a
  ld a,(ypos+1)
  sub c
  ld c,a
  ld a,(grounded)
  or a
  jr z,sprite_y_offset_done
  ld a,(frame_id)
  cp $07
  jr c,sprite_y_offset_done
  cp $0D
  jr nc,sprite_y_offset_done
  ld a,c
  add a,8
  ld c,a
  ld a,(frame_id)
  cp $08
  jr z,sprite_extra_pixel
  cp $0A
  jr nz,sprite_y_offset_done
sprite_extra_pixel:
  inc c
sprite_y_offset_done:
  ld a,c
  ld (sprite_draw_y),a
  ; Two 16x16 layers in each 16x16 quadrant: four sprites per scanline.
  ld b,0
sprite_loop:
  ld a,(sprite_draw_y)
  bit 2,b
  jr z,sprite_top
  add a,16
sprite_top:
  dec a
  out ($BE),a
  ld a,(camera_x)
  add a,a
  add a,a
  add a,a
  ld c,a
  ld a,(xpos+1)
  sub c
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
