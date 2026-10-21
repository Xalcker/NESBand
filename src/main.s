; =============================================================================
; NESBand - prototipo
;
; Una autopista de 5 carriles con notas que bajan al ritmo de la canción.
; Presionas el botón del carril cuando la nota pasa por el aro de abajo; si
; fallas, tu instrumento se calla hasta el siguiente acierto.
;
; Cómo está armado el programa (todo el NES funciona así):
;
;   1. reset:     el NES enciende y salta aquí. Preparamos hardware y memoria.
;   2. main_loop: una vuelta por cuadro (60 por segundo). Lee el control,
;                 avanza el tiempo, juzga aciertos y prepara qué dibujar.
;   3. nmi:       interrupción que el PPU dispara al terminar de dibujar cada
;                 cuadro (el "vblank"). Es el ÚNICO momento seguro para
;                 escribir en la memoria de video, y dura muy poco (~2270
;                 ciclos), así que main_loop deja todo listo en buffers y la
;                 NMI solo los copia.
;
; Este archivo incluye a los demás (.include), así se ensambla todo junto y
; no hace falta exportar/importar símbolos entre archivos.
; =============================================================================

.include "nes.inc"

; -----------------------------------------------------------------------------
; Parámetros del juego
; -----------------------------------------------------------------------------
NUM_LANES       = 5
NUM_DIFFICULTIES = 4                   ; fácil, medio, difícil, experto
FRAMES_PER_ROW  = 4                    ; una fila (8 px) dura 4 cuadros -> las notas bajan 2 px por cuadro
CHART_ENTRY     = 5                    ; bytes por nota del chart: fila (2), cuadro (2), carriles (1)
HIT_ROW         = 25                   ; fila de pantalla del aro (25 * 8 = pixel 200)
HIT_Y           = HIT_ROW * 8
WINDOW          = 6                    ; tolerancia: +-6 cuadros (~100 ms) para acertar
MAX_ERASE       = NUM_LANES            ; gemas que se pueden borrar en un mismo cuadro

; Las nametables guardan 30 filas cada una; usamos 2 apiladas = 60 filas
VROWS           = 60

; Al iniciar, llenamos las 60 filas: desde la fila del chart FILL_FIRST_ROW
; hasta HIT_ROW+1 (la que queda justo arriba de la pantalla, aún sin verse)
FILL_FIRST_ROW  = HIT_ROW + 1 - (VROWS - 1)
FILL_FIRST_VROW = HIT_ROW - FILL_FIRST_ROW

PPUCTRL_BASE    = %10000000            ; NMI encendida, tiles de fondo y sprites en $0000
PPUMASK_ON      = %00011110            ; mostrar fondo y sprites (incluida la columna izquierda)

; -----------------------------------------------------------------------------
; Variables en zero page (las primeras 256 bytes de RAM: acceso más rápido y
; las únicas que sirven como punteros para el modo (ptr),y)
; -----------------------------------------------------------------------------
.segment "ZEROPAGE"
frame_counter:  .res 1   ; lo incrementa la NMI; main_loop lo usa para esperar al siguiente cuadro
nmi_ready:      .res 1   ; 1 = main_loop ya dejó listo todo para que la NMI lo copie
tmp:            .res 2   ; temporal de uso general
addr:           .res 2   ; resultado de vrow_to_addr (dirección de VRAM)
ptr:            .res 2   ; puntero de uso general al chart
render_ptr:     .res 2   ; puntero al chart para dibujar filas nuevas
lane:           .res 1   ; carril que se está procesando (0-4)
fill_count:     .res 1

buttons:        .res 1   ; botones presionados en este cuadro
prev_buttons:   .res 1   ; los del cuadro anterior
pressed:        .res 1   ; los que se acaban de presionar (no estaban en el anterior)

