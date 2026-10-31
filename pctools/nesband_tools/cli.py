"""nesband: línea de comandos de las herramientas de PC.

    uv run nesband import-song "songs_src/Blaster Master (...).nsf" --track 2 --name blaster_area1
    uv run nesband import-song cancion.nsf --name wily --title "Dr. Wily's Castle" --game "Mega Man 2" --duration 75
    uv run nesband list-songs
    uv run nesband reimport              (todas, con las mismas opciones, tras mejorar el generador)
    uv run nesband build-audio           (música del título y efectos, de audio/*.txt)

import-song genera en src/songs/<nombre>/:
    music.s   datos para el motor de sonido de FamiStudio
    chart.s   un chart por instrumento y dificultad
    song.s    la ficha de la canción que lee el juego (título, tempo, fin, charts)
y regenera src/songs/list.s, la lista de canciones que entran en la ROM.

Cada canción ocupa un "slot" de 16 KB del cartucho MMC3 (ver nes.cfg).
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from . import famistudio
from .chart import (
    DIFFICULTIES,
    BeatGrid,
    build_chart,
    check_playable,
    chart_size,
    chart_to_asm,
    estimate_beat,
    merge_attacks,
)
from .drums import DRUMS_FILE, build_drum_chart, drum_hits, load_drums
from .chartedit import EDITS_FILE, apply_edits, chart_file_text, load_edits, validate_chart
from .m3u import find_playlist

ROOT = Path(__file__).resolve().parents[2]
SONGS_DIR = ROOT / "src" / "songs"
WORK_DIR = ROOT / "build" / "songs"

LEAD_IN = 128  # cuadros de autopista antes de que arranque la música (SONG_LEAD_IN en main.s)
TEXT_MAX = 26  # caracteres que caben en el menú
MAX_SONGS = 31  # slots en nes.cfg
FICHA_RESERVE = 128  # bytes del inicio del slot para la ficha de la canción (45) y su título y juego (hasta ~55)
SLOT_START = 0xA000  # donde se ve el slot de la canción elegida
SLOT_SIZE = 0x4000  # 16 KB por canción
BANK_SIZE = 0x2000  # la segunda mitad del slot ($C000-$DFFF) es donde pueden ir los samples DPCM

# Instrumentos en el orden que usa el juego, con su canal del APU.
# La batería necesita su propio criterio de carriles (por tipo de golpe); mientras
# tanto no se genera y en el menú no aparece.
INSTRUMENTS = [
    ("guitarra", "Square1"),
    ("teclado", "Square2"),
    ("bajo", "Triangle"),
    ("bateria", None),
]
# Papel de cada instrumento en el generador (ver chart.py) y el canal que le da la armonía a sus acordes
ROLE_OF = {
    "guitarra": ("lead", "Square2"),
    "teclado": ("keys", "Square1"),
    "bajo": ("bass", None),
}

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

# Chips de sonido extra que traían algunos cartuchos
EXPANSIONS = {
    "VRC6": "Konami VRC6 (Castlevania 3 japonés, Madara...)",
    "VRC7": "Konami VRC7 (Lagrange Point)",
    "MMC5": "Nintendo MMC5",
    "FDS": "Famicom Disk System",
    "N163": "Namco 163",
    "S5B": "Sunsoft 5B (Gimmick!)",
    "EPSM": "EPSM",
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
    is_nsf = source.suffix.lower() in (".nsf", ".nsfe")
    is_vgm = source.suffix.lower() in (".vgm", ".vgz")

    # Pista, título, juego y duración: de las opciones o del .m3u junto al NSF
    song_index, title, game, duration = args.song, args.title, args.game, args.duration
    vgm_data = None
    if is_vgm:  # VGM del NES: título y juego de su etiqueta GD3; dura una vuelta (con la introducción)
        from bandcore.vgm import read_vgm

        vgm_data = read_vgm(source)
        if "nes_apu" not in vgm_data.clocks:
            sys.exit(f"{source.name} no es música del NES: solo se importan VGM del APU del NES")
        title, game = title or vgm_data.title or None, game or vgm_data.game or None
        duration = duration or math.ceil(vgm_data.total_samples / 44100)
    if args.track is not None:
        playlist = find_playlist(source) if is_nsf else None
        song_index = args.track - 1  # el .m3u cuenta desde 1; FamiStudio desde 0
        if playlist:
            track = playlist.tracks.get(args.track)
            if track is None:
                sys.exit(f"La pista {args.track} no está en el .m3u de {source.name}")
            title = title or track.title
            game = game or playlist.game
            duration = duration or track.seconds
            print(f"Pista {args.track} del .m3u: '{track.title}' ({track.seconds} s) de {playlist.game}")
    duration = duration or 120

    fs = famistudio.find_famistudio(ROOT)
    out_dir = SONGS_DIR / name
    work_dir = WORK_DIR / name

    # El trabajo manual (edits.json con las ediciones de los charts y drums.json con la asignación de la
    # batería) sobrevive a la importación: se lee antes de que convert borre la carpeta, las ediciones se
    # aplican a los charts automáticos y los archivos se vuelven a escribir
    kept = {n: (out_dir / n).read_text(encoding="utf-8") for n in (EDITS_FILE, DRUMS_FILE) if (out_dir / n).exists()}
    edits = load_edits(out_dir)
    drums = load_drums(out_dir)

    def restore_manual_work() -> None:
        for file_name, text in kept.items():
            write_lf(out_dir / file_name, text)

    # Convertir; si no cabe en el slot y es un NSF o un VGM, grabar menos segundos y reintentar
    for _ in range(6):
        project_source = vgm_project(vgm_data, name, duration, title) if is_vgm else source
        result = convert(fs, project_source, name, song_index, duration, args.beat_frames, is_nsf, out_dir, work_dir,
                         edits, drums)
        restore_manual_work()
        if result.fits:
            break
        shutil.rmtree(out_dir)
        if not (is_nsf or is_vgm):
            out_dir.mkdir(parents=True)
            restore_manual_work()
            if not kept:
                out_dir.rmdir()
            sys.exit(f"La canción no cabe en su slot de 16 KB ({result.total} bytes): hay que acortarla en FamiStudio.")
        new_duration = min(duration - 1, int(duration * SLOT_SIZE * 0.96 / result.total))
        print(f"No cabe con {duration} s ({result.total} de {SLOT_SIZE} bytes): pruebo con {new_duration} s")
        duration = new_duration
    else:
        sys.exit("No logré que la canción cupiera en su slot de 16 KB.")

    music_label, music_size, dmc_files, dmc_size = result.music_label, result.music_size, result.dmc_files, result.dmc_size
    project, song, grid = result.project, result.song, result.grid
    charts, chart_labels, instrument_mask = result.charts, result.chart_labels, result.instrument_mask
    summary = result.summary

    write_lf(out_dir / "chart.s", chart_file_text(source.name, [asm for _, asm, _ in charts]))

    # Samples DPCM: al final del slot. Los datos de la música dicen dónde están
    # con FAMISTUDIO_DPCM_PTR, que es el mismo para todas las canciones; lo
    # cambiamos por uno propio de esta canción.
    dpcm = ""
    if dmc_files:
        start = dpcm_start(dmc_size)
        dpcm_ptr = f"song_{name}_dpcm_ptr"
        music_path = out_dir / "music.s"
        music_asm = music_path.read_text(encoding="utf-8")
        music_asm = music_asm.replace(".global FAMISTUDIO_DPCM_PTR\n", "").replace("FAMISTUDIO_DPCM_PTR", dpcm_ptr)
        write_lf(music_path, music_asm)
        incbins = "".join(f'    .incbin "songs/{name}/{f.name}"\n' for f in dmc_files)
        dpcm = f"""
