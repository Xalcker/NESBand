; =============================================================================
; results.s - Pantalla de resultados al terminar la canción
;
; Una columna por jugador (o una al centro si jugó uno solo) con su
; instrumento, dificultad, puntaje, notas, precisión, combo máximo y estrellas.
; =============================================================================

RES_INST_ROW    = 9
RES_DIFF_ROW    = 10
RES_SCORE_ROW   = 12     ; etiqueta; el valor va en la fila siguiente
RES_NOTES_ROW   = 15
RES_ACC_ROW     = 18
RES_COMBO_ROW   = 21
RES_STARS_ROW   = 24

enter_results:
    jsr ppu_off
    jsr famistudio_music_stop
    lda #STATE_RESULTS
    sta game_state
    ldx #PALETTES_MENU
    jsr load_palettes
    jsr clear_nametable
    jsr hide_sprites

    PRINT_CENTER 3, txt_results
    ldy #SONG_TITLE
    jsr ptr_from_song
    lda #5
    jsr print_centered
    ldy #SONG_GAME
    jsr ptr_from_song
    lda #6
    jsr print_centered
    PRINT_CENTER 26, txt_continue

    ; Una columna por jugador
    ldx #0
@player:
    jsr load_player
    jsr compute_stats
    jsr store_player        ; (percent y stars quedan guardados para las pruebas)
    jsr draw_player_results
    ldx player
    inx
    cpx num_players
    bne @player

    lda #0
    sta scroll_y
    sta scroll_nt
    jmp ppu_on

results_update:
    lda pad_pressed
    ora pad_pressed+1
    and #BTN_START
    beq @done
    jmp enter_menu
@done:
    rts

; -----------------------------------------------------------------------------
; draw_player_results: la columna del jugador cargado en pstate
; -----------------------------------------------------------------------------
draw_player_results:
    ; Columna: results_col[(num_players - 1) * 2 + jugador]
    lda num_players
    sec
    sbc #1
    asl a
    clc
    adc player
    tax
    lda results_col,x
    sta res_col

    ; Instrumento y dificultad
    lda cur_instrument
    jsr ptr_instrument_name
    lda #RES_INST_ROW
    jsr res_print
    lda cur_difficulty
    jsr ptr_difficulty_name
    lda #RES_DIFF_ROW
    jsr res_print

    ; Puntaje: los 6 dígitos tal cual (score_digits son 0-9, el texto es '0'-'9')
    SET_PTR txt_score
    lda #RES_SCORE_ROW
    jsr res_print
    ldx #5
@score:
    lda score_digits,x
    clc
    adc #'0'
    sta numstr,x
    dex
    bpl @score
    lda #0
    sta numstr+6
    SET_PTR numstr
    lda #RES_SCORE_ROW + 1
    jsr res_print

    ; Notas: acertadas/total
    SET_PTR txt_notes
    lda #RES_NOTES_ROW
    jsr res_print
    lda notes_hit
    sta tmp
    lda notes_hit+1
    sta tmp+1
    jsr num_to_text
    lda #RES_NOTES_ROW + 1
    jsr res_print
    SET_PTR txt_slash
    jsr print_more
    lda notes_total
    sta tmp
    lda notes_total+1
    sta tmp+1
    jsr num_to_text
    jsr print_more

    ; Precisión
    SET_PTR txt_accuracy
    lda #RES_ACC_ROW
    jsr res_print
    lda percent
    sta tmp
    lda #0
    sta tmp+1
    jsr num_to_text
    lda #RES_ACC_ROW + 1
    jsr res_print
    SET_PTR txt_percent
    jsr print_more

    ; Combo máximo
    SET_PTR txt_max_combo
    lda #RES_COMBO_ROW
    jsr res_print
    lda max_combo
    sta tmp
    lda max_combo+1
    sta tmp+1
    jsr num_to_text
    lda #RES_COMBO_ROW + 1
    jsr res_print

    ; Estrellas: "* * *" (una por cada umbral de precisión alcanzado)
    ldx #0
    ldy #0
@star:
    cpx stars
    beq @stars_done
    lda #'*'
    sta numstr,y
    iny
    lda #' '
    sta numstr,y
    iny
    inx
    jmp @star
@stars_done:
    lda #0
    sta numstr,y
    SET_PTR numstr
    lda #RES_STARS_ROW
    ; sigue en res_print

; res_print: escribe el texto de ptr en la fila A, columna res_col (render apagado)
res_print:
    ldx res_col
    jsr text_addr
    jmp print_direct

; -----------------------------------------------------------------------------
; compute_stats: percent = notes_hit * 100 / notes_total, y las estrellas
;
; El 6502 no sabe multiplicar ni dividir, así que:
;   - multiplicar por 100 = sumar 100 veces (en 24 bits, porque puede pasar de 65535)
;   - dividir = contar cuántas veces se puede restar el total (a lo más 100)
; -----------------------------------------------------------------------------
compute_stats:
    lda #0
    sta hits100
    sta hits100+1
    sta hits100+2
    sta percent
    ldx #100
@multiply:
    clc
    lda hits100
    adc notes_hit
    sta hits100
    lda hits100+1
    adc notes_hit+1
    sta hits100+1
    lda hits100+2
    adc #0
    sta hits100+2
    dex
    bne @multiply

    lda notes_total
    ora notes_total+1
    beq @stars              ; chart vacío: 0%
@divide:
    sec
    lda hits100
    sbc notes_total
    sta tmp
    lda hits100+1
    sbc notes_total+1
    sta tmp+1
    lda hits100+2
    sbc #0
    bcc @stars              ; ya no cabe otra vez
    sta hits100+2
    lda tmp+1
    sta hits100+1
    lda tmp
    sta hits100
    inc percent
    jmp @divide

@stars:
    ldx #0
@threshold:
    lda percent
    cmp star_thresholds,x
    bcc @done
    inx
    cpx #5
    bne @threshold
@done:
    stx stars
    rts

.segment "RODATA"

; Precisión mínima para cada estrella
star_thresholds: .byte 20, 50, 70, 85, 95

;                1 jugador   2 jugadores
results_col:     .byte 10, 0,    2, 17

txt_results:    .byte "RESULTADOS", 0
txt_score:      .byte "PUNTAJE", 0
txt_notes:      .byte "NOTAS", 0
txt_accuracy:   .byte "PRECISION", 0
txt_max_combo:  .byte "COMBO MAXIMO", 0
txt_slash:      .byte "/", 0
txt_percent:    .byte "%", 0
txt_continue:   .byte "START: CONTINUAR", 0

.segment "CODE"
