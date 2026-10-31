"""Charts de NESBand: el generador común está en bandcore (`bandcore.chart`, ahí se explica cómo se arma un chart).

Aquí queda lo propio del NES: escribir cada chart en el ensamblador de chart.s (`chart_to_asm`).
"""

from __future__ import annotations

# El generador de charts, la nota y las reglas de lo que se puede tocar son los mismos en los cuatro juegos:
# viven en bandcore (aquí se vuelven a exportar para el resto del juego)
from bandcore.chart import (  # noqa: F401
    BLOCKED_PAIRS,
    CHART_END,
    DIFFICULTIES,
    DRUM_BLOCKED_PAIRS,
    END_FLAG,
    KEYS_WINDOW,
    MAX_DELTA,
    MIN_SUSTAIN,
    ROLES,
    STAR_FIRST,
    STAR_FLAG,
    STAR_PHRASE_LEN,
    STAR_SPACING,
    SUSTAIN_FLAG,
    SUSTAIN_GAP,
    SUSTAIN_TRIM,
    BeatGrid,
    ChartNote,
    Difficulty,
    arpeggio_pitch,
    assign_lanes,
    build_chart,
    chart_entries,
    chart_size,
    check_playable,
    chord_masks,
    estimate_beat,
    lanes_clash,
    merge_attacks,
    reduce_notes,
    second_lane,
    star_notes,
    sustain_ends,
)


def chart_to_asm(label: str, chart: list[ChartNote]) -> str:
    lines = [f"{label}:"]
    for delta, mask in chart_entries(chart):
        comment = "  ; fin" if mask == CHART_END else ""
        lines.append(f"    .byte {delta}, ${mask:02X}{comment}")
    return "\n".join(lines) + "\n"
