; =============================================================================
; title.s - Pantalla de título
; =============================================================================

TITLE_LOGO_ROW = 7

enter_title:
    jsr ppu_off
    lda #STATE_TITLE
    sta game_state

    ldx #PALETTES_MENU
    jsr load_palettes
    jsr clear_nametable
    lda #TITLE_LOGO_ROW
    jsr draw_logo
    PRINT_CENTER 16, txt_press_start
    PRINT_CENTER 22, txt_tagline
    PRINT_CENTER 24, txt_ai_made
    jsr hide_sprites

    lda #0
    sta scroll_y
    sta scroll_nt
    jsr ppu_on

    ; La música del título (original; ver audio/titulo.txt)
    ldx #<title_music_data
    ldy #>title_music_data
    jsr music_init
    lda #0
    jmp famistudio_music_play

title_update:
    jsr famistudio_update
    lda pressed
    and #BTN_START
    beq @blink
    jmp enter_menu          ; (enter_menu toca el efecto de "aceptar")

    ; "PRESIONA START" parpadea: cada 32 cuadros se escribe o se borra
@blink:
    lda frame_counter
    and #31
    bne @done
    SET_PTR txt_press_start
    lda #16
    jsr center_addr
    lda frame_counter
    and #32
    beq @show
    SET_PTR txt_empty
@show:
    lda #txt_press_start_end - txt_press_start
    jmp vbuf_text
@done:
    rts

; -----------------------------------------------------------------------------
; draw_logo: dibuja el logo en la fila A (render apagado)
; -----------------------------------------------------------------------------
LOGO_WIDTH = 21         ; tiles por renglón
LOGO_ROWS  = 4
LOGO_COL   = (32 - LOGO_WIDTH) / 2

draw_logo:
    ; addr = $2000 + fila * 32 + LOGO_COL
    sta addr
    lda #0
    sta addr+1
    ldx #5
@shift:
    asl addr
    rol addr+1
    dex
    bne @shift
    lda addr
    clc
    adc #LOGO_COL
    sta addr
    lda addr+1
    adc #$20
    sta addr+1

    ldx #0                  ; índice dentro de logo_tiles
    lda #LOGO_ROWS
    sta fill_count
@row:
    bit PPUSTATUS
    lda addr+1
    sta PPUADDR
    lda addr
    sta PPUADDR
    ldy #LOGO_WIDTH
@tile:
    lda logo_tiles,x
    sta PPUDATA
    inx
    dey
    bne @tile
    lda addr                ; siguiente renglón: +32
    clc
    adc #32
    sta addr
    bcc @no_carry
    inc addr+1
@no_carry:
    dec fill_count
    bne @row
    rts

.segment "RODATA"

; El logo se dibuja con "pixeles gordos" de 4x4: cada tile tiene 2x2 de ellos.
; BIG_ROW toma dos renglones de texto ('#' = lleno) y produce los tiles con
; los bloques que tocan (TILE_BIG + máscara, ver chr.s).
.macro BIG_ROW top, bottom
    .assert .strlen(top) = LOGO_WIDTH * 2 && .strlen(bottom) = LOGO_WIDTH * 2, error, "Renglón del logo de largo incorrecto"
    .repeat LOGO_WIDTH, i
        .byte TILE_BIG | ((.strat(top, i * 2) = '#') << 3) | ((.strat(top, i * 2 + 1) = '#') << 2) | ((.strat(bottom, i * 2) = '#') << 1) | (.strat(bottom, i * 2 + 1) = '#')
    .endrepeat
.endmacro

logo_tiles:
    BIG_ROW "#...#.#####..####.####...###..#...#.####..", "##..#.#.....#.....#...#.#...#.##..#.#...#."
    BIG_ROW "##..#.#.....#.....#...#.#...#.##..#.#...#.", "#.#.#.####...###..####..#####.#.#.#.#...#."
    BIG_ROW "#..##.#.........#.#...#.#...#.#..##.#...#.", "#..##.#.........#.#...#.#...#.#..##.#...#."
    BIG_ROW "#...#.#####.####..####..#...#.#...#.####..", ".........................................."

txt_press_start:    .byte "PRESIONA START"
txt_press_start_end:
                    .byte 0
txt_tagline:        .byte "UN JUEGO DE RITMO PARA NES", 0
txt_ai_made:        .byte "CODIGO 100% HECHO POR IA", 0
txt_empty:          .byte 0

.segment "CODE"
