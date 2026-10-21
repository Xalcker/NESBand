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
    lda #1                  ; NTSC
    jsr famistudio_init

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

    ldy #SONG_BEAT_ROWS
    lda (song_ptr),y
    sta beat_rows
    ldy #SONG_FIRST_BEAT
    lda (song_ptr),y
    sta first_beat_row

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

    ; --- Variables de tiempo y scroll ---
    lda #0
    sta paused
    sta player_muted
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

    ; --- Marcador y estadísticas en ceros ---
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
    lda #1
    sta multiplier
    jsr count_notes

    ; --- Cada carril busca su primera nota ---
    ldx #0
@lanes:
    jsr chart_first
    jsr lane_seek
    inx
    cpx #NUM_LANES
    bne @lanes

    ; --- Dibujar las 60 filas iniciales de la autopista ---
    jsr chart_first         ; el dibujo lleva su propio puntero y cuadro
    lda ptr
    sta render_ptr
    lda ptr+1
    sta render_ptr+1
    lda seek_frame
    sta render_frame
    lda seek_frame+1
    sta render_frame+1
    lda #<FILL_FIRST_ROW
    sta next_k
    lda #>FILL_FIRST_ROW
    sta next_k+1
    lda #FILL_FIRST_VROW
    sta next_vrow

    ; beat_count = (first_beat_row - FILL_FIRST_ROW) mod beat_rows
    ; (FILL_FIRST_ROW es negativo, así que restarlo es sumar; el módulo se
    ; saca restando beat_rows mientras se pueda)
    lda first_beat_row
    sec
    sbc #<FILL_FIRST_ROW
@mod:
    cmp beat_rows
    bcc @mod_done
    sbc beat_rows           ; (carry = 1 por el cmp)
    jmp @mod
@mod_done:
    sta beat_count

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
    jsr compute_scroll
    lda #1
    sta split_on            ; desde el siguiente vblank, pantalla dividida
    jmp ppu_on

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
    cmp #CHART_END
    beq @done               ; fin del chart
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
    clc
    lda ptr
    adc #CHART_ENTRY
    sta ptr
    bcc @entry
    inc ptr+1
    jmp @entry
@done:
    rts

; =============================================================================
; play_update: un cuadro de juego
; =============================================================================
play_update:
    lda paused
    bne @paused

    lda pressed
    and #BTN_START
    beq @run
    lda #1                  ; Start: pausar
    sta paused
    jsr famistudio_music_pause
    jsr show_pause
    jmp famistudio_update

@run:
    jsr advance_time        ; mover las notas y, si toca, preparar una fila nueva
    jsr judge_lanes         ; aciertos y fallos
    jsr update_music        ; motor de sonido (y silenciar si fallaste)
    jsr update_hud          ; aros y marcador
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
    lda pressed
    and #BTN_START
    beq @no_resume
    lda #0                  ; Start: continuar
    sta paused
    jsr famistudio_music_pause
    jmp hide_pause
@no_resume:
    lda pressed
    and #BTN_SELECT
    beq @still_paused
    jmp enter_menu          ; Select: salir al menú
@still_paused:
    ; El motor sigue corriendo en pausa (con el volumen en 0) pero la canción
    ; no avanza, así que al continuar sigue sincronizada con las notas
    jmp famistudio_update

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
