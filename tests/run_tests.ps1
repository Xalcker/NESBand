# Compila y corre las pruebas automáticas en Mesen 2 (modo --testrunner, sin ventana)
# Uso:  .\tests\run_tests.ps1
# Deja resultado y capturas en build\test-perfect y build\test-idle
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

& (Join-Path $root 'build.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

$mesen = Join-Path $root 'tools\mesen\Mesen.exe'
if (-not (Test-Path $mesen)) { Write-Host 'No encontré tools\mesen\Mesen.exe (ver README)' -ForegroundColor Red; exit 1 }

$failed = $false
foreach ($mode in 'perfect', 'idle') {
    $out = Join-Path $root "build\test-$mode"
    New-Item -ItemType Directory -Force $out | Out-Null
    $env:AUTOPLAY_MODE = $mode
    $env:TEST_OUT = $out
    $p = Start-Process -FilePath $mesen -PassThru -Wait -NoNewWindow -ArgumentList @(
        '--testrunner', "`"$root\build\nesband.nes`"", "`"$root\tests\autoplay.lua`"")
    $result = if (Test-Path "$out\resultado.txt") { (Get-Content "$out\resultado.txt" -Raw).Trim() } else { 'sin resultado' }
    Write-Host "[$mode] $result (exit $($p.ExitCode))"
    if ($p.ExitCode -ne 0) { $failed = $true }
}
if ($failed) { exit 1 }