song_frame:     .res 2   ; cuadros transcurridos desde que empezó la canción
cur_row:        .res 2   ; fila del chart que está ahora sobre el aro
frame_in_row:   .res 1   ; cuadro dentro de la fila actual (0 .. FRAMES_PER_ROW-1)
rowpix:         .res 1   ; cuántos pixeles ha bajado la fila actual (0..7)
cur_vrow:       .res 1   ; en qué fila de la nametable (0..59) está cur_row
row_scroll:     .res 2   ; scroll vertical al inicio de la fila actual (0..479)
scroll_y:       .res 1   ; valor final para $2005
scroll_nt:      .res 1   ; nametable de arriba (0) o de abajo (2) para $2000

next_k:         .res 2   ; siguiente fila del chart que hay que dibujar
next_vrow:      .res 1   ; fila de la nametable donde va
row_mask:       .res 1   ; carriles con nota en la fila que se está dibujando
row_pending:    .res 1   ; 1 = hay una fila en row_buf esperando a la NMI
row_addr:       .res 2   ; dirección de VRAM donde va row_buf
erase_count:    .res 1   ; cuántas gemas hay que borrar en la próxima NMI

diff:           .res 2   ; song_frame - cuadro de la nota (con signo)
multiplier:     .res 1   ; x1..x4
player_muted:   .res 1   ; 1 = el jugador falló: su instrumento no suena hasta el siguiente acierto
difficulty:     .res 1   ; 0..3
chart_start:    .res 2   ; chart de la dificultad elegida
beat_count:     .res 1   ; filas que faltan para la siguiente línea de beat (al dibujar)

; -----------------------------------------------------------------------------
; Resto de la RAM
; -----------------------------------------------------------------------------
.segment "OAM"
oam:            .res 256 ; 64 sprites x 4 bytes (Y, tile, atributos, X)

.segment "BSS"
row_buf:        .res 32  ; una fila completa de la nametable (32 tiles)
lane_ptr_lo:    .res NUM_LANES   ; siguiente nota pendiente de cada carril
lane_ptr_hi:    .res NUM_LANES
erase_hi:       .res MAX_ERASE   ; cola de gemas a borrar: dirección y tile
erase_lo:       .res MAX_ERASE
erase_tile:     .res MAX_ERASE
score_digits:   .res 6   ; puntaje en decimal, un dígito por byte (más fácil de dibujar)
combo_digits:   .res 3

; -----------------------------------------------------------------------------
; La canción: música, charts y sus constantes (SONG_...). La genera
; `uv run nesband import-song`; va antes del código porque el código usa
; esas constantes en directivas .if
; -----------------------------------------------------------------------------
.include "songs/current.s"

; beat_count para la primera fila que se dibuja (FILL_FIRST_ROW)
BEAT_COUNT_INIT = (SONG_FIRST_BEAT_ROW - FILL_FIRST_ROW) .mod SONG_BEAT_ROWS

; -----------------------------------------------------------------------------
; Encabezado iNES: le dice al emulador qué tipo de cartucho es
; -----------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 2          ; 2 bancos de 16 KB de PRG-ROM
    .byte 1          ; 1 banco de 8 KB de CHR-ROM
    .byte $00        ; mapper 0 (NROM), mirroring horizontal (nametables apiladas en vertical)
    .byte $00
    .res 8, $00

; -----------------------------------------------------------------------------
; Código
; -----------------------------------------------------------------------------
.segment "CODE"

.include "highway.s"
.include "gameplay.s"
.include "hud.s"
.include "audio.s"

; =============================================================================
; reset: lo primero que se ejecuta al encender o al presionar Reset
; =============================================================================
reset:
    sei                     ; ignorar interrupciones IRQ
    cld                     ; el 6502 del NES no tiene modo decimal; lo apagamos por costumbre
    ldx #$40
    stx APU_FRAME           ; apagar la IRQ del contador de cuadros del APU
    ldx #$FF
    txs                     ; pila en $01FF
    inx                     ; X = 0
    stx PPUCTRL             ; NMI apagada
    stx PPUMASK             ; no dibujar nada
    stx APU_DMC_FREQ        ; sin IRQ del canal DMC

    ; El PPU necesita ~2 cuadros para "despertar". Esperamos dos vblanks.
    bit PPUSTATUS
