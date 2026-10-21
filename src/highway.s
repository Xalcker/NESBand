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
    cmp #FRAMES_PER_ROW
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
    ldx frame_in_row
    lda rowpix_table,x
    sta rowpix
    rts

; -----------------------------------------------------------------------------
; step_next_row: pasa a la siguiente fila por dibujar (next_k+1, next_vrow-1)
; y lleva la cuenta de cuándo toca línea de beat
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
    dec beat_count
    bpl @done
    ldx beat_rows
    dex
    stx beat_count
@done:
    rts

; -----------------------------------------------------------------------------
; frame_to_row: tmp = fila donde se dibuja una nota que suena en el cuadro
; A (bajo) / X (alto). Fila = (cuadro + 2) / 4, redondeando al más cercano.
; -----------------------------------------------------------------------------
.assert FRAMES_PER_ROW = 4, error, "frame_to_row divide entre 4 con dos corrimientos"
frame_to_row:
    clc
    adc #FRAMES_PER_ROW / 2
    sta tmp
    txa
    adc #0
    sta tmp+1
    lsr tmp+1               ; / 2
    ror tmp
    lsr tmp+1               ; / 4
    ror tmp
    rts

; -----------------------------------------------------------------------------
; build_row: arma en row_buf los 32 tiles de la fila next_k del chart (con
; la autopista de cada jugador), y en row_addr la dirección de next_vrow.
; -----------------------------------------------------------------------------
build_row:
    ; 1) ¿Esta fila lleva la línea horizontal del beat?
    ldx #TILE_EDGE
    ldy #TILE_BLANK
    lda beat_count
    bne @no_beat
    ldx #TILE_EDGE_BEAT
    ldy #TILE_BEAT
@no_beat:
    stx edge_tile
    sty inner_tile

    ; 2) Fila vacía
    ldx #31
    lda #TILE_BLANK
@clear:
    sta row_buf,x
    dex
    bpl @clear

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
; player_row_mask: row_mask = carriles del jugador actual con nota en next_k
; -----------------------------------------------------------------------------
player_row_mask:
    lda #0
    sta row_mask
    lda next_k+1
    bmi @have_mask          ; fila negativa = antes de que empiece la canción

    ; El chart está ordenado por tiempo. Saltamos las entradas con fila < next_k
    ; y juntamos los carriles de las que caen en esta fila (una nota puede
    ; compartir fila con una entrada de relleno, que no tiene carriles).
@seek:
    ldy #1
    lda (render_ptr),y      ; carriles
    cmp #CHART_END
    beq @have_mask          ; fin del chart: no hay más notas
    lda render_frame
    ldx render_frame+1
    jsr frame_to_row        ; tmp = fila de la entrada
    lda tmp+1
    cmp next_k+1
    bcc @skip               ; entrada < k: ya pasó
    bne @have_mask          ; entrada > k: es más adelante, ya terminamos
    lda tmp
    cmp next_k
    bcc @skip
    bne @have_mask
    ldy #1                  ; misma fila: sumamos sus carriles
    lda (render_ptr),y
    ora row_mask
    sta row_mask
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
    lda row_mask
    and lane_bit,y
    beq @next_lane
    lda lane_gem,y          ; mitad izquierda de la gema (con el borde)
    sta row_buf,x
    clc
    adc #1                  ; la mitad derecha es el tile siguiente
    sta row_buf+1,x
@next_lane:
    inc lane
    lda lane
    cmp #NUM_LANES
    bne @lane

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
    ldx player
    lda lane
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
    ; 1) Paleta de cada columna de 16 px: 0 por default, la del carril donde hay uno
    lda #0
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
    lda lane_palette,y
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
lane_gem:       .byte    TILE_GEM_A, TILE_GEM_A, TILE_GEM_A, TILE_GEM_A, TILE_GEM_B
lane_palette:   .byte    0,      1,      2,      3,      0       ; naranja comparte paleta con verde
