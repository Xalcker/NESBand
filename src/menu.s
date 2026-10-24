; =============================================================================
; menu.s - Menú: canción, jugadores, instrumento y dificultad
;
; El jugador 1 (control 1) mueve su cursor por las 4 opciones con
; arriba/abajo y cambia el valor con izquierda/derecha. Con 2 jugadores, el
; jugador 2 (control 2) tiene su propio cursor (naranja) para su instrumento
; y su dificultad. Start (cualquier control) empieza; B regresa al título.
; Mientras eligen, suena la canción.
;
; Dos jugadores no pueden tocar el mismo instrumento: cada uno silencia su
; canal al fallar.
;
; La pantalla se arma completa con el dibujo apagado; después solo se
; reescriben los valores que cambian, por la cola de textos (vbuf).
; =============================================================================

MENU_LABEL_COL   = 2
MENU_VALUE_COL   = 4     ; valores del jugador 1 (y la canción)
MENU_VALUE_COL2  = 18    ; valores del jugador 2
MENU_SONG_ROW    = 8     ; título (y en la siguiente fila, el juego)
MENU_PLAYERS_ROW = 12
MENU_INST_ROW    = 15
MENU_DIFF_ROW    = 18
MENU_FAIL_ROW    = 21
MENU_REC_ROW     = 23    ; récord guardado de cada jugador (su etiqueta, en la fila de arriba)
MENU_REC_WIDTH   = 13    ; "012345 ABC 5*"
MENU_TEXT_WIDTH  = 26
MENU_VALUE_WIDTH = 12
MENU_PLAYERS_WIDTH = 16  ; "2 JUGADORES COOP"

MENU_ITEMS       = 5     ; opciones del jugador 1: canción, jugadores, instrumento, dificultad, fallo
ITEM_SONG        = 0
ITEM_PLAYERS     = 1
ITEM_INSTRUMENT  = 2
ITEM_DIFFICULTY  = 3
ITEM_FAIL        = 4

PS_INSTRUMENT    = cur_instrument - pstate   ; posición dentro del bloque de un jugador
PS_DIFFICULTY    = cur_difficulty - pstate

enter_menu:
    jsr ppu_off
    lda #STATE_MENU
    sta game_state

    ldx #PALETTES_MENU
    jsr load_palettes
    jsr clear_nametable
    lda #1
    jsr draw_logo
    PRINT MENU_LABEL_COL, MENU_SONG_ROW - 1, txt_song
    PRINT MENU_LABEL_COL, MENU_PLAYERS_ROW - 1, txt_players
    PRINT MENU_LABEL_COL, MENU_INST_ROW - 1, txt_instrument
    PRINT MENU_LABEL_COL, MENU_DIFF_ROW - 1, txt_difficulty
    PRINT MENU_LABEL_COL, MENU_FAIL_ROW - 1, txt_fail
    PRINT MENU_LABEL_COL, MENU_REC_ROW - 1, txt_record
    PRINT_CENTER 26, txt_menu_help
    PRINT_CENTER 27, txt_menu_options

    ; Los valores se escriben con las mismas rutinas que al cambiarlos
    jsr select_song
    jsr menu_draw_song
    jsr flush_vbuf          ; el dibujo está apagado: se puede copiar ya
    jsr menu_draw_players
    jsr flush_vbuf
    ldx #0
    jsr menu_draw_player
    jsr flush_vbuf
    ldx #1
    jsr menu_draw_player
    jsr flush_vbuf
    ldx #0
    jsr menu_draw_record
    jsr flush_vbuf
    ldx #1
    jsr menu_draw_record
    jsr flush_vbuf
    lda #0
    sta menu_rec_dirty

    jsr hide_sprites
    lda #ITEM_SONG
    sta menu_cursor
    lda #0
    sta menu_cursor2
    jsr menu_place_cursors

    lda #0
    sta scroll_y
    sta scroll_nt
    jsr ppu_on
    jsr start_preview
    lda #SFX_ACEPTAR        ; venimos de un Start (título, resultados o pausa)
    jmp play_sfx

menu_update:
    lda #0
    sta menu_moved
    lda pad_pressed
    ora pad_pressed+1
    and #BTN_START
    beq @no_start
    jmp enter_play          ; Start de cualquier control
@no_start:
    lda pad_pressed
    ora pad_pressed+1
    and #BTN_SELECT
    beq @no_options
    jmp enter_options       ; Select: modificadores y práctica (options.s)
