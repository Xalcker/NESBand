"""Arte del escenario (issue #4): público, luces y torres, dibujados con código.

    uv run nesband build-scene       genera src/scene_art.s

Todo se dibuja pixel por pixel en lienzos pequeños con 4 colores (0-3) y luego se
corta en tiles de 8x8, como pide el NES. Los colores son los de la paleta 3 de
fondo (ver `palettes` en main.s):
    0 negro   1 gris (estructura)   2 azul (luz de fondo: cambia con las luces)   3 blanco

Lo que sale en src/scene_art.s:
  * SCENE_CHR_LOW: tiles fijos del escenario que caben en la mitad baja de la CHR ($5B-$7F)
  * SCENE_CHR_BANK n: un banco de 2 KB para el fondo ($80-$FF) con el público en su pose n
    (0 quieto, 1 brazos arriba, 2 saltando), más los tiles fijos que no cupieron arriba
  * scene_rows: las filas de la nametable de la autopista (3 filas se repiten cada 24 px)
  * scene_strip: las filas de la franja fija con el público
  * scene_phase_of_vrow: qué fila del dibujo repetido toca a cada fila de la nametable
"""

from __future__ import annotations

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src" / "scene_art.s"

PERIOD = 24  # alto del dibujo que se repite en el scroll (3 filas de tiles; 30 filas = 10 repeticiones)
SIDE_W = 88  # ancho de un costado (11 tiles; el lado izquierdo usa solo 10)
CROWD_ROWS = 5  # alto del público: filas 25-29 de la pantalla (la franja fija)
CROWD_COLS = 11
CROWD_H = CROWD_ROWS * 8
SCREEN_COLS = 32
VROWS = 30

# Números de tile
LOW_FIRST = 0x5B  # la fuente termina en la Z ($5A)
LOW_LAST = 0x7F
HIGH_STATIC = list(range(0x80, 0x90)) + list(range(0xA9, 0xC0))  # tiles fijos que no cupieron en la parte baja
CROWD_FIRST = 0xC0  # + fila * CROWD_COLS + columna
BLANK = 0x00
SPACE = 0x20  # el espacio de la fuente: lo que lleva la franja donde no hay nada

# Dónde va cada cosa en la pantalla (columnas de tiles). 1 jugador: la autopista ocupa 10-20.
LEFT_COLS = range(0, 10)
RIGHT_COLS = range(21, 32)
# 2 jugadores: autopistas en 2-12 y 20-30; el centro (13-19) y los bordes (0-1 y 31) quedan libres
CENTER_COLS = range(13, 20)
EDGE_COLS = (0, 1, 31)


class Canvas:
    """Un lienzo de pixeles con valores 0-3. Con wrap_y, lo que se sale por abajo reaparece arriba."""

    def __init__(self, w: int, h: int, wrap_y: bool = False):
        self.w, self.h, self.wrap_y = w, h, wrap_y
        self.px = [[0] * w for _ in range(h)]

    def set(self, x: int, y: int, c: int) -> None:
        if self.wrap_y:
            y %= self.h
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x: int, y: int) -> int:
        if self.wrap_y:
            y %= self.h
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return 0

    def rect(self, x0: int, y0: int, x1: int, y1: int, c: int) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def tile(self, col: int, row: int, flip: bool = False) -> tuple[str, ...]:
        """El tile de 8x8 de la columna y fila de tiles dadas, como 8 textos ('.' = color 0)."""
        rows = []
        for y in range(8):
            line = ""
            for x in range(8):
                xx = col * 8 + (7 - x if flip else x)
                c = self.get(xx, row * 8 + y)
                line += "." if c == 0 else str(c)
            rows.append(line)
        return tuple(rows)


BLANK_TILE = ("........",) * 8


# -----------------------------------------------------------------------------
# Escenario que se desplaza con la autopista (se repite cada PERIOD pixeles)
# -----------------------------------------------------------------------------
def draw_speaker(cv: Canvas, x0: int) -> None:
    """Bocina de 16 px de ancho y PERIOD de alto: marco, cono y tweeter."""
    for y in range(PERIOD):
        cv.set(x0, y, 1)
        cv.set(x0 + 15, y, 1)
    for x in range(16):
        cv.set(x0 + x, 0, 1)
    cx, cy = x0 + 7.5, 14.0  # cono grande
    for y in range(PERIOD):
        for x in range(16):
            d = math.hypot(x0 + x - cx, y - cy)
            if 5.2 <= d <= 6.6:
                cv.set(x0 + x, y, 1)
            elif d < 3.2:
                cv.set(x0 + x, y, 2)
            if d < 1.4:
                cv.set(x0 + x, y, 3)
    cx, cy = x0 + 7.5, 5.0  # tweeter
    for y in range(PERIOD):
        for x in range(16):
            d = math.hypot(x0 + x - cx, y - cy)
            if 1.6 <= d <= 2.8:
                cv.set(x0 + x, y, 1)
            elif d < 1.6:
                cv.set(x0 + x, y, 2)


