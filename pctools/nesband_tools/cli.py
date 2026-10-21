"""nesband: línea de comandos de las herramientas de PC.

    uv run nesband import-song cancion.nsf --name wily --duration 75

Genera en src/songs/<nombre>/:
    music.s   datos para el motor de sonido de FamiStudio
    chart.s   un chart por dificultad
    song.s    metadatos (tempo, inicio, fin) que usa el juego
y deja esa canción como la seleccionada (src/songs/current.s).
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

from . import famistudio
from .chart import DIFFICULTIES, FRAMES_PER_ROW, build_chart, chart_to_asm, estimate_beat, frame_to_row

ROOT = Path(__file__).resolve().parents[2]
SONGS_DIR = ROOT / "src" / "songs"
WORK_DIR = ROOT / "build" / "songs"

LEAD_IN = 128  # cuadros de autopista antes de que arranque la música

# Instrumento del jugador -> canal del APU (y su índice para silenciarlo al fallar)
INSTRUMENTS = {
    "guitarra": ("Square1", 0),
    "teclado": ("Square2", 1),
    "bajo": ("Triangle", 2),
    "bateria": ("Noise", 3),
}

# Banderas que activa src/music.s. Si una canción pide otra, hay que agregarla allá.
SUPPORTED_FLAGS = {
    "FAMISTUDIO_USE_VOLUME_TRACK",
    "FAMISTUDIO_USE_VOLUME_SLIDES",
    "FAMISTUDIO_USE_PITCH_TRACK",
    "FAMISTUDIO_USE_SLIDE_NOTES",
    "FAMISTUDIO_USE_NOISE_SLIDE_NOTES",
    "FAMISTUDIO_USE_VIBRATO",
    "FAMISTUDIO_USE_ARPEGGIO",
    "FAMISTUDIO_USE_RELEASE_NOTES",
    "FAMISTUDIO_USE_DUTYCYCLE_EFFECT",
    "FAMISTUDIO_USE_DELTA_COUNTER",
    "FAMISTUDIO_USE_PHASE_RESET",
    "FAMISTUDIO_CFG_DPCM_SUPPORT",
}


def import_song(args: argparse.Namespace) -> None:
    source: Path = args.source.resolve()
    name: str = args.name
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
        sys.exit("--name debe ser minúsculas, números y _ (empezando con letra)")
    channel_type, channel_index = INSTRUMENTS[args.instrument]

    fs = famistudio.find_famistudio(ROOT)
    out_dir = SONGS_DIR / name
    work_dir = WORK_DIR / name
    for d in (out_dir, work_dir):
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)

    options = famistudio.import_options(source, args.song, args.duration)
    is_nsf = source.suffix.lower() in (".nsf", ".nsfe")

    # 1) Música para el motor
    music_path = out_dir / "music.s"
    famistudio.run(fs, [str(source), "famistudio-asm-export", str(music_path), "-famistudio-asm-format:ca65", *options])
    music_asm = music_path.read_text(encoding="utf-8")
    music_path.write_text(music_asm, encoding="utf-8", newline="\n")  # FamiStudio lo escribe con CRLF
    missing = famistudio.read_required_flags(music_asm) - SUPPORTED_FLAGS
    if missing:
        sys.exit(f"La canción necesita banderas que src/music.s no activa: {', '.join(sorted(missing))}")
    music_label = famistudio.read_music_label(music_asm)
    dmc_files = sorted(out_dir.glob("*.dmc"))

    # 2) Notas, desde el export de texto
    text_path = work_dir / "song.txt"
    famistudio.run(fs, [str(source), "famistudio-txt-export", str(text_path), *options])
    project = famistudio.parse_text(text_path.read_text(encoding="utf-8"))
    song = project.songs[0] if len(project.songs) == 1 else project.songs[args.song]
    notes = song.notes.get(channel_type, [])
    if not notes:
        sys.exit(f"El canal {channel_type} ({args.instrument}) no tiene notas en esta canción")

    # 3) Tempo: el de FamiStudio es confiable en sus proyectos, no en un NSF importado
    if args.beat_frames or is_nsf:
        all_onsets = [n.frame for ch in song.notes.values() for n in ch]
        grid = estimate_beat(all_onsets, args.beat_frames)
    else:
        grid = estimate_beat([0], song.frames_per_beat)
    beat_rows = max(1, round(grid.frames_per_beat / FRAMES_PER_ROW))
    first_beat_row = frame_to_row(LEAD_IN + grid.first_beat)
    if grid.frames_per_beat % FRAMES_PER_ROW:
        print(f"Aviso: el tiempo dura {grid.frames_per_beat} cuadros, no es múltiplo de {FRAMES_PER_ROW}: "
              "las líneas de beat se irán desfasando un poco.")

    # 4) Charts
    charts = []
    chart_asm = [f"; Generado por `nesband import-song` desde {source.name} - no editar a mano\n"]
    for difficulty in DIFFICULTIES:
        chart = build_chart(notes, difficulty, grid, LEAD_IN, beat_rows, first_beat_row)
        charts.append((difficulty, chart))
        chart_asm.append(chart_to_asm(f"chart_{name}_{difficulty.name}", chart))
    (out_dir / "chart.s").write_text("\n".join(chart_asm), encoding="utf-8", newline="\n")

    # 5) Metadatos
    end_frame = LEAD_IN + song.length_frames
    dpcm = "".join(f'.segment "DPCM"\n    .incbin "songs/{name}/{f.name}"\n' for f in dmc_files)
    chart_labels = ", ".join(f"chart_{name}_{d.name}" for d in DIFFICULTIES)
    (out_dir / "song.s").write_text(
        f"""; Generado por `nesband import-song` - no editar a mano
