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
from urllib.parse import parse_qs, urlparse

from . import famistudio
from .chart import DIFFICULTIES, BeatGrid, ChartNote, build_chart, chart_size, chart_to_asm
from .m3u import find_playlist
from .player import player_payload
from .chartedit import (
    EDITS_FILE,
    apply_edits,
    chart_file_text,
    chart_from_json,
    chart_problems,
    diff_charts,
    load_edits,
    save_edits,
    validate_chart,
)

HTML_PATH = Path(__file__).with_name("editor.html")
HOME_PATH = Path(__file__).with_name("home.html")  # la página sin canción abierta
MENU_PATH = Path(__file__).with_name("menu.html")  # el menú Archivo, compartido por las dos
NESPLAYER_PATH = Path(__file__).with_name("nesplayer.js")  # el 6502 y el APU que tocan la canción


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
        "auto": {key: chart_json(chart) for key, chart in auto.items()},
        "problems": {key: chart_problems(chart, lanes_for(key)) for key, chart in charts.items()},
        "warnings": warnings,
        "chartBytes": sum(chart_size(chart) for chart in charts.values()),
        "editable": False,
    }


def lanes_for(key: str) -> int:
    """Carriles de la dificultad de un chart ("guitarra/facil" -> 3)."""
    difficulty = key.split("/")[1]
    return next(d.lanes for d in DIFFICULTIES if d.name == difficulty)


def save_edits_from_page(src: SongSource, charts: dict[str, list[ChartNote]]) -> dict[str, list[dict]]:
    """Guarda en edits.json lo que difiere de los charts automáticos. Falla si algún chart no se puede tocar."""
    auto = auto_charts(src)
    if set(charts) != set(auto):
        raise ValueError(f"faltan o sobran charts: se esperaban {sorted(auto)}")
    edits = {}
    for key, chart in charts.items():
        if key not in auto:
            raise ValueError(f"chart desconocido: {key}")
        validate_chart(key, chart)
        edits[key] = diff_charts(auto[key], chart)
    save_edits(src.song_dir, edits)
    return edits


def export_chart_s(src: SongSource, charts: dict[str, list[ChartNote]]) -> str:
    """Guarda las ediciones y reescribe chart.s con el mismo formato y orden que `import-song`."""
    from . import cli

    save_edits_from_page(src, charts)
    blocks = []
    for instrument, _ in cli.INSTRUMENTS:
        for difficulty in DIFFICULTIES:
            key = f"{instrument}/{difficulty.name}"
            if key in charts:
                blocks.append(chart_to_asm(f"chart_{src.name}_{instrument}_{difficulty.name}", charts[key]))
    source_name = Path(src.options["source"]).name
    cli.write_lf(src.song_dir / "chart.s", chart_file_text(source_name, blocks))
    return f"chart.s escrito ({sum(chart_size(c) for c in charts.values())} bytes de charts)"


def render_page(payload: dict, template: Path = HTML_PATH) -> str:
    data = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).replace("</", "<\\/")
    menu = MENU_PATH.read_text(encoding="utf-8")
    nesplayer = NESPLAYER_PATH.read_text(encoding="utf-8")
    return (template.read_text(encoding="utf-8").replace("__MENU__", menu, 1)
            .replace("__NESPLAYER__", nesplayer, 1).replace("__DATA__", data, 1))


# --- Menú Archivo: canciones disponibles, fuentes para importar y la canción abierta -----------

SOURCE_SUFFIXES = (".nsf", ".nsfe", ".fms", ".ftm")


class App:
    """La canción abierta (o ninguna) del servidor. Un candado evita que dos acciones se pisen."""

    def __init__(self, src: SongSource | None = None):
        self.src = src
        self.lock = threading.RLock()


def list_songs() -> list[dict]:
    from . import cli

    songs = []
    for options in sorted(cli.SONGS_DIR.glob("*/import.json")):
        meta = read_song_meta(options.parent)
        songs.append({
            "name": options.parent.name,
            "title": meta.get("title", options.parent.name),
            "game": meta.get("game", ""),
            "edited": (options.parent / EDITS_FILE).exists(),
        })
    return songs


def list_sources() -> list[dict]:
    """Archivos que se pueden importar como canción nueva: los de songs_src/ y las demos de FamiStudio."""
    from . import cli

    found = []
    for folder in (cli.ROOT / "songs_src", cli.ROOT / "tools" / "famistudio" / "Demo Songs"):
        for path in sorted(folder.glob("*")) if folder.is_dir() else []:
            if path.suffix.lower() in SOURCE_SUFFIXES:
                found.append({"path": path.relative_to(cli.ROOT).as_posix(), "name": path.stem})
    return found


def resolve_source(text: str) -> Path:
    from . import cli

    path = Path(text.strip().strip('"'))
    path = path if path.is_absolute() else cli.ROOT / path
    if path.suffix.lower() not in SOURCE_SUFFIXES or not path.is_file():
        raise ValueError(f"no encontré un archivo .nsf, .nsfe, .fms o .ftm en {path}")
    return path


def list_tracks(source: str) -> dict:
    """Las pistas del .m3u junto a un NSF (vacío si no hay)."""
    path = resolve_source(source)
    playlist = find_playlist(path) if path.suffix.lower() in (".nsf", ".nsfe") else None
    if not playlist:
        return {"game": None, "tracks": []}
    return {"game": playlist.game,
            "tracks": [{"number": t.number, "title": t.title, "seconds": t.seconds} for t in playlist.tracks.values()]}