def draw_truss(cv: Canvas, x0: int) -> None:
    """Torre de luces de 16 px: dos rieles y diagonales en X."""
    for y in range(PERIOD):
        for dx in (0, 1, 14, 15):
            cv.set(x0 + dx, y, 1)
        t = y % 12
        cv.set(x0 + 2 + t, y, 1)
        cv.set(x0 + 13 - t, y, 1)
    for x in range(16):  # travesaño cada 12 px
        cv.set(x0 + x, 0, 1)
        cv.set(x0 + x, 12, 1)


def draw_shaft(cv: Canvas, x0: int, width: int, edge: int) -> None:
    """Haz de luz vertical y continuo (no se corta con el período: con el scroll se ve fijo).

    Punteado denso al centro y ralo hacia las orillas, como luz difusa; la orilla del lado
    `edge` (+1 derecha, -1 izquierda; la que da a la autopista) lleva una línea sólida.
    """
    center = x0 + (width - 1) / 2
    half = width / 2
    for y in range(PERIOD):
        for x in range(x0, x0 + width):
            d = abs(x - center) / half
            if d < 0.38:
                lit = (x + y) % 4 != 3  # denso: 3 de cada 4
            elif d < 0.72:
                lit = (x + y) % 2 == 0  # medio: tablero
            else:
                lit = (x + 2 * y) % 4 == 0  # ralo: 1 de cada 4
            if lit:
                cv.set(x, y, 2)
        cv.set(x0 + (width - 1 if edge > 0 else 0), y, 2)


def draw_lamp(cv: Canvas, x0: int, direction: int) -> None:
    """Foco de 8x8 pegado a la torre (x0 = su borde izquierdo); su luz es el haz que se dibuja al lado.

    direction = +1: el foco mira a la derecha; -1: a la izquierda.
    """
    cv.rect(x0, 6, x0 + 7, 13, 0)  # el foco
    for x in range(8):
        cv.set(x0 + x, 6, 1)
        cv.set(x0 + x, 13, 1)
    for y in range(6, 14):
        cv.set(x0, y, 1)
        cv.set(x0 + 7, y, 1)
    bulb_x = x0 + (4 if direction > 0 else 1)
    cv.rect(bulb_x, 9, bulb_x + 2, 12, 3)


def side_canvas() -> Canvas:
    """El costado del escenario (visto desde el borde de la pantalla hacia la autopista)."""
    cv = Canvas(SIDE_W, PERIOD, wrap_y=True)
    draw_shaft(cv, 50, 16, +1)   # dos haces, uno ancho y otro angosto
    draw_shaft(cv, 68, 10, +1)
    draw_lamp(cv, 40, +1)
    draw_speaker(cv, 0)
    draw_truss(cv, 24)
    return cv


def center_canvas() -> Canvas:
    """El centro con 2 jugadores (7 tiles = 56 px): una torre con un foco a cada lado."""
    cv = Canvas(56, PERIOD, wrap_y=True)
    draw_shaft(cv, 12, 8, -1)    # un haz entre cada foco y la torre
    draw_shaft(cv, 36, 8, +1)
    draw_lamp(cv, 4, -1)
    draw_lamp(cv, 44, +1)
    draw_truss(cv, 20)
    return cv


# -----------------------------------------------------------------------------
# El público (franja fija, 5 filas de tiles): tres poses
# -----------------------------------------------------------------------------
FRONT = [8, 28, 48, 67, 85]  # centros de las personas de adelante
BACK = [18, 38, 58, 76]  # y de atrás (más chicas)


