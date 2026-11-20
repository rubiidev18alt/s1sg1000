; Provisional GHZ1 second test level. Terrain uses SMS floor profiles, sampled
; to 8x8 for the display. Connected terrain has solid undersides; detached
; platforms remain one-way. Collision is still approximate.
ghz_init:
  xor a
  ld (xpos),a
  ld (xpos+1),a
  ld (ypos),a
  ld (grounded),a
  ld (camera_x_hi),a
  ld (ghz_downhill),a
  ld (launch_active),a
  ld a,1
  ld (xpage),a             ; original start x=256
  ld (ypage),a
  ld a,96
  ld (ypos+1),a            ; original start y=352
  ld a,$FF
  ld (camera_x),a
  ld (camera_y),a
  ; Graphics I: green foreground, cyan background for characters 0..7.
  ld hl,$6000
  call vdp_addr
  ld a,$37
  out ($BE),a
  ld a,$07
  out ($BF),a
  ld a,$87
  out ($BF),a
  ; GHZ-only Graphics I tile groups: source-derived grass in two greens,
  ; checker soil/walls in brown. These do not change the collision map.
  ld hl,$4200
  call vdp_addr
  ld hl,ghz_terrain_patterns
  ld bc,8
  call vdp_copy
  ld hl,$4240
  call vdp_addr
  ld hl,ghz_terrain_patterns+8
  ld bc,16
  call vdp_copy
  ld hl,$4280
  call vdp_addr
  ld hl,ghz_terrain_patterns+24
  ld bc,64
  call vdp_copy
  ld hl,$6008
  call vdp_addr
  ld a,$32
  out ($BE),a
  ld a,$A6
  out ($BE),a
  ld a,$F7                ; ramp: white on cyan
  out ($BE),a
  ret

ghz_x_limit:
  call ghz_wall_x
  ; SMS GHZ1 camera right limit is $18C0 = 6336 pixels.
  ; SMS player clamp is camera limit + $F8 - $18 - 1 = 6559.
  ld a,(xpage)
  cp 25
  ret c
  jr nz,ghz_right_edge
  ld a,(xpos+1)
  cp 159
  ret c
ghz_right_edge:
  ld a,25
  ld (xpage),a
  ld hl,$9F00
  ld (xpos),hl
  ld hl,0
  ld (xvel),hl
  ret

; Original profile 22 has full-width left/right sides. Sloped and flat
; connected terrain has a solid underside, while detached platforms are one-way.
; Probe one pixel beyond the leading edge at two heights.
ghz_wall_x:
  ld hl,(xvel)
  ld a,h
  or l
  ret z
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld a,(xvel+1)
  bit 7,a
  jr nz,ghz_wall_probe_left
  ld de,24
  add hl,de
  jr ghz_wall_probe_ready
ghz_wall_probe_left:
  dec hl
ghz_wall_probe_ready:
  ld (ghz_probe_x),hl
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld (ghz_probe_y),hl
  call ghz_collision_at
  cp 22
  jr z,ghz_wall_block
  ld hl,(ghz_probe_y)
  ld de,31
  add hl,de
  ld (ghz_probe_y),hl
  call ghz_collision_at
  cp 22
  ret nz
ghz_wall_block:
  ld hl,(ghz_probe_x)
  ld a,l
  and $E0
  ld l,a
  ld a,(xvel+1)
  bit 7,a
  jr nz,ghz_wall_block_left
  ld de,24
  or a
  sbc hl,de
  jr ghz_wall_store
ghz_wall_block_left:
  ld de,32
  add hl,de
ghz_wall_store:
  ld a,h
  ld (xpage),a
  ld a,l
  ld (xpos+1),a
  xor a
  ld (xpos),a
  ld (xvel),a
  ld (xvel+1),a
  ret

; Read a metatile collision type from pixel coordinates in probe_x/probe_y.
; Returns zero outside the 512-pixel-high layout.
ghz_collision_at:
  call ghz_collision_at_raw
  and $3F
  ret
ghz_collision_at_raw:
  ld hl,(ghz_probe_y)
  ld a,h
  cp 2
  jr c,ghz_probe_y_valid
  xor a
  ret
ghz_probe_y_valid:
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld d,l
  ld hl,(ghz_probe_x)
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld e,l
  jp ghz_collision_raw

