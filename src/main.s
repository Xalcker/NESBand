; =============================================================================
; NESBand
;
; Un juego de ritmo: notas que bajan al ritmo de canciones de NES. Presionas
; el botón del carril cuando la nota pasa por el aro de abajo; si fallas, tu
; instrumento se calla hasta el siguiente acierto.
;
; Cómo está armado el programa (todo el NES funciona así):
;
;   1. reset:     el NES enciende y salta aquí. Preparamos hardware y memoria.
;   2. main_loop: una vuelta por cuadro (60 por segundo). Lee el control y
;                 llama a la rutina del estado actual del juego:
;                   título -> menú -> juego -> resultados -> menú ...
;   3. nmi:       interrupción que el PPU dispara al terminar de dibujar cada
;                 cuadro (el "vblank"). Es el ÚNICO momento seguro para
;                 escribir en la memoria de video, y dura muy poco (~2270
;                 ciclos), así que main_loop deja todo listo en buffers y la
;                 NMI solo los copia.
;
; Cada estado tiene una rutina enter_... (apaga el dibujo, arma su pantalla
; y lo vuelve a prender) y una ..._update (lo que pasa en cada cuadro).
;
; Este archivo incluye a los demás (.include), así se ensambla todo junto y
; no hace falta exportar/importar símbolos entre archivos.
; =============================================================================

.include "nes.inc"

; -----------------------------------------------------------------------------
; Parámetros del juego
; -----------------------------------------------------------------------------
NUM_LANES       = 5
NUM_INSTRUMENTS = 4                    ; guitarra, teclado, bajo, batería
NUM_DIFFICULTIES = 4                   ; fácil, medio, difícil, experto
FRAMES_PER_ROW  = 4                    ; una fila (8 px) dura 4 cuadros -> las notas bajan 2 px por cuadro
CHART_ENTRY     = 2                    ; bytes por entrada del chart: cuadros desde la anterior, carriles
CHART_END       = $FF                  ; carriles = $FF: fin del chart
HIT_ROW         = 25                   ; fila de pantalla del aro (25 * 8 = pixel 200)
HIT_Y           = HIT_ROW * 8
WINDOW          = 6                    ; tolerancia: +-6 cuadros (~100 ms) para acertar
MAX_ERASE       = NUM_LANES            ; gemas que se pueden borrar en un mismo cuadro
SONG_LEAD_IN    = 128                  ; cuadros de autopista antes de que arranque la música
RESULTS_DELAY   = 60                   ; cuadros entre el fin de la música y los resultados
VBUF_SIZE       = 128                  ; bytes de la cola de textos para la NMI

; Las nametables guardan 30 filas cada una; usamos 2 apiladas = 60 filas
VROWS           = 60

; Al iniciar, llenamos las 60 filas: desde la fila del chart FILL_FIRST_ROW
; hasta HIT_ROW+1 (la que queda justo arriba de la pantalla, aún sin verse)
FILL_FIRST_ROW  = HIT_ROW + 1 - (VROWS - 1)
FILL_FIRST_VROW = HIT_ROW - FILL_FIRST_ROW

PPUCTRL_BASE    = %10000000            ; NMI encendida, tiles de fondo y sprites en $0000
PPUMASK_ON      = %00011110            ; mostrar fondo y sprites (incluida la columna izquierda)

; Estados del juego (índices de state_handlers)
STATE_TITLE     = 0
STATE_MENU      = 1
STATE_PLAY      = 2
STATE_RESULTS   = 3

