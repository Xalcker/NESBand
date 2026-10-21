; =============================================================================
; gameplay.s - Control, aciertos, fallos y puntaje
;
; Formato del chart (lo genera `nesband import-song` en src/songs/*/chart.s):
; una lista de notas de 5 bytes, ordenada por fila:
;     .word fila, cuadro  ; fila donde se dibuja y cuadro exacto en que suena
;     .byte carriles      ; bit 0 = verde ... bit 4 = naranja (varios = acorde)
;                         ; bit 7 = la fila tiene línea de beat
; y termina con una fila $FFFF. La fila sirve para dibujar (cada fila son
; 4 cuadros) y el cuadro para juzgar con precisión de 1/60 de segundo.
;
; Cada carril lleva su propio puntero a su siguiente nota pendiente
; (lane_ptr). Así cada gema de un acorde se juzga por separado, como en la
; batería de Rock Band.
; =============================================================================

; -----------------------------------------------------------------------------
; read_pad: lee el control 1
; El control es un registro de desplazamiento: se "congela" escribiendo 1 y
; luego 0 en $4016, y después cada lectura entrega un botón en el bit 0, en
; orden: A, B, Select, Start, Arriba, Abajo, Izquierda, Derecha.
; -----------------------------------------------------------------------------
read_pad:
    lda buttons
    sta prev_buttons

    lda #1
    sta buttons             ; este 1 sale por el carry después de 8 rotaciones: fin del ciclo
    sta JOY1
    lda #0
    sta JOY1
@loop:
    lda JOY1
    lsr a                   ; bit 0 -> carry
    rol buttons             ; carry -> bit 0 de buttons, el bit 7 sale al carry
    bcc @loop

    ; pressed = botones que están ahora y no estaban antes
    lda prev_buttons
    eor #$FF
    and buttons
    sta pressed
    rts

; -----------------------------------------------------------------------------
; judge_lanes: para cada carril, revisa su siguiente nota
; -----------------------------------------------------------------------------
judge_lanes:
    lda #0
    sta lane
@lane_loop:
    ldx lane
    lda lane_ptr_lo,x
    sta ptr
    lda lane_ptr_hi,x
    sta ptr+1

    ldy #1
    lda (ptr),y             ; byte alto de la fila
    cmp #$FF
    beq @next               ; fin del chart para este carril

    ; tmp = cuadro en que la nota toca el aro
    ldy #2
    lda (ptr),y
    sta tmp
    iny
    lda (ptr),y
    sta tmp+1

    ; diff = song_frame - tmp   (negativo = la nota aún no llega)
    sec
    lda song_frame
    sbc tmp
    sta diff
    lda song_frame+1
    sbc tmp+1
    sta diff+1

    lda pressed
    and lane_button,x
    beq @not_pressed

    ; Se presionó el botón: ¿la nota está dentro de la ventana?
    jsr in_window
    bcc @next               ; golpe al aire: por ahora no se castiga
    jsr note_hit
    jmp @advance

@not_pressed:
    ; ¿Ya se pasó la nota? (diff > WINDOW)
    lda diff+1
    bmi @next               ; negativo: todavía no llega
    bne @miss               ; 256 cuadros o más de retraso
    lda diff
    cmp #WINDOW + 1
    bcc @next
@miss:
    jsr note_miss
@advance:
    jsr lane_advance
@next:
    inc lane
    lda lane
    cmp #NUM_LANES
    bne @lane_loop
    rts

; -----------------------------------------------------------------------------
; in_window: carry = 1 si -WINDOW <= diff <= WINDOW
; -----------------------------------------------------------------------------
in_window:
    lda diff+1
    beq @positive
    cmp #$FF
    bne @outside
    lda diff                ; diff negativo: dentro si diff >= -WINDOW
    cmp #256 - WINDOW
    rts
@positive:
    lda #WINDOW             ; dentro si WINDOW >= diff
    cmp diff
    rts
@outside:
    clc
    rts

; -----------------------------------------------------------------------------
; lane_seek: a partir de ptr, busca la siguiente nota que use el carril X
; (o el final del chart) y la guarda en lane_ptr. No modifica X.
; -----------------------------------------------------------------------------
lane_seek:
@check:
    ldy #1
    lda (ptr),y
    cmp #$FF
    beq @found              ; fin del chart
    ldy #4
    lda (ptr),y
    and lane_bit,x
    bne @found
    clc
    lda ptr
    adc #CHART_ENTRY
    sta ptr
    bcc @check
    inc ptr+1
    jmp @check
@found:
    lda ptr
    sta lane_ptr_lo,x
    lda ptr+1
    sta lane_ptr_hi,x
    rts

; lane_advance: pasa el carril `lane` a su siguiente nota
lane_advance:
    ldx lane
    lda lane_ptr_lo,x
    clc
    adc #CHART_ENTRY
    sta ptr
    lda lane_ptr_hi,x
    adc #0
    sta ptr+1
    jmp lane_seek

; -----------------------------------------------------------------------------
; note_hit / note_miss
; -----------------------------------------------------------------------------
note_hit:
    lda #0
    sta player_muted        ; acertaste: tu instrumento vuelve a sonar
    inc notes_hit
    bne @counted
    inc notes_hit+1
@counted:
    jsr erase_gem
    jsr combo_inc
    jmp score_add

note_miss:
    lda #0
    sta combo_digits
    sta combo_digits+1
    sta combo_digits+2
    sta combo_bin
    sta combo_bin+1
    lda #1
    sta multiplier
    sta player_muted        ; fallaste: tu instrumento se calla
    rts

; -----------------------------------------------------------------------------
; erase_gem: agrega a la cola de la NMI el borrado de la gema (ptr, carril lane)
; -----------------------------------------------------------------------------
erase_gem:
    ldy erase_count
    cpy #MAX_ERASE
    bcs @done

    ; La nota está a pocas filas de cur_row, así que d = fila - cur_row cabe
    ; en un byte con signo, y su fila de nametable es cur_vrow - d (mod 60).
    ldy #0
    lda (ptr),y
    sec
    sbc cur_row
    sta tmp
    lda cur_vrow
    sec
    sbc tmp
    bmi @wrap_up
    cmp #VROWS
    bcc @have_vrow
    sbc #VROWS
    jmp @have_vrow
@wrap_up:
    clc
    adc #VROWS
@have_vrow:
    jsr vrow_to_addr

    ldx lane
    lda lane_col,x
    sec                     ; +1: la gema empieza una columna después del borde
    adc addr
    ldy erase_count
    sta erase_lo,y
    lda addr+1
    sta erase_hi,y

    ; Debajo de la gema puede haber línea de beat (bit 7 de los carriles)
    ldx #TILE_BLANK
    ldy #4
    lda (ptr),y
    bpl @store_tile
    ldx #TILE_BEAT
@store_tile:
    txa
    ldy erase_count
    sta erase_tile,y
    inc erase_count
@done:
    rts

; -----------------------------------------------------------------------------
; combo_inc: combo + 1 (en decimal) y recalcula el multiplicador:
;   0-9 -> x1, 10-19 -> x2, 20-29 -> x3, 30+ -> x4
; -----------------------------------------------------------------------------
combo_inc:
    ; En binario, para las estadísticas: combo_bin + 1 y, si supera al máximo, guardarlo
    inc combo_bin
    bne @bin_ok
    inc combo_bin+1
@bin_ok:
    lda max_combo           ; max_combo - combo_bin: carry = 1 si max_combo >= combo_bin
    cmp combo_bin
    lda max_combo+1
    sbc combo_bin+1
    bcs @max_ok
    lda combo_bin
    sta max_combo
    lda combo_bin+1
    sta max_combo+1
@max_ok:

    ldx #2                  ; en decimal, para dibujarlo: empezamos por las unidades
@digit:
    inc combo_digits,x
    lda combo_digits,x
    cmp #10
    bcc @mult
    lda #0                  ; llegó a 10: se vuelve 0 y se lleva 1
    sta combo_digits,x
    dex
    bpl @digit
    lda #9                  ; pasó de 999: lo dejamos en 999
    sta combo_digits
    sta combo_digits+1
    sta combo_digits+2
@mult:
    lda combo_digits        ; centenas
    bne @max
    lda combo_digits+1      ; decenas
    cmp #3
    bcs @max
    adc #1                  ; (carry = 0 por el bcs)
    sta multiplier
    rts
@max:
    lda #4
    sta multiplier
    rts

; -----------------------------------------------------------------------------
; score_add: puntaje += 50 * multiplicador
; Se suma 5 a las decenas, tantas veces como el multiplicador.
; -----------------------------------------------------------------------------
score_add:
    ldy multiplier
@times:
    ldx #4                  ; dígito de las decenas
    lda #5
@digit:
    clc
    adc score_digits,x
    cmp #10
    bcc @store
    sbc #10                 ; (carry = 1 por el cmp)
    sta score_digits,x
    lda #1                  ; lo que se lleva al siguiente dígito
    dex
    bpl @digit
    jmp @next               ; se pasó de 999999: se pierde
@store:
    sta score_digits,x
@next:
    dey
    bne @times
    rts

; Botón de cada carril:  verde      rojo      amarillo    azul   naranja
lane_button:    .byte    BTN_LEFT, BTN_DOWN, BTN_RIGHT, BTN_B, BTN_A
