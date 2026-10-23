; =============================================================================
; chr.s - Los dibujos (tiles) de 8x8 pixeles
;
; Cada tile usa 4 colores (0-3) de la paleta que le toque. En este archivo los
; dibujamos como texto: '.' = color 0 (transparente/fondo), '1', '2', '3'.
; La macro TILE convierte el dibujo al formato del NES: 16 bytes, primero los
; 8 bytes del bit 0 de cada pixel y luego los 8 del bit 1 ("bitplanes").
;
; Organización:
;   $00-$0F  autopista, gemas y aros
;   $10-$17  llamarada de acierto (sprites)
;   $18-$1F  colas de las notas sostenidas
;   $20-$5A  fuente: el número de tile de cada letra es su código ASCII, así
;            un texto se escribe tal cual con .byte "HOLA" (solo mayúsculas)
;   $80-$8F  bloques de 4x4 px para el logo (ver BIG_ROW en title.s)
; =============================================================================

; Un byte de un bitplane: el bit `plano` de los 8 pixeles de una fila
.macro TILE_PLANE fila, plano
    _tile_byte .set 0
    .repeat 8, i
        ; valor del pixel: el dígito, o 0 si es '.'
        _tile_byte .set _tile_byte | ((((.strat(fila, i) - '0') * (.strat(fila, i) <> '.')) >> plano) & 1) << (7 - i)
    .endrepeat
    .byte _tile_byte
.endmacro

.macro TILE r0, r1, r2, r3, r4, r5, r6, r7
    .assert .strlen(r0) = 8 && .strlen(r1) = 8 && .strlen(r2) = 8 && .strlen(r3) = 8 && .strlen(r4) = 8 && .strlen(r5) = 8 && .strlen(r6) = 8 && .strlen(r7) = 8, error, "Cada fila de un tile debe tener 8 caracteres"
    TILE_PLANE r0, 0
    TILE_PLANE r1, 0
    TILE_PLANE r2, 0
    TILE_PLANE r3, 0
    TILE_PLANE r4, 0
    TILE_PLANE r5, 0
    TILE_PLANE r6, 0
    TILE_PLANE r7, 0
    TILE_PLANE r0, 1
    TILE_PLANE r1, 1
    TILE_PLANE r2, 1
    TILE_PLANE r3, 1
    TILE_PLANE r4, 1
    TILE_PLANE r5, 1
    TILE_PLANE r6, 1
    TILE_PLANE r7, 1
.endmacro

; Rellena con tiles vacíos hasta llegar al tile número n. `org` es donde empieza el tile 0 del
; banco que se está escribiendo: sin él, el banco base (chr_start); los bancos del escenario
; (ver al final) lo piden porque sus tiles son los $80-$FF de un banco de 2 KB.
.macro TILE_AT n, org
    .ifblank org
        .assert * - chr_start <= (n) * 16, error, "Hay tiles encimados: el anterior se pasó del número pedido"
        .res (n) * 16 - (* - chr_start)
    .else
        .assert * - (org) <= (n) * 16, error, "Hay tiles encimados: el anterior se pasó del número pedido"
        .res (n) * 16 - (* - (org))
    .endif
.endmacro

; Números de tile
TILE_BLANK      = $00
TILE_EDGE       = $01
TILE_BEAT       = $02
TILE_EDGE_BEAT  = $03
TILE_GEM_A      = $04   ; con borde + $05 mitad derecha (usa color 2)
TILE_GEM_B      = $06   ; con borde + $07 mitad derecha (usa color 3)
TILE_RING_A     = $08   ; + $09 mitad derecha (color 2)
TILE_RING_B     = $0A   ; + $0B mitad derecha (color 3)
TILE_FILL_A     = $0C   ; = aro + 4: presionado
TILE_FILL_B     = $0E
TILE_FX         = $10   ; llamarada de acierto: 4 cuadros x 2 tiles (arriba, abajo)
TILE_DIGIT0     = '0'
TILE_X          = 'X'
TILE_BIG        = $80   ; + máscara de 4 bits (ver BIG_ROW)

