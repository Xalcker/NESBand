# Compila la ROM: src/main.s -> build/nesband.nes (+ nesband.dbg con símbolos para Mesen)
# Uso:  .\build.ps1
#       .\build.ps1 -Release [-Version 0.2.0]
# -Release arma la ROM para publicar: solo con las canciones que están en git (las importadas de
# juegos comerciales no se distribuyen) y la deja en build\release\nesband-v<versión>.nes con su
# suma de verificación (.sha256) y la licencia. La versión sale del archivo VERSION si no se indica.
param([switch]$Release, [string]$Version = '', [switch]$LucesBateria, [switch]$MedidorTransparente, [string[]]$Solo = @(), [string]$Nombre = '')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ($Release -and -not $Version) { $Version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim() }

# Usa el cc65 local (tools/cc65) si existe; si no, el que esté en el PATH
$bin  = Join-Path $root 'tools\cc65\bin'
$ca65 = if (Test-Path "$bin\ca65.exe") { "$bin\ca65.exe" } else { 'ca65' }
$ld65 = if (Test-Path "$bin\ld65.exe") { "$bin\ld65.exe" } else { 'ld65' }

$out = if ($Release) { Join-Path $root 'build\release' } else { Join-Path $root 'build' }
New-Item -ItemType Directory -Force $out | Out-Null

# Lista de canciones (src/songs/list.s): todas las carpetas de src/songs con un song.s, en orden
# alfabético. Se arma en cada compilación porque depende de qué canciones tenga cada quien (las
# importadas de NSF no van en git). Mismo formato que `nesband list-songs`.
$songsDir = Join-Path $root 'src\songs'
function Escribir-Lista($names) {
    if ($names.Count -eq 0) { Write-Host 'No hay canciones en src/songs' -ForegroundColor Red; exit 1 }
    if ($names.Count -gt 31) { Write-Host "Hay $($names.Count) canciones y el cartucho tiene 31 slots: compila un subconjunto con -Solo <patron>[,<patron>] (ej. -Solo mm1_*)" -ForegroundColor Red; exit 1 }
    $list = "; Generado al compilar - lista de canciones de la ROM, en orden alfabetico`n"
    $list += "; Cada cancion va en su slot de 16 KB (ver nes.cfg)`nNUM_SONGS = $($names.Count)`n`n"
    for ($i = 0; $i -lt $names.Count; $i++) {
        $list += "SONG_SLOT_NUMBER .set $i`n.include `"songs/$($names[$i])/song.s`"`n`n"
    }
    $list += ".segment `"RODATA`"`nsong_table:`n"
    foreach ($n in $names) { $list += "    .addr song_$n`n" }
    [IO.File]::WriteAllText((Join-Path $songsDir 'list.s'), $list)
}
$todas = @(Get-ChildItem $songsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'song.s') } |
           Sort-Object Name | ForEach-Object { $_.Name })
if ($Release) {
    # Solo las que git versiona (sus song.s): los originales de NESBand, no lo importado de NSF comerciales
    $versionadas = @(git -C $root ls-files 'src/songs' | Where-Object { $_ -match '^src/songs/[^/]+/song\.s$' } |
                     ForEach-Object { ($_ -split '/')[2] })
    $names = @($todas | Where-Object { $versionadas -contains $_ })
} else {
    $names = $todas
}
# -Solo: solo las canciones que coincidan con algún patrón (ej. -Solo mm1_*), para tener más canciones locales que slots
if ($Solo.Count -gt 0) {
    $names = @($names | Where-Object { $n = $_; @($Solo | Where-Object { $n -like $_ }).Count -gt 0 })
    if ($names.Count -eq 0) { Write-Host "Ninguna cancion coincide con -Solo $($Solo -join ', ')" -ForegroundColor Red; exit 1 }
}
Escribir-Lista $names

# Opciones de compilación (apagadas por defecto; ver src/main.s): -LucesBateria, -MedidorTransparente
$opciones = @()
if ($LucesBateria) { $opciones += '-D', 'DRUM_LIGHTS=1' }
if ($MedidorTransparente) { $opciones += '-D', 'METER_FLICKER=1' }
& $ca65 (Join-Path $root 'src\main.s') @opciones -g -I (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src\famistudio') -o "$out\main.o"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al ensamblar' -ForegroundColor Red; exit 1 }

$base = if ($Release) { "nesband-v$Version" } elseif ($Solo.Count -gt 0) { if ($Nombre) { "nesband-$Nombre" } else { 'nesband-solo' } } else { 'nesband' }   # (con -Solo: build\nesband-solo.nes, para no pisar la ROM completa)
& $ld65 -C (Join-Path $root 'nes.cfg') "$out\main.o" -o "$out\$base.nes" --dbgfile "$out\$base.dbg" -m "$out\$base.map"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al enlazar' -ForegroundColor Red; exit 1 }

if ($Release) {
    # Suma de verificación (formato de sha256sum: "hash  archivo") y la licencia junto a la ROM
    $hash = (Get-FileHash "$out\$base.nes" -Algorithm SHA256).Hash.ToLower()
    [IO.File]::WriteAllText("$out\$base.nes.sha256", "$hash  $base.nes`n")
    Copy-Item (Join-Path $root 'LICENSE') "$out\LICENSE" -Force
    if ($todas.Count -le 31) { Escribir-Lista $todas }      # la lista de las compilaciones normales vuelve a tener todas las canciones locales (si caben)
    Write-Host "ROM de release ($($names.Count) canciones): $out\$base.nes" -ForegroundColor Green
    Write-Host "SHA-256: $hash"
} else {
    Write-Host "Listo: $out\$base.nes" -ForegroundColor Green
}
