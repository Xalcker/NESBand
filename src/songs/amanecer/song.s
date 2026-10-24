; Generado por `nesband import-song` - no editar a mano
; Fuente: amanecer.txt (canción 0, 120 s)
; SONG_SLOT_NUMBER lo define src/songs/list.s antes de incluir este archivo

.assert SONG_LEAD_IN = 128, error, "El chart se generó con otro SONG_LEAD_IN"
.assert CHART_ENTRY = 2, error, "El chart se generó con otro CHART_ENTRY"

; La ficha, el título y el juego van al inicio del slot (no en el banco fijo, que ya está casi lleno):
; solo se leen con la canción elegida, que es cuando su slot está en $A000. El slot de cada canción es
; su lugar en el menú (SONG_SLOT_NUMBER), así que select_song no necesita leer la ficha para encontrarlo.
.segment .sprintf("SONG%d", SONG_SLOT_NUMBER)
song_amanecer_data:
song_amanecer:
    .addr music_data_amanecer
    .word 5504            ; cuadro en que se detiene la música
    .byte 28              ; cuadros por tiempo (129 BPM)
    .word 128             ; cuadro del primer tiempo
    .addr song_amanecer_title, song_amanecer_game
    .byte %00000111        ; instrumentos con chart (bit 0 = guitarra)
    .byte SONG_SLOT_NUMBER
    ; charts: un renglón por instrumento, una columna por dificultad
    .addr chart_amanecer_guitarra_facil, chart_amanecer_guitarra_medio, chart_amanecer_guitarra_dificil, chart_amanecer_guitarra_experto  ; guitarra
    .addr chart_amanecer_teclado_facil, chart_amanecer_teclado_medio, chart_amanecer_teclado_dificil, chart_amanecer_teclado_experto  ; teclado
    .addr chart_amanecer_bajo_facil, chart_amanecer_bajo_medio, chart_amanecer_bajo_dificil, chart_amanecer_bajo_experto  ; bajo
    .addr 0, 0, 0, 0  ; bateria

song_amanecer_title: .byte "AMANECER DIGITAL", 0
song_amanecer_game:  .byte "NESBAND", 0

; Música y charts, a continuación
.include "songs/amanecer/music.s"
.include "songs/amanecer/chart.s"

; Samples DPCM al final del slot, en $DE80 (múltiplo de 64, como pide el chip de sonido)
song_amanecer_data_end:
.assert song_amanecer_data_end - song_amanecer_data <= $3E80, error, "La música y los charts se encimarían con los samples"
    .res $3E80 - (song_amanecer_data_end - song_amanecer_data), $FF
    .incbin "songs/amanecer/music.dmc"
song_amanecer_dpcm_ptr = ($DE80 & $3FFF) >> 6