; Fuente: {source.name} (canción {args.song}), instrumento: {args.instrument}

.assert FRAMES_PER_ROW = {FRAMES_PER_ROW}, error, "El chart se generó con otro FRAMES_PER_ROW"

SONG_LEAD_IN        = {LEAD_IN}      ; cuadro en que arranca la música
SONG_END_FRAME      = {end_frame}    ; cuadro en que se detiene
SONG_BEAT_ROWS      = {beat_rows}    ; filas entre líneas de beat ({grid.frames_per_beat} cuadros = {3600 / grid.frames_per_beat:.0f} BPM)
SONG_FIRST_BEAT_ROW = {first_beat_row}
SONG_PLAYER_CHANNEL = {channel_index}      ; canal que se silencia al fallar ({channel_type})

.segment "RODATA"
song_music_data = {music_label}
song_charts:
    .addr {chart_labels}

.include "songs/{name}/music.s"
.include "songs/{name}/chart.s"
{dpcm}""",
        encoding="utf-8",
        newline="\n",
    )
    if not args.no_select:
        (SONGS_DIR / "current.s").write_text(
            f'; Canción que se ensambla en la ROM (la escribe `nesband import-song`)\n.include "songs/{name}/song.s"\n',
            encoding="utf-8",
            newline="\n",
        )

    print(f"Canción '{song.name}' -> src/songs/{name}/")
    print(f"  duración: {song.length_frames} cuadros ({song.length_frames / 60:.1f} s)")
    print(f"  tempo: {grid.frames_per_beat} cuadros por tiempo ({3600 / grid.frames_per_beat:.0f} BPM), "
          f"primer tiempo en el cuadro {grid.first_beat}")
    print(f"  {args.instrument} = {channel_type}: {len(notes)} notas en la canción")
    for difficulty, chart in charts:
        print(f"    {difficulty.name:8} {len(chart):4} notas")
    if dmc_files:
        print(f"  samples DPCM: {', '.join(f.name for f in dmc_files)}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="nesband", description="Herramientas de PC para NESBand")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("import-song", help="Importa una canción (NSF, FamiStudio o FamiTracker) y genera sus charts")
    p.add_argument("source", type=Path, help="archivo .nsf, .nsfe, .fms o .ftm")
    p.add_argument("--name", required=True, help="identificador de la canción (minúsculas, sin espacios)")
    p.add_argument("--song", type=int, default=0, help="índice de la canción dentro del archivo (desde 0)")
    p.add_argument("--duration", type=int, default=120, help="solo NSF: segundos a grabar")
    p.add_argument("--instrument", choices=INSTRUMENTS, default="guitarra", help="instrumento del jugador")
    p.add_argument("--beat-frames", type=int, help="cuadros por tiempo, si la estimación automática falla")
    p.add_argument("--no-select", action="store_true", help="no dejarla como la canción de la ROM")
    p.set_defaults(func=import_song)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
