from pathlib import Path

import pytest

from nesband_tools import fontgen

ROOT = Path(__file__).resolve().parents[2]

# Una 'A' propia (no de Fonts_MiSTer): el bit más alto de cada byte es la columna de la izquierda
LETTER_A = [0b00011000, 0b00100100, 0b01000010, 0b01111110, 0b01000010, 0b01000010, 0b11000011, 0b00000000]


def write_pf(path: Path, glyphs: dict[str, list[int]]) -> Path:
    data = bytearray(fontgen.PF_SIZE)
    for ch, rows in glyphs.items():
        start = (ord(ch) - 32) * 8
        data[start:start + 8] = bytes(rows)
    path.write_bytes(bytes(data))
    return path


def test_pf_rows_and_columns(tmp_path):
    glyphs = fontgen.glyphs_from(write_pf(tmp_path / "propia.pf", {"A": LETTER_A, "1": [0b10000000] * 8}))
    assert glyphs["A"][0] == "...11..."
    assert glyphs["A"][6] == "11....11"
    assert glyphs["1"] == ["1......."] * 8   # el bit 7 es la columna de la izquierda
    assert set(glyphs) == set(fontgen.FONT_CHARS)


def test_pf_keeps_game_symbols(tmp_path):
    # El * del .pf (todo lleno) no se usa: la estrella, el cursor y la barra del bombo son del juego
    pf = write_pf(tmp_path / "propia.pf", {"A": LETTER_A, "*": [0xFF] * 8})
    text = fontgen.build_font_s(fontgen.glyphs_from(pf), pf.name)
    star = '"' + '", "'.join(fontgen.GAME_SYMBOLS["*"]) + '"'
    assert f"TILE_AT $2A   ; '*'\nTILE {star}" in text
    assert "TILE_AT $41   ; 'A'\nTILE \"...11...\", \"..1..1..\"" in text
    assert "TILE_AT $23   ; barra del bombo" in text


def test_pf_wrong_size(tmp_path):
    pf = tmp_path / "corta.pf"
    pf.write_bytes(bytes(100))
    with pytest.raises(ValueError, match="768"):
        fontgen.glyphs_from(pf)


def test_unknown_extension(tmp_path):
    with pytest.raises(ValueError, match=r"\.pf"):
        fontgen.glyphs_from(tmp_path / "fuente.bdf")


def test_default_font_matches_src():
    # src/font.s es lo que genera Bongo-8 Mono (solo si Pillow está: `uv run --with pillow pytest`)
    pytest.importorskip("PIL")
    ttf = ROOT / "assets" / "fonts" / "Bongo-8_Mono.ttf"
    expected = fontgen.build_font_s(fontgen.glyphs_from(ttf), ttf.name)
    assert (ROOT / "src" / "font.s").read_text() == expected