; Samples DPCM al final del slot, en ${start:04X} (múltiplo de 64, como pide el chip de sonido)
song_{name}_data_end:
.assert song_{name}_data_end - song_{name}_data <= ${start - SLOT_START:04X}, error, "La música y los charts se encimarían con los samples"
    .res ${start - SLOT_START:04X} - (song_{name}_data_end - song_{name}_data), $FF
{incbins}{dpcm_ptr} = (${start:04X} & $3FFF) >> 6
"""

    # Ficha de la canción (el orden de los campos lo define SONG_... en src/main.s)
    title = to_nes_text(title or song.name)
    game = to_nes_text(game or project.attrs.get("Name", ""))
    end_frame = LEAD_IN + song.length_frames
    charts_lines = "\n".join(
        f"    .addr {', '.join(chart_labels[i * len(DIFFICULTIES):(i + 1) * len(DIFFICULTIES)])}  ; {inst}"
        for i, (inst, _) in enumerate(INSTRUMENTS)
    )
    write_lf(out_dir / "song.s", f"""; Generado por `nesband import-song` - no editar a mano
; Fuente: {source.name} (canción {song_index}, {duration} s)
; SONG_SLOT_NUMBER lo define src/songs/list.s antes de incluir este archivo

.assert SONG_LEAD_IN = {LEAD_IN}, error, "El chart se generó con otro SONG_LEAD_IN"
.assert CHART_ENTRY = 2, error, "El chart se generó con otro CHART_ENTRY"

