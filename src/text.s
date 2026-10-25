; =============================================================================
; text.s - Escribir texto y números en la pantalla
;
; Dos formas de escribir en la nametable:
;   - Directo (print_direct): solo con el dibujo APAGADO, para armar una
;     pantalla completa de un jalón (título, menú, resultados).
;   - En cola (vbuf_text): con el dibujo PRENDIDO. Se guarda en vbuf y la NMI
;     lo copia en el vblank. Sirve para cambiar unas cuantas palabras por
;     cuadro (por ejemplo, el valor que cambias en el menú).
;
; Los textos son bytes ASCII terminados en 0: como cada letra de la fuente
; está en el tile de su código ASCII, no hace falta traducir nada.
; =============================================================================

; addr = dirección de la nametable $2000 en la columna/fila dadas
.macro SET_ADDR col, row
    lda #<($2000 + (row) * 32 + (col))
    sta addr
    lda #>($2000 + (row) * 32 + (col))
    sta addr+1
.endmacro

.macro SET_PTR label
    lda #<(label)
    sta ptr
    lda #>(label)
    sta ptr+1
.endmacro

; Escribe un texto fijo (render apagado). Los parametros van en linea, justo
; despues del jsr (ver print_at): 7 bytes por uso en vez de 19.
.macro PRINT col, row, label
    jsr print_at
    .byte col, row
    .addr label
.endmacro

; Escribe un texto fijo centrado en la fila (render apagado): 6 bytes por uso
.macro PRINT_CENTER row, label
    jsr print_center_at
    .byte row
    .addr label
.endmacro

; -----------------------------------------------------------------------------
; fill_blank: llena de espacios (30 filas de 32 tiles) la nametable cuyo byte
; alto es A, dejando la PPU lista para seguir escribiendo (render apagado).
; La comparten clear_nametable y draw_strip.
; -----------------------------------------------------------------------------
fill_blank:
    bit PPUSTATUS
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #' '
    ldy #30                 ; 30 filas
@row:
    ldx #32                 ; de 32 tiles
@col:
    sta PPUDATA
    dex
    bne @col
    dey
    bne @row
    rts

; -----------------------------------------------------------------------------
; clear_nametable: llena $2000 con espacios y sus atributos con paleta 0
; (render apagado)
; -----------------------------------------------------------------------------
clear_nametable:
    lda #$20
    jsr fill_blank
    lda #0                  ; 64 bytes de atributos
    ldx #64
@attr:
    sta PPUDATA
    dex
    bne @attr
    rts

; -----------------------------------------------------------------------------
; print_direct: escribe el texto de ptr en addr (render apagado)
; print_more:   sigue escribiendo justo después de lo último que se escribió
; -----------------------------------------------------------------------------
print_direct:
    bit PPUSTATUS
    lda addr+1
    sta PPUADDR
    lda addr
    sta PPUADDR
print_more:
    ldy #0
@loop:
    lda (ptr),y
    beq @done
    sta PPUDATA
    iny
    bne @loop
@done:
    rts

; strlen: A = largo del texto de ptr
strlen:
    ldy #0
@loop:
    lda (ptr),y
    beq @done
    iny
    bne @loop
@done:
    tya
    rts

; -----------------------------------------------------------------------------
; print_at / print_center_at: lo que expanden PRINT y PRINT_CENTER. Los
; parametros van como datos justo despues del jsr:
;   jsr print_at         .byte col, row   .addr texto
;   jsr print_center_at  .byte row        .addr texto
; La direccion de retorno que dejo el jsr apunta a su ultimo byte, o sea que
; los parametros empiezan en tmp + 1. Se arma addr y ptr, y se deja en la pila
; como retorno la direccion del ultimo parametro: el rts de print_direct
; sigue en la instruccion que viene despues de los datos.
; Usa tmp; solo con el dibujo apagado.
; -----------------------------------------------------------------------------
print_at:
    pla
    sta tmp
    pla
    sta tmp+1
    ldy #4
    lda (tmp),y             ; texto (alto)
    sta ptr+1
    dey
    lda (tmp),y             ; texto (bajo)
    sta ptr
    dey
    lda (tmp),y             ; fila
    pha
    dey
    lda (tmp),y             ; columna
    tax
    pla
    jsr text_addr
    ldy #4                  ; largo de los parametros
    bne print_ret           ; siempre
