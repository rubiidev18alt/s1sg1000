; TMS Graphics I background-ring experiment. Original GHZ ring positions
; are stored as x/y pixel words sorted by x; collect once per level load.
rings_init:
  xor a
  ld (ring_count),a
  ld (ring_redraw),a
  ld a,(menu_selection)
  or a
  jr nz,rings_clear_start
  xor a
  ld (camera_x_hi),a
rings_clear_start:
  xor a
  ld hl,ring_bits
  ld b,14
rings_clear:
  ld (hl),a
  inc hl
  djnz rings_clear
  ld hl,$4100                 ; patterns 32..35: first SMS ring frame
  call vdp_addr
  ld hl,ring_patterns
  ld bc,32
  call vdp_copy
  ld hl,$4140                 ; patterns 40..63: original digits and emblem
  call vdp_addr
  ld hl,ring_hud_patterns
  ld bc,192
  call vdp_copy
  ld hl,$6004                 ; character groups 32..63
  call vdp_addr
  ld a,(menu_selection)
  or a
  ld c,1
  jr z,rings_colour_ready
  ld c,7
rings_colour_ready:
  ld a,c
  or $A0                      ; yellow ring
  out ($BE),a
  ld a,c
  or $F0                      ; white SMS HUD glyphs
  out ($BE),a
  out ($BE),a
  out ($BE),a
  ret

rings_tick:
  ld a,(menu_selection)
  or a
  jr nz,rings_ghz_list
  ld hl,test_rings
  ld (ring_ptr),hl
  xor a
  ld (ring_index),a
  ld b,4
  jr rings_loop
rings_ghz_list:
  ; Bucket by 256 world pixels, beginning one page before the camera so
  ; partially visible rings are included. This avoids scanning all 107 rings.
  ld a,(camera_x)
  ld l,a
  ld a,(camera_x_hi)
  ld h,a
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
  ld (ring_cam_page),a
  or a
  jr z,rings_bucket_ready
  dec a
rings_bucket_ready:
  ld e,a
  ld d,0
  ld hl,ghz_ring_buckets
  add hl,de
  ld a,(hl)
  ld (ring_index),a
  ld e,a
  ld d,0
  ld l,e
  ld h,d
  add hl,hl
  add hl,hl
  ld de,ghz_rings
  add hl,de
  ld (ring_ptr),hl
  ld a,(ring_index)
  ld b,a
  ld a,107
  sub b
  jp z,rings_finished
  ld b,a
rings_loop:
  push bc
  ld hl,(ring_ptr)
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld (ring_x),de
  ld a,(menu_selection)
  or a
  jr z,rings_read_y
  ld a,(ring_cam_page)
  add a,2
  cp d
  jr nc,rings_read_y
  pop bc
  jp rings_finished
rings_read_y:
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld (ring_y),de
  ld (ring_ptr),hl
  call ring_bit_ptr
  ld a,(hl)
  and c
  jp nz,rings_next
  ; The SMS checks Sonic's centre x and y+8 against the two 16px halves
  ; and the containing 32px ring metatile.
  ld a,(xpos+1)
  ld l,a
  ld a,(xpage)
  ld h,a
  ld de,12
  add hl,de
  ld de,(ring_x)
  or a
  sbc hl,de
  jp c,rings_render
  ld a,h
  or a
  jp nz,rings_render
  ld a,l
  cp 16
  jp nc,rings_render
  ld a,(ypos+1)
  ld l,a
  ld a,(ypage)
  ld h,a
  ld de,16                    ; Sonic y+8 minus (ring y-8)
  add hl,de
  ld de,(ring_y)
  or a
  sbc hl,de
  jp c,rings_render
  ld a,h
  or a
  jp nz,rings_render
  ld a,l
  cp 32
  jp nc,rings_render
  call ring_bit_ptr
  ld a,(hl)
  or c
  ld (hl),a
  ld a,(ring_count)
  add a,1
  daa                         ; SMS counter is two-digit BCD
  ld (ring_count),a
  call sfx_ring
  ; Force redraw so the collected background-ring is erased.
  ld a,$FF
  ld (camera_x),a
  ld (camera_y),a
  jp rings_next
rings_render:
  ld a,(ring_redraw)
  or a
  jp z,rings_next
  ; Draw only if the whole 16x16 ring is inside the viewport. Each camera
  ; coordinate is in 8px tiles, so positions remain tile aligned.
  ld a,(camera_x)
  ld l,a
  ld a,(camera_x_hi)
  ld h,a
  add hl,hl
  add hl,hl
  add hl,hl
  ex de,hl
  ld hl,(ring_x)
  or a
  sbc hl,de
  jp c,rings_next
  ld a,h
  or a
  jp nz,rings_next
  ld a,l
  cp 241
  jp nc,rings_next
  srl a
  srl a
  srl a
  ld (ring_sx),a
  ld a,(camera_y)
  ld l,a
  ld h,0
  add hl,hl
  add hl,hl
  add hl,hl
  ex de,hl
  ld hl,(ring_y)
  or a
  sbc hl,de
  jp c,rings_next
  ld a,h
  or a
  jp nz,rings_next
  ld a,l
  cp 177
  jp nc,rings_next
  srl a
  srl a
  srl a
  ld (ring_sy),a
  call ring_draw
rings_next:
  ld a,(ring_index)
  inc a
  ld (ring_index),a
  pop bc
  dec b
  jp nz,rings_loop
rings_finished:
  xor a
  ld (ring_redraw),a
  jp ring_draw_hud

; Return HL -> collected bitset byte, C -> bit for current index.
ring_bit_ptr:
  ld a,(ring_index)
  and 7
  ld e,a
  ld d,0
  ld hl,ring_masks
  add hl,de
  ld c,(hl)
  ld a,(ring_index)
  srl a
  srl a
  srl a
  ld e,a
  ld d,0
  ld hl,ring_bits
  add hl,de
  ret
ring_masks:
.db 1,2,4,8,16,32,64,128

ring_draw:
  ld a,(ring_sy)
  ld l,a
  ld h,0
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  ld a,(ring_sx)
  ld e,a
  ld d,0
  add hl,de
  ld de,$5800
  add hl,de
  push hl
  call vdp_addr
  ld a,32
  out ($BE),a
  inc a
  out ($BE),a
  pop hl
  ld de,32
  add hl,de
  call vdp_addr
  ld a,34
  out ($BE),a
  inc a
  out ($BE),a
  ret

; SMS ring emblem and two 8x16 digits; adapt sprite art to name-table tiles.
ring_draw_hud:
  ld hl,$5802
  call vdp_addr
  ld a,60
  out ($BE),a
  ld a,62
  out ($BE),a
  ld hl,$5822
  call vdp_addr
  ld a,61
  out ($BE),a
  ld a,63
  out ($BE),a
  ld a,(ring_count)
  and $F0
  rrca
  rrca
  rrca
  rrca
  add a,a
  add a,40
  ld b,a
  ld a,(ring_count)
  and $0F
  add a,a
  add a,40
  ld c,a
  ld hl,$5805
  call vdp_addr
  ld a,b
  out ($BE),a
  ld a,c
  out ($BE),a
  ld hl,$5825
  call vdp_addr
  ld a,b
  inc a
  out ($BE),a
  ld a,c
  inc a
  out ($BE),a
  ret
