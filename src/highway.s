; =============================================================================
; highway.s - La autopista que se desplaza
;
; IDEA CENTRAL: las notas NO son sprites. El NES solo puede mostrar 8 sprites
; por línea horizontal, y un acorde de 5 gemas de 16 px ya serían 10. Así que
; las gemas se dibujan en el FONDO (la nametable) y lo que se mueve es el
; scroll vertical: toda la autopista "baja" junta.
;
; La autopista es un rollo de 30 filas (240 px) en la nametable de $2000:
; con mirroring vertical, debajo de la fila 29 el PPU vuelve a la fila 0.
; Arriba de la franja fija se ven 26 filas; en las que sobran vamos dibujando
; las que vienen, antes de que aparezcan arriba.
;
; Relación entre fila del chart (k) y fila de la nametable (vrow):
;     vrow = (HIT_ROW - k) mod 30
; Las filas más adelante en la canción quedan más arriba. Cuando cur_row
; avanza, el scroll baja 8 pixeles y todo se desliza hacia abajo.
; =============================================================================

; Cada autopista: 5 carriles de 2 tiles (16 px) a partir de la columna
; player_base del jugador (siempre par), y un borde a la derecha:
;   [borde+izq][der] [borde+izq][der] ... [borde]
; Los 16 px hacen que cada carril coincida con la cuadrícula de atributos
; del NES (cuadros de 16x16 que eligen la paleta), y así cada carril tiene
; su propio color. Con 1 jugador la autopista va al centro; con 2, una a
; cada lado (ver set_layout).
LANE_TILES     = 2
HIGHWAY_TILES  = NUM_LANES * LANE_TILES     ; sin contar el borde derecho

; -----------------------------------------------------------------------------
; advance_time: avanza un cuadro el reloj de la canción
; -----------------------------------------------------------------------------
advance_time:
    inc song_frame
    bne @frame_ok
    inc song_frame+1
@frame_ok:
    inc frame_in_row
    lda frame_in_row
    cmp fpr                 ; cuadros por fila: depende de la dificultad (set_speed)
    bcc @same_row

    ; --- Empieza una fila nueva ---
    lda #0
    sta frame_in_row

    inc cur_row
    bne @row_ok
    inc cur_row+1
@row_ok:
    ; cur_vrow = cur_vrow - 1, dando la vuelta de 0 a 29
    dec cur_vrow
    bpl @vrow_ok
    lda #VROWS - 1
    sta cur_vrow
@vrow_ok:
    ; row_scroll = row_scroll - 8, dando la vuelta de 0 a 232
    lda row_scroll
    sec
    sbc #8
    bcs @scroll_ok
    adc #VROWS * 8          ; quedó negativo: + 240 (el carry está en 0)
@scroll_ok:
    sta row_scroll
    ; Preparar la fila que está por aparecer arriba (la NMI la copiará)
    jsr build_row
    lda #1
    sta row_pending
    jsr step_next_row

@same_row:
    lda frame_in_row        ; cuántos pixeles ha bajado la fila (tabla de esta velocidad)
    clc
    adc rowpix_base
    tax
    lda rowpix_table,x
    sta rowpix
    rts

; -----------------------------------------------------------------------------
; set_speed: A = dificultad (0-3) -> velocidad de la autopista.
; Más difícil = menos cuadros por fila = las notas bajan más rápido y se ven
; venir con menos anticipación (como en Rock Band).
; -----------------------------------------------------------------------------
set_speed:
    tax
    lda speed_frames_per_row,x
    sta fpr
    lsr a
    sta half_row            ; fpr / 2: para redondear a la fila más cercana
    lda fpr
    asl a
    asl a
    asl a
    sta fpr8                ; fpr * 8 (ver erase_gem)
    lda speed_rowpix_base,x
    sta rowpix_base
    rts

;                       fácil  medio  difícil  experto
speed_frames_per_row: .byte 6, 5,     4,       3
speed_rowpix_base:    .byte 12, 7,    3,       0       ; dónde empieza su tabla en rowpix_table

; Cuántos pixeles ha bajado una fila según el cuadro dentro de ella:
; round(cuadro * 8 / cuadros_por_fila), una tabla por velocidad
.macro ROWPIX_FOR frames
    .repeat frames, i
        .byte (i * 16 + frames) / (2 * frames)
    .endrepeat
.endmacro
rowpix_table:
    ROWPIX_FOR 3            ; base 0
    ROWPIX_FOR 4            ; base 3
    ROWPIX_FOR 5            ; base 7
    ROWPIX_FOR 6            ; base 12

