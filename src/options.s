; =============================================================================
; options.s - Pantalla de opciones (issue #6): modificadores y práctica
;
; Se abre con Select desde el menú; Start juega con lo elegido y B regresa al menú. Las
; opciones valen para todos los jugadores y se quedan hasta que las cambies:
;
;   ESPEJO          invierte los carriles: la nota verde sale en el carril naranja y al revés
;                   (se traduce al leer el chart: ver chart_bit y rev5)
;   VELOCIDAD       100%, 75% o 50%: la canción y las notas avanzan más lento. El juego se salta
;                   1 de cada 4 (o 1 de cada 2) cuadros, sin tocar el motor de sonido (ver play_update)
;   CAIDA DE NOTAS  qué tan rápido bajan las notas, sin importar la dificultad (la de los charts no
;                   cambia): AUTO usa la de la dificultad, o la de fácil a experto (ver set_speed)
;   PRACTICA        la canción se repite desde el inicio hasta 1/4, 1/2, 3/4 o el final; sin fallo,
;                   sin resultados y sin récord. Select en la pausa regresa al menú
;
; Con cualquier opción distinta de la normal no se guardan récords.
; =============================================================================

OPT_ITEMS       = 4
OPT_ROW0        = 9      ; fila del valor de la primera opción; cada una va 3 filas más abajo
OPT_VALUE_COL   = 4
OPT_VALUE_WIDTH = 16
PRACTICE_LOOP_MAX = 4    ; el valor más alto de PRACTICA (4 = toda la canción)

enter_options:
    jsr ppu_off
    lda #STATE_OPTIONS
    sta game_state
    ldx #PALETTES_MENU
    jsr load_palettes
    jsr clear_nametable
    PRINT_CENTER 4, txt_options
    PRINT MENU_LABEL_COL, OPT_ROW0 - 1, txt_opt_mirror
    PRINT MENU_LABEL_COL, OPT_ROW0 + 2, txt_opt_speed
    PRINT MENU_LABEL_COL, OPT_ROW0 + 5, txt_opt_fall
    PRINT MENU_LABEL_COL, OPT_ROW0 + 8, txt_opt_practice
    PRINT_CENTER 22, txt_opt_note1
    PRINT_CENTER 23, txt_opt_note2
    PRINT_CENTER 26, txt_menu_help
    ldx #OPT_ITEMS - 1
@draw:
    txa
    pha
    jsr options_draw_value
    jsr flush_vbuf          ; el dibujo está apagado: se puede copiar ya
    pla
    tax
    dex
    bpl @draw

    jsr hide_sprites
    lda #0
    sta opt_cursor
    jsr options_place_cursor
    lda #0
    sta scroll_y
    sta scroll_nt
    jmp ppu_on              ; la canción de muestra del menú sigue sonando

options_update:
    lda #0
    sta menu_moved
    lda pad_pressed
    ora pad_pressed+1
    sta tmp+1               ; los botones de cualquiera de los dos controles
    and #BTN_START
    beq @no_start
    jmp enter_play
@no_start:
    lda tmp+1
    and #BTN_B | BTN_SELECT
    beq @no_back
    jmp enter_menu
@no_back:
    lda opt_cursor
    ldx #OPT_ITEMS - 1
    jsr move_cursor
    sta opt_cursor
    jsr direction           ; menu_dir = -1/+1, o 0 si no hay izquierda/derecha
    beq @done
    ldx opt_cursor
    lda opt_values,x
    clc
    adc menu_dir
    bpl @not_negative
    lda opt_count,x         ; de la primera a la última
    sec
    sbc #1
@not_negative:
    cmp opt_count,x
    bcc @store
    lda #0                  ; de la última a la primera
@store:
    sta opt_values,x
    jsr options_draw_value
@done:
    jsr options_place_cursor
    lda menu_moved
    beq @no_sfx
    lda #SFX_MOVER
    jsr play_sfx
@no_sfx:
    jmp famistudio_update   ; la canción de muestra

; options_draw_value: X = opción. Escribe el nombre de su valor actual (por la cola vbuf)
options_draw_value:
    lda opt_addr_lo,x
    sta addr
    lda opt_addr_hi,x
    sta addr+1
    txa
    asl a
    tay
    lda opt_lists,y         ; ptr = su lista de nombres
    sta ptr
    lda opt_lists+1,y
    sta ptr+1
    lda opt_values,x
    asl a
    tay
    lda (ptr),y             ; ptr = el nombre del valor
    pha
    iny
    lda (ptr),y
    sta ptr+1
    pla
    sta ptr
    lda #OPT_VALUE_WIDTH
    jmp vbuf_text

; El cursor es un sprite '>' a la izquierda del valor de la opción elegida
options_place_cursor:
    ldx opt_cursor
    lda opt_cursor_y,x
    sta oam
    lda #'>'
    sta oam+1
    lda #0                  ; paleta de sprites 0: blanco
    sta oam+2
    lda #(OPT_VALUE_COL - 1) * 8
    sta oam+3
    rts

.segment "RODATA"

opt_count:      .byte 2, 3, 5, PRACTICE_LOOP_MAX + 1
opt_cursor_y:   .byte OPT_ROW0 * 8 - 1, (OPT_ROW0 + 3) * 8 - 1, (OPT_ROW0 + 6) * 8 - 1, (OPT_ROW0 + 9) * 8 - 1
opt_addr_lo:    .byte <($2000 + OPT_ROW0 * 32 + OPT_VALUE_COL), <($2000 + (OPT_ROW0 + 3) * 32 + OPT_VALUE_COL)
                .byte <($2000 + (OPT_ROW0 + 6) * 32 + OPT_VALUE_COL), <($2000 + (OPT_ROW0 + 9) * 32 + OPT_VALUE_COL)
opt_addr_hi:    .byte >($2000 + OPT_ROW0 * 32 + OPT_VALUE_COL), >($2000 + (OPT_ROW0 + 3) * 32 + OPT_VALUE_COL)
                .byte >($2000 + (OPT_ROW0 + 6) * 32 + OPT_VALUE_COL), >($2000 + (OPT_ROW0 + 9) * 32 + OPT_VALUE_COL)

opt_lists:      .addr opt_names_mirror, opt_names_speed, opt_names_fall, opt_names_practice
opt_names_mirror:   .addr txt_no, txt_yes
opt_names_speed:    .addr txt_speed_100, txt_speed_75, txt_speed_50
opt_names_fall:     .addr txt_auto, txt_easy, txt_medium, txt_hard, txt_expert
opt_names_practice: .addr txt_no, txt_loop_1, txt_loop_2, txt_loop_3, txt_loop_4

txt_options:     .byte "OPCIONES", 0
txt_opt_mirror:  .byte "ESPEJO", 0
txt_opt_speed:   .byte "VELOCIDAD", 0
txt_opt_fall:    .byte "CAIDA DE NOTAS", 0
txt_opt_practice: .byte "PRACTICA", 0
txt_opt_note1:   .byte "PRACTICA: SIN FALLO NI RECORD", 0
txt_opt_note2:   .byte "CON OPCIONES NO HAY RECORD", 0
txt_menu_options: .byte "SELECT: OPCIONES", 0
txt_no:          .byte "NO", 0
txt_yes:         .byte "SI", 0
txt_auto:        .byte "AUTO", 0
txt_speed_100:   .byte "100%", 0
txt_speed_75:    .byte "75%", 0
txt_speed_50:    .byte "50%", 0
txt_loop_1:      .byte "HASTA 1/4", 0
txt_loop_2:      .byte "HASTA 1/2", 0
txt_loop_3:      .byte "HASTA 3/4", 0
txt_loop_4:      .byte "TODA LA CANCION", 0

.segment "CODE2"
