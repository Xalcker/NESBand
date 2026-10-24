"""Reproductor del editor: el motor de sonido real del juego, armado para una sola canción.

El editor toca la música ejecutando en JavaScript (nesplayer.js) el mismo código 6502 del motor de
FamiStudio que corre en el NES, con los mismos datos de la canción. Aquí se arma lo que necesita:
se ensambla src/audio.s (las mismas banderas del motor que el juego) junto con la ficha de la canción
y se enlaza con la misma disposición de memoria (player.cfg). El resultado son 24 KB: el slot de la
canción en $A000-$DFFF (música y samples DPCM) y el banco del motor en $E000-$FFFF.
"""

from __future__ import annotations

import base64
import re
import subprocess
from pathlib import Path

PACKAGE = Path(__file__).parent
ROUTINES = ("famistudio_init", "famistudio_music_play", "famistudio_music_stop", "famistudio_update")
IMAGE_START = 0xA000
IMAGE_SIZE = 0x6000


def find_tool(root: Path, name: str) -> str:
    """ca65/ld65 de tools/cc65 si existe; si no, el del PATH (como build.ps1)."""
    for exe in (f"{name}.exe", name):
        local = root / "tools" / "cc65" / "bin" / exe
        if local.exists():
            return str(local)
    return name


def sources(root: Path, name: str) -> list[Path]:
    """Todo lo que, si cambia, obliga a rearmar el reproductor."""
    song = root / "src" / "songs" / name
    return [
        *sorted(song.glob("*.s")), *sorted(song.glob("*.dmc")),
        root / "src" / "audio.s", *sorted((root / "src" / "audio").glob("*.s")),
        root / "src" / "famistudio" / "famistudio_ca65.s",
        PACKAGE / "player_stubs.s", PACKAGE / "player.cfg",
    ]


def build_player(root: Path, name: str, out_dir: Path) -> tuple[bytes, dict[str, int]]:
    """La imagen de 24 KB y las direcciones de las rutinas del motor. Se guarda en out_dir y se reusa
    mientras no cambie nada de lo que usa."""
    out_dir.mkdir(parents=True, exist_ok=True)
    binary, labels = out_dir / "player.bin", out_dir / "player.lbl"
    if not (binary.exists() and labels.exists() and all(
        binary.stat().st_mtime >= path.stat().st_mtime for path in sources(root, name) if path.exists()
    )):
        wrapper = out_dir / "player.s"
        wrapper.write_text(
            '.include "player_stubs.s"\n.include "audio.s"\n'
            f'SONG_SLOT_NUMBER .set 0\n.include "songs/{name}/song.s"\n', encoding="utf-8", newline="\n")
        obj = out_dir / "player.o"
        src = root / "src"
        run([find_tool(root, "ca65"), str(wrapper), "-I", str(src), "-I", str(PACKAGE),
             "--bin-include-dir", str(src), "--bin-include-dir", str(src / "famistudio"), "-o", str(obj)])
        run([find_tool(root, "ld65"), "-C", str(PACKAGE / "player.cfg"), str(obj), "-o", str(binary),
             "-Ln", str(labels)])
    image = binary.read_bytes()
    if len(image) != IMAGE_SIZE:
        raise RuntimeError(f"el reproductor mide {len(image)} bytes y debían ser {IMAGE_SIZE}")
    return image, read_labels(labels.read_text(encoding="utf-8"))


def run(command: list[str]) -> None:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{Path(command[0]).stem} falló:\n{result.stdout}{result.stderr}")


def read_labels(text: str) -> dict[str, int]:
    """Las direcciones de las rutinas del motor, del archivo de etiquetas de ld65 (-Ln)."""
    found = {m.group(2): int(m.group(1), 16) for m in re.finditer(r"^al ([0-9A-F]+) \.(\w+)$", text, re.MULTILINE)}
    missing = [r for r in ROUTINES if r not in found]
    if missing:
        raise RuntimeError(f"el reproductor no tiene las rutinas {missing}")
    return {r: found[r] for r in ROUTINES}


def player_payload(root: Path, name: str) -> dict:
    """Lo que el navegador necesita para tocar la canción: la imagen en base64 y las rutinas del motor."""
    image, routines = build_player(root, name, root / "build" / "player" / name)
    return {"image": base64.b64encode(image).decode("ascii"), "start": IMAGE_START, "routines": routines}
