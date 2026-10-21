# Compila y corre las pruebas automáticas en Mesen 2 (modo --testrunner, sin ventana)
# Uso:  .\tests\run_tests.ps1
# Por cada canción:
#   1 jugador: juego perfecto con guitarra, teclado y bajo, y una partida sin tocar nada
#   2 jugadores: los dos perfectos (guitarra + bajo), y uno perfecto con el otro sin tocar
#                (teclado + guitarra), para comprobar que cada quien lleva su propio juego
# Deja resultado y capturas en build\test-<cancion>-<caso>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

& (Join-Path $root 'build.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

$mesen = Join-Path $root 'tools\mesen\Mesen.exe'
if (-not (Test-Path $mesen)) { Write-Host 'No encontre tools\mesen\Mesen.exe (ver README)' -ForegroundColor Red; exit 1 }

# Canciones en el orden del menú (alfabético, como src/songs/list.s)
$songs = @(Get-ChildItem (Join-Path $root 'src\songs') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'song.s') } | Sort-Object Name)

# nombre, jugadores, modo J1, instrumento J1, modo J2, instrumento J2
$kinds = @(
    @('1p-guitarra', 1, 'perfect', 0, 'perfect', 2),
    @('1p-teclado',  1, 'perfect', 1, 'perfect', 2),
    @('1p-bajo',     1, 'perfect', 2, 'perfect', 0),
    @('1p-idle',     1, 'idle',    0, 'perfect', 2),
    @('2p-perfect',  2, 'perfect', 0, 'perfect', 2),
    @('2p-mixto',    2, 'perfect', 1, 'idle',    0)
)

$failed = $false
for ($s = 0; $s -lt $songs.Count; $s++) {
    foreach ($kind in $kinds) {
        $name, $players, $mode1, $inst1, $mode2, $inst2 = $kind
        $out = Join-Path $root "build\test-$($songs[$s].Name)-$name"
        New-Item -ItemType Directory -Force $out | Out-Null
        Remove-Item "$out\resultado.txt" -ErrorAction SilentlyContinue
        $env:AUTOPLAY_SONG = $s
        $env:AUTOPLAY_PLAYERS = $players
        $env:AUTOPLAY_MODE = $mode1
        $env:AUTOPLAY_INSTRUMENT = $inst1
        $env:AUTOPLAY_MODE2 = $mode2
        $env:AUTOPLAY_INSTRUMENT2 = $inst2
        $env:TEST_OUT = $out
        $p = Start-Process -FilePath $mesen -PassThru -Wait -NoNewWindow -ArgumentList @(
            '--testrunner', "`"$root\build\nesband.nes`"", "`"$root\tests\autoplay.lua`"")
        $result = if (Test-Path "$out\resultado.txt") { (Get-Content "$out\resultado.txt" -Raw).Trim() } else { 'sin resultado' }
        Write-Host "[$($songs[$s].Name)/$name] $result (exit $($p.ExitCode))"
        if ($p.ExitCode -ne 0) { $failed = $true }
    }
}
if ($failed) { exit 1 }
