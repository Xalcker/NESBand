# Compila y corre las pruebas automáticas en Mesen 2 (modo --testrunner, sin ventana)
# Uso:  .\tests\run_tests.ps1                       (todas las canciones)
#       .\tests\run_tests.ps1 -Only wily,cv3_*      (solo esas canciones; acepta comodines)
# Por cada canción:
#   1 jugador: juego perfecto con guitarra, teclado y bajo (en experto), uno en fácil (la
#              autopista más lenta), una partida sin tocar nada y una machacando botones
#              (el combo y las estrellas no deben subir)
#   2 jugadores: los dos perfectos (guitarra + bajo); uno perfecto con el otro sin tocar
#                (teclado + guitarra), para comprobar que cada quien lleva su propio juego;
#                y fácil + experto (la autopista va a la velocidad de experto)
# Deja resultado y capturas en build\test-<cancion>-<caso>
param([string[]]$Only = @('*'), [string]$Rom = '', [switch]$NoBuild, [switch]$Rapida)   # (no puede llamarse $Songs: PowerShell no distingue mayúsculas y chocaría con $songs)
$ErrorActionPreference = 'Stop'
# -Rapida: la demo y 3 canciones representativas (la de chart más grande, una densa y la más chica);
# alcanza para cambios del motor. La corrida completa es para cambios de charts, generador o bancos.
if ($Rapida) { $Only = @('nesband_demo', 'ddragon_mission1', 'cv3_clockwork', 'startropics_boss') }
$root = Split-Path $PSScriptRoot -Parent

$LASTEXITCODE = 0; if (-not $NoBuild) { & (Join-Path $root 'build.ps1') }
if ($LASTEXITCODE -ne 0) { exit 1 }

$romPath = if ($Rom) { $Rom } else { Join-Path $root 'build\nesband.nes' }; $romName = [IO.Path]::GetFileNameWithoutExtension($romPath)   # -Rom permite probar una copia mientras se sigue compilando
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
    @('1p-humano90',   1, 'human90', 0, 3, 'perfect', 2, 3),
    @('1p-humano50',   1, 'human50', 0, 3, 'perfect', 2, 3),
    @('2p-perfect',    2, 'perfect', 0, 3, 'perfect', 2, 3),
    @('2p-mixto',      2, 'perfect', 1, 3, 'idle',    0, 3, 0, 0, 0, 1),
    @('2p-velocidades', 2, 'perfect', 0, 0, 'perfect', 2, 3, 0, 0, 1),   # Co-Op: en VS la dificultad es la misma
    @('2p-vs-facil',   2, 'perfect', 0, 0, 'perfect', 2, 0, 0, 0, 0, 0),
    @('1p-fallo',      1, 'fail',    0, 3, 'perfect', 2, 3),
    # (el antiguo 2p-fallo, uno pierde y el otro sigue, ahora es 2p-vs-pierde2: en VS la partida se corta)
    @('1p-estrella',   1, 'perfect', 0, 3, 'perfect', 2, 3, 1),
    @('2p-estrella',   2, 'perfect', 0, 3, 'perfect', 2, 3, 1),
    # VS: quién gana (el último número: 1 = J1, 2 = J2, 3 = empate; 2p-mixto ya revisa que gane J1)
    @('2p-vs-gana2',   2, 'idle',    0, 3, 'perfect', 2, 3, 0, 0, 0, 2),
    @('2p-vs-empate',  2, 'idle',    0, 3, 'idle',    2, 3, 0, 0, 0, 3),
    # VS con fallo: si uno pierde, la partida se corta y gana el otro (el último 1 = se corta)
    @('2p-vs-pierde1', 2, 'fail',    0, 3, 'perfect', 2, 3, 0, 0, 0, 2, 1),
    @('2p-vs-pierde2', 2, 'perfect', 0, 3, 'fail',    2, 3, 0, 0, 0, 1, 1),
    # VS con el mismo instrumento (mismo chart y canal): perfectos = empate; sin tocar, el canal se calla
    @('2p-vs-mismo',   2, 'perfect', 0, 3, 'perfect', 0, 3, 0, 0, 0, 3),
    @('2p-vs-mismo-idle', 2, 'idle', 0, 3, 'idle',    0, 3, 0, 0, 0, 3),
    # Co-Op (el penúltimo número: 1 = banda): puntaje, combo y poder estelar compartidos
    @('2p-coop',       2, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 1),
    @('2p-coop-estrella', 2, 'perfect', 0, 3, 'perfect', 2, 3, 1, 0, 1),
    @('2p-coop-fallo', 2, 'fail',    0, 3, 'fail',    2, 3, 0, 0, 1),
    # Récords (solo con la canción de ejemplo, y en este orden: el segundo usa lo que guardó el primero)
    @('1p-record1',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 1),
    @('1p-record2',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 2)
)

$failed = $false
for ($s = 0; $s -lt $songs.Count; $s++) {
    $songName = $songs[$s].Name
    if (-not ($Only | Where-Object { $songName -like $_ })) { continue }
    foreach ($kind in $kinds) {
        $name, $players, $mode1, $inst1, $diff1, $mode2, $inst2, $diff2, $star, $record, $coop, $vs, $cut = $kind
        if (-not $cut) { $cut = 0 }     # 1 = en VS la partida debe cortarse porque un jugador pierde
        if (-not $coop) { $coop = 0 }   # 1 = modo Co-Op
        if (-not $vs) { $vs = 0 }       # en VS, quién debe ganar (1, 2 o 3 = empate)
        if (-not $star) { $star = 0 }   # 1 = los jugadores perfectos activan el poder estelar con Select
        if (-not $record) { $record = 0 }   # 1 = escribe iniciales y comprueba el .sav, 2 = comprueba que sigue ahí
        if ($record -and $songName -ne 'nesband_demo') { continue }
        # Cada caso empieza con los récords vacíos, salvo el que comprueba que sobrevivieron
        if ($record -ne 2) { Remove-Item (Join-Path $root "tools\mesen\Saves\$romName.sav") -ErrorAction SilentlyContinue }
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
        $env:AUTOPLAY_STAR = $star
        $env:AUTOPLAY_RECORD = $record
        $env:AUTOPLAY_COOP = $coop
        $env:AUTOPLAY_VS = $vs
        $env:AUTOPLAY_CUT = $cut
        $env:TEST_OUT = $out
        $p = Start-Process -FilePath $mesen -PassThru -Wait -NoNewWindow -ArgumentList @(
            '--testrunner', "`"$romPath`"", "`"$root\tests\autoplay.lua`"")
        $result = if (Test-Path "$out\resultado.txt") { (Get-Content "$out\resultado.txt" -Raw).Trim() } else { 'sin resultado' }
        Write-Host "[$($songs[$s].Name)/$name] $result (exit $($p.ExitCode))"
        if ($p.ExitCode -ne 0) { $failed = $true }
    }
}
if ($failed) { exit 1 }
