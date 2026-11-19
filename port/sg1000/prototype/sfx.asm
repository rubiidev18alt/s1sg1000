; Lightweight, provisional PSG sound effects. Only tone channel 2 is used;
; music can later use tone 0/1 and noise without being interrupted.
; Pitches follow the original SMS note-period table and SFX note sequences;
; durations/envelopes are approximations, not the original sound driver.
sfx_init:
  xor a
  ld (sfx_ptr),a
  ld (sfx_ptr+1),a
  ld (sfx_timer),a
  ld a,$9F
  out ($7F),a
  ld a,$BF
  out ($7F),a
  ld a,$DF
  out ($7F),a
  ld a,$FF
  out ($7F),a
  ret
sfx_jump:
  ld hl,sfx_jump_data
  jr sfx_start
sfx_ring:
  ld hl,sfx_ring_data
  jr sfx_start
sfx_roll:
  ld hl,sfx_roll_data
  jr sfx_start
sfx_brake:
  ld hl,sfx_brake_data
sfx_start:
  ld (sfx_ptr),hl
  xor a
  ld (sfx_timer),a
  ret

; Each event is duration in frames, 10-bit period (little-endian), and
; attenuation (0..15). Zero duration terminates and mutes channel 2.
sfx_tick:
  ld hl,(sfx_ptr)
  ld a,h
  or l
  ret z
  ld a,(sfx_timer)
  or a
  jr z,sfx_next
  dec a
  ld (sfx_timer),a
  ret nz
sfx_next:
  ld a,(hl)
  inc hl
  or a
  jr z,sfx_end
  ld (sfx_timer),a
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld a,e
  and $0F
  or $C0
  out ($7F),a
  push hl
  ex de,hl
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  srl h
  rr l
  ld a,l
  out ($7F),a
  pop hl
  ld a,(hl)
  inc hl
  and $0F
  or $D0
  out ($7F),a
  ld (sfx_ptr),hl
  ret
sfx_end:
  xor a
  ld (sfx_ptr),a
  ld (sfx_ptr+1),a
  ld (sfx_timer),a
  ld a,$DF
  out ($7F),a
  ret

; The SMS bytecode's pitch sequence, simplified to fixed PSG notes.
sfx_jump_data:
.db 3
.dw 320
.db 3
.db 21
.dw 239
.db 5
.db 0
sfx_ring_data:
.db 4
.dw 84
.db 2
.db 4
.dw 71
.db 3
.db 4
.dw 53
.db 4
.db 0
sfx_roll_data:
.db 12
.dw 56
.db 5
.db 6
.dw 302
.db 6
.db 0
sfx_brake_data:
.db 3
.dw 134
.db 5
.db 3
.dw 119
.db 5
.db 3
.dw 134
.db 6
.db 3
.dw 119
.db 7
.db 0
