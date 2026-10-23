; =============================================================================
; records.s - Récords guardados en la RAM con batería del cartucho
;
; El MMC3 puede mapear 8 KB de RAM en $6000-$7FFF. Con el bit de batería del
; encabezado iNES, el emulador (o el flash cart) la guarda en un archivo .sav,
; y los datos sobreviven aunque se apague. Se habilita con el registro $A001.
;
; Diseño de lo que guardamos:
;   $6000  firma "NBR1" (4 bytes): si no está, la RAM está vacía o es de otro juego
;   $6004  suma de comprobación de la tabla (2 bytes): detecta datos corruptos
;   $6008  tabla de REC_MAX registros de REC_SIZE bytes, uno por
;          (canción, instrumento, dificultad)
;
; Registro (13 bytes):
;   0-1  id de la canción (hash de su título y juego: así el récord no se pega
;        a otra canción si cambia el orden o el número de canciones del cartucho)
;   2    clave = instrumento * 4 + dificultad ($FF = registro libre)
;   3-8  puntaje: 6 dígitos decimales, uno por byte (como score_digits)
;   9-11 iniciales (3 letras)
;   12   estrellas (0-5)
;
; Si la firma o la suma no cuadran al encender, la tabla se formatea vacía.
; Los récords de "sin fallo" o de una canción perdida no se guardan.
; =============================================================================

RECORDS      = $6000
REC_MAGIC    = RECORDS
REC_SUM      = RECORDS + 4
REC_TABLE    = RECORDS + 8
REC_SIZE     = 13
REC_MAX      = 250                      ; 250 * 13 = 3250 bytes; hay 180 combinaciones posibles con 15 canciones
REC_FREE     = $FF                      ; clave de un registro sin usar

R_ID         = 0
R_KEY        = 2
R_SCORE      = 3
R_INI        = 9
R_STARS      = 12

; -----------------------------------------------------------------------------
; records_init: habilita la RAM y comprueba la tabla; si no es válida, la
; deja vacía
; -----------------------------------------------------------------------------
records_init:
    lda #$80                    ; RAM habilitada y sin protección contra escritura
    sta MMC3_PRG_RAM
    ldx #3
@magic:
    lda REC_MAGIC,x
    cmp rec_magic_text,x
    bne @format
    dex
    bpl @magic
    jsr rec_checksum            ; ¿la suma coincide?
    lda addr
    cmp REC_SUM
    bne @format
    lda addr+1
    cmp REC_SUM+1
    bne @format
    rts
@format:
    ; Todos los registros libres
    lda #<REC_TABLE
    sta rec_ptr
    lda #>REC_TABLE
    sta rec_ptr+1
    ldx #REC_MAX
@free:
    ldy #R_KEY
    lda #REC_FREE
    sta (rec_ptr),y
    clc
    lda rec_ptr
    adc #REC_SIZE
    sta rec_ptr
    bcc @same_page
    inc rec_ptr+1
@same_page:
    dex
    bne @free
    ldx #3
@write_magic:
    lda rec_magic_text,x
    sta REC_MAGIC,x
    dex
    bpl @write_magic
    ; sigue en rec_update_sum

; rec_update_sum: recalcula y guarda la suma de comprobación (tras cambiar la tabla)
rec_update_sum:
    jsr rec_checksum
    lda addr
    sta REC_SUM
    lda addr+1
    sta REC_SUM+1
    rts

; rec_checksum: addr = suma (16 bits) de todos los bytes de la tabla
rec_checksum:
    lda #<REC_TABLE
    sta ptr
    lda #>REC_TABLE
    sta ptr+1
    lda #0
    sta addr
    sta addr+1
    lda #<(REC_MAX * REC_SIZE)
    sta tmp
    lda #>(REC_MAX * REC_SIZE)
    sta tmp+1
    ldy #0
@loop:
    lda (ptr),y
    clc
    adc addr
    sta addr
    bcc @no_carry
    inc addr+1
@no_carry:
    iny
    bne @same_page
    inc ptr+1
@same_page:
    lda tmp                     ; contador de bytes que faltan, de 16 bits
    bne @dec_low
    dec tmp+1
@dec_low:
    dec tmp
    lda tmp
    ora tmp+1
    bne @loop
    rts

rec_magic_text: .byte "NBR1"