def person_mask(cx: float, head_y: float, scale: float, arms: tuple[int, int], arm_dx: float) -> set[tuple[int, int]]:
    """Silueta de una persona: cabeza, hombros y (si arms > 0) brazos levantados con la mano abierta."""
    m: set[tuple[int, int]] = set()
    hr = 4.4 * scale
    sh_y = head_y + hr + 8 * scale  # centro de los hombros: su borde de arriba toca la cabeza
    for y in range(int(head_y - hr) - 1, CROWD_H + 12):
        for x in range(int(cx - 16 * scale), int(cx + 16 * scale) + 1):
            if math.hypot(x - cx, y - head_y) <= hr:
                m.add((x, y))
            elif ((x - cx) / (11.5 * scale)) ** 2 + ((y - sh_y) / (8.5 * scale)) ** 2 <= 1.0:
                m.add((x, y))
            elif y >= sh_y and abs(x - cx) <= 11 * scale:  # el torso, hacia abajo
                m.add((x, y))
            elif head_y + hr <= y < sh_y and abs(x - cx) <= 2.4 * scale:  # el cuello
                m.add((x, y))
    for side, length in zip((-1, 1), arms):
        if length <= 0:
            continue
        x_start = cx + side * 9 * scale
        y_start = sh_y - 3 * scale
        x_end = x_start + side * arm_dx
        y_end = y_start - length
        steps = max(int(abs(y_end - y_start)) * 2, 1)
        for i in range(steps + 1):
            t = i / steps
            x = x_start + (x_end - x_start) * t
            y = y_start + (y_end - y_start) * t
            for dx in (0, 1, 2):
                m.add((int(x) + dx, int(y)))
        for dx in (-1, 0, 1, 2, 3):  # la mano
            for dy in (-3, -2, -1, 0):
                m.add((int(x_end) + dx, int(y_end) + dy))
    return m


def crowd_canvas(pose: int) -> Canvas:
    """El público en una pose: 0 quieto, 1 con brazos arriba, 2 saltando."""
    w = CROWD_COLS * 8
    cv = Canvas(w, CROWD_H)
    for y in range(CROWD_H):  # la luz de fondo: sube desde las cabezas, con una orilla punteada
        for x in range(w):
            if y >= 8 or (y >= 4 and (x + y) % 2 == 0):
                cv.set(x, y, 2)
    lift = 3 if pose == 2 else 0
    # Los de atrás sin borde (siluetas oscuras sobre la luz: dan profundidad); los de adelante con borde gris
    for row, (xs, scale, head_y, outline) in enumerate(((BACK, 0.8, 16.0, 2), (FRONT, 1.0, 24.0, 1))):
        for i, cx in enumerate(xs):
            if pose == 0:
                arms = (0, 0)
            elif pose == 1:  # alternan los brazos; las de atrás levantan menos
                arms = ((22, 0), (0, 24), (21, 21), (0, 23), (24, 0))[i % 5] if row else ((11, 0), (0, 12), (11, 11), (0, 10))[i % 4]
            else:
                arms = (25 + i % 3 * 2, 25 + (i + 1) % 3 * 2) if row else (13, 13)
            arm_dx = 3 if pose == 1 else 4
            jump = lift + (i % 2) if pose == 2 else 0
            height = (0, 2, -1, 1, 0)[(i + row * 2) % 5]  # cada quien con su estatura
            mask = person_mask(cx, head_y - jump + height, scale, arms, arm_dx)
            border = set()
            for (x, y) in mask:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if (x + dx, y + dy) not in mask:
                        border.add((x + dx, y + dy))
            for (x, y) in border:
                cv.set(x, y, outline)
            for (x, y) in mask:
                cv.set(x, y, 0)
    return cv


# -----------------------------------------------------------------------------
# Reparto de tiles
# -----------------------------------------------------------------------------
class TilePool:
    """Reparte números de tile fijos (iguales en todos los cuadros) sin repetir dibujos."""

    def __init__(self) -> None:
        self.free = list(range(LOW_FIRST, LOW_LAST + 1)) + HIGH_STATIC
        self.by_content: dict[tuple[str, ...], int] = {}

    def id_of(self, tile: tuple[str, ...]) -> int:
        if tile == BLANK_TILE:
            return BLANK
        if tile not in self.by_content:
            if not self.free:
                raise SystemExit("El escenario ya no cabe: faltan tiles libres en la CHR")
            self.by_content[tile] = self.free.pop(0)
        return self.by_content[tile]