TILE_STAR_A     = $99   ; gema estelar (diamante, color 2) + $9A mitad derecha
TILE_STAR_B     = $9B   ; (color 3) + $9C
TILE_BAR        = $90   ; barra de poder estelar: + 0..8 píxeles llenos (blanco)
TILE_BAR_ON     = $A0   ; lo mismo con el poder activo (azul)
TILE_BOLT       = $A9   ; rayo de las frases estelares: dos dibujos, $A9 y $AA
TILE_METER      = $B0   ; medidor de vida: + 0..8 filas llenas
TILE_TAIL_A     = $19  ; cola de nota sostenida (color 2): mitad izquierda; la derecha es $18 (el tile anterior)
TILE_TAIL_B     = $1B   ; (color 3); la derecha es $1A. Con la línea del beat: +4 (ver TAIL_BEAT)
TAIL_BEAT       = 4

chr_start:

; --- Autopista ---------------------------------------------------------------

; $00 vacío
TILE "........", "........", "........", "........", "........", "........", "........", "........"
; $01 borde del carril
TILE "1.......", "1.......", "1.......", "1.......", "1.......", "1.......", "1.......", "1......."
; $02 línea del beat
TILE "........", "........", "........", "11111111", "........", "........", "........", "........"
; $03 borde + línea del beat
TILE "1.......", "1.......", "1.......", "11111111", "1.......", "1.......", "1.......", "1......."
; Cada carril mide 16 px: dos tiles, [borde + izquierda][derecha]. Para
; borrar una gema se escribe el tile del borde y luego el anterior (el
; interior): $01 -> $00 sin beat, $03 -> $02 con beat (ver la NMI).
; $04-$05 gema (color 2): la mitad izquierda trae la línea del borde del carril
TILE "1.......", "1..11111", "1.122222", "1.122222", "1.122222", "1.122222", "1..11111", "1......."
TILE "........", "11111...", "222221..", "222221..", "222221..", "222221..", "11111...", "........"
; $06-$07 gema (color 3)
TILE "1.......", "1..11111", "1.133333", "1.133333", "1.133333", "1.133333", "1..11111", "1......."
TILE "........", "11111...", "333331..", "333331..", "333331..", "333331..", "11111...", "........"
; Aros de 14x8 en dos tiles (para que los de carriles vecinos no se toquen)
; $08-$09 aro vacío (color 2), $0A-$0B aro vacío (color 3)
TILE "....2222", "..22....", ".2......", ".2......", ".2......", ".2......", "..22....", "....2222"
TILE "2222....", "....22..", "......2.", "......2.", "......2.", "......2.", "....22..", "2222...."
TILE "....3333", "..33....", ".3......", ".3......", ".3......", ".3......", "..33....", "....3333"
TILE "3333....", "....33..", "......3.", "......3.", "......3.", "......3.", "....33..", "3333...."
; $0C-$0D aro presionado (color 2), $0E-$0F aro presionado (color 3)
TILE "....2222", "..222222", ".2222222", ".2221111", ".2221111", ".2222222", "..222222", "....2222"
TILE "2222....", "222222..", "2222222.", "1111222.", "1111222.", "2222222.", "222222..", "2222...."
TILE "....3333", "..333333", ".3333333", ".3331111", ".3331111", ".3333333", "..333333", "....3333"
TILE "3333....", "333333..", "3333333.", "1111333.", "1111333.", "3333333.", "333333..", "3333...."

; --- Llamarada de acierto (sprites) --------------------------------------------
; Cada cuadro de la animación son 2 tiles apilados (arriba y abajo, 8x16 px) que
; se dibujan sobre el aro. Colores de la paleta de sprites 0: 1 = blanco
; (centro), 2 = amarillo, 3 = naranja (orilla). Tiles $10-$17.
TILE_AT TILE_FX
; cuadro 0: estallido
TILE "3..22..3", ".3.22.3.", "..3223..", "3.2112.3", ".321123.", "..2112..", "3.2112.3", "..2112.."
TILE "..2112..", ".321123.", "3.2112.3", "..3223..", ".3.22.3.", "3..22..3", "........", "........"
; cuadro 1: llama alta
TILE "........", "....3...", "...33...", "...33...", "..3223..", "..3223..", ".322223.", ".322223."
TILE ".322223.", "32211223", "32211223", "32211223", "32211223", "32211223", ".322223.", "..3223.."
; cuadro 2: llama baja
TILE "........", "........", "........", "........", "....3...", "...33...", "...33...", "..3223.."
TILE "..3223..", ".322223.", ".322123.", ".322123.", ".322223.", ".322223.", "..3223..", "..3333.."
; cuadro 3: chispas que se dispersan
TILE "........", "3.......", "......3.", "........", "..3...3.", "........", ".3......", "....3..."
TILE "3......3", "....3...", ".3...3..", "........", "..3...3.", "3.......", "....3...", "........"