; -----------------------------------------------------------------------------
; step_next_row: pasa a la siguiente fila por dibujar: next_k + 1,
; next_vrow - 1 y su cuadro next_k_frame + fpr
; -----------------------------------------------------------------------------
step_next_row:
    inc next_k
    bne @k_ok
    inc next_k+1
@k_ok:
    dec next_vrow
    bpl @vrow_ok
    lda #VROWS - 1
    sta next_vrow
@vrow_ok:
    clc
    lda next_k_frame
    adc fpr
    sta next_k_frame
    bcc @done
    inc next_k_frame+1
@done:
    rts

; -----------------------------------------------------------------------------
; build_row: arma en row_buf los 32 tiles de la fila next_k del chart (con
; la autopista de cada jugador), y en row_addr la dirección de next_vrow.
;
; Una fila abarca fpr cuadros: los de [row_lo, row_hi), centrados en
; next_k_frame. Una nota se dibuja en la fila cuya ventana contiene su cuadro.
; -----------------------------------------------------------------------------
build_row:
    ; 0) La ventana de cuadros de esta fila
    sec
    lda next_k_frame
    sbc half_row
    sta row_lo
    lda next_k_frame+1
    sbc #0
    sta row_lo+1
    clc
    lda row_lo
    adc fpr
    sta row_hi
    lda row_lo+1
    adc #0
    sta row_hi+1

    ; 1) ¿Esta fila lleva la línea horizontal del beat? Sí, si el siguiente
    ;    tiempo de la canción (next_beat) cae dentro de su ventana.
    ldx #TILE_EDGE
    ldy #TILE_BLANK
    lda row_lo+1
    bmi @no_beat            ; antes del cuadro 0: sin líneas
@beat_seek:
    lda next_beat           ; mientras next_beat < row_lo, el siguiente tiempo
    cmp row_lo
    lda next_beat+1
    sbc row_lo+1
    bcs @beat_check
    clc
    lda next_beat
    adc beat_frames
    sta next_beat
    bcc @beat_seek
    inc next_beat+1
    jmp @beat_seek
@beat_check:
    lda next_beat           ; ¿next_beat < row_hi?
    cmp row_hi
    lda next_beat+1
    sbc row_hi+1
    bcs @no_beat
    ldx #TILE_EDGE_BEAT
    ldy #TILE_BEAT
@no_beat:
    stx edge_tile
    sty inner_tile

    ; 2) El fondo de la fila: el escenario de los costados (scene.s); en la autopista, vacío.
    ; scene_rows trae 3 filas por distribución (1 jugador, 2 jugadores) de 32 columnas;
    ; cuál toca depende de la fila de la nametable: el dibujo se repite cada 3 filas.
    ldx next_vrow
    lda scene_phase_of_vrow,x
    asl a
    asl a
    asl a
    asl a
    asl a                   ; fase * 32
    ldx num_players
    cpx #2
    bcc @layout
    adc #3 * 32 - 1         ; 2 jugadores: sus 3 filas van después (el carry está en 1)
@layout:
    tay
    ldx #0
@clear:
    lda scene_rows,y
    sta row_buf,x
    iny
    inx
    cpx #32
    bne @clear

    ; 3) La autopista de cada jugador
    ldx #0
@player:
    jsr load_player
    jsr player_row_mask
    jsr draw_player_lanes
    jsr store_player
    ldx player
    inx
    cpx num_players
    bne @player

    ; 4) Dirección de VRAM
    lda next_vrow
    jsr vrow_to_addr
    lda addr
    sta row_addr
    lda addr+1
    sta row_addr+1
    rts

; -----------------------------------------------------------------------------
; player_row_mask: row_mask = carriles del jugador actual con nota en la
; ventana [row_lo, row_hi) de la fila que se está armando
;
; También lleva las colas de las notas sostenidas (tail_mask: los carriles que
; ya tienen una cola abierta en lo dibujado). Las entradas de la ventana la
; abren (nota con CHART_SUSTAIN) o la cierran (entrada CHART_RELEASE). La fila
; de la nota lleva la gema, las siguientes llevan cola, y la fila donde termina
; ya no. Al final quedan tail_draw (carriles con cola en esta fila) y
; tail_mask actualizado para la fila siguiente.
; -----------------------------------------------------------------------------
player_row_mask:
    lda #0
    sta row_mask
    sta row_star
    sta tail_add
    sta tail_rem
    lda row_lo+1
    bmi @have_mask          ; ventana antes del cuadro 0: no hay notas

    ; El chart está ordenado por tiempo. Saltamos las entradas de antes de la
    ; ventana [row_lo, row_hi) y juntamos los carriles de las que caen en ella
    ; (una nota puede compartir fila con una entrada de relleno, sin carriles).