; Solid terrain stops upward motion at its bottom. Detached semisolid
; platforms have no ceiling: Sonic can continue through them from below.
ghz_ceiling:
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld (ghz_probe_y),hl
  ld a,l
  and $E0
  ld l,a
  ld de,(ghz_old_feet)
  ex de,hl
  ld bc,32
  or a
  sbc hl,bc             ; old top
  ld a,l
  and $E0
  ld l,a
  or a
  sbc hl,de
  ret z
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld (ghz_probe_x),hl
  call ghz_ceiling_at
  or a
  jr nz,ghz_ceiling_block
  ld hl,(ghz_probe_x)
  ld de,23
  add hl,de
  ld (ghz_probe_x),hl
  call ghz_ceiling_at
  or a
  ret z
ghz_ceiling_block:
  ld hl,(ghz_probe_y)
  ld a,l
  and $E0
  ld l,a
  ld de,32
  add hl,de
  ld a,h
  ld (ypage),a
  ld a,l
  ld (ypos+1),a
  xor a
  ld (ypos),a
  ld (yvel),a
  ld (yvel+1),a
  ld (jump_timer),a
  ret

; Test whether a solid terrain metatile actually occupies its bottom at this
; x. Some slopes extend below their cell; their empty portion is not a ceiling.
ghz_ceiling_at:
  call ghz_collision_at_raw
  bit 7,a
  jr nz,ghz_ceiling_solid
  xor a
  ret
ghz_ceiling_solid:
  and $3F
  ld b,a
  ld a,(ghz_probe_x)
  and 31
  ld c,a
  ld a,b
  call ghz_floor_offset
  cp $80
  jr z,ghz_ceiling_empty
  bit 7,a
  jr nz,ghz_ceiling_occupied
  cp 32
  jr nc,ghz_ceiling_empty
ghz_ceiling_occupied:
  ld a,1
  ret
ghz_ceiling_empty:
  xor a
  ret

ghz_save_old_feet:
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld de,32
  add hl,de
  ld (ghz_old_feet),hl
  ret

ghz_landing:
  ; Check solid ceilings while rising; respawn if falling below the map.
  ld hl,(yvel)
  bit 7,h
  jp nz,ghz_ceiling
  ld a,(ypage)
  cp 2
  jp nc,ghz_respawn
  call ghz_save_current_feet
  xor a
  ld (ghz_sensor_index),a
ghz_scan_sensor:
  ; Look at the current 32px cell and its neighbours, because SMS slope
  ; profiles can point beyond their containing cell.
  ld hl,(ghz_feet)
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld a,l
  dec a
  ld (ghz_row),a
  ld a,3
  ld (ghz_count),a
ghz_collision_loop:
  ld a,(ghz_row)
  cp 16
  jp nc,ghz_next_row
  ld d,a
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld a,(ghz_sensor_index)
  ld e,a
  ld d,0
  push hl
  ld hl,ghz_foot_offsets
  add hl,de
  ld c,(hl)
  ld b,0
  pop hl
  add hl,bc
  ld a,l
  and 31
  ld (ghz_xoffset),a
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld e,l
  ld a,(ghz_row)
  ld d,a
  call ghz_collision_type
  ld b,a
  ld a,(ghz_xoffset)
  ld c,a
  ld a,b
  call ghz_floor_offset
  cp $80
  jp z,ghz_next_row
  ld e,a
  ld d,0
  bit 7,e
  jr z,ghz_offset_positive
  dec d
ghz_offset_positive:
  ld a,(ghz_row)
  ld l,a
  ld h,0
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,de
  ld (ghz_surface),hl
  ld de,(ghz_feet)
  or a
  sbc hl,de               ; surface - current feet
  ld a,(grounded)
  or a
  jr z,ghz_air_check
  ; Grounded: follow a floor at most 8 pixels above or below the feet.
  ld de,8
  add hl,de
  ld a,h
  or a
  jp nz,ghz_next_row
  ld a,l
  cp 17
  jp nc,ghz_next_row
  jr ghz_apply_floor
ghz_air_check:
  ; Current feet must cross the top from above, never from underneath.
  bit 7,h
  jr nz,ghz_surface_reached
  ld a,h
  or l
  jp nz,ghz_next_row
ghz_surface_reached:
  ld hl,(ghz_surface)
  ld de,(ghz_old_feet)
  or a
  sbc hl,de
  jp c,ghz_next_row
ghz_apply_floor:
  xor a
  ld (launch_active),a
  ld hl,(ghz_surface)
  ld de,32
  or a
  sbc hl,de
  push hl
  ld a,(ypos+1)
  ld e,a
  ld a,(ypage)
  ld d,a
  or a
  sbc hl,de
  ld a,0
  jr c,ghz_slope_saved
  ld a,h
  or l
  jr z,ghz_slope_saved
  ld a,(grounded)
  or a
  jr z,ghz_slope_saved
  ld a,1
