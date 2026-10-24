"""Genera src/font.s: las letras del juego a partir de una fuente de 8x8 (y los símbolos propios del juego).

La fuente por defecto es Bongo-8 Mono (Caffinate / Nathan Scott, CC0: assets/fonts/). Para volver a
generarla hace falta Pillow, que el proyecto no usa en ningún otro lado:

    uv run --with pillow nesband build-font                          (Bongo-8, la de assets/fonts/)
    uv run --with pillow nesband build-font --ttf otra_fuente.ttf    (cualquier TTF de 8 px)

src/font.s se versiona ya generado, así que compilar la ROM no necesita Pillow ni Python.
"""

from __future__ import annotations

from pathlib import Path

# Los caracteres de la fuente del juego (ver FONT_CHARS en cli.py): su tile es su código ASCII
FONT_CHARS = " !%'()*,-./0123456789:<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ"
# Los que no salen de la fuente: son símbolos del juego (el cursor del menú y la estrella), no letras
GAME_SYMBOLS = {
    "*": ["...1....", "...1....", "1111111.", ".11111..", "..111...", ".11.11..", ".1...1..", "........"],
    "<": ["....11..", "...11...", "..11....", ".11.....", "..11....", "...11...", "....11..", "........"],
    ">": [".11.....", "..11....", "...11...", "....11..", "...11...", "..11....", ".11.....", "........"],
}
# Tiles que no son caracteres pero caen en números de la fuente que no usa ningún carácter ($22 y $23
# son '"' y '#'): la barra del bombo de la batería (color 3). Ver TILE_KICK en chr.s.
KICK_BAR = {
    0x22: ["........"] + ["33333333"] * 6 + ["........"],
    0x23: ["1......."] + ["13333333"] * 6 + ["1......."],
}
EMPTY = ["........"] * 8


def glyphs_from_ttf(path: Path, size: int = 8) -> dict[str, list[str]]:
    """Los glifos de FONT_CHARS de una TTF de píxeles, sin suavizado: 8 filas de 8 columnas ('1' = trazo)."""
    from PIL import Image, ImageDraw, ImageFont  # (solo aquí: ver el docstring)

    font = ImageFont.truetype(str(path), size)
    glyphs = {}
    for ch in FONT_CHARS:
        image = Image.new("L", (8, 8), 0)
        draw = ImageDraw.Draw(image)
        draw.fontmode = "1"
        draw.text((0, 0), ch, font=font, fill=255)
        glyphs[ch] = ["".join("1" if image.getpixel((x, y)) else "." for x in range(8)) for y in range(8)]
    return glyphs


def build_font_s(glyphs: dict[str, list[str]], source: str) -> str:
    """El texto de src/font.s: un TILE_AT y un TILE por carácter, en orden de número de tile."""
    tiles: dict[int, list[str]] = {0x20: EMPTY}
    for ch in FONT_CHARS:
        rows = GAME_SYMBOLS.get(ch) or glyphs.get(ch) or EMPTY
        if len(rows) != 8 or any(len(r) != 8 for r in rows):
            raise ValueError(f"el glifo de {ch!r} no es de 8x8")
        tiles[ord(ch)] = rows
    tiles.update(KICK_BAR)
    lines = [
        f"; Generado por `nesband build-font` desde {source} - no editar a mano",
        "; Un tile por carácter (su número es su código ASCII), en color 1; ver FONT_CHARS en cli.py.",
        "; Los símbolos del juego (* < >) y la barra del bombo ($22-$23) no salen de la fuente: ver fontgen.py.",
        "",
    ]
    for number in sorted(tiles):
        what = repr(chr(number)) if chr(number) in FONT_CHARS else "barra del bombo"
        lines.append(f"TILE_AT ${number:02X}   ; {what}")
        lines.append("TILE " + ", ".join(f'"{row}"' for row in tiles[number]))
    return "\n".join(lines) + "\n"