@seek:
    ldy #1
    lda (render_ptr),y      ; carriles
    cmp #CHART_END
    beq @have_mask          ; fin del chart: no hay más notas
    lda render_frame        ; ¿render_frame < row_lo? ya pasó
    cmp row_lo
    lda render_frame+1
    sbc row_lo+1
    bcc @skip
    lda render_frame        ; ¿render_frame >= row_hi? es más adelante: terminamos
    cmp row_hi
    lda render_frame+1
    sbc row_hi+1
    bcs @have_mask
    ldy #1                  ; dentro de la ventana
    lda (render_ptr),y
    bmi @release            ; fin de cola
    and #%00011111          ; nota: sumamos sus carriles
    ora row_mask
    sta row_mask
    lda (render_ptr),y
    and #CHART_STAR
    beq @not_star           ; nota de una frase estelar: su gema es una estrella
    lda (render_ptr),y
    and #%00011111
    ora row_star
    sta row_star
@not_star:
    lda cur_instrument      ; batería: el bit $40 es un platillo, no una cola (no se abre cola)
    cmp #INSTR_DRUMS
    beq @skip
    lda (render_ptr),y
    and #CHART_SUSTAIN
    beq @skip
    lda (render_ptr),y      ; con cola: sus carriles la abren
    and #%00011111
    ora tail_add
    sta tail_add
    jmp @skip
@release:
    and #%00011111          ; los carriles que sueltan: su cola termina en esta fila
    ora tail_rem
    sta tail_rem
@skip:
    ; render_ptr a la siguiente entrada, y render_frame suma su distancia
    clc
    lda render_ptr
    adc #CHART_ENTRY
    sta render_ptr
    bcc @no_carry
    inc render_ptr+1
@no_carry:
    ldy #0
    lda (render_ptr),y
    clc
    adc render_frame
    sta render_frame
    bcc @seek
    inc render_frame+1
    jmp @seek

@have_mask:
    lda mirror_on           ; ESPEJO: el chart dice carril 0 y se dibuja en el 4 (y al revés)
    beq @not_mirrored
    ldx row_mask
    lda rev5,x
    sta row_mask
    ldx row_star
    lda rev5,x
    sta row_star
    ldx tail_add
    lda rev5,x
    sta tail_add
    ldx tail_rem
    lda rev5,x
    sta tail_rem
@not_mirrored:
    lda tail_rem            ; cola de esta fila = las abiertas menos las que terminan aquí
    eor #$FF
    and tail_mask
    sta tail_draw
    ora tail_add            ; y para la siguiente fila, más las que abren aquí
    sta tail_mask
    rts

; -----------------------------------------------------------------------------
; draw_player_lanes: dibuja en row_buf los carriles del jugador actual:
; borde + interior, y la gema donde row_mask lo diga
; -----------------------------------------------------------------------------
draw_player_lanes:
    lda #0
    sta lane
@lane:
    jsr lane_column
    tax                     ; X = columna donde empieza el carril
    lda edge_tile
    sta row_buf,x
    lda inner_tile
    sta row_buf+1,x
    ldy lane
    lda drum_look
    bne @drum_lane          ; batería: pads, y la barra del bombo (más abajo)
    lda row_mask
    and lane_bit,y
    bne @gem
    lda tail_draw           ; sin gema: ¿pasa una cola por aquí?
    and lane_bit,y
    beq @next_lane
    lda lane_tail,y         ; mitad izquierda de la cola; la derecha es el tile anterior
    ldy edge_tile
    cpy #TILE_EDGE_BEAT
    bne @tail_tiles
    clc
    adc #TAIL_BEAT          ; esta fila lleva la línea del beat
@tail_tiles:
    sta row_buf,x
    sec
    sbc #1
    sta row_buf+1,x
    jmp @next_lane
@gem:
    lda row_star
    and lane_bit,y
    bne @star_gem
    lda lane_gem,y          ; mitad izquierda de la gema (con el borde)
    jmp @gem_tiles
@star_gem:
    lda lane_star,y         ; la de las frases de poder estelar tiene forma de diamante
