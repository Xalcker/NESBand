"""Lectura de las listas .m3u que acompañan a muchos NSF (formato de NEZplug / nsfe2m3u).

    # Blaster Master                          <- primer comentario: el juego
    # Music by Naoki Kodaka & Marumo
    juego.nsf::NSF,2,Area 1,0:01:27,,         <- pista (desde 1), título, duración, fade...

Las comas dentro del título vienen escapadas como "\\,".
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from pathlib import Path

_ENTRY = re.compile(r"::NSF,(\d+),((?:[^,\\]|\\.)*),([^,]*)")


@dataclass(frozen=True)
class Track:
    number: int  # como viene en el .m3u: la primera pista es 1
    title: str
    seconds: int | None  # duración redondeada hacia arriba


@dataclass(frozen=True)
class Playlist:
    game: str | None
    tracks: dict[int, Track]


def parse_duration(text: str) -> int | None:
    """'0:01:27' o '1:27.5' -> segundos (hacia arriba)."""
    parts = text.strip().split(":")
    if not parts or not all(re.fullmatch(r"\d+(\.\d+)?", p) for p in parts):
        return None
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + float(part)
    return math.ceil(seconds) if seconds > 0 else None


def parse_m3u(text: str) -> Playlist:
    game = None
    tracks: dict[int, Track] = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#"):
            if game is None and line[1:].strip():
                game = line[1:].strip()
            continue
        match = _ENTRY.search(line)
        if match:
            number = int(match.group(1))
            title = match.group(2).replace("\\,", ",").strip()
            tracks[number] = Track(number, title, parse_duration(match.group(3)))
    return Playlist(game, tracks)


def find_playlist(nsf: Path) -> Playlist | None:
    m3u = nsf.with_suffix(".m3u")
    if not m3u.exists():
        return None
    return parse_m3u(m3u.read_text(encoding="utf-8", errors="replace"))
