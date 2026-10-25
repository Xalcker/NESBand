"""Ejecuta FamiStudio por línea de comandos y lee su formato de texto.

FamiStudio importa NSF, FamiTracker y sus propios proyectos. De ahí sacamos dos cosas:
  - el ensamblador para su motor de sonido (lo que suena en el NES)
  - un export de texto con cada nota, del que generamos los charts
"""

from __future__ import annotations

import os
import platform
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

CHANNEL_TYPES = ["Square1", "Square2", "Triangle", "Noise", "DPCM"]

_ATTR = re.compile(r'(\w+)="([^"]*)"')
_NOTE_NAME = re.compile(r"^([A-G])(#?)(-?\d)$")
_PITCH_CLASS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def find_famistudio(root: Path) -> Path:
    """FamiStudio: variable de entorno FAMISTUDIO, o la copia en tools/famistudio."""
    env = os.environ.get("FAMISTUDIO")
    if env:
        return Path(env)
    exe = {"Windows": "FamiStudio.exe", "Darwin": "FamiStudio.app"}.get(platform.system(), "FamiStudio")
    candidate = root / "tools" / "famistudio" / exe
    if candidate.exists():
        return candidate
    raise FileNotFoundError(
        f"No encontré FamiStudio en {candidate}. Descárgalo (ver README) o define la variable FAMISTUDIO."
    )


def _command(famistudio: Path) -> list[str]:
    """Cómo lanzar FamiStudio. En macOS es un .app de .NET cuyo lanzador manda la salida a un log, así que se
    corre su FamiStudio.dll con el dotnet del PATH."""
    if famistudio.suffix.lower() == ".app":
        famistudio = famistudio / "Contents" / "MacOS" / "FamiStudio.dll"
    if famistudio.suffix.lower() == ".dll":
        return ["dotnet", str(famistudio)]
    return [str(famistudio)]


def run(famistudio: Path, args: list[str]) -> str:
    # FamiStudio pide .NET 8; con roll-forward también corre con uno más nuevo si el 8 no está instalado
    env = {**os.environ, "DOTNET_ROLL_FORWARD": os.environ.get("DOTNET_ROLL_FORWARD", "Major")}
    result = subprocess.run([*_command(famistudio), *args], capture_output=True, text=True, env=env)
    output = result.stdout + result.stderr
    if result.returncode != 0 or "Error" in output:
        raise RuntimeError(f"FamiStudio falló ({' '.join(args)}):\n{output}")
    return output


def import_options(source: Path, song: int, duration: int) -> list[str]:
    """Opciones para leer la canción `song` de cualquier formato de entrada."""
    if source.suffix.lower() in (".nsf", ".nsfe"):
        # Un NSF tiene un solo "song" por exportación: FamiStudio graba `duration` segundos
        return [f"-nsf-import-song:{song}", f"-nsf-import-duration:{duration}"]
    return [f"-export-songs:{song}"]


# --- Lectura del formato de texto ------------------------------------------------


@dataclass
class Note:
    frame: int  # cuadro desde que empieza la canción
    pitch: int  # número MIDI (solo importa para comparar alturas)
    duration: int
    extra: int | None = None  # otra altura del mismo gesto (un arpegio fusionado: un acorde "roto"); ver merge_attacks
    instrument: str | None = None  # nombre del instrumento de FamiStudio (en ruido y DPCM, parte de lo que identifica un golpe)


@dataclass
class Song:
    name: str
    attrs: dict[str, str]
    pattern_frames: list[int] = field(default_factory=list)  # duración en cuadros de cada patrón
    notes: dict[str, list[Note]] = field(default_factory=dict)  # por tipo de canal

    @property
    def length_frames(self) -> int:
        return sum(self.pattern_frames)

    @property
    def frames_per_beat(self) -> int:
        return int(self.attrs["BeatLength"]) * int(self.attrs["NoteLength"])


@dataclass
class Project:
    attrs: dict[str, str]
    songs: list[Song]


_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def midi_to_name(pitch: int) -> str:
    """60 -> "C4" (inverso de note_to_midi)."""
    return f"{_NAMES[pitch % 12]}{pitch // 12 - 1}"


