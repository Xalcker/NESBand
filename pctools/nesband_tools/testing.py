"""Pruebas de NESBand en Mesen 2 (``--testrunner``, sin ventana): los casos de cada canción.

Se corren con ``uv run nesband test`` (ver ``bandcore.testrun``). El bot (``tests/autoplay.lua``) lee las variables
AUTOPLAY_* de cada caso, juega, escribe ``resultado.txt`` y termina con código 0 si todo salió como debe.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

from bandcore import testrun
from bandcore.testrun import Case, Result

ROOT = Path(__file__).resolve().parents[2]

# Con un settings.json junto al ejecutable Mesen corre en modo portable. Sin AutoConfigureInput, uno nuevo deja el
# puerto 1 sin control: hay que declarar los dos
MESEN_SETTINGS = ('{"Debug":{"ScriptWindow":{"AllowIoOsAccess":true}},"Nes":{"AutoConfigureInput":false,'
                  '"Port1":{"Type":"NesController"},"Port2":{"Type":"NesController"}}}')

DEMO = "nesband_demo"
RAPIDA_SONGS = ["tormenta", "salto", "carrera"]       # originales (van en git, así que existen en cualquier copia)
RAPIDA_KINDS = ["1p-guitarra", "1p-bajo", "1p-teclado", "1p-bateria", "2p-coop"]

# nombre, jugadores, modo J1, instrumento J1, dificultad J1, modo J2, instrumento J2, dificultad J2, y opcionales:
# estrella, récord, coop, vs, corte, cae, revive, opciones (dificultad: 0 fácil .. 3 experto)
P = "perfect"
KINDS = [
    ("1p-guitarra", 1, P, 0, 3, P, 2, 3),
    ("1p-teclado", 1, P, 1, 3, P, 2, 3),
    ("1p-bajo", 1, P, 2, 3, P, 0, 3),
    ("1p-facil", 1, P, 0, 0, P, 2, 0),
    ("1p-idle", 1, "idle", 0, 3, P, 2, 3),
    ("1p-smash", 1, "smash", 0, 3, P, 2, 3),
    ("1p-humano90", 1, "human90", 0, 3, P, 2, 3),
    ("1p-humano50", 1, "human50", 0, 3, P, 2, 3),
    ("2p-perfect", 2, P, 0, 3, P, 2, 3),
    ("2p-mixto", 2, P, 1, 3, "idle", 0, 3, 0, 0, 0, 1),
    ("2p-velocidades", 2, P, 0, 0, P, 2, 3, 0, 0, 1),   # Co-Op: en VS la dificultad es la misma
    ("2p-vs-facil", 2, P, 0, 0, P, 2, 0, 0, 0, 0, 0),
    ("1p-fallo", 1, "fail", 0, 3, P, 2, 3),
    # Batería (instrumento 3): solo en las canciones con chart de batería (su drums.json); el bombo es una gema naranja
    ("1p-bateria", 1, P, 3, 3, P, 2, 3),
    ("1p-bateria-facil", 1, P, 3, 0, P, 2, 0),
    ("1p-bateria-idle", 1, "idle", 3, 3, P, 2, 3),
    ("1p-bateria-espejo", 1, P, 3, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "1000"),   # la batería no se espeja
    ("2p-bateria", 2, P, 3, 3, P, 0, 3),
    ("1p-estrella", 1, P, 0, 3, P, 2, 3, 1),
    ("2p-estrella", 2, P, 0, 3, P, 2, 3, 1),
    # VS: quién gana (el penúltimo número: 1 = J1, 2 = J2, 3 = empate; 2p-mixto ya revisa que gane J1)
    ("2p-vs-gana2", 2, "idle", 0, 3, P, 2, 3, 0, 0, 0, 2),
    ("2p-vs-empate", 2, "idle", 0, 3, "idle", 2, 3, 0, 0, 0, 3),
    # VS con fallo: si uno pierde, la partida se corta y gana el otro (el último 1 = se corta)
    ("2p-vs-pierde1", 2, "fail", 0, 3, P, 2, 3, 0, 0, 0, 2, 1),
    ("2p-vs-pierde2", 2, P, 0, 3, "fail", 2, 3, 0, 0, 0, 1, 1),
    # VS con el mismo instrumento (mismo chart y canal): perfectos = empate; sin tocar, el canal se calla
    ("2p-vs-mismo", 2, P, 0, 3, P, 0, 3, 0, 0, 0, 3),
    ("2p-vs-mismo-idle", 2, "idle", 0, 3, "idle", 0, 3, 0, 0, 0, 3),
    # Co-Op: puntaje, combo y poder estelar compartidos
    ("2p-coop", 2, P, 0, 3, P, 2, 3, 0, 0, 1),
    ("2p-coop-estrella", 2, P, 0, 3, P, 2, 3, 1, 0, 1),
    ("2p-coop-fallo", 2, "fail", 0, 3, "fail", 2, 3, 0, 0, 1),
    # Co-Op con un caído: el jugador 2 cae y el 1 sigue; y el 1 lo revive con media barra de poder
    ("2p-coop-cae", 2, P, 0, 3, "fail", 2, 3, 0, 0, 1, 0, 0, 1),
    ("2p-coop-revive", 2, P, 0, 3, "fail", 2, 3, 0, 0, 1, 0, 0, 0, 1),
    # Opciones: 4 dígitos = espejo (0-1), velocidad (0 = 100%, 1 = 75%, 2 = 50%, 3 = 125%), caída (0 = auto, 1-4) y
    # práctica (0 = no, 1-3 = hasta 1/4, 1/2, 3/4; 4 = toda)
    ("1p-espejo", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "1000"),
    ("1p-lenta75", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "0100"),
    ("1p-lenta50", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "0200"),
    ("1p-rapida125", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "0300"),
    ("2p-coop-rapida125", 2, P, 0, 3, P, 2, 3, 0, 0, 1, 0, 0, 0, 0, "0300"),
    ("2p-vs-rapida125", 2, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "0300"),
    ("1p-caida", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "0010"),
    ("1p-practica", 1, "fail", 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "0001"),
    # el quinto dígito es el inicio de la práctica (0 = el principio, 1-3 = 1/4, 1/2, 3/4)
    ("1p-inicio", 1, "fail", 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "00032"),
    ("1p-inicio-tope", 1, "fail", 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "00023"),
    # el sexto dígito son las marcas de la pausa: 1 = A (inicio), 2 = B (final)
    ("1p-pausa-practica", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "0002"),
    ("1p-marca-inicio", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "000201"),
    ("1p-marca-final", 1, P, 0, 3, P, 2, 3, 0, 0, 0, 0, 0, 0, 0, "000202"),
    ("2p-vs-espejo", 2, P, 0, 3, P, 0, 3, 0, 0, 0, 3, 0, 0, 0, "1000"),    # mismo chart y mismo espejo: empate
    # Récords (solo con la canción de ejemplo, y en este orden: el segundo usa lo que guardó el primero)
    ("1p-record1", 1, P, 0, 3, P, 2, 3, 0, 1),
    ("1p-record2", 1, P, 0, 3, P, 2, 3, 0, 2),
]


def songs_of(root: Path, release: bool) -> list[Path]:
    """Las canciones en el orden del menú (alfabético, como src/songs/list.s); con ``release``, solo las de git."""
    songs = sorted((d for d in (root / "src" / "songs").iterdir() if (d / "song.s").is_file()), key=lambda d: d.name)
    if release:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "src/songs"], capture_output=True, text=True).stdout
        tracked = {m.group(1) for ln in out.splitlines() if (m := re.match(r"^src/songs/([^/]+)/song\.s$", ln))}
        songs = [d for d in songs if d.name in tracked]
    return songs


def has_drums(song: Path) -> bool:
    """¿Tiene chart de batería? (el bit 3 de los instrumentos con chart de su ficha): el menú la ofrece o no."""
    m = re.search(r"(?m)^\s*\.byte %0000(\d)(\d{3})\s*; instrumentos con chart", (song / "song.s").read_text(encoding="utf-8"))
    return bool(m and m.group(1) == "1")


def rom_path(root: Path, args) -> Path:
    if getattr(args, "rom", None):
        return Path(args.rom).resolve()
    if getattr(args, "release", False):
        version = (root / "VERSION").read_text(encoding="utf-8").splitlines()[0].strip()
        return root / "build" / "release" / f"nesband-v{version}.nes"
    return root / "build" / "nesband.nes"


def build_cases(args, root: Path = ROOT) -> list[Case]:
    release = getattr(args, "release", False)
    songs = songs_of(root, release)
    cases: list[Case] = []
    for s, song in enumerate(songs):
        drums = has_drums(song)
        for kind in KINDS:
            name, players, mode1, inst1, diff1, mode2, inst2, diff2, *rest = kind
            star, record, coop, vs, cut, down, revive = (list(rest[:7]) + [0] * 7)[:7]
            opts = rest[7] if len(rest) > 7 else "0000"     # espejo, velocidad, caída, práctica, inicio, marca
            if record and song.name != "nesband_demo":
                continue
            if "bateria" in name and not drums:
                continue
            env = {
                "AUTOPLAY_SONG": str(s), "AUTOPLAY_PLAYERS": str(players), "AUTOPLAY_MODE": mode1,
                "AUTOPLAY_INSTRUMENT": str(inst1), "AUTOPLAY_DIFFICULTY": str(diff1), "AUTOPLAY_MODE2": mode2,
                "AUTOPLAY_INSTRUMENT2": str(inst2), "AUTOPLAY_DIFFICULTY2": str(diff2), "AUTOPLAY_STAR": str(star),
                "AUTOPLAY_DRUMS": str(int(drums)), "AUTOPLAY_RECORD": str(record), "AUTOPLAY_COOP": str(coop),
                "AUTOPLAY_VS": str(vs), "AUTOPLAY_CUT": str(cut), "AUTOPLAY_DOWN": str(down),
                "AUTOPLAY_REVIVE": str(revive), "AUTOPLAY_MIRROR": opts[0], "AUTOPLAY_SPEED": opts[1],
                "AUTOPLAY_FALL": opts[2], "AUTOPLAY_PRACTICE": opts[3], "AUTOPLAY_START": opts[4:5],
                "AUTOPLAY_MARK": opts[5:6],
            }
            mame = getattr(args, "emulador", "mame") == "mame"
            cases.append(Case(f"{song.name}/{name}", env, out=root / "build" / f"test-{song.name}-{name}",
                              check=check_case, serial=bool(record), fresh_nvram=record == 1,
                              # (MAME guarda la SRAM en su carpeta nvram: los dos casos de récord comparten una)
                              nvram=root / "build" / "test-nvram-records" if mame and record else None,
                              extra={"mame": mame}))
    if getattr(args, "rapida", False):
        # la demo completa (la lógica del juego no depende de la canción) y, en unas canciones originales, solo lo que
        # sí depende de ella: el chart y el audio de cada instrumento, una partida de 2 jugadores y las notas sostenidas
        cases = [c for c in cases if (s := c.name.split("/")[0]) == DEMO
                 or (s in RAPIDA_SONGS and c.name.split("/")[1] in RAPIDA_KINDS)]
    return cases


def check_case(case: Case, d: Path, code: int) -> Result:
    """El bot decide: código de salida 0 = bien. El resumen es lo que escribió en resultado.txt.
    (En MAME el código de salida del proceso no sirve: el bot deja el suyo en exitcode.txt.)"""
    exit_file = d / "exitcode.txt"
    if exit_file.exists():
        code = int(exit_file.read_text().strip() or 1)
    elif case.extra.get("mame"):
        code = 1                                         # MAME terminó sin que el bot llamara a emu.stop
    f = d / "resultado.txt"
    text = " ".join(f.read_text(encoding="utf-8").split()) if f.exists() else "sin resultado"
    return Result(testrun.OK if code == 0 else testrun.FAIL, f"{text} (exit {code})")


def expand_patterns(patterns: list[str]) -> list[str]:
    """Los casos se llaman ``cancion/caso``: un patrón sin ``/`` es una canción entera (``wily`` = ``wily/*``)."""
    return [p if "/" in p else f"{p}/*" for p in testrun.split_patterns(patterns)]


def emulator(root: Path, args):
    """Mesen 2 (por omisión) o MAME con ``tests/mame_shim.lua``, que le presta a autoplay.lua la API de Mesen."""
    rom = rom_path(root, args)
    if getattr(args, "emulador", "mame") == "mame":
        return testrun.Mame(
            lambda case: ["nes", "-cart", str(rom), "-seconds_to_run", "1500"],
            root / "tests" / "mame_shim.lua", window=not getattr(args, "sin_ventana", False), resolution="512x480",
            env=lambda case: {"SHIM_DBG": str(rom.with_suffix(".dbg")),
                              "SHIM_SCRIPT": str(root / "tests" / "autoplay.lua"), "TEST_OUT": str(case.out)})
    return testrun.Mesen(rom, root / "tests" / "autoplay.lua", MESEN_SETTINGS)
