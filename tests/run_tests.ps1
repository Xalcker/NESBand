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
param([string[]]$Only = @('*'), [string]$Rom = '', [switch]$NoBuild, [switch]$Rapida, [switch]$Release, [int]$Paralelo = 1)   # (no puede llamarse $Songs: PowerShell no distingue mayúsculas y chocaría con $songs)
$ErrorActionPreference = 'Stop'
$Only = @($Only | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })   # (con pwsh -File, "a,b" llega como un solo texto)
# -Rapida: la demo y 3 canciones representativas (la de chart más grande, una densa y la más chica);
# alcanza para cambios del motor. La corrida completa es para cambios de charts, generador o bancos.
if ($Rapida) { $Only = @('nesband_demo', 'ddragon_mission1', 'cv3_clockwork', 'startropics_boss') }
$root = Split-Path $PSScriptRoot -Parent

# -Release prueba la ROM que se publica (build.ps1 -Release): solo con las canciones que están en git
# (el orden del menú y los números de canción cambian, así que se listan solo esas). Sin -Rapida
# prueba todas; con -Rapida, la demo y una original de cada estilo de instrumento.
if ($Release -and $Rapida) { $Only = @('nesband_demo', 'tormenta', 'salto', 'carrera') }
$LASTEXITCODE = 0
if (-not $NoBuild) { if ($Release) { & (Join-Path $root 'build.ps1') -Release } else { & (Join-Path $root 'build.ps1') } }
if ($LASTEXITCODE -ne 0) { exit 1 }

$version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim()
$romPath = if ($Rom) { $Rom } elseif ($Release) { Join-Path $root "build/release/nesband-v$version.nes" } else { Join-Path $root 'build/nesband.nes' }; $romName = [IO.Path]::GetFileNameWithoutExtension($romPath)   # -Rom permite probar una copia mientras se sigue compilando
# Mesen en tools/mesen según el sistema (las rutas van con /, que Windows también acepta, para correr con pwsh en
# macOS y Linux). $IsMacOS/$IsLinux no existen en Windows PowerShell 5.1: ahí valen $null y queda el .exe
$mesenRel = if ($IsMacOS) { 'tools/mesen/Mesen.app/Contents/MacOS/Mesen' } elseif ($IsLinux) { 'tools/mesen/Mesen' } else { 'tools/mesen/Mesen.exe' }
$mesen = Join-Path $root $mesenRel
if (-not (Test-Path $mesen)) { Write-Host "No encontre $mesenRel (ver README)" -ForegroundColor Red; exit 1 }
# Con un settings.json junto al ejecutable Mesen corre en modo portable (no toca tu configuración normal). Si no
# hay, se crea uno con lo que necesitan las pruebas; Mesen pone los valores por defecto en lo demás
$mesenDir = Split-Path $mesen -Parent
$settings = Join-Path $mesenDir 'settings.json'
if (-not (Test-Path $settings)) {
    # (sin AutoConfigureInput, un settings.json nuevo deja el puerto 1 sin control: hay que declarar los dos)
    [IO.File]::WriteAllText($settings, '{"Debug":{"ScriptWindow":{"AllowIoOsAccess":true}},"Nes":{"AutoConfigureInput":false,"Port1":{"Type":"NesController"},"Port2":{"Type":"NesController"}}}')
    Write-Host "Cree $settings (Mesen portable para las pruebas)"
}

