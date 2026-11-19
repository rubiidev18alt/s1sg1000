; SG-1000 Sonic movement sandbox, WLA-DX. All motion values are 8.8 fixed point.
; Keep Sonic 16 pixels further left on screen to show more terrain ahead.
.DEFINE CAMERA_FOLLOW_X 88
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
idle_timer_hi db
menu_selection db
anim_mode db
anim_phase db
anim_subframe db
camera_x_hi db
ghz_old_feet dw
ghz_feet dw
ghz_surface dw
ghz_row db
ghz_count db
ghz_xoffset db
ghz_render_y db
ghz_render_x dw
ghz_screen_row db
ghz_screen_col db
ghz_last_row db
test_draw_row db
ghz_buffer dsb 9
ghz_probe_x dw
ghz_probe_y dw
ghz_sensor_index db
debug_mode db
ring_count db
ring_bits dsb 14
ring_ptr dw
ring_index db
ring_x dw
ring_y dw
ring_sx db
ring_sy db
ring_redraw db
ring_cam_page db
sfx_ptr dw
sfx_timer db
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
  call sfx_init
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
  ld (idle_timer_hi),a
  ld (idle_phase),a
  ld (menu_selection),a
  ld (anim_mode),a
  ld (anim_phase),a
  ld (anim_subframe),a
  ld (debug_mode),a
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
  out ($BE),a              ; characters 16-23
  ; Upload the original SMS world-map glyphs, reduced to white pixels.
  ld hl,$4040             ; character 8
  call vdp_addr
  ld hl,menu_font_patterns
  ld bc,104
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
.IFDEF GHZ_PROBE
  jp ghz_probe
.ENDIF
  call zone_menu
  ld a,(menu_selection)
  or a
  call nz,ghz_init
  call rings_init
  call update_camera
  call rings_tick
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
  ld b,a
  ld a,(menu_selection)
  or a
  jr nz,ghz_input
  ; In TEST, button 1 + button 2 retains the animation viewer. Button 2
  ; alone toggles free movement on its rising edge.
  ld a,b
  and $30
  cp $30
  jr z,preview_frame
  ld a,(previous_controls)
  cpl
  and b
  bit 5,a
  call nz,debug_toggle
  ld a,(debug_mode)
  or a
  jr z,normal_frame
  call debug_move
  jr frame_draw
ghz_input:
  ld a,b
  bit 5,a
  jr nz,preview_frame
normal_frame:
  call physics_x
  call physics_y
  call animate
  jr frame_draw
preview_frame:
  call animation_viewer
frame_draw:
  call update_camera
  call rings_tick
  call sfx_tick
  call draw_sonic
  ld a,(controls)
  ld (previous_controls),a
  jr main_loop

; Button 2 changes modes once per press. Clear momentum and transient
; actions both ways, so normal gravity resumes safely on exit.
debug_toggle:
  ld a,(debug_mode)
  xor 1
  ld (debug_mode),a
  xor a
  ld (xvel),a
  ld (xvel+1),a
  ld (yvel),a
  ld (yvel+1),a
  ld (jump_timer),a
  ld (jump_latch),a
  ld (rolling),a
  ld (grounded),a
  ld (idle_timer),a
  ld (idle_timer_hi),a
  ld (idle_phase),a
  ld a,6
  ld (frame_id),a
  ret

; TEST debug flight: 4 pixels per frame, including diagonals. Positions are
; clamped to the existing course dimensions, but terrain collision is ignored.
debug_move:
  ld a,6
  ld (frame_id),a
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld a,(controls)
  bit 2,a
  jr z,debug_right
  bit 3,a
  jr nz,debug_x_store
  ld de,4
  or a
  sbc hl,de
  jr nc,debug_face_left
  ld hl,0
debug_face_left:
  ld a,1
  ld (facing),a
  jr debug_x_store
debug_right:
  bit 3,a
  jr z,debug_x_store
  ld de,4
  add hl,de
  ld de,744
  or a
  sbc hl,de
  add hl,de
  jr c,debug_face_right
  ld hl,744
