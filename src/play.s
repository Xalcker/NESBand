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
    lda opt_fall            ; CAIDA DE NOTAS: con otra opción que AUTO, la velocidad de esa dificultad
    beq @fall_auto
    sec
    sbc #1
    sta tmp
@fall_auto:
    lda tmp
    jsr set_speed

    jsr set_layout          ; dónde va la autopista de cada jugador

    ; ESPEJO: qué bit del chart toca cada carril (los bits que mueven las notas del chart
    ; al carril de enfrente; la autopista dibuja con rev5, ver player_row_mask)
    ldx #NUM_LANES - 1
@chart_bit:
    lda lane_bit,x
    ldy opt_mirror
    beq @bit_set
    lda lane_bit_mirror,x
@bit_set:
    sta chart_bit,x
    dex
    bpl @chart_bit

    ; PRACTICA: el bucle vuelve a empezar en practice_end = (song_end / 4) * opt_practice
    jsr song_quarter        ; tmp = song_end / 4
    lda #0
    sta practice_end
    sta practice_end+1
    ldx opt_practice
    beq @no_practice
@loop_end:
    clc
    lda practice_end
    adc tmp
    sta practice_end
    lda practice_end+1
    adc tmp+1
    sta practice_end+1
    dex
    bne @loop_end
@no_practice:

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
    sta speed_ctr
    sta pad_latch
    sta pad_latch+1
    sta skip_frame          ; (practice_seek lo cambia si la práctica empieza más adelante)
    sta skip_frame+1
    lda #HIT_ROW
    sta cur_vrow
    lda #FILL_FIRST_VROW
    sta next_vrow
    jsr practice_seek       ; PRACTICA con INICIO: salta la canción hasta ese punto

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

    ; Las líneas de beat y el público siguen los tiempos de la canción: next_beat debe caer en
    ; song_frame o después (con la práctica empezando más adelante hay que saltar varios)
@beat_catch_up:
    lda next_beat
    cmp song_frame
    lda next_beat+1
    sbc song_frame+1
    bcs @beat_caught
    clc
    lda next_beat
    adc beat_frames
    sta next_beat
    bcc @beat_catch_up
    inc next_beat+1
    jmp @beat_catch_up
@beat_caught:
    jsr scene_init          ; el público baila al ritmo de estos mismos tiempos (y scene_on avisa
                            ; que ya está todo listo: song_frame, charts y escenario)

    ; --- Dibujar las 30 filas iniciales de la autopista ---
    ; next_k = FILL_FIRST_ROW + cur_row (la fila de abajo del todo; negativa si empieza la canción)
    clc
    lda #<FILL_FIRST_ROW
    adc cur_row
    sta next_k
    lda #>FILL_FIRST_ROW
    adc cur_row+1
    sta next_k+1

    ; next_k_frame = song_frame + FILL_FIRST_ROW * fpr (negativo al empezar la canción: filas de
    ; antes del cuadro 0, que van vacías). Multiplicar = restar fpr unas cuantas veces.
    lda song_frame
    sta next_k_frame
    lda song_frame+1
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
    lda #0                  ; sin llamaradas ni rayos encendidos
    sta star_hit
    ldx #FX_SLOTS - 1
@no_fx:
    sta fx_timer,x
    dex
    bpl @no_fx
    sta bolt_timer
    sta bolt_timer+1
    jsr compute_scroll
    lda #1
    sta split_on            ; desde el siguiente vblank, pantalla dividida
    jmp ppu_on

; -----------------------------------------------------------------------------
; song_quarter: tmp = song_end / 4
; -----------------------------------------------------------------------------
song_quarter:
    lda song_end+1
    lsr a
    sta tmp+1
    lda song_end
    ror a
    lsr tmp+1
    ror a
    sta tmp
    rts

; -----------------------------------------------------------------------------
; practice_seek: PRACTICA con INICIO distinto del principio (1/4, 1/2 o 3/4 de la canción).
; Deja el reloj, el scroll y la música como si la canción llevara jugándose hasta ahí:
;   - song_frame, cur_row, cur_vrow, next_vrow y row_scroll avanzan fila por fila (un cuadro
;     cae en la fila exacta: song_frame queda en un múltiplo de fpr)
;   - skip_frame = ese cuadro + PRACTICE_GRACE: los charts omiten las notas anteriores (no
;     da tiempo de tocarlas) y la autopista arranca con unos segundos limpios
;   - el motor de sonido se adelanta llamándolo cuadro por cuadro con el APU callado (la NMI y
;     la pantalla siguen apagadas, así que solo es cuestión de esperar unos segundos)
; Si no hay práctica, o empieza en el principio, no hace nada. Va antes que init_player
; (los charts leen skip_frame) y que scene_init (el público lee song_frame).
; -----------------------------------------------------------------------------
practice_seek:
    lda opt_practice
    bne @active
    rts
