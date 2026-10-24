import json
import shutil
import subprocess
from pathlib import Path

import pytest
from nesband_tools import player

ROOT = Path(__file__).resolve().parents[2]
TESTS = Path(__file__).parent
NODE = shutil.which("node")
HAS_CC65 = player.find_tool(ROOT, "ca65") != "ca65" or shutil.which("ca65")

needs_node = pytest.mark.skipif(not NODE, reason="falta Node.js")
needs_cc65 = pytest.mark.skipif(not HAS_CC65, reason="falta cc65 (tools/cc65 o el PATH)")


def test_read_labels():
    text = "al 00E088 ._famistudio_init\nal 00E088 .famistudio_init\nal 00E165 .famistudio_music_play\n" \
           "al 00E1A0 .famistudio_music_stop\nal 00E268 .famistudio_update\n"
    assert player.read_labels(text)["famistudio_update"] == 0xE268
    with pytest.raises(RuntimeError, match="famistudio_update"):
        player.read_labels("al 00E088 .famistudio_init\nal 00E165 .famistudio_music_play\nal 00E1A0 .famistudio_music_stop\n")


@needs_node
def test_cpu_and_apu_in_javascript():
    result = subprocess.run([NODE, str(TESTS / "nesplayer_test.js")], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def render_with_node(tmp_path, name, frames):
    """Arma el reproductor de una canción y lo toca con nesplayer.js; devuelve (muestras, rms, escrituras al APU)."""
    payload = player.player_payload(ROOT, name)
    (tmp_path / "player.json").write_text(json.dumps(payload), encoding="utf-8")
    script = """
const fs = require('fs'), NP = require(process.argv[1]);
const player = JSON.parse(fs.readFileSync(process.argv[2]));
const log = [];
NP.render(player, Number(process.argv[3]), { log }).then((r) => {
  let sum = 0; for (const s of r.audio) sum += s * s;
  console.log(JSON.stringify({ samples: r.audio.length, rms: Math.sqrt(sum / r.audio.length), writes: log.map((w) => w[1]) }));
});
"""
    result = subprocess.run(
        [NODE, "-e", script, str(ROOT / "pctools" / "nesband_tools" / "nesplayer.js"), str(tmp_path / "player.json"), str(frames)],
        capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    return data["samples"], data["rms"], set(data["writes"])


@needs_node
@needs_cc65
def test_player_image_and_rendering(tmp_path):
    image, routines = player.build_player(ROOT, "tormenta", ROOT / "build" / "player" / "tormenta")
    assert len(image) == player.IMAGE_SIZE
    assert all(0xE000 <= address < 0x10000 for address in routines.values())   # el motor vive en el banco de $E000
    samples, rms, regs = render_with_node(tmp_path, "tormenta", 300)
    assert abs(samples - 300 * 44100 / 60.0988) < 2
    assert 0.02 < rms < 0.5
    assert {0x4000, 0x4002, 0x4008, 0x400C} <= regs   # pulso, triángulo y ruido


@needs_node
@needs_cc65
def test_dpcm_song_reaches_the_dmc(tmp_path):
    _, rms, regs = render_with_node(tmp_path, "carrera", 600)
    assert rms > 0.02
    assert {0x4010, 0x4012, 0x4013, 0x4015} <= regs   # el motor lanza samples DPCM
