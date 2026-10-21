; =============================================================================
; menu.s - Menú: canción, instrumento y dificultad
;
; Arriba/abajo mueve el cursor, izquierda/derecha cambia el valor, Start
; empieza a jugar y B regresa al título. Mientras eliges, suena la canción.
;
; La pantalla se arma completa con el dibujo apagado; después solo se
; reescriben los valores que cambian, por la cola de textos (vbuf).
; =============================================================================

MENU_LABEL_COL  = 4
MENU_VALUE_COL  = 6
MENU_SONG_ROW   = 10    ; título (y en la siguiente fila, el juego)
MENU_INST_ROW   = 16
MENU_DIFF_ROW   = 21
MENU_TEXT_WIDTH = 26

enter_menu:
    jsr ppu_off
    lda #STATE_MENU
    sta game_state

    ldx #PALETTES_MENU
    jsr load_palettes
    jsr clear_nametable
    lda #2
    jsr draw_logo
    PRINT MENU_LABEL_COL, MENU_SONG_ROW - 2, txt_song
    PRINT MENU_LABEL_COL, MENU_INST_ROW - 2, txt_instrument
    PRINT MENU_LABEL_COL, MENU_DIFF_ROW - 2, txt_difficulty
    PRINT_CENTER 26, txt_menu_help

    ; Los valores se escriben con las mismas rutinas que al cambiarlos
    jsr select_song
    jsr menu_draw_song
    jsr menu_draw_instrument
    jsr menu_draw_difficulty
    jsr flush_vbuf          ; el dibujo está apagado: se puede copiar ya

    jsr hide_sprites
    lda #0
    sta menu_cursor
    jsr menu_place_cursor

    lda #0
    sta scroll_y
    sta scroll_nt
    jsr ppu_on
    jmp start_preview

menu_update:
    lda pressed
    and #BTN_START
    beq @no_start
    jmp enter_play
@no_start:
    lda pressed
    and #BTN_B
    beq @no_back
    jmp enter_title
@no_back:
    ; Arriba / abajo: mover el cursor entre las 3 opciones
    lda pressed
    and #BTN_UP
    beq @no_up
    lda menu_cursor
    beq @no_up
    dec menu_cursor
@no_up:
    lda pressed
    and #BTN_DOWN
    beq @no_down
    lda menu_cursor
    cmp #2
    beq @no_down
    inc menu_cursor
@no_down:
    ; Izquierda / derecha: cambiar el valor
    lda pressed
    and #BTN_LEFT
    beq @no_left
    lda #$FF                ; -1
    sta menu_dir
    jsr menu_change
@no_left:
    lda pressed
    and #BTN_RIGHT
    beq @no_right
    lda #1
    sta menu_dir
    jsr menu_change
@no_right:
    jsr menu_place_cursor
    jmp famistudio_update   ; la canción de muestra

; -----------------------------------------------------------------------------
; menu_change: suma menu_dir (+1/-1) a la opción donde está el cursor
; -----------------------------------------------------------------------------
menu_change:
    lda menu_cursor
    beq @song
    cmp #1
    beq @instrument

    ; Dificultad: 0..3, dando la vuelta
    lda cur_difficulty
    clc
    adc menu_dir
    and #NUM_DIFFICULTIES - 1
    sta cur_difficulty
    jmp menu_draw_difficulty

@instrument:
    ; Siguiente instrumento con chart en esta canción (siempre hay al menos uno)
    lda cur_instrument
    clc
    adc menu_dir
    and #NUM_INSTRUMENTS - 1
    sta cur_instrument
    jsr instrument_available
    beq @instrument
    jmp menu_draw_instrument

@song:
    lda cur_song
    clc
    adc menu_dir
    bpl @not_negative
    lda #NUM_SONGS - 1      ; de la primera a la última
@not_negative:
    cmp #NUM_SONGS
    bcc @song_ok
    lda #0                  ; de la última a la primera
@song_ok:
    cmp cur_song
    beq @same_song          ; solo hay una canción: no hay nada que cambiar
    sta cur_song
    jsr select_song
    jsr menu_draw_song
    jsr menu_draw_instrument
    jmp start_preview
@same_song:
    rts