print_center_at:
    pla
    sta tmp
    pla
    sta tmp+1
    ldy #3
    lda (tmp),y             ; texto (alto)
    sta ptr+1
    dey
    lda (tmp),y             ; texto (bajo)
    sta ptr
    dey
    lda (tmp),y             ; fila
    jsr center_addr
    ldy #3                  ; largo de los parametros
print_ret:
    tya                     ; retorno = tmp + largo (ultimo parametro)
    clc
    adc tmp
    tax
    lda tmp+1
    adc #0
    pha
    txa
    pha
    jmp print_direct

; print_centered: escribe el texto de ptr centrado en la fila A (render apagado)
print_centered:
    jsr center_addr
    jmp print_direct

; text_addr: addr = $2000 + fila A * 32 + columna X
text_addr:
    sta addr
    lda #0
    sta addr+1
    ldy #5                  ; fila * 32 = fila << 5, en 16 bits
@shift:
    asl addr
    rol addr+1
    dey
    bne @shift
    txa
    clc
    adc addr
    sta addr
    lda addr+1
    adc #$20
    sta addr+1
    rts

; center_addr: addr = inicio de la fila A + (32 - largo) / 2
center_addr:
    ldx #0
    jsr text_addr
    ; + (32 - largo) / 2
    jsr strlen
    eor #$FF                ; -largo = (largo xor $FF) + 1
    sec
    adc #32
    lsr a
    clc
    adc addr
    sta addr
    rts

; -----------------------------------------------------------------------------
; vbuf_text: pone en la cola el texto de ptr para escribirse en addr,
; rellenando con espacios hasta A caracteres (así borra lo que había antes).
;
; Formato de vbuf: [dir alta, dir baja, largo, bytes...] repetido, y un 0
; al final (ninguna dirección de nametable empieza con $00).
; -----------------------------------------------------------------------------
vbuf_text:
    sta tmp                 ; ancho total
    ldx vbuf_len
    lda addr+1
    sta vbuf,x
    inx
    lda addr
    sta vbuf,x
    inx
    lda tmp
    sta vbuf,x
    inx
    ldy #0
@copy:
    cpy tmp
    beq @end
    lda (ptr),y
    beq @pad
    sta vbuf,x
    inx
    iny
    jmp @copy
@pad:
    lda #' '
@pad_loop:
    cpy tmp
    beq @end
    sta vbuf,x
    inx
    iny
    jmp @pad_loop
@end:
    lda #0
    sta vbuf,x              ; terminador (el siguiente vbuf_text lo sobrescribe)
    stx vbuf_len
    rts

; -----------------------------------------------------------------------------
; flush_vbuf: copia la cola a la PPU y la vacía. La llama la NMI; también se
; puede llamar con el render apagado para dibujar algo de inmediato.
; -----------------------------------------------------------------------------
flush_vbuf:
    bit PPUSTATUS
    ldx #0
@entry:
    lda vbuf,x
    beq @done
    sta PPUADDR
    lda vbuf+1,x
    sta PPUADDR
    ldy vbuf+2,x
    inx
    inx
    inx
@byte:
    lda vbuf,x
    sta PPUDATA
    inx
    dey
    bne @byte
    jmp @entry
@done:
    lda #0
    sta vbuf
    sta vbuf_len
    rts

; -----------------------------------------------------------------------------
; num_to_text: convierte tmp (16 bits) a texto decimal en numstr y deja ptr
; apuntando al primer dígito (sin ceros a la izquierda).
;
; Método: cuántas veces cabe 10000 (restando), luego 1000, 100, 10 y 1.
; -----------------------------------------------------------------------------
num_to_text:
    ldx #0
@digit:
    lda #'0'
    sta numstr,x
@subtract:
    sec
    lda tmp
    sbc pow10_lo,x
    tay
    lda tmp+1
    sbc pow10_hi,x
    bcc @next               ; ya no cabe: siguiente dígito
    sta tmp+1
    sty tmp
    inc numstr,x
    jmp @subtract
@next:
    inx
    cpx #5
    bne @digit
    lda #0
    sta numstr+5

    ; Saltar ceros a la izquierda (pero dejar al menos un dígito)
    ldx #0
@skip:
    lda numstr,x
    cmp #'0'
    bne @found
    inx
    cpx #4
    bne @skip
@found:
    txa
    clc
    adc #<numstr
    sta ptr
    lda #>numstr
    adc #0
    sta ptr+1
    rts

pow10_lo: .byte <10000, <1000, <100, <10, <1
pow10_hi: .byte >10000, >1000, >100, >10, >1