def open_song(app: App, name: str) -> None:
    from . import cli

    if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or not (cli.SONGS_DIR / name / "import.json").exists():
        raise ValueError(f"no existe la canción {name}")
    try:
        app.src = load_song_source(name)
    except SystemExit as error:  # load_song_source avisa con sys.exit
        raise ValueError(str(error.code)) from None


def import_new_song(app: App, body: dict) -> str:
    """Importa una canción nueva (como `nesband import-song`), la abre y devuelve lo que imprimió el importador."""
    import argparse
    import contextlib
    import io

    from . import cli

    name = str(body.get("name", "")).strip()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
        raise ValueError("el identificador son minúsculas, números y _ (empezando con letra)")
    if (cli.SONGS_DIR / name).exists():
        raise ValueError(f"ya existe la canción {name}: ábrela, o elige otro identificador")
    source = resolve_source(str(body.get("source", "")))
    number = body.get("number")
    is_nsf = source.suffix.lower() in (".nsf", ".nsfe")
    has_playlist = is_nsf and find_playlist(source) is not None
    args = argparse.Namespace(
        source=source, name=name,
        track=number if has_playlist else None,                      # el .m3u cuenta desde 1
        song=0 if has_playlist or number is None else number - 1,    # el archivo, desde 0
        title=body.get("title") or None, game=body.get("game") or None,
        duration=body.get("duration") or None, beat_frames=body.get("beat_frames") or None,
    )
    log = io.StringIO()
    try:
        with contextlib.redirect_stdout(log):
            cli.import_song(args)
    except SystemExit as error:
        raise ValueError(str(error.code)) from None
    except (RuntimeError, FileNotFoundError) as error:
        raise ValueError(str(error)) from None
    open_song(app, name)
    return log.getvalue()


class Handler(BaseHTTPRequestHandler):
    app: App  # lo fija serve()

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
        url = urlparse(self.path)
        try:
            with self.app.lock:
                if url.path == "/":
                    if self.app.src is None:
                        page = render_page({"home": True}, HOME_PATH)
                    else:
                        page = render_page({**build_payload(self.app.src), "editable": True})
                    self._send(200, page.encode("utf-8"), "text/html; charset=utf-8")
                elif url.path == "/api/player":
                    if self.app.src is None:
                        raise ValueError("no hay canción abierta")
                    self._json(200, self._player(self.app.src))
                elif url.path == "/api/songs":
                    self._json(200, {"songs": list_songs()})
                elif url.path == "/api/sources":
                    self._json(200, {"sources": list_sources()})
                elif url.path == "/api/tracks":
                    self._json(200, list_tracks(parse_qs(url.query).get("source", [""])[0]))
                else:
                    self._send(404, b"no encontrado", "text/plain; charset=utf-8")
        except (ValueError, KeyError) as error:
            self._json(400, {"error": str(error)})

    @staticmethod
    def _player(src: SongSource) -> dict:
        """El motor de sonido del juego con la música de la canción (ver player.py)."""
        from . import cli

        try:
            return player_payload(cli.ROOT, src.name)
        except (RuntimeError, OSError) as error:
            raise ValueError(f"no pude armar el reproductor: {error}") from None

    def _json(self, status: int, data: dict) -> None:
        self._send(status, json.dumps(data).encode("utf-8"), "application/json")

    def do_POST(self) -> None:
        # Solo la propia página: otro origen (una web cualquiera) no puede escribir en el proyecto
        if self.headers.get("Origin") not in (None, f"http://{self.headers.get('Host')}"):
            self._json(403, {"error": "origen no permitido"})
            return
        app = self.app
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            with app.lock:
                if self.path == "/api/open":
                    open_song(app, str(body.get("name", "")))
                    self._json(200, {"message": f"abierta {app.src.name}"})
                elif self.path == "/api/close":
                    app.src = None
                    self._json(200, {"message": "cerrada"})
                elif self.path == "/api/import":
                    self._json(200, {"message": import_new_song(app, body)})
                elif self.path in ("/api/validate", "/api/save", "/api/export"):
                    src = app.src
                    if src is None or body.get("song") != src.name:
                        raise ValueError("la canción de esta página ya no es la abierta: recarga la página")
                    if self.path == "/api/validate":
                        chart = chart_from_json(body["chart"])
                        self._json(200, {"problems": chart_problems(chart, lanes_for(body["key"]))})
                    else:
                        charts = {key: chart_from_json(items) for key, items in body["charts"].items()}
                        if self.path == "/api/save":
                            edits = save_edits_from_page(src, charts)
                            count = sum(len(ops) for ops in edits.values())
                            self._json(200, {"message": f"edits.json guardado ({count} ediciones)"})
                        else:
                            self._json(200, {"message": export_chart_s(src, charts)})
                else:
                    self._json(404, {"error": "no encontrado"})
        except (ValueError, KeyError, TypeError) as error:
            self._json(400, {"error": str(error)})


def serve(name: str | None, port: int, open_browser: bool) -> None:
    app = App(load_song_source(name) if name else None)
    Bound = type("Bound", (Handler,), {"app": app})
    server = ThreadingHTTPServer(("127.0.0.1", port), Bound)
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    print(f"Editor de charts{f' de {name!r}' if name else ''}: {url}  (Ctrl+C para cerrar)")
    if open_browser:
        threading.Timer(0.3, webbrowser.open, args=(url,)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()
