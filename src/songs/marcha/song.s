; Generado por `nesband import-song` - no editar a mano
; Fuente: marcha.txt (canción 0, 120 s)
; SONG_SLOT_NUMBER lo define src/songs/list.s antes de incluir este archivo

.assert SONG_LEAD_IN = 128, error, "El chart se generó con otro SONG_LEAD_IN"
.assert CHART_ENTRY = 2, error, "El chart se generó con otro CHART_ENTRY"

; La ficha, el título y el juego van al inicio del slot (no en el banco fijo, que ya está casi lleno):
; solo se leen con la canción elegida, que es cuando su slot está en $A000. El slot de cada canción es
; su lugar en el menú (SONG_SLOT_NUMBER), así que select_song no necesita leer la ficha para encontrarlo.
.segment .sprintf("SONG%d", SONG_SLOT_NUMBER)
song_marcha_data:
song_marcha:
    .addr music_data_marcha
    .word 5504            ; cuadro en que se detiene la música
    .byte 28              ; cuadros por tiempo (129 BPM)
    .word 128             ; cuadro del primer tiempo
    .addr song_marcha_title, song_marcha_game
    .byte %00000111        ; instrumentos con chart (bit 0 = guitarra)
    .byte SONG_SLOT_NUMBER
    ; charts: un renglón por instrumento, una columna por dificultad
    .addr chart_marcha_guitarra_facil, chart_marcha_guitarra_medio, chart_marcha_guitarra_dificil, chart_marcha_guitarra_experto  ; guitarra
    .addr chart_marcha_teclado_facil, chart_marcha_teclado_medio, chart_marcha_teclado_dificil, chart_marcha_teclado_experto  ; teclado
    .addr chart_marcha_bajo_facil, chart_marcha_bajo_medio, chart_marcha_bajo_dificil, chart_marcha_bajo_experto  ; bajo
    .addr 0, 0, 0, 0  ; bateria

song_marcha_title: .byte "MARCHA DEL CARTUCHO", 0
song_marcha_game:  .byte "NESBAND", 0

; Música y charts, a continuación
.include "songs/marcha/music.s"
.include "songs/marcha/chart.s"