; Ficha de una canción (la genera `nesband import-song` en src/songs/*/song.s)
SONG_MUSIC       = 0    ; .addr  datos para el motor de FamiStudio
SONG_END         = 2    ; .word  cuadro en que se detiene la música
SONG_BEAT_ROWS   = 4    ; .byte  filas entre líneas de beat
SONG_FIRST_BEAT  = 5    ; .byte  primera fila con línea de beat
SONG_TITLE       = 6    ; .addr  texto
SONG_GAME        = 8    ; .addr  texto
SONG_INSTRUMENTS = 10   ; .byte  bit i = el instrumento i tiene chart
SONG_SLOT        = 11   ; .byte  slot de 16 KB donde están su música y sus charts
SONG_CHARTS      = 12   ; .addr  [instrumento][dificultad], 0 si no hay

; MMC3 (mapper 4): ver nes.cfg para el mapa de memoria
MMC3_BANK_SELECT = $8000   ; qué registro de banco se va a cambiar (+ modo)
MMC3_BANK_DATA   = $8001   ; número de banco para ese registro
MMC3_MIRRORING   = $A000   ; 0 = vertical, 1 = horizontal
MMC3_IRQ_DISABLE = $E000
MMC3_PRG_MODE_1  = %01000000   ; $8000 fijo, $C000 intercambiable (R6)
MMC3_R6          = 6           ; banco en $C000
MMC3_R7          = 7           ; banco en $A000

; -----------------------------------------------------------------------------
; Variables en zero page (las primeras 256 bytes de RAM: acceso más rápido y
; las únicas que sirven como punteros para el modo (ptr),y)
; -----------------------------------------------------------------------------
.segment "ZEROPAGE"
frame_counter:  .res 1   ; lo incrementa la NMI; main_loop lo usa para esperar al siguiente cuadro
nmi_ready:      .res 1   ; 1 = main_loop ya dejó listo todo para que la NMI lo copie
tmp:            .res 2   ; temporal de uso general
addr:           .res 2   ; dirección de VRAM (resultado de vrow_to_addr, SET_ADDR, etc.)
ptr:            .res 2   ; puntero de uso general (chart, textos)
render_ptr:     .res 2   ; puntero al chart para dibujar filas nuevas
render_frame:   .res 2   ; cuadro de la entrada a la que apunta render_ptr
seek_frame:     .res 2   ; cuadro de la entrada a la que apunta ptr (ver chart_step)
lane:           .res 1   ; carril que se está procesando (0-4)
fill_count:     .res 1
vbuf_len:       .res 1   ; bytes ocupados en vbuf (la cola de textos para la NMI)

buttons:        .res 1   ; botones presionados en este cuadro
prev_buttons:   .res 1   ; los del cuadro anterior
pressed:        .res 1   ; los que se acaban de presionar (no estaban en el anterior)

game_state:     .res 1   ; STATE_...
cur_song:       .res 1   ; lo que se eligió en el menú
cur_instrument: .res 1
cur_difficulty: .res 1
menu_cursor:    .res 1   ; 0 = canción, 1 = instrumento, 2 = dificultad
menu_dir:       .res 1   ; +1 o -1 al cambiar un valor del menú
song_ptr:       .res 2   ; ficha de la canción elegida

song_frame:     .res 2   ; cuadros transcurridos desde que empezó la canción
song_end:       .res 2   ; cuadro en que se detiene la música
results_frame:  .res 2   ; cuadro en que se pasa a los resultados
beat_rows:      .res 1   ; filas entre líneas de beat
first_beat_row: .res 1
player_channel: .res 1   ; canal del APU que se silencia al fallar (0-3)
paused:         .res 1

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
chart_start:    .res 2   ; chart elegido (instrumento + dificultad)
beat_count:     .res 1   ; filas que faltan para la siguiente línea de beat (al dibujar)

notes_total:    .res 2   ; gemas en el chart
notes_hit:      .res 2   ; gemas acertadas
combo_bin:      .res 2   ; el combo en binario (combo_digits es para dibujarlo)
max_combo:      .res 2

; -----------------------------------------------------------------------------
; Resto de la RAM
; -----------------------------------------------------------------------------
.segment "OAM"
oam:            .res 256 ; 64 sprites x 4 bytes (Y, tile, atributos, X)

.segment "BSS"
row_buf:        .res 32  ; una fila completa de la nametable (32 tiles)
lane_ptr_lo:    .res NUM_LANES   ; siguiente nota pendiente de cada carril
lane_ptr_hi:    .res NUM_LANES
lane_frame_lo:  .res NUM_LANES   ; y el cuadro en que suena
lane_frame_hi:  .res NUM_LANES
erase_hi:       .res MAX_ERASE   ; cola de gemas a borrar: dirección y tile
erase_lo:       .res MAX_ERASE
erase_tile:     .res MAX_ERASE
score_digits:   .res 6   ; puntaje en decimal, un dígito por byte (más fácil de dibujar)
combo_digits:   .res 3
vbuf:           .res VBUF_SIZE   ; cola de textos para la NMI (ver text.s)
numstr:         .res 12  ; texto de un número (num_to_text) u otro texto armado al vuelo
hits100:        .res 3   ; notes_hit * 100, para calcular el porcentaje
percent:        .res 1
stars:          .res 1

; -----------------------------------------------------------------------------
; Encabezado iNES: le dice al emulador qué tipo de cartucho es
; -----------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 16         ; 16 bancos de 16 KB de PRG-ROM = 256 KB (ver nes.cfg)
    .byte 1          ; 1 banco de 8 KB de CHR-ROM
    .byte $40        ; mapper 4 (MMC3): el mirroring lo elige el programa
    .byte $00
    .res 8, $00

; -----------------------------------------------------------------------------
; Código
; -----------------------------------------------------------------------------
.segment "CODE"

.include "text.s"
.include "highway.s"
.include "gameplay.s"
.include "hud.s"
.include "audio.s"
.include "title.s"
.include "menu.s"
.include "play.s"
.include "results.s"

; =============================================================================
; reset: lo primero que se ejecuta al encender o al presionar Reset
;
; Va en el segmento STARTUP, en el último banco ($E000-$FFFF): al encender,
; el MMC3 solo garantiza qué hay en ese banco. Hasta configurar el MMC3 no
; se puede saltar al código de $8000.
; =============================================================================
.segment "STARTUP"
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

    ; MMC3: gráficos en orden (los 8 KB de CHR tal cual), modo de PRG 1,
    ; mirroring horizontal y sin interrupciones de scanline
    ldx #0
@chr_banks:
    txa
    ora #MMC3_PRG_MODE_1
    sta MMC3_BANK_SELECT    ; registros R0-R5: los bancos de gráficos
    lda mmc3_chr_banks,x
    sta MMC3_BANK_DATA
    inx
    cpx #6
    bne @chr_banks
    lda #1
    sta MMC3_MIRRORING
    sta MMC3_IRQ_DISABLE
    lda #0
    jsr select_slot         ; algo válido en $A000-$DFFF
    jmp reset_continue

; R0, R1 = bancos de 2 KB en $0000/$0800; R2-R5 = bancos de 1 KB en $1000-$1C00
mmc3_chr_banks: .byte 0, 2, 4, 5, 6, 7

.segment "CODE"

; -----------------------------------------------------------------------------
; select_slot: pone el slot A (música y charts de una canción) en $A000-$DFFF
; El slot n son los bancos de 8 KB 2n ($A000, registro R7) y 2n+1 ($C000, R6).
; -----------------------------------------------------------------------------
select_slot:
    asl a
    tax
    lda #MMC3_PRG_MODE_1 | MMC3_R7
    sta MMC3_BANK_SELECT
    stx MMC3_BANK_DATA
    inx
    lda #MMC3_PRG_MODE_1 | MMC3_R6
    sta MMC3_BANK_SELECT
    stx MMC3_BANK_DATA
    rts

reset_continue:

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
    jsr hide_sprites

@wait_vblank2:
    bit PPUSTATUS
    bpl @wait_vblank2

    ; Lo que aparece elegido en el menú la primera vez
    lda #1                  ; dificultad: medio
    sta cur_difficulty
    jsr select_song         ; canción 0 y su primer instrumento disponible

    jsr enter_title

; =============================================================================
; main_loop: una vuelta por cuadro
; =============================================================================
main_loop:
    jsr wait_nmi            ; esperar a que la NMI copie lo del cuadro anterior
    jsr read_pad

    ; Saltar a la rutina del estado actual: ptr = state_handlers[game_state]
    lda game_state
    asl a                   ; 2 bytes por dirección
    tax
    lda state_handlers,x
    sta ptr
    lda state_handlers+1,x
    sta ptr+1
    jsr jump_to_ptr         ; "jsr (ptr)" no existe en el 6502: jsr a un jmp (ptr)

    lda #1
    sta nmi_ready           ; listo: la próxima NMI copia todo a la PPU
    jmp main_loop

jump_to_ptr:
    jmp (ptr)

state_handlers:
    .addr title_update, menu_update, play_update, results_update

; Espera hasta que ocurra la siguiente NMI
wait_nmi:
    lda frame_counter
@wait:
    cmp frame_counter
    beq @wait
    rts

; -----------------------------------------------------------------------------
; ppu_off / ppu_on: apagar el dibujo para armar una pantalla completa, y
; volver a prenderlo (con el scroll de scroll_y / scroll_nt)
; -----------------------------------------------------------------------------
ppu_off:
    lda #0
    sta PPUCTRL             ; sin NMI: nadie toca la PPU mientras dibujamos
    sta PPUMASK
    sta row_pending         ; descartar lo que el juego dejó pendiente para la NMI,
    sta erase_count         ; o se escribiría encima de la pantalla nueva
    rts

ppu_on:
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
    lda #PPUCTRL_BASE
    ora scroll_nt
    sta PPUCTRL
    jsr wait_nmi            ; esperar el vblank para prender sin basura a medio cuadro
    lda #0
    sta OAMADDR
    lda #>oam
    sta OAMDMA              ; los sprites nuevos desde el primer cuadro
    lda #PPUMASK_ON
    sta PPUMASK
    rts

; Oculta los 64 sprites (Y = $FF queda fuera de la pantalla)
hide_sprites:
    lda #$FF
    ldx #0
@loop:
    sta oam,x
    inx
    bne @loop
    rts

; Copia 32 colores a la PPU ($3F00). X = PALETTES_PLAY o PALETTES_MENU
load_palettes:
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldy #32
@loop:
    lda palettes,x
    sta PPUDATA
    inx
    dey
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

    ; 4) Textos en cola (menús)
    lda vbuf_len
    beq @no_text
    jsr flush_vbuf
@no_text:

    ; 5) Scroll. Va al final porque escribir en $2006 descompone el scroll.
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
; Juego: 4 paletas de fondo de 3 colores + el negro común. Color 1 = gris
; de las líneas; color 2 = gema del carril; color 3 = gema del carril
; naranja (que comparte paleta con el verde porque solo hay 4 paletas).
PALETTES_PLAY = 0
PALETTES_MENU = 32
palettes:
    .byte $0F, $00, $2A, $27   ; fondo 0: verde + naranja
    .byte $0F, $00, $16, $30   ; fondo 1: rojo
    .byte $0F, $00, $28, $30   ; fondo 2: amarillo
    .byte $0F, $00, $12, $30   ; fondo 3: azul
    .byte $0F, $30, $2A, $27   ; sprites 0: blanco (texto), verde, naranja
    .byte $0F, $30, $16, $30   ; sprites 1: rojo
    .byte $0F, $30, $28, $30   ; sprites 2: amarillo
    .byte $0F, $30, $12, $30   ; sprites 3: azul
; Menús: texto blanco (color 1), gris (2) y el logo naranja (3)
    .byte $0F, $30, $10, $27
    .byte $0F, $30, $10, $27
    .byte $0F, $30, $10, $27
    .byte $0F, $30, $10, $27
    .byte $0F, $30, $27, $16
    .byte $0F, $30, $27, $16
    .byte $0F, $30, $27, $16
    .byte $0F, $30, $27, $16

; Cuántos pixeles ha bajado una fila según el cuadro dentro de ella
rowpix_table:
.repeat FRAMES_PER_ROW, i
    .byte (i * 8) / FRAMES_PER_ROW
.endrepeat

; Las canciones (las genera `uv run nesband import-song`)
.include "songs/list.s"

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