@active:
    ldx opt_start
    cpx opt_practice        ; no puede empezar donde termina (ni después)
    bcc @start_ok
    ldx opt_practice
    dex
@start_ok:
    txa
    bne @go
    rts
@go:
    jsr song_quarter        ; practice_start = (song_end / 4) * X
    lda #0
    sta practice_start
    sta practice_start+1
@quarters:
    clc
    lda practice_start
    adc tmp
    sta practice_start
    lda practice_start+1
    adc tmp+1
    sta practice_start+1
    dex
    bne @quarters

    ; Fila por fila, mientras la siguiente fila empiece en practice_start o antes
@row:
    clc
    lda song_frame
    adc fpr
    sta tmp
    lda song_frame+1
    adc #0
    sta tmp+1
    lda practice_start
    cmp tmp
    lda practice_start+1
    sbc tmp+1
    bcc @rows_done          ; practice_start < la siguiente fila: ya llegamos
    lda tmp
    sta song_frame
    lda tmp+1
    sta song_frame+1
    inc cur_row
    bne @row_ok
    inc cur_row+1
@row_ok:
    dec cur_vrow            ; (como advance_time: la fila de la nametable da la vuelta de 0 a 29)
    bpl @cur_ok
    lda #VROWS - 1
    sta cur_vrow
@cur_ok:
    dec next_vrow
    bpl @next_ok
    lda #VROWS - 1
    sta next_vrow
@next_ok:
    lda row_scroll
    sec
    sbc #8
    bcs @scroll_ok
    adc #VROWS * 8
@scroll_ok:
    sta row_scroll
    jmp @row

@rows_done:
    lda song_frame
    ora song_frame+1
    beq @done
    clc                     ; las notas de los primeros cuadros ya no se tocan ni se dibujan
    lda song_frame
    adc #PRACTICE_GRACE
    sta skip_frame
    lda song_frame+1
    adc #0
    sta skip_frame+1

    ; La música: update_music la arranca (y la actualiza por primera vez) en el cuadro en que
    ; song_frame llega a SONG_LEAD_IN, así que al empezar el cuadro song_frame lleva
    ; song_frame - SONG_LEAD_IN + 1 actualizaciones
    sec
    lda song_frame
    sbc #<(SONG_LEAD_IN - 1)
    sta tmp
    lda song_frame+1
    sbc #>(SONG_LEAD_IN - 1)
    sta tmp+1
    bcc @done               ; (no pasa: un cuarto de canción dura mucho más que la entrada)
    lda #0                  ; la canción 0 del archivo exportado
    jsr famistudio_music_play
    lda tmp
    ora tmp+1
    beq @music_done
@music:
    jsr famistudio_update
    lda #0
    sta APU_STATUS          ; sin sonido mientras se adelanta (el motor lo enciende en cada nota)
    lda tmp
    bne @low
    dec tmp+1
@low:
    dec tmp
    lda tmp
    ora tmp+1
    bne @music
@music_done:
    lda #%00001111          ; canales encendidos otra vez (como los deja famistudio_music_play)
    sta APU_STATUS
@done:
    rts

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
    sta failed              ; (no_fail no se toca: lo eligió el menú)
    sta life_grace
    sta life_hit_frame      ; (0: el primer acierto cae después del cuadro 128 de la autopista)
    sta star_energy         ; ni poder estelar
    sta star_active
    sta star_timer
    sta star_failed
    ldx #NUM_LANES - 1
@no_hold:
    sta hold_on,x
    dex
    bpl @no_hold
    lda #LIFE_START
    sta life
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
    beq @playing
    jmp @paused             ; (muy lejos para un bne)
@playing:

    lda tmp+1
    and #BTN_START
    beq @run
    lda #1                  ; Start: pausar
    sta paused
    jsr famistudio_music_pause
    jsr show_pause
    jmp famistudio_update

@run:
    lda opt_speed           ; VELOCIDAD 75% / 50%: cada tanto el juego se salta un cuadro entero
    beq @go                 ; (ni la canción ni las notas avanzan, y el sonido sigue donde iba)
    inc speed_ctr
    ldx opt_speed
    cpx #3
    beq @fast
    lda speed_ctr
    and speed_mask - 1,x
    bne @go
    lda pad_pressed         ; lo que presionaste en un cuadro saltado cuenta en el siguiente
    ora pad_latch
    and #<~BTN_START        ; (Start ya se atendió arriba)
    sta pad_latch
    lda pad_pressed+1
    ora pad_latch+1
    and #<~BTN_START
    sta pad_latch+1
    rts
