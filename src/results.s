; =============================================================================
; results.s - Pantalla de resultados al terminar la canción
;
; Una columna por jugador (o una al centro si jugó uno solo) con su
; instrumento, dificultad, puntaje, notas, precisión, combo máximo y estrellas.
; =============================================================================

PSL_NEW_RECORD  = new_record - pslow    ; posición dentro del bloque lento de un jugador (player_slow)
PSL_NOTES_TOTAL = notes_total - pslow
PSL_STARS       = stars - pslow
PS_SCORE        = score_digits - pstate ; y dentro del bloque de pstate (player_save)
RES_WINNER_ROW  = 7      ; "GANA J1 POR 001230" (VS)
RES_RECORD_ROW  = 8      ; "NUEVO RECORD"
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
    lda #0
    sta vs_result

    ; Una columna por jugador
    ldx #0
@player:
    jsr load_player
    jsr load_slow
    jsr compute_stats
    lda game_mode
    beq @check
    lda #0                  ; Co-Op: solo hay un récord, el de la banda, y es del jugador 1
    sta new_record
    lda player
    bne @checked
    lda player_save + PSTATE_SIZE + PS_FAILED   ; y vale solo si los dos terminaron en pie
    bne @checked
@check:
    jsr rec_check_new       ; ¿superó el récord guardado?
    lda num_players         ; VS: si el rival perdió, la partida se cortó y no vale como récord
    cmp #2
    bne @checked
    lda game_mode
    bne @checked
    lda player
    eor #1
    tax
    ldy player_offset,x
    lda player_save + PS_FAILED,y
    beq @checked
    lda #0
    sta new_record
@checked:
    jsr store_player
    jsr store_slow          ; (percent y stars quedan guardados para las pruebas)
    jsr draw_player_results
    ldx player
    inx
    cpx num_players
    bne @player

    lda game_mode
    beq @versus
    jsr team_results        ; Co-Op: lo de la banda, al centro
    jmp @finish
@versus:
    lda num_players
    cmp #2
    bne @finish
    jsr vs_winner           ; VS: quién ganó
@finish:
    lda #0
    sta scroll_y
    sta scroll_nt
    jmp ppu_on

results_update:
    lda pad_pressed
    ora pad_pressed+1
    and #BTN_START
    beq @done
    lda player_slow + PSL_NEW_RECORD   ; ¿alguien tiene récord nuevo? Primero escribe sus iniciales
    bne @initials
    ldx num_players
    cpx #2
    bne @menu
    lda player_slow + PSLOW_SIZE + PSL_NEW_RECORD
    beq @menu
@initials:
    jmp enter_initials
@menu:
    jmp enter_menu
@done:
    rts

; results_set_col: res_col = columna de texto del jugador cargado:
; results_col[(num_players - 1) * 2 + jugador]
results_set_col:
    lda num_players
    sec
    sbc #1
    asl a
    clc
    adc player
    tax
    lda results_col,x
    sta res_col
    rts

; -----------------------------------------------------------------------------
; draw_player_results: la columna del jugador cargado en pstate
; -----------------------------------------------------------------------------
draw_player_results:
    jsr results_set_col

    ; ¿Récord nuevo? (en Co-Op lo de la banda va al centro: team_results)
    lda game_mode
    bne @no_record
    lda new_record
    beq @no_record
    SET_PTR txt_new_record
    lda #RES_RECORD_ROW
    jsr res_print
@no_record:

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
    lda game_mode           ; Co-Op: el puntaje es de la banda (team_results)
    beq @own_score
    jmp @notes
@own_score:

    ; Puntaje: los 6 dígitos tal cual
    SET_PTR txt_score
    lda #RES_SCORE_ROW
    jsr res_print
    jsr score_text
    lda #RES_SCORE_ROW + 1
    jsr res_print

    ; Notas: acertadas/total
@notes:
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

    lda game_mode           ; Co-Op: combo máximo y estrellas son de la banda
    beq @own_combo
    rts
@own_combo:

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

    jsr stars_text
    lda #RES_STARS_ROW
    ; sigue en res_print

; res_print: escribe el texto de ptr en la fila A, columna res_col (render apagado)
res_print:
    ldx res_col
    jsr text_addr
    jmp print_direct

; stars_text: ptr = "* * *" (una por cada estrella ganada)
stars_text:
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
    rts

; score_text: ptr = los 6 dígitos del puntaje del jugador cargado (score_digits son 0-9, el texto '0'-'9')
score_text:
    ldx #5
@digit:
    lda score_digits,x
    clc
    adc #'0'
    sta numstr,x
    dex
    bpl @digit
    lda #0
    sta numstr+6
    SET_PTR numstr
    rts

