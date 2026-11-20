; GHZ1 signpost, at the original object coordinates (6432,384). Its visual
; 32x48 background-tile overlay avoids Sonic's four-sprites-per-line limit.
; Collision and spin deceleration are deliberately simplified for now.
signpost_init:
  xor a
  ld (sign_state),a
  ld (sign_timer),a
  ld (sign_frame),a
  ld hl,$600B                 ; character groups 88..111
  call vdp_addr
  ld a,$F7
  out ($BE),a
  out ($BE),a
  out ($BE),a
  xor a
  jp signpost_upload

; A selects one of five source-derived, 192-byte animation frames.
signpost_upload:
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
  ld de,352
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
  ld a,96
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
  ; Four source views, six frames each, repeatedly while spinning.
  ld e,a
  ld d,0
  ld hl,signpost_anim
  ld a,e
  and 31
  ld e,a
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
.db 0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,2,2,2,3,3,3,3,3,3,0,0,0,0,0,0,0,0

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
  ld a,44                   ; (384-32)/8
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
  ld c,88
  ld b,6
signpost_draw_row:
  call vdp_addr
  ld a,c
  out ($BE),a
  inc a
  out ($BE),a
  inc a
  out ($BE),a
  inc a
  out ($BE),a
  inc a
  ld c,a
  ld de,32
  add hl,de
  djnz signpost_draw_row
  ret
