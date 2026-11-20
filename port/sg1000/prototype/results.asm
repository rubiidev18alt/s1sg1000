; Minimal level-clear screen: use the original menu font, plus custom A/P/I.
; No score/time or bonus-stage transition exists in this prototype yet.
result_init:
  call music_stop
  ld hl,$5B00
  call vdp_addr
  ld a,$D0
  out ($BE),a                 ; hide sprites
  ld hl,$5800
  call vdp_addr
  ld bc,768
result_clear:
  xor a
  out ($BE),a
  dec bc
  ld a,b
  or c
  jr nz,result_clear
  ld hl,$6000
  call vdp_addr
  ld b,4
  ld a,$F1
result_colours:
  out ($BE),a
  djnz result_colours
  ld a,$01
  out ($BF),a
  ld a,$87
  out ($BF),a                 ; black backdrop
  ld hl,$40C8                ; characters 25..27
  call vdp_addr
  ld hl,result_letters
  ld bc,24
  call vdp_copy
  ld hl,$5908                ; row 8, column 8
  call vdp_addr
  ld hl,result_heading
  ld bc,16
  call vdp_copy
  ld hl,$59AE                ; row 13, column 14
  call vdp_addr
  ld hl,result_act
  ld bc,5
  jp vdp_copy
result_heading:
.db 12,9,10,27,14,0,17,25,12,0,26,25,12,12,11,20
result_act:
.db 25,14,15,0,18
result_letters:
.db $18,$24,$42,$7E,$42,$42,$42,0 ; A
.db $7C,$42,$42,$7C,$40,$40,$40,0 ; P
.db $3E,$08,$08,$08,$08,$08,$3E,0 ; I

result_frame:
  ; Button 1 returns to zone select; init reinitializes the stack and state.
  ld a,(controls)
  and $10
  jp nz,init
  jp main_loop
