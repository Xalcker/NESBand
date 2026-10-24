; Generado por `nesband import-song` - no editar a mano
; Fuente: brisa.txt (canción 0, 120 s)
; SONG_SLOT_NUMBER lo define src/songs/list.s antes de incluir este archivo

.assert SONG_LEAD_IN = 128, error, "El chart se generó con otro SONG_LEAD_IN"
.assert CHART_ENTRY = 2, error, "El chart se generó con otro CHART_ENTRY"

; La ficha, el título y el juego van al inicio del slot (no en el banco fijo, que ya está casi lleno):
; solo se leen con la canción elegida, que es cuando su slot está en $A000. El slot de cada canción es
; su lugar en el menú (SONG_SLOT_NUMBER), así que select_song no necesita leer la ficha para encontrarlo.
.segment .sprintf("SONG%d", SONG_SLOT_NUMBER)
song_brisa_data:
song_brisa:
    .addr music_data_brisa
    .word 5952            ; cuadro en que se detiene la música
    .byte 28              ; cuadros por tiempo (129 BPM)
    .word 128             ; cuadro del primer tiempo
    .addr song_brisa_title, song_brisa_game
    .byte %00001111        ; instrumentos con chart (bit 0 = guitarra)
    .byte SONG_SLOT_NUMBER
    ; charts: un renglón por instrumento, una columna por dificultad
    .addr chart_brisa_guitarra_facil, chart_brisa_guitarra_medio, chart_brisa_guitarra_dificil, chart_brisa_guitarra_experto  ; guitarra
    .addr chart_brisa_teclado_facil, chart_brisa_teclado_medio, chart_brisa_teclado_dificil, chart_brisa_teclado_experto  ; teclado
    .addr chart_brisa_bajo_facil, chart_brisa_bajo_medio, chart_brisa_bajo_dificil, chart_brisa_bajo_experto  ; bajo
    .addr chart_brisa_bateria_facil, chart_brisa_bateria_medio, chart_brisa_bateria_dificil, chart_brisa_bateria_experto  ; bateria

song_brisa_title: .byte "BRISA DE VERANO", 0
song_brisa_game:  .byte "NESBAND", 0

; Música y charts, a continuación
.include "songs/brisa/music.s"
.include "songs/brisa/chart.s"
