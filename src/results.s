; =============================================================================
; results.s - Pantalla de resultados al terminar la canción
; =============================================================================

RESULTS_LABEL_COL = 5
RESULTS_VALUE_COL = 18

enter_results:
    jsr ppu_off
    jsr famistudio_music_stop
    lda #STATE_RESULTS
    sta game_state
    ldx #PALETTES_MENU
    jsr load_palettes
    jsr clear_nametable
    jsr hide_sprites
    jsr compute_stats

    PRINT_CENTER 3, txt_results

    ; Canción, juego, instrumento y dificultad
    ldy #SONG_TITLE
    jsr ptr_from_song
    lda #6
    jsr print_centered
    ldy #SONG_GAME
    jsr ptr_from_song
    lda #7
    jsr print_centered
    SET_ADDR RESULTS_LABEL_COL, 9
    lda cur_instrument
    jsr ptr_instrument_name
    jsr print_direct
    SET_PTR txt_dash
    jsr print_more
    lda cur_difficulty
    jsr ptr_difficulty_name
    jsr print_more

    ; Puntaje: los 6 dígitos tal cual (score_digits son 0-9, el texto es '0'-'9')
    PRINT RESULTS_LABEL_COL, 12, txt_score
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
    SET_ADDR RESULTS_VALUE_COL, 12
    SET_PTR numstr
    jsr print_direct

    ; Notas: acertadas/total
    PRINT RESULTS_LABEL_COL, 14, txt_notes
    SET_ADDR RESULTS_VALUE_COL, 14
    lda notes_hit
    sta tmp
    lda notes_hit+1
    sta tmp+1
    jsr num_to_text
    jsr print_direct
    SET_PTR txt_slash
    jsr print_more
    lda notes_total
    sta tmp
    lda notes_total+1
    sta tmp+1
    jsr num_to_text
    jsr print_more

    ; Precisión
    PRINT RESULTS_LABEL_COL, 16, txt_accuracy
    SET_ADDR RESULTS_VALUE_COL, 16
    lda percent
    sta tmp
    lda #0
    sta tmp+1
    jsr num_to_text
    jsr print_direct
    SET_PTR txt_percent
    jsr print_more

    ; Combo máximo
    PRINT RESULTS_LABEL_COL, 18, txt_max_combo
    SET_ADDR RESULTS_VALUE_COL, 18
    lda max_combo
    sta tmp
    lda max_combo+1
    sta tmp+1
    jsr num_to_text
    jsr print_direct

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
    lda #21
    jsr print_centered

    PRINT_CENTER 26, txt_continue

    lda #0
    sta scroll_y
    sta scroll_nt
    jmp ppu_on

results_update:
    lda pressed
    and #BTN_START
    beq @done
    jmp enter_menu
@done:
    rts

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

txt_results:    .byte "RESULTADOS", 0
txt_dash:       .byte " - ", 0
txt_score:      .byte "PUNTAJE", 0
txt_notes:      .byte "NOTAS", 0
txt_accuracy:   .byte "PRECISION", 0
txt_max_combo:  .byte "COMBO MAXIMO", 0
txt_slash:      .byte "/", 0
txt_percent:    .byte "%", 0
txt_continue:   .byte "START: CONTINUAR", 0

.segment "CODE"
