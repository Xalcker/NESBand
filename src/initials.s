; =============================================================================
; initials.s - "NUEVO RECORD": escribir las 3 iniciales, como en un arcade
;
; Después de los resultados, si algún jugador superó su récord se llega aquí.
; Cada jugador con récord escribe sus iniciales con su propio control:
;   arriba / abajo     cambia la letra (A-Z, dando la vuelta)
;   izquierda / derecha  cambia de letra
;   A o Start          listo: se guarda el récord (rec_save)
; Cuando todos terminan, se regresa al menú.
; =============================================================================

INI_INST_ROW     = 8        ; instrumento (y dificultad en la fila siguiente)
INI_SCORE_LABEL  = 11
INI_LABEL_ROW    = 15
INI_LETTERS_ROW  = 17
INI_UNDER_ROW    = 18

PS_INI_DONE      = ini_done - pstate

enter_initials:
    jsr ppu_off
    lda #STATE_INITIALS
    sta game_state
    ldx #PALETTES_MENU
    jsr load_palettes
    jsr clear_nametable
    jsr hide_sprites
    PRINT_CENTER 3, txt_new_record
    PRINT_CENTER 25, txt_initials_help

    ldx #0
@player:
    jsr load_player
    lda new_record
    bne @enters
    lda #1                  ; este jugador no tiene récord: ya terminó
    sta ini_done
    jmp @store
@enters:
    lda #'A'
    sta ini
    sta ini+1
    sta ini+2
    lda #0
    sta ini_pos
    sta ini_done
    jsr results_set_col
    lda game_mode
    beq @own
    SET_PTR txt_band        ; Co-Op: el récord es de la banda
    lda #INI_INST_ROW
    jsr res_print
    jmp @score_label
@own:
    lda cur_instrument
    jsr ptr_instrument_name
    lda #INI_INST_ROW
    jsr res_print
    lda cur_difficulty
    jsr ptr_difficulty_name
    lda #INI_INST_ROW + 1
    jsr res_print
@score_label:
    SET_PTR txt_score
    lda #INI_SCORE_LABEL
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
    lda #INI_SCORE_LABEL + 1
    jsr res_print
    SET_PTR txt_initials
    lda #INI_LABEL_ROW
    jsr res_print
    jsr draw_initials
    jsr flush_vbuf          ; el dibujo está apagado: se puede copiar ya
@store:
    jsr store_player
    ldx player
    inx
    cpx num_players
    beq @players_done
    jmp @player             ; (muy lejos para un bne)
@players_done:

    lda #0
    sta scroll_y
    sta scroll_nt
    jmp ppu_on

; draw_initials: las 3 letras del jugador cargado y una raya debajo de la que se cambia
draw_initials:
    jsr results_set_col
    lda ini
    sta numstr
    lda ini+1
    sta numstr+2
    lda ini+2
    sta numstr+4
    lda #' '
    sta numstr+1
    sta numstr+3
    lda #0
    sta numstr+5
    ldx res_col
    lda #INI_LETTERS_ROW
    jsr text_addr
    SET_PTR numstr
    lda #5
    jsr vbuf_text

    ldx #4                  ; debajo: espacios, y un '-' bajo la letra actual
    lda #' '
@blank:
    sta numstr,x
    dex
    bpl @blank
    lda ini_pos
    asl a
    tax
    lda #'-'
    sta numstr,x
    ldx res_col
    lda #INI_UNDER_ROW
    jsr text_addr
    SET_PTR numstr
    lda #5
    jmp vbuf_text

initials_update:
    ldx #0
@player:
    jsr load_player
    lda new_record
    beq @next
    lda ini_done
    bne @next
    jsr initials_input
@next:
    jsr store_player
    ldx player
    inx
    cpx num_players
    bne @player

    lda player_save + PS_INI_DONE   ; ¿terminaron todos?
    beq @wait
    ldx num_players
    cpx #2
    bne @all_done
    lda player_save + PSTATE_SIZE + PS_INI_DONE
    beq @wait
@all_done:
    jmp enter_menu
@wait:
    rts

; initials_input: los botones del jugador cargado (pressed)
initials_input:
    lda pressed
    and #BTN_START | BTN_A
    beq @letters
    jsr rec_save            ; listo: se graba el récord
    lda #1
    sta ini_done
    lda #SFX_ACEPTAR
    jmp play_sfx
@letters:
    lda pressed
    and #BTN_UP
    beq @no_up
    ldx ini_pos
    lda ini,x
    cmp #'Z'
    bcc @up_ok
    lda #'A' - 1            ; después de la Z, la A
@up_ok:
    clc
    adc #1
    sta ini,x
    jmp @changed
@no_up:
    lda pressed
    and #BTN_DOWN
    beq @no_down
    ldx ini_pos
    lda ini,x
    cmp #'A' + 1
    bcs @down_ok
    lda #'Z' + 1            ; antes de la A, la Z
@down_ok:
    sec
    sbc #1
    sta ini,x
    jmp @changed
@no_down:
    lda pressed
    and #BTN_LEFT
    beq @no_left
    lda ini_pos
    beq @no_left
    dec ini_pos
    jmp @changed
@no_left:
    lda pressed
    and #BTN_RIGHT
    beq @none
    lda ini_pos
    cmp #2
    beq @none
    inc ini_pos
@changed:
    jsr draw_initials
    lda #SFX_MOVER
    jmp play_sfx
@none:
    rts

.segment "RODATA"
txt_new_record:    .byte "NUEVO RECORD", 0
txt_initials:      .byte "INICIALES", 0
txt_initials_help: .byte "ARRIBA/ABAJO: LETRA   A: LISTO", 0
.segment "CODE"
