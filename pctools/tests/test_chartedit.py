import json
from pathlib import Path

import pytest
from nesband_tools import cli, editor
from nesband_tools.chart import (
    DIFFICULTIES,
    BeatGrid,
    ChartNote,
    chart_entries,
    chart_to_asm,
)
from nesband_tools.chartedit import (
    apply_edits,
    chart_file_text,
    chart_from_json,
    chart_problems,
    diff_charts,
    dump_edits,
    entries_to_chart,
    load_edits,
    parse_chart_asm,
    read_song_charts,
    save_edits,
    validate_chart,
)
from nesband_tools.famistudio import Note, Project, Song

SONGS = Path(__file__).resolve().parents[2] / "src" / "songs"

CHART = [
    ChartNote(128, 0b00100),
    ChartNote(168, 0b00001, star=True),
    ChartNote(208, 0b00011, end=260),  # acorde con cola
    ChartNote(300, 0b01000, end=330, star=True),
    ChartNote(700, 0b10000),  # a más de 255 cuadros: lleva entradas de relleno
]


def test_entries_round_trip():
    assert entries_to_chart(chart_entries(CHART)) == CHART


def test_asm_round_trip():
    asm = chart_to_asm("chart_x_guitarra_facil", CHART)
    parsed = parse_chart_asm(asm)
    assert list(parsed) == ["chart_x_guitarra_facil"]
    assert entries_to_chart(parsed["chart_x_guitarra_facil"]) == CHART


def test_two_sustains_ending_together():
    chart = [ChartNote(10, 0b00001, end=100), ChartNote(20, 0b01000, end=100)]
    assert entries_to_chart(chart_entries(chart)) == chart


def test_every_committed_chart_reads_and_rewrites_identically():
    """El chart.s de cada canción de git se lee y se vuelve a escribir byte por byte igual."""
    checked = 0
    for chart_s in sorted(SONGS.glob("*/chart.s")):
        for label, entries in parse_chart_asm(chart_s.read_text(encoding="utf-8")).items():
            assert chart_entries(entries_to_chart(entries, "_bateria_" in label)) == entries, f"{chart_s.parent.name}/{label}"
            checked += 1
    assert checked > 0


def test_read_song_charts_keys():
    charts = read_song_charts(SONGS / "tormenta")
    assert set(charts) >= {f"guitarra/{d.name}" for d in DIFFICULTIES}
    assert all(c for c in charts.values())


def test_apply_edits_add_delete_set():
    ops = [
        {"op": "delete", "frame": 128},
        {"op": "set", "frame": 168, "mask": 0b00010, "star": False},
        {"op": "set", "frame": 208, "end": None},
        {"op": "add", "frame": 150, "mask": 0b01000, "end": None, "star": False},
    ]
    result = apply_edits(CHART, ops)
    assert [n.frame for n in result] == [150, 168, 208, 300, 700]
    assert result[1] == ChartNote(168, 0b00010)
    assert result[2] == ChartNote(208, 0b00011)
    assert result[0] == ChartNote(150, 0b01000)


def test_apply_edits_warns_about_missing_notes():
    warnings = []
    result = apply_edits(CHART, [{"op": "delete", "frame": 999}, {"op": "set", "frame": 998, "mask": 1}], warnings.append)
    assert result == CHART
    assert len(warnings) == 2


def test_diff_is_inverse_of_apply():
    edited = [
        ChartNote(128, 0b00010),  # carril movido
        ChartNote(208, 0b00011),  # cola quitada
        ChartNote(250, 0b00100, star=True),  # agregada
        ChartNote(300, 0b01000, end=340, star=True),  # cola alargada
        ChartNote(700, 0b10000),
    ]
    ops = diff_charts(CHART, edited)
    assert {op["op"] for op in ops} == {"add", "delete", "set"}
    assert apply_edits(CHART, ops) == edited
    assert diff_charts(CHART, CHART) == []