; --- Colas de las notas sostenidas ----------------------------------------------
; Una barra de 4 px en el centro del carril. Cada pareja se escribe como
; [izquierda][derecha] pero el número de la derecha es el anterior, porque el
; borrado de gemas escribe "tile y luego tile - 1" (ver la NMI).
; $18-$19 color 2, $1A-$1B color 3, $1C-$1F las mismas con la línea del beat
TILE_AT $18
; $18 derecha color 2, $19 izquierda color 2 (con el borde del carril)
TILE "22......", "22......", "22......", "22......", "22......", "22......", "22......", "22......"
TILE "1.....22", "1.....22", "1.....22", "1.....22", "1.....22", "1.....22", "1.....22", "1.....22"
; $1A derecha color 3, $1B izquierda color 3
TILE "33......", "33......", "33......", "33......", "33......", "33......", "33......", "33......"
TILE "1.....33", "1.....33", "1.....33", "1.....33", "1.....33", "1.....33", "1.....33", "1.....33"
; $1C-$1D color 2 con la línea del beat, $1E-$1F color 3 con la línea del beat
TILE "22......", "22......", "22......", "22111111", "22......", "22......", "22......", "22......"
TILE "1.....22", "1.....22", "1.....22", "11111122", "1.....22", "1.....22", "1.....22", "1.....22"
TILE "33......", "33......", "33......", "33111111", "33......", "33......", "33......", "33......"
TILE "1.....33", "1.....33", "1.....33", "11111133", "1.....33", "1.....33", "1.....33", "1.....33"

; --- Fuente (color 1) ----------------------------------------------------------

