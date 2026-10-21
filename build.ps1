# Compila la ROM: src/main.s -> build/nesband.nes (+ nesband.dbg con símbolos para Mesen)
# Uso:  .\build.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Usa el cc65 local (tools/cc65) si existe; si no, el que esté en el PATH
$bin  = Join-Path $root 'tools\cc65\bin'
$ca65 = if (Test-Path "$bin\ca65.exe") { "$bin\ca65.exe" } else { 'ca65' }
$ld65 = if (Test-Path "$bin\ld65.exe") { "$bin\ld65.exe" } else { 'ld65' }

$out = Join-Path $root 'build'
New-Item -ItemType Directory -Force $out | Out-Null

& $ca65 (Join-Path $root 'src\main.s') -g -I (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src\famistudio') -o "$out\main.o"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al ensamblar' -ForegroundColor Red; exit 1 }

& $ld65 -C (Join-Path $root 'nes.cfg') "$out\main.o" -o "$out\nesband.nes" --dbgfile "$out\nesband.dbg" -m "$out\nesband.map"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al enlazar' -ForegroundColor Red; exit 1 }

Write-Host "Listo: $out\nesband.nes" -ForegroundColor Green
