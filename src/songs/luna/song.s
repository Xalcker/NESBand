; Generado por `nesband import-song` - no editar a mano
; Fuente: luna.txt (canción 0, 120 s)
; SONG_SLOT_NUMBER lo define src/songs/list.s antes de incluir este archivo

.assert SONG_LEAD_IN = 128, error, "El chart se generó con otro SONG_LEAD_IN"
.assert CHART_ENTRY = 2, error, "El chart se generó con otro CHART_ENTRY"

; La ficha, el título y el juego van al inicio del slot (no en el banco fijo, que ya está casi lleno):
; solo se leen con la canción elegida, que es cuando su slot está en $A000. El slot de cada canción es
; su lugar en el menú (SONG_SLOT_NUMBER), así que select_song no necesita leer la ficha para encontrarlo.
.segment .sprintf("SONG%d", SONG_SLOT_NUMBER)
song_luna_data:
song_luna:
    .addr music_data_luna
    .word 5760            ; cuadro en que se detiene la música
    .byte 32              ; cuadros por tiempo (112 BPM)
    .word 128             ; cuadro del primer tiempo
    .addr song_luna_title, song_luna_game
    .byte %00000111        ; instrumentos con chart (bit 0 = guitarra)
    .byte SONG_SLOT_NUMBER
    ; charts: un renglón por instrumento, una columna por dificultad
    .addr chart_luna_guitarra_facil, chart_luna_guitarra_medio, chart_luna_guitarra_dificil, chart_luna_guitarra_experto  ; guitarra
    .addr chart_luna_teclado_facil, chart_luna_teclado_medio, chart_luna_teclado_dificil, chart_luna_teclado_experto  ; teclado
    .addr chart_luna_bajo_facil, chart_luna_bajo_medio, chart_luna_bajo_dificil, chart_luna_bajo_experto  ; bajo
    .addr 0, 0, 0, 0  ; bateria

song_luna_title: .byte "LUZ DE LUNA", 0
song_luna_game:  .byte "NESBAND", 0

; Música y charts, a continuación
.include "songs/luna/music.s"
.include "songs/luna/chart.s"
