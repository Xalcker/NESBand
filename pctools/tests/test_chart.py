from nesband_tools.chart import (
    DIFFICULTIES,
    BeatGrid,
    assign_lanes,
    build_chart,
    estimate_beat,
    merge_attacks,
    reduce_notes,
)
from nesband_tools.famistudio import Note, note_to_midi, parse_text

SAMPLE = """Project Version="4.5.3" TempoMode="FamiStudio" Name="Test"
\tSong Name="Song 1" Length="2" LoopPoint="0" PatternLength="4" BeatLength="4" NoteLength="5" Groove="5"
\t\tChannel Type="Square1"
\t\t\tPattern Name="A"
\t\t\t\tNote Time="0" Value="C4" Duration="5" Instrument="Lead"
\t\t\t\tNote Time="3" Volume="10"
\t\t\t\tNote Time="10" Value="E4" Duration="5" Instrument="Lead"
\t\t\tPattern Name="B"
\t\t\t\tNote Time="5" Value="G4" Duration="5" Instrument="Lead"
\t\t\tPatternInstance Time="0" Pattern="A"
\t\t\tPatternInstance Time="1" Pattern="B"
\t\tChannel Type="Triangle"
"""


def test_note_to_midi():
    assert note_to_midi("C4") == 60
    assert note_to_midi("A4") == 69
    assert note_to_midi("C#3") == 49
    assert note_to_midi("Stop") is None


def test_parse_text_places_notes_in_frames():
    song = parse_text(SAMPLE).songs[0]
    assert song.pattern_frames == [20, 20]
    assert song.frames_per_beat == 20
    # La nota de solo volumen (Time=3) no cuenta; el patrón B empieza en el cuadro 20
    assert [(n.frame, n.pitch) for n in song.notes["Square1"]] == [(0, 60), (10, 64), (25, 67)]
    assert song.notes["Triangle"] == []


def test_estimate_beat_doubles_subdivision():
    onsets = list(range(0, 400, 5))  # semicorcheas cada 5 cuadros
    grid = estimate_beat(onsets)
    assert grid.frames_per_beat == 20
    assert grid.first_beat == 0


def test_reduce_notes_keeps_strong_beats_and_gap():
    grid = BeatGrid(20, 0)
    notes = [Note(f, 60, 5) for f in range(0, 80, 5)]
    kept = reduce_notes(notes, DIFFICULTIES[0], grid)  # fácil: min_gap 24
    # Primero los tiempos (0 y 40; 20 y 60 quedan muy cerca), luego medios tiempos (70)
    assert [n.frame for n in kept] == [0, 40, 70]
    assert all(b.frame - a.frame >= 24 for a, b in zip(kept, kept[1:]))


def test_merge_attacks_keeps_first_frame():
    # Golpe de 1 cuadro + la misma nota sostenida = una nota desde el golpe
    notes = [Note(0, 50, 1), Note(1, 50, 111), Note(120, 50, 10), Note(121, 52, 10)]
    merged = merge_attacks(notes)
    assert [(n.frame, n.pitch, n.duration) for n in merged] == [(0, 50, 112), (120, 50, 10), (121, 52, 10)]


def test_merge_attacks_joins_pitch_sweeps():
    # Barrido de un cuadro por nota (como Double Dragon) y luego una nota normal
    sweep = [Note(10 + i, 53 - 2 * i, 1) for i in range(8)]
    notes = sweep + [Note(20, 45, 8)]
    merged = merge_attacks(notes)
    assert [(n.frame, n.pitch, n.duration) for n in merged] == [(10, 53, 8), (20, 45, 8)]


def test_assign_lanes_follows_contour():
    pitches = [60, 62, 64, 64, 62, 60]
    notes = [Note(i * 10, p, 5) for i, p in enumerate(pitches)]
    lanes = assign_lanes(notes, 5)
    assert lanes[0] < lanes[1] < lanes[2]  # sube
    assert lanes[2] == lanes[3]  # repite nota, repite carril
    assert lanes[3] > lanes[4] > lanes[5]  # baja
    assert all(0 <= lane < 5 for lane in lanes)


def test_chart_entries_use_deltas_and_spacers():
    from nesband_tools.chart import ChartNote, chart_entries, chart_size

    chart = [ChartNote(128, 0x01), ChartNote(140, 0x02), ChartNote(800, 0x04)]
    entries = chart_entries(chart)
    # 128; +12; +660 = 255 + 255 + 150 (dos rellenos sin carriles); fin
    assert entries == [(128, 0x01), (12, 0x02), (255, 0), (255, 0), (150, 0x04), (0, 0xFF)]
    assert chart_size(chart) == 12


def test_chart_entries_sustain_flag_and_release():
    from nesband_tools.chart import END_FLAG, SUSTAIN_FLAG, ChartNote, chart_entries

    # Una nota con cola en el carril 0 (cuadros 100-160) y otra normal en medio
    chart = [ChartNote(100, 0x01, end=160), ChartNote(130, 0x04)]
    assert chart_entries(chart) == [
        (100, 0x01 | SUSTAIN_FLAG),
        (30, 0x04),
        (30, 0x01 | END_FLAG),
        (0, 0xFF),
    ]


def test_sustain_ends_respects_duration_and_next_note_in_lane():
    from nesband_tools.chart import MIN_SUSTAIN, SUSTAIN_GAP, SUSTAIN_TRIM, sustain_ends

    notes = [Note(0, 60, 100), Note(40, 64, 5), Note(200, 60, 10), Note(300, 60, 90)]
    lanes = [0, 1, 0, 0]
    ends = sustain_ends(notes, lanes)
    # la 1ª es larga pero la siguiente en su carril llega en 200: termina por su duración
    assert ends[0] == 100 - SUSTAIN_TRIM
    assert ends[1] is None  # muy corta
    assert ends[2] is None  # 10 cuadros < MIN_SUSTAIN
    assert ends[3] == 300 + 90 - SUSTAIN_TRIM
    # y si la siguiente nota del carril llega antes de que acabe, la cola la deja pasar
    cut = sustain_ends([Note(0, 60, 100), Note(50, 62, 5)], [0, 0])
    assert cut[0] == 50 - SUSTAIN_GAP - SUSTAIN_TRIM
    assert MIN_SUSTAIN <= cut[0]


def test_star_phrases_are_separated_runs():
    from nesband_tools.chart import STAR_FIRST, STAR_FLAG, STAR_PHRASE_LEN, STAR_SPACING, ChartNote, chart_entries, star_notes

    stars = star_notes(100)
    runs = []
    for i, star in enumerate(stars):
        if star and (i == 0 or not stars[i - 1]):
            runs.append(i)
    assert runs == list(range(STAR_FIRST, 100 - STAR_PHRASE_LEN, STAR_SPACING))
    assert all(sum(stars[r : r + STAR_PHRASE_LEN]) == STAR_PHRASE_LEN for r in runs)
    assert star_notes(5) == [False] * 5  # canción corta: sin frases

    entries = chart_entries([ChartNote(10, 0x04, star=True), ChartNote(20, 0x01)])
    assert entries[0] == (10, 0x04 | STAR_FLAG)
    assert entries[1] == (10, 0x01)


def test_build_chart_frames_and_lanes():
    grid = BeatGrid(20, 0)
    notes = [Note(0, 60, 5), Note(10, 64, 5), Note(20, 67, 5)]
    chart = build_chart(notes, DIFFICULTIES[-1], grid, lead_in=128)
    assert [n.frame for n in chart] == [128, 138, 148]
    assert all(bin(n.mask).count("1") == 1 and n.mask < 0x20 for n in chart)  # un carril por nota
