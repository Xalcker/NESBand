"""Generación automática de charts a partir de las notas de un canal.

Pasos:
  1. Reducir: según la dificultad, quitamos notas demasiado juntas. Se conservan
     primero las que caen en tiempos fuertes (el beat), luego medios tiempos, etc.
  2. Carriles: la nota más aguda de su vecindario va a la derecha y la más grave
     a la izquierda. Además se respeta el contorno: si la melodía sube, el carril
     sube; si repite nota, repite carril.
"""

from __future__ import annotations

from dataclasses import dataclass

from .famistudio import Note

FRAMES_PER_ROW = 4  # debe coincidir con FRAMES_PER_ROW en src/main.s


@dataclass(frozen=True)
class Difficulty:
    name: str
    lanes: int  # cuántos carriles usa (desde el verde)
    min_gap: int  # cuadros mínimos entre dos notas


DIFFICULTIES = [
    Difficulty("facil", lanes=3, min_gap=24),
    Difficulty("medio", lanes=4, min_gap=14),
    Difficulty("dificil", lanes=5, min_gap=9),
    Difficulty("experto", lanes=5, min_gap=5),
]


@dataclass(frozen=True)
class BeatGrid:
    frames_per_beat: int
    first_beat: int  # cuadro (relativo a la música) del primer tiempo

    def strength(self, frame: int) -> int:
        """3 = en el tiempo, 2 = medio tiempo, 1 = cuarto de tiempo, 0 = otra cosa."""
        offset = (frame - self.first_beat) % self.frames_per_beat
        for level, divisions in ((3, 1), (2, 2), (1, 4)):
            step = self.frames_per_beat / divisions
            nearest = round(offset / step) * step
            if abs(offset - nearest) <= 1:
                return level
        return 0


def estimate_beat(onsets: list[int], hint: int | None = None) -> BeatGrid:
    """Estima la duración del tiempo a partir de todos los ataques de la canción.

    Un NSF no trae tempo: FamiStudio adivina uno al importarlo y suele fallar. Aquí
    buscamos el intervalo más común entre ataques (la "subdivisión") y lo
    duplicamos hasta caer en un tempo razonable (100-200 BPM a 60 cuadros/s).
    """
    onsets = sorted(set(onsets))
    if hint:
        period = hint
    else:
        counts: dict[int, int] = {}
        for a, b in zip(onsets, onsets[1:]):
            gap = b - a
            if 3 <= gap <= 48:
                counts[gap] = counts.get(gap, 0) + 1
        step = max(counts, key=lambda g: (counts[g], -g)) if counts else 8
        # Duplicar la subdivisión hasta llegar a 18 cuadros (200 BPM) o más
        period = step
        while period < 18:
            period *= 2
    # Fase: la que hace caer más ataques en tiempos
    best_phase = max(range(period), key=lambda p: sum(1 for f in onsets if (f - p) % period == 0))
    return BeatGrid(period, best_phase)


def merge_attacks(notes: list[Note], max_gap: int = 2) -> list[Note]:
    """Junta en una sola nota los "gestos" hechos de notas cortísimas.

    Los drivers de NES adornan las notas cuadro por cuadro, y FamiStudio importa
    cada cuadro como una nota distinta:
      - un golpe de 1 cuadro (otro instrumento) y luego la nota sostenida
      - barridos de tono: una nota distinta en cada cuadro (bajando o subiendo)
      - arpegios rapidísimos (acordes "rotos" a 30 o 60 notas por segundo)
    Al oído cada uno es una sola nota que empieza en la primera. Regla: una nota
    de max_gap cuadros o menos se une con la que la sigue de inmediato. El grupo
    toma el tono de su nota más larga (la nota "de llegada").
    """
    groups: list[list[Note]] = []
    for note in notes:
        last = groups[-1][-1] if groups else None
        if last and last.duration <= max_gap and note.frame - last.frame <= max_gap:
            groups[-1].append(note)
        else:
            groups.append([note])
    merged = []
    for group in groups:
        first, last = group[0], group[-1]
        main = max(group, key=lambda n: n.duration)
        merged.append(Note(first.frame, main.pitch, last.frame + last.duration - first.frame))
    return merged