def note_to_midi(value: str) -> int | None:
    match = _NOTE_NAME.match(value)
    if not match:
        return None  # "Stop", "Release", etc.
    letter, sharp, octave = match.groups()
    return 12 * (int(octave) + 1) + _PITCH_CLASS[letter] + (1 if sharp else 0)


def parse_text(text: str) -> Project:
    """Lee un archivo de `famistudio-txt-export`.

    La jerarquía va por tabuladores:
        Project > Song > Channel > Pattern > Note
                       > Channel > PatternInstance
                       > PatternCustomSettings
    En el modo de tempo "FamiStudio", el Time de las notas está en cuadros.
    """
    project_attrs: dict[str, str] = {}
    songs: list[Song] = []
    # Por canción y canal: patrones (nombre -> notas en cuadros relativos) e instancias
    patterns: dict[str, list[tuple[int, int, int]]] = {}
    instances: list[tuple[int, str]] = []
    custom: dict[int, dict[str, str]] = {}
    channel = ""
    pattern = ""

    def finish_channel() -> None:
        if songs and channel:
            song = songs[-1]
            starts = _pattern_starts(song)
            notes = []
            for index, name in sorted(instances):
                if index >= len(starts):
                    continue
                for time, pitch, duration, instrument in patterns.get(name, []):
                    notes.append(Note(starts[index] + time, pitch, duration, None, instrument))
            song.notes[channel] = sorted(notes, key=lambda n: n.frame)

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        tag = stripped.split(" ", 1)[0]
        attrs = dict(_ATTR.findall(stripped))

        if tag == "Project":
            project_attrs = attrs
            if attrs.get("TempoMode", "FamiStudio") != "FamiStudio":
                raise ValueError(
                    "El proyecto usa tempo de FamiTracker. Ábrelo en FamiStudio y conviértelo a tempo FamiStudio."
                )
        elif tag == "Song":
            finish_channel()
            channel, patterns, instances, custom = "", {}, [], {}
            songs.append(Song(attrs.get("Name", f"Song {len(songs)}"), attrs))
        elif tag == "PatternCustomSettings":
            custom[int(attrs["Time"])] = attrs
        elif tag == "Channel":
            finish_channel()
            if channel == "" and songs and not songs[-1].pattern_frames:
                _compute_pattern_frames(songs[-1], custom)
            channel, patterns, instances = attrs["Type"], {}, []
        elif tag == "Pattern":
            pattern = attrs["Name"]
            patterns[pattern] = []
        elif tag == "Note" and "Value" in attrs:
            pitch = note_to_midi(attrs["Value"])
            if pitch is not None:
                patterns[pattern].append((int(attrs["Time"]), pitch, int(attrs.get("Duration", "1")), attrs.get("Instrument")))
        elif tag == "PatternInstance":
            instances.append((int(attrs["Time"]), attrs["Pattern"]))
    finish_channel()
    return Project(project_attrs, songs)


def _compute_pattern_frames(song: Song, custom: dict[int, dict[str, str]]) -> None:
    length = int(song.attrs["Length"])
    for index in range(length):
        settings = custom.get(index, song.attrs)
        song.pattern_frames.append(int(settings["Length" if index in custom else "PatternLength"]) * int(settings["NoteLength"]))


def _pattern_starts(song: Song) -> list[int]:
    starts, total = [], 0
    for frames in song.pattern_frames:
        starts.append(total)
        total += frames
    return starts


def read_required_flags(asm: str) -> set[str]:
    """Banderas del motor que pide la música exportada (vienen como comentarios al inicio)."""
    return set(re.findall(r"^;\s*(FAMISTUDIO_\w+)\s*=\s*1", asm, re.MULTILINE))


def read_export_size(output: str) -> int:
    """Bytes del ensamblador exportado, según lo que reporta FamiStudio."""
    match = re.search(r"Total assembly file size: (\d+) bytes", output)
    if not match:
        raise ValueError(f"FamiStudio no reportó el tamaño de la música:\n{output}")
    return int(match.group(1))


def read_music_label(asm: str) -> str:
    match = re.search(r"^(music_data_\w+):", asm, re.MULTILINE)
    if not match:
        raise ValueError("No encontré la etiqueta music_data_... en el ensamblador exportado")
    return match.group(1)
