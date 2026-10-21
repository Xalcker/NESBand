# Compila y corre las pruebas automáticas en Mesen 2 (modo --testrunner, sin ventana)
# Uso:  .\tests\run_tests.ps1
# Por cada canción: juego perfecto con guitarra, teclado y bajo, y una partida sin tocar nada.
# Deja resultado y capturas en build\test-<modo>-<cancion>-<instrumento>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

& (Join-Path $root 'build.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

$mesen = Join-Path $root 'tools\mesen\Mesen.exe'
if (-not (Test-Path $mesen)) { Write-Host 'No encontre tools\mesen\Mesen.exe (ver README)' -ForegroundColor Red; exit 1 }

# Canciones en el orden del menú (alfabético, como src/songs/list.s)
$songs = @(Get-ChildItem (Join-Path $root 'src\songs') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'song.s') } | Sort-Object Name)

$cases = @()
for ($s = 0; $s -lt $songs.Count; $s++) {
    $cases += , @('perfect', $s, 0)
    $cases += , @('perfect', $s, 1)
    $cases += , @('perfect', $s, 2)
    $cases += , @('idle', $s, 0)
}

$failed = $false
foreach ($case in $cases) {
    $mode, $song, $instrument = $case
    $out = Join-Path $root "build\test-$mode-$song-$instrument"
    New-Item -ItemType Directory -Force $out | Out-Null
    Remove-Item "$out\resultado.txt" -ErrorAction SilentlyContinue
    $env:AUTOPLAY_MODE = $mode
    $env:AUTOPLAY_SONG = $song
    $env:AUTOPLAY_INSTRUMENT = $instrument
    $env:TEST_OUT = $out
    $p = Start-Process -FilePath $mesen -PassThru -Wait -NoNewWindow -ArgumentList @(
        '--testrunner', "`"$root\build\nesband.nes`"", "`"$root\tests\autoplay.lua`"")
    $result = if (Test-Path "$out\resultado.txt") { (Get-Content "$out\resultado.txt" -Raw).Trim() } else { 'sin resultado' }
    Write-Host "[$($songs[$song].Name)/$mode/$instrument] $result (exit $($p.ExitCode))"
    if ($p.ExitCode -ne 0) { $failed = $true }
}
if ($failed) { exit 1 }
