; Lo que src/audio.s espera del resto del juego, para armar el reproductor del editor de charts
; (ver player.py). Solo hace falta que ensamble: el reproductor nunca llama a update_music ni a
; apply_mute, solo a las rutinas del motor de FamiStudio que incluye audio.s.

SONG_LEAD_IN = 128
CHART_ENTRY  = 2
APU_TRI_CTRL = $4008

.segment "ZEROPAGE"
tmp:         .res 1
song_frame:  .res 2
song_end:    .res 2
num_players: .res 1

.segment "BSS"
pstate:
player_muted:   .res 1
player_channel: .res 1
star_active:    .res 1
life:           .res 1
no_fail:        .res 1
failed:         .res 1
player_save:    .res 32
player_offset:  .res 2
