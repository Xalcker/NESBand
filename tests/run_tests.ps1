# Compila y corre las pruebas automáticas en Mesen 2 (modo --testrunner, sin ventana)
# Uso:  .\tests\run_tests.ps1
# Por cada canción:
#   1 jugador: juego perfecto con guitarra, teclado y bajo (en experto), uno en fácil (la
#              autopista más lenta), una partida sin tocar nada y una machacando botones
#              (el combo y las estrellas no deben subir)
#   2 jugadores: los dos perfectos (guitarra + bajo); uno perfecto con el otro sin tocar
#                (teclado + guitarra), para comprobar que cada quien lleva su propio juego;
#                y fácil + experto (la autopista va a la velocidad de experto)
# Deja resultado y capturas en build\test-<cancion>-<caso>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

& (Join-Path $root 'build.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

$mesen = Join-Path $root 'tools\mesen\Mesen.exe'
if (-not (Test-Path $mesen)) { Write-Host 'No encontre tools\mesen\Mesen.exe (ver README)' -ForegroundColor Red; exit 1 }

# Canciones en el orden del menú (alfabético, como src/songs/list.s)
$songs = @(Get-ChildItem (Join-Path $root 'src\songs') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'song.s') } | Sort-Object Name)

# nombre, jugadores, modo J1, instrumento J1, dificultad J1, modo J2, instrumento J2, dificultad J2
# (dificultad: 0 fácil .. 3 experto)
$kinds = @(
    @('1p-guitarra',   1, 'perfect', 0, 3, 'perfect', 2, 3),
    @('1p-teclado',    1, 'perfect', 1, 3, 'perfect', 2, 3),
    @('1p-bajo',       1, 'perfect', 2, 3, 'perfect', 0, 3),
    @('1p-facil',      1, 'perfect', 0, 0, 'perfect', 2, 0),
    @('1p-idle',       1, 'idle',    0, 3, 'perfect', 2, 3),
    @('1p-smash',      1, 'smash',   0, 3, 'perfect', 2, 3),
    @('2p-perfect',    2, 'perfect', 0, 3, 'perfect', 2, 3),
    @('2p-mixto',      2, 'perfect', 1, 3, 'idle',    0, 3),
    @('2p-velocidades', 2, 'perfect', 0, 0, 'perfect', 2, 3)
)

$failed = $false
for ($s = 0; $s -lt $songs.Count; $s++) {
    foreach ($kind in $kinds) {
        $name, $players, $mode1, $inst1, $diff1, $mode2, $inst2, $diff2 = $kind
        $out = Join-Path $root "build\test-$($songs[$s].Name)-$name"
        New-Item -ItemType Directory -Force $out | Out-Null
        Remove-Item "$out\resultado.txt" -ErrorAction SilentlyContinue
        $env:AUTOPLAY_SONG = $s
        $env:AUTOPLAY_PLAYERS = $players
        $env:AUTOPLAY_MODE = $mode1
        $env:AUTOPLAY_INSTRUMENT = $inst1
        $env:AUTOPLAY_DIFFICULTY = $diff1
        $env:AUTOPLAY_MODE2 = $mode2
        $env:AUTOPLAY_INSTRUMENT2 = $inst2
        $env:AUTOPLAY_DIFFICULTY2 = $diff2
        $env:TEST_OUT = $out
        $p = Start-Process -FilePath $mesen -PassThru -Wait -NoNewWindow -ArgumentList @(
            '--testrunner', "`"$root\build\nesband.nes`"", "`"$root\tests\autoplay.lua`"")
        $result = if (Test-Path "$out\resultado.txt") { (Get-Content "$out\resultado.txt" -Raw).Trim() } else { 'sin resultado' }
        Write-Host "[$($songs[$s].Name)/$name] $result (exit $($p.ExitCode))"
        if ($p.ExitCode -ne 0) { $failed = $true }
    }
}
if ($failed) { exit 1 }