@gem_tiles:
    sta row_buf,x
    clc
    adc #1                  ; la mitad derecha es el tile siguiente
    sta row_buf+1,x
    jmp @next_lane

    ; --- Batería --------------------------------------------------------------------------------
    ; Los 4 pads (rojo, amarillo, azul, verde) son gemas como las de siempre, todas del color 2 de su
    ; paleta. El bombo (carril 4) no es una gema sino una barra naranja que cruza la autopista entera:
    ; en la fila de un bombo, cada carril que no tenga la gema de un pad lleva un tramo de barra
    ; (TILE_KICK, color 3 de cada paleta = el mismo naranja en todas: ver palettes). Si el bombo
    ; cae junto con un pad (un acorde), la gema del pad queda encima de la barra.
@drum_lane:
    cpy #4
    beq @kick_lane          ; el carril del bombo: solo tiene la barra
    lda row_mask
    and lane_bit,y
    bne @drum_gem           ; un pad con nota: su gema
    lda row_mask            ; sin gema: ¿hay bombo en esta fila?
    and #%10000
    beq @next_lane
    bne @bar                ; (siempre)
@kick_lane:
    lda row_mask
    and #%10000
    beq @next_lane
@bar:
    lda #TILE_KICK          ; mitad izquierda (con el borde del carril)
    sta row_buf,x
    lda #TILE_KICK - 1      ; y la derecha es el tile anterior (como en las colas)
    sta row_buf+1,x
    jmp @next_lane
@drum_gem:
    lda row_star
    and lane_bit,y
    bne @drum_star
    lda #TILE_GEM_A
    jmp @gem_tiles
@drum_star:
    lda #TILE_STAR_A
    jmp @gem_tiles
@next_lane:
    inc lane
    lda lane
    cmp #NUM_LANES
    beq @lanes_done
    jmp @lane               ; (el bloque de la batería alargó el lazo: ya no alcanza un salto corto)
@lanes_done:

    ldx player              ; borde derecho del último carril
    lda player_base,x
    clc
    adc #HIGHWAY_TILES
    tax
    lda edge_tile
    sta row_buf,x
    rts

; lane_column: A = columna donde empieza el carril `lane` del jugador actual
;              = player_base + lane * 2
lane_column:
    ldy lane
    lda drum_look
    beq @plain
    lda drum_slot,y         ; batería: la columna de cada carril, en el orden de Rock Band
    tay
@plain:
    ldx player
    tya
    asl a
    clc
    adc player_base,x
    rts

; -----------------------------------------------------------------------------
; set_layout: dónde va la autopista de cada jugador, según num_players.
; Las columnas son pares para que cada carril caiga en un cuadro de atributos.
; -----------------------------------------------------------------------------
set_layout:
    ldx num_players
    lda layout_p1-1,x
    sta player_base
    lda layout_p2-1,x
    sta player_base+1
    rts

;               1 jugador  2 jugadores
layout_p1: .byte 10,        2       ; columnas 10-20 (centro) / 2-12 (izquierda)
layout_p2: .byte 0,         20      ; -               / 20-30 (derecha)

; -----------------------------------------------------------------------------
; vrow_to_addr: A = fila de la autopista (0..29) -> addr = $2000 + fila * 32
; -----------------------------------------------------------------------------
vrow_to_addr:
    ldx #$20
    stx addr+1
    pha
    asl a                   ; byte bajo = (fila mod 8) * 32
    asl a
    asl a
    asl a
    asl a
    sta addr
    pla
    lsr a                   ; byte alto += fila / 8
    lsr a
    lsr a
    clc
    adc addr+1
    sta addr+1
    rts

; -----------------------------------------------------------------------------
; compute_scroll: scroll_y = row_scroll - rowpix, dando la vuelta en 240
; -----------------------------------------------------------------------------
compute_scroll:
    lda row_scroll
    sec
    sbc rowpix
    bcs @ok
    adc #VROWS * 8          ; quedó negativo: + 240 (el carry está en 0)
@ok:
    sta scroll_y
    lda #0
    sta scroll_nt           ; siempre la nametable de $2000
    rts

; -----------------------------------------------------------------------------
; write_attributes: asigna la paleta de cada carril en la autopista ($2000)
; y en la franja fija ($2400), para que aros y gemas tengan el color del
; carril. Como cada carril es una columna completa, todas las filas de
; atributos son iguales: se calcula una (attr_row) y se repite.
;
; Un byte de atributos cubre 32x32 px en 4 cuadros de 16x16 (2 bits cada uno):
;   bits 0-1 arriba-izq, 2-3 arriba-der, 4-5 abajo-izq, 6-7 abajo-der
; -----------------------------------------------------------------------------
write_attributes:
    ; 1) Paleta de cada columna de 16 px: la 3 (escenario) por default, la del carril donde hay uno
    lda #3
    ldx #15
@clear:
    sta attr_cols,x
    dex
    bpl @clear
    ldx #0
