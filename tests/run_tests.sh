#!/usr/bin/env bash
# Compila y corre las pruebas de NESBand en MAME (tests/mame_shim.lua; con --emulador mesen, en Mesen 2). Envoltorio de
# `uv run nesband test`, que es igual en macOS y Windows (ver bandcore.testrun).
# Uso:  tests/run_tests.sh [--no-build] [--rapida] [-j 6] [--sin-ventana] [--emulador mesen] [--release] [--rom ruta]
#                          [--lista] [patron ...]
#   patron: una canción entera (`wily`, `cv3_*`) o un caso (`wily/1p-guitarra`, `*/2p-coop*`); acepta comodines y comas
# Deja resultado y capturas en build/test-<cancion>-<caso>. Las fallas conocidas van en tests/known_failures.txt.
exec uv run --project "$(cd "$(dirname "$0")/.." && pwd)" nesband test "$@"
