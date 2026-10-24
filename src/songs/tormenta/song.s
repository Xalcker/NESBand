; Generado por `nesband import-song` - no editar a mano
; Fuente: tormenta.txt (canción 0, 120 s)
; SONG_SLOT_NUMBER lo define src/songs/list.s antes de incluir este archivo

.assert SONG_LEAD_IN = 128, error, "El chart se generó con otro SONG_LEAD_IN"
.assert CHART_ENTRY = 2, error, "El chart se generó con otro CHART_ENTRY"

; La ficha, el título y el juego van al inicio del slot (no en el banco fijo, que ya está casi lleno):
; solo se leen con la canción elegida, que es cuando su slot está en $A000. El slot de cada canción es
; su lugar en el menú (SONG_SLOT_NUMBER), así que select_song no necesita leer la ficha para encontrarlo.
.segment .sprintf("SONG%d", SONG_SLOT_NUMBER)
song_tormenta_data:
song_tormenta:
    .addr music_data_tormenta
    .word 4608            ; cuadro en que se detiene la música
    .byte 20              ; cuadros por tiempo (180 BPM)
    .word 128             ; cuadro del primer tiempo
    .addr song_tormenta_title, song_tormenta_game
    .byte %00001111        ; instrumentos con chart (bit 0 = guitarra)
    .byte SONG_SLOT_NUMBER
    ; charts: un renglón por instrumento, una columna por dificultad
    .addr chart_tormenta_guitarra_facil, chart_tormenta_guitarra_medio, chart_tormenta_guitarra_dificil, chart_tormenta_guitarra_experto  ; guitarra
    .addr chart_tormenta_teclado_facil, chart_tormenta_teclado_medio, chart_tormenta_teclado_dificil, chart_tormenta_teclado_experto  ; teclado
    .addr chart_tormenta_bajo_facil, chart_tormenta_bajo_medio, chart_tormenta_bajo_dificil, chart_tormenta_bajo_experto  ; bajo
    .addr chart_tormenta_bateria_facil, chart_tormenta_bateria_medio, chart_tormenta_bateria_dificil, chart_tormenta_bateria_experto  ; bateria

song_tormenta_title: .byte "TORMENTA DE NEON", 0
song_tormenta_game:  .byte "NESBAND", 0

; Música y charts, a continuación
.include "songs/tormenta/music.s"
.include "songs/tormenta/chart.s"