TILE_AT ' '
TILE "........", "........", "........", "........", "........", "........", "........", "........"
; !
TILE "..11....", "..11....", "..11....", "..11....", "..11....", "........", "..11....", "........"
TILE_AT '%'
TILE "11....1.", "11...11.", "....11..", "...11...", "..11....", ".11..11.", "11...11.", "........"
TILE_AT $27   ; apóstrofo
TILE "..11....", "..11....", ".11.....", "........", "........", "........", "........", "........"
; ( )
TILE "...11...", "..11....", ".11.....", ".11.....", ".11.....", "..11....", "...11...", "........"
TILE "..11....", "...11...", "....11..", "....11..", "....11..", "...11...", "..11....", "........"
; * (estrella)
TILE "...1....", "...1....", "1111111.", ".11111..", "..111...", ".11.11..", ".1...1..", "........"
TILE_AT ','
TILE "........", "........", "........", "........", "........", "..11....", "..11....", ".11....."
; -
TILE "........", "........", "........", ".11111..", "........", "........", "........", "........"
; .
TILE "........", "........", "........", "........", "........", "..11....", "..11....", "........"
; /
TILE "......11", ".....11.", "....11..", "...11...", "..11....", ".11.....", "11......", "........"
; 0-9
TILE ".11111..", "11...11.", "11..111.", "11.1.11.", "111..11.", "11...11.", ".11111..", "........"
TILE "..11....", ".111....", "..11....", "..11....", "..11....", "..11....", ".1111...", "........"
TILE ".11111..", "11...11.", ".....11.", "..1111..", ".11.....", "11......", "1111111.", "........"
TILE ".11111..", "11...11.", ".....11.", "..1111..", ".....11.", "11...11.", ".11111..", "........"
TILE "...111..", "..1111..", ".11.11..", "11..11..", "1111111.", "....11..", "....11..", "........"
TILE "1111111.", "11......", "111111..", ".....11.", ".....11.", "11...11.", ".11111..", "........"
TILE "..1111..", ".11.....", "11......", "111111..", "11...11.", "11...11.", ".11111..", "........"
TILE "1111111.", "11...11.", "....11..", "...11...", "..11....", "..11....", "..11....", "........"
TILE ".11111..", "11...11.", "11...11.", ".11111..", "11...11.", "11...11.", ".11111..", "........"
TILE ".11111..", "11...11.", "11...11.", ".111111.", ".....11.", "....11..", ".1111...", "........"
; :
TILE "........", "..11....", "..11....", "........", "..11....", "..11....", "........", "........"
TILE_AT '<'
TILE "....11..", "...11...", "..11....", ".11.....", "..11....", "...11...", "....11..", "........"
TILE_AT '>'
TILE ".11.....", "..11....", "...11...", "....11..", "...11...", "..11....", ".11.....", "........"
; ?
TILE ".11111..", "11...11.", ".....11.", "...111..", "...11...", "........", "...11...", "........"
TILE_AT 'A'
TILE "..111...", ".11.11..", "11...11.", "11...11.", "1111111.", "11...11.", "11...11.", "........"
TILE "111111..", "11...11.", "11...11.", "111111..", "11...11.", "11...11.", "111111..", "........"
TILE "..1111..", ".11..11.", "11......", "11......", "11......", ".11..11.", "..1111..", "........"
TILE "11111...", "11..11..", "11...11.", "11...11.", "11...11.", "11..11..", "11111...", "........"
TILE "1111111.", "11......", "11......", "111111..", "11......", "11......", "1111111.", "........"
TILE "1111111.", "11......", "11......", "111111..", "11......", "11......", "11......", "........"
TILE "..11111.", ".11.....", "11......", "11..111.", "11...11.", ".11..11.", "..11111.", "........"
TILE "11...11.", "11...11.", "11...11.", "1111111.", "11...11.", "11...11.", "11...11.", "........"
TILE ".111111.", "...11...", "...11...", "...11...", "...11...", "...11...", ".111111.", "........"
TILE "...1111.", ".....11.", ".....11.", ".....11.", "11...11.", "11...11.", ".11111..", "........"
TILE "11...11.", "11..11..", "11.11...", "1111....", "11.11...", "11..11..", "11...11.", "........"
TILE "11......", "11......", "11......", "11......", "11......", "11......", "1111111.", "........"
TILE "11...11.", "111.111.", "1111111.", "11.1.11.", "11...11.", "11...11.", "11...11.", "........"
TILE "11...11.", "111..11.", "1111.11.", "11.1111.", "11..111.", "11...11.", "11...11.", "........"
TILE ".11111..", "11...11.", "11...11.", "11...11.", "11...11.", "11...11.", ".11111..", "........"
TILE "111111..", "11...11.", "11...11.", "111111..", "11......", "11......", "11......", "........"
TILE ".11111..", "11...11.", "11...11.", "11...11.", "11.1111.", "11..11..", ".111.11.", "........"
TILE "111111..", "11...11.", "11...11.", "111111..", "11.11...", "11..11..", "11...11.", "........"
TILE ".11111..", "11...11.", "11......", ".11111..", ".....11.", "11...11.", ".11111..", "........"
TILE "1111111.", "...11...", "...11...", "...11...", "...11...", "...11...", "...11...", "........"
TILE "11...11.", "11...11.", "11...11.", "11...11.", "11...11.", "11...11.", ".11111..", "........"
TILE "11...11.", "11...11.", "11...11.", "11...11.", ".11.11..", "..111...", "...1....", "........"
TILE "11...11.", "11...11.", "11...11.", "11.1.11.", "1111111.", "111.111.", "11...11.", "........"
TILE "11...11.", ".11.11..", "..111...", "..111...", "..111...", ".11.11..", "11...11.", "........"
TILE "11...11.", "11...11.", ".11.11..", "..111...", "..111...", "..111...", "..111...", "........"
TILE "1111111.", ".....11.", "....11..", "...11...", "..11....", ".11.....", "1111111.", "........"

; --- Escenario: tiles fijos que se repiten con el scroll (los genera `nesband build-scene`) ---
SCENE_CHR_LOW

; --- Bloques del logo (color 3) ------------------------------------------------
; Tile $80 + m, donde los bits de m dicen qué cuartos de 4x4 px están llenos:
;   bit 3 = arriba-izq, bit 2 = arriba-der, bit 1 = abajo-izq, bit 0 = abajo-der
; Color 3 = los dos bitplanes con el mismo dibujo.
TILE_AT TILE_BIG
.repeat 16, m
    .repeat 2           ; plano 0 y plano 1 iguales
        .repeat 4
            .byte ((m >> 3) & 1) * $F0 | ((m >> 2) & 1) * $0F
        .endrepeat
        .repeat 4
            .byte ((m >> 1) & 1) * $F0 | (m & 1) * $0F
        .endrepeat
    .endrepeat
.endrepeat

