; =============================================================================
; play.s - El estado de juego: preparar la canción, cada cuadro, pausa y fin
;
; Start pausa; en pausa, Start continúa y Select regresa al menú.
; =============================================================================

PAUSE_SPRITE = 0        ; en el juego no hay otros sprites (aros y marcador son fondo)
PAUSE_X      = 108
PAUSE_Y      = 104

; =============================================================================
; enter_play: deja todo listo para empezar la canción elegida en el menú
; =============================================================================
enter_play:
    jsr ppu_off
    lda #STATE_PLAY
    sta game_state
    ldx #PALETTES_PLAY
    jsr load_palettes

    ; --- Datos de la canción (de su ficha, ver SONG_... en main.s) ---
    ldy #SONG_MUSIC         ; el motor de sonido, con la música de esta canción
    lda (song_ptr),y
    tax
    iny
    lda (song_ptr),y
    tay
    jsr music_init
    lda #SFX_ACEPTAR        ; suena mientras bajan las primeras filas
    jsr play_sfx

    ldy #SONG_END
    lda (song_ptr),y
    sta song_end
    clc
    adc #<RESULTS_DELAY
    sta results_frame
    iny
    lda (song_ptr),y
    sta song_end+1
    adc #>RESULTS_DELAY
    sta results_frame+1

    ; Líneas de beat: cuadros por tiempo y el primer tiempo, retrocedido de
    ; tiempo en tiempo hasta el primero que cae en el cuadro 0 o después (así
    ; también hay líneas antes de que empiece la música)
    ldy #SONG_BEAT_FRAMES
    lda (song_ptr),y
    sta beat_frames
    iny
    lda (song_ptr),y        ; SONG_FIRST_BEAT
    sta next_beat
    iny
    lda (song_ptr),y
    sta next_beat+1
@beat_back:
    lda next_beat           ; mientras next_beat >= beat_frames: next_beat -= beat_frames
    cmp beat_frames
    lda next_beat+1
    sbc #0
    bcc @beat_ready
    sec
    lda next_beat
    sbc beat_frames
    sta next_beat
    lda next_beat+1
    sbc #0
    sta next_beat+1
    jmp @beat_back
@beat_ready:

    ; Velocidad: la de la dificultad más alta entre los jugadores
    lda #0
    sta tmp
    ldx #0
@max_difficulty:
    ldy player_offset,x
    lda player_save + (cur_difficulty - pstate),y
    cmp tmp
    bcc @not_higher
    sta tmp
@not_higher:
    inx
    cpx num_players
    bne @max_difficulty
    lda tmp
    jsr set_speed

    jsr set_layout          ; dónde va la autopista de cada jugador

    ; --- Cada jugador: su chart, marcador y carriles ---
    ldx #0
@player:
    jsr load_player
    jsr init_player
    jsr store_player
    ldx player
    inx
    cpx num_players
    bne @player

    ; --- Variables de tiempo y scroll (las comparten todos) ---
    lda #0
    sta paused
    sta song_frame
    sta song_frame+1
    sta cur_row
    sta cur_row+1
    sta frame_in_row
    sta rowpix
    sta row_scroll
    sta row_pending
    sta erase_count
    sta nmi_ready
    lda #HIT_ROW
    sta cur_vrow

    ; --- Dibujar las 30 filas iniciales de la autopista ---
    lda #<FILL_FIRST_ROW
    sta next_k
    lda #>FILL_FIRST_ROW
    sta next_k+1
    lda #FILL_FIRST_VROW
    sta next_vrow

    ; next_k_frame = FILL_FIRST_ROW * fpr (es negativo: filas de antes del
    ; cuadro 0, que van vacías). Multiplicar = restar fpr unas cuantas veces.
    lda #0
    sta next_k_frame
    sta next_k_frame+1
    ldx #-FILL_FIRST_ROW
@first_frame:
    sec
    lda next_k_frame
    sbc fpr
    sta next_k_frame
    lda next_k_frame+1
    sbc #0
    sta next_k_frame+1
    dex
    bne @first_frame

    lda #VROWS
    sta fill_count
