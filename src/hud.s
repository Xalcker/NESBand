; =============================================================================
; hud.s - La franja fija de abajo: aros y marcador de cada jugador
;
; Desde la scanline SPLIT_Y la pantalla muestra la nametable de $2400 sin
; scroll (ver irq en main.s). Debajo de la autopista de cada jugador, como
; tiles de fondo:
;   fila SPLIT_ROW      los 5 aros (rellenos mientras mantienes el botón)
;   fila SPLIT_ROW + 1  barra de poder estelar
;   fila SPLIT_ROW + 2  puntaje y multiplicador   "000000 X4"
;   fila SPLIT_ROW + 3  combo                      "COMBO 123"
; Con sprites no se podría: dos jugadores son 10 aros en la misma línea y el
; PPU solo dibuja 8 sprites por línea.
;
; Los cambios se mandan por la cola de textos (vbuf) y solo cuando hay algo
; nuevo. Además hay un presupuesto por cuadro (HUD_BUDGET): el vblank alcanza
; para poco y también hay que copiar la autopista. Lo que no quepa espera al
; cuadro siguiente; a 60 cuadros por segundo nadie lo nota.
; =============================================================================

STRIP_NT     = $2400
RING_ROW     = SPLIT_ROW
SCORE_ROW    = SPLIT_ROW + 2
COMBO_ROW    = SPLIT_ROW + 3
STRIP_WIDTH  = HIGHWAY_TILES        ; cada bloque mide lo que la autopista
HUD_ENTRY    = 3 + STRIP_WIDTH      ; bytes que ocupa un renglón en vbuf
HUD_BUDGET   = 4 * HUD_ENTRY        ; a lo más 4 renglones por cuadro

STAR_ROW     = SPLIT_ROW + 1        ; barra de poder estelar (entre los aros y el puntaje)

HUD_SCORE    = %001                 ; bits de hud_dirty
HUD_COMBO    = %010
HUD_STAR     = %100

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

    ; El público del escenario: las filas SPLIT_ROW .. 29 a los lados de los marcadores
    ; (scene_strip trae 5 filas de 32 columnas por distribución: 1 jugador, 2 jugadores)
    lda #<scene_strip
    sta ptr
    lda #>scene_strip
    sta ptr+1
    lda num_players
    cmp #2
    bcc @crowd
    lda ptr                 ; 2 jugadores: sus filas van 5 * 32 bytes después (el carry está en 1)
    adc #5 * 32 - 1
    sta ptr
    bcc @crowd
    inc ptr+1
@crowd:
    bit PPUSTATUS
    lda #>(STRIP_NT + SPLIT_ROW * 32)
    sta PPUADDR
    lda #<(STRIP_NT + SPLIT_ROW * 32)
    sta PPUADDR
    ldy #0
@crowd_tile:
    lda (ptr),y
    sta PPUDATA
    iny
    cpy #5 * 32
    bne @crowd_tile

    ldx #0
@player:
    jsr load_player
    lda #$FF                ; ningún estado de aros coincide con $FF: se dibujan
    sta rings_shown
    lda #HUD_SCORE | HUD_COMBO | HUD_STAR
    sta hud_dirty
    jsr update_hud
    jsr flush_vbuf          ; el dibujo está apagado: se puede copiar ya
    jsr store_player
    ldx player
    inx
    cpx num_players
    bne @player
    rts

; -----------------------------------------------------------------------------
; update_hud: cada cuadro, para el jugador actual; manda a la cola lo que
; haya cambiado, si cabe en el presupuesto de este cuadro
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
    jsr hud_room
    bcc @rings_ok           ; no cabe: el siguiente cuadro
    lda tmp
    sta rings_shown
    jsr queue_rings
@rings_ok:
    lda hud_dirty
    and #HUD_SCORE
    beq @score_ok
    jsr hud_room
    bcc @score_ok
    lda hud_dirty
    and #<~HUD_SCORE
    sta hud_dirty
    jsr queue_score
@score_ok:
    lda hud_dirty
    and #HUD_COMBO
    beq @combo_ok
    jsr hud_room
    bcc @combo_ok
    lda hud_dirty
    and #<~HUD_COMBO
    sta hud_dirty
    jsr queue_combo
