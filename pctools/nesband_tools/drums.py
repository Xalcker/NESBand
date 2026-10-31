"""Batería: de los golpes del canal de ruido y de DPCM a un chart de 4 pads y bombo, al estilo de Rock Band.

Un NSF no dice qué es cada golpe, así que primero se agrupan: cada grupo es un canal (Ruido o DPCM), un
tono o sample y el instrumento de FamiStudio que lo toca. El usuario (o una sugerencia automática) le asigna
a cada grupo un papel; la asignación vive en src/songs/<canción>/drums.json, aparte del chart, para que
`nesband reimport` no la pierda. Con ella se genera un chart por dificultad (build_drum_chart), que luego
se retoca a mano en el editor con las mismas ediciones (edits.json) que los demás instrumentos.

Papeles y carriles (cada carril es el color de siempre, que fija el botón del control):
    tarola = rojo (↓)   tom 1 / hi-hat = amarillo (→)   tom 2 / ride = azul (B)   tom 3 / crash = verde (←)
    bombo = naranja (A), la barra
En el nivel experto (el "Pro" de Rock Band) un golpe de platillo se marca con el bit $40 (la batería no usa
colas); va en el mismo carril y botón que un tom, solo se ve distinto. En las demás dificultades los
platillos se tocan como toms.
"""

from __future__ import annotations

from dataclasses import dataclass

# Papeles, drums.json y el chart de batería son los mismos en los cuatro juegos: viven en bandcore
from bandcore.drums import (  # noqa: F401
    CYMBAL_WEIGHT_PENALTY,
    DRUMS_FILE,
    DRUMS_VERSION,
    FOLD,
    MAX_BUTTONS,
    MAX_HANDS,
    MERGE_FRAMES,
    MIN_GROUP_HITS,
    PRO_CYMBALS,
    ROLES,
    ROLE_LABELS,
    ROLE_LANE,
    ROLE_WEIGHT,
    Hit,
    build_drum_chart,
    check_assignment,
    dump_drums,
    load_drums,
    save_drums,
)

from .famistudio import Note, Song, midi_to_name


DRUM_CHANNELS = ("Noise", "DPCM")


@dataclass(frozen=True)
class Group:
    key: str  # "Noise:G3:Duty 0"
    channel: str
    pitch: int
    instrument: str
    count: int
    avg_duration: float
    first_frame: int

    @property
    def tone(self) -> str:
        return midi_to_name(self.pitch)


def group_key(channel: str, pitch: int, instrument: str | None) -> str:
    return f"{channel}:{midi_to_name(pitch)}:{instrument or ''}"


def drum_groups(song: Song) -> list[Group]:
    """Los grupos de golpes de ruido y DPCM, ordenados por canal y tono."""
    found: dict[str, list[Note]] = {}
    for channel in DRUM_CHANNELS:
        for note in song.notes.get(channel, []):
            found.setdefault(group_key(channel, note.pitch, note.instrument), []).append(note)
    groups = []
    for key, notes in found.items():
        channel = key.split(":", 1)[0]
        groups.append(Group(key, channel, notes[0].pitch, notes[0].instrument or "", len(notes),
                            sum(n.duration for n in notes) / len(notes), min(n.frame for n in notes)))
    return sorted(groups, key=lambda g: (DRUM_CHANNELS.index(g.channel), g.pitch, g.instrument))


NAME_HINTS = (
    (("bombo", "kick", "bass drum", "bd"), "kick", False),
    (("tarola", "snare", "caja", "sd"), "snare", False),
    (("hat", "hh", "cerrado", "abierto", "closed", "open"), "tom1", True),   # hi-hat: amarillo
    (("ride",), "tom2", True),                                              # ride: azul
    (("platillo", "cymbal", "crash"), "tom3", True),                        # crash: verde
    (("tom",), "tom1", False),
)


def suggest_assignment(groups: list[Group]) -> dict[str, dict]:
    """Una primera asignación: por el nombre del instrumento si lo dice, si no por el canal y el tono.

    DPCM: el sample más grave es el bombo y el siguiente la tarola. Ruido: lo más grave es bombo o tom, el
    medio tarola y lo agudo (hi-hat, platillo) va de platillo en el tom 2. Casi nunca acierta del todo:
    es el punto de partida para corregir en el editor."""
    assignment: dict[str, dict] = {g.key: {"lane": None, "cymbal": False} for g in groups}
    used: set[str] = set()
    rest = []
    for group in groups:
        if group.count < MIN_GROUP_HITS:
            continue
        name = group.instrument.lower()
        for words, role, cymbal in NAME_HINTS:
            if any(word in name for word in words):
                assignment[group.key] = {"lane": role, "cymbal": cymbal}
                used.add(role)
                break
        else:
            rest.append(group)

    def give(group: Group, preferred: list[str], cymbal: bool = False) -> None:
        role = next((r for r in preferred if r not in used), preferred[-1])
        assignment[group.key] = {"lane": role, "cymbal": cymbal}
        used.add(role)

    dpcm = sorted((g for g in rest if g.channel == "DPCM"), key=lambda g: g.pitch)
    for index, group in enumerate(dpcm):
        give(group, ["kick"] if index == 0 else ["snare", "tom3", "tom1", "tom2"] if index == 1 else ["tom3", "tom1", "tom2"])
    noise = sorted((g for g in rest if g.channel == "Noise"), key=lambda g: g.pitch)
    for index, group in enumerate(noise):
        third = index * 3 // max(1, len(noise))
        if third == 0:
            give(group, ["kick", "tom3", "tom1"])
        elif third == 1:
            give(group, ["snare", "tom1", "tom3"])
        else:
            give(group, ["tom1", "tom2", "tom3"], cymbal=True)   # lo más agudo: hi-hat (amarillo), luego ride y crash
    return assignment


# --- drums.json -----------------------------------------------------------------------------------


# --- Chart --------------------------------------------------------------------------------------------


def drum_hits(song: Song, assignment: dict[str, dict]) -> list[Hit]:
    hits = []
    for channel in DRUM_CHANNELS:
        for note in song.notes.get(channel, []):
            item = assignment.get(group_key(channel, note.pitch, note.instrument))
            if item and item.get("lane"):
                hits.append(Hit(note.frame, item["lane"], bool(item.get("cymbal")) and item["lane"] not in ("kick", "snare")))
    return sorted(hits, key=lambda h: h.frame)