@no_options:
    lda pad_pressed
    and #BTN_B
    beq @no_back
    jsr enter_title
    lda #SFX_VOLVER         ; (después de enter_title, que reinicia el motor)
    jmp play_sfx
@no_back:

    ; --- Jugador 1 ---
    lda pad_pressed
    sta tmp+1
    lda menu_cursor
    ldx #MENU_ITEMS - 1
    jsr move_cursor
    sta menu_cursor
    jsr direction           ; menu_dir = -1/+1, o 0 si no hay izquierda/derecha
    beq @p2
    lda menu_cursor
    ldx #0
    jsr menu_change

    ; --- Jugador 2 (solo instrumento y dificultad) ---
@p2:
    lda num_players
    cmp #2
    bne @done
    lda pad_pressed+1
    sta tmp+1
    lda menu_cursor2
    ldx #2                  ; 0 = instrumento, 1 = dificultad, 2 = fallo
    jsr move_cursor
    sta menu_cursor2
    jsr direction
    beq @done
    lda menu_cursor2
    clc
    adc #ITEM_INSTRUMENT
    ldx #1
    jsr menu_change

@done:
    ; Los récords se redibujan de a uno por cuadro (la cola de textos es corta)
    lda menu_rec_dirty
    beq @rec_ok
    and #%01
    beq @rec2
    lda menu_rec_dirty
    and #%10
    sta menu_rec_dirty
    ldx #0
    jsr menu_draw_record
    jmp @rec_ok
@rec2:
    lda #0
    sta menu_rec_dirty
    ldx #1
    jsr menu_draw_record
@rec_ok:
    jsr menu_place_cursors
    lda menu_moved          ; ¿alguien movió el cursor o cambió algo? "blip"
    beq @no_sfx
    lda #SFX_MOVER
    jsr play_sfx
@no_sfx:
    jmp famistudio_update   ; la canción de muestra

; move_cursor: A = cursor, X = último valor, tmp+1 = botones presionados.
; Devuelve el cursor movido con arriba/abajo (y si cambió, marca menu_moved).
move_cursor:
    stx tmp
    pha
    jsr @move
    sta tmp                 ; ¿quedó distinto?
    pla
    cmp tmp
    beq @same
    inc menu_moved
@same:
    lda tmp
    rts
@move:
    tay
    lda tmp+1
    and #BTN_UP
    beq @no_up
    cpy #0
    beq @no_up
    dey
@no_up:
    lda tmp+1
    and #BTN_DOWN
    beq @no_down
    cpy tmp
    beq @no_down
    iny
@no_down:
    tya
    rts

; direction: menu_dir = -1 (izquierda), +1 (derecha) o 0; Z = 1 si es 0
; (si no es 0, marca menu_moved)
direction:
    lda #0
    sta menu_dir
    lda tmp+1
    and #BTN_LEFT
    beq @no_left
    dec menu_dir
@no_left:
    lda tmp+1
    and #BTN_RIGHT
    beq @no_right
    inc menu_dir
@no_right:
    lda menu_dir
    beq @done
    inc menu_moved          ; (inc deja Z = 0)
@done:
    rts

; -----------------------------------------------------------------------------
; menu_change: suma menu_dir (+1/-1) a la opción A del jugador X
; -----------------------------------------------------------------------------
menu_change:
    pha
    jsr load_player
    pla
    cmp #ITEM_SONG
    bne @not_song
    jmp @song               ; (muy lejos para un beq)
@not_song:
    cmp #ITEM_PLAYERS
    beq @players
    cmp #ITEM_INSTRUMENT
    beq @instrument
    cmp #ITEM_FAIL
    beq @fail

    ; Dificultad: 0..3, dando la vuelta. En VS los dos juegan la misma (un duelo solo es
    ; justo con las mismas notas): la elige el jugador 1 y el jugador 2 la sigue.
    lda num_players
    cmp #2
    bne @difficulty
    lda game_mode
    bne @difficulty
    lda player
    beq @difficulty
    rts                     ; el jugador 2 no puede cambiarla en VS
@difficulty:
    lda cur_difficulty
    clc
    adc menu_dir
    and #NUM_DIFFICULTIES - 1
    sta cur_difficulty
    jsr store_player
    jsr mark_record_dirty
    lda #0
    jsr vs_mirror
    ldx player
    jmp menu_draw_player

@fail:
    ; Con fallo <-> sin fallo (izquierda o derecha da igual)
    lda no_fail
    eor #1
    sta no_fail
    jsr store_player
    ldx player
    jmp menu_draw_player

