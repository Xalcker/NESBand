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
#
# -Paralelo N corre N casos a la vez (cada uno es un Mesen con su propio ROM copiado a build\par, así que sus
# .sav no se mezclan); con 6 núcleos,-Paralelo 6 baja la corrida completa de ~4 horas a ~45 minutos. Los casos de
# récords van siempre de uno en uno, después. Sin -Paralelo corre de uno en uno.
param([string[]]$Only = @('*'), [string]$Rom = '', [switch]$NoBuild, [switch]$Rapida, [int]$Paralelo = 1)   # (no puede llamarse $Songs: PowerShell no distingue mayúsculas y chocaría con $songs)
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
    # Co-Op con un caído: el jugador 2 cae y el 1 sigue; y el 1 lo revive con media barra de poder
    @('2p-coop-cae',   2, 'perfect', 0, 3, 'fail',    2, 3, 0, 0, 1, 0, 0, 1),
    @('2p-coop-revive', 2, 'perfect', 0, 3, 'fail',   2, 3, 0, 0, 1, 0, 0, 0, 1),
    # Opciones (#6): el último texto son 4 dígitos = espejo (0-1), velocidad (0 = 100%, 1 = 75%, 2 = 50%),
    # caída de notas (0 = auto, 1-4) y práctica (0 = no, 1-3 = hasta 1/4, 1/2, 3/4; 4 = toda)
    @('1p-espejo',     1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '1000'),
    @('1p-lenta75',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0100'),
    @('1p-lenta50',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0200'),
    @('1p-caida',      1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0010'),
    @('1p-practica',   1, 'fail',    0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0001'),
    @('2p-vs-espejo',  2, 'perfect', 0, 3, 'perfect', 0, 3, 0, 0, 0, 3, 0, 0, 0, '1000'),   # mismo chart y mismo espejo: empate
    # Récords (solo con la canción de ejemplo, y en este orden: el segundo usa lo que guardó el primero)
    @('1p-record1',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 1),
    @('1p-record2',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 2)
)

$failed = $false

# Los casos: cada uno con las variables de entorno que lee tests/autoplay.lua
$trabajos = @()     # los que pueden correr a la vez (cada uno con su copia del ROM y su .sav)
$registros = @()    # los de récords: se pasan el .sav uno al otro, así que van de uno en uno y en orden
for ($s = 0; $s -lt $songs.Count; $s++) {
    $songName = $songs[$s].Name
    if (-not ($Only | Where-Object { $songName -like $_ })) { continue }
    foreach ($kind in $kinds) {
        $name, $players, $mode1, $inst1, $diff1, $mode2, $inst2, $diff2, $star, $record, $coop, $vs, $cut, $down, $revive, $opts = $kind
        if (-not $opts) { $opts = '0000' }   # espejo, velocidad, caída, práctica (ver los casos de opciones)
        if (-not $down) { $down = 0 }       # 1 = en Co-Op el jugador 2 cae y el 1 sigue hasta el final
        if (-not $revive) { $revive = 0 }   # 1 = y el jugador 1 lo revive con poder estelar
        if (-not $cut) { $cut = 0 }     # 1 = en VS la partida debe cortarse porque un jugador pierde
        if (-not $coop) { $coop = 0 }   # 1 = modo Co-Op
        if (-not $vs) { $vs = 0 }       # en VS, quién debe ganar (1, 2 o 3 = empate)
        if (-not $star) { $star = 0 }   # 1 = los jugadores perfectos activan el poder estelar con Select
        if (-not $record) { $record = 0 }   # 1 = escribe iniciales y comprueba el .sav, 2 = comprueba que sigue ahí
        if ($record -and $songName -ne 'nesband_demo') { continue }
        $caso = @{
            Nombre = "$songName/$name"
            Record = $record
            Out = Join-Path $root "build\test-$songName-$name"
            Env = [ordered]@{
                AUTOPLAY_SONG = "$s"; AUTOPLAY_PLAYERS = "$players"; AUTOPLAY_MODE = "$mode1"
                AUTOPLAY_INSTRUMENT = "$inst1"; AUTOPLAY_DIFFICULTY = "$diff1"; AUTOPLAY_MODE2 = "$mode2"
                AUTOPLAY_INSTRUMENT2 = "$inst2"; AUTOPLAY_DIFFICULTY2 = "$diff2"; AUTOPLAY_STAR = "$star"
                AUTOPLAY_RECORD = "$record"; AUTOPLAY_COOP = "$coop"; AUTOPLAY_VS = "$vs"; AUTOPLAY_CUT = "$cut"
                AUTOPLAY_DOWN = "$down"; AUTOPLAY_REVIVE = "$revive"
                AUTOPLAY_MIRROR = "$($opts[0])"; AUTOPLAY_SPEED = "$($opts[1])"
                AUTOPLAY_FALL = "$($opts[2])"; AUTOPLAY_PRACTICE = "$($opts[3])"
            }
        }
        if ($record) { $registros += $caso } else { $trabajos += $caso }
    }
}

# Lanza Mesen con un ROM (sin esperarlo) para un caso y devuelve el proceso
function Iniciar-Caso($caso, $rom) {
    foreach ($k in $caso.Env.Keys) { Set-Item -Path "env:$k" -Value $caso.Env[$k] }
    $env:TEST_OUT = $caso.Out
    New-Item -ItemType Directory -Force $caso.Out | Out-Null
    Remove-Item "$($caso.Out)\resultado.txt" -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $mesen -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput "$($caso.Out)\mesen.log" -RedirectStandardError "$($caso.Out)\mesen_err.log" `
        -ArgumentList @('--testrunner', "`"$rom`"", "`"$root\tests\autoplay.lua`"")
    $null = $p.Handle    # (sin esto, PowerShell 5.1 pierde el código de salida de un proceso que no se espera)
    return $p
}

function Informar-Caso($caso, $codigo) {
    $archivo = "$($caso.Out)\resultado.txt"
    $resultado = if (Test-Path $archivo) { (Get-Content $archivo -Raw).Trim() } else { 'sin resultado' }
    Write-Host "[$($caso.Nombre)] $resultado (exit $codigo)"
    if ($codigo -ne 0) { $script:failed = $true }
}

# 1) Los casos independientes, de a $Paralelo a la vez. Cada ranura tiene su copia del ROM (y su .dbg,
#    que Mesen busca junto a él) para que los .sav de récords de uno no se mezclen con los de otro
$saves = Join-Path $root 'tools\mesen\Saves'
$parDir = Join-Path $root 'build\par'
$dbgOrigen = [IO.Path]::ChangeExtension($romPath, '.dbg')
if ($trabajos.Count -gt 0) {
    New-Item -ItemType Directory -Force $parDir | Out-Null
    $libres = New-Object System.Collections.Generic.Queue[int]
    for ($i = 0; $i -lt [Math]::Max(1, $Paralelo); $i++) {
        Copy-Item $romPath (Join-Path $parDir "par$i.nes") -Force
        if (Test-Path $dbgOrigen) { Copy-Item $dbgOrigen (Join-Path $parDir "par$i.dbg") -Force }
        $libres.Enqueue($i)
    }
    $cola = New-Object System.Collections.Generic.Queue[object]
    $trabajos | ForEach-Object { $cola.Enqueue($_) }
    $corriendo = @()
    while ($cola.Count -gt 0 -or $corriendo.Count -gt 0) {
        while ($cola.Count -gt 0 -and $libres.Count -gt 0) {
            $caso = $cola.Dequeue()
            $ranura = $libres.Dequeue()
            Remove-Item (Join-Path $saves "par$ranura.sav") -ErrorAction SilentlyContinue   # cada caso empieza con los récords vacíos
            $p = Iniciar-Caso $caso (Join-Path $parDir "par$ranura.nes")
            $corriendo += , @{ Proceso = $p; Caso = $caso; Ranura = $ranura }
        }
        Start-Sleep -Milliseconds 250
        $siguen = @()
        foreach ($c in $corriendo) {
            if ($c.Proceso.HasExited) {
                Informar-Caso $c.Caso $c.Proceso.ExitCode
                $libres.Enqueue($c.Ranura)
            } else {
                $siguen += , $c
            }
        }
        $corriendo = $siguen
    }
}

# 2) Los de récords, de uno en uno con el ROM de siempre (el segundo usa lo que guardó el primero)
foreach ($caso in $registros) {
    if ($caso.Env.AUTOPLAY_RECORD -ne '2') { Remove-Item (Join-Path $saves "$romName.sav") -ErrorAction SilentlyContinue }
    $p = Iniciar-Caso $caso $romPath
    $p.WaitForExit()
    Informar-Caso $caso $p.ExitCode
}
if ($failed) { exit 1 }