debug_face_right:
  xor a
  ld (facing),a
debug_x_store:
  ld a,h
  ld (xpage),a
  ld a,l
  ld (xpos+1),a
  xor a
  ld (xpos),a
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld a,(controls)
  bit 0,a
  jr z,debug_down
  bit 1,a
  jr nz,debug_y_store
  ld de,4
  or a
  sbc hl,de
  jr nc,debug_y_store
  ld hl,0
  jr debug_y_store
debug_down:
  bit 1,a
  jr z,debug_y_store
  ld de,4
  add hl,de
  ld de,352
  or a
  sbc hl,de
  add hl,de
  jr c,debug_y_store
  ld hl,352
debug_y_store:
  ld a,h
  ld (ypage),a
  ld a,l
  ld (ypos+1),a
  xor a
  ld (ypos),a
  ret

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

; TEST is initially selected; button 2 toggles selection. Button 1 enters
; the selected level. Require release before and after confirmation to avoid jumping.
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
  ld hl,$59CD             ; row 14, column 13
  call vdp_addr
  ld hl,menu_ghz1
  ld bc,6
  call vdp_copy
  ; Do not enable display until every VDP register and menu tile is ready.
  ld a,$C2
  out ($BF),a
  ld a,$81
  out ($BF),a
menu_wait_initial_release:
  call menu_poll
  and $30
  jr nz,menu_wait_initial_release
  xor a
  ld (previous_controls),a
menu_wait_input:
  call menu_poll
  ld b,a
  ld a,(previous_controls)
  cpl
  and b                   ; rising button edges only
  ld c,a
  ld a,b
  ld (previous_controls),a
  bit 5,c
  call nz,menu_toggle
  bit 4,c
  jr z,menu_wait_input
menu_wait_release:
  call menu_poll
  and $30
  jr nz,menu_wait_release
  xor a
  ld (previous_controls),a
  ret
menu_toggle:
  ld a,(menu_selection)
  xor 1
  ld (menu_selection),a
  ld hl,$598D
  call vdp_addr
  ld a,(menu_selection)
  or a
  ld a,0
  jr nz,menu_write_test_arrow
  ld a,2
menu_write_test_arrow:
  out ($BE),a
  ld hl,$59CD
  call vdp_addr
  ld a,(menu_selection)
  or a
  ld a,0
  jr z,menu_write_ghz_arrow
  ld a,2
menu_write_ghz_arrow:
  out ($BE),a
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
menu_ghz1:
.db 0,0,16,17,8,18               ;   GHZ1
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
  ; The SMS permits rolling at any nonzero speed. At rest down remains
  ; a crouch rather than creating a stationary roll.
  ld hl,(xvel)
  ld a,h
  or l
  jp z,normal_movement
enter_roll:
  ld a,1
  ld (rolling),a
  call sfx_roll
roll_physics:
  ; On the SMS (01:535B-53A4), pressing opposite with down released
  ; exits the grounded roll and applies normal braking. Same-direction input
  ; and horizontal input while down is held do not accelerate the ground roll.
  ld a,(controls)
  bit 1,a
  jr nz,roll_friction
  bit 2,a
  jr z,roll_check_right
  ld hl,(xvel)
  bit 7,h
  jr nz,roll_friction
  xor a
  ld (rolling),a
  jp move_left
roll_check_right:
  bit 3,a
  jr z,roll_friction
  ld hl,(xvel)
  bit 7,h
  jr z,roll_friction
  xor a
  ld (rolling),a
  jp move_right
roll_friction:
  ; SMS flat roll drag is $0004 per frame (01:53A7), not $0010.
  ; This stepped test course retains its previous downhill exemption: the
  ; original slope collision/acceleration system is not yet ported.
  call rolling_downhill
  or a
  jr nz,roll_maintain_speed
  ld hl,(xvel)
  bit 7,h
  jr nz,roll_slow_left
  ld de,$0004
  or a
  sbc hl,de
  jr c,roll_stop
  ld a,h
  or l
  jr z,roll_stop
  jp save_vx