@instrument:
    ; Siguiente instrumento que se pueda usar (siempre hay al menos uno)
    lda cur_instrument
    clc
    adc menu_dir
    and #NUM_INSTRUMENTS - 1
    sta cur_instrument
    jsr instrument_ok
    beq @instrument
    jsr store_player
    jsr mark_record_dirty
    lda #1
    jsr vs_mirror
    ldx player
    jmp menu_draw_player

@players:
    ; 1 jugador -> 2 jugadores VS -> 2 jugadores Co-Op -> vuelta (izquierda va al revés)
    jsr players_mode
    clc
    adc menu_dir
    bpl @mode_low
    lda #2
@mode_low:
    cmp #3
    bcc @mode_ok
    lda #0
@mode_ok:
    ldx #1
    stx num_players
    ldx #0
    stx game_mode
    cmp #0
    beq @mode_set           ; 1 jugador
    inc num_players
    cmp #2
    bne @mode_set           ; 2 jugadores VS
    inc game_mode           ; 2 jugadores Co-Op
@mode_set:
    lda num_players
    cmp #2
    bne @players_done
    ldx #1                  ; el jugador 2: en Co-Op necesita un instrumento distinto; en VS
    jsr load_player         ; juega lo mismo que el jugador 1 (dificultad e instrumento)
    lda game_mode
    bne @fix_p2
    lda player_save + PS_INSTRUMENT
    sta cur_instrument
    lda player_save + PS_DIFFICULTY
    sta cur_difficulty
@fix_p2:
    jsr fix_instrument
    jsr store_player
    bcs @players_done
    lda #1                  ; no hay instrumento libre en esta canción
    sta num_players
@players_done:
    lda #%11                ; el jugador 2 aparece o desaparece
    sta menu_rec_dirty
    jsr menu_draw_players
    ldx #1
    jmp menu_draw_player

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
    ldx #0
    jsr menu_draw_instrument
    ldx #1
    jsr menu_draw_instrument
    lda #%11                ; cada canción tiene sus propios récords
    sta menu_rec_dirty
    jmp start_preview
@same_song:
    rts

; vs_mirror: (VS, 2 jugadores) el jugador 1 acaba de cambiar su dificultad (A = 0) o su
; instrumento (A <> 0): el jugador 2 lo copia. Su instrumento sí puede cambiarlo después.
vs_mirror:
    tay
    lda num_players
    cmp #2
    bne @none
    lda game_mode
    bne @none
    lda player
    bne @none               ; solo cuando quien cambió es el jugador 1
    lda cur_difficulty
    sta player_save + PSTATE_SIZE + PS_DIFFICULTY
    tya
    beq @redraw
    lda cur_instrument
    sta player_save + PSTATE_SIZE + PS_INSTRUMENT
@redraw:
    lda menu_rec_dirty
    ora #%10                ; su récord es de otro instrumento o dificultad
    sta menu_rec_dirty
    ldx #1
    jmp menu_draw_player
@none:
    rts

; -----------------------------------------------------------------------------
; select_song: song_ptr = ficha de cur_song, su slot en $A000-$DFFF, y que
; cada jugador tenga un instrumento que se pueda usar en esta canción
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
    jsr compute_song_hash   ; para encontrar sus récords

    ldx #0
@player:
    jsr load_player
    jsr fix_instrument
    jsr store_player
    bcs @next
    lda #1                  ; el jugador 2 no tiene instrumento libre: juega uno solo
    sta num_players
@next:
    ldx player
    inx
    cpx #MAX_PLAYERS
    bne @player
    rts

; fix_instrument: si cur_instrument no se puede usar, busca el siguiente que
; sí. Carry = 1 si lo encontró.
fix_instrument:
    ldy #NUM_INSTRUMENTS
@try:
    jsr instrument_ok
    bne @found
    lda cur_instrument
    clc
    adc #1
    and #NUM_INSTRUMENTS - 1
    sta cur_instrument
    dey
    bne @try
    clc
    rts
@found:
    sec
    rts

