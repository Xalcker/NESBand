; =============================================================================
; results.s - Pantalla de resultados al terminar la canción
;
; Una columna por jugador (o una al centro si jugó uno solo) con su
; instrumento, dificultad, puntaje, notas, precisión, combo máximo y estrellas.
; =============================================================================

RES_INST_ROW    = 9
RES_DIFF_ROW    = 10
RES_STATUS_ROW  = 11     ; "FALLASTE" o "SIN FALLO"
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

    ; Cómo terminó: perdiste, o jugaste sin fallo (esa partida no puede grabar récord)
    lda failed
    beq @not_failed
    SET_PTR txt_res_failed
    lda #RES_STATUS_ROW
    jsr res_print
    jmp @status_done
@not_failed:
    lda no_fail
    beq @status_done
    SET_PTR txt_res_no_fail
    lda #RES_STATUS_ROW
    jsr res_print
@status_done:

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
    ; Precisión = notas acertadas / total
    lda notes_hit
    sta ratio_num
    lda notes_hit+1
    sta ratio_num+1
    lda notes_total
    sta ratio_den
    lda notes_total+1
    sta ratio_den+1
    jsr ratio100
    sta percent

    ; Las estrellas salen del PUNTAJE, como en Rock Band, y no de la
    ; precisión: machacando botones se aciertan notas de suerte, pero los
    ; golpes al aire rompen el combo y el puntaje se queda muy abajo.
    ; score_pct = puntaje logrado / puntaje máximo posible
    lda score_units
    sta ratio_num
    lda score_units+1
    sta ratio_num+1
    jsr perfect_units       ; ratio_den = puntaje máximo (en unidades de 50)
    jsr ratio100
    sta score_pct

    ldx #0
@threshold:
    lda score_pct
    cmp star_thresholds,x
    bcc @done
    inx
    cpx #5
    bne @threshold
@done:
    stx stars
    rts

; -----------------------------------------------------------------------------
; perfect_units: ratio_den = puntaje de acertar las notes_total notas sin
; fallar, en unidades de 50. La nota número i vale su multiplicador:
;   notas 1-9 x1, 10-19 x2, 20-29 x3, de la 30 en adelante x4
; Sumando por tramos queda (n = notas):
;   n < 10: n      n < 20: 2n - 9      n < 30: 3n - 28      si no: 4n - 57
; -----------------------------------------------------------------------------
perfect_units:
    lda notes_total+1
    bne @x4                 ; 256 notas o más
    lda notes_total
    ldx #1                  ; X = multiplicador del tramo
    ldy #0                  ; Y = lo que se resta
    cmp #10
    bcc @calc
    inx
    ldy #9
    cmp #20
    bcc @calc
    inx
    ldy #28
    cmp #30
    bcc @calc
@x4:
    ldx #4
    ldy #57
@calc:
    ; ratio_den = notes_total * X - Y
    sty tmp
    lda #0
    sta ratio_den
    sta ratio_den+1
@times:
    clc
    lda ratio_den
    adc notes_total
    sta ratio_den
    lda ratio_den+1
    adc notes_total+1
    sta ratio_den+1
    dex
    bne @times
    sec
    lda ratio_den
    sbc tmp
    sta ratio_den
    lda ratio_den+1
    sbc #0
    sta ratio_den+1
    rts

; -----------------------------------------------------------------------------
; ratio100: A = ratio_num * 100 / ratio_den, de 0 a 100 (0 si ratio_den = 0)
;
; El 6502 no sabe multiplicar ni dividir, así que:
;   - multiplicar por 100 = sumar 100 veces (en 24 bits, porque puede pasar de 65535)
;   - dividir = contar cuántas veces se puede restar ratio_den (a lo más 100)
; -----------------------------------------------------------------------------
ratio100:
    lda #0
    sta hits100
    sta hits100+1
    sta hits100+2
    sta ratio_res
    ldx #100
@multiply:
    clc
    lda hits100
    adc ratio_num
    sta hits100
    lda hits100+1
    adc ratio_num+1
    sta hits100+1
    lda hits100+2
    adc #0
    sta hits100+2
    dex
    bne @multiply

    lda ratio_den
    ora ratio_den+1
    beq @done               ; división entre 0: 0%
@divide:
    lda ratio_res
    cmp #100
    beq @done               ; tope: 100%
    sec
    lda hits100
    sbc ratio_den
    sta tmp
    lda hits100+1
    sbc ratio_den+1
    sta tmp+1
    lda hits100+2
    sbc #0
    bcc @done               ; ya no cabe otra vez
    sta hits100+2
    lda tmp+1
    sta hits100+1
    lda tmp
    sta hits100
    inc ratio_res
    jmp @divide
@done:
    lda ratio_res
    rts

.segment "RODATA"

; Puntaje mínimo (en % del máximo posible) para cada estrella
star_thresholds: .byte 20, 40, 60, 80, 95

;                1 jugador   2 jugadores
results_col:     .byte 10, 0,    2, 17

txt_results:    .byte "RESULTADOS", 0
txt_res_failed: .byte "FALLASTE", 0
txt_res_no_fail: .byte "SIN FALLO", 0
txt_score:      .byte "PUNTAJE", 0
txt_notes:      .byte "NOTAS", 0
txt_accuracy:   .byte "PRECISION", 0
txt_max_combo:  .byte "COMBO MAXIMO", 0
txt_slash:      .byte "/", 0
txt_percent:    .byte "%", 0
txt_continue:   .byte "START: CONTINUAR", 0

.segment "CODE"