@wait_vblank1:
    bit PPUSTATUS           ; bit 7 de PPUSTATUS -> bandera N
    bpl @wait_vblank1

    ; Mientras, limpiamos la RAM (2 KB) a cero
    lda #0
@clear_ram:
    sta $0000,x
    sta $0100,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne @clear_ram

    ; Sprites con Y=$FF quedan fuera de la pantalla (ocultos)
    lda #$FF
@clear_oam:
    sta oam,x
    inx
    bne @clear_oam

@wait_vblank2:
    bit PPUSTATUS
    bpl @wait_vblank2

    jsr load_palettes

    ; Motor de sonido: A = 1 (NTSC), X/Y = dirección de la música
    lda #1
    ldx #<song_music_data
    ldy #>song_music_data
    jsr famistudio_init

    lda #NUM_DIFFICULTIES - 1   ; arrancamos en experto
    sta difficulty
    jsr game_init

; =============================================================================
; main_loop: una vuelta por cuadro
; =============================================================================
main_loop:
    jsr wait_nmi            ; esperar a que la NMI copie lo del cuadro anterior

    jsr read_pad
    lda pressed
    and #BTN_SELECT
    beq @no_select
    ldx difficulty          ; Select = siguiente dificultad (y reinicia)
    inx
    cpx #NUM_DIFFICULTIES
    bcc @set_difficulty
    ldx #0
@set_difficulty:
    stx difficulty
    jmp @restart
@no_select:
    lda pressed
    and #BTN_START
    beq @no_restart
@restart:
    jsr game_init           ; Start = reiniciar la canción
    jmp main_loop
@no_restart:

    jsr advance_time        ; mover las notas y, si toca, preparar una fila nueva
    jsr judge_lanes         ; aciertos y fallos
    jsr update_music        ; motor de sonido (y silenciar si fallaste)
    jsr update_sprites      ; aros y marcador
    jsr compute_scroll

    lda #1
    sta nmi_ready           ; listo: la próxima NMI copia todo a la PPU
    jmp main_loop

; Espera hasta que ocurra la siguiente NMI
wait_nmi:
    lda frame_counter
@wait:
    cmp frame_counter
    beq @wait
    rts

; =============================================================================
; game_init: deja todo listo para empezar la canción desde el principio
; =============================================================================
game_init:
    ; Apagamos NMI y dibujo para poder escribir libremente en la VRAM
    lda #0
    sta PPUCTRL
    sta PPUMASK

    jsr famistudio_music_stop

    ; Chart de la dificultad elegida: song_charts es una tabla de direcciones
    lda difficulty
    asl a                   ; 2 bytes por dirección
    tax
    lda song_charts,x
    sta chart_start
    lda song_charts+1,x
    sta chart_start+1

    ; Variables de tiempo y scroll
    lda #0
    sta player_muted
    sta song_frame
    sta song_frame+1
    sta cur_row
    sta cur_row+1
    sta frame_in_row
    sta rowpix
    sta row_scroll
    sta row_scroll+1
    sta row_pending
    sta erase_count
    sta nmi_ready
    lda #HIT_ROW
    sta cur_vrow

    ; Marcador en ceros
    ldx #5
    lda #0
@clear_score:
    sta score_digits,x
    dex
    bpl @clear_score
    sta combo_digits
    sta combo_digits+1
    sta combo_digits+2
    lda #1
    sta multiplier

    ; Cada carril busca su primera nota
    ldx #0
@lanes:
    lda chart_start
    sta ptr
    lda chart_start+1
    sta ptr+1
    jsr lane_seek
    inx
    cpx #NUM_LANES
    bne @lanes

    ; Dibujar las 60 filas iniciales de la autopista
    lda chart_start
    sta render_ptr
    lda chart_start+1
    sta render_ptr+1
    lda #BEAT_COUNT_INIT
    sta beat_count
    lda #<FILL_FIRST_ROW
    sta next_k
    lda #>FILL_FIRST_ROW
    sta next_k+1
    lda #FILL_FIRST_VROW
    sta next_vrow
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

    ; Sprites: ocultar todos y dibujar los aros/marcador
    lda #$FF
    ldx #0