def build() -> str:
    pool = TilePool()
    side = side_canvas()
    center = center_canvas()

    # scene_rows: [1 jugador, 2 jugadores][fase 0-2][32 columnas]
    rows: list[list[int]] = []
    for layout in (1, 2):
        for phase in range(PERIOD // 8):
            line = [BLANK] * SCREEN_COLS
            if layout == 1:
                for col in LEFT_COLS:
                    line[col] = pool.id_of(side.tile(col, phase))
                for col in RIGHT_COLS:  # el costado derecho es el izquierdo en espejo
                    line[col] = pool.id_of(side.tile(31 - col, phase, flip=True))
            else:
                for i, col in enumerate(CENTER_COLS):
                    line[col] = pool.id_of(center.tile(i, phase))
            rows.append(line)

    # scene_strip: filas 25-29 de la franja fija. Cada celda del público tiene su número de tile
    # (el mismo en las tres poses: lo que cambia es el banco de la CHR)
    def crowd_id(r: int, c: int) -> int:
        return CROWD_FIRST + r * CROWD_COLS + c

    strip: list[list[int]] = []
    for layout in (1, 2):
        for r in range(CROWD_ROWS):
            line = [SPACE] * SCREEN_COLS
            if layout == 1:
                for c, col in enumerate(LEFT_COLS):
                    line[col] = crowd_id(r, c)
                for c, col in enumerate(RIGHT_COLS):
                    line[col] = crowd_id(r, c)
            else:
                for c, col in enumerate(CENTER_COLS):
                    line[col] = crowd_id(r, c)
                for c, col in zip((8, 9, 10), EDGE_COLS):
                    line[col] = crowd_id(r, c)
            strip.append(line)

    out: list[str] = []
    w = out.append
    w("; =============================================================================")
    w("; scene_art.s - GENERADO por `uv run nesband build-scene` (pctools/nesband_tools/scene.py)")
    w("; No lo edites a mano: cambia el script y vuelve a generarlo.")
    w("; =============================================================================")
    w("")
    w('.segment "RODATA"')
    w("")
    w("; Qué fila (0-2) del dibujo repetido toca a cada fila de la nametable de la autopista")
    w("scene_phase_of_vrow:")
    w("    .byte " + ", ".join(str(v % (PERIOD // 8)) for v in range(VROWS)))
    w("")
    w("; Las 32 columnas de cada fila de la autopista: [1 jugador: fases 0-2][2 jugadores: fases 0-2]")
    w("scene_rows:")
    for line in rows:
        w("    .byte " + ", ".join(f"${v:02X}" for v in line))
    w("")
    w("; Las filas 25-29 de la franja fija: [1 jugador: 5 filas][2 jugadores: 5 filas]")
    w("scene_strip:")
    for line in strip:
        w("    .byte " + ", ".join(f"${v:02X}" for v in line))
    w("")

    def emit_tiles(ids: list[int], org: str = "") -> None:
        by_id = {i: t for t, i in pool.by_content.items()}
        for i in sorted(ids):
            w(f"    TILE_AT ${i:02X}{org}")
            w("    TILE " + ", ".join(f'"{r}"' for r in by_id[i]))

    low = [i for i in pool.by_content.values() if i <= LOW_LAST]
    high_lo = [i for i in pool.by_content.values() if 0x80 <= i < 0x90]
    high_hi = [i for i in pool.by_content.values() if i >= 0xA9]

    w("; Tiles fijos de la mitad baja de la CHR (entran en el banco base)")
    w(".macro SCENE_CHR_LOW")
    emit_tiles(low)
    w(".endmacro")
    w("")
    w("; Un banco de 2 KB para $0800-$0FFF del fondo: los tiles que el juego usa ahí (BG_STAR_TILES),")
    w("; los fijos que no cupieron arriba y el público en la pose `pose`. `org` es el origen de TILE_AT")
    w("; (ver chr.s): la dirección del banco menos 128 tiles")
    w(".macro SCENE_CHR_BANK pose, org")
    emit_tiles(high_lo, ", org")
    w("    BG_STAR_TILES org")
    emit_tiles(high_hi, ", org")
    for pose in range(3):
        w(f"    .if pose = {pose}")
        cv = crowd_canvas(pose)
        for r in range(CROWD_ROWS):
            for c in range(CROWD_COLS):
                t = cv.tile(c, r)
                if t != BLANK_TILE:
                    w(f"        TILE_AT ${crowd_id(r, c):02X}, org")
                    w("        TILE " + ", ".join(f'"{x}"' for x in t))
        w("    .endif")
    w("    TILE_AT $100, org")
    w(".endmacro")
    w("")
    return "\n".join(out)


def preview() -> None:
    """Dibuja el escenario como texto (para mirarlo sin compilar): el costado y las tres poses."""
    shades = " ░▒█"
    print("--- costado (se repite hacia abajo) ---")
    side = side_canvas()
    for y in range(PERIOD):
        print("".join(shades[side.get(x, y)] for x in range(SIDE_W)))
    for pose in range(3):
        print(f"--- público, pose {pose} ---")
        cv = crowd_canvas(pose)
        for y in range(CROWD_H):
            print("".join(shades[cv.get(x, y)] for x in range(CROWD_COLS * 8)))


def main() -> None:
    OUT.write_text(build() + "\n", encoding="utf-8", newline="\n")
    print(f"Listo: {OUT}")


if __name__ == "__main__":
    main()