@fast:                      ; 125%: de cada 4 cuadros, uno avanza dos pasos de juego (canción, notas y
    lda speed_ctr           ; sonido); el segundo paso no cuenta otra vez lo que se presionó
    and #%11
    bne @go
    jsr @go
    lda #0
    sta pad_pressed
    sta pad_pressed+1
@go:
    lda pad_latch
    ora pad_pressed
    sta pad_pressed
    lda pad_latch+1
    ora pad_pressed+1
    sta pad_pressed+1
    lda #0
    sta pad_latch
    sta pad_latch+1
    jsr advance_time        ; mover las notas y, si toca, preparar una fila nueva

    ldx #0                  ; cada jugador:
@player:
    jsr load_player
    lda failed
    bne @no_judge           ; quien ya perdió no juega más
    lda life_grace          ; el respiro después de un fallo se acaba
    beq @judge
    dec life_grace
@judge:
    jsr judge_lanes         ; aciertos y fallos
    jsr update_holds        ; puntos de las notas sostenidas
    jsr update_star         ; Select activa el poder estelar; la barra se vacía
@no_judge:
    jsr update_hud          ; aros y marcador
    jsr store_player
    ldx player
    inx
    cpx num_players
    bne @player

    ; ¿Terminó la partida porque alguien perdió? Con 1 jugador, él. Con 2: en VS basta con que
    ; pierda uno (gana el otro: vs_winner); en Co-Op la banda sigue mientras quede uno en pie
    ; (puede revivir al caído con poder estelar: update_star)
    lda player_save + PS_FAILED
    ldx num_players
    cpx #2
    bne @check
    ldx game_mode
    bne @both
    ora player_save + PSTATE_SIZE + PS_FAILED
    jmp @check
@both:
    and player_save + PSTATE_SIZE + PS_FAILED
@check:
    cmp #0
    beq @alive
    jmp enter_results
@alive:
    jsr update_meters       ; medidores de vida
    jsr update_fx           ; llamaradas de los aciertos
    jsr update_bolts        ; y los rayos de las notas estelares
    jsr scene_update        ; público y luces del escenario
    jsr update_music        ; motor de sonido (y silenciar a quien haya fallado)
    jsr compute_scroll

    ; PRACTICA: al llegar a practice_end la canción vuelve a empezar (sin resultados)
    lda opt_practice
    beq @not_practice
    lda song_frame
    cmp practice_end
    bne @not_practice
    lda song_frame+1
    cmp practice_end+1
    bne @not_practice
    jmp enter_play
@not_practice:

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
    lda #0                  ; paleta de sprites 0 (fuego), o la 1 (azul) si el jugador tiene el
    cpx #NUM_LANES          ; poder estelar activo; leemos su copia guardada
    bcs @second
    lda player_save + PS_STAR_ACTIVE
    jmp @palette
@second:
    lda player_save + PSTATE_SIZE + PS_STAR_ACTIVE
@palette:
    beq @attr               ; (A = 0: fuego)
    lda #1
@attr:
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

; -----------------------------------------------------------------------------
; update_bolts: el rayo que cae sobre el carril al acertar una nota estelar.
; Una columna de BOLT_LEN sprites (cada uno de 8x8, sobre el anterior) que sube
; desde el aro: un rayo largo en zigzag. Los dos dibujos del zigzag se
; alternan y se intercambian en cada cuadro para que "chispee". Hay un rayo
; por jugador (a diferencia de las llamaradas, que son una por carril).
; -----------------------------------------------------------------------------
update_bolts:
    ldx #0
@player:
    stx tmp                 ; jugador (X pasa a contar sprites más abajo)
    lda bolt_oam,x          ; Y = OAM del primer sprite de este rayo
    tay
    lda bolt_timer,x
    beq @hide
    dec bolt_timer,x
    lda bolt_x,x
    sta addr                ; posición X del rayo
    lda #FX_Y + 8 - 1       ; el de más abajo queda sobre el aro (coordenada Y = línea - 1)
    sta tmp+1
    ldx #BOLT_LEN           ; sprites por dibujar
@sprite:
    lda tmp+1
    sta oam,y
    sec
    sbc #8                  ; el siguiente va 8 px más arriba
    sta tmp+1
    txa
    clc
    adc frame_counter       ; zigzag: alterna el dibujo entre sprites vecinos y entre cuadros
    and #1
    clc
    adc #TILE_BOLT
    sta oam+1,y
    lda #1                  ; paleta de sprites 1 (blanco, cian, azul)
    sta oam+2,y
    lda addr
    sta oam+3,y
    iny
    iny
    iny
    iny
    dex
    bne @sprite
    jmp @next
