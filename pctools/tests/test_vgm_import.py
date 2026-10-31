"""El VGM del NES se vuelve un proyecto de texto de FamiStudio antes de importarse (cli.vgm_project)."""

import struct

from bandcore.vgm import parse_vgm

from nesband_tools import cli


def nes_vgm(seconds: int, loop: bool) -> bytes:
    header = bytearray(0x100)
    header[0:4] = b"Vgm "
    struct.pack_into("<I", header, 0x08, 0x161)
    struct.pack_into("<I", header, 0x18, 44100)
    struct.pack_into("<I", header, 0x34, 0x100 - 0x34)
    struct.pack_into("<I", header, 0x84, 1789772)
    w = lambda reg, value: bytes([0xB4, reg - 0x4000, value])  # noqa: E731
    body = w(0x4015, 0x0F) + w(0x4000, 0xBC) + w(0x4002, 253) + w(0x4003, 0x08) + bytes([0x61]) + struct.pack("<H", 44100)
    if loop:
        struct.pack_into("<I", header, 0x1C, 0x100 - 0x1C)
        struct.pack_into("<I", header, 0x20, 44100)
    return bytes(header) + body + b"\x66"


def test_vgm_a_proyecto(tmp_path, monkeypatch):
    monkeypatch.setattr(cli, "WORK_DIR", tmp_path)
    path = cli.vgm_project(parse_vgm(nes_vgm(1, loop=False)), "prueba", 5, "Prueba")
    text = path.read_text(encoding="utf-8")
    assert path == tmp_path / "prueba_vgm" / "fuente.txt"
    assert text.startswith('Project Version="4.5.3"') and 'Name="Prueba"' in text
    assert 'Instrument Name="Pulso 1"' in text and 'Value="A4"' in text
    # Sin bucle dura lo que el VGM (1 s), aunque se pidan 5; con bucle, los 5
    song = text.split("\tSong ")[1]
    with_loop = cli.vgm_project(parse_vgm(nes_vgm(1, loop=True)), "prueba2", 5, "Prueba").read_text(encoding="utf-8")
    assert int(song.split('Length="')[1].split('"')[0]) < int(with_loop.split("\tSong ")[1].split('Length="')[1].split('"')[0])
