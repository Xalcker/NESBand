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


_EXT_TITLE = re.compile(r"^#EXTINF:[-\d]+,\s*(.*?)\s*$")
_EXT_ENTRY = re.compile(r"::(\d+)\s*$")
_EXT_TRACK = re.compile(r"^(.*?)\s+-\s+Track\s+\d+\s+-\s+(.*)$")
_EXT_PLAIN = re.compile(r"^(.+?)\s+-\s+(.+)$")


def parse_extm3u(text: str) -> Playlist:
    """El otro formato de .m3u que traen algunos NSF (sin duraciones):

        #EXTINF:-1,Mega Man (NES) - Track 03 - Cut Man Stage
        mega-man-nes.nsf::3
    """
    game = None
    tracks: dict[int, Track] = {}
    title = None
    for line in text.splitlines():
        line = line.strip()
        match = _EXT_TITLE.match(line)
        if match:
            title = match.group(1)
            continue
        entry = _EXT_ENTRY.search(line)
        if entry and title is not None and not line.startswith("#"):
            number = int(entry.group(1))
            named = _EXT_TRACK.match(title) or _EXT_PLAIN.match(title)   # "Juego - Track 03 - Título" o "Juego - Título"
            if named:
                game = game or named.group(1)
                title = named.group(2)
            tracks[number] = Track(number, title, None)
            title = None
    return Playlist(game, tracks)


def parse_m3u(text: str) -> Playlist:
    game = None
    tracks: dict[int, Track] = {}
    if "#EXTINF" in text and "::NSF," not in text:
        return parse_extm3u(text)
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