ghz_slope_saved:
  ld (ghz_downhill),a
  pop hl
  ld a,h
  ld (ypage),a
  ld a,l
  ld (ypos+1),a
  xor a
  ld (ypos),a
  ld (yvel),a
  ld (yvel+1),a
  inc a
  ld (grounded),a
  ret
ghz_next_row:
  ld a,(ghz_row)
  inc a
  ld (ghz_row),a
  ld a,(ghz_count)
  dec a
  ld (ghz_count),a
  jp nz,ghz_collision_loop
  ld a,(ghz_sensor_index)
  inc a
  ld (ghz_sensor_index),a
  cp 3
  jp c,ghz_scan_sensor
  xor a
  ld (grounded),a
  ret

; Centre first; if unsupported, try inset left and right foot sensors.
ghz_foot_offsets:
.db 12,4,19

ghz_save_current_feet:
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld de,32
  add hl,de
  ld (ghz_feet),hl
  ret

ghz_respawn:
  xor a
  ld (xvel),a
  ld (xvel+1),a
  ld (yvel),a
  ld (yvel+1),a
  ld (rolling),a
  call ghz_init
  jp rings_init

; Tile-aligned camera with a 16-bit horizontal coordinate, necessary for
; the original 1024-tile-wide layout. The right camera limit uses the SMS
; level header ($18C0 pixels, 792 tiles), rather than the unused map tail.
ghz_camera:
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,CAMERA_FOLLOW_X
  or a
  sbc hl,de
  jr nc,ghz_cam_x_positive
  ld hl,0
ghz_cam_x_positive:
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld de,792
  or a
  sbc hl,de
  add hl,de
  jr c,ghz_cam_x_ready
  ld hl,792
ghz_cam_x_ready:
  ; During a ramp launch the SMS camera can only catch up by 8px/frame.
  ld a,(launch_active)
  or a
  jr z,ghz_cam_launch_done
  ld a,(camera_y)
  cp $FF
  jr z,ghz_cam_launch_done ; forced redraw/initialisation, not a position
  ld a,(camera_x)
  ld c,a
  ld a,(camera_x_hi)
  ld b,a
  push hl
  or a
  sbc hl,bc
  jr c,ghz_cam_launch_restore
  ld a,h
  or a
  jr nz,ghz_cam_launch_cap
  ld a,l
  cp 2
  jr c,ghz_cam_launch_restore
ghz_cam_launch_cap:
  pop hl
  ld l,c
  ld h,b
  inc hl
  jr ghz_cam_launch_done
ghz_cam_launch_restore:
  pop hl
ghz_cam_launch_done:
  push hl
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld de,72
  or a
  sbc hl,de
  jr nc,ghz_cam_y_positive
  ld hl,0
ghz_cam_y_positive:
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld a,h
  or a
  ld a,l
  jr nz,ghz_cam_y_max
  cp 41
  jr c,ghz_cam_y_ready
ghz_cam_y_max:
  ld a,40
ghz_cam_y_ready:
  ld b,a
  ld a,(launch_active)
  or a
  jr z,ghz_cam_y_launch_done
  ld a,(camera_y)
  cp $FF
  jr z,ghz_cam_y_launch_done
  cp b
  jr z,ghz_cam_y_launch_done
  jr c,ghz_cam_y_launch_down
  dec a
  jr ghz_cam_y_launch_store
ghz_cam_y_launch_down:
  inc a
ghz_cam_y_launch_store:
  ld b,a
ghz_cam_y_launch_done:
  pop hl
  ld a,(camera_y)
  cp b
  jr nz,ghz_camera_changed
  ld a,(camera_x)
  cp l
  jr nz,ghz_camera_changed
  ld a,(camera_x_hi)
  cp h
  ret z
ghz_camera_changed:
  push hl
  ld a,1
  ld (ring_redraw),a
  pop hl
  ld a,l
  ld (camera_x),a
  ld a,h
  ld (camera_x_hi),a
  ld a,b
  ld (camera_y),a
  jp ghz_draw_map

; Each row uses type in the top two bits, with a five-bit short count;
; bit 5 indicates a long count with its low byte in the following byte.
; Skip camera_x cells and stream just 32 cells per row to the name table.
; This retains exactly the previous 8-pixel silhouette without repeated
; metatile lookups or per-cell multiplications.
ghz_draw_map:
  ld hl,$5800
  call vdp_addr
  xor a
  ld (ghz_screen_row),a
ghz_draw_row:
  ld a,(camera_y)
  ld b,a
  ld a,(ghz_screen_row)
  add a,b
  ld l,a
  ld h,0
  add hl,hl
  ld de,ghz_visual_rows
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld hl,ghz_visual_data
  add hl,de
  ld a,(camera_x)
  ld e,a
  ld a,(camera_x_hi)
  ld d,a