roll_slow_left:
  ld de,$0004
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
  ld a,(menu_selection)
  or a
  jp nz,ghz_x_limit
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
  ld a,(menu_selection)
  or a
  call nz,ghz_save_old_feet
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
  ld a,(rolling)
  or a
  jr z,jump_not_rolling
  ld a,(xvel)
  and $F8
  ld (xvel),a
jump_not_rolling:
  xor a
  ld (rolling),a
  ld (grounded),a
  ld a,16
  ld (jump_timer),a
  call sfx_jump
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
  jp nz,grounded_follow_dispatch
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
  ld a,(menu_selection)
  or a
  jp nz,ghz_landing
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
grounded_follow_dispatch:
  ld a,(menu_selection)
  or a
  jp nz,ghz_landing
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
  ld a,(menu_selection)
  or a
  jp nz,not_downhill
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

.IFDEF GHZ_PROBE
; Emulator-only test harness. Input row/column/x offset at C030-C032,
; result type and floor offset at C033-C034.
ghz_probe:
  ld a,($C030)
  ld d,a
  ld a,($C031)
  ld e,a
  call ghz_collision_type
  ld ($C033),a
  ld b,a
  ld a,($C032)
  ld c,a
  ld a,b
  call ghz_floor_offset
  ld ($C034),a
  jp ghz_probe
.ENDIF

; GHZ1 collision building blocks; TEST keeps its original physics.
; Input D=metatile row 0..15, E=metatile column 0..255.
; Return A=original collision profile ID, clobber BC/DE/HL.
ghz_collision_type:
  call ghz_collision_raw
  and $3F
  ret
ghz_collision_raw:
  ld a,d
  cp 16
  jr c,ghz_row_valid
  xor a
  ret
ghz_row_valid:
  add a,a
  ld l,a
  ld h,0
  ld bc,ghz_collision_rows
  add hl,bc
  ld c,(hl)
  inc hl
  ld b,(hl)
  ld hl,ghz_collision_row_data
  add hl,bc
  ld a,e
ghz_find_run:
  ld b,(hl)              ; count 0 encodes the entire 256-column row
  inc hl
  ld c,(hl)              ; physics profile
  inc hl
  ld d,a
  ld a,b
  or a
  jr z,ghz_run_found
  ld a,d
  sub b
  jr nc,ghz_find_run
ghz_run_found:
  ld a,c
  ret

; Input A=profile 0..22, C=world x within metatile 0..31.
; Return A=signed surface offset relative to metatile top; $80 = none.
; Offsets may be negative or greater than 31, as in the SMS tables.
; Clobbers BC/DE/HL.
ghz_floor_offset:
  cp 23
  jr c,ghz_profile_valid
  ld a,$80
  ret
ghz_profile_valid:
  ld l,a
  ld h,0
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  ld a,c
  and 31
  ld e,a
  ld d,0
  add hl,de
  ld de,ghz_floor_profiles
  add hl,de
  ld a,(hl)
  ret

; Camera coordinates are in 8-pixel tiles. The 9918 has no fine-scroll
; register; redraw the name table only when a tile boundary is crossed.
update_camera:
  ld a,(menu_selection)
  or a
  jp nz,ghz_camera
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,CAMERA_FOLLOW_X
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
  ld a,1
  ld (ring_redraw),a
  ld a,c
  ld (camera_x),a
  ld a,b
  ld (camera_y),a
  ; One pointer per row; identical test-course rows share ROM storage.
  ld l,b
  ld h,0
  add hl,hl
  ld de,ground_rows
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld hl,ground_map
  add hl,de
  ld e,c
  ld d,0
  add hl,de
  push hl
  ld hl,$5800
  call vdp_addr
  pop hl
  ld b,24
  ld a,(camera_y)
  ld (test_draw_row),a
camera_row:
  ld c,32