; --- Poder estelar -----------------------------------------------------------------
; Barra: un tile de 8 px de ancho con n píxeles llenos de izquierda a derecha
; (color 3 = blanco, o color 2 = azul con el poder activo) y borde arriba y abajo
; en color 1. Los colores salen de la paleta 3 de fondo, que write_attributes
; asigna a la fila de la barra para que no cambie con el color de cada carril.
.macro BAR_TILE n, on
    _bar_fill .set ($FF << (8 - n)) & $FF
    .byte 0, $FF                ; plano 0: fila 0 vacía, fila 1 borde (color 1)
    .repeat 4
        .byte _bar_fill * (on)  ; filas 2-5: el color 3 usa también el plano 0
    .endrepeat
    .byte $FF, 0                ; fila 6 borde, fila 7 vacía
    .byte 0, 0                  ; plano 1: filas 0-1 vacías
    .repeat 4
        .byte _bar_fill
    .endrepeat
    .byte 0, 0
.endmacro

; Es una macro porque estos tiles también van en los bancos del escenario (SCENE_CHR_BANK, ver
; scene_art.s): ahí el fondo cambia de banco en $0800-$0FFF y todo lo que el juego dibuja en esa
; mitad debe estar en cada uno.
.macro BG_STAR_TILES org
TILE_AT TILE_BAR, org
.repeat 9, n
    BAR_TILE n, 1           ; color 3: blanco (la franja usa la paleta 3, ver write_attributes)
.endrepeat

; Gemas de las frases estelares: un diamante de 14 px (color 2 y color 3)
; $99-$9A color 2, $9B-$9C color 3
TILE "1.....22", "1...2222", "1.222222", "12222222", "12222222", "1.222222", "1...2222", "1.....22"
TILE "22......", "2222....", "222222..", "2222222.", "2222222.", "222222..", "2222....", "22......"
TILE "1.....33", "1...3333", "1.333333", "13333333", "13333333", "1.333333", "1...3333", "1.....33"
TILE "33......", "3333....", "333333..", "3333333.", "3333333.", "333333..", "3333....", "33......"

TILE_AT TILE_BAR_ON, org
.repeat 9, n
    BAR_TILE n, 0           ; color 2: azul
.endrepeat
.endmacro

BG_STAR_TILES

; Rayo de las frases estelares completas (paleta de sprites 1: 1 = blanco, 2 = cian).
; Dos tiles que se alternan en una columna: $A9 baja de derecha a izquierda y $AA
; sube de vuelta, así que uno sobre otro forman un zigzag continuo
TILE "....2112", "....2112", "...2112.", "...2112.", "..2112..", "..2112..", ".2112...", ".2112..."
TILE ".2112...", ".2112...", "..2112..", "..2112..", "...2112.", "...2112.", "....2112", "....2112"

; Medidor de vida (sprites): un segmento de 8 px con borde blanco (color 1) y n
; filas llenas de abajo hacia arriba (color 2: verde, amarillo o rojo según la paleta)
.macro METER_TILE n
    .repeat 8
        .byte $81               ; plano 0: el borde de los lados
    .endrepeat
    .repeat 8, r
        .if r >= 8 - n
            .byte $7E           ; plano 1: el interior, en las filas llenas
        .else
            .byte 0
        .endif
    .endrepeat
.endmacro

TILE_AT TILE_METER
.repeat 9, n
    METER_TILE n
.endrepeat

; --- Bancos del escenario ------------------------------------------------------------
; Lo de arriba son los 4 KB que ven el fondo y los sprites (unidades 0-3 de 1 KB). Después van
; 3 bancos de 2 KB, los que el fondo pone en $0800-$0FFF mientras se juega (ver scene.s): el
; público quieto, con los brazos arriba y saltando. Cada uno repite los tiles del juego que
; viven en esa mitad (BG_STAR_TILES) y trae los del escenario.
; El "origen" que se le da a TILE_AT queda 128 tiles antes del inicio del banco, para usar los
; mismos números de tile que ve el PPU ($80-$FF).
TILE_AT $100
scene_bank_idle:
SCENE_CHR_BANK 0, scene_bank_idle - $80 * 16
scene_bank_arms:
SCENE_CHR_BANK 1, scene_bank_arms - $80 * 16
scene_bank_jump:
SCENE_CHR_BANK 2, scene_bank_jump - $80 * 16
.assert * - scene_bank_idle = 3 * $800, error, "Cada banco del escenario debe medir 2 KB (SCENE_BANK_IDLE..JUMP en scene.s)"
