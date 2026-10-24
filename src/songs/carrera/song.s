; Generado por `nesband import-song` - no editar a mano
; Fuente: carrera.txt (canción 0, 120 s)
; SONG_SLOT_NUMBER lo define src/songs/list.s antes de incluir este archivo

.assert SONG_LEAD_IN = 128, error, "El chart se generó con otro SONG_LEAD_IN"
.assert CHART_ENTRY = 2, error, "El chart se generó con otro CHART_ENTRY"

; La ficha, el título y el juego van al inicio del slot (no en el banco fijo, que ya está casi lleno):
; solo se leen con la canción elegida, que es cuando su slot está en $A000. El slot de cada canción es
; su lugar en el menú (SONG_SLOT_NUMBER), así que select_song no necesita leer la ficha para encontrarlo.
.segment .sprintf("SONG%d", SONG_SLOT_NUMBER)
song_carrera_data:
song_carrera:
    .addr music_data_carrera
    .word 4608            ; cuadro en que se detiene la música
    .byte 20              ; cuadros por tiempo (180 BPM)
    .word 128             ; cuadro del primer tiempo
    .addr song_carrera_title, song_carrera_game
    .byte %00001111        ; instrumentos con chart (bit 0 = guitarra)
    .byte SONG_SLOT_NUMBER
    ; charts: un renglón por instrumento, una columna por dificultad
    .addr chart_carrera_guitarra_facil, chart_carrera_guitarra_medio, chart_carrera_guitarra_dificil, chart_carrera_guitarra_experto  ; guitarra
    .addr chart_carrera_teclado_facil, chart_carrera_teclado_medio, chart_carrera_teclado_dificil, chart_carrera_teclado_experto  ; teclado
    .addr chart_carrera_bajo_facil, chart_carrera_bajo_medio, chart_carrera_bajo_dificil, chart_carrera_bajo_experto  ; bajo
    .addr chart_carrera_bateria_facil, chart_carrera_bateria_medio, chart_carrera_bateria_dificil, chart_carrera_bateria_experto  ; bateria

song_carrera_title: .byte "CARRERA DE FUEGO", 0
song_carrera_game:  .byte "NESBAND", 0

; Música y charts, a continuación
.include "songs/carrera/music.s"
.include "songs/carrera/chart.s"

; Samples DPCM al final del slot, en $DD40 (múltiplo de 64, como pide el chip de sonido)
song_carrera_data_end:
.assert song_carrera_data_end - song_carrera_data <= $3D40, error, "La música y los charts se encimarían con los samples"
    .res $3D40 - (song_carrera_data_end - song_carrera_data), $FF
    .incbin "songs/carrera/music.dmc"
song_carrera_dpcm_ptr = ($DD40 & $3FFF) >> 6