camera_col:
  ld a,(hl)
  out ($BE),a
  inc hl
  dec c
  jr nz,camera_col
  ld a,(test_draw_row)
  inc a
  ld (test_draw_row),a
  ld l,a
  ld h,0
  add hl,hl
  ld de,ground_rows
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld hl,ground_map
  add hl,de
  ld a,(camera_x)
  ld e,a
  ld d,0
  add hl,de
  djnz camera_row
  ret

animate:
  ld a,(frame_tick)
  inc a
  ld (frame_tick),a
  ld a,(grounded)
  or a
  jp z,anim_air
  ld a,(rolling)
  or a
  jr z,anim_not_rolling
  call reset_idle
  jp anim_roll
anim_not_rolling:
  ld hl,(xvel)
  ld a,h
  or l
  jp nz,anim_moving
  ; Looking is allowed only when standing still, with no movement requested.
  ld a,(controls)
  and $0C
  jr nz,anim_standing
  ld a,(controls)
  bit 0,a
  jr z,check_look_down
  call reset_idle
  ld (anim_mode),a
  ld a,$14
  jp anim_save
check_look_down:
  bit 1,a
  jr z,anim_idle
  call reset_idle
  ld (anim_mode),a
  ld a,$07
  jp anim_save
anim_standing:
  xor a
  ld (anim_mode),a
  call reset_idle
  ld a,$06
  jp anim_save
anim_idle:
  xor a
  ld (anim_mode),a
  ; SMS bored timer (01:4A55/4A6A) begins after $0168 idle frames.
  ld a,(idle_timer_hi)
  or a
  jr z,idle_increment
  ld a,(idle_timer)
  cp $68
  jr nc,anim_bored
idle_increment:
  ld a,(idle_timer)
  inc a
  ld (idle_timer),a
  jr nz,idle_check_ready
  ld a,(idle_timer_hi)
  inc a
  ld (idle_timer_hi),a
idle_check_ready:
  ld a,(idle_timer_hi)
  or a
  jr z,anim_waiting
  ld a,(idle_timer)
  cp $68
  jr nc,anim_bored
anim_waiting:
  ld a,$06
  jp anim_save
anim_bored:
  ; SMS table 01:5A6B: 16 for 16 ticks, 15 for 18, 16 for 16,
  ; 17 for 16; its FF,22 loop repeats from offset $22 (decimal 34).
  ld a,(idle_phase)
  ld b,a
  inc a
  cp 66
  jr c,idle_phase_ready
  ld a,34
idle_phase_ready:
  ld (idle_phase),a
  ld a,b
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
  jp anim_air_spin
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
  ; At speeds below 1 px/frame the SMS turns instead of skidding.
  bit 7,h
  jr z,brake_was_positive
  ld a,h
  cp $FF
  jr nz,brake_face_left
  ld a,l
  or a
  jp nz,anim_speed
brake_face_left:
  ld a,1
  ld (facing),a
  jr brake_animation
brake_was_positive:
  ld a,h
  or a
  jp z,anim_speed
  xor a
  ld (facing),a
brake_animation:
  ld a,(anim_mode)
  cp 5
  call nz,sfx_brake
  ; The SMS braking table alternates 13 and 25 at eight ticks per frame.
  ld a,5
  call anim_select_mode
  ld a,(anim_phase)
  inc a
  and $0F
  ld (anim_phase),a
  bit 3,a
  ld a,$13
  jp z,anim_save
  ld a,$25
  jp anim_save
anim_speed:
  ; Normal speed cap selects the SMS run cycle 0D-10; below it the walk
  ; cycle uses a velocity-dependent 48-step phase (01:4D8D-4DC7).
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
  cp 3
  jr c,anim_walk
  ld a,3
  call anim_select_mode
  ld a,(anim_phase)
  inc a
  and $0F
  ld (anim_phase),a
  rrca
  rrca
  and 3
  add a,$0D
  jp anim_save
anim_walk:
  ld a,1
  call anim_select_mode
  ld d,1
  ld c,48
  call anim_advance_speed
  srl a
  srl a
  srl a
  jp anim_save
