# NESBand

Un juego de ritmo estilo Guitar Hero / Rock Band para el NES, con canciones de otros juegos de NES.

**Estado actual:** título, menú (canción, jugadores, instrumento y dificultad), juego para **1 o 2
jugadores** con pausa, y pantalla de resultados con precisión, combo máximo y estrellas. Cartucho MMC3
de 256 KB con espacio para 15 canciones; hoy trae 4, importadas desde NSF: *Blaster Master* (Area 1), *Castlevania III* (Beginning),
*Double Dragon* (Mission 1) y *Mega Man 2* (Dr. Wily's Castle). Los charts se generan automáticamente
para guitarra, teclado y bajo en 4 dificultades, y los aciertos y fallos están sincronizados al cuadro con
la música. Si fallas, tu instrumento se calla hasta tu siguiente acierto, como en Rock Band.

## Sobre este proyecto

Todo el código de NESBand lo escribió una IA (Claude). Yo solo pongo las ideas.

**P: ¿Es código generado por IA?**
R: Absolutamente sí, 100%.

**P: ¿Sabes cómo funciona?**
R: Claro que no.

**P: ¿Te importa?**
R: Absolutamente no.

**P: ¿Por qué un NESBand?**
R: Porque parecía lo correcto con las obras maestras que existen en la música del NES.

## Instalación

### Windows

1. **cc65** (ensamblador `ca65` y linker `ld65`): descarga el
   [snapshot de Windows](https://sourceforge.net/projects/cc65/files/cc65-snapshot-win64.zip/download)
   y descomprímelo en `tools/cc65/` (debe quedar `tools/cc65/bin/ca65.exe`).
   Si ya lo tienes en el PATH, también sirve.
2. **Mesen 2** (emulador con el mejor depurador para NES): descarga
   [Mesen 2](https://github.com/SourMesen/Mesen2/releases) y pon `Mesen.exe` en `tools/mesen/`.
   Necesita .NET 8.
3. **FamiStudio** (solo para importar canciones): descarga la versión
   [4.5.3 portable](https://github.com/BleuBleu/FamiStudio/releases/tag/4.5.3)
   y descomprímela en `tools/famistudio/`. Usa la misma versión que el motor de sonido de `src/famistudio/`.
4. **uv** (para las herramientas de Python): [instrucciones](https://docs.astral.sh/uv/getting-started/installation/).
   `uv sync` crea el venv con todo lo necesario.

`tools/` está en `.gitignore`: cada máquina baja sus propias herramientas.

### macOS

```bash
brew install cc65 uv
```

Mesen 2 y FamiStudio tienen versión para macOS en sus páginas de releases. Para FamiStudio, apunta la
variable `FAMISTUDIO` al ejecutable.

## Compilar y jugar

```bash
.\build.ps1
```

En macOS/Linux: `./build.sh`. El resultado es `build/nesband.nes`; ábrelo en Mesen.
Mesen carga solo `build/nesband.dbg`, así que en el depurador verás los nombres
de las variables y las etiquetas del código en lugar de direcciones sueltas.

Compilar la ROM **no** necesita FamiStudio ni Python: la canción ya convertida vive en `src/songs/`.

### Controles

**Menú:** ↑/↓ elige la opción (canción, jugadores, instrumento, dificultad), ←/→ cambia el valor,
Start juega y B regresa al título. Mientras eliges, suena la canción. Con **2 jugadores**, el jugador 2
elige su instrumento y dificultad con el control 2 (su cursor es naranja). No pueden tocar el mismo
instrumento: cada quien silencia su canal al fallar.

**Juego** (modo "tap", un botón por carril, cada jugador con su control):

| Carril   | Botón |
|----------|-------|
| Verde    | ←     |
| Rojo     | ↓     |
| Amarillo | →     |
| Azul     | B     |
| Naranja  | A     |
| Pausa    | Start |
| Salir al menú (en pausa) | Select |

Fácil usa 3 carriles, medio 4, difícil y experto los 5. Start o Select sirven desde cualquiera de los
dos controles.

**Reglas:** presionar un carril sin nota cerca (golpe al aire) rompe el combo y calla tu instrumento,
como el *overstrum* de Guitar Hero. Las **estrellas salen del puntaje** (qué porcentaje del puntaje
máximo posible lograste), no de las notas acertadas: machacando botones se aciertan notas de suerte,
pero el combo nunca sube y el puntaje se queda abajo.

En Mesen configura qué teclas corresponden a cada botón en *Settings → Input*. Para jugar de a dos, el
**puerto 2** debe tener un control de NES conectado (por default Mesen lo deja vacío).

## Importar canciones

Si el NSF trae su `.m3u` (misma carpeta, mismo nombre), basta con el número de pista tal como aparece
en la lista; de ahí salen el título, el juego y la duración:

```bash
uv run nesband import-song "songs_src/Blaster Master [Chou Wakusei Senki - Metafight] (1988-06-17)(Sunsoft).nsf" --track 2 --name blaster_area1
```

Sin `.m3u`, se indica todo a mano (`--song` cuenta desde 0):

```bash
uv run nesband import-song songs_src/megaman2.nsf --name wily --title "Dr. Wily's Castle" --game "Mega Man 2" --duration 75
```

Acepta NSF, proyectos de FamiStudio (`.fms`) y de FamiTracker (`.ftm`). Opciones:

| Opción | Para qué |
|---|---|
| `--track N` | Pista N del `.m3u` (empieza en 1) |
| `--song N` | Canción N del archivo, si no hay `.m3u` (empieza en 0) |
| `--title` / `--game` | Lo que se muestra en el menú (sin acentos; se convierte a mayúsculas) |
| `--duration S` | Solo NSF: cuántos segundos grabar. Un NSF no dice cuándo termina la canción |
| `--beat-frames N` | Cuadros por tiempo, si el tempo detectado sale mal (las líneas de beat no cuadran) |

**Espacio:** cada canción tiene un slot de 16 KB (música + 12 charts + samples). Si no cabe, el
generador graba menos segundos y vuelve a intentar hasta que quepa, y lo avisa ("No cabe con 154 s…
pruebo con 102 s"). En el cartucho caben 15 canciones.

Cada canción importada se agrega a la lista del menú (`src/songs/list.s`, en orden alfabético). Para
quitar una, borra su carpeta en `src/songs/` y corre `uv run nesband list-songs`.

Las opciones con que se importó cada canción quedan en `src/songs/<nombre>/import.json`. Si se mejora el
generador, `uv run nesband reimport` vuelve a importarlas todas igual (o `reimport wily` solo una).

**Chips de sonido extra:** algunos cartuchos japoneses traían sonido adicional (VRC6, Sunsoft 5B…). El
motor solo usa el sonido del NES, así que esas canciones se rechazan con un mensaje. Revisa el NSF y no
el nombre del archivo: el *Castlevania 3 (Akumajou Densetsu)* incluido aquí es el arreglo para el NES
normal y funciona.

Se generan charts de **guitarra** (pulso 1), **teclado** (pulso 2) y **bajo** (triángulo), si el canal
tiene notas. La **batería** (ruido) aún no: necesita su propio criterio.

Qué hace, paso a paso:

1. **FamiStudio** importa el archivo y lo exporta en dos formatos: ensamblador para su motor de sonido
   (`src/songs/<nombre>/music.s`) y texto con cada nota y el cuadro exacto en que suena.
2. **Tempo**: un NSF no trae tempo, así que se estima a partir de los ataques de todas las notas
   (el intervalo más común, duplicado hasta caer entre 100 y 200 BPM).
3. **Charts**, uno por instrumento y dificultad, generados con las notas del canal de cada instrumento:
   - los adornos cuadro por cuadro del driver original (golpes de ataque, barridos de tono, arpegios
     rapidísimos) se juntan en una sola nota que empieza donde empieza el sonido;
   - se quitan notas demasiado juntas, conservando primero las que caen en el tiempo;
   - a cada nota le toca un carril según su altura respecto a sus vecinas, respetando el contorno:
     si la melodía sube, sube el carril; si repite nota, repite carril.
4. Se escribe `src/songs/<nombre>/song.s`, la ficha que lee el juego (título, fin, tempo, charts), y
   se regenera la lista de canciones.

**Dónde van los originales:** pon tus NSF (y sus `.m3u`, que dicen el número, nombre y duración de cada
pista) en `songs_src/`. Esa carpeta no se sube a git: la música de juegos comerciales tiene copyright,
y la ROM no la necesita porque compila con lo ya convertido en `src/songs/`. Ojo: en un `.m3u` las pistas
empiezan en 1 y `--song` empieza en 0.

La canción de ejemplo (*Dr. Wily's Castle*) es la versión de *Mega Man 2* que viene como demo de
FamiStudio. Para volver a generar su NSF:

```bash
.\tools\famistudio\FamiStudio.exe "tools\famistudio\Demo Songs\Mega Man 2.fms" nsf-export songs_src\megaman2.nsf
```

## Música del título y efectos de sonido

Son originales de NESBand y viven como proyectos de FamiStudio en formato texto:

- `audio/titulo.txt`: la pista del título (La menor, 150 BPM, 8 compases que se repiten: melodía en
  el pulso 1, arpegios en el pulso 2, bajo en el triángulo y batería en el ruido).
- `audio/efectos.txt`: los efectos. Cada "canción" del proyecto es un efecto: *Mover* (cursor del
  menú), *Aceptar* (Start) y *Volver* (B).

Para editarlos, ábrelos en FamiStudio (con *Open* o *Import*, según tu versión, eligiendo el `.txt`), y
guárdalos de nuevo como texto (*Export → FamiStudio Text*) sobre el mismo archivo. Luego:

```bash
uv run nesband build-audio
```

Exporta los dos a `src/audio/` y genera las constantes `SFX_...` de cada efecto. Si agregas un
efecto, queda disponible en el código como `SFX_<NOMBRE>` (con `lda #SFX_... / jsr play_sfx`).

## Pruebas

```bash
.\tests\run_tests.ps1
uv run pytest
```

- `run_tests.ps1` corre la ROM en Mesen, sin ventana, con un bot por jugador (`tests/autoplay.lua`)
  que recorre todo: título → menú (elige canción, jugadores, instrumentos y experto) → juego →
  resultados. Por cada canción hace 6 partidas (unos 8 minutos con 4 canciones):
  - 1 jugador **perfecto** con guitarra, teclado y bajo: acierta todo y pausa a media canción. El
    puntaje y los resultados (100%, 5 estrellas) deben ser exactos, y **cada nota del chart debe caer
    en el mismo cuadro en que el motor dispara esa nota** en el canal del jugador (prueba de
    sincronía), también después de la pausa.
  - 1 jugador **sin tocar nada**: todo debe fallar y su canal debe quedar silenciado.
  - 1 jugador **machacando botones**: acierta notas de suerte, pero el combo máximo no pasa de 5 y
    no saca más de 2 estrellas.
  - 2 jugadores **perfectos** (guitarra + bajo).
  - 2 jugadores **mixto**: uno perfecto y el otro sin tocar nada, para comprobar que cada quien lleva
    su propio juego (puntaje, silenciado, resultados).
  - En todas, además: que suene la música del título y que suenen los efectos en el menú y al empezar.
  - Las capturas de cada pantalla quedan en `build/test-<canción>-<caso>/`.
- `pytest` prueba el generador de charts (lectura de FamiStudio, tempo, reducción, carriles).

Requisitos del `settings.json` del Mesen de pruebas: `AllowIoOsAccess: true` (el script de Lua escribe
archivos), `Nes.Port2.Type: "NesController"` (control 2 conectado) y `Nes.AutoConfigureInput: false`.
Si `tools/mesen/` tiene su propio `settings.json`, Mesen corre en modo portable y no toca tu
configuración normal. Ojo con la API de Lua de Mesen 2.1: el control va en el tercer argumento,
`emu.setInput(botones, 0, control)`.

## Cómo está organizado el código

| Archivo | Qué hace |
|---|---|
| `src/main.s` | Arranque (`reset`), ciclo principal con los estados del juego, interrupción de vblank (`nmi`), variables, paletas |
| `src/title.s` | Pantalla de título y el logo |
| `src/menu.s` | Menú de canción, instrumento y dificultad |
| `src/play.s` | Preparar la canción elegida, cada cuadro de juego (por jugador), pausa y fin |
| `src/hud.s` | La franja fija de abajo: aros y marcador de cada jugador |
| `src/results.s` | Pantalla de resultados por jugador: precisión, combo máximo, estrellas |
| `src/text.s` | Escribir textos y números en pantalla |
| `src/highway.s` | La autopista: reloj de la canción, scroll, armado de cada fila de notas |
| `src/gameplay.s` | Control, ventana de acierto, fallos, combo, puntaje |
| `src/audio.s` | Configuración del motor de FamiStudio, arranque/fin de la música, efectos, silenciar al fallar |
| `src/audio/` | Música del título y efectos ya exportados (generados por `nesband build-audio`) |
| `audio/` | Proyectos de FamiStudio (texto) de la música del título y los efectos |
| `src/famistudio/` | Motor de sonido de FamiStudio 4.5.3 (licencia MIT, sin modificar) |
| `src/songs/` | Canciones convertidas (generadas por `nesband import-song`) |
| `src/chr.s` | Los gráficos (tiles) dibujados como texto; la fuente usa el código ASCII como número de tile |
| `src/nes.inc` | Direcciones de los registros del hardware |
| `nes.cfg` | Mapa de memoria del cartucho MMC3 para el linker: dos bancos fijos con el código y 15 slots de canción |
| `pctools/` | Herramientas de PC en Python (`nesband import-song`) |

## Conceptos clave (para ir aprendiendo)

- **El ciclo de cuadro.** El NES dibuja 60 cuadros por segundo. Entre un cuadro y otro hay un ratito,
  el *vblank*, en el que el chip de video (PPU) no está dibujando. Solo en ese momento puedes escribir
  en la memoria de video sin causar basura en pantalla. El PPU avisa con una interrupción, la **NMI**.
  Por eso el juego se divide en dos partes: `main_loop` calcula todo y lo deja en buffers, y `nmi` solo copia.
- **Fondo vs. sprites.** El fondo es una cuadrícula de tiles de 8×8 (la *nametable*, 32×30). Los sprites
  son 64 objetos sueltos, pero el PPU solo dibuja **8 por línea horizontal**. Por eso las notas son parte
  del fondo y lo que se mueve es el *scroll*.
- **Zero page.** Los primeros 256 bytes de RAM son más rápidos de usar y son los únicos que sirven como
  punteros (`lda (ptr),y`). Ahí van las variables más usadas.
- **Todo es memoria.** Video, sonido y controles se manejan leyendo y escribiendo en direcciones fijas
  (`$2000`-`$2007`, `$4000`-`$4017`).
- **El tiempo se mide en cuadros.** La música avanza exactamente un paso por cuadro, y el chart guarda
  el cuadro exacto de cada nota. Por eso juego y música no se desfasan nunca: comparten el mismo reloj.
- **Bancos (mapper MMC3).** El 6502 solo ve 32 KB de cartucho a la vez (`$8000-$FFFF`). El MMC3 deja
  fijos `$8000-$9FFF` y `$E000-$FFFF` (ahí va el código) y permite cambiar qué parte del cartucho se ve
  en `$A000-$DFFF`: al elegir una canción se pone ahí su slot (`select_slot` en `main.s`).
- **El glitch del DPCM.** Cuando suena un sample, el chip de sonido puede "robar" una lectura justo
  cuando el juego lee el control, y aparecen botones fantasma. Por eso `read_pad` lee el control
  hasta que dos lecturas seguidas coinciden.
- **Pantalla dividida.** El MMC3 cuenta scanlines y dispara una interrupción (IRQ) en la línea 200. Ahí
  `irq` cambia a qué parte de la memoria de video apunta el PPU: arriba se ve la autopista
  desplazándose y abajo una franja fija con los aros y el marcador. Para que el MMC3 pueda contar, los
  sprites usan la tabla de patrones de `$1000` y el fondo la de `$0000`.
- **Un jugador a la vez.** Todo lo de un jugador (sus carriles, puntaje, combo, chart) vive en un bloque
  de variables (`pstate`). Cada jugador guarda su copia; `load_player` la trae antes de procesarlo y
  `store_player` la devuelve. Así el mismo código sirve para 1 o 2 jugadores.

### Para aprender 6502 y NES desde cero

- [Famicom Party](https://famicom.party/book/): libro gratis que enseña desde cero con el mismo
  ensamblador (ca65). Es el mejor punto de partida.
- [NESdev Wiki](https://www.nesdev.org/wiki/): la referencia de todo el hardware.
- [Easy 6502](https://skilldrick.github.io/easy6502/): tutorial interactivo del procesador en el navegador.

## Hoja de ruta

1. ~~Prototipo: autopista, notas, aciertos, puntaje~~ ✅
2. ~~Música de verdad: NSF → FamiStudio → motor de sonido, sincronizada al cuadro~~ ✅
3. ~~Generador automático de charts por canal y dificultad~~ ✅ (primera versión)
4. ~~Charts de bajo y teclado~~ ✅ · batería pendiente (necesita su propio criterio: bombo/tarola/platillo por tipo de ruido)
5. ~~Menús: título, selección de canción/instrumento/dificultad, pausa, resultados~~ ✅
6. ~~Mapper con más espacio (MMC3) para muchas canciones~~ ✅ · pantalla de título ilustrada pendiente
   (ver [docs/ideas.md](docs/ideas.md))
7. Editor visual de charts para retocar lo generado
8. ~~2 jugadores~~ ✅ · 4 jugadores con el Four Score (ver [docs/ideas.md](docs/ideas.md)); batería "pro"
   con la Power Pad; modo con rasgueo para un adaptador de guitarra
