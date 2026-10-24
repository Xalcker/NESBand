"""Editor visual de charts: una página HTML local (Canvas, sin dependencias) servida por `nesband edit-chart`.

La página muestra las notas de cada canal de la canción y el chart de un instrumento y dificultad.
Los datos salen de la misma tubería que `import-song` (cli.py): las notas de FamiStudio, la rejilla
de tiempos y build_chart; encima se aplican las ediciones de edits.json (chartedit.py).
"""

from __future__ import annotations

import json
import re
import sys
import threading
import webbrowser
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import famistudio
from .chart import DIFFICULTIES, BeatGrid, ChartNote, build_chart
from .chartedit import apply_edits, chart_problems, load_edits

HTML_PATH = Path(__file__).with_name("editor.html")


@dataclass
class SongSource:
    name: str
    song_dir: Path
    options: dict
    song: famistudio.Song
    grid: BeatGrid
    is_nsf: bool


def load_song_source(name: str) -> SongSource:
    """Lee las notas de la canción `name` (de build/songs/<name>/song.txt, o de su fuente con FamiStudio)."""
    from . import cli  # (cli importa este módulo solo cuando se pide el editor, así que no hay ciclo)

    song_dir = cli.SONGS_DIR / name
    options_file = song_dir / "import.json"
    if not options_file.exists():
        sys.exit(f"{name} no tiene import.json: impórtala con import-song (o elige una de src/songs/)")
    options = json.loads(options_file.read_text(encoding="utf-8"))
    source = cli.ROOT / options["source"]
    is_nsf = source.suffix.lower() in (".nsf", ".nsfe")
    text_path = cli.WORK_DIR / name / "song.txt"
    if not text_path.exists() or (source.exists() and text_path.stat().st_mtime < source.stat().st_mtime):
        if is_nsf:
            sys.exit(f"Falta build/songs/{name}/song.txt (se crea al importar): corre `nesband reimport {name}` una vez")
        text_path.parent.mkdir(parents=True, exist_ok=True)
        fs = famistudio.find_famistudio(cli.ROOT)
        song_index = options["song"]
        duration = options["duration"] or 120
        famistudio.run(fs, [str(source), "famistudio-txt-export", str(text_path), *famistudio.import_options(source, song_index, duration)])
    project = famistudio.parse_text(text_path.read_text(encoding="utf-8"))
    song = project.songs[0] if len(project.songs) == 1 else project.songs[options["song"]]
    grid = cli.song_grid(song, options["beat_frames"], is_nsf)
    return SongSource(name, song_dir, options, song, grid, is_nsf)


def read_song_meta(song_dir: Path) -> dict[str, str]:
    """Título y juego de la canción, de la ficha song.s que ya generó el importador."""
    path = song_dir / "song.s"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    meta = {}
    for key in ("title", "game"):
        match = re.search(rf'^song_\w+_{key}:\s*\.byte\s+"([^"]*)"', text, re.MULTILINE)
        if match:
            meta[key] = match.group(1)
    return meta


def auto_charts(src: SongSource) -> dict[str, list[ChartNote]]:
    """Los charts que genera el importador, sin ediciones, por clave "instrumento/dificultad"."""
    from . import cli

    charts: dict[str, list[ChartNote]] = {}
    for instrument, channel in cli.INSTRUMENTS:
        notes = src.song.notes.get(channel, []) if channel else []
        if not notes:
            continue
        role, partner = cli.ROLE_OF[instrument]
        for difficulty in DIFFICULTIES:
            charts[f"{instrument}/{difficulty.name}"] = build_chart(
                notes, difficulty, src.grid, cli.LEAD_IN, role, src.song.notes.get(partner, [])
            )
    return charts


def edited_charts(src: SongSource, auto: dict[str, list[ChartNote]], edits: dict | None = None) -> tuple[dict, list[str]]:
    """Los charts automáticos con las ediciones de edits.json encima, y los avisos de lo que no se pudo aplicar."""
    edits = load_edits(src.song_dir) if edits is None else edits
    warnings: list[str] = []
    result = {}
    for key, chart in auto.items():
        warn = lambda text, key=key: warnings.append(f"{key}: {text}")  # noqa: E731
        result[key] = apply_edits(chart, edits[key], warn) if edits.get(key) else chart
    return result, warnings


def chart_json(chart: list[ChartNote]) -> list[dict]:
    return [{"frame": n.frame, "mask": n.mask, "end": n.end, "star": n.star} for n in chart]


def build_payload(src: SongSource) -> dict:
    """Todo lo que la página necesita, como JSON."""
    from . import cli

    lead_in = cli.LEAD_IN
    auto = auto_charts(src)
    charts, warnings = edited_charts(src, auto)
    meta = read_song_meta(src.song_dir)
    return {
        "name": src.name,
        "title": meta.get("title") or src.name,
        "game": meta.get("game") or "",
        "leadIn": lead_in,
        "endFrame": lead_in + src.song.length_frames,
        "framesPerBeat": src.grid.frames_per_beat,
        "firstBeat": lead_in + src.grid.first_beat,
        # [cuadro, altura, duración] por canal; los cuadros ya cuentan la entrada de la autopista
        "channels": {
            channel: [[lead_in + n.frame, n.pitch, n.duration] for n in src.song.notes.get(channel, [])]
            for channel in famistudio.CHANNEL_TYPES
        },
        "instruments": [{"name": name, "channel": channel} for name, channel in cli.INSTRUMENTS
                        if any(k.startswith(name + "/") for k in charts)],
        "difficulties": [{"name": d.name, "lanes": d.lanes} for d in DIFFICULTIES],
        "charts": {key: chart_json(chart) for key, chart in charts.items()},
        "problems": {key: chart_problems(chart) for key, chart in charts.items()},
        "warnings": warnings,
        "editable": False,
    }


def render_page(payload: dict) -> str:
    data = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).replace("</", "<\\/")
    return HTML_PATH.read_text(encoding="utf-8").replace("__DATA__", data, 1)


class Handler(BaseHTTPRequestHandler):
    src: SongSource  # lo fija serve()

    def log_message(self, format, *args):  # sin ruido en la terminal
        pass

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path.split("?")[0] == "/":
            page = render_page(build_payload(self.src))
            self._send(200, page.encode("utf-8"), "text/html; charset=utf-8")
        else:
            self._send(404, b"no encontrado", "text/plain; charset=utf-8")


def serve(name: str, port: int, open_browser: bool) -> None:
    src = load_song_source(name)

    class Bound(Handler):
        pass

    Bound.src = src
    server = ThreadingHTTPServer(("127.0.0.1", port), Bound)
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    print(f"Editor de charts de '{name}': {url}  (Ctrl+C para cerrar)")
    if open_browser:
        threading.Timer(0.3, webbrowser.open, args=(url,)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()
