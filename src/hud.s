; =============================================================================
; hud.s - Sprites: los 5 aros de la línea de golpe y el marcador
;
; Cada sprite son 4 bytes en la página OAM ($0200):
;   Y (menos 1, el PPU los dibuja una línea abajo), tile, atributos, X
; Ojo con el límite de 8 sprites por línea: por eso el puntaje, el combo y
; el multiplicador van a alturas distintas.
; =============================================================================

SCORE_X = 0
SCORE_Y = 16
COMBO_X = 224
COMBO_Y = 32
MULT_X  = 224
MULT_Y  = 48
DIFF_X  = 0
DIFF_Y  = 32

update_sprites:
    ldy #0                  ; Y = índice dentro de la OAM

    ; --- Aros: uno por carril, relleno mientras mantienes el botón ---
    ldx #0
@target:
    lda #HIT_Y - 1
    sta oam,y
    lda lane_target_tile,x
    sta tmp
    lda buttons
    and lane_button,x
    beq @not_held
    inc tmp                 ; el aro relleno está 2 tiles después
    inc tmp
@not_held:
    lda tmp
    sta oam+1,y
    lda lane_palette,x
    sta oam+2,y
    lda lane_col,x          ; X en pixeles = columna * 8 + 12 (centro del carril)
    asl a
    asl a
    asl a
    clc
    adc #12
    sta oam+3,y
    iny
    iny
    iny
    iny
    inx
    cpx #NUM_LANES
    bne @target

    ; --- Puntaje: 6 dígitos ---
    ldx #0
@score:
    lda #SCORE_Y - 1
    sta oam,y
    lda score_digits,x
    clc
    adc #TILE_DIGIT0
    sta oam+1,y
    lda #0
    sta oam+2,y
    txa
    asl a
    asl a
    asl a
    adc #SCORE_X            ; (carry = 0: x*8 nunca desborda aquí)
    sta oam+3,y
    iny
    iny
    iny
    iny
    inx
    cpx #6
    bne @score

    ; --- Combo: 3 dígitos ---
    ldx #0
@combo:
    lda #COMBO_Y - 1
    sta oam,y
    lda combo_digits,x
    clc
    adc #TILE_DIGIT0
    sta oam+1,y
    lda #0
    sta oam+2,y
    txa
    asl a
    asl a
    asl a
    adc #COMBO_X
    sta oam+3,y
    iny
    iny
    iny
    iny
    inx
    cpx #3
    bne @combo

    ; --- Multiplicador: "X" y un dígito ---
    lda #MULT_Y - 1
    sta oam,y
    sta oam+4,y
    lda #TILE_X
    sta oam+1,y
    lda multiplier
    clc
    adc #TILE_DIGIT0
    sta oam+5,y
    lda #0
    sta oam+2,y
    sta oam+6,y
    lda #MULT_X
    sta oam+3,y
    lda #MULT_X + 8
    sta oam+7,y

    ; --- Dificultad: un dígito del 1 (fácil) al 4 (experto) ---
    lda #DIFF_Y - 1
    sta oam+8,y
    lda difficulty
    clc
    adc #TILE_DIGIT0 + 1
    sta oam+9,y
    lda #0
    sta oam+10,y
    lda #DIFF_X
    sta oam+11,y
    rts

;                        verde        rojo         amarillo     azul         naranja
lane_target_tile: .byte  TILE_RING_A, TILE_RING_A, TILE_RING_A, TILE_RING_A, TILE_RING_B
lane_palette:     .byte  0,           1,           2,           3,           0