@fill:
    jsr build_row           ; arma row_buf y row_addr
    bit PPUSTATUS
    lda row_addr+1
    sta PPUADDR
    lda row_addr
    sta PPUADDR
    ldx #0
@copy:
    lda row_buf,x
    sta PPUDATA
    inx
    cpx #32
    bne @copy
    jsr step_next_row
    dec fill_count
    bne @fill

    jsr write_attributes
    jsr draw_strip          ; aros y marcador, en la nametable de $2400

    jsr hide_sprites
    lda #0                  ; sin llamaradas encendidas
    ldx #FX_SLOTS - 1
@no_fx:
    sta fx_timer,x
    dex
    bpl @no_fx
    jsr compute_scroll
    lda #1
    sta split_on            ; desde el siguiente vblank, pantalla dividida
    jmp ppu_on

; -----------------------------------------------------------------------------
; init_player: prepara al jugador cargado en pstate para empezar la canción
; -----------------------------------------------------------------------------
init_player:
    lda cur_instrument      ; guitarra, teclado, bajo, batería = canales 0, 1, 2, 3
    sta player_channel

    ; chart_start = charts[instrumento * 4 + dificultad]
    lda cur_instrument
    asl a
    asl a
    clc
    adc cur_difficulty
    asl a                   ; 2 bytes por dirección
    clc
    adc #SONG_CHARTS
    tay
    lda (song_ptr),y
    sta chart_start
    iny
    lda (song_ptr),y
    sta chart_start+1

    ; Marcador y estadísticas en ceros
    ldx #5
    lda #0
@clear_score:
    sta score_digits,x
    dex
    bpl @clear_score
    sta combo_digits
    sta combo_digits+1
    sta combo_digits+2
    sta notes_hit
    sta notes_hit+1
    sta combo_bin
    sta combo_bin+1
    sta max_combo
    sta max_combo+1
    sta score_units
    sta score_units+1
    sta player_muted
    sta tail_mask           ; sin colas dibujadas ni notas sostenidas
    ldx #NUM_LANES - 1
@no_hold:
    sta hold_on,x
    dex
    bpl @no_hold
    lda #1
    sta multiplier
    jsr count_notes

    ; Cada carril busca su primera nota
    ldx #0
@lanes:
    jsr chart_first
    jsr lane_seek
    inx
    cpx #NUM_LANES
    bne @lanes

    ; El dibujo lleva su propio puntero y cuadro
    jsr chart_first
    lda ptr
    sta render_ptr
    lda ptr+1
    sta render_ptr+1
    lda seek_frame
    sta render_frame
    lda seek_frame+1
    sta render_frame+1
    rts

; -----------------------------------------------------------------------------
; count_notes: notes_total = cuántas gemas tiene el chart (un acorde de 2 son 2)
; -----------------------------------------------------------------------------
count_notes:
    lda chart_start
    sta ptr
    lda chart_start+1
    sta ptr+1
    lda #0
    sta notes_total
    sta notes_total+1
@entry:
    ldy #1
    lda (ptr),y             ; carriles
    bmi @release            ; fin de cola (o el fin del chart): no es una nota
    and #%00011111          ; solo los bits de carriles
@bits:
    lsr a                   ; un carril -> carry
    bcc @no_gem
    inc notes_total
    bne @no_gem
    inc notes_total+1
@no_gem:
    cmp #0
    bne @bits
@next:
    clc
    lda ptr
    adc #CHART_ENTRY
    sta ptr
    bcc @entry
    inc ptr+1
    jmp @entry
@release:
    cmp #CHART_END
    bne @next               ; fin de cola: no cuenta
@done:
    rts

; =============================================================================
; play_update: un cuadro de juego
; =============================================================================
play_update:
    ; Start/Select de cualquiera de los dos controles
    lda pad_pressed
    ora pad_pressed+1
    sta tmp+1
    lda paused
    bne @paused

    lda tmp+1
    and #BTN_START
    beq @run
    lda #1                  ; Start: pausar
    sta paused
    jsr famistudio_music_pause
    jsr show_pause
    jmp famistudio_update

@run:
    jsr advance_time        ; mover las notas y, si toca, preparar una fila nueva

    ldx #0                  ; cada jugador:
