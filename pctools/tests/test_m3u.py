from nesband_tools.cli import to_nes_text
from nesband_tools.m3u import parse_duration, parse_m3u

SAMPLE = """# Blaster Master
# Music by Naoki Kodaka & Marumo

Blaster Master.nsf::NSF,1,Intro,0:00:33,,
Blaster Master.nsf::NSF,2,Area 1,0:01:27,,
Juego.nsf::NSF,3,Mission 1 [Billy\\, Jimmy],0:02:33.878,,0:00:03.123
Juego.nsf::NSF,9,Boss (se),,,
"""


def test_parse_duration():
    assert parse_duration("0:01:27") == 87
    assert parse_duration("0:02:33.878") == 154
    assert parse_duration("1:05") == 65
    assert parse_duration("") is None


def test_parse_m3u():
    playlist = parse_m3u(SAMPLE)
    assert playlist.game == "Blaster Master"
    assert playlist.tracks[2].title == "Area 1"
    assert playlist.tracks[2].seconds == 87
    assert playlist.tracks[3].title == "Mission 1 [Billy, Jimmy]"
    assert playlist.tracks[9].seconds is None


def test_to_nes_text():
    assert to_nes_text("Canción ñandú: ¡Área 1!") == "CANCION NANDU: AREA 1!"
    assert to_nes_text("Mission 1 [Billy & Jimmy]") == "MISSION 1 BILLY JIMMY"


EXT_SAMPLE = """#EXTM3U
#EXTINF:-1,Mega Man (NES) - Track 03 - Cut Man Stage
mega-man-nes-[NSF-ID1961].nsf::3
#EXTINF:-1,Mega Man (NES) - Track 11 - Dr. Wily's Castle Stage 1 & 2
mega-man-nes-[NSF-ID1961].nsf::11
"""


def test_parse_extm3u_without_durations():
    playlist = parse_m3u(EXT_SAMPLE)
    assert playlist.game == "Mega Man (NES)"
    assert playlist.tracks[3].title == "Cut Man Stage"
    assert playlist.tracks[3].seconds is None
    assert playlist.tracks[11].title == "Dr. Wily's Castle Stage 1 & 2"


def test_parse_extm3u_without_track_numbers():
    text = "#EXTM3U\n#EXTINF:-1,Mega Man 2 - Quick Man Stage\nmm2.nsf::6\n"
    playlist = parse_m3u(text)
    assert playlist.game == "Mega Man 2"
    assert playlist.tracks[6].title == "Quick Man Stage"
