"""nesband: línea de comandos de las herramientas de PC.

    uv run nesband import-song cancion.nsf --name wily --title "Dr. Wily's Castle" --game "Mega Man 2" --duration 75
    uv run nesband list-songs

import-song genera en src/songs/<nombre>/:
    music.s   datos para el motor de sonido de FamiStudio
    chart.s   un chart por instrumento y dificultad
    song.s    la ficha de la canción que lee el juego (título, tempo, fin, charts)
y regenera src/songs/list.s, la lista de canciones que entran en la ROM.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import unicodedata
from pathlib import Path

from . import famistudio
from .chart import DIFFICULTIES, FRAMES_PER_ROW, build_chart, chart_to_asm, estimate_beat, frame_to_row

ROOT = Path(__file__).resolve().parents[2]
SONGS_DIR = ROOT / "src" / "songs"
WORK_DIR = ROOT / "build" / "songs"

LEAD_IN = 128  # cuadros de autopista antes de que arranque la música (SONG_LEAD_IN en main.s)
TEXT_MAX = 26  # caracteres que caben en el menú

# Instrumentos en el orden que usa el juego, con su canal del APU.
# La batería necesita su propio criterio de carriles (por tipo de golpe); mientras
# tanto no se genera y en el menú no aparece.
INSTRUMENTS = [
    ("guitarra", "Square1"),
    ("teclado", "Square2"),
    ("bajo", "Triangle"),
    ("bateria", None),
]

# Banderas que activa src/audio.s. Si una canción pide otra, hay que agregarla allá.
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

# Caracteres que tiene la fuente del juego (src/chr.s): el tile de cada letra es su código ASCII
FONT_CHARS = set(" !%'()*,-./0123456789:<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ")


def to_nes_text(text: str) -> str:
    """Mayúsculas, sin acentos y solo con caracteres de la fuente del NES."""
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii").upper()
    plain = "".join(c if c in FONT_CHARS else " " for c in plain)
    return " ".join(plain.split())[:TEXT_MAX]


def write_lf(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def import_song(args: argparse.Namespace) -> None:
    source: Path = args.source.resolve()
    name: str = args.name
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
        sys.exit("--name debe ser minúsculas, números y _ (empezando con letra)")

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
    write_lf(music_path, music_asm)  # FamiStudio lo escribe con CRLF
    missing = famistudio.read_required_flags(music_asm) - SUPPORTED_FLAGS
    if missing:
        sys.exit(f"La canción necesita banderas que src/audio.s no activa: {', '.join(sorted(missing))}")
    music_label = famistudio.read_music_label(music_asm)
    dmc_files = sorted(out_dir.glob("*.dmc"))

    # 2) Notas, desde el export de texto
    text_path = work_dir / "song.txt"
    famistudio.run(fs, [str(source), "famistudio-txt-export", str(text_path), *options])
    project = famistudio.parse_text(text_path.read_text(encoding="utf-8"))
    song = project.songs[0] if len(project.songs) == 1 else project.songs[args.song]

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

    # 4) Charts por instrumento y dificultad
    chart_asm = [f"; Generado por `nesband import-song` desde {source.name} - no editar a mano\n"]
    chart_labels: list[str] = []
    instrument_mask = 0
    summary = []
    for index, (instrument, channel) in enumerate(INSTRUMENTS):
        notes = song.notes.get(channel, []) if channel else []
        if not notes:
            chart_labels += ["0"] * len(DIFFICULTIES)
            summary.append(f"  {instrument:9} -")
            continue
        instrument_mask |= 1 << index
        counts = []
        for difficulty in DIFFICULTIES:
            label = f"chart_{name}_{instrument}_{difficulty.name}"
            chart = build_chart(notes, difficulty, grid, LEAD_IN, beat_rows, first_beat_row)
            chart_asm.append(chart_to_asm(label, chart))
            chart_labels.append(label)
            counts.append(f"{difficulty.name} {len(chart)}")
        summary.append(f"  {instrument:9} ({channel}): " + ", ".join(counts))
    if not instrument_mask:
        sys.exit("La canción no tiene notas en ningún canal melódico")
    write_lf(out_dir / "chart.s", "\n".join(chart_asm))

    # 5) Ficha de la canción (el orden de los campos lo define SONG_... en src/main.s)
    title = to_nes_text(args.title or song.name)
    game = to_nes_text(args.game or project.attrs.get("Name", ""))
    end_frame = LEAD_IN + song.length_frames
    dpcm = "".join(f'.segment "DPCM"\n    .incbin "songs/{name}/{f.name}"\n' for f in dmc_files)
    charts_lines = "\n".join(
        f"    .addr {', '.join(chart_labels[i * len(DIFFICULTIES):(i + 1) * len(DIFFICULTIES)])}  ; {inst}"
        for i, (inst, _) in enumerate(INSTRUMENTS)
    )
    write_lf(out_dir / "song.s", f"""; Generado por `nesband import-song` - no editar a mano
