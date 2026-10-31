"""Lógica del editor de charts, sin interfaz: leer chart.s, aplicar ediciones manuales y validar.

Aplicar y validar ediciones es lo de bandcore (`bandcore.chartedit`, igual en los cuatro juegos; ahí está el formato
de edits.json). Aquí queda lo propio del NES: leer y escribir el chart.s de cada canción.
Las notas se identifican por su cuadro (el mismo de chart.s, contando la entrada de la autopista).
"""

from __future__ import annotations

import re
from pathlib import Path

from bandcore.chartedit import (  # noqa: F401  (el resto de NESBand los usa como chartedit.<nombre>)
    EDITS_FILE,
    EDITS_VERSION,
    KICK_MASK,
    LANE_MASK,
    MAX_DRUM_BUTTONS,
    MAX_DRUM_HANDS,
    TOM_MASK,
    apply_edits,
    chart_from_json,
    chart_problems,
    diff_charts,
    dump_edits,
    lanes_of,
    load_edits,
    save_edits,
    validate_chart,
)

from .chart import CHART_END, END_FLAG, STAR_FLAG, SUSTAIN_FLAG, ChartNote

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


def entries_to_chart(entries: list[tuple[int, int]], drums: bool = False) -> list[ChartNote]:
    """Inverso de chart.chart_entries: del formato del juego a notas con su cola y su frase estelar.
    En la batería el bit $40 es un platillo (no hay colas)."""
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
        note = {"frame": frame, "mask": mask & LANE_MASK, "end": None, "star": bool(mask & STAR_FLAG),
                "cymbal": drums and bool(mask & SUSTAIN_FLAG)}
        notes.append(note)
        if mask & SUSTAIN_FLAG and not drums:
            open_notes.append(note)
    return [ChartNote(n["frame"], n["mask"], n["end"], n["star"], n["cymbal"]) for n in notes]


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
            result[f"{match.group(1)}/{match.group(2)}"] = entries_to_chart(entries, match.group(1) == "bateria")
    return result


def chart_file_text(source_name: str, blocks: list[str]) -> str:
    """El chart.s completo: el encabezado y el ensamblador de cada chart (chart.chart_to_asm), en orden."""
    return "\n".join([f"; Generado por `nesband import-song` desde {source_name} - no editar a mano\n", *blocks])