; instrument_ok: A <> 0 si el jugador actual puede usar cur_instrument: la
; canción tiene chart para él y (con 2 jugadores) el otro no lo eligió.
; No modifica Y.
instrument_ok:
    lda cur_instrument
    tax
    sty tmp
    ldy #SONG_INSTRUMENTS
    lda (song_ptr),y
    ldy tmp
    and lane_bit,x          ; lane_bit = 1, 2, 4, 8... sirve igual para instrumentos
    beq @no
    lda num_players
    cmp #2
    bne @yes
    lda game_mode           ; en VS pueden tocar el mismo instrumento (el mismo chart: duelo
    beq @yes                ; parejo); en Co-Op no, o se tocarían las mismas notas dos veces
    lda player              ; instrumento del otro jugador, de su copia guardada
    eor #1
    tax
    lda player_offset,x
    tax
    lda player_save + PS_INSTRUMENT,x
    cmp cur_instrument
    beq @no
@yes:
    lda #1
    rts
@no:
    lda #0
    rts

; start_preview: la canción elegida suena desde el principio
start_preview:
    ldy #SONG_MUSIC
    lda (song_ptr),y
    tax
    iny
    lda (song_ptr),y
    tay
    jsr music_init
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

menu_draw_players:
    jsr players_mode
    asl a
    tax
    lda players_names,x
    sta ptr
    lda players_names+1,x
    sta ptr+1
    SET_ADDR MENU_VALUE_COL, MENU_PLAYERS_ROW
    lda #MENU_PLAYERS_WIDTH
    jmp vbuf_text

; players_mode: A = 0 (1 jugador), 1 (2 jugadores, VS) o 2 (2 jugadores, Co-Op)
players_mode:
    lda num_players
    cmp #2
    bne @one
    lda game_mode
    clc
    adc #1
    rts
@one:
    lda #0
    rts

; Instrumento y dificultad del jugador X (en blanco si no está jugando)
menu_draw_player:
    stx tmp+1
    jsr menu_draw_instrument
    ldx tmp+1
    jsr menu_draw_difficulty
    ldx tmp+1
    jmp menu_draw_fail

menu_draw_difficulty:
    jsr menu_value_ptr      ; ptr = nombre, o texto vacío
    bcc @write
    ldy player_offset,x
    lda player_save + (cur_difficulty - pstate),y
    jsr ptr_difficulty_name
@write:
    ldx player_drawn
    lda #<($2000 + MENU_DIFF_ROW * 32)
    clc
    adc menu_value_col,x
    sta addr
    lda #>($2000 + MENU_DIFF_ROW * 32)
    adc #0
    sta addr+1
    lda #MENU_VALUE_WIDTH
    jmp vbuf_text

; mark_record_dirty: hay que redibujar el récord del jugador actual
mark_record_dirty:
    ldx player
    lda menu_rec_dirty
    ora record_bit,x
    ldx game_mode
    beq @store
    ora #%11                ; Co-Op: el récord de la banda depende de la dificultad de los dos
@store:
    sta menu_rec_dirty
    rts

; menu_draw_record: el récord guardado para la canción, instrumento y dificultad
; del jugador X: "012345 ABC 5*", o "---" si no hay (en blanco si no juega)
menu_draw_record:
    jsr menu_value_ptr
    bcc @write
    lda game_mode
    beq @solo
    cpx #0                  ; Co-Op: un solo récord, el de la banda, bajo el jugador 1
    beq @band
    SET_PTR txt_empty
    jmp @write
@band:
    jsr rec_team_key
    jmp @find
@solo:
    lda player_offset,x
    tay
    lda player_save + PS_INSTRUMENT,y
    asl a
    asl a
    ora player_save + (cur_difficulty - pstate),y
@find:
    jsr rec_find
    bcs @found
    SET_PTR txt_no_record
    jmp @write
@found:
    ldx #0
@digit:
    txa
    clc
    adc #R_SCORE
    tay
    lda (rec_ptr),y
    clc
    adc #'0'
    sta numstr,x
    inx
    cpx #6
    bne @digit
    lda #' '
    sta numstr+6
    sta numstr+10
    ldx #0
@letter:
    txa
    clc
    adc #R_INI
    tay
    lda (rec_ptr),y
    sta numstr+7,x
    inx
    cpx #3
    bne @letter
    ldy #R_STARS
    lda (rec_ptr),y
    clc
    adc #'0'
    sta numstr+11
    lda #'*'
    sta numstr+12
    lda #0
    sta numstr+13
    SET_PTR numstr
@write:
    ldx player_drawn
    lda #<($2000 + MENU_REC_ROW * 32)
    clc
    adc menu_value_col,x
    sta addr
    lda #>($2000 + MENU_REC_ROW * 32)
    adc #0
    sta addr+1
    lda #MENU_REC_WIDTH
    jmp vbuf_text

