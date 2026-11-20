; SMS-inspired PSG sound effects. Only tone channel 2 is used;
; music can later use tone 0/1 and noise without being interrupted.
; Frame sequences follow the SMS bytecode note timings, volume steps and
; pitch modulation, simplified to precomputed PSG writes.
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
sfx_launch:
  ld hl,sfx_launch_data
  jr sfx_start
sfx_brake:
  ld hl,sfx_brake_data
sfx_start:
  ld (sfx_ptr),hl
  xor a
  ld (sfx_timer),a
  ret

; Each event is duration, then a packed 16-bit word: 10-bit period and
; attenuation in bits 10..13. Zero duration terminates and mutes channel 2.
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
  ld a,d
  rrca
  rrca
  and $0F
  or $D0
  push af
  ld a,d
  and 3
  ld d,a
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
  pop af
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

; Source: SFX 00/02/03/06 in src/prediet.asm. The SMS sound driver
; uses one update per bytecode tick here. Ring includes its repeated fading
; high notes; brake includes the two-tick rest and nine alternating pairs.
; Jump and roll precompute the original vibrato deltas before octave scaling.
; Direct-volume PSG attenuation is 15 minus the SMS direct-volume setting.
sfx_jump_data:
.db 3
.dw 320
.db 3
.dw 239
.db 1
.dw 231
.db 1
.dw 223
.db 1
.dw 215
.db 1
.dw 207
.db 1
.dw 199
.db 1
.dw 191
.db 1
.dw 183
.db 1
.dw 175
.db 1
.dw 167
.db 1
.dw 159
.db 1
.dw 151
.db 1
.dw 143
.db 1
.dw 135
.db 1
.dw 127
.db 1
.dw 119
.db 1
.dw 111
.db 1
.dw 103
.db 1
.dw 95
.db 0
sfx_ring_data:
.db 4
.dw 84
.db 4
.dw 71
.db 4
.dw 53
.db 4
.dw 2101
.db 4
.dw 4149
.db 4
.dw 6197
.db 0
sfx_roll_data:
.db 3
.dw 5176
.db 4
.dw 5175
.db 4
.dw 5174
.db 1
.dw 5173
.db 3
.dw 4149
.db 4
.dw 4148
.db 4
.dw 4147
.db 1
.dw 4146
.db 3
.dw 3122
.db 4
.dw 3121
.db 4
.dw 3120
.db 1
.dw 3119
.db 3
.dw 2095
.db 4
.dw 2094
.db 4
.dw 2093
.db 1
.dw 2092
.db 3
.dw 1068
.db 4
.dw 1067
.db 4
.dw 1066
.db 1
.dw 1065
.db 3
.dw 2089
.db 4
.dw 2088
.db 4
.dw 2087
.db 1
.dw 2086
.db 3
.dw 3110
.db 4
.dw 3109
.db 4
.dw 3108
.db 1
.dw 3107
.db 3
.dw 4131
.db 4
.dw 4130
.db 4
.dw 4129
.db 1
.dw 4128
.db 3
.dw 5152
.db 4
.dw 5151
.db 4
.dw 5150
.db 1
.dw 5149
.db 3
.dw 6173
.db 4
.dw 6172
.db 4
.dw 6171
.db 1
.dw 6170
.db 0
sfx_brake_data:
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 2
.dw 15479
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 1
.dw 134
.db 1
.dw 119
.db 0

; Short approximation of SMS SFX 05 (ramp whoosh), tone channel 2 only.
sfx_launch_data:
.db 3
.dw 3128
.db 3
.dw 2101
.db 3
.dw 1074
.db 3
.dw 3100
.db 6
.dw 6169
.db 0