; -----------------------------------------------------------------------------
; select_song: song_ptr = ficha de cur_song, su slot en $A000-$DFFF, y un
; instrumento que sí tenga chart
; -----------------------------------------------------------------------------
select_song:
    lda cur_song
    asl a
    tax
    lda song_table,x
    sta song_ptr
    lda song_table+1,x
    sta song_ptr+1
    ldy #SONG_SLOT
    lda (song_ptr),y
    jsr select_slot
    jsr instrument_available
    bne @done
    lda #0                  ; el instrumento elegido no existe en esta canción:
    sta cur_instrument      ; buscar el primero que sí
@find:
    jsr instrument_available
    bne @done
    inc cur_instrument
    jmp @find
@done:
    rts

; A <> 0 si cur_instrument tiene chart en la canción de song_ptr
instrument_available:
    ldy #SONG_INSTRUMENTS
    lda (song_ptr),y
    ldx cur_instrument
    and lane_bit,x          ; lane_bit = 1, 2, 4, 8... sirve igual para instrumentos
    rts

; start_preview: la canción elegida suena desde el principio
start_preview:
    ldy #SONG_MUSIC
    lda (song_ptr),y
    tax
    iny
    lda (song_ptr),y
    tay
    lda #1                  ; NTSC
    jsr famistudio_init
    lda #0
    jmp famistudio_music_play

; -----------------------------------------------------------------------------
; Escribir los valores (por la cola vbuf)
; -----------------------------------------------------------------------------
menu_draw_song:
    ldy #SONG_TITLE
    jsr ptr_from_song
    SET_ADDR MENU_VALUE_COL, MENU_SONG_ROW
    lda #MENU_TEXT_WIDTH
    jsr vbuf_text
    ldy #SONG_GAME
    jsr ptr_from_song
    SET_ADDR MENU_VALUE_COL, MENU_SONG_ROW + 1
    lda #MENU_TEXT_WIDTH
    jmp vbuf_text

menu_draw_instrument:
    lda cur_instrument
    jsr ptr_instrument_name
    SET_ADDR MENU_VALUE_COL, MENU_INST_ROW
    lda #12
    jmp vbuf_text

menu_draw_difficulty:
    lda cur_difficulty
    jsr ptr_difficulty_name
    SET_ADDR MENU_VALUE_COL, MENU_DIFF_ROW
    lda #12
    jmp vbuf_text

; ptr = la dirección guardada en la ficha de la canción, en el campo Y
ptr_from_song:
    lda (song_ptr),y
    sta ptr
    iny
    lda (song_ptr),y
    sta ptr+1
    rts

; ptr = nombre del instrumento / dificultad número A
ptr_instrument_name:
    asl a
    tax
    lda instrument_names,x
    sta ptr
    lda instrument_names+1,x
    sta ptr+1
    rts

ptr_difficulty_name:
    asl a
    tax
    lda difficulty_names,x
    sta ptr
    lda difficulty_names+1,x
    sta ptr+1
    rts

; El cursor es un sprite '>' a la izquierda del valor elegido
menu_place_cursor:
    ldx menu_cursor
    lda cursor_y,x
    sta oam
    lda #'>'
    sta oam+1
    lda #0
    sta oam+2
    lda #MENU_LABEL_COL * 8
    sta oam+3
    rts

.segment "RODATA"

cursor_y:       .byte MENU_SONG_ROW * 8 - 1, MENU_INST_ROW * 8 - 1, MENU_DIFF_ROW * 8 - 1

instrument_names: .addr txt_guitar, txt_keys, txt_bass, txt_drums
difficulty_names: .addr txt_easy, txt_medium, txt_hard, txt_expert

txt_song:       .byte "CANCION", 0
txt_instrument: .byte "INSTRUMENTO", 0
txt_difficulty: .byte "DIFICULTAD", 0
txt_menu_help:  .byte "START: JUGAR   B: VOLVER", 0
txt_guitar:     .byte "GUITARRA", 0
txt_keys:       .byte "TECLADO", 0
txt_bass:       .byte "BAJO", 0
txt_drums:      .byte "BATERIA", 0
txt_easy:       .byte "FACIL", 0
txt_medium:     .byte "MEDIO", 0
txt_hard:       .byte "DIFICIL", 0
txt_expert:     .byte "EXPERTO", 0

.segment "CODE"
