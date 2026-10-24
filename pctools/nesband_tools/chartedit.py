"""Lógica del editor de charts, sin interfaz: leer chart.s, aplicar ediciones manuales y validar.

Las ediciones viven en src/songs/<canción>/edits.json, aparte del chart que genera el importador.
`nesband import-song` / `reimport` genera el chart automático de cada instrumento y dificultad y
luego le aplica las ediciones (apply_edits), así que mejorar el generador no pierde las correcciones.

Formato de edits.json:
    {"version": 1,
     "charts": {"guitarra/facil": [
         {"op": "delete", "frame": 168},
         {"op": "add", "frame": 200, "mask": 5, "end": 230, "star": false},
         {"op": "set", "frame": 328, "mask": 2, "end": null, "star": true}]}}
Las notas se identifican por su cuadro (el mismo de chart.s, contando la entrada de la autopista).
Si el generador cambia y una operación ya no encuentra su nota, se avisa y se omite.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from .chart import (
    BLOCKED_PAIRS,
    CHART_END,
    END_FLAG,
    STAR_FLAG,
    STAR_PHRASE_LEN,
    SUSTAIN_FLAG,
    ChartNote,
    check_playable,
    lanes_clash,
)

EDITS_FILE = "edits.json"
EDITS_VERSION = 1
LANE_MASK = 0x1F


def lanes_of(mask: int) -> set[int]:
    return {b for b in range(5) if mask >> b & 1}


# --- Leer chart.s -------------------------------------------------------------------


def parse_chart_asm(text: str) -> dict[str, list[tuple[int, int]]]:
    """Las entradas (cuadros, carriles) de cada etiqueta de un chart.s."""
    charts: dict[str, list[tuple[int, int]]] = {}
    current: list[tuple[int, int]] | None = None
    for line in text.splitlines():
        code = line.split(";", 1)[0].strip()
        label = re.fullmatch(r"(\w+):", code)
        if label:
            current = charts.setdefault(label.group(1), [])
            continue
        byte = re.fullmatch(r"\.byte\s+(\d+)\s*,\s*\$([0-9A-Fa-f]{2})", code)
        if byte and current is not None:
            current.append((int(byte.group(1)), int(byte.group(2), 16)))
    return charts


def entries_to_chart(entries: list[tuple[int, int]]) -> list[ChartNote]:
    """Inverso de chart.chart_entries: del formato del juego a notas con su cola y su frase estelar."""
    notes: list[dict] = []
    open_notes: list[dict] = []  # notas con cola esperando su entrada de fin
    frame = 0
    for delta, mask in entries:
        if mask == CHART_END:
            break
        frame += delta
        if mask == 0:  # relleno: solo avanza el tiempo
            continue
        if mask & END_FLAG:
            release = mask & LANE_MASK
            for note in list(open_notes):
                if note["mask"] & ~release == 0:
                    note["end"] = frame
                    release &= ~note["mask"]
                    open_notes.remove(note)
            continue
        note = {"frame": frame, "mask": mask & LANE_MASK, "end": None, "star": bool(mask & STAR_FLAG)}
        notes.append(note)
        if mask & SUSTAIN_FLAG:
            open_notes.append(note)
    return [ChartNote(n["frame"], n["mask"], n["end"], n["star"]) for n in notes]


def read_song_charts(song_dir: Path) -> dict[str, list[ChartNote]]:
    """Los charts de src/songs/<canción>/chart.s, por clave "instrumento/dificultad"."""
    path = song_dir / "chart.s"
    if not path.exists():
        return {}
    name = song_dir.name
    result: dict[str, list[ChartNote]] = {}
    for label, entries in parse_chart_asm(path.read_text(encoding="utf-8")).items():
        match = re.fullmatch(rf"chart_{re.escape(name)}_(\w+?)_(\w+)", label)
        if match:
            result[f"{match.group(1)}/{match.group(2)}"] = entries_to_chart(entries)
    return result


# --- Ediciones ----------------------------------------------------------------------


def load_edits(song_dir: Path) -> dict:
    path = song_dir / EDITS_FILE
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("version") != EDITS_VERSION:
        raise ValueError(f"{path}: versión de edits.json no soportada ({data.get('version')})")
    return data.get("charts", {})


def dump_edits(edits: dict) -> str:
    """El texto de edits.json: una operación por renglón, para que git muestre bien los cambios."""
    edits = {key: ops for key, ops in sorted(edits.items()) if ops}
    if not edits:
        return ""
    lines = ['{', f'  "version": {EDITS_VERSION},', '  "charts": {']
    blocks = []
    for key, ops in edits.items():
        body = ",\n".join("      " + json.dumps(op, ensure_ascii=False) for op in ops)
        blocks.append(f'    {json.dumps(key)}: [\n{body}\n    ]')
    lines.append(",\n".join(blocks))
    lines += ["  }", "}", ""]
    return "\n".join(lines)


def save_edits(song_dir: Path, edits: dict) -> None:
    """Guarda las ediciones; sin ninguna, borra edits.json."""
    path = song_dir / EDITS_FILE
    text = dump_edits(edits)
    if text:
        path.write_text(text, encoding="utf-8", newline="\n")
    elif path.exists():
        path.unlink()


def _note_dict(note: ChartNote) -> dict:
    return {"frame": note.frame, "mask": note.mask, "end": note.end, "star": note.star}


def apply_edits(chart: list[ChartNote], ops: list[dict], warn=None) -> list[ChartNote]:
    """El chart automático con las ediciones manuales encima. `warn(texto)` recibe lo que no se pudo aplicar."""
    warn = warn or (lambda text: None)
    notes = {n.frame: n for n in chart}
    for op in ops:
        frame, kind = op["frame"], op["op"]
        if kind == "add":
            if frame in notes:
                warn(f"cuadro {frame}: ya hay una nota; se reemplaza con la agregada a mano")
            notes[frame] = ChartNote(frame, op["mask"], op.get("end"), op.get("star", False))
        elif frame not in notes:
            warn(f"cuadro {frame}: la nota que se editó ya no existe en el chart automático ({kind} omitido)")
        elif kind == "delete":
            del notes[frame]
        elif kind == "set":
            old = notes[frame]
            notes[frame] = ChartNote(
                frame,
                op.get("mask", old.mask),
                op["end"] if "end" in op else old.end,
                op.get("star", old.star),
            )
        else:
            raise ValueError(f"operación desconocida en edits.json: {kind!r}")
    return sorted(notes.values(), key=lambda n: n.frame)


def diff_charts(auto: list[ChartNote], edited: list[ChartNote]) -> list[dict]:
    """Las operaciones que convierten el chart automático en el editado (inverso de apply_edits)."""
    before = {n.frame: n for n in auto}
    after = {n.frame: n for n in edited}
    ops: list[dict] = []
    for frame in sorted(before.keys() | after.keys()):
        old, new = before.get(frame), after.get(frame)
        if new is None:
            ops.append({"op": "delete", "frame": frame})
        elif old is None:
            ops.append({"op": "add", **_note_dict(new)})
        elif old != new:
            changes = {k: v for k, v in _note_dict(new).items() if _note_dict(old)[k] != v}
            ops.append({"op": "set", "frame": frame, **changes})
    return ops


# --- Validación ---------------------------------------------------------------------


def chart_problems(chart: list[ChartNote]) -> list[dict]:
    """Todo lo que el editor debe avisar de un chart: [{"frame", "kind", "text"}, ...].

    Errores (los que check_playable rechaza): "error". Avisos que el juego acepta pero que no
    son lo habitual: "warn"."""
    problems: list[dict] = []

    def add(frame: int, kind: str, text: str) -> None:
        problems.append({"frame": frame, "kind": kind, "text": text})

    sets = [lanes_of(n.mask) for n in chart]
    for i, (note, lanes) in enumerate(zip(chart, sets)):
        if not lanes:
            add(note.frame, "error", "nota sin carril")
        if any({x, y} in BLOCKED_PAIRS for x in lanes for y in lanes):
            add(note.frame, "error", "acorde imposible (izquierda + derecha de la cruz)")
        if note.end is not None:
            if note.end <= note.frame:
                add(note.frame, "error", "la cola termina antes de empezar")
                continue
            for other, other_lanes in zip(chart[i + 1 :], sets[i + 1 :]):
                if other.frame >= note.end:
                    break
                if lanes_clash(other_lanes, lanes):
                    add(other.frame, "error", f"cae mientras se sostiene la nota del cuadro {note.frame}")
        if note.star and len(lanes) > 1:
            add(note.frame, "warn", "un acorde dentro de una frase estelar")
    run = 0
    for i, note in enumerate(chart):
        run = run + 1 if note.star else 0
        if run and (i + 1 == len(chart) or not chart[i + 1].star) and run != STAR_PHRASE_LEN:
            add(chart[i - run + 1].frame, "warn", f"frase estelar de {run} notas (lo normal son {STAR_PHRASE_LEN})")
    return problems


def validate_chart(key: str, chart: list[ChartNote]) -> None:
    """Falla con un mensaje claro si el chart no se puede tocar (ver chart.check_playable)."""
    try:
        check_playable(chart)
    except ValueError as error:
        raise ValueError(f"chart {key}: {error}") from error
