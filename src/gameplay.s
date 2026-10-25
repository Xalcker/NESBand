; =============================================================================
; gameplay.s - Control, aciertos, fallos y puntaje
;
; Formato del chart (lo genera `nesband import-song` en src/songs/*/chart.s):
; una lista de entradas de 2 bytes, ordenada por tiempo:
;     .byte cuadros       ; cuántos cuadros después de la entrada anterior suena
;     .byte carriles      ; bit 0 = verde ... bit 4 = naranja (varios = acorde)
; y termina con carriles = $FF (CHART_END). Si entre dos notas hay más de 255
; cuadros, el generador mete entradas de relleno sin carriles (carriles = 0).
;
; Notas sostenidas: una nota con el bit $40 (CHART_SUSTAIN) tiene cola, y su fin
; es una entrada posterior con el bit $80 (CHART_RELEASE) y los carriles que se
; sueltan en ese cuadro. Ver hold_start. (CHART_END = $FF también tiene el
; bit $80, así que "bit 7 = no es una nota" vale para ambos.)
; El bit $20 (CHART_STAR) marca las notas de las frases de poder estelar.
;
; Guardar la distancia en vez del cuadro completo ahorra un byte por nota,
; pero obliga a que cada lector lleve la cuenta del cuadro donde va
; (chart_step). El chart no dice en qué fila se dibuja cada gema: eso depende
; de la velocidad de la autopista (ver build_row en highway.s).
;
; Cada carril lleva su propio puntero a su siguiente nota pendiente
; (lane_ptr) y el cuadro de esa nota (lane_frame). Así cada gema de un
; acorde se juzga por separado, como en la batería de Rock Band.
; =============================================================================

; -----------------------------------------------------------------------------
; read_pad: lee los dos controles (pad_buttons / pad_pressed). En los menús,
; buttons/pressed quedan con los del control 1; en el juego, load_player
; pone los del control de cada jugador.
;
; El control es un registro de desplazamiento: se "congela" escribiendo 1 y
; luego 0 en $4016, y después cada lectura de $4016 (control 1) o $4017
; (control 2) entrega un botón en el bit 0, en orden: A, B, Select, Start,
; Arriba, Abajo, Izquierda, Derecha.
;
; Glitch del DPCM: si el chip de sonido está leyendo un sample justo cuando
; leemos el control, se puede perder un bit y aparecen botones que nadie
; presionó. Por eso leemos hasta que dos lecturas seguidas coincidan.
; -----------------------------------------------------------------------------
read_pad:
    ldx #0
@pad:
    lda pad_buttons,x
    sta pad_prev,x
    jsr read_pad_once
@retry:
    sta tmp                 ; lectura anterior
    jsr read_pad_once
    cmp tmp
    bne @retry
    sta pad_buttons,x

    ; recién presionados = están ahora y no estaban antes
    lda pad_prev,x
    eor #$FF
    and pad_buttons,x
    sta pad_pressed,x
    inx
    cpx #MAX_PLAYERS
    bne @pad

    lda pad_buttons
    sta buttons
    lda pad_pressed
    sta pressed
    rts

; read_pad_once: A = botones del control X (0 o 1)
read_pad_once:
    lda #1
    sta tmp+1               ; este 1 sale por el carry después de 8 rotaciones: fin del ciclo
    sta JOY1
    lda #0
    sta JOY1
@loop:
    lda JOY1,x              ; $4016 o $4017
    lsr a                   ; bit 0 -> carry
    rol tmp+1               ; carry -> bit 0, el bit 7 sale al carry
    bcc @loop
    lda tmp+1
    rts

; -----------------------------------------------------------------------------
; judge_lanes: para cada carril, revisa su siguiente nota
; -----------------------------------------------------------------------------
judge_lanes:
    lda #0
    sta lane
@lane_loop:
    ldx lane
    lda lanes_seeking       ; ¿este carril aún busca su siguiente nota (lane_seek por partes)?
    and lane_bit,x
    beq @judge
    lda lane_ptr_lo,x       ; sí: sigue buscando desde donde se quedó y no juzga nada este cuadro
    sta ptr
    lda lane_ptr_hi,x
    sta ptr+1
    lda lane_frame_lo,x
    sta seek_frame
    lda lane_frame_hi,x
    sta seek_frame+1
    jsr lane_seek
    jmp @next
@judge:
    lda lane_ptr_lo,x
    sta ptr
    lda lane_ptr_hi,x
    sta ptr+1

    ldy #1
    lda (ptr),y             ; carriles
    cmp #CHART_END
    beq @no_more_notes      ; fin del chart para este carril

    ; tmp = cuadro en que la nota toca el aro
    lda lane_frame_lo,x
    sta tmp
    lda lane_frame_hi,x
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
    bcc @overhit
    jsr note_hit
    jmp @advance

@no_more_notes:
    ; Ya no hay notas en este carril: presionarlo también es golpe al aire
    lda pressed
    and lane_button,x
    beq @next
@overhit:
    ; Golpe al aire (botón sin nota cerca): rompe el combo y calla el
    ; instrumento, como el "overstrum" de Guitar Hero. Si no, machacar
    ; botones sin parar acertaría todo sin perder nunca el combo.
    ; La nota pendiente sigue esperando: no se cuenta como fallada.
    jsr air_hit
    jmp @next

@not_pressed:
    ; ¿Ya se pasó la nota? (diff > WINDOW)
    lda diff+1
    bmi @next               ; negativo: todavía no llega
    bne @miss               ; 256 cuadros o más de retraso
    lda diff
    cmp #WINDOW + 1
    bcc @next
@miss:
    jsr star_missed         ; si era una nota estelar, la frase ya no cuenta
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
; chart_first: ptr = chart_start y seek_frame = cuadro de su primera entrada
; chart_step:  ptr pasa a la siguiente entrada y seek_frame suma su distancia
; (solo usan A e Y)
; -----------------------------------------------------------------------------
chart_first:
    lda chart_start
    sta ptr
    lda chart_start+1
    sta ptr+1
    ldy #0
    lda (ptr),y
    sta seek_frame
    sty seek_frame+1
@skip:                      ; práctica desde un punto: omite lo que ya pasó (skip_frame = 0: nada)
    lda seek_frame
    cmp skip_frame
    lda seek_frame+1
    sbc skip_frame+1
    bcs @done               ; seek_frame >= skip_frame
    ldy #1
    lda (ptr),y
    cmp #CHART_END
    beq @done
    jsr chart_step
    jmp @skip
@done:
    rts

chart_step:
    clc
    lda ptr
    adc #CHART_ENTRY
    sta ptr
    bcc @no_carry
    inc ptr+1
@no_carry:
    ldy #0
    lda (ptr),y             ; cuadros desde la entrada anterior
    clc
    adc seek_frame
    sta seek_frame
    bcc @done
    inc seek_frame+1
@done:
    rts

; -----------------------------------------------------------------------------
; lane_seek: a partir de ptr/seek_frame, busca la siguiente nota que use el
; carril X (o el final del chart) y la guarda en lane_ptr/lane_frame.
; No modifica X.
;
; Revisa a lo más SEEK_BUDGET entradas por llamada: en un chart con huecos largos
; en un carril, recorrerlo entero en un solo cuadro costaba ~12 000 ciclos (un cuadro
; atrasado). Si no la encuentra en ese presupuesto, deja en lane_ptr/lane_frame la
; entrada por revisar (ya avanzada) y marca el carril en lanes_seeking; judge_lanes
; la continúa en los cuadros siguientes. Las notas de un chart están a 5 cuadros o
; más una de otra, así que la búsqueda termina mucho antes de que la nota llegue a la
; ventana de juicio. Al encontrarla (o el fin del chart) limpia el bit.
; -----------------------------------------------------------------------------
SEEK_BUDGET = 24

lane_seek:
    lda #SEEK_BUDGET
    sta seek_left
@check:
    ldy #1
    lda (ptr),y             ; carriles
    bmi @release            ; fin de cola (o el fin del chart): no es una nota
    and chart_bit,x         ; (con ESPEJO, el carril X toca las notas del carril de enfrente)
    bne @found
@step:
    clc                     ; chart_step en línea (sin jsr/rts: este bucle es el que más se repite)
    lda ptr
    adc #CHART_ENTRY
    sta ptr
    bcc @no_carry
    inc ptr+1
@no_carry:
    ldy #0
    lda (ptr),y             ; cuadros desde la entrada anterior
    clc
    adc seek_frame
    sta seek_frame
    bcc @no_carry2
    inc seek_frame+1
@no_carry2:
    dec seek_left
    bne @check
    lda lanes_seeking       ; se acabó el presupuesto: queda pendiente
    ora lane_bit,x
    sta lanes_seeking
    bne @save               ; (siempre)
@release:
    cmp #CHART_END
    bne @step
@found:
    lda lane_bit,x          ; la encontró: ya no está buscando
    eor #$FF
    and lanes_seeking
    sta lanes_seeking
@save:
    lda ptr
    sta lane_ptr_lo,x
    lda ptr+1
    sta lane_ptr_hi,x
    lda seek_frame
    sta lane_frame_lo,x
    lda seek_frame+1
    sta lane_frame_hi,x
    rts

; lane_advance: pasa el carril `lane` a su siguiente nota
lane_advance:
    ldx lane
    lda lane_ptr_lo,x
    sta ptr
    lda lane_ptr_hi,x
    sta ptr+1
    lda lane_frame_lo,x
    sta seek_frame
    lda lane_frame_hi,x
    sta seek_frame+1
    jsr chart_step
    jmp lane_seek

; -----------------------------------------------------------------------------
; note_hit / note_miss (una nota que se pasó sin tocarla) / air_hit (golpe al aire)
; -----------------------------------------------------------------------------
note_hit:
    lda hud_dirty
    ora #HUD_SCORE | HUD_COMBO
    sta hud_dirty           ; puntaje y combo cambiaron
    lda #0
    sta player_muted        ; acertaste: tu instrumento vuelve a sonar
    lda song_frame          ; un acorde (varias notas en el mismo cuadro) da la vida de una sola nota:
    cmp life_hit_frame      ; sus fallos cuestan una vez por el respiro (life_grace), y si cada nota
    beq @no_life            ; sumara, quien acierta la mitad del chart sobreviviría con acordes
    sta life_hit_frame
    lda #LIFE_HIT
    jsr life_up
@no_life:
    jsr star_note_hit       ; (antes que hold_start, que mueve ptr)
    jsr hold_start          ; si la nota tiene cola, empieza a sostenerse
    jsr start_fx            ; llamarada sobre el aro
    inc notes_hit
    bne @counted
    inc notes_hit+1
@counted:
    jsr erase_gem
    jsr combo_inc
    jmp score_add

note_miss:
    jsr combo_break
    jmp life_down           ; y pierdes vida (según la dificultad)

air_hit:
    jsr combo_break
    lda #LIFE_AIR           ; un golpe al aire cuesta menos que perder una nota
    jmp life_lose

combo_break:
    lda #0
    sta combo_digits
    sta combo_digits+1
    sta combo_digits+2
    sta combo_bin
    sta combo_bin+1
    lda #1
    sta multiplier
    sta player_muted        ; fallaste: tu instrumento se calla
    lda hud_dirty
    ora #HUD_SCORE | HUD_COMBO
    sta hud_dirty           ; el combo volvió a 0 y el multiplicador a x1
    rts

; -----------------------------------------------------------------------------
; Vida (el medidor de rendimiento)
;
; Empieza en dos tercios. Acertar sube 1; perder una nota baja 2 (1 en fácil) y un
; golpe al aire baja 1, así que hay que acertar la mayoría (se aguanta con 2 de
; cada 3 aciertos, pero una mala racha con poca vida sí cuesta la canción). Si
; llega a 0, el jugador pierde: su instrumento calla y deja de jugar. En
; "sin fallo" (no_fail) no pasa nada, y el medidor ni se dibuja.
;
; Cómo se llegó a estos números (issue #7): con 4 de penalización y empezando
; a la mitad, en experto bastaban 6 fallos para perder. Se simuló un jugador cuyos
; errores vienen en rachas (como los humanos) en charts de 150 a 700 notas: con
; 90% de aciertos terminaba la canción solo 15-43% de las veces; con estos
; valores, el 100%. Uno que acierta 70% o menos sigue perdiendo casi siempre.
; Además, tras perder vida hay un respiro de LIFE_GRACE cuadros (life_grace) en el
; que los fallos no cuestan más: en pasajes con notas repetidas en un carril, una
; sola nota perdida hace que las siguientes caigan fuera de la ventana antes de
; poder tocarlas, y sin el respiro cada una se cobraría aparte.
; -----------------------------------------------------------------------------

; life_up: A = puntos de vida que se ganan
life_up:
    clc
    adc life
    cmp #LIFE_MAX + 1
    bcc @store
    lda #LIFE_MAX
@store:
    sta life
    rts

; life_down: pierde la vida de una nota perdida, según la dificultad del jugador
life_down:
    ldx cur_difficulty
    lda life_penalty,x
    ; sigue en life_lose

; life_lose: A = puntos de vida que se pierden (y pierde si llega a 0)
life_lose:
    ldx no_fail
    bne @done
    ldx opt_practice        ; la práctica es sin fallo
    bne @done
    ldx failed
    bne @done
    ldx life_grace          ; todavía en el respiro del fallo anterior: este no cuesta vida
    bne @done
    ldx #LIFE_GRACE
    stx life_grace
    eor #$FF                ; life - A = life + (A xor $FF) + 1
    sec
    adc life
    bcs @store              ; (carry = 1: alcanzó, no hubo préstamo)
    lda #0
@store:
    sta life
    bne @done
    lda #1                  ; se acabó la vida
    sta failed
    sta player_muted
    lda hud_dirty
    ora #HUD_COMBO          ; el renglón del combo pasa a decir "FALLASTE"
    sta hud_dirty
@done:
    rts

; Lo que se pierde por una nota perdida, por dificultad. Con +1 por acierto, la
; vida se sostiene acertando 1 de cada 2 notas en fácil y 2 de cada 3 en las demás.
;                 fácil medio difícil experto
life_penalty:  .byte 1,    2,    2,      2

; -----------------------------------------------------------------------------
; start_fx: enciende la llamarada del carril `lane` del jugador actual.
; Cada carril de cada jugador tiene su ranura (jugador * 5 + carril), así que
; un acorde enciende varias a la vez y volver a acertar en el mismo carril
; reinicia la animación.
; Los sprites se ponen en pantalla en update_fx (play.s).
; -----------------------------------------------------------------------------
start_fx:
    lda drum_look
    beq @one_flame
    lda lane
    cmp #4
    beq @kick_flames        ; batería: el bombo no tiene carril propio (es la barra de los 4 pads)
@one_flame:
    lda #FX_FRAMES
    jmp set_fx

    ; Un bombo acertado enciende la llamarada en los 4 carriles a la vez. set_fx lee `lane`, así que
    ; se recorre con él y al final vuelve a valer 4.
@kick_flames:
    lda #0
    sta lane
@flame_lane:
    lda #FX_FRAMES
    jsr set_fx
    inc lane
    lda lane
    cmp #4
    bne @flame_lane
    rts                     ; (lane = 4 otra vez)

set_fx:                     ; A = cuadros que durará la llamarada
    sta tmp
    jsr mode_lane_column        ; columna del carril (deja X = jugador)
    asl a
    asl a
    asl a                   ; x 8 = pixel donde empieza el carril
    clc
    adc #4                  ; el sprite mide 8 px y el carril 16: centrado
    pha
    lda player
    beq @slot               ; jugador 0: las ranuras 0-4
    lda #NUM_LANES          ; jugador 1: las ranuras 5-9
@slot:
    clc
    adc lane
    tax
    pla
    sta fx_x,x
    lda tmp
    sta fx_timer,x
    lda star_hit            ; frase estelar completa: además cae el rayo sobre este carril
    beq @no_bolt
    lda fx_x,x
    ldy player
    sta bolt_x,y
    lda #BOLT_FRAMES
    sta bolt_timer,y
    lda #0
    sta star_hit
@no_bolt:
    rts

; -----------------------------------------------------------------------------
; Poder estelar
;
; Algunas notas del chart (CHART_STAR) forman frases de unas 4 notas seguidas.
; Si aciertas todas, la barra de poder sube 25%. Con la barra a la mitad o más,
; Select activa el poder: el puntaje vale el doble (x2, x4, x6, x8) mientras la
; barra se vacía. Las frases que completes con el poder activo la rellenan.
;
; El juego reconoce el final de una frase porque la siguiente nota del chart
; ya no es estelar (star_next). star_failed recuerda si fallaste alguna nota
; de la frase en curso.
; -----------------------------------------------------------------------------

; star_next: carry = 1 si la siguiente nota del chart (después de la de ptr)
; también es estelar. Usa star_ptr: no mueve ptr.
star_next:
    lda ptr
    sta star_ptr
    lda ptr+1
    sta star_ptr+1
@step:
    clc
    lda star_ptr
    adc #CHART_ENTRY
    sta star_ptr
    bcc @read
    inc star_ptr+1
@read:
    ldy #1
    lda (star_ptr),y
    bmi @event
    and #%00011111
    beq @step               ; entrada de relleno: seguimos
    lda (star_ptr),y
    and #CHART_STAR
    beq @no
    sec
    rts
@event:
    cmp #CHART_END
    bne @step               ; fin de cola: seguimos
@no:
    clc
    rts

; star_note_hit: se acaba de acertar la nota de ptr
star_note_hit:
    ldy #1
    lda (ptr),y
    and #CHART_STAR
    beq @done
    jsr star_next
    bcs @done               ; la frase sigue
    lda star_failed         ; era la última nota de la frase
    bne @clear
    lda #1
    sta star_hit            ; frase completa: cae el rayo sobre este carril (lo arma set_fx)
    lda #LIFE_STAR
    jsr life_up
    lda star_energy         ; y sube la barra 25%
    clc
    adc #STAR_PHRASE
    cmp #STAR_MAX + 1
    bcc @store
    lda #STAR_MAX
@store:
    sta star_energy
    lda hud_dirty
    ora #HUD_STAR
    sta hud_dirty
@clear:
    lda #0
    sta star_failed
@done:
    rts

; star_missed: se acaba de fallar la nota de ptr (se pasó sin tocarla)
star_missed:
    ldy #1
    lda (ptr),y
    and #CHART_STAR
    beq @done
    lda #1
    sta star_failed
    jsr star_next
    bcs @done
    lda #0                  ; era la última de la frase: la siguiente empieza limpia
    sta star_failed
@done:
    rts

PS_GRACE = life_grace - pstate

; update_star: una vez por cuadro, para el jugador actual: Select activa el
; poder (o, en Co-Op, si el compañero cayó, lo revive con media barra) y,
; mientras está activo, la barra se vacía
update_star:
    lda pressed
    and #BTN_SELECT
    beq @drain
    lda game_mode           ; Co-Op: si el compañero cayó, Select lo revive (en vez de activar el poder)
    beq @activate
    lda player
    eor #1
    tax
    ldy player_offset,x     ; Y = donde empieza la copia guardada del compañero
    lda player_save + PS_FAILED,y
    beq @activate           ; sigue en pie
    lda star_energy
    cmp #STAR_MIN
    bcc @drain              ; no alcanza la media barra para revivirlo
    sec
    sbc #STAR_MIN           ; cuesta media barra
    sta star_energy
    bne @energy_left
    sta star_active         ; (A = 0) sin energía no se puede seguir con el poder activo
@energy_left:
    lda #0
    sta player_save + PS_FAILED,y
    sta player_save + PS_MUTED,y
    lda #LIFE_REVIVE
    sta player_save + PS_LIFE,y
    lda #LIFE_GRACE
    sta player_save + PS_GRACE,y
    lda player_save + (hud_dirty - pstate),y
    ora #HUD_COMBO          ; su renglón del combo deja de decir "FALLASTE"
    sta player_save + (hud_dirty - pstate),y
    lda hud_dirty
    ora #HUD_STAR | HUD_SCORE
    sta hud_dirty
    lda #SFX_ACEPTAR
    jsr play_sfx
    jmp @drain
@activate:
    lda star_active
    bne @drain
    lda star_energy
    cmp #STAR_MIN
    bcc @drain
    lda #1
    sta star_active
    lda #STAR_DRAIN
    sta star_timer
    lda hud_dirty
    ora #HUD_STAR | HUD_SCORE ; el multiplicador cambia
    sta hud_dirty
    lda #SFX_ACEPTAR
    jsr play_sfx
@drain:
    lda game_mode           ; Co-Op: la barra es de la banda y se pasa por aquí una vez por
    beq @drain_now          ; jugador; solo el jugador 1 la gasta, o se vaciaría al doble
    lda player
    bne @done
@drain_now:
    lda star_active
    beq @done
    dec star_timer
    bne @done
    lda #STAR_DRAIN
    sta star_timer
    dec star_energy
    lda hud_dirty
    ora #HUD_STAR
    sta hud_dirty
    lda star_energy
    bne @done
    sta star_active         ; se acabó la energía
    lda hud_dirty
    ora #HUD_SCORE
    sta hud_dirty
@done:
    rts

; eff_multiplier: A = multiplicador de puntaje (el del combo, x2 con el poder activo)
eff_multiplier:
    lda multiplier
    ldx star_active
    beq @done
    asl a
@done:
    rts

; -----------------------------------------------------------------------------
; Notas sostenidas
;
; Una nota con CHART_SUSTAIN tiene una cola: su fin es una entrada posterior
; del chart con CHART_RELEASE y el bit de su carril. Al acertar la nota,
; hold_start busca esa entrada y guarda su cuadro (hold_end). Mientras el
; botón siga presionado hasta ese cuadro, update_holds suma puntos. Soltarlo
; antes solo deja de dar puntos: no rompe el combo.
; -----------------------------------------------------------------------------

; hold_start: la nota que se acaba de acertar es la de `lane` (apuntada por ptr)
hold_start:
    ldx lane
    lda #0
    sta hold_on,x
    lda cur_instrument      ; batería: el bit $40 es un platillo, no una cola. (Si no saliéramos aquí,
    cmp #INSTR_DRUMS        ; @scan recorrería todo el chart buscando un fin de cola que no existe.)
    beq @done
    ldy #1
    lda (ptr),y
    and #CHART_SUSTAIN
    beq @done               ; nota normal
    lda lane_frame_lo,x     ; seek_frame = cuadro de la nota; avanzamos hasta su fin
    sta seek_frame
    lda lane_frame_hi,x
    sta seek_frame+1
@scan:
    jsr chart_step          ; (no toca X)
    ldy #1
    lda (ptr),y
    bmi @event
    jmp @scan               ; una nota (de cualquier carril): seguimos buscando
@event:
    cmp #CHART_END
    beq @done               ; no debería pasar: toda cola tiene su fin
    and chart_bit,x
    beq @scan               ; es el fin de la cola de otro carril
    lda seek_frame
    sta hold_end_lo,x
    lda seek_frame+1
    sta hold_end_hi,x
    lda #1
    sta hold_on,x
@done:
    rts

; update_holds: una vez por cuadro, para el jugador actual (ya juzgado)
update_holds:
    ldx #0
@lane:
    lda hold_on,x
    beq @next
    lda song_frame          ; ¿ya llegó al fin de la cola? (song_frame >= hold_end)
    cmp hold_end_lo,x
    lda song_frame+1
    sbc hold_end_hi,x
    bcs @finish
    lda buttons
    and lane_button,x
    beq @finish             ; soltaste antes: ya no da puntos, y el combo sigue
    stx lane
    lda song_frame
    and #HOLD_TICK
    bne @flame
    jsr score_add_hold      ; cada 8 cuadros
    lda song_frame          ; y cada 32, un poco de vida
    and #%00011111
    bne @flame
    lda song_frame          ; (una sola vez por cuadro: con un acorde sostenido no se duplica)
    cmp life_hit_frame
    beq @flame
    sta life_hit_frame
    lda #LIFE_HOLD
    jsr life_up
@flame:
    lda song_frame          ; la llamarada sigue encendida mientras sostienes, y se anima:
    and #%00000100          ; cada 4 cuadros alterna entre la llama alta y la baja
    beq @tall
    lda #HOLD_FX - 2
    bne @set                ; (siempre)
@tall:
    lda #HOLD_FX
@set:
    jsr set_fx
    ldx lane
    jmp @next
@finish:
    lda #0
    sta hold_on,x
@next:
    inx
    cpx #NUM_LANES
    bne @lane
    rts

; score_add_hold: puntaje += 10 (fijos, sin multiplicador). No cuenta para las
; estrellas: estas salen solo de las notas.
score_add_hold:
    lda hud_dirty
    ora #HUD_SCORE
    sta hud_dirty
    lda #1
    ; (sigue en score_add_tens)

; score_add_tens: puntaje += A * 10, sumando A al dígito de las decenas y
; llevando el acarreo hacia arriba. Compartida por score_add y score_add_hold;
; no toca Y.
score_add_tens:
    ldx #4                  ; dígito de las decenas
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
    rts                     ; se pasó de 999999: se pierde
@store:
    sta score_digits,x
    rts

; -----------------------------------------------------------------------------
; erase_gem: agrega a la cola de la NMI el borrado de la gema (ptr, carril lane)
; -----------------------------------------------------------------------------
erase_gem:
    ldy erase_count
    cpy #MAX_ERASE
    bcc @room               ; (rts aquí: @done quedó lejos con el bloque de la batería)
    rts
@room:

    ; La nota está a pocas filas de cur_row: d = su fila - cur_row cabe en un
    ; byte con signo, y su fila de nametable es cur_vrow - d (mod 30).
    ;   delta = cuadro de la nota - cuadro de cur_row (= song_frame - frame_in_row)
    ;   d     = redondear(delta / fpr) = (delta + half_row) / fpr, hacia abajo
    ; delta es pequeño (de -6 a +11 aprox.): sumándole 8 * fpr queda positivo,
    ; dividimos restando y al final le quitamos 8.
    ldy lane
    lda lane_frame_lo,y
    sec
    sbc song_frame          ; (solo el byte bajo: la diferencia es pequeña)
    clc
    adc frame_in_row
    clc
    adc half_row
    clc
    adc fpr8
    ldx #0                  ; X = cociente
@divide:
    cmp fpr
    bcc @divided
    sbc fpr                 ; (carry = 1 por el cmp)
    inx
    jmp @divide
@divided:
    txa
    sec
    sbc #8
    sta tmp                 ; d
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

    lda drum_look
    beq @one_gem
    lda lane
    cmp #4
    beq @erase_bar          ; batería: el bombo es una barra de lado a lado, no una gema

@one_gem:
    jsr mode_lane_column        ; la gema ocupa las 2 columnas del carril
    clc
    adc addr
    ldy erase_count
    sta erase_lo,y
    lda addr+1
    sta erase_hi,y

    ; Debajo de la gema queda el borde del carril. La NMI escribe este tile y
    ; luego el anterior, que es el interior que le corresponde. (Si en esa
    ; fila había línea de beat, en este carril ya no se vuelve a dibujar.)
    ; Si la nota tiene cola (hold_on), en su fila empieza la cola en vez del interior.
    lda #TILE_EDGE
    ldx lane
    ldy hold_on,x
    beq @tile
    lda lane_tail,x
@tile:
    ldy drum_look
    beq @store_tile
    ; Batería: si el bombo de este mismo acorde aún no se toca, la barra sigue pasando por este carril:
    ; en vez del borde vacío queda su tramo de barra (lo borrará el bombo al tocarse)
    pha
    ldy #1
    lda (ptr),y
    and #%10000
    beq @no_bar_here
    lda lane_ptr_lo+4
    cmp ptr
    bne @no_bar_here
    lda lane_ptr_hi+4
    cmp ptr+1
    bne @no_bar_here
    pla
    lda #TILE_KICK
    jmp @store_tile
@no_bar_here:
    pla
@store_tile:
    ldy erase_count
    sta erase_tile,y
    inc erase_count
@done:
    rts

    ; Batería: se acertó un bombo. Se borra su barra en todos los carriles de la fila, menos donde esté la
    ; gema de un pad del mismo acorde que aún no se toca (esa se borra cuando se toque). `lane` se usa
    ; de contador porque lane_column lo lee: se restaura al final.
@erase_bar:
    ldy #1
    lda (ptr),y
    and #%00001111          ; los pads (carriles 0-3) que tiene esta entrada
    sta tmp
    lda lane
    pha
    lda #0
    sta lane
@bar_lane:
    ldx lane
    cpx #4
    beq @bar_next           ; el bombo no tiene columna (la barra cruza las de los 4 pads)
    lda lane_bit,x
    and tmp
    beq @bar_erase          ; este pad no está en la entrada: ahí solo había barra
    lda lane_ptr_lo,x       ; está, pero ¿ya se tocó? (su carril ya pasó a otra nota)
    cmp ptr
    bne @bar_erase
    lda lane_ptr_hi,x
    cmp ptr+1
    beq @bar_next           ; sigue pendiente: se queda su gema
@bar_erase:
    ldy erase_count
    cpy #MAX_ERASE
    bcs @bar_next
    jsr mode_lane_column
    clc
    adc addr
    ldy erase_count
    sta erase_lo,y
    lda addr+1
    sta erase_hi,y
    lda #TILE_EDGE
    sta erase_tile,y
    inc erase_count
@bar_next:
    inc lane
    lda lane
    cmp #NUM_LANES
    bne @bar_lane
    pla
    sta lane
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
; Se suma 5 a las decenas, tantas veces como el multiplicador. Además
; score_units lleva la cuenta en binario (en unidades de 50) para calcular
; las estrellas al final.
; -----------------------------------------------------------------------------
score_add:
    lda score_units
    clc
    adc multiplier
    sta score_units
    bcc @units_ok
    inc score_units+1
@units_ok:
    jsr eff_multiplier      ; (las estrellas solo cuentan el multiplicador del combo)
    tay
@times:
    lda #5
    jsr score_add_tens
    dey
    bne @times
    rts

; Botón de cada carril:  verde      rojo      amarillo    azul   naranja
lane_button:    .byte    BTN_LEFT, BTN_DOWN, BTN_RIGHT, BTN_B, BTN_A
