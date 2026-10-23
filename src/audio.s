; =============================================================================
; audio.s - Motor de sonido de FamiStudio y silenciado del instrumento
;
; El motor (src/famistudio/famistudio_ca65.s, licencia MIT) toca la música
; exportada desde FamiStudio. Se usa con tres rutinas:
;   famistudio_init        una vez, al arrancar
;   famistudio_music_play  al empezar la canción
;   famistudio_update      una vez por cuadro
;
; Las banderas de abajo activan funciones del motor. Cada canción exportada
; dice cuáles necesita; `nesband import-song` revisa que estén todas aquí
; (lista SUPPORTED_FLAGS en pctools/nesband_tools/cli.py).
; =============================================================================

FAMISTUDIO_CFG_EXTERNAL          = 1
FAMISTUDIO_CFG_NTSC_SUPPORT      = 1
FAMISTUDIO_CFG_DPCM_SUPPORT      = 1
FAMISTUDIO_CFG_SFX_SUPPORT       = 1   ; efectos de sonido (menú), encima de la música
FAMISTUDIO_CFG_SFX_STREAMS       = 1   ; uno a la vez basta
FAMISTUDIO_CFG_EQUALIZER         = 1   ; cuenta regresiva por canal al tocar una nota (la usan las pruebas)
FAMISTUDIO_USE_VOLUME_TRACK      = 1
FAMISTUDIO_USE_VOLUME_SLIDES     = 1
FAMISTUDIO_USE_PITCH_TRACK       = 1
FAMISTUDIO_USE_SLIDE_NOTES       = 1
FAMISTUDIO_USE_NOISE_SLIDE_NOTES = 1
FAMISTUDIO_USE_VIBRATO           = 1
FAMISTUDIO_USE_ARPEGGIO          = 1
FAMISTUDIO_USE_RELEASE_NOTES     = 1
FAMISTUDIO_USE_DUTYCYCLE_EFFECT  = 1
FAMISTUDIO_USE_DELTA_COUNTER     = 1
FAMISTUDIO_USE_PHASE_RESET       = 1
FAMISTUDIO_DPCM_OFF              = $C000   ; los samples de cada canción van en $C000 de su slot (ver nes.cfg)

.define FAMISTUDIO_CA65_ZP_SEGMENT   ZEROPAGE
.define FAMISTUDIO_CA65_RAM_SEGMENT  BSS
.define FAMISTUDIO_CA65_CODE_SEGMENT ENGINE   ; en el banco fijo de $E000

.include "famistudio/famistudio_ca65.s"

; Música del título y efectos de sonido: originales de NESBand. Se editan en
; FamiStudio (audio/titulo.txt, audio/efectos.txt) y se exportan con
; `uv run nesband build-audio`. Van en el banco fijo: son chiquitos.
.segment "RODATA"
.include "audio/title_music.s"
.include "audio/sfx.s"

.segment "CODE"

; -----------------------------------------------------------------------------
; music_init: prepara el motor con la música X/Y (y los efectos, que se
; pierden cada vez que se reinicia el motor)
; play_sfx: toca el efecto A (SFX_... de src/audio/sfx.s)
; -----------------------------------------------------------------------------
music_init:
    lda #1                      ; NTSC
    jsr famistudio_init
    ldx #<sounds
    ldy #>sounds
    jmp famistudio_sfx_init

play_sfx:
    ldx #FAMISTUDIO_SFX_CH0
    jmp famistudio_sfx_play

; -----------------------------------------------------------------------------
; update_music: arranca/detiene la canción según el reloj y avanza el motor.
; Se llama una vez por cuadro desde play_update.
; -----------------------------------------------------------------------------
update_music:
    lda song_frame
    cmp #<SONG_LEAD_IN
    bne @not_start
    lda song_frame+1
    cmp #>SONG_LEAD_IN
    bne @not_start
    lda #0                      ; la canción 0 del archivo exportado
    jsr famistudio_music_play
@not_start:
    lda song_frame
    cmp song_end
    bne @not_end
    lda song_frame+1
    cmp song_end+1
    bne @not_end
    jsr famistudio_music_stop
@not_end:
    jsr famistudio_update
    ; continúa en apply_mute

; -----------------------------------------------------------------------------
; apply_mute: silencia el instrumento de cada jugador que haya fallado (como
; en Rock Band)
;
; El motor reescribe el volumen de cada canal en cada cuadro dentro de
; famistudio_update. Si justo después escribimos volumen 0, ese canal queda
; callado este cuadro; en cuanto dejamos de hacerlo, vuelve a sonar.
;
; Lee directo de la copia guardada de cada jugador (player_save), sin
; cargarla: solo necesita dos bytes.
; -----------------------------------------------------------------------------
PS_MUTED   = player_muted - pstate      ; posición dentro del bloque de un jugador
PS_CHANNEL = player_channel - pstate
PS_STAR_ACTIVE = star_active - pstate   ; (lo usa update_fx, en play.s)
PS_LIFE    = life - pstate              ; (los usa update_meters, en play.s)
PS_NO_FAIL = no_fail - pstate
PS_FAILED  = failed - pstate

apply_mute:
    ldx #0
@player:
    ldy player_offset,x
    lda player_save + PS_MUTED,y
    beq @next
    stx tmp
    lda num_players
    cmp #2
    bne @mute
    ; En VS los dos pueden tocar el mismo instrumento (el mismo canal): solo se calla
    ; si los dos están fallando; mientras el otro acierte, sigue sonando
    txa
    eor #1
    tax                         ; X = el otro jugador
    ldy player_offset,x
    lda player_save + PS_MUTED,y
    bne @mute                   ; también falló: se calla
    lda player_save + PS_CHANNEL,y
    ldx tmp
    ldy player_offset,x
    cmp player_save + PS_CHANNEL,y
    beq @back                   ; mismo canal y el otro acierta: suena
@mute:
    ldx tmp
    ldy player_offset,x
    lda player_save + PS_CHANNEL,y
    cmp #2
    bne @pulse_or_noise
    lda #$80                    ; triángulo: contador lineal en 0 = silencio
    sta APU_TRI_CTRL
    ldx tmp
    jmp @next
@pulse_or_noise:
    asl a                       ; cada canal ocupa 4 registros: $4000, $4004, $400C
    asl a
    tay
    lda #%00110000              ; pulso/ruido: volumen constante 0
    sta $4000,y
    jmp @next
@back:
    ldx tmp
@next:
    inx
    cpx num_players
    bne @player
    rts