@player:
    stx player
    lda #0
    sta lane
@lane:
    jsr lane_column         ; columna del carril / 2 = su columna de 16 px
    lsr a
    tax
    ldy lane
    lda drum_look
    beq @plain_palette
    lda drum_palette,y      ; batería: una paleta para cada pad (ver palettes en main.s)
    jmp @palette_set
@plain_palette:
    lda lane_palette,y
@palette_set:
    sta attr_cols,x
    inc lane
    lda lane
    cmp #NUM_LANES
    bne @lane
    ldx player
    inx
    cpx num_players
    bne @player

    ; 2) attr_row: cada byte junta dos columnas de 16 px (izquierda y derecha),
    ;    repetidas arriba y abajo
    ldx #0                  ; byte (0..7)
@byte:
    txa
    asl a
    tay                     ; Y = columna de 16 px de la izquierda
    lda attr_cols+1,y       ; derecha -> bits 2-3 y 6-7
    asl a
    asl a
    ora attr_cols,y         ; izquierda -> bits 0-1 y 4-5
    sta tmp
    asl a
    asl a
    asl a
    asl a
    ora tmp
    sta attr_row,x
    inx
    cpx #8
    bne @byte

    ; 3) Las dos tablas de atributos
    lda #$23
    jsr @one_table
    lda #$27
    jsr @one_table

    ; 4) En la franja ($2400), las filas 26-27 (barra de poder estelar y puntaje)
    ;    usan la paleta 3 en vez de la de cada carril: sus colores 2 y 3 son azul y
    ;    blanco para todos. Son los cuadros de abajo (bits 4-7) de los bytes de la
    ;    fila 6 de la tabla ($27C0 + 6 * 8).
    bit PPUSTATUS
    lda #$27
    sta PPUADDR
    lda #$C0 + 6 * 8
    sta PPUADDR
    ldx #0
@bar_row:
    lda attr_row,x
    ora #%11110000
    sta PPUDATA
    inx
    cpx #8
    bne @bar_row
    rts

@one_table:
    bit PPUSTATUS
    sta PPUADDR
    lda #$C0
    sta PPUADDR
    ldx #0
@loop:
    txa
    and #7
    tay
    lda attr_row,y
    sta PPUDATA
    inx
    cpx #64
    bne @loop
    rts

; -----------------------------------------------------------------------------
; Tablas por carril:     verde  rojo  amarillo  azul  naranja
; -----------------------------------------------------------------------------
lane_bit:       .byte    %00001, %00010, %00100, %01000, %10000
lane_bit_mirror: .byte   %10000, %01000, %00100, %00010, %00001   ; chart_bit con ESPEJO
; rev5[m] = los 5 bits de m al revés (ESPEJO sobre una máscara de carriles)
rev5:
.repeat 32, i
    .byte ((i & 1) << 4) | ((i & 2) << 2) | (i & 4) | ((i & 8) >> 2) | ((i & 16) >> 4)
.endrepeat
; Solo hay 4 paletas de fondo y la 3 es del escenario (público, luces y marcador), así que los
; carriles comparten: verde + naranja (0), rojo + amarillo (1) y el azul solo (2). En cada pareja
; el segundo usa los tiles "B" (color 3 de la paleta).
lane_gem:       .byte    TILE_GEM_A, TILE_GEM_A, TILE_GEM_B, TILE_GEM_A, TILE_GEM_B
lane_star:      .byte    TILE_STAR_A, TILE_STAR_A, TILE_STAR_B, TILE_STAR_A, TILE_STAR_B
lane_tail:      .byte   TILE_TAIL_A, TILE_TAIL_A, TILE_TAIL_B, TILE_TAIL_A, TILE_TAIL_B
lane_palette:   .byte    0,      1,      1,      2,      0

; La batería (drum_look) usa los mismos botones y carriles, pero el orden de las columnas es el de Rock Band:
; rojo (tarola), amarillo (tom 1 / hi-hat), azul (tom 2 / ride), verde (tom 3 / crash) y, al final, el naranja
; del bombo. Cada pad tiene su propia paleta de fondo (con el naranja de la barra en el color 3).
;                verde  rojo  amarillo azul  naranja (bombo)
drum_slot:      .byte 3,     0,     1,      2,     4      ; columna (0-4) de cada carril
drum_palette:   .byte 3,     0,     1,      2,     0      ; paleta de fondo de cada carril
drum_ring_tile: .byte TILE_RING_A, TILE_RING_A, TILE_RING_A, TILE_RING_A, TILE_RING_B   ; (el aro del bombo es naranja: color 3)
