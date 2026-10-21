; =============================================================================
; hud.s - La franja fija de abajo: aros y marcador
;
; Desde la scanline SPLIT_Y la pantalla muestra la nametable de $2400 sin
; scroll (ver irq en main.s). Ahí van, como tiles de fondo:
;   fila SPLIT_ROW      los 5 aros (rellenos mientras mantienes el botón)
;   fila SPLIT_ROW + 2  puntaje, multiplicador y combo
; Con sprites no se podría: dos jugadores son 10 aros en la misma línea y el
; PPU solo dibuja 8 sprites por línea.
;
; Los cambios se mandan por la cola de textos (vbuf) y solo cuando hay algo
; nuevo: el vblank alcanza para poco y también hay que copiar la autopista.
; =============================================================================

STRIP_NT        = $2400
RING_ROW        = SPLIT_ROW
HUD_ROW         = SPLIT_ROW + 2
STRIP_FIRST_COL = 7     ; mitad izquierda de la gema del primer carril (lane_col + 1)
STRIP_WIDTH     = 18    ; hasta la mitad derecha de la gema del último carril

; -----------------------------------------------------------------------------
; draw_strip: la franja completa, con el dibujo apagado (al empezar a jugar)
; -----------------------------------------------------------------------------
draw_strip:
    ; Nametable de $2400 en blanco (espacios); los atributos los pone write_attributes
    bit PPUSTATUS
    lda #>STRIP_NT
    sta PPUADDR
    lda #<STRIP_NT
    sta PPUADDR
    lda #' '
    ldy #30
@row:
    ldx #32
@col:
    sta PPUDATA
    dex
    bne @col
    dey
    bne @row

    lda #$FF                ; ningún estado de aros coincide con $FF: se dibujan
    sta rings_shown
    lda #1
    sta hud_dirty
    jsr update_hud
    jmp flush_vbuf          ; el dibujo está apagado: se puede copiar ya

; -----------------------------------------------------------------------------
; update_hud: cada cuadro de juego; manda a la cola lo que haya cambiado
; -----------------------------------------------------------------------------
update_hud:
    ; ¿Qué carriles tienen su botón presionado? -> tmp (un bit por carril)
    lda #0
    sta tmp
    ldx #NUM_LANES - 1
@held:
    lda buttons
    and lane_button,x
    beq @not_held
    lda tmp
    ora lane_bit,x
    sta tmp
@not_held:
    dex
    bpl @held
    lda tmp
    cmp rings_shown
    beq @rings_ok
    sta rings_shown
    jsr queue_rings
@rings_ok:
    lda hud_dirty
    beq @done
    lda #0
    sta hud_dirty
    jmp queue_score
@done:
    rts

; Los 5 aros (2 tiles cada uno), con espacios entre ellos
queue_rings:
    jsr clear_strip_buf
    ldx #0
@lane:
    lda lane_ring_tile,x    ; aro vacío, mitad izquierda
    sta tmp+1
    lda rings_shown
    and lane_bit,x
    beq @empty
    lda tmp+1               ; el aro relleno está 4 tiles después
    clc
    adc #4
    sta tmp+1
@empty:
    lda lane_col,x          ; posición dentro de la franja: lane_col + 1 - STRIP_FIRST_COL
    sec
    sbc #STRIP_FIRST_COL - 1
    tay
    lda tmp+1
    sta strip_buf,y
    clc
    adc #1                  ; mitad derecha
    sta strip_buf+1,y
    inx
    cpx #NUM_LANES
    bne @lane
    lda #<(STRIP_NT + RING_ROW * 32 + STRIP_FIRST_COL)
    sta addr
    lda #>(STRIP_NT + RING_ROW * 32 + STRIP_FIRST_COL)
    sta addr+1
    jmp queue_strip_buf

; "000000 X4      123": puntaje, multiplicador y combo
queue_score:
    jsr clear_strip_buf
    ldx #5
@score:
    lda score_digits,x
    clc
    adc #'0'
    sta strip_buf,x
    dex
    bpl @score
    lda #'X'
    sta strip_buf+7
    lda multiplier
    clc
    adc #'0'
    sta strip_buf+8
    ldx #2
@combo:
    lda combo_digits,x
    clc
    adc #'0'
    sta strip_buf + STRIP_WIDTH - 3,x
    dex
    bpl @combo
    lda #<(STRIP_NT + HUD_ROW * 32 + STRIP_FIRST_COL)
    sta addr
    lda #>(STRIP_NT + HUD_ROW * 32 + STRIP_FIRST_COL)
    sta addr+1
    ; sigue en queue_strip_buf

queue_strip_buf:
    SET_PTR strip_buf
    lda #STRIP_WIDTH
    jmp vbuf_text

clear_strip_buf:
    lda #' '
    ldx #STRIP_WIDTH - 1
@loop:
    sta strip_buf,x
    dex
    bpl @loop
    rts

;                     verde        rojo         amarillo     azul         naranja
lane_ring_tile: .byte TILE_RING_A, TILE_RING_A, TILE_RING_A, TILE_RING_A, TILE_RING_B
