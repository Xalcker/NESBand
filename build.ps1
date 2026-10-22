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

# Lista de canciones (src/songs/list.s): todas las carpetas de src/songs con un song.s, en orden
# alfabético. Se arma en cada compilación porque depende de qué canciones tenga cada quien (las
# importadas de NSF no van en git). Mismo formato que `nesband list-songs`.
$songsDir = Join-Path $root 'src\songs'
$names = @(Get-ChildItem $songsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'song.s') } |
           Sort-Object Name | ForEach-Object { $_.Name })
if ($names.Count -eq 0) { Write-Host 'No hay canciones en src/songs' -ForegroundColor Red; exit 1 }
if ($names.Count -gt 15) { Write-Host "Hay $($names.Count) canciones y el cartucho tiene 15 slots" -ForegroundColor Red; exit 1 }
$list = "; Generado al compilar - lista de canciones de la ROM, en orden alfabetico`n"
$list += "; Cada cancion va en su slot de 16 KB (ver nes.cfg)`nNUM_SONGS = $($names.Count)`n`n"
for ($i = 0; $i -lt $names.Count; $i++) {
    $list += "SONG_SLOT_NUMBER .set $i`n.include `"songs/$($names[$i])/song.s`"`n`n"
}
$list += ".segment `"RODATA`"`nsong_table:`n"
foreach ($n in $names) { $list += "    .addr song_$n`n" }
[IO.File]::WriteAllText((Join-Path $songsDir 'list.s'), $list)

& $ca65 (Join-Path $root 'src\main.s') -g -I (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src\famistudio') -o "$out\main.o"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al ensamblar' -ForegroundColor Red; exit 1 }

& $ld65 -C (Join-Path $root 'nes.cfg') "$out\main.o" -o "$out\nesband.nes" --dbgfile "$out\nesband.dbg" -m "$out\nesband.map"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al enlazar' -ForegroundColor Red; exit 1 }

Write-Host "Listo: $out\nesband.nes" -ForegroundColor Green