@hide:
    lda #$FF
    ldx #BOLT_LEN
@hide_loop:
    sta oam,y
    iny
    iny
    iny
    iny
    dex
    bne @hide_loop
@next:
    ldx tmp
    inx
    cpx #MAX_PLAYERS
    bne @player
    rts

; -----------------------------------------------------------------------------
; update_meters: el medidor de vida de cada jugador: una columna de
; METER_SEGMENTS sprites de 8 px junto a su autopista, que se llena de abajo
; hacia arriba (el tile de cada sprite trae de 0 a 8 filas llenas). Verde con
; vida de sobra, amarillo a medias y rojo parpadeando cuando falta poco. No se
; dibuja en "sin fallo", ni de quien ya perdió.
; Lee de la copia guardada de cada jugador (player_save), sin cargarla.
; -----------------------------------------------------------------------------
METER_LOW    = LIFE_MAX / 4         ; por debajo de esto: rojo y parpadeando
METER_MID    = LIFE_MAX * 5 / 8     ; por debajo: amarillo; arriba: verde

update_meters:
    ldx #0
@player:
    stx lane                ; jugador (X pasa a contar segmentos más abajo)
    lda meter_oam,x
    tay                     ; Y = OAM del primer sprite de su medidor
    cpx num_players
    bcc @plays
    jmp @hide               ; este jugador no juega (muy lejos para un bcs)
@plays:
    lda player_offset,x     ; X = dónde empieza su copia en player_save
    tax
    lda player_save + PS_NO_FAIL,x
    ora player_save + PS_FAILED,x
    bne @hide
    lda player_save + PS_LIFE,x
    sta tmp+1               ; vida que queda por dibujar
    cmp #METER_LOW + 1
    bcs @steady
    lda frame_counter       ; poca vida: parpadea (8 cuadros sí, 8 no)
    and #%00001000
    bne @hide
@steady:
    ; paleta según el nivel: 2 = rojo, 0 = amarillo (fuego), 3 = verde
    lda tmp+1
    cmp #METER_LOW + 1
    bcs @not_low
    lda #2
    bne @palette
@not_low:
    cmp #METER_MID
    bcs @high
    lda #0
    beq @palette
@high:
    lda #3
@palette:
    sta addr                ; atributo de los sprites
    lda num_players         ; posición X: meter_x[(num_players - 1) * 2 + jugador]
    sec
    sbc #1
    asl a
    clc
    adc lane
    tax
    lda meter_x,x
    sta addr+1
    lda #FX_Y - 1           ; coordenada Y del segmento de abajo (su borde de arriba es FX_Y)
    sta tmp
    ldx #0                  ; X = número de segmento (0 = el de abajo)
@segment:
    lda tmp+1               ; filas llenas de este segmento = min(vida que queda, 8)
    cmp #8
    bcc @fill
    lda #8
@fill:
    sta ptr
    clc
    adc #TILE_METER
    sta oam+1,y
    lda tmp+1               ; la vida que queda para los segmentos de arriba
    sec
    sbc ptr
    sta tmp+1
    lda tmp
    sta oam,y
    sec
    sbc #8
    sta tmp
    lda addr
    sta oam+2,y
    lda addr+1
    sta oam+3,y
    iny
    iny
    iny
    iny
    inx
    cpx #METER_SEGMENTS
    bne @segment
    jmp @next
@hide:
    lda #$FF
    ldx #METER_SEGMENTS
@hide_loop:
    sta oam,y
    iny
    iny
    iny
    iny
    dex
    bne @hide_loop
@next:
    ldx lane
    inx
    cpx #MAX_PLAYERS
    beq @done
    jmp @player             ; (muy lejos para un bne)
@done:
    rts

; Dónde empieza en la OAM el rayo y el medidor de cada jugador
bolt_oam:  .byte BOLT_SPRITE * 4, (BOLT_SPRITE + BOLT_LEN) * 4
meter_oam: .byte METER_SPRITE * 4, (METER_SPRITE + METER_SEGMENTS) * 4
; X del medidor, por (jugadores - 1) * 2 + jugador: con uno, a la derecha de la
; autopista (columna 22); con dos, en el hueco del centro, uno junto al otro
meter_x:   .byte 22 * 8, 0, 14 * 8, 18 * 8

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
; VELOCIDAD: el juego se salta el cuadro cuando (speed_ctr AND máscara) = 0: 75% -> 1 de cada 4, 50% -> 1 de cada 2
speed_mask: .byte %11, %01
.segment "CODE"