; La ficha, el título y el juego van al inicio del slot (no en el banco fijo, que ya está casi lleno):
; solo se leen con la canción elegida, que es cuando su slot está en $A000. El slot de cada canción es
; su lugar en el menú (SONG_SLOT_NUMBER), así que select_song no necesita leer la ficha para encontrarlo.
.segment .sprintf("SONG%d", SONG_SLOT_NUMBER)
song_{name}_data:
song_{name}:
    .addr {music_label}
    .word {end_frame}            ; cuadro en que se detiene la música
    .byte {grid.frames_per_beat}              ; cuadros por tiempo ({3600 / grid.frames_per_beat:.0f} BPM)
    .word {LEAD_IN + grid.first_beat}             ; cuadro del primer tiempo
    .addr song_{name}_title, song_{name}_game
    .byte %{instrument_mask:08b}        ; instrumentos con chart (bit 0 = guitarra)
    .byte SONG_SLOT_NUMBER
    ; charts: un renglón por instrumento, una columna por dificultad
{charts_lines}

song_{name}_title: .byte "{title}", 0
song_{name}_game:  .byte "{game}", 0

; Música y charts, a continuación
.include "songs/{name}/music.s"
.include "songs/{name}/chart.s"
{dpcm}""")

    # Las opciones con que se importó, para `nesband reimport`
    options_used = {
        "source": source.relative_to(ROOT).as_posix() if source.is_relative_to(ROOT) else str(source),
        "track": args.track, "song": args.song, "title": args.title, "game": args.game,
        "duration": args.duration, "beat_frames": args.beat_frames,
    }
    write_lf(out_dir / "import.json", json.dumps(options_used, indent=2, ensure_ascii=False) + "\n")

    write_song_list()

    total = result.total
    print(f"Canción '{title}' ({game}) -> src/songs/{name}/")
    print(f"  duración: {song.length_frames} cuadros ({song.length_frames / 60:.1f} s)")
    print(f"  tempo: {grid.frames_per_beat} cuadros por tiempo ({3600 / grid.frames_per_beat:.0f} BPM), "
          f"primer tiempo en el cuadro {grid.first_beat}")
    print("\n".join(summary))
    print(f"  tamaño: {total} de {SLOT_SIZE} bytes (música {music_size}, charts {total - music_size - dmc_size}"
          + (f", samples {dmc_size}" if dmc_files else "") + ")")


@dataclass
class Converted:
    fits: bool
    total: int
    music_label: str = ""
    music_size: int = 0
    dmc_files: list[Path] = field(default_factory=list)
    dmc_size: int = 0
    project: famistudio.Project | None = None
    song: famistudio.Song | None = None
    grid: BeatGrid | None = None
    charts: list[tuple[str, str, int]] = field(default_factory=list)  # (etiqueta, ensamblador, bytes)
    chart_labels: list[str] = field(default_factory=list)
    instrument_mask: int = 0
    summary: list[str] = field(default_factory=list)


def vgm_project(data, name: str, duration: int, title: str | None) -> Path:
    """Un VGM del NES como proyecto de texto de FamiStudio (el que importa convert): sus escrituras pasan por el APU
    emulado de bandcore y cada nota conserva su duty y su envolvente de volumen. El DPCM y el canal del Famicom Disk
    System se pierden (con aviso)."""
    from bandcore import famistudio as projects
    from bandcore import nesapu

    total = round(duration * 44100)
    if data.loop_write is None:
        total = min(total, data.total_samples)
    rec, fds = nesapu.record_vgm(data, total)
    path = WORK_DIR / f"{name}_vgm" / "fuente.txt"
    info = projects.write_recording_project(rec, path, title or name, "NESBand")
    print(f"  VGM: {duration} s, {info['instruments']} instrumentos (envolventes de hasta {info['envelope_frames']} cuadros)")
    if info["dpcm_lost"]:
        print(f"  AVISO: {info['dpcm_lost']} golpes de DPCM no se pasan (sus samples no van en el proyecto de texto)")
    if fds:
        print(f"  AVISO: el VGM usa el canal del Famicom Disk System ({fds} escrituras): se pierde")
    return path


def convert(fs: Path, source: Path, name: str, song_index: int, duration: int, beat_frames: int | None,
            is_nsf: bool, out_dir: Path, work_dir: Path, edits: dict | None = None,
            drums: dict | None = None) -> Converted:
    """Pasa la canción por FamiStudio, genera los charts y ve si todo cabe en un slot."""
    for d in (out_dir, work_dir):
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)

    options = famistudio.import_options(source, song_index, duration)

    # 1) Música para el motor
    music_path = out_dir / "music.s"
    output = famistudio.run(
        fs, [str(source), "famistudio-asm-export", str(music_path), "-famistudio-asm-format:ca65", *options]
    )
    music_size = famistudio.read_export_size(output)
    music_asm = music_path.read_text(encoding="utf-8")
    # FamiStudio nombra la música con el nombre del juego: dos canciones del mismo
    # NSF chocarían. Le ponemos el de la canción.
    music_asm = music_asm.replace(famistudio.read_music_label(music_asm), f"music_data_{name}")
    write_lf(music_path, music_asm)  # (y en LF: FamiStudio lo escribe con CRLF)
    missing = famistudio.read_required_flags(music_asm) - SUPPORTED_FLAGS
    expansions = [desc for key, desc in EXPANSIONS.items() if f"FAMISTUDIO_EXP_{key}" in missing]
    if expansions:
        shutil.rmtree(out_dir)
        sys.exit(
            f"La canción usa el chip de sonido extra {expansions[0]}. El motor solo usa el sonido del NES "
            "(2A03). Busca la versión americana/europea del juego, que normalmente no lo usa."
        )
    if missing:
        sys.exit(f"La canción necesita banderas que src/audio.s no activa: {', '.join(sorted(missing))}")
    music_label = famistudio.read_music_label(music_asm)
    dmc_files = sorted(out_dir.glob("*.dmc"))
    dmc_size = sum(f.stat().st_size for f in dmc_files)

    # 2) Notas, desde el export de texto
    text_path = work_dir / "song.txt"
    famistudio.run(fs, [str(source), "famistudio-txt-export", str(text_path), *options])
    project = famistudio.parse_text(text_path.read_text(encoding="utf-8"))
    song = project.songs[0] if len(project.songs) == 1 else project.songs[song_index]

    # 3) Tempo
    grid = song_grid(song, beat_frames, is_nsf)

    # 4) Charts por instrumento y dificultad
    charts: list[tuple[str, str, int]] = []  # (etiqueta, ensamblador, bytes)
    chart_labels: list[str] = []
    instrument_mask = 0
    summary = []
    # La batería sale de la asignación de papeles de drums.json (ver drums.py): sin ella, o si ningún grupo
    # tiene papel, la canción no tiene chart de batería y el menú del juego no la ofrece
    drum_notes = drum_hits(song, drums) if drums else []
    for index, (instrument, channel) in enumerate(INSTRUMENTS):
        notes = song.notes.get(channel, []) if channel else []
        if not notes and not (instrument == "bateria" and drum_notes):
            chart_labels += ["0"] * len(DIFFICULTIES)
            summary.append(f"  {instrument:9} -")
            continue
        instrument_mask |= 1 << index
        counts = []
        for difficulty in DIFFICULTIES:
            label = f"chart_{name}_{instrument}_{difficulty.name}"
            if instrument == "bateria":
                chart = build_drum_chart(drum_notes, difficulty.name, grid, LEAD_IN)
            else:
                role, partner_channel = ROLE_OF[instrument]
                chart = build_chart(notes, difficulty, grid, LEAD_IN, role, song.notes.get(partner_channel, []))
            key = f"{instrument}/{difficulty.name}"
            if edits and edits.get(key):
                chart = apply_edits(chart, edits[key], warn=lambda text, key=key: print(f"  AVISO edits.json ({key}): {text}"))
            validate_chart(key, chart)
            charts.append((label, chart_to_asm(label, chart), chart_size(chart)))
            chart_labels.append(label)
            counts.append(f"{difficulty.name} {len(chart)}")
        summary.append(f"  {instrument:9} ({channel or 'ruido y DPCM'}): " + ", ".join(counts))
    if not instrument_mask:
        sys.exit("La canción no tiene notas en ningún canal melódico")

    # 5) ¿Cabe en el slot de 16 KB? Música y charts van seguidos desde $A000;
    #    los samples, al final del slot y alineados a 64 bytes (ver dpcm_start)
    if dmc_size > BANK_SIZE:
        sys.exit(f"Los samples DPCM ocupan {dmc_size} B y el máximo es {BANK_SIZE} B")
    data_size = FICHA_RESERVE + music_size + sum(c[2] for c in charts)
    total = data_size + dpcm_room(dmc_size)
    return Converted(total <= SLOT_SIZE, total, music_label, music_size, dmc_files, dmc_size, project, song, grid,
                     charts, chart_labels, instrument_mask, summary)


def song_grid(song: famistudio.Song, beat_frames: int | None, is_nsf: bool) -> BeatGrid:
    """La rejilla de tiempos: la de FamiStudio es confiable en sus proyectos, no en un NSF importado."""
    if beat_frames or is_nsf:
        all_onsets = [n.frame for ch in song.notes.values() for n in merge_attacks(ch)]
        return estimate_beat(all_onsets, beat_frames)
    return estimate_beat([0], song.frames_per_beat)


def dpcm_room(dmc_size: int) -> int:
    """Bytes que ocupan los samples al final del slot (múltiplo de 64)."""
    return (dmc_size + 63) // 64 * 64


def dpcm_start(dmc_size: int) -> int:
    """Dirección de los samples: pegados al final del slot ($DFFF). Como son a lo
    más 8 KB, quedan en $C000 o después, que es donde el chip de sonido los lee."""
    return SLOT_START + SLOT_SIZE - dpcm_room(dmc_size)


def write_song_list() -> list[str]:
    """Regenera src/songs/list.s con todas las canciones de src/songs/*/song.s."""
    names = sorted(p.parent.name for p in SONGS_DIR.glob("*/song.s"))
    if not names:
        sys.exit("No hay canciones en src/songs/")
    if len(names) > MAX_SONGS:
        # No es un error: puedes tener más canciones que slots y compilar un subconjunto (build.ps1 -Solo)
        print(f"AVISO: hay {len(names)} canciones y el cartucho tiene {MAX_SONGS} slots (ver nes.cfg): "
              "compila un subconjunto con `build.ps1 -Solo <patrón>` (o SOLO=<patrón> ./build.sh)")
        return names
    includes = "\n".join(
        f'SONG_SLOT_NUMBER .set {slot}\n.include "songs/{n}/song.s"\n' for slot, n in enumerate(names)
    )
    table = "\n".join(f"    .addr song_{n}" for n in names)
    write_lf(SONGS_DIR / "list.s", f"""; Generado por `nesband` - lista de canciones de la ROM, en orden alfabético
; Cada canción va en su slot de 16 KB (ver nes.cfg)
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


AUDIO_DIR = ROOT / "audio"
AUDIO_OUT = ROOT / "src" / "audio"


def build_audio(args: argparse.Namespace) -> None:
    """Exporta la música del título y los efectos de sonido (proyectos de FamiStudio en audio/)."""
    fs = famistudio.find_famistudio(ROOT)
    AUDIO_OUT.mkdir(parents=True, exist_ok=True)

    # Música del título: un proyecto con una canción
    title_path = AUDIO_OUT / "title_music.s"
    famistudio.run(fs, [str(AUDIO_DIR / "titulo.txt"), "famistudio-asm-export", str(title_path),
                        "-famistudio-asm-format:ca65"])
    title_asm = title_path.read_text(encoding="utf-8")
    missing = famistudio.read_required_flags(title_asm) - SUPPORTED_FLAGS
    if missing:
        sys.exit(f"La música del título necesita banderas que src/audio.s no activa: {', '.join(sorted(missing))}")
    write_lf(title_path, title_asm.replace(famistudio.read_music_label(title_asm), "title_music_data"))

    # Efectos: cada "canción" del proyecto es un efecto, en ese orden
    sfx_path = AUDIO_OUT / "sfx.s"
    famistudio.run(fs, [str(AUDIO_DIR / "efectos.txt"), "famistudio-asm-sfx-export", str(sfx_path),
                        "-famistudio-asm-format:ca65", "-famistudio-asm-sfx-mode:ntsc"])
    sfx_asm = sfx_path.read_text(encoding="utf-8")
    names = re.findall(r"^\s*\.word @sfx_ntsc_(\w+)", sfx_asm, re.MULTILINE)
    ids = "".join(f"SFX_{n.upper()} = {i}\n" for i, n in enumerate(names))
    write_lf(sfx_path, f"; Constantes de cada efecto (índice para famistudio_sfx_play)\n{ids}\n{sfx_asm}")
    print(f"Música del título y {len(names)} efectos ({', '.join(names)}) -> src/audio/")


def preview(args: argparse.Namespace) -> None:
    """Exporta los primeros segundos de cada pista de un NSF a WAV, para elegir cuál importar
    cuando el NSF no trae .m3u (que diría el nombre de cada pista)."""
    source: Path = args.source.resolve()
    header = source.read_bytes()[:0x80]
    if header[:5] != b"NESM\x1a":
        sys.exit(f"{source.name} no es un NSF")
    total = header[6]
    game = header[0x0E:0x2E].split(b"\0")[0].decode("ascii", "replace")
    slug = re.sub(r"[^a-z0-9]+", "_", game.lower()).strip("_") or "nsf"
    out_dir = ROOT / "build" / "previews" / slug
    out_dir.mkdir(parents=True, exist_ok=True)
    fs = famistudio.find_famistudio(ROOT)
    print(f"{game}: {total} pistas -> {out_dir.relative_to(ROOT)}")
    for index in range(total):
        wav = out_dir / f"pista_{index + 1:02d}.wav"   # numeradas desde 1, como --track
        famistudio.run(fs, [str(source), "wav-export", str(wav), *famistudio.import_options(source, index, args.seconds)])
        print(f"  pista {index + 1:2d} (--song {index})")


def build_scene(args: argparse.Namespace) -> None:
    from . import scene

    if args.preview:
        scene.preview()
    else:
        scene.main()


def build_font(args: argparse.Namespace) -> None:
    from . import fontgen

    font = args.fuente or ROOT / "assets" / "fonts" / "Bongo-8_Mono.ttf"
    try:
        glyphs = fontgen.glyphs_from(font)
    except ImportError:
        sys.exit("Falta Pillow: corre `uv run --with pillow nesband build-font` (solo hace falta para las fuentes TTF)")
    except (OSError, ValueError) as e:
        sys.exit(str(e))
    out = args.out or ROOT / "src" / "font.s"
    out.parent.mkdir(parents=True, exist_ok=True)
    write_lf(out, fontgen.build_font_s(glyphs, font.name))
    print(f"{out} generado desde {font.name}")


def list_songs(args: argparse.Namespace) -> None:
    names = write_song_list()
    print(f"{len(names)} canciones en src/songs/list.s: {', '.join(names)}")


def reimport(args: argparse.Namespace) -> None:
    """Vuelve a importar canciones con las mismas opciones (después de mejorar el generador)."""
    names = args.names or sorted(p.parent.name for p in SONGS_DIR.glob("*/import.json"))
    for name in names:
        options_file = SONGS_DIR / name / "import.json"
        if not options_file.exists():
            sys.exit(f"{name} no tiene import.json: impórtala una vez con import-song")
        options = json.loads(options_file.read_text(encoding="utf-8"))
        print(f"=== {name}")
        import_song(argparse.Namespace(
            source=ROOT / options["source"], name=name, track=options["track"], song=options["song"],
            title=options["title"], game=options["game"], duration=options["duration"],
            beat_frames=options["beat_frames"],
        ))


def edit_chart(args: argparse.Namespace) -> None:
    from . import editor

    if args.html:
        if not args.name:
            sys.exit("--html necesita el nombre de la canción")
        payload = editor.build_payload(editor.load_song_source(args.name))
        args.html.write_text(editor.render_page(payload), encoding="utf-8", newline="\n")
        print(f"Página de solo lectura: {args.html}")
    else:
        editor.serve(args.name, args.port, not args.no_open)


def main() -> None:
    parser = argparse.ArgumentParser(prog="nesband", description="Herramientas de PC para NESBand")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("import-song", help="Importa una canción (NSF, VGM del NES, FamiStudio o FamiTracker) y genera sus charts")
    p.add_argument("source", type=Path, help="archivo .nsf, .nsfe, .vgm, .vgz, .fms, .ftm o proyecto de texto (.txt)")
    p.add_argument("--name", required=True, help="identificador de la canción (minúsculas, sin espacios)")
    p.add_argument("--track", type=int,
                   help="pista como la numera el .m3u (desde 1); de ahí salen título, juego y duración")
    p.add_argument("--song", type=int, default=0, help="índice de la canción dentro del archivo (desde 0)")
    p.add_argument("--title", help="nombre que se muestra en el menú")
    p.add_argument("--game", help="juego del que viene (default: el del .m3u o el nombre del NSF)")
    p.add_argument("--duration", type=int, help="solo NSF: segundos a grabar (default: los del .m3u, o 120)")
    p.add_argument("--beat-frames", type=int, help="cuadros por tiempo, si la estimación automática falla")
    p.set_defaults(func=import_song)

    p = sub.add_parser("list-songs", help="Regenera src/songs/list.s (por ejemplo, después de borrar una canción)")
    p.set_defaults(func=list_songs)

    p = sub.add_parser("preview", help="Exporta unos segundos de cada pista de un NSF a WAV (build/previews/)")
    p.add_argument("source", type=Path, help="archivo .nsf")
    p.add_argument("--seconds", type=int, default=15, help="segundos por pista")
    p.set_defaults(func=preview)

    p = sub.add_parser("build-audio", help="Exporta la música del título y los efectos (audio/*.txt) a src/audio/")
    p.set_defaults(func=build_audio)

    p = sub.add_parser("build-font", help="Genera src/font.s: las letras del juego desde una fuente de 8x8 (.ttf con Pillow, o .pf)")
    p.add_argument("--fuente", "--ttf", dest="fuente", type=Path,
                   help="fuente a usar: .ttf de 8 px o .pf de Fonts_MiSTer (default: Bongo-8 Mono, assets/fonts/)")
    p.add_argument("--out", type=Path, help="archivo a generar (default: src/font.s; las fuentes privadas van a build/font_private.s)")
    p.set_defaults(func=build_font)

    p = sub.add_parser("build-scene", help="Genera src/scene_art.s: el público, las luces y las torres del escenario")
    p.add_argument("--preview", action="store_true", help="en vez de generar, dibuja el escenario como texto")
    p.set_defaults(func=build_scene)

    p = sub.add_parser("reimport", help="Vuelve a importar canciones con las opciones que se usaron la primera vez")
    p.add_argument("names", nargs="*", help="canciones (default: todas)")
    p.set_defaults(func=reimport)

    p = sub.add_parser("edit-chart", help="Abre el editor visual de charts de una canción (página local en el navegador)")
    p.add_argument("name", nargs="?", help="canción de src/songs/ (sin ella, el editor abre en blanco y eliges desde su menú Archivo)")
    p.add_argument("--port", type=int, default=8765, help="puerto local (0 = cualquiera libre)")
    p.add_argument("--no-open", action="store_true", help="no abrir el navegador")
    p.add_argument("--html", type=Path, help="en vez de servir, escribe una página HTML de solo lectura en esta ruta")
    p.set_defaults(func=edit_chart)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