@combo_ok:
    lda hud_dirty
    and #HUD_STAR
    beq @done
    jsr hud_room
    bcc @done
    lda hud_dirty
    and #<~HUD_STAR
    sta hud_dirty
    jmp queue_star
@done:
    rts

; carry = 1 si en vbuf cabe un renglón más este cuadro
; (cmp deja carry = 1 cuando A >= el otro: aquí, cuando lo libre alcanza)
hud_room:
    lda #HUD_BUDGET - HUD_ENTRY
    cmp vbuf_len
    rts

; Los 5 aros (2 tiles cada uno)
queue_rings:
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
    txa                     ; posición: carril * 2
    asl a
    tay
    lda tmp+1
    sta strip_buf,y
    clc
    adc #1                  ; mitad derecha
    sta strip_buf+1,y
    inx
    cpx #NUM_LANES
    bne @lane
    lda #<(STRIP_NT + RING_ROW * 32)
    jmp queue_strip_buf

; "000000 X4": puntaje y multiplicador
queue_score:
    jsr clear_strip_buf
    ldx #5
@digit:
    lda score_digits,x
    clc
    adc #'0'
    sta strip_buf,x
    dex
    bpl @digit
    lda #'X'
    sta strip_buf+7
    jsr eff_multiplier      ; x2..x8 con el poder estelar activo
    clc
    adc #'0'
    sta strip_buf+8
    lda #<(STRIP_NT + SCORE_ROW * 32)
    jmp queue_strip_buf

; La barra de poder estelar: 10 tiles de 8 px; cada uno se llena de izquierda a
; derecha según star_energy (tiles TILE_BAR + 0..8 píxeles llenos). Con el poder
; activo se dibuja con el otro color (TILE_BAR_ON).
queue_star:
    ldx #0
@tile:
    txa
    asl a
    asl a
    asl a                   ; píxel donde empieza este tile
    sta tmp
    lda star_energy
    sec
    sbc tmp
    bcs @some
    lda #0                  ; la energía no llega a este tile: vacío
    beq @filled             ; (siempre)
@some:
    cmp #9
    bcc @filled
    lda #8                  ; lleno
@filled:
    ldy star_active
    beq @color
    clc
    adc #TILE_BAR_ON - TILE_BAR
@color:
    clc
    adc #TILE_BAR
    sta strip_buf,x
    inx
    cpx #STRIP_WIDTH
    bne @tile
    lda #<(STRIP_NT + STAR_ROW * 32)
    jmp queue_strip_buf

; "COMBO 123", o "FALLASTE" si el jugador ya perdió
queue_combo:
    lda failed
    beq @combo
    ldx #STRIP_WIDTH - 1
@failed:
    lda txt_failed,x
    sta strip_buf,x
    dex
    bpl @failed
    lda #<(STRIP_NT + COMBO_ROW * 32)
    jmp queue_strip_buf
@combo:
    ldx #5
@label:
    lda txt_combo,x
    sta strip_buf,x
    dex
    bpl @label
    ldx #2
@digit:
    lda combo_digits,x
    clc
    adc #'0'
    sta strip_buf+6,x
    dex
    bpl @digit
    lda #' '
    sta strip_buf+9
    lda #<(STRIP_NT + COMBO_ROW * 32)
    ; sigue en queue_strip_buf

; Manda strip_buf a la cola, en la fila cuya dirección (byte bajo, sin la
; columna) viene en A, debajo de la autopista del jugador actual. Todas las
; filas de la franja tienen el mismo byte alto ($27).
.assert >(STRIP_NT + RING_ROW * 32) = >(STRIP_NT + COMBO_ROW * 32), error, "La franja cruza de página"
queue_strip_buf:
    ldx player
    clc
    adc player_base,x
    sta addr
    lda #>(STRIP_NT + RING_ROW * 32)
    sta addr+1
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
lane_ring_tile: .byte TILE_RING_A, TILE_RING_A, TILE_RING_B, TILE_RING_A, TILE_RING_B   ; (ver lane_gem)

txt_combo:      .byte "COMBO "
txt_failed:     .byte "FALLASTE  "        ; STRIP_WIDTH (10) caracteres
.assert .strlen("FALLASTE  ") = STRIP_WIDTH, error, "txt_failed debe medir lo que la franja"
