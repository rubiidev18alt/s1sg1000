; Provisional GHZ1 second test level. Terrain uses SMS floor profiles, sampled
; to 8x8 for the display. Collision is top-only, not full SMS wall physics.
ghz_init:
  xor a
  ld (xpos),a
  ld (xpos+1),a
  ld (ypos),a
  ld (grounded),a
  ld (camera_x_hi),a
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
  ret

ghz_x_limit:
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
  ; Do not land while moving upward. If Sonic falls below the map, restart.
  ld hl,(yvel)
  bit 7,h
  ret nz
  ld a,(ypage)
  cp 2
  jp nc,ghz_respawn
  call ghz_save_current_feet
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
  ld bc,12
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
  ld hl,(ghz_surface)
  ld de,32
  or a
  sbc hl,de
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
  xor a
  ld (grounded),a
  ret

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
  jp ghz_init

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
  ld a,l
  ld (camera_x),a
  ld a,h
  ld (camera_x_hi),a
  ld a,b
  ld (camera_y),a
  jp ghz_draw_map

; Each source row is RLE-compressed as (16-bit count, tile value) runs.
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
  ld c,(hl)
  inc hl
  ld b,(hl)
  inc hl
  push hl                ; pointer to run value
  ex de,hl               ; skip count
  or a
  sbc hl,bc
  jr c,ghz_found_run
  ex de,hl               ; remaining skip count
  pop hl
  inc hl                 ; next run
  jr ghz_skip_run
ghz_found_run:
  ; BC = length minus skipped tiles (negate the negative subtraction).
  xor a
  sub l
  ld c,a
  ld a,0
  sbc a,h
  ld b,a
  pop hl                 ; run value
  ld e,32                ; screen cells left
ghz_output_run:
  ld d,(hl)
  inc hl
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
  out ($BE),a
  djnz ghz_output_partial
  ld c,(hl)
  inc hl
  ld b,(hl)
  inc hl
  jr ghz_output_run
ghz_output_last_run:
  ld b,e
ghz_output_final:
  ld a,d
  out ($BE),a
  djnz ghz_output_final
  ld a,(ghz_screen_row)
  inc a
  ld (ghz_screen_row),a
  cp 24
  jp c,ghz_draw_row
  ret