; -----------------------------------------------------------------------------
; team_results: (Co-Op) lo de la banda, centrado: récord, estado, puntaje, combo
; máximo y estrellas. Las estrellas salen del puntaje de la banda contra el máximo
; posible de los dos charts juntos (el combo es uno solo: notas de uno y otro).
; Cada jugador ya dibujó su columna (instrumento, notas y precisión).
; -----------------------------------------------------------------------------
team_results:
    ldx #0
    jsr load_player         ; lo compartido es igual en los dos; las notas, se suman
    jsr load_slow
    lda notes_total
    sta ptr
    lda notes_total+1
    sta ptr+1
    clc
    lda notes_total
    adc player_slow + PSLOW_SIZE + PSL_NOTES_TOTAL
    sta notes_total
    lda notes_total+1
    adc player_slow + PSLOW_SIZE + PSL_NOTES_TOTAL + 1
    sta notes_total+1
    jsr compute_stars
    lda ptr                 ; y el jugador 1 conserva las suyas
    sta notes_total
    lda ptr+1
    sta notes_total+1
    jsr store_player
    jsr store_slow
    lda stars               ; el jugador 2 también guarda las estrellas de la banda (para las pruebas)
    sta player_slow + PSLOW_SIZE + PSL_STARS

    lda new_record
    beq @no_record
    SET_PTR txt_new_record
    lda #RES_RECORD_ROW
    jsr print_centered
@no_record:
    SET_PTR txt_score       ; (el estado, FALLASTE o SIN FALLO, va en la columna de cada jugador)
    lda #RES_SCORE_ROW
    jsr print_centered
    jsr score_text
    lda #RES_SCORE_ROW + 1
    jsr print_centered
    SET_PTR txt_max_combo
    lda #RES_COMBO_ROW
    jsr print_centered
    lda max_combo
    sta tmp
    lda max_combo+1
    sta tmp+1
    jsr num_to_text
    lda #RES_COMBO_ROW + 1
    jsr print_centered
    jsr stars_text
    lda #RES_STARS_ROW
    jmp print_centered

; -----------------------------------------------------------------------------
; vs_winner: (VS, 2 jugadores) compara los puntajes, deja en vs_result 1 (gana J1),
; 2 (gana J2) o 3 (empate), y escribe "GANA J1 POR 001230" (o "EMPATE")
; -----------------------------------------------------------------------------
vs_winner:
    lda player_save + PS_FAILED         ; si uno perdió (la partida se corta) y el otro no, gana el otro
    cmp player_save + PSTATE_SIZE + PS_FAILED
    beq @by_score                       ; los dos perdieron, o ninguno: por puntaje
    ldx #1
    bcc @survivor                       ; perdió el jugador 2: gana el 1
    ldx #2                              ; perdió el jugador 1: gana el 2
@survivor:
    stx vs_result
    ldx #18                             ; "GANA J? - J? PERDIO"
@lost_text:
    lda txt_wins_lost,x
    sta numstr,x
    dex
    bpl @lost_text
    lda vs_result
    ora #'0'
    sta numstr + 6
    lda #3                              ; el que perdió es el otro: 3 - jugador
    sec
    sbc vs_result
    ora #'0'
    sta numstr + 11
    lda #0
    sta numstr + 19
    SET_PTR numstr
    lda #RES_WINNER_ROW
    jmp print_centered
@by_score:
    ldx #0
@compare:
    lda player_save + PS_SCORE,x        ; de la cifra más alta a la más baja
    cmp player_save + PSTATE_SIZE + PS_SCORE,x
    bne @differ
    inx
    cpx #6
    bne @compare
    lda #3
    sta vs_result
    SET_PTR txt_tie
    lda #RES_WINNER_ROW
    jmp print_centered
@differ:
    bcc @second
    ; Gana el jugador 1: ptr = su puntaje, addr = el del jugador 2
    lda #1
    sta vs_result
    lda #<(player_save + PS_SCORE)
    sta ptr
    lda #>(player_save + PS_SCORE)
    sta ptr+1
    lda #<(player_save + PSTATE_SIZE + PS_SCORE)
    sta addr
    lda #>(player_save + PSTATE_SIZE + PS_SCORE)
    sta addr+1
    jmp @text
@second:
    lda #2
    sta vs_result
    lda #<(player_save + PSTATE_SIZE + PS_SCORE)
    sta ptr
    lda #>(player_save + PSTATE_SIZE + PS_SCORE)
    sta ptr+1
    lda #<(player_save + PS_SCORE)
    sta addr
    lda #>(player_save + PS_SCORE)
    sta addr+1
@text:
    ; "GANA J? POR " y, detrás, la diferencia (ptr - addr, dígito por dígito con préstamo)
    ldx #11
@prefix:
    lda txt_wins,x
    sta numstr,x
    dex
    bpl @prefix
    lda vs_result
    ora #'0'
    sta numstr + 6
    ldy #5
    sec
@subtract:
    lda (ptr),y
    sbc (addr),y
    bcs @digit
    adc #10                 ; préstamo (carry = 0): +10, y el siguiente dígito resta 1 más
    clc
@digit:
    ora #'0'                ; (no toca el carry)
    sta numstr + 12,y
    dey
    bpl @subtract
    lda #0
    sta numstr + 18
    SET_PTR numstr
    lda #RES_WINNER_ROW
    jmp print_centered

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
    ; sigue en compute_stars

; compute_stars: las estrellas, a partir del puntaje y de notes_total
compute_stars:
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
txt_wins:       .byte "GANA J? POR "       ; 12 caracteres: después va la diferencia de puntaje
txt_wins_lost:  .byte "GANA J? - J? PERDIO"   ; 19 caracteres: gana por el fallo del rival
txt_tie:        .byte "EMPATE", 0
txt_slash:      .byte "/", 0
txt_percent:    .byte "%", 0
txt_continue:   .byte "START: CONTINUAR", 0

.segment "CODE2"
