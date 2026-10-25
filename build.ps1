# Compila la ROM: src/main.s -> build/nesband.nes (+ nesband.dbg con símbolos para Mesen)
# Uso:  .\build.ps1
#       .\build.ps1 -Release [-Version 0.2.0]
# -Release arma la ROM para publicar: solo con las canciones que están en git (las importadas de
# juegos comerciales no se distribuyen) y la deja en build\release\nesband-v<versión>.nes con su
# suma de verificación (.sha256) y la licencia. La versión sale del archivo VERSION si no se indica.
# -Fuente ruta.pf usa una fuente de 8x8 de tu equipo (.pf de Fonts_MiSTer o .ttf de 8 px), solo para tu copia:
# necesita uv, y -Release la ignora siempre.
# -Nombre prueba deja build/nesband-prueba.nes sin pisar build/nesband.nes (con o sin -Solo).
param([switch]$Release, [string]$Version = '', [switch]$LucesBateria, [switch]$MedidorTransparente, [string[]]$Solo = @(), [string]$Nombre = '', [string]$Fuente = '')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ($Release -and -not $Version) { $Version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim() }

# Usa el cc65 local (tools/cc65) si existe; si no, el que esté en el PATH. Las rutas van con / para que el
# mismo script sirva con pwsh en macOS y Linux (Windows también las acepta)
$bin  = Join-Path $root 'tools/cc65/bin'
function Buscar-Cc65($nombre) {
    foreach ($exe in "$nombre.exe", $nombre) { if (Test-Path (Join-Path $bin $exe) -PathType Leaf) { return Join-Path $bin $exe } }
    return $nombre
}
$ca65 = Buscar-Cc65 'ca65'
$ld65 = Buscar-Cc65 'ld65'

$out = if ($Release) { Join-Path $root 'build/release' } else { Join-Path $root 'build' }
New-Item -ItemType Directory -Force $out | Out-Null

# Lista de canciones (src/songs/list.s): todas las carpetas de src/songs con un song.s, en orden
# alfabético. Se arma en cada compilación porque depende de qué canciones tenga cada quien (las
# importadas de NSF no van en git). Mismo formato que `nesband list-songs`.
$songsDir = Join-Path $root 'src/songs'
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
$Solo = @($Solo | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })   # (con pwsh -File, "a,b" llega como un solo texto)
if ($Solo.Count -gt 0) {
    $names = @($names | Where-Object { $n = $_; @($Solo | Where-Object { $n -like $_ }).Count -gt 0 })
    if ($names.Count -eq 0) { Write-Host "Ninguna cancion coincide con -Solo $($Solo -join ', ')" -ForegroundColor Red; exit 1 }
}
Escribir-Lista $names

# Opciones de compilación (apagadas por defecto; ver src/main.s): -LucesBateria, -MedidorTransparente
$opciones = @()
if ($LucesBateria) { $opciones += '-D', 'DRUM_LIGHTS=1' }
if ($MedidorTransparente) { $opciones += '-D', 'METER_FLICKER=1' }
# Fuente privada (#21): se convierte a build/font_private.s, que src/chr.s incluye con PRIVATE_FONT
if ($Fuente -and $Release) {
    Write-Host 'La ROM de release usa siempre la fuente por defecto: ignoro -Fuente' -ForegroundColor Yellow
} elseif ($Fuente) {
    if (-not (Test-Path $Fuente -PathType Leaf)) { Write-Host "No encontre la fuente $Fuente" -ForegroundColor Red; exit 1 }
    $rutaFuente = (Resolve-Path $Fuente).Path
    $conPillow = if ($rutaFuente -like '*.ttf') { @('--with', 'pillow') } else { @() }
    & uv run --project $root @conPillow nesband build-font --fuente $rutaFuente --out (Join-Path $root 'build/font_private.s')
    if ($LASTEXITCODE -ne 0) { Write-Host 'Error al convertir la fuente' -ForegroundColor Red; exit 1 }
    $opciones += '-D', 'PRIVATE_FONT=1', '-I', (Join-Path $root 'build')
}
& $ca65 (Join-Path $root 'src/main.s') @opciones -g -I (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src') --bin-include-dir (Join-Path $root 'src/famistudio') -o "$out/main.o"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al ensamblar' -ForegroundColor Red; exit 1 }

$base = if ($Release) { "nesband-v$Version" } elseif ($Nombre) { "nesband-$Nombre" } elseif ($Solo.Count -gt 0) { 'nesband-solo' } else { 'nesband' }   # (con -Nombre o -Solo: otro archivo, para no pisar build/nesband.nes)
& $ld65 -C (Join-Path $root 'nes.cfg') "$out/main.o" -o "$out/$base.nes" --dbgfile "$out/$base.dbg" -m "$out/$base.map"
if ($LASTEXITCODE -ne 0) { Write-Host 'Error al enlazar' -ForegroundColor Red; exit 1 }

if ($Release) {
    # Comprobación: el .dbg lista cada archivo que entró a la ROM; una fuente privada nunca se publica
    if (Select-String -Path "$out/$base.dbg" -Pattern 'font_private' -SimpleMatch -Quiet) {
        Remove-Item "$out/$base.nes"
        Write-Host 'La ROM de release incluye una fuente privada (font_private.s): no se publica' -ForegroundColor Red; exit 1
    }
    # Suma de verificación (formato de sha256sum: "hash  archivo") y la licencia junto a la ROM
    $hash = (Get-FileHash "$out/$base.nes" -Algorithm SHA256).Hash.ToLower()
    [IO.File]::WriteAllText("$out/$base.nes.sha256", "$hash  $base.nes`n")
    Copy-Item (Join-Path $root 'LICENSE') "$out/LICENSE" -Force
    if ($todas.Count -le 31) { Escribir-Lista $todas }      # la lista de las compilaciones normales vuelve a tener todas las canciones locales (si caben)
    Write-Host "ROM de release ($($names.Count) canciones): $out/$base.nes" -ForegroundColor Green
    Write-Host "SHA-256: $hash"
} else {
    Write-Host "Listo: $out/$base.nes" -ForegroundColor Green
}