def reduce_notes(notes: list[Note], difficulty: Difficulty, grid: BeatGrid) -> list[Note]:
    """Quita notas hasta que ninguna quede a menos de min_gap cuadros de otra."""
    by_priority = sorted(notes, key=lambda n: (-grid.strength(n.frame), n.frame))
    kept: list[Note] = []
    for note in by_priority:
        if all(abs(note.frame - other.frame) >= difficulty.min_gap for other in kept):
            kept.append(note)
    return sorted(kept, key=lambda n: n.frame)


def assign_lanes(notes: list[Note], lanes: int, window: int = 4) -> list[int]:
    """Un carril (0..lanes-1) por nota, siguiendo la altura y el contorno."""
    result: list[int] = []
    for i, note in enumerate(notes):
        neighborhood = sorted({n.pitch for n in notes[max(0, i - window) : i + window + 1]})
        if len(neighborhood) == 1:
            lane = result[-1] if result else lanes // 2
        else:
            rank = neighborhood.index(note.pitch)
            lane = round(rank * (lanes - 1) / (len(neighborhood) - 1))

        if result:
            prev_lane, prev_pitch = result[-1], notes[i - 1].pitch
            if note.pitch == prev_pitch:
                lane = prev_lane
            elif note.pitch > prev_pitch and lane <= prev_lane:
                lane = min(prev_lane + 1, lanes - 1)
            elif note.pitch < prev_pitch and lane >= prev_lane:
                lane = max(prev_lane - 1, 0)
        result.append(lane)
    return result


@dataclass(frozen=True)
class ChartNote:
    row: int
    frame: int
    mask: int  # bits 0-4 = carriles, bit 7 = la fila tiene línea de beat


def frame_to_row(frame: int) -> int:
    return (frame + FRAMES_PER_ROW // 2) // FRAMES_PER_ROW


def build_chart(
    notes: list[Note], difficulty: Difficulty, grid: BeatGrid, lead_in: int, beat_rows: int, first_beat_row: int
) -> list[ChartNote]:
    reduced = reduce_notes(merge_attacks(notes), difficulty, grid)
    lanes = assign_lanes(reduced, difficulty.lanes)
    chart: list[ChartNote] = []
    for note, lane in zip(reduced, lanes):
        frame = lead_in + note.frame
        row = frame_to_row(frame)
        beat = 0x80 if (row - first_beat_row) % beat_rows == 0 else 0
        chart.append(ChartNote(row, frame, (1 << lane) | beat))
    rows = [n.row for n in chart]
    assert len(rows) == len(set(rows)), "Dos notas quedaron en la misma fila: sube min_gap"
    return chart


CHART_END = 0xFF  # carriles = $FF marca el fin del chart
MAX_DELTA = 255


def chart_entries(chart: list[ChartNote]) -> list[tuple[int, int]]:
    """El chart como lo lee el juego: pares (cuadros desde la entrada anterior, carriles).

    Si dos notas están a más de 255 cuadros, se intercalan entradas de relleno
    sin carriles (carriles = 0) que solo hacen avanzar el tiempo.
    """
    entries: list[tuple[int, int]] = []
    previous = 0
    for note in chart:
        delta = note.frame - previous
        while delta > MAX_DELTA:
            entries.append((MAX_DELTA, 0))
            delta -= MAX_DELTA
        entries.append((delta, note.mask))
        previous = note.frame
    entries.append((0, CHART_END))
    return entries


def chart_size(chart: list[ChartNote]) -> int:
    return 2 * len(chart_entries(chart))


def chart_to_asm(label: str, chart: list[ChartNote]) -> str:
    lines = [f"{label}:"]
    for delta, mask in chart_entries(chart):
        comment = "  ; fin" if mask == CHART_END else ""
        lines.append(f"    .byte {delta}, ${mask:02X}{comment}")
    return "\n".join(lines) + "\n"
