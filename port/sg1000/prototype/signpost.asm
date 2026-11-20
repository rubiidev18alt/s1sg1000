; GHZ1 signpost: original object x=6432; ground at this position is y=432.
; The 32x48 converted art ends at the floor. Background tiles avoid Sonic's
; four-sprites-per-line limit; transparent tile gaps are not overlaid.
signpost_init:
  xor a
  ld (sign_state),a
  ld (sign_timer),a
  ld (sign_frame),a
  ld hl,$600B                 ; character groups 88..111
  call vdp_addr
  ld a,$E7                 ; grey border and pole on sky
  out ($BE),a
  ld a,$A7                 ; yellow face edges on sky
  out ($BE),a
  ld a,$8A                 ; red/black detail on yellow face
  out ($BE),a
  xor a
  jp signpost_upload

; A selects one of five source-derived, 192-byte animation frames.
signpost_upload:
  ; The side-on frame is grey against sky, not a filled yellow rectangle.
  push af
  ld hl,$600D
  call vdp_addr
  pop af
  cp 2
  ld b,a
  ld a,$8A
  jr nz,signpost_face_colour
  ld a,$E7
signpost_face_colour:
  out ($BE),a
  ld a,b
  ld l,a
  ld h,0
  ld e,l
  ld d,h
  add hl,hl
  add hl,de                 ; frame * 3
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl                 ; frame * 192
  ld de,signpost_patterns
  add hl,de
  push hl
  ld hl,$42C0               ; character 88
  call vdp_addr
  pop hl
  ld bc,192
  jp vdp_copy

signpost_tick:
  ld a,(menu_selection)
  or a
  ret z
  ld a,(sign_state)
  or a
  jr nz,signpost_active
  ld a,(debug_mode)
  or a
  ret nz
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,12
  add hl,de
  ld de,6412
  or a
  sbc hl,de
  ret c
  ld a,h
  or a
  ret nz
  ld a,l
  cp 41
  ret nc
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld de,16
  add hl,de
  ld de,384                ; align touch zone with grounded sign
  or a
  sbc hl,de
  ret c
  ld a,h
  or a
  ret nz
  ld a,l
  cp 65
  ret nc
  ld a,1
  ld (sign_state),a
  ; Approximate the original speed-sensitive spin: a faster hit spins
  ; longer. The SMS uses fixed-point angular velocity and deceleration.
  ld a,(xvel+1)
  bit 7,a
  jr z,sign_speed_positive
  neg
sign_speed_positive:
  cp 4
  jr c,sign_speed_capped
  ld a,3
sign_speed_capped:
  add a,a
  add a,a
  add a,a
  add a,a
  add a,64
  ld (sign_timer),a
  jp sfx_sign_spin
signpost_active:
  cp 1
  jp nz,signpost_clear_wait
  ld a,(sign_timer)
  dec a
  ld (sign_timer),a
  jr z,signpost_settle
  and 7
  call z,sfx_sign_spin       ; repeat original spinning motif until it settles
  ld a,(sign_timer)
  ; Spin faster at first, then visibly slow in the final half-second.
  cp 32
  jr c,signpost_slow_spin
  srl a
  srl a
  jr signpost_spin_frame
signpost_slow_spin:
  srl a
  srl a
  srl a
signpost_spin_frame:
  and 3
  ld e,a
  ld d,0
  ld hl,signpost_anim
  add hl,de
  ld a,(hl)
  ld b,a
  ld a,(sign_frame)
  cp b
  ret z
  ld a,b
  ld (sign_frame),a
  jp signpost_upload
signpost_settle:
  ld a,2
  ld (sign_state),a
  xor a
  ld (debug_mode),a
  ld (launch_active),a
  ld (rolling),a
  ld a,4
  ld (sign_frame),a
  call signpost_upload
  call sfx_sign_land
  ld hl,328                 ; duration of the original clear tune arrangement
  ld (clear_timer),hl
  jp music_clear_start
signpost_clear_wait:
  cp 2
  ret nz
  ld hl,(clear_timer)
  dec hl
  ld (clear_timer),hl
  ld a,h
  or l
  ret nz
  ld a,3
  ld (sign_state),a
  jp result_init
signpost_anim:
.db 0,1,2,3

; Draw on full terrain redraw only; animated frames replace patterns in place.
signpost_draw:
  ld a,(menu_selection)
  or a
  ret z
  ld a,(ring_redraw)
  or a
  ret z
  ld a,(camera_x)
  ld e,a
  ld a,(camera_x_hi)
  ld d,a
  ld hl,802                 ; (6432-16)/8
  or a
  sbc hl,de
  ret c
  ld a,h
  or a
  ret nz
  ld a,l
  cp 29
  ret nc
  ld c,a
  ld a,48                   ; (432-48)/8: pole rests on ground
  ld b,a
  ld a,(camera_y)
  ld e,a
  ld a,b
  sub e
  ret c
  cp 19
  ret nc
  ld l,a
  ld h,0
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  ld e,c
  ld d,0
  add hl,de
  ld de,$5800
  add hl,de
  ; Write only occupied cells; group characters by material rather than
  ; screen row so each group of eight can have its own Graphics I colours.
  ld de,32
  add hl,de
  ld c,0
signpost_draw_board_row:
  call vdp_addr
  ld b,4
  ld a,c
  push hl
  ld l,a
  ld h,0
  ld de,signpost_board_tiles
  add hl,de
signpost_draw_board_tile:
  ld a,(hl)
  out ($BE),a
  inc hl
  djnz signpost_draw_board_tile
  pop hl
  ld de,32
  add hl,de
  ld a,c
  add a,4
  ld c,a
  cp 12
  jr nz,signpost_draw_board_row
  ; Only the middle two columns of the pole contain pixels.
  inc hl
  ld c,90
  ld b,2
signpost_draw_pole:
  call vdp_addr
  ld a,c
  out ($BE),a
  inc a
  out ($BE),a
  inc a
  ld c,a
  ld de,32
  add hl,de
  djnz signpost_draw_pole
  ret
signpost_board_tiles:
.db 88,104,105,89
.db 96,106,107,97
.db 98,108,109,99