; Fuente: {source.name} (canción {args.song})

.assert SONG_LEAD_IN = {LEAD_IN}, error, "El chart se generó con otro SONG_LEAD_IN"
.assert FRAMES_PER_ROW = {FRAMES_PER_ROW}, error, "El chart se generó con otro FRAMES_PER_ROW"

.segment "RODATA"
song_{name}:
    .addr {music_label}
    .word {end_frame}            ; cuadro en que se detiene la música
    .byte {beat_rows}               ; filas entre líneas de beat ({grid.frames_per_beat} cuadros = {3600 / grid.frames_per_beat:.0f} BPM)
    .byte {first_beat_row}              ; primera fila con línea de beat
    .addr song_{name}_title, song_{name}_game
    .byte %{instrument_mask:08b}        ; instrumentos con chart (bit 0 = guitarra)
    ; charts: un renglón por instrumento, una columna por dificultad
{charts_lines}

song_{name}_title: .byte "{title}", 0
song_{name}_game:  .byte "{game}", 0

.include "songs/{name}/music.s"
.include "songs/{name}/chart.s"
{dpcm}""")

    write_song_list()

    print(f"Canción '{title}' ({game}) -> src/songs/{name}/")
    print(f"  duración: {song.length_frames} cuadros ({song.length_frames / 60:.1f} s)")
    print(f"  tempo: {grid.frames_per_beat} cuadros por tiempo ({3600 / grid.frames_per_beat:.0f} BPM), "
          f"primer tiempo en el cuadro {grid.first_beat}")
    print("\n".join(summary))
    if dmc_files:
        print(f"  samples DPCM: {', '.join(f.name for f in dmc_files)}")


def write_song_list() -> list[str]:
    """Regenera src/songs/list.s con todas las canciones de src/songs/*/song.s."""
    names = sorted(p.parent.name for p in SONGS_DIR.glob("*/song.s"))
    if not names:
        sys.exit("No hay canciones en src/songs/")
    with_dpcm = [n for n in names if any((SONGS_DIR / n).glob("*.dmc"))]
    if len(with_dpcm) > 1:
        sys.exit(f"Por ahora solo una canción puede usar samples DPCM: {', '.join(with_dpcm)}")
    includes = "\n".join(f'.include "songs/{n}/song.s"' for n in names)
    table = "\n".join(f"    .addr song_{n}" for n in names)
    write_lf(SONGS_DIR / "list.s", f"""; Generado por `nesband` - lista de canciones de la ROM, en orden alfabético
NUM_SONGS = {len(names)}

{includes}

.segment "RODATA"
song_table:
{table}
""")
    old = SONGS_DIR / "current.s"
    if old.exists():
        old.unlink()
    return names


def list_songs(args: argparse.Namespace) -> None:
    names = write_song_list()
    print(f"{len(names)} canciones en src/songs/list.s: {', '.join(names)}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="nesband", description="Herramientas de PC para NESBand")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("import-song", help="Importa una canción (NSF, FamiStudio o FamiTracker) y genera sus charts")
    p.add_argument("source", type=Path, help="archivo .nsf, .nsfe, .fms o .ftm")
    p.add_argument("--name", required=True, help="identificador de la canción (minúsculas, sin espacios)")
    p.add_argument("--title", help="nombre que se muestra en el menú")
    p.add_argument("--game", help="juego del que viene (default: el nombre del NSF/proyecto)")
    p.add_argument("--song", type=int, default=0, help="índice de la canción dentro del archivo (desde 0)")
    p.add_argument("--duration", type=int, default=120, help="solo NSF: segundos a grabar")
    p.add_argument("--beat-frames", type=int, help="cuadros por tiempo, si la estimación automática falla")
    p.set_defaults(func=import_song)

    p = sub.add_parser("list-songs", help="Regenera src/songs/list.s (por ejemplo, después de borrar una canción)")
    p.set_defaults(func=list_songs)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