@player:
    jsr load_player
    jsr judge_lanes         ; aciertos y fallos
    jsr update_holds        ; puntos de las notas sostenidas
    jsr update_hud          ; aros y marcador
    jsr store_player
    ldx player
    inx
    cpx num_players
    bne @player

    jsr update_fx           ; llamaradas de los aciertos
    jsr update_music        ; motor de sonido (y silenciar a quien haya fallado)
    jsr compute_scroll

    ; ¿Ya terminó? (un segundo después de que se detiene la música)
    lda song_frame
    cmp results_frame
    bne @done
    lda song_frame+1
    cmp results_frame+1
    bne @done
    jmp enter_results
@done:
    rts

@paused:
    lda tmp+1
    and #BTN_START
    beq @no_resume
    lda #0                  ; Start: continuar
    sta paused
    jsr famistudio_music_pause
    jmp hide_pause
@no_resume:
    lda tmp+1
    and #BTN_SELECT
    beq @still_paused
    jmp enter_menu          ; Select: salir al menú
@still_paused:
    ; El motor sigue corriendo en pausa (con el volumen en 0) pero la canción
    ; no avanza, así que al continuar sigue sincronizada con las notas
    jmp famistudio_update

; -----------------------------------------------------------------------------
; update_fx: dibuja las llamaradas encendidas y avanza su animación.
; Cada ranura usa 2 sprites apilados (8 bytes de OAM). Como van uno sobre el
; otro, cada llamarada ocupa un solo sprite por línea: con 5 carriles no se
; acerca al límite de 8 por línea (dos jugadores con acordes sí lo pueden
; pasar: entonces el PPU omite algunas, solo parpadea el efecto).
; El dibujo es (FX_FRAMES - timer) / 2: 0 estallido, 1 llama, 2 llama baja,
; 3 chispas.
; -----------------------------------------------------------------------------
update_fx:
    ldx #0
@slot:
    txa
    asl a
    asl a
    asl a                   ; 8 bytes de OAM por ranura
    clc
    adc #FX_SPRITE * 4
    tay
    lda fx_timer,x
    beq @hide
    sta tmp
    dec fx_timer,x
    txa                     ; "semitransparente": cada llamarada se dibuja un cuadro sí y uno no,
    clc                     ; y las de ranuras vecinas se alternan. Así casi nunca hay más de 8
    adc frame_counter       ; sprites en una línea (con 2 jugadores el PPU descartaba siempre los
    and #1                  ; del jugador 2)
    bne @hide
    lda #FX_FRAMES
    sec
    sbc tmp
    and #%11111110          ; / 2 x 2: los tiles de cada dibujo son una pareja
    clc
    adc #TILE_FX
    sta oam+1,y             ; mitad de arriba
    adc #1                  ; (carry = 0)
    sta oam+5,y             ; mitad de abajo
    lda #FX_Y - 1           ; la coordenada Y del sprite es la línea - 1
    sta oam,y
    lda #FX_Y + 8 - 1
    sta oam+4,y
    lda #0                  ; paleta de sprites 0, sin voltear
    sta oam+2,y
    sta oam+6,y
    lda fx_x,x
    sta oam+3,y
    sta oam+7,y
    jmp @next
@hide:
    lda #$FF
    sta oam,y
    sta oam+4,y
@next:
    inx
    cpx #FX_SLOTS
    bne @slot
    rts

; "PAUSA" con sprites (el fondo de la autopista se está desplazando y es
; más fácil poner el letrero encima)
show_pause:
    ldx #0
    ldy #PAUSE_SPRITE * 4
@loop:
    lda #PAUSE_Y - 1
    sta oam,y
    lda txt_pause,x
    sta oam+1,y
    lda #0
    sta oam+2,y
    txa
    asl a
    asl a
    asl a
    adc #PAUSE_X            ; (carry = 0)
    sta oam+3,y
    iny
    iny
    iny
    iny
    inx
    cpx #5
    bne @loop
    rts

hide_pause:
    lda #$FF
    ldy #PAUSE_SPRITE * 4
    ldx #5
@loop:
    sta oam,y
    iny
    iny
    iny
    iny
    dex
    bne @loop
    rts

.segment "RODATA"
txt_pause: .byte "PAUSA"
.segment "CODE"
