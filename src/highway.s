; =============================================================================
; highway.s - La autopista que se desplaza
;
; IDEA CENTRAL: las notas NO son sprites. El NES solo puede mostrar 8 sprites
; por línea horizontal, y un acorde de 5 gemas de 16 px ya serían 10. Así que
; las gemas se dibujan en el FONDO (la nametable) y lo que se mueve es el
; scroll vertical: toda la autopista "baja" junta.
;
; Usamos mirroring horizontal: hay dos nametables apiladas en vertical
; ($2000 arriba y $2800 abajo) que forman un rollo de 60 filas (480 px).
; La pantalla muestra 30 filas; las otras 30 están fuera de la vista y ahí
; vamos dibujando las filas que vienen antes de que aparezcan arriba.
;
; Relación entre fila del chart (k) y fila de la nametable (vrow):
;     vrow = (HIT_ROW - k) mod 60
; Las filas más adelante en la canción quedan más arriba. Cuando cur_row
; avanza, el scroll baja 8 pixeles y todo se desliza hacia abajo.
; =============================================================================

; Columnas de la autopista: 5 carriles de 4 tiles (32 px) a partir de la 6.
;   [borde][gema izq][gema der][vacío]
; El ancho de 32 px hace que cada carril coincida con la cuadrícula de
; atributos del NES (cuadros de 16x16 que eligen la paleta), y así cada
; carril tiene su propio color.
HIGHWAY_RIGHT_COL = 26          ; borde derecho del último carril

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
    ; cur_vrow = cur_vrow - 1, dando la vuelta de 0 a 59
    dec cur_vrow
    bpl @vrow_ok
    lda #VROWS - 1
    sta cur_vrow
@vrow_ok:
    ; row_scroll = row_scroll - 8, dando la vuelta de 0 a 472
    sec
    lda row_scroll
    sbc #8
    sta row_scroll
    lda row_scroll+1
    sbc #0
    sta row_scroll+1
    bpl @scroll_ok
    clc
    lda row_scroll
    adc #<480
    sta row_scroll
    lda row_scroll+1
    adc #>480
    sta row_scroll+1
@scroll_ok:
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
; build_row: arma en row_buf los 32 tiles de la fila next_k del chart,
; y en row_addr la dirección de VRAM de next_vrow.
; -----------------------------------------------------------------------------
build_row:
    ; 1) ¿Qué carriles tienen nota en esta fila?
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
    ; 2) ¿Esta fila lleva la línea horizontal del beat?
    ldx #TILE_EDGE
    ldy #TILE_BLANK
    lda beat_count
    bne @no_beat
    ldx #TILE_EDGE_BEAT
    ldy #TILE_BEAT
@no_beat:
    stx tmp                 ; tmp   = tile del borde
    sty tmp+1               ; tmp+1 = tile del interior

    ; 3) Fila vacía
    ldx #31
    lda #TILE_BLANK
@clear:
    sta row_buf,x
    dex
    bpl @clear

    ; 4) Cada carril: borde + interior, y la gema si hay nota
    ldy #0
@lane:
    ldx lane_col,y          ; X = columna donde empieza el carril
    lda tmp
    sta row_buf,x
    lda tmp+1
    sta row_buf+1,x
    sta row_buf+2,x
    sta row_buf+3,x
    lda row_mask
    and lane_bit,y
    beq @next_lane
    lda lane_gem,y          ; mitad izquierda de la gema
    sta row_buf+1,x
    clc
    adc #1                  ; la mitad derecha es el tile siguiente
    sta row_buf+2,x
@next_lane:
    iny
    cpy #NUM_LANES
    bne @lane

    lda tmp
    sta row_buf+HIGHWAY_RIGHT_COL

    ; 5) Dirección de VRAM
    lda next_vrow
    jsr vrow_to_addr
    lda addr
    sta row_addr
    lda addr+1
    sta row_addr+1
    rts

; -----------------------------------------------------------------------------
; vrow_to_addr: A = fila de nametable (0..59) -> addr = dirección en VRAM
;   filas 0..29  -> $2000 + fila*32
;   filas 30..59 -> $2800 + (fila-30)*32
; -----------------------------------------------------------------------------
vrow_to_addr:
    ldx #$20
    cmp #30
    bcc @top
    sbc #30                 ; (el cmp dejó carry=1, que la resta necesita)
    ldx #$28
@top:
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
; compute_scroll: scroll = row_scroll - rowpix (en 0..479), separado en
; nametable (arriba/abajo) y Y dentro de ella (0..239)
; -----------------------------------------------------------------------------
compute_scroll:
    sec
    lda row_scroll
    sbc rowpix
    sta tmp
    lda row_scroll+1
    sbc #0
    sta tmp+1
    bpl @positive
    clc
    lda tmp
    adc #<480
    sta tmp
    lda tmp+1
    adc #>480
    sta tmp+1
@positive:
    lda tmp+1
    bne @bottom             ; >= 256: seguro está en la de abajo
    lda tmp
    cmp #240
    bcs @bottom
    sta scroll_y
    lda #0
    sta scroll_nt
    rts
@bottom:
    sec
    lda tmp
    sbc #240
    sta scroll_y
    lda #2                  ; bit 1 de PPUCTRL: nametable $2800
    sta scroll_nt
    rts

; -----------------------------------------------------------------------------
; write_attributes: asigna la paleta de cada carril en ambas nametables.
; Como cada carril es una columna completa, todas las filas de atributos son
; iguales.
; -----------------------------------------------------------------------------
write_attributes:
    lda #$23
    jsr @one_table
    lda #$2B
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
    lda attribute_row,y
    sta PPUDATA
    inx
    cpx #64
    bne @loop
    rts

; -----------------------------------------------------------------------------
; Tablas por carril:     verde  rojo  amarillo  azul  naranja
; -----------------------------------------------------------------------------
lane_col:       .byte    6,    10,    14,      18,    22
lane_bit:       .byte    %00001, %00010, %00100, %01000, %10000
lane_gem:       .byte    TILE_GEM_A, TILE_GEM_A, TILE_GEM_A, TILE_GEM_A, TILE_GEM_B

; Un byte de atributos cubre 32x32 px en 4 cuadros de 16x16 (2 bits cada uno):
;   bits 0-1 arriba-izq, 2-3 arriba-der, 4-5 abajo-izq, 6-7 abajo-der
; Columnas de 16 px: 0-2 fuera (pal 0), 3-4 verde (0), 5-6 rojo (1),
; 7-8 amarillo (2), 9-10 azul (3), 11-12 naranja (0), 13-15 fuera (0)
attribute_row:
    .byte $00, $00, $44, $99, $EE, $33, $00, $00
