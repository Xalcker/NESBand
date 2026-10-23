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


SUSTAIN_FLAG = 0x40  # en la entrada de una nota: tiene cola (su fin va en otra entrada)
END_FLAG = 0x80  # entrada de fin de cola: los bits 0-4 son los carriles que la sueltan
MIN_SUSTAIN = 16  # cuadros mínimos de cola (0.27 s); más corta no vale la pena mantenerla
SUSTAIN_TRIM = 4  # la cola termina un poco antes de que acabe la nota: soltar a tiempo no castiga
SUSTAIN_GAP = 3  # cuadros libres entre el fin de una cola y la siguiente nota del mismo carril


@dataclass(frozen=True)
class ChartNote:
    frame: int  # cuadro en que suena (contando la entrada de la autopista)
    mask: int  # bits 0-4 = carriles
    end: int | None = None  # cuadro en que termina su cola (None = nota normal)


def sustain_ends(notes: list[Note], lanes: list[int]) -> list[int | None]:
    """Fin de la cola de cada nota, o None si dura muy poco.

    La cola dura lo que la nota, pero termina antes de la siguiente nota del
    mismo carril (con SUSTAIN_GAP cuadros libres) para poder soltar y volver a tocar.
    """
    ends: list[int | None] = []
    for i, (note, lane) in enumerate(zip(notes, lanes)):
        limit = note.frame + note.duration
        for other, other_lane in zip(notes[i + 1 :], lanes[i + 1 :]):
            if other_lane == lane:
                limit = min(limit, other.frame - SUSTAIN_GAP)
                break
        length = limit - note.frame - SUSTAIN_TRIM
        ends.append(note.frame + length if length >= MIN_SUSTAIN else None)
    return ends


def build_chart(notes: list[Note], difficulty: Difficulty, grid: BeatGrid, lead_in: int) -> list[ChartNote]:
    """El chart guarda cuadros, no filas: así sirve para cualquier velocidad de
    la autopista (el juego calcula en qué fila se dibuja cada nota)."""
    reduced = reduce_notes(merge_attacks(notes), difficulty, grid)
    lanes = assign_lanes(reduced, difficulty.lanes)
    ends = sustain_ends(reduced, lanes)
    return [
        ChartNote(lead_in + note.frame, 1 << lane, None if end is None else lead_in + end)
        for note, lane, end in zip(reduced, lanes, ends)
    ]


CHART_END = 0xFF  # carriles = $FF marca el fin del chart
MAX_DELTA = 255


def chart_entries(chart: list[ChartNote]) -> list[tuple[int, int]]:
    """El chart como lo lee el juego: pares (cuadros desde la entrada anterior, carriles).

    Si dos entradas están a más de 255 cuadros, se intercalan entradas de relleno
    sin carriles (carriles = 0) que solo hacen avanzar el tiempo.

    Una nota con cola lleva SUSTAIN_FLAG, y su fin es otra entrada con END_FLAG y los
    carriles que se sueltan en ese cuadro (así el formato sigue siendo de 2 bytes).
    """
    events: list[tuple[int, int]] = []  # (cuadro, carriles)
    end_masks: dict[int, int] = {}
    for note in chart:
        if note.end is None:
            events.append((note.frame, note.mask))
        else:
            events.append((note.frame, note.mask | SUSTAIN_FLAG))
            end_masks[note.end] = end_masks.get(note.end, 0) | note.mask
    events += [(frame, END_FLAG | mask) for frame, mask in end_masks.items()]
    events.sort(key=lambda e: e[0])  # estable: a igual cuadro, las notas van antes que los fines

    entries: list[tuple[int, int]] = []
    previous = 0
    for frame, mask in events:
        delta = frame - previous
        while delta > MAX_DELTA:
            entries.append((MAX_DELTA, 0))
            delta -= MAX_DELTA
        entries.append((delta, mask))
        previous = frame
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
