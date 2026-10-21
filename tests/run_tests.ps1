# Compila y corre las pruebas automáticas en Mesen 2 (modo --testrunner, sin ventana)
# Uso:  .\tests\run_tests.ps1
# Deja resultado y capturas en build\test-<modo>-<instrumento>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

& (Join-Path $root 'build.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

$mesen = Join-Path $root 'tools\mesen\Mesen.exe'
if (-not (Test-Path $mesen)) { Write-Host 'No encontre tools\mesen\Mesen.exe (ver README)' -ForegroundColor Red; exit 1 }

# modo, instrumento (0 guitarra, 1 teclado, 2 bajo)
$cases = @(
    @('perfect', 0), @('idle', 0),
    @('perfect', 1), @('idle', 1),
    @('perfect', 2), @('idle', 2)
)

$failed = $false
foreach ($case in $cases) {
    $mode, $instrument = $case
    $out = Join-Path $root "build\test-$mode-$instrument"
    New-Item -ItemType Directory -Force $out | Out-Null
    $env:AUTOPLAY_MODE = $mode
    $env:AUTOPLAY_INSTRUMENT = $instrument
    $env:TEST_OUT = $out
    $p = Start-Process -FilePath $mesen -PassThru -Wait -NoNewWindow -ArgumentList @(
        '--testrunner', "`"$root\build\nesband.nes`"", "`"$root\tests\autoplay.lua`"")
    $result = if (Test-Path "$out\resultado.txt") { (Get-Content "$out\resultado.txt" -Raw).Trim() } else { 'sin resultado' }
    Write-Host "[$mode/$instrument] $result (exit $($p.ExitCode))"
    if ($p.ExitCode -ne 0) { $failed = $true }
}
if ($failed) { exit 1 }
