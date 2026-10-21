from nesband_tools.chart import (
    DIFFICULTIES,
    BeatGrid,
    assign_lanes,
    build_chart,
    estimate_beat,
    frame_to_row,
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


def test_assign_lanes_follows_contour():
    pitches = [60, 62, 64, 64, 62, 60]
    notes = [Note(i * 10, p, 5) for i, p in enumerate(pitches)]
    lanes = assign_lanes(notes, 5)
    assert lanes[0] < lanes[1] < lanes[2]  # sube
    assert lanes[2] == lanes[3]  # repite nota, repite carril
    assert lanes[3] > lanes[4] > lanes[5]  # baja
    assert all(0 <= lane < 5 for lane in lanes)


def test_build_chart_rows_frames_and_beat_flag():
    grid = BeatGrid(20, 0)
    notes = [Note(0, 60, 5), Note(10, 64, 5), Note(20, 67, 5)]
    chart = build_chart(notes, DIFFICULTIES[-1], grid, lead_in=128, beat_rows=5, first_beat_row=32)
    assert [n.frame for n in chart] == [128, 138, 148]
    assert [n.row for n in chart] == [frame_to_row(f) for f in (128, 138, 148)]
    assert chart[0].mask & 0x80  # fila 32: tiene línea de beat
    assert not chart[1].mask & 0x80
    assert chart[2].mask & 0x80  # fila 37
