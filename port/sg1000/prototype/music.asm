; Simplified SMS arrangement: tones 0/1 and fixed-clock noise percussion.
; Tone 2 stays reserved for effects; the SMS third tone is omitted.
; Each score record is duration in frames, SMS note, PSG attenuation; a zero
; duration is followed by a 16-bit loop pointer, or zero to stop the stream.
music_title_start:
  ld hl,music_title_0
  ld de,music_title_1
  ld bc,music_title_3
  jr music_start
music_ghz_start:
  ld hl,music_ghz_0
  ld de,music_ghz_1
  ld bc,music_ghz_3
music_start:
  ld (music_ch0),hl
  ld (music_ch1),de
  ld (music_ch3),bc
  xor a
  ld (music_ch0+2),a
  ld (music_ch1+2),a
  ld (music_ch3+2),a
  ld a,$E5              ; white noise, fixed rate, independent of tone 2
  out ($7F),a
  ld a,$80
  ld (music_ch0+3),a
  ld a,$A0
  ld (music_ch1+3),a
  ret
music_stop:
  xor a
  ld (music_ch0),a
  ld (music_ch0+1),a
  ld (music_ch1),a
  ld (music_ch1+1),a
  ld (music_ch3),a
  ld (music_ch3+1),a
  ld a,$FF
  out ($7F),a
  ld a,$9F
  out ($7F),a
  ld a,$BF
  out ($7F),a
  ret
music_tick:
  ld ix,music_ch0
  call music_tick_channel
  ld ix,music_ch1
  call music_tick_channel
  jp music_tick_noise
music_tick_channel:
  ld l,(ix+0)
  ld h,(ix+1)
  ld a,h
  or l
  ret z
  ld a,(ix+2)
  or a
  jr z,music_next
  dec a
  ld (ix+2),a
  jr z,music_next
  cp (ix+4)               ; one gentle decay step after the attack
  ret nz
  ld a,(ix+5)
  out ($7F),a
  ret
music_next:
  ld a,(hl)
  inc hl
  or a
  jr nz,music_note
  ld e,(hl)
  inc hl
  ld d,(hl)
  ex de,hl
  ld a,h
  or l
  jr nz,music_next
  ld (ix+0),l
  ld (ix+1),h
  ld a,(ix+3)
  or $1F
  out ($7F),a
  ret
music_note:
  ld (ix+2),a
  sub 4
  jr nc,music_decay_time
  xor a
music_decay_time:
  ld (ix+4),a
  ld a,(hl)
  inc hl
  ld c,a
  ld a,(hl)
  inc hl
  ld b,a
  add a,2
  cp 16
  jr c,music_decay_volume_ready
  ld a,15
music_decay_volume_ready:
  or (ix+3)
  or $10
  ld (ix+5),a
  ld a,b
  or (ix+3)
  or $10
  out ($7F),a
  ld (ix+0),l
  ld (ix+1),h
  ld a,c
  cp $7F
  ret z
  and $0F
  add a,a
  ld e,a
  ld d,0
  ld hl,music_periods
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld a,c
  rrca
  rrca
  rrca
  rrca
  and $0F
  jr z,music_period_ready
  ld b,a
music_octave:
  srl d
  rr e
  djnz music_octave
music_period_ready:
  ld a,e
  and $0F
  or (ix+3)
  out ($7F),a
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
  ret
; Compact noise records: duration in the high nibble, attenuation in the
; low nibble. A zero byte points to a
; loop or null, just like the tone scores. Both SMS percussion presets use
; white-noise setting 5; their different decays are baked into the records.
music_tick_noise:
  ld hl,(music_ch3)
  ld a,h
  or l
  ret z
  ld a,(music_ch3+2)
  or a
  jr z,music_noise_next
  dec a
  ld (music_ch3+2),a
  ret nz
music_noise_next:
  ld a,(hl)
  inc hl
  or a
  jr nz,music_noise_note
  ld e,(hl)
  inc hl
  ld d,(hl)
  ex de,hl
  ld a,h
  or l
  jr nz,music_noise_next
  ld (music_ch3),hl
  ld a,$FF
  out ($7F),a
  ret
music_noise_note:
  ld c,a
  and $0F
  or $F0
  out ($7F),a
  ld a,c
  rrca
  rrca
  rrca
  rrca
  and $0F
  ld (music_ch3+2),a
  ld (music_ch3),hl
  ret
music_periods:
.dw $0356,$0326,$02F9,$02CE,$02A5,$0280,$025C,$023A
.dw $021A,$01FB,$01DF,$01C4,$03F7,$03BE,$0388

.INCLUDE "build/sg1000/prototype/music_score.inc"
