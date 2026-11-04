# Compila y corre las pruebas de NESBand en MAME (tests/mame_shim.lua; con --emulador mesen, en Mesen 2). Envoltorio de
# `uv run nesband test`, que es igual en macOS y Windows (ver bandcore.testrun).
# Uso:  .\tests\run_tests.ps1 [--no-build] [--rapida] [-j 6] [--sin-ventana] [--emulador mesen] [--release] [--rom ruta]
#                             [--lista] [patron ...]
#   patron: una canción entera (`wily`, `cv3_*`) o un caso (`wily/1p-guitarra`, `*/2p-coop*`); acepta comodines y comas
#   --rapida   la demo y 3 canciones representativas (cambios del motor); sin ella, la corrida completa (cambios de
#              charts, generador o bancos). Con --release, la demo y una original de cada estilo.
#   -j N       N casos a la vez (cada uno con su copia del ROM, así que sus .sav no se mezclan)
# Deja resultado y capturas en build\test-<cancion>-<caso>. Las fallas conocidas van en tests\known_failures.txt.
$root = Split-Path $PSScriptRoot -Parent
& uv run --project $root nesband test @args
exit $LASTEXITCODE
