; Two-channel, deliberately simplified SMS music arrangement. Channel 2 is
; reserved for effects; channel 3/noise and the SMS third tone are omitted.
; Each score record is duration in frames, SMS note, PSG attenuation; a zero
; duration is followed by a 16-bit loop pointer, or zero to stop the stream.
music_title_start:
  ld hl,music_title_0
  ld de,music_title_1
  jr music_start
music_ghz_start:
  ld hl,music_ghz_0
  ld de,music_ghz_1
music_start:
  ld (music_ch0),hl
  ld (music_ch1),de
  xor a
  ld (music_ch0+2),a
  ld (music_ch1+2),a
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
  ld a,$9F
  out ($7F),a
  ld a,$BF
  out ($7F),a
  ret
music_tick:
  ld ix,music_ch0
  call music_tick_channel
  ld ix,music_ch1
  jp music_tick_channel
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
  ret nz
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
  ld a,(hl)
  inc hl
  ld c,a
  ld a,(hl)
  inc hl
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
music_periods:
.dw $0356,$0326,$02F9,$02CE,$02A5,$0280,$025C,$023A
.dw $021A,$01FB,$01DF,$01C4,$03F7,$03BE,$0388

.INCLUDE "build/sg1000/prototype/music_score.inc"
