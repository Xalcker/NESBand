; =============================================================================
; scene.s - El escenario vivo (issue #4): público y luces que reaccionan
;
; Los costados de la autopista y la franja de abajo dejan de estar vacíos:
;   * Costados (en la nametable que se desplaza): bocinas, torres y focos con su haz de luz.
;     Es un dibujo que se repite cada 24 px (3 filas), así que baja con el scroll sin cortes;
;     cada fila nueva lo trae de scene_rows (ver build_row).
;   * Público (en la franja fija de abajo): 5 filas de tiles a cada lado.
;
; Nada de esto cuesta CPU: el público se anima cambiando de banco de CHR (un solo registro del
; MMC3 por cuadro) y las luces cambiando el color 2 de la paleta 3 de fondo (una escritura).
; El arte lo genera pctools/nesband_tools/scene.py (src/scene_art.s).
;
; Banco de CHR del fondo en $0800-$0FFF (tiles $80-$FF), registro R1 del MMC3. Fuera del juego
; vale SCENE_BANK_BASE (los bloques del logo); en el juego, uno de los 3 bancos del escenario:
; la NMI lo copia desde scene_bank cada cuadro mientras scene_on = 1.
;
; Cómo reacciona (scene_update, un cuadro de juego):
;   * Nadie sigue en pie: luces apagadas y público quieto.
;   * Sin combo (menos de SCENE_CHEER): público quieto.
;   * Con combo: brazos arriba, y al empezar cada tiempo de la canción salta un momento.
;   * Con poder estelar: además, el color de las luces cambia en cada tiempo.
;   * Frase estelar completa (el rayo): destello blanco mientras dure.
; =============================================================================

SCENE_BANK_BASE = 2         ; el banco de siempre ($80-$FF: logo, barra de poder, ...), en unidades de 1 KB
SCENE_BANK_IDLE = 4         ; público quieto (los 3 bancos del escenario van después de los 4 KB base)
SCENE_BANK_ARMS = 6         ; con brazos arriba
SCENE_BANK_JUMP = 8         ; saltando
SCENE_CHEER     = 10        ; combo desde el que el público se anima
SCENE_ATTACK    = 6         ; cuadros del inicio de cada tiempo en que el público salta y la luz late

SCENE_COLOR       = $12     ; luz de fondo normal (azul)
SCENE_COLOR_PULSE = $22     ; y al latir con el tiempo (azul más claro)
SCENE_COLOR_OFF   = $0F     ; todos perdieron: luces apagadas (negro)
SCENE_COLOR_FLASH = $30     ; destello de una frase estelar completa (blanco)

PS_COMBO        = combo_bin - pstate   ; posición dentro del bloque de un jugador (lo lee scene_update)

; -----------------------------------------------------------------------------
; scene_init: al empezar la canción (enter_play, con la NMI apagada). Debe llamarse justo
; después de dejar next_beat en el primer tiempo desde el cuadro 0: los tiempos de la
; canción caen en cuadros song_frame = next_beat + k * beat_frames.
; -----------------------------------------------------------------------------
scene_init:
    lda next_beat           ; fase = cuadros desde el último tiempo: en el cuadro 0 faltan
    beq @phase              ; next_beat para el siguiente, así que la fase es el resto
    lda beat_frames
    sec
    sbc next_beat
@phase:
    sta scene_phase
    lda #0
    sta scene_beat
    lda #SCENE_BANK_IDLE
    sta scene_bank
    lda #SCENE_COLOR
    sta scene_color
    lda #1
    sta scene_on            ; desde el primer cuadro la NMI pone el banco y el color
    rts

; -----------------------------------------------------------------------------
; scene_update: un cuadro de juego. Decide el banco del público y el color de las luces
; (scene_bank y scene_color) según cómo va la banda; la NMI los aplica.
; -----------------------------------------------------------------------------
scene_update:
    ; 1) El tiempo de la canción: scene_phase cuenta cuadros dentro de cada tiempo
    inc scene_phase
    lda scene_phase
    cmp beat_frames
    bcc @phase_ok
    lda #0
    sta scene_phase
    inc scene_beat          ; (sirve para cambiar de color con el poder estelar)
@phase_ok:

    ; 2) ¿Cómo va la banda? Quién sigue en pie, si alguien tiene combo y si hay poder estelar
    lda #0
    sta scene_alive
    sta scene_cheer
    sta scene_star
    ldx #0
@player:
    ldy player_offset,x
    lda player_save + PS_FAILED,y
    bne @next
    inc scene_alive
    lda player_save + PS_COMBO + 1,y
    bne @cheers
    lda player_save + PS_COMBO,y
    cmp #SCENE_CHEER
    bcc @combo_ok
@cheers:
    inc scene_cheer
@combo_ok:
    lda player_save + PS_STAR_ACTIVE,y
    beq @next
    inc scene_star
@next:
    inx
    cpx num_players
    bne @player

    ; 3) Público (X = banco) y luces (A = color)
    ldx #SCENE_BANK_IDLE
    lda scene_alive
    bne @lit
    lda #SCENE_COLOR_OFF
    jmp @set
@lit:
    lda scene_cheer
    beq @color              ; sin combo el público no se mueve
    ldx #SCENE_BANK_ARMS
    lda scene_phase
    cmp #SCENE_ATTACK
    bcs @color
    ldx #SCENE_BANK_JUMP    ; al empezar el tiempo salta
@color:
    lda scene_star
    beq @no_star
    lda scene_beat          ; poder estelar: un color distinto en cada tiempo
    and #3
    tay
    lda scene_star_colors,y
    bne @bolt               ; (ninguno es 0)
@no_star:
    lda #SCENE_COLOR
    ldy scene_cheer
    beq @bolt
    ldy scene_phase
    cpy #SCENE_ATTACK
    bcs @bolt
    lda #SCENE_COLOR_PULSE  ; con combo, la luz late con el tiempo
@bolt:
    ldy bolt_timer          ; frase estelar completa: destello blanco
    bne @flash
    ldy bolt_timer+1
    beq @set
@flash:
    lda #SCENE_COLOR_FLASH
@set:
    stx scene_bank
    sta scene_color
    rts

; Colores de las luces con el poder estelar activo: cian, rojo, amarillo y violeta
scene_star_colors: .byte $2C, $16, $28, $14