anim_roll:
  ld a,2
  call anim_select_mode
  ld hl,(xvel)
  bit 7,h
  jr z,roll_anim_abs_ready
  xor a
  sub l
  ld l,a
  ld a,0
  sbc a,h
  ld h,a
roll_anim_abs_ready:
  ld d,6
  ld c,80
  call anim_advance_speed
  srl a
  srl a
  srl a
  srl a
  or a
  jr nz,roll_anim_nonzero
  ld a,$0C
  jp anim_save
roll_anim_nonzero:
  add a,$07
  jp anim_save
anim_air_spin:
  ; Airborne jump animation uses all five frames 08-0C, four ticks each.
  ld a,4
  call anim_select_mode
  ld a,(anim_phase)
  inc a
  cp 20
  jr c,air_phase_ready
  xor a
air_phase_ready:
  ld (anim_phase),a
  srl a
  srl a
  add a,$08
anim_save:
  ld (frame_id),a
  ret

; Reset the frame phase when the motion animation changes.
; Preserves HL, used for speed in the walking case.
anim_select_mode:
  ld b,a
  ld a,(anim_mode)
  cp b
  ret z
  ld a,b
  ld (anim_mode),a
  xor a
  ld (anim_phase),a
  ld (anim_subframe),a
  ret

; HL=absolute velocity, D=base step, C=table length. Return previous phase.
; The SMS adds (absolute velocity / 2) in 8.8 fixed point plus the base step.
anim_advance_speed:
  srl h
  rr l
  ld a,(anim_subframe)
  add a,l
  ld (anim_subframe),a
  ld a,h
  adc a,d
  ld e,a
  ld a,(anim_phase)
  push af
  add a,e
  cp c
  jr c,anim_phase_in_range
  sub c
anim_phase_in_range:
  ld (anim_phase),a
  pop af
  ret

reset_idle:
  xor a
  ld (idle_timer),a
  ld (idle_timer_hi),a
  ld (idle_phase),a
  ret

; In TEST hold buttons 1+2; in GHZ1 hold button 2. Tap left/right to
; inspect frames, including actions the prototype does not implement yet.
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


.INCLUDE "port/sg1000/prototype/ghz_level.asm"
.INCLUDE "port/sg1000/prototype/rings.asm"
.INCLUDE "port/sg1000/prototype/sfx.asm"

; Graphics I, 16K VRAM, display disabled until menu setup completes.
vdpregs:
.db $00,$82,$06,$80,$00,$36,$07,$01
heights:
.INCBIN "build/sg1000/prototype/heights.bin"
ground_rows:
.INCBIN "build/sg1000/prototype/ground_rows.bin"
ground_map:
.INCBIN "build/sg1000/prototype/ground.bin"
frame_ptrs:
.INCLUDE "build/sg1000/prototype/sonic_frame_ptrs.inc"
frame_data:
.INCBIN "build/sg1000/prototype/sonic_frames.bin"
; Compact original GHZ1 physics data. Map rows use count/type pairs.
ghz_collision_rows:
.INCBIN "build/sg1000/prototype/ghz_collision_rows.bin" SKIP 0 READ 32
ghz_collision_row_data:
.INCBIN "build/sg1000/prototype/ghz_collision_rows.bin" SKIP 32
ghz_floor_profiles:
.INCBIN "build/sg1000/prototype/ghz_floor_profiles.bin"
ghz_visual_rows:
.INCBIN "build/sg1000/prototype/ghz_visual_rows.bin" SKIP 0 READ 128
ghz_visual_data:
.INCBIN "build/sg1000/prototype/ghz_visual_rows.bin" SKIP 128


ring_patterns:
.INCBIN "build/sg1000/prototype/ring_patterns.bin"
ring_hud_patterns:
.INCBIN "build/sg1000/prototype/ring_hud_patterns.bin"
test_rings:
.INCBIN "build/sg1000/prototype/test_rings.bin"
ghz_rings:
.INCBIN "build/sg1000/prototype/ghz_rings.bin"
ghz_ring_buckets:
.INCBIN "build/sg1000/prototype/ghz_ring_buckets.bin"