# Canciones en el orden del menú (alfabético, como src/songs/list.s)
$songs = @(Get-ChildItem (Join-Path $root 'src/songs') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'song.s') } | Sort-Object Name)
if ($Release) {
    $versionadas = @(git -C $root ls-files 'src/songs' | Where-Object { $_ -match '^src/songs/[^/]+/song\.s$' } | ForEach-Object { ($_ -split '/')[2] })
    $songs = @($songs | Where-Object { $versionadas -contains $_.Name })
}

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
    # Batería (instrumento 3): solo en las canciones con chart de batería (su drums.json); el bombo es una gema del carril naranja
    @('1p-bateria',    1, 'perfect', 3, 3, 'perfect', 2, 3),
    @('1p-bateria-facil', 1, 'perfect', 3, 0, 'perfect', 2, 0),
    @('1p-bateria-idle', 1, 'idle',  3, 3, 'perfect', 2, 3),
    @('1p-bateria-espejo', 1, 'perfect', 3, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '1000'),   # la batería no se espeja
    @('2p-bateria',    2, 'perfect', 3, 3, 'perfect', 0, 3),
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
    # Opciones (#6): el último texto son 4 dígitos = espejo (0-1), velocidad (0 = 100%, 1 = 75%, 2 = 50%, 3 = 125%),
    # caída de notas (0 = auto, 1-4) y práctica (0 = no, 1-3 = hasta 1/4, 1/2, 3/4; 4 = toda)
    @('1p-espejo',     1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '1000'),
    @('1p-lenta75',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0100'),
    @('1p-lenta50',    1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0200'),
    @('1p-rapida125',  1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0300'),
    @('1p-caida',      1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0010'),
    @('1p-practica',   1, 'fail',    0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0001'),
    # (#16) el quinto dígito es el inicio de la práctica (0 = el principio, 1-3 = 1/4, 1/2, 3/4): hasta 3/4 desde 1/2,
    # y hasta 1/2 pidiendo que empiece en 3/4 (no puede: empieza en el cuarto anterior al final, o sea en 1/4)
    @('1p-inicio',     1, 'fail',    0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '00032'),
    @('1p-inicio-tope', 1, 'fail',   0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '00023'),
    # (#16) el sexto dígito son las marcas de la pausa: 1 = A (inicio, 2 s antes de donde se pausó), 2 = B (final donde se pausó);
    # el bot pausa a mitad de la canción, marca en vez de continuar, y el bucle (hasta 1/2) debe reiniciar con la marca
    @('1p-pausa-practica', 1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '0002'),   # pausa en una práctica: captura con el letrero de las marcas
    @('1p-marca-inicio', 1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '000201'),
    @('1p-marca-final',  1, 'perfect', 0, 3, 'perfect', 2, 3, 0, 0, 0, 0, 0, 0, 0, '000202'),
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
    # ¿tiene chart de batería? (el bit 3 de los instrumentos con chart de su ficha): el menú la ofrece o no
    $ficha = Get-Content (Join-Path $songs[$s].FullName 'song.s') -Raw
    $tieneBateria = $ficha -match '(?m)^\s*\.byte %0000(\d)(\d{3})\s*; instrumentos con chart' -and $Matches[1] -eq '1'
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
        if ($name -like '*bateria*' -and -not $tieneBateria) { continue }
        $caso = @{
            Nombre = "$songName/$name"
            Record = $record
            Out = Join-Path $root "build/test-$songName-$name"
            Env = [ordered]@{
                AUTOPLAY_SONG = "$s"; AUTOPLAY_PLAYERS = "$players"; AUTOPLAY_MODE = "$mode1"
                AUTOPLAY_INSTRUMENT = "$inst1"; AUTOPLAY_DIFFICULTY = "$diff1"; AUTOPLAY_MODE2 = "$mode2"
                AUTOPLAY_INSTRUMENT2 = "$inst2"; AUTOPLAY_DIFFICULTY2 = "$diff2"; AUTOPLAY_STAR = "$star"
                AUTOPLAY_DRUMS = "$([int]$tieneBateria)"; AUTOPLAY_RECORD = "$record"; AUTOPLAY_COOP = "$coop"; AUTOPLAY_VS = "$vs"; AUTOPLAY_CUT = "$cut"
                AUTOPLAY_DOWN = "$down"; AUTOPLAY_REVIVE = "$revive"
                AUTOPLAY_MIRROR = "$($opts[0])"; AUTOPLAY_SPEED = "$($opts[1])"
                AUTOPLAY_FALL = "$($opts[2])"; AUTOPLAY_PRACTICE = "$($opts[3])"; AUTOPLAY_START = "$($opts[4])"; AUTOPLAY_MARK = "$($opts[5])"
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
    Remove-Item "$($caso.Out)/resultado.txt" -ErrorAction SilentlyContinue
    $ventana = if ($IsMacOS -or $IsLinux) { @{} } else { @{ WindowStyle = 'Hidden' } }   # (-WindowStyle solo existe en Windows)
    $p = Start-Process -FilePath $mesen -PassThru @ventana `
        -RedirectStandardOutput "$($caso.Out)/mesen.log" -RedirectStandardError "$($caso.Out)/mesen_err.log" `
        -ArgumentList @('--testrunner', "`"$rom`"", "`"$root/tests/autoplay.lua`"")
    $null = $p.Handle    # (sin esto, PowerShell 5.1 pierde el código de salida de un proceso que no se espera)
    return $p
}

function Informar-Caso($caso, $codigo) {
    $archivo = "$($caso.Out)/resultado.txt"
    $resultado = if (Test-Path $archivo) { (Get-Content $archivo -Raw).Trim() } else { 'sin resultado' }
    Write-Host "[$($caso.Nombre)] $resultado (exit $codigo)"
    if ($codigo -ne 0) { $script:failed = $true }
}

# 1) Los casos independientes, de a $Paralelo a la vez. Cada ranura tiene su copia del ROM (y su .dbg,
#    que Mesen busca junto a él) para que los .sav de récords de uno no se mezclen con los de otro
$saves = Join-Path $mesenDir 'Saves'
$parDir = Join-Path $root 'build/par'
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