def test_edits_file_round_trip(tmp_path):
    ops = diff_charts(CHART, [ChartNote(128, 0b00010)] + CHART[1:])
    save_edits(tmp_path, {"guitarra/facil": ops, "bajo/facil": []})
    text = (tmp_path / "edits.json").read_text(encoding="utf-8")
    assert json.loads(text)["charts"] == {"guitarra/facil": ops}  # los vacíos no se guardan
    assert "\r" not in text
    assert load_edits(tmp_path) == {"guitarra/facil": ops}
    assert dump_edits({}) == ""
    save_edits(tmp_path, {})
    assert not (tmp_path / "edits.json").exists()


def test_problems_blocked_pairs_and_sustain():
    assert not [p for p in chart_problems(CHART) if p["kind"] == "error"]
    chord = [ChartNote(10, 0b00101)]  # verde + amarillo: izquierda + derecha
    assert chart_problems(chord)[0]["kind"] == "error"
    clash = [ChartNote(10, 0b00001, end=100), ChartNote(50, 0b00001)]
    assert [p["frame"] for p in chart_problems(clash)] == [50]
    with pytest.raises(ValueError, match="guitarra/facil"):
        validate_chart("guitarra/facil", chord)
    validate_chart("guitarra/facil", CHART)


def test_problems_star_rules():
    chord_star = [ChartNote(10, 0b00011, star=True)]
    kinds = {p["text"] for p in chart_problems(chord_star)}
    assert any("acorde" in t for t in kinds)
    short_run = [ChartNote(f, 0b00001, star=True) for f in (10, 20)]
    assert any("frase estelar de 2" in p["text"] for p in chart_problems(short_run))
    run = [ChartNote(f, 0b00001, star=True) for f in (10, 20, 30, 40)]
    assert not chart_problems(run)


def test_chart_file_text_matches_committed_files():
    """Escribir lo que se leyó de un chart.s da el mismo archivo (así el export del editor no cambia nada)."""
    for chart_s in sorted(SONGS.glob("*/chart.s")):
        text = chart_s.read_text(encoding="utf-8")
        header = text.split("\n", 1)[0]
        source = header.split(" desde ")[1].removesuffix(" - no editar a mano")
        blocks = [chart_to_asm(label, entries_to_chart(entries, "_bateria_" in label)) for label, entries in parse_chart_asm(text).items()]
        assert chart_file_text(source, blocks) == text, chart_s.parent.name


def test_chart_from_json_checks_input():
    notes = chart_from_json([{"frame": 20, "mask": 2}, {"frame": 10, "mask": 1, "end": 30, "star": True}])
    assert notes == [ChartNote(10, 1, 30, True), ChartNote(20, 2)]
    for bad in ({"frame": -1, "mask": 1}, {"frame": 1, "mask": 64}, {"frame": 1.5, "mask": 1}):
        with pytest.raises(ValueError):
            chart_from_json([bad])
    with pytest.raises(ValueError):
        chart_from_json([{"frame": 5, "mask": 1}, {"frame": 5, "mask": 2}])


def test_lanes_allowed_warning():
    assert any("fuera de los 3" in p["text"] for p in chart_problems([ChartNote(10, 0b01000)], 3))
    assert not chart_problems([ChartNote(10, 0b00100)], 3)


def make_source(tmp_path):
    notes = [Note(i * 10, 60 + (i % 5), 8) for i in range(60)]
    song = Song("Prueba", {"BeatLength": "4", "NoteLength": "5"}, [300, 300], {"Square1": notes, "Square2": notes[::2]})
    return editor.SongSource("prueba", tmp_path, {}, song, BeatGrid(20, 0), False)


def test_payload_and_page(tmp_path):
    src = make_source(tmp_path)
    payload = editor.build_payload(src)
    assert payload["leadIn"] == cli.LEAD_IN
    assert payload["endFrame"] == cli.LEAD_IN + 600
    assert [i["name"] for i in payload["instruments"]] == ["guitarra", "teclado"]
    assert set(payload["charts"]) == {f"{i}/{d.name}" for i in ("guitarra", "teclado") for d in DIFFICULTIES}
    assert payload["channels"]["Triangle"] == []
    page = editor.render_page(payload)
    assert "__DATA__" not in page
    assert '"name":"prueba"' in page