; -----------------------------------------------------------------------------
; compute_song_hash: song_hash = identificador de la canción elegida (song_ptr),
; calculado con su título y el juego. Se rota 1 bit a la izquierda y se mezcla
; cada letra con XOR.
; -----------------------------------------------------------------------------
compute_song_hash:
    lda #0
    sta song_hash
    sta song_hash+1
    ldy #SONG_TITLE
    jsr ptr_from_song
    jsr @hash_string
    ldy #SONG_GAME
    jsr ptr_from_song
@hash_string:
    ldy #0
@loop:
    lda (ptr),y
    beq @done
    tax                         ; la letra
    lda song_hash
    asl a
    sta song_hash
    lda song_hash+1
    rol a
    sta song_hash+1
    bcc @no_wrap
    inc song_hash               ; el bit que salió por arriba entra por abajo
@no_wrap:
    txa
    eor song_hash
    sta song_hash
    iny
    bne @loop
@done:
    rts

; -----------------------------------------------------------------------------
; rec_find: busca el registro de la canción elegida con la clave A.
;   carry = 1: lo encontró (rec_ptr apunta a él)
;   carry = 0: no hay; rec_free apunta al primer registro libre (byte alto 0 =
;              la tabla está llena)
; -----------------------------------------------------------------------------
rec_find:
    sta tmp                     ; clave que se busca
    lda #0
    sta rec_free+1
    lda #<REC_TABLE
    sta rec_ptr
    lda #>REC_TABLE
    sta rec_ptr+1
    ldx #REC_MAX
@next:
    ldy #R_KEY
    lda (rec_ptr),y
    cmp #REC_FREE
    beq @free
    cmp tmp
    bne @advance
    ldy #R_ID
    lda (rec_ptr),y
    cmp song_hash
    bne @advance
    iny
    lda (rec_ptr),y
    cmp song_hash+1
    bne @advance
    sec
    rts
@free:
    lda rec_free+1
    bne @advance                ; ya teníamos un hueco
    lda rec_ptr
    sta rec_free
    lda rec_ptr+1
    sta rec_free+1
@advance:
    clc
    lda rec_ptr
    adc #REC_SIZE
    sta rec_ptr
    bcc @same_page
    inc rec_ptr+1
@same_page:
    dex
    bne @next
    clc
    rts

; rec_key: A = clave (instrumento * 4 + dificultad) del jugador cargado en pstate
rec_key:
    lda cur_instrument
    asl a
    asl a
    ora cur_difficulty
    rts

; -----------------------------------------------------------------------------
; rec_check_new: new_record = 1 si el jugador cargado superó el récord guardado
; de su canción, instrumento y dificultad (o no hay ninguno) y puede grabar uno:
; no perdió, no jugó sin fallo, y hay lugar en la tabla.
; -----------------------------------------------------------------------------
rec_check_new:
    lda #0
    sta new_record
    lda failed
    ora no_fail
    bne @done
    ldx #5                      ; ¿hizo algún punto?
    lda #0
@any:
    ora score_digits,x
    dex
    bpl @any
    cmp #0
    beq @done
    jsr rec_key
    jsr rec_find
    bcc @absent
    ldx #0                      ; comparar el puntaje con el guardado, dígito por dígito
@compare:
    txa
    clc
    adc #R_SCORE
    tay
    lda score_digits,x
    cmp (rec_ptr),y
    bne @different
    inx
    cpx #6
    bne @compare
    rts                         ; igual: no es récord
@different:
    bcc @done                   ; menor
    bcs @new
@absent:
    lda rec_free+1
    beq @done                   ; la tabla está llena
@new:
    lda #1
    sta new_record
@done:
    rts

; -----------------------------------------------------------------------------
; rec_save: guarda el récord del jugador cargado, con las iniciales de ini
; -----------------------------------------------------------------------------
rec_save:
    jsr rec_key
    jsr rec_find
    bcs @have
    lda rec_free+1
    beq @done                   ; no hay lugar
    lda rec_free
    sta rec_ptr
    lda rec_free+1
    sta rec_ptr+1
@have:
    ldy #R_ID
    lda song_hash
    sta (rec_ptr),y
    iny
    lda song_hash+1
    sta (rec_ptr),y
    jsr rec_key
    ldy #R_KEY
    sta (rec_ptr),y
    ldx #0
@score:
    txa
    clc
    adc #R_SCORE
    tay
    lda score_digits,x
    sta (rec_ptr),y
    inx
    cpx #6
    bne @score
    ldx #0
@initials:
    txa
    clc
    adc #R_INI
    tay
    lda ini,x
    sta (rec_ptr),y
    inx
    cpx #3
    bne @initials
    ldy #R_STARS
    lda stars
    sta (rec_ptr),y
    jmp rec_update_sum
@done:
    rts
