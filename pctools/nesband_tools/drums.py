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

import json
from dataclasses import dataclass
from pathlib import Path

from .chart import DIFFICULTIES, BeatGrid, ChartNote, star_notes
from .famistudio import Note, Song, midi_to_name

DRUMS_FILE = "drums.json"
DRUMS_VERSION = 1
DRUM_CHANNELS = ("Noise", "DPCM")
ROLE_LANE = {"tom3": 0, "snare": 1, "tom1": 2, "tom2": 3, "kick": 4}
ROLE_LABELS = {"kick": "Bombo (barra naranja)", "snare": "Tarola (rojo)", "tom1": "Tom 1 / Hi-hat (amarillo)",
               "tom2": "Tom 2 / Ride (azul)", "tom3": "Tom 3 / Crash (verde)"}
ROLES = tuple(ROLE_LABELS)
ROLE_WEIGHT = {"kick": 3, "snare": 3, "tom1": 2, "tom2": 2, "tom3": 2}
# Con menos dificultad, los toms se juntan en los que quedan: fácil usa bombo, tarola y tom 1; medio agrega el 2
FOLD = {"facil": {"tom2": "tom1", "tom3": "tom1"}, "medio": {"tom3": "tom2"}, "dificil": {}, "experto": {}}
MAX_BUTTONS = {"facil": 1, "medio": 2, "dificil": 2, "experto": 2}   # botones a la vez (un golpe y su bombo)
PRO_CYMBALS = {"experto"}   # dificultades donde los platillos se distinguen de los toms
CYMBAL_WEIGHT_PENALTY = 0.5   # los platillos (hi-hat) son lo primero que se quita al reducir
MERGE_FRAMES = 1   # golpes a esta distancia son el mismo momento
MIN_GROUP_HITS = 3   # sugerencia: grupos con menos golpes no se asignan


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


def load_drums(song_dir: Path) -> dict[str, dict] | None:
    """La asignación guardada (grupo -> {"lane", "cymbal"}), o None si la canción aún no tiene."""
    path = song_dir / DRUMS_FILE
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("version") != DRUMS_VERSION:
        raise ValueError(f"{path}: versión de drums.json no soportada ({data.get('version')})")
    return data.get("groups", {})


def check_assignment(assignment: dict[str, dict]) -> None:
    for key, item in assignment.items():
        if item.get("lane") not in (*ROLES, None):
            raise ValueError(f"{key}: papel desconocido {item.get('lane')!r}")


def dump_drums(assignment: dict[str, dict]) -> str:
    lines = [f'{{\n  "version": {DRUMS_VERSION},\n  "groups": {{']
    lines.append(",\n".join(
        f"    {json.dumps(key, ensure_ascii=False)}: {json.dumps({'lane': item.get('lane'), 'cymbal': bool(item.get('cymbal'))})}"
        for key, item in sorted(assignment.items())))
    lines.append("  }\n}\n")
    return "\n".join(lines)


def save_drums(song_dir: Path, assignment: dict[str, dict]) -> None:
    check_assignment(assignment)
    (song_dir / DRUMS_FILE).write_text(dump_drums(assignment), encoding="utf-8", newline="\n")


# --- Chart --------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Hit:
    frame: int
    role: str
    cymbal: bool


def drum_hits(song: Song, assignment: dict[str, dict]) -> list[Hit]:
    hits = []
    for channel in DRUM_CHANNELS:
        for note in song.notes.get(channel, []):
            item = assignment.get(group_key(channel, note.pitch, note.instrument))
            if item and item.get("lane"):
                hits.append(Hit(note.frame, item["lane"], bool(item.get("cymbal")) and item["lane"] not in ("kick", "snare")))
    return sorted(hits, key=lambda h: h.frame)


def build_drum_chart(hits: list[Hit], difficulty_name: str, grid: BeatGrid, lead_in: int) -> list[ChartNote]:
    """El chart de batería de una dificultad.

    1. Los toms se juntan según la dificultad (FOLD) y los golpes casi simultáneos son un "momento".
    2. De cada momento quedan hasta MAX_BUTTONS botones (primero bombo y tarola), sin verde + amarillo.
    3. Se quitan momentos hasta que ninguno quede a menos de min_gap cuadros de otro, conservando los
       de los tiempos fuertes y los de bombo y tarola.
    4. Los platillos solo se marcan en las dificultades Pro (PRO_CYMBALS)."""
    difficulty = next(d for d in DIFFICULTIES if d.name == difficulty_name)
    fold, max_buttons = FOLD[difficulty_name], MAX_BUTTONS[difficulty_name]
    moments: list[dict] = []   # {"frame", "lanes": {lane: (peso, platillo)}}
    for hit in hits:
        role = fold.get(hit.role, hit.role)
        weight = ROLE_WEIGHT[role] - (CYMBAL_WEIGHT_PENALTY if hit.cymbal else 0)
        if moments and hit.frame - moments[-1]["frame"] <= MERGE_FRAMES:
            lanes = moments[-1]["lanes"]
            old = lanes.get(ROLE_LANE[role])
            lanes[ROLE_LANE[role]] = (max(weight, old[0]) if old else weight, hit.cymbal and (old[1] if old else True))
        else:
            moments.append({"frame": hit.frame, "lanes": {ROLE_LANE[role]: (weight, hit.cymbal)}})
    pro = difficulty_name in PRO_CYMBALS
    for moment in moments:
        lanes = moment["lanes"]
        if not pro and any(not cymbal for _, cymbal in lanes.values()):
            # Sin Pro un platillo es un tom más: si el momento ya tiene un golpe de bombo o tarola, el
            # platillo se omite (si no, casi todo sería un acorde con el hi-hat)
            lanes = {lane: value for lane, value in lanes.items() if not value[1]}
        ranked = sorted(lanes.items(), key=lambda item: -item[1][0])
        kept: dict[int, tuple] = {}
        for lane, value in ranked:
            if len(kept) < max_buttons and not any({lane, other} == {0, 2} for other in kept):
                kept[lane] = value
        moment["lanes"] = kept
        moment["weight"] = max(w for w, _ in kept.values())
    by_priority = sorted(moments, key=lambda m: (-grid.strength(m["frame"]), -m["weight"], m["frame"]))
    chosen: list[dict] = []
    for moment in by_priority:
        if all(abs(moment["frame"] - other["frame"]) >= difficulty.min_gap for other in chosen):
            chosen.append(moment)
    chosen.sort(key=lambda m: m["frame"])
    masks = [sum(1 << lane for lane in m["lanes"]) for m in chosen]
    stars = star_notes(len(chosen), [mask & (mask - 1) != 0 for mask in masks])
    return [
        ChartNote(lead_in + m["frame"], mask, None, star,
                  pro and any(cymbal for lane, (_, cymbal) in m["lanes"].items() if lane not in (ROLE_LANE["kick"], ROLE_LANE["snare"])))
        for m, mask, star in zip(chosen, masks, stars)
    ]
