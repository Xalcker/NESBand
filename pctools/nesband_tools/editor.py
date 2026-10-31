"""Editor visual de charts: una página HTML local (Canvas, sin dependencias) servida por `nesband edit-chart`.

La página muestra las notas de cada canal de la canción y el chart de un instrumento y dificultad.
Los datos salen de la misma tubería que `import-song` (cli.py): las notas de FamiStudio, la rejilla
de tiempos y build_chart; encima se aplican las ediciones de edits.json (chartedit.py).
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from http.server import ThreadingHTTPServer  # noqa: F401  (las pruebas arman el servidor con él)
from pathlib import Path

from bandcore import editor as bandeditor
from bandcore.editor import server as bandserver

from . import famistudio
from .chart import DIFFICULTIES, BeatGrid, ChartNote, build_chart, chart_size, chart_to_asm
from .drums import (
    ROLE_LABELS,
    ROLE_LANE,
    ROLES,
    build_drum_chart,
    check_assignment,
    drum_groups,
    drum_hits,
    load_drums,
    save_drums,
    suggest_assignment,
)
from .m3u import find_playlist
from .player import player_payload
from .chartedit import (
    EDITS_FILE,
    apply_edits,
    chart_file_text,
    chart_problems,
    diff_charts,
    load_edits,
    save_edits,
    validate_chart,
)

# Las páginas (editor.html, home.html y el menú Archivo) son las de bandcore, compartidas con GBBand, GENBand y
# NGBand; aquí van el perfil del NES y su reproductor
HTML_PATH = bandeditor.EDITOR_HTML
HOME_PATH = bandeditor.HOME_HTML  # la página sin canción abierta
NESPLAYER_PATH = Path(__file__).with_name("nesplayer.js")  # el 6502 y el APU que tocan la canción

PROFILE = {
    "game": "NESBand",
    "cli": "nesband",
    "pads": ["←", "↓", "→", "B", "A"],
    "channels": [
        {"id": "Square1", "label": "Square 1", "color": "#58d0ff", "discrete": False},
        {"id": "Square2", "label": "Square 2", "color": "#b58cff", "discrete": False},
        {"id": "Triangle", "label": "Triángulo", "color": "#6be88a", "discrete": False},
        {"id": "Noise", "label": "Ruido", "color": "#ffb45e", "discrete": True},
        {"id": "DPCM", "label": "DPCM", "color": "#ff7a9c", "discrete": True},
    ],
    "drumInstrument": True,
    "exportLabel": "Exportar chart.s",
    "exportTitle": "Guarda y reescribe chart.s con el formato de siempre",
    "playerTitle": "Toca la canción con el motor de sonido del juego",
    "import": {
        "label": "Archivo a importar (NSF, FamiStudio o FamiTracker)",
        "placeholder": "C:\\ruta\\cancion.nsf o songs_src\\cancion.nsf",
        "hint": "Importar usa FamiStudio y genera música, charts y ficha en "
                "<code>src/songs/&lt;identificador&gt;/</code>. Puede tardar un poco.",
        "status": "Importando con FamiStudio…",
        "tracks": True,
        "durationLabel": "Segundos a grabar (NSF)",
        "durationPlaceholder": "del .m3u, o 120",
        "durationPattern": r"\.nsfe?$",
    },
}
# nesplayer.js corre el motor de sonido del juego (el servidor lo ensambla con la música) desde el inicio de la canción
_PLAYER_ADAPTER = """
window.BandPlayer = {
  FPS: NesPlayer.CPU_HZ / NesPlayer.FRAME_CYCLES,
  render: (player, data, opts) => NesPlayer.render(player, data.endFrame - data.leadIn, { ...opts, stems: true }),
};
"""


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


def drum_assignment(src: SongSource, override: dict | None = None) -> tuple[dict, bool]:
    """La asignación de papeles de la batería: la que manda la página, la de drums.json o, si no hay,
    la sugerida. Devuelve (asignación, ¿es solo una sugerencia sin guardar?)."""
    if override is not None:
        check_assignment(override)
        return override, False
    saved = load_drums(src.song_dir)
    if saved is not None:
        return saved, False
    return suggest_assignment(drum_groups(src.song)), True


def auto_charts(src: SongSource, assignment: dict | None = None) -> dict[str, list[ChartNote]]:
    """Los charts que genera el importador, sin ediciones, por clave "instrumento/dificultad".
    La batería sale de la asignación de papeles (ver drums.py) y solo existe si algún grupo tiene papel."""
    from . import cli

    charts: dict[str, list[ChartNote]] = {}
    hits = drum_hits(src.song, drum_assignment(src, assignment)[0])
    if hits:
        for difficulty in DIFFICULTIES:
            charts[f"bateria/{difficulty.name}"] = build_drum_chart(hits, difficulty.name, src.grid, cli.LEAD_IN)
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
    return [{"frame": n.frame, "mask": n.mask, "end": n.end, "star": n.star, "cymbal": n.cymbal} for n in chart]


def build_payload(src: SongSource) -> dict:
    """Todo lo que la página necesita, como JSON."""
    from . import cli

    lead_in = cli.LEAD_IN
    assignment, suggested = drum_assignment(src)
    auto = auto_charts(src, assignment)
    charts, warnings = edited_charts(src, auto)
    meta = read_song_meta(src.song_dir)
    return {
        "drums": {
            "groups": [{"key": g.key, "channel": g.channel, "tone": g.tone, "instrument": g.instrument,
                        "count": g.count, "avgDuration": round(g.avg_duration, 1)}
                       for g in drum_groups(src.song)],
            "assignment": assignment,
            "suggested": suggested,
            "roles": [{"id": role, "label": ROLE_LABELS[role], "lane": ROLE_LANE[role]} for role in ROLES],
        },
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
        "problems": {key: problems_for(key, chart) for key, chart in charts.items()},
        "warnings": warnings,
        "chartBytes": sum(chart_size(chart) for chart in charts.values()),
        "editable": False,
    }


def lanes_for(key: str) -> int:
    """Carriles de la dificultad de un chart ("guitarra/facil" -> 3)."""
    difficulty = key.split("/")[1]
    return next(d.lanes for d in DIFFICULTIES if d.name == difficulty)


def problems_for(key: str, chart: list[ChartNote]) -> list[dict]:
    return chart_problems(chart, lanes_for(key), key.startswith("bateria/"))


def save_edits_from_page(src: SongSource, charts: dict[str, list[ChartNote]],
                         assignment: dict | None = None) -> dict[str, list[dict]]:
    """Guarda en edits.json lo que difiere de los charts automáticos (y en drums.json la asignación de la
    batería, si la manda la página). Falla si algún chart no se puede tocar."""
    auto = auto_charts(src, assignment)
    if set(charts) != set(auto):
        raise ValueError(f"faltan o sobran charts: se esperaban {sorted(auto)}")
    edits = {}
    for key, chart in charts.items():
        if key not in auto:
            raise ValueError(f"chart desconocido: {key}")
        validate_chart(key, chart)
        edits[key] = diff_charts(auto[key], chart)
    if assignment is None and load_drums(src.song_dir) is None and any(
            ops for key, ops in edits.items() if key.startswith("bateria/")):
        assignment = drum_assignment(src)[0]   # las ediciones de la batería van atadas a la asignación con que se hicieron
    if assignment is not None:
        save_drums(src.song_dir, assignment)
    save_edits(src.song_dir, edits)
    return edits


def export_chart_s(src: SongSource, charts: dict[str, list[ChartNote]], assignment: dict | None = None) -> str:
    """Guarda las ediciones y reescribe chart.s con el mismo formato y orden que `import-song`. Si la
    canción tiene (o deja de tener) chart de batería, también ajusta su ficha song.s (ver patch_song_s)."""
    from . import cli

    save_edits_from_page(src, charts, assignment)
    blocks = []
    for instrument, _ in cli.INSTRUMENTS:
        for difficulty in DIFFICULTIES:
            key = f"{instrument}/{difficulty.name}"
            if key in charts:
                blocks.append(chart_to_asm(f"chart_{src.name}_{instrument}_{difficulty.name}", charts[key]))
    source_name = Path(src.options["source"]).name
    cli.write_lf(src.song_dir / "chart.s", chart_file_text(source_name, blocks))
    song_s = src.song_dir / "song.s"
    if song_s.exists():
        patched = patch_song_s(song_s.read_text(encoding="utf-8"), src.name, any(k.startswith("bateria/") for k in charts))
        cli.write_lf(song_s, patched)
    return f"chart.s escrito ({sum(chart_size(c) for c in charts.values())} bytes de charts)"


def patch_song_s(text: str, name: str, drums: bool) -> str:
    """La ficha song.s con o sin batería: el bit 3 de los instrumentos con chart y su renglón de charts.
    (Es lo único de la ficha que depende de la batería; lo demás lo deja `import-song`.)"""
    mask = re.search(r"^(    \.byte %)([01]{8})(\s*; instrumentos con chart)", text, re.MULTILINE)
    row = re.search(r"^    \.addr .*; bateria$", text, re.MULTILINE)
    if not mask or not row:
        raise ValueError("song.s no tiene el formato de import-song: corre `nesband reimport` para regenerarla")
    bits = int(mask.group(2), 2)
    bits = bits | 0b1000 if drums else bits & ~0b1000
    labels = ", ".join(f"chart_{name}_bateria_{d.name}" for d in DIFFICULTIES) if drums else ", ".join("0" for _ in DIFFICULTIES)
    text = text[:mask.start(2)] + f"{bits:08b}" + text[mask.end(2):]
    row = re.search(r"^    \.addr .*; bateria$", text, re.MULTILINE)
    return text[:row.start()] + f"    .addr {labels}  ; bateria" + text[row.end():]


def render_page(payload: dict, template: Path = HTML_PATH) -> str:
    """La página del editor de bandcore con el perfil del NES. Escuchar existe cuando la página es editable."""
    payload = {"player": bool(payload.get("editable")), **payload}
    player = NESPLAYER_PATH.read_text(encoding="utf-8") + _PLAYER_ADAPTER
    return bandeditor.render_page(payload, PROFILE, player, template)


# --- Menú Archivo: canciones disponibles, fuentes para importar y la canción abierta -----------

SOURCE_SUFFIXES = (".nsf", ".nsfe", ".fms", ".ftm")


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


def load_named_song(name: str) -> SongSource:
    from . import cli

    if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or not (cli.SONGS_DIR / name / "import.json").exists():
        raise ValueError(f"no existe la canción {name}")
    try:
        return load_song_source(name)
    except SystemExit as error:  # load_song_source avisa con sys.exit
        raise ValueError(str(error.code)) from None


def import_source(body: dict) -> tuple[SongSource, str]:
    """Importa una canción nueva (como `nesband import-song`): la canción ya cargada y lo que imprimió el importador."""
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
    return load_named_song(name), log.getvalue()


# --- Servidor: el de bandcore, con lo propio del NES -------------------------------------------------------

class Game(bandserver.EditorGame):
    profile = PROFILE

    def player_js(self) -> str:
        return NESPLAYER_PATH.read_text(encoding="utf-8") + _PLAYER_ADAPTER

    def open(self, name: str) -> SongSource:
        return load_named_song(name)

    def payload(self, src: SongSource) -> dict:
        return build_payload(src)

    def player(self, src: SongSource) -> dict:
        """El motor de sonido del juego con la música de la canción (ver player.py)."""
        from . import cli

        try:
            return player_payload(cli.ROOT, src.name)
        except (RuntimeError, OSError) as error:
            raise ValueError(f"no pude armar el reproductor: {error}") from None

    def problems(self, key: str, chart: list[ChartNote]) -> list[dict]:
        return problems_for(key, chart)

    def drums(self, src: SongSource, assignment: dict) -> dict:
        # Otra asignación: los charts de batería se rehacen (con las ediciones ya guardadas encima)
        assignment, _ = drum_assignment(src, assignment)
        auto = auto_charts(src, assignment)
        charts, warnings = edited_charts(src, auto)
        return {
            "charts": {k: chart_json(c) for k, c in charts.items() if k.startswith("bateria/")},
            "auto": {k: chart_json(c) for k, c in auto.items() if k.startswith("bateria/")},
            "problems": {k: problems_for(k, c) for k, c in charts.items() if k.startswith("bateria/")},
            "warnings": warnings,
        }

    def save(self, src: SongSource, charts: dict, assignment: dict | None) -> dict:
        return save_edits_from_page(src, charts, assignment)

    def export(self, src: SongSource, charts: dict, assignment: dict | None) -> tuple[str, SongSource]:
        return export_chart_s(src, charts, assignment), src

    def songs(self) -> list[dict]:
        return list_songs()

    def sources(self) -> list[dict]:
        return list_sources()

    def tracks(self, source: str) -> dict:
        return list_tracks(source)

    def import_song(self, body: dict) -> tuple[SongSource, str]:
        return import_source(body)


GAME = Game()
Handler = bandserver.Handler


class App(bandserver.App):
    """La canción abierta (o ninguna) del servidor; `src` es la canción (`song` en bandcore)."""

    def __init__(self, src: SongSource | None = None):
        super().__init__(GAME, src)

    @property
    def src(self) -> SongSource | None:
        return self.song

    @src.setter
    def src(self, value: SongSource | None) -> None:
        self.song = value


def open_song(app: App, name: str) -> None:
    app.song = GAME.open(name)


def import_new_song(app: App, body: dict) -> str:
    """Importa una canción nueva (como `nesband import-song`), la abre y devuelve lo que imprimió el importador."""
    app.song, log = GAME.import_song(body)
    return log


def serve(name: str | None, port: int, open_browser: bool) -> None:
    bandserver.serve(App(load_song_source(name) if name else None), port, open_browser)