ghz_skip_run:
  call ghz_read_run
  push hl                ; pointer to next run
  ex de,hl               ; skip count
  or a
  sbc hl,bc
  jr c,ghz_found_run
  ex de,hl               ; remaining skip count
  pop hl
  jr ghz_skip_run
ghz_found_run:
  ; BC = length minus skipped tiles (negate the negative subtraction).
  xor a
  sub l
  ld c,a
  ld a,0
  sbc a,h
  ld b,a
  pop hl                 ; next run
  ld e,32                ; screen cells left
ghz_output_run:
  ld a,(ghz_draw_value)
  ld d,a
  cp 72
  jr nz,ghz_output_type_ready
  ; The SMS alternates its two soil tiles in world space, not screen space.
  ; E is remaining screen columns; 32-E has the same low bit as E.
  ld a,(camera_x)
  xor e
  ld d,a
  ld a,(camera_y)
  xor d
  ld d,a
  ld a,(ghz_screen_row)
  xor d
  and 1
  add a,72
  ld d,a
ghz_output_type_ready:
  ld a,b
  or a
  jr nz,ghz_output_last_run
  ld a,c
  cp e
  jr nc,ghz_output_last_run
  ld a,e
  sub c
  ld e,a
  ld b,c
ghz_output_partial:
  ld a,d
  cp 72
  jr nc,ghz_partial_checker
-:
  ld a,d
  out ($BE),a
  djnz -
  jr ghz_partial_done
ghz_partial_checker:
  ld a,d
  out ($BE),a
  xor 1
  ld d,a
  djnz ghz_partial_checker
ghz_partial_done:
  call ghz_read_run
  jr ghz_output_run
ghz_output_last_run:
  ld b,e
ghz_output_final:
  ld a,d
  cp 72
  jr nc,ghz_final_checker
-:
  ld a,d
  out ($BE),a
  djnz -
  jr ghz_row_done
ghz_final_checker:
  ld a,d
  out ($BE),a
  xor 1
  ld d,a
  djnz ghz_final_checker
ghz_row_done:
  ld a,(ghz_screen_row)
  inc a
  ld (ghz_screen_row),a
  cp 24
  jp c,ghz_draw_row
  ret

; HL points to packed run, returns BC=count and preserves DE.
ghz_read_run:
  ld a,(hl)
  inc hl
  push af
  ld b,0
  bit 5,a
  jr z,ghz_run_short
  and 31
  ld b,a
  ld c,(hl)
  inc hl
  jr ghz_run_count_ready
ghz_run_short:
  and 31
  ld c,a
ghz_run_count_ready:
  pop af
  rlca
  rlca
  and 3
  jr z,ghz_run_value_ready
  dec a
  jr z,ghz_run_soil
  dec a
  ld a,64                 ; two-green grass surface
  jr z,ghz_run_value_ready
  ld a,(hl)               ; tile index 0..7 follows each one-cell ramp run
  inc hl
  add a,80
  jr ghz_run_value_ready
ghz_run_soil:
  ld a,72                 ; checker soil and walls
ghz_run_value_ready:
  ld (ghz_draw_value),a
  ret

; SMS GHZ1 ramp special 02. Require the requested up+right input and
; positive speed >3px/frame; original launch vertical velocity is -2*xvel.
ghz_try_launch:
  ld a,(menu_selection)
  or a
  ret z
  ld a,(grounded)
  or a
  ret z
  ld a,(controls)
  and $09
  cp $09
  ret nz
  ld hl,(xvel)
  ld a,h
  cp 3
  ret c
  ret m
  jr nz,ghz_launch_speed_ok
  ld a,l
  or a
  ret z
ghz_launch_speed_ok:
  ld a,(ypage)
  cp (GHZ_RAMP_Y-32)>>8
  ret nz
  ld a,(ypos+1)
  cp (GHZ_RAMP_Y-32)&255
  ret c
  cp (GHZ_RAMP_Y+8)&255
  ret nc
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,12
  add hl,de
  ld de,GHZ_RAMP_X+18
  or a
  sbc hl,de
  ret c
  ld de,18
  or a
  sbc hl,de
  ret nc
  ld hl,(xvel)
  ld a,h
  cp 8
  ld hl,$F000
  jr nc,ghz_launch_y_ready
  ld hl,(xvel)
  add hl,hl
  xor a
  sub l
  ld l,a
  ld a,0
  sbc a,h
  ld h,a
ghz_launch_y_ready:
  ld (yvel),hl
  xor a
  ld (grounded),a
  ld (jump_timer),a
  inc a
  ld (launch_active),a
  jp sfx_launch
