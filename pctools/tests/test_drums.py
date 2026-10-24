import json
import threading
import urllib.request

import pytest
from nesband_tools import editor
from nesband_tools.chart import (
    DRUM_BLOCKED_PAIRS,
    BeatGrid,
    ChartNote,
    chart_entries,
    check_playable,
)
from nesband_tools.chartedit import (
    apply_edits,
    chart_problems,
    diff_charts,
    entries_to_chart,
    load_edits,
    validate_chart,
)
from nesband_tools.drums import (
    ROLE_LANE,
    Hit,
    build_drum_chart,
    drum_groups,
    load_drums,
    save_drums,
    suggest_assignment,
)
from nesband_tools.famistudio import Note, Song, parse_text

GRID = BeatGrid(20, 0)
KICK, SNARE, TOM1, TOM2, TOM3 = (1 << ROLE_LANE[r] for r in ("kick", "snare", "tom1", "tom2", "tom3"))


def drum_song():
    """Una canción de prueba: bombo y tarola en DPCM, hi-hat y un golpe raro en ruido."""
    notes = {
        "DPCM": [Note(f, 36, 4, None, "Bombo") for f in range(0, 400, 40)]
        + [Note(f, 38, 4, None, "Tarola") for f in range(20, 400, 40)],
        "Noise": [Note(f, 60, 2, None, "Hi-hat") for f in range(0, 400, 10)] + [Note(5, 50, 2, None, "Raro")],
    }
    return Song("Prueba", {"BeatLength": "4", "NoteLength": "5"}, [400], notes)


def test_instrument_name_is_parsed():
    text = ('Project TempoMode="FamiStudio"\n\tSong Name="S" Length="1" PatternLength="4" BeatLength="4" NoteLength="5"\n'
            '\t\tChannel Type="Noise"\n\t\t\tPattern Name="A"\n'
            '\t\t\t\tNote Time="0" Value="G3" Duration="2" Instrument="Platillo"\n'
            '\t\t\tPatternInstance Time="0" Pattern="A"\n')
    note = parse_text(text).songs[0].notes["Noise"][0]
    assert note.instrument == "Platillo" and note.pitch == 55


def test_groups_and_suggestion_use_names_then_pitch():
    groups = drum_groups(drum_song())
    assert [(g.channel, g.instrument, g.count) for g in groups] == [
        ("Noise", "Raro", 1), ("Noise", "Hi-hat", 40), ("DPCM", "Bombo", 10), ("DPCM", "Tarola", 10)]
    assignment = suggest_assignment(groups)
    assert assignment["DPCM:C2:Bombo"] == {"lane": "kick", "cymbal": False}
    assert assignment["DPCM:D2:Tarola"] == {"lane": "snare", "cymbal": False}
    assert assignment["Noise:C4:Hi-hat"] == {"lane": "tom2", "cymbal": True}
    assert assignment["Noise:D3:Raro"]["lane"] is None   # menos de 3 golpes: no se asigna


def test_drums_file_round_trip(tmp_path):
    assert load_drums(tmp_path) is None
    assignment = {"DPCM:C2:Bombo": {"lane": "kick", "cymbal": False}, "Noise:C4:Hi-hat": {"lane": "tom2", "cymbal": True}}
    save_drums(tmp_path, assignment)
    assert load_drums(tmp_path) == assignment
    assert "\r" not in (tmp_path / "drums.json").read_text(encoding="utf-8")
    with pytest.raises(ValueError, match="papel"):
        save_drums(tmp_path, {"x": {"lane": "triangulo", "cymbal": False}})


def hits_of(items):
    return [Hit(frame, role, cymbal) for frame, role, cymbal in items]


def test_chart_lanes_and_difficulty_folding():
    hits = hits_of([(0, "kick", False), (40, "snare", False), (80, "tom1", False), (120, "tom2", False), (160, "tom3", False)])
    masks = lambda name: [n.mask for n in build_drum_chart(hits, name, GRID, 128)]
    assert masks("experto") == [KICK, SNARE, TOM1, TOM2, TOM3]
    assert masks("dificil") == [KICK, SNARE, TOM1, TOM2, TOM3]
    assert masks("medio") == [KICK, SNARE, TOM1, TOM2, TOM2]    # el tom 3 se junta con el 2
    assert masks("facil") == [KICK, SNARE, TOM1, TOM1, TOM1]    # los toms se juntan en el 1
    assert build_drum_chart(hits, "experto", GRID, 128)[0].frame == 128


def test_cymbals_only_in_expert():
    hits = hits_of([(0, "kick", False), (0, "tom2", True), (40, "tom2", True)])
    expert = build_drum_chart(hits, "experto", GRID, 0)
    assert [(n.mask, n.cymbal) for n in expert] == [(KICK | TOM2, True), (TOM2, True)]
    hard = build_drum_chart(hits, "dificil", GRID, 0)
    # sin Pro el platillo es un tom, y no se junta con el bombo (si no, casi todo serían acordes con el hi-hat)
    assert [(n.mask, n.cymbal) for n in hard] == [(KICK, False), (TOM2, False)]