def test_edits_change_payload_but_not_auto(tmp_path):
    src = make_source(tmp_path)
    auto = editor.auto_charts(src)
    first = auto["guitarra/facil"][0]
    save_edits(tmp_path, {"guitarra/facil": [{"op": "delete", "frame": first.frame}]})
    charts, warnings = editor.edited_charts(src, auto)
    assert not warnings
    assert len(charts["guitarra/facil"]) == len(auto["guitarra/facil"]) - 1
    assert charts["teclado/facil"] == auto["teclado/facil"]


def test_save_and_export_through_the_server(tmp_path):
    import threading
    import urllib.error
    import urllib.request

    from nesband_tools.chartedit import parse_chart_asm

    src = make_source(tmp_path)
    src.options = {"source": "audio/prueba.txt"}
    handler = type("Bound", (editor.Handler,), {"app": editor.App(src)})
    server = editor.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"

    def call(path, body=None):
        request = urllib.request.Request(base + path, json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.read()

    try:
        status, page = call("/")
        assert status == 200 and b'"editable":true' in page
        payload = editor.build_payload(src)
        charts = {k: v for k, v in payload["charts"].items()}

        # Mover la primera nota a otro carril y guardar
        first = charts["guitarra/facil"][0]
        first["mask"] = 0b00010 if first["mask"] != 0b00010 else 0b00001
        assert call("/api/save", {"song": "prueba", "charts": charts})[0] == 200
        edits = load_edits(tmp_path)
        assert set(edits) == {"guitarra/facil"} and edits["guitarra/facil"][0]["op"] == "set"

        # Exportar: el chart.s tiene todos los charts, con la edición
        status, _ = call("/api/export", {"song": "prueba", "charts": charts})
        assert status == 200
        exported = parse_chart_asm((tmp_path / "chart.s").read_text(encoding="utf-8"))
        assert len(exported) == len(charts)
        assert entries_to_chart(exported["chart_prueba_guitarra_facil"])[0].mask == first["mask"]

        # Un chart imposible o incompleto se rechaza y no toca los archivos
        before = (tmp_path / "edits.json").read_text(encoding="utf-8")
        bad = {k: list(v) for k, v in charts.items()}
        bad["guitarra/facil"] = [{"frame": 200, "mask": 0b00101, "end": None, "star": False}]
        assert call("/api/save", {"song": "prueba", "charts": bad})[0] == 400
        assert call("/api/export", {"song": "prueba", "charts": {}})[0] == 400
        assert (tmp_path / "edits.json").read_text(encoding="utf-8") == before

        status, body = call("/api/validate", {"song": "prueba", "key": "guitarra/facil", "chart": bad["guitarra/facil"]})
        assert status == 200 and json.loads(body)["problems"][0]["kind"] == "error"

        # Una página de otra canción (o sin canción abierta) no puede guardar encima
        assert call("/api/save", {"song": "otra", "charts": charts})[0] == 400
        assert call("/api/close", {})[0] == 200
        assert call("/api/save", {"song": "prueba", "charts": charts})[0] == 400
        status, page = call("/")
        assert status == 200 and b'"home":true' in page and b"Nueva canci" in page
    finally:
        server.shutdown()
        server.server_close()


def test_song_and_source_lists():
    songs = {s["name"]: s for s in editor.list_songs()}
    assert songs["tormenta"]["title"] == "TORMENTA DE NEON" and not songs["tormenta"]["edited"]
    assert all(s["path"].lower().endswith(editor.SOURCE_SUFFIXES) for s in editor.list_sources())


def test_import_rejects_bad_requests():
    app = editor.App()
    with pytest.raises(ValueError, match="identificador"):
        editor.import_new_song(app, {"name": "Mala Cancion", "source": "x.nsf"})
    with pytest.raises(ValueError, match="ya existe"):
        editor.import_new_song(app, {"name": "tormenta", "source": "x.nsf"})
    with pytest.raises(ValueError, match="no encontré"):
        editor.import_new_song(app, {"name": "nueva_cancion", "source": "no_existe.nsf"})
    with pytest.raises(ValueError, match="no encontré"):
        editor.import_new_song(app, {"name": "nueva_cancion", "source": "README.md"})
    with pytest.raises(ValueError, match="no existe"):
        editor.open_song(app, "../etc")
    assert app.src is None