@hide:
    sta oam,x
    inx
    bne @hide
    jsr update_sprites
    jsr compute_scroll

    ; Reencender: scroll en 0, NMI encendida, y el dibujo hasta el siguiente vblank
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #PPUCTRL_BASE
    sta PPUCTRL
    jsr wait_nmi
    lda #PPUMASK_ON
    sta PPUMASK
    rts

; Copia las 32 entradas de paleta a la PPU ($3F00)
load_palettes:
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #0
@loop:
    lda palettes,x
    sta PPUDATA
    inx
    cpx #32
    bne @loop
    rts

; =============================================================================
; nmi: se ejecuta en cada vblank. Solo copia; la lógica vive en main_loop.
; =============================================================================
nmi:
    ; Guardar registros (la NMI puede interrumpir a main_loop en cualquier punto)
    pha
    txa
    pha
    tya
    pha

    lda nmi_ready
    beq @done               ; main_loop no terminó a tiempo: no tocamos nada este cuadro

    ; 1) Sprites: el DMA copia la página $0200 completa (~513 ciclos)
    lda #0
    sta OAMADDR
    lda #>oam
    sta OAMDMA

    ; 2) Fila nueva de la autopista
    lda row_pending
    beq @no_row
    bit PPUSTATUS
    lda row_addr+1
    sta PPUADDR
    lda row_addr
    sta PPUADDR
    ldx #0
@row_loop:
    lda row_buf,x
    sta PPUDATA
    inx
    cpx #32
    bne @row_loop
    lda #0
    sta row_pending
@no_row:

    ; 3) Borrar las gemas acertadas (2 tiles cada una)
    ldx erase_count
    beq @no_erase
    ldx #0
@erase_loop:
    lda erase_hi,x
    sta PPUADDR
    lda erase_lo,x
    sta PPUADDR
    lda erase_tile,x
    sta PPUDATA
    sta PPUDATA
    inx
    cpx erase_count
    bne @erase_loop
    lda #0
    sta erase_count
@no_erase:

    ; 4) Scroll. Va al final porque escribir en $2006 descompone el scroll.
    lda #PPUCTRL_BASE
    ora scroll_nt
    sta PPUCTRL
    lda #0
    sta PPUSCROLL           ; X
    lda scroll_y
    sta PPUSCROLL           ; Y

    lda #0
    sta nmi_ready
@done:
    inc frame_counter

    pla
    tay
    pla
    tax
    pla
irq:
    rti

; -----------------------------------------------------------------------------
; Datos
; -----------------------------------------------------------------------------
.segment "RODATA"

; Colores (índices de la paleta del NES). $0F = negro.
; Fondo: 4 paletas de 3 colores + el negro común. Color 1 = gris de las
; líneas; color 2 = gema del carril; color 3 = gema del carril naranja
; (que comparte paleta con el verde porque solo hay 4 paletas).
palettes:
    .byte $0F, $00, $2A, $27   ; fondo 0: verde + naranja
    .byte $0F, $00, $16, $30   ; fondo 1: rojo
    .byte $0F, $00, $28, $30   ; fondo 2: amarillo
    .byte $0F, $00, $12, $30   ; fondo 3: azul
    .byte $0F, $30, $2A, $27   ; sprites 0: blanco (texto), verde, naranja
    .byte $0F, $30, $16, $30   ; sprites 1: rojo
    .byte $0F, $30, $28, $30   ; sprites 2: amarillo
    .byte $0F, $30, $12, $30   ; sprites 3: azul

; Cuántos pixeles ha bajado una fila según el cuadro dentro de ella
rowpix_table:
.repeat FRAMES_PER_ROW, i
    .byte (i * 8) / FRAMES_PER_ROW
.endrepeat

; -----------------------------------------------------------------------------
; Vectores: las 3 direcciones a las que salta el 6502 (NMI, reset, IRQ)
; -----------------------------------------------------------------------------
.segment "VECTORS"
    .addr nmi, reset, irq

; -----------------------------------------------------------------------------
; Gráficos (CHR-ROM)
; -----------------------------------------------------------------------------
.segment "CHARS"
.include "chr.s"