def test_chart_respects_blocked_pair_gap_and_buttons():
    # tom 3 (verde) y tom 1 (amarillo) a la vez son imposibles: se queda uno, con el bombo
    chart = build_drum_chart(hits_of([(0, "tom3", False), (0, "tom1", False), (0, "kick", False)]), "experto", GRID, 0)
    check_playable(chart, DRUM_BLOCKED_PAIRS)
    assert len(chart) == 1 and bin(chart[0].mask).count("1") == 2 and chart[0].mask & KICK
    # fácil no usa acordes
    easy = build_drum_chart(hits_of([(0, "kick", False), (0, "snare", False)]), "facil", GRID, 0)
    assert len(easy) == 1 and bin(easy[0].mask).count("1") == 1
    # golpes demasiado juntos: fácil deja 24 cuadros mínimos y experto 5
    close = hits_of([(f, "snare", False) for f in range(0, 100, 3)])
    for name, gap in (("facil", 24), ("experto", 5)):
        chart = build_drum_chart(close, name, GRID, 0)
        assert all(b.frame - a.frame >= gap for a, b in zip(chart, chart[1:])), name


def test_cymbal_flag_in_chart_file_format():
    chart = [ChartNote(10, 0b01000, None, False, True), ChartNote(20, 0b10000)]
    entries = chart_entries(chart)
    assert entries[0] == (10, 0x48)       # bit $40: platillo
    assert entries_to_chart(entries, drums=True) == chart
    assert entries_to_chart(entries)[0].cymbal is False   # sin ser batería ese bit es una cola
    with pytest.raises(ValueError, match="platillo"):
        chart_entries([ChartNote(10, 0b01000, 40, False, True)])


def test_cymbal_edits_and_problems():
    auto = [ChartNote(10, 0b01000), ChartNote(20, 0b00010)]
    edited = [ChartNote(10, 0b01000, None, False, True), ChartNote(20, 0b00010)]
    ops = diff_charts(auto, edited)
    assert ops == [{"op": "set", "frame": 10, "cymbal": True}]
    assert apply_edits(auto, ops) == edited
    assert diff_charts(auto, [ChartNote(30, 0b01000, None, False, True)])[-1] == {
        "op": "add", "frame": 30, "mask": 8, "end": None, "star": False, "cymbal": True}
    assert not [p for p in chart_problems(edited, 5, True) if p["kind"] == "error"]
    assert chart_problems([ChartNote(10, 0b00010, None, False, True)], 5, True)[0]["kind"] == "error"   # la tarola no es platillo
    # en la batería solo verde + amarillo es imposible; amarillo + naranja (tom 1 + bombo) sí se puede
    chord = [ChartNote(10, 0b10100)]
    assert not chart_problems(chord, 5, True)
    assert chart_problems(chord, 5, False)
    validate_chart("bateria/experto", chord)
    with pytest.raises(ValueError):
        validate_chart("guitarra/experto", chord)
    with pytest.raises(ValueError):
        validate_chart("bateria/experto", [ChartNote(10, 0b00101)])


def make_drum_source(tmp_path):
    song = drum_song()
    song.notes["Square1"] = [Note(i * 10, 60 + (i % 5), 8) for i in range(40)]
    return editor.SongSource("prueba", tmp_path, {"source": "audio/prueba.txt"}, song, GRID, False)


def test_payload_has_drum_charts_and_groups(tmp_path):
    payload = editor.build_payload(make_drum_source(tmp_path))
    assert "bateria" in [i["name"] for i in payload["instruments"]]
    assert {k for k in payload["charts"] if k.startswith("bateria/")} == {
        f"bateria/{d}" for d in ("facil", "medio", "dificil", "experto")}
    assert payload["drums"]["suggested"] and len(payload["drums"]["groups"]) == 4
    assert [r["lane"] for r in payload["drums"]["roles"]] == [4, 1, 2, 3, 0]


def test_server_saves_assignment_and_rebuilds_charts(tmp_path):
    src = make_drum_source(tmp_path)
    server = editor.ThreadingHTTPServer(("127.0.0.1", 0), type("Bound", (editor.Handler,), {"app": editor.App(src)}))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"

    def call(path, body):
        request = urllib.request.Request(base + path, json.dumps(body).encode())
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read())

    try:
        payload = editor.build_payload(src)
        assignment = payload["drums"]["assignment"]
        # Solo el bombo: el chart de batería queda con bombos nada más
        only_kick = {k: {"lane": "kick" if "Bombo" in k else None, "cymbal": False} for k in assignment}
        data = call("/api/drums", {"song": "prueba", "assignment": only_kick})
        assert set(data["charts"]) == {f"bateria/{d}" for d in ("facil", "medio", "dificil", "experto")}
        assert all(n["mask"] == KICK for n in data["charts"]["bateria/experto"])
        # Sin papeles: no hay chart de batería
        nothing = {k: {"lane": None, "cymbal": False} for k in assignment}
        assert call("/api/drums", {"song": "prueba", "assignment": nothing})["charts"] == {}

        # Guardar con una edición de la batería: queda en edits.json y la asignación en drums.json
        charts = dict(payload["charts"])
        charts["bateria/facil"] = charts["bateria/facil"][1:]
        call("/api/save", {"song": "prueba", "charts": charts, "drums": assignment})
        assert load_drums(tmp_path) == assignment
        assert load_edits(tmp_path)["bateria/facil"][0]["op"] == "delete"
        # Si la página no mandó la asignación, las ediciones de batería la dejan escrita igual
        (tmp_path / "drums.json").unlink()
        call("/api/save", {"song": "prueba", "charts": charts})
        assert load_drums(tmp_path) is not None
        # Exportar no escribe la batería en chart.s (el juego aún no tiene su modo)
        call("/api/export", {"song": "prueba", "charts": charts, "drums": assignment})
        assert "bateria" not in (tmp_path / "chart.s").read_text(encoding="utf-8")
    finally:
        server.shutdown()
        server.server_close()