; "CON FALLO" / "SIN FALLO" del jugador X
menu_draw_fail:
    jsr menu_value_ptr
    bcc @write
    ldy player_offset,x
    lda player_save + PS_NO_FAIL,y
    asl a
    tax
    lda fail_names,x
    sta ptr
    lda fail_names+1,x
    sta ptr+1
@write:
    ldx player_drawn
    lda #<($2000 + MENU_FAIL_ROW * 32)
    clc
    adc menu_value_col,x
    sta addr
    lda #>($2000 + MENU_FAIL_ROW * 32)
    adc #0
    sta addr+1
    lda #MENU_VALUE_WIDTH
    jmp vbuf_text

menu_draw_instrument:
    jsr menu_value_ptr
    bcc @write
    ldy player_offset,x
    lda player_save + PS_INSTRUMENT,y
    jsr ptr_instrument_name
@write:
    ldx player_drawn
    lda #<($2000 + MENU_INST_ROW * 32)
    clc
    adc menu_value_col,x
    sta addr
    lda #>($2000 + MENU_INST_ROW * 32)
    adc #0
    sta addr+1
    lda #MENU_VALUE_WIDTH
    jmp vbuf_text

; menu_value_ptr: X = jugador. Si no está jugando, ptr = texto vacío y
; carry = 0; si sí, carry = 1 (y X sigue siendo el jugador).
menu_value_ptr:
    stx player_drawn
    cpx num_players         ; carry = 1 si X >= num_players: no juega
    bcc @plays
    SET_PTR txt_empty
    clc
    rts
@plays:
    sec
    rts

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

; Los cursores son sprites '>' a la izquierda del valor elegido
menu_place_cursors:
    ldx menu_cursor
    lda cursor_y,x
    sta oam
    lda #'>'
    sta oam+1
    lda #0                  ; paleta de sprites 0: blanco
    sta oam+2
    lda #(MENU_VALUE_COL - 1) * 8
    sta oam+3

    lda #$FF                ; jugador 2: oculto si no juega
    ldx num_players
    cpx #2
    bne @hide2
    ldx menu_cursor2
    lda cursor_y + ITEM_INSTRUMENT,x
@hide2:
    sta oam+4
    lda #'>'
    sta oam+5
    lda #1                  ; paleta de sprites 1: naranja
    sta oam+6
    lda #(MENU_VALUE_COL2 - 1) * 8
    sta oam+7
    rts

.segment "RODATA"

cursor_y:       .byte MENU_SONG_ROW * 8 - 1, MENU_PLAYERS_ROW * 8 - 1, MENU_INST_ROW * 8 - 1, MENU_DIFF_ROW * 8 - 1, MENU_FAIL_ROW * 8 - 1
menu_value_col: .byte MENU_VALUE_COL, MENU_VALUE_COL2

instrument_names: .addr txt_guitar, txt_keys, txt_bass, txt_drums
difficulty_names: .addr txt_easy, txt_medium, txt_hard, txt_expert
players_names:    .addr txt_one_player, txt_two_players, txt_two_coop
fail_names:       .addr txt_with_fail, txt_no_fail
record_bit:       .byte %01, %10

txt_song:        .byte "CANCION", 0
txt_players:     .byte "JUGADORES", 0
txt_instrument:  .byte "INSTRUMENTO", 0
txt_difficulty:  .byte "DIFICULTAD", 0
txt_record:      .byte "RECORD", 0
txt_no_record:   .byte "---", 0
txt_fail:        .byte "FALLO", 0
txt_with_fail:   .byte "CON FALLO", 0
txt_no_fail:     .byte "SIN FALLO", 0
txt_menu_help:   .byte "START: JUGAR   B: VOLVER", 0
txt_one_player:  .byte "1 JUGADOR", 0
txt_two_players: .byte "2 JUGADORES VS", 0
txt_two_coop:    .byte "2 JUGADORES COOP", 0
txt_band:        .byte "BANDA", 0
txt_guitar:      .byte "GUITARRA", 0
txt_keys:        .byte "TECLADO", 0
txt_bass:        .byte "BAJO", 0
txt_drums:       .byte "BATERIA", 0
txt_easy:        .byte "FACIL", 0
txt_medium:      .byte "MEDIO", 0
txt_hard:        .byte "DIFICIL", 0
txt_expert:      .byte "EXPERTO", 0

.segment "CODE"
