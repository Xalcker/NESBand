# NESBand

Un juego de ritmo estilo Guitar Hero / Rock Band para el NES, con canciones de otros juegos de NES.

**Estado actual:** suena *Dr. Wily's Castle* (Mega Man 2) importada desde un NSF, con charts generados
automáticamente en 4 dificultades. Hay autopista de 5 carriles, aciertos y fallos sincronizados al cuadro
con la música, combo, multiplicador y puntaje. Si fallas, tu instrumento se calla hasta tu siguiente
acierto, como en Rock Band.

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

### Controles (modo "tap", un botón por carril)

| Carril   | Botón |
|----------|-------|
| Verde    | ←     |
| Rojo     | ↓     |
| Amarillo | →     |
| Azul     | B     |
| Naranja  | A     |
| Reiniciar | Start |
| Cambiar dificultad (y reiniciar) | Select |

La dificultad aparece arriba a la izquierda: 1 = fácil (3 carriles), 2 = medio (4), 3 = difícil, 4 = experto.
En Mesen configura qué teclas corresponden a cada botón en *Settings → Input*.

## Importar canciones

```bash
uv run nesband import-song songs_src/megaman2.nsf --name wily --duration 75
```

Acepta NSF, proyectos de FamiStudio (`.fms`) y de FamiTracker (`.ftm`). Opciones útiles:

| Opción | Para qué |
|---|---|
| `--song N` | Canción N del archivo (un NSF trae todas las del juego; empieza en 0) |
| `--duration S` | Solo NSF: cuántos segundos grabar. Un NSF no dice cuándo termina la canción |
| `--instrument X` | `guitarra` (pulso 1), `teclado` (pulso 2), `bajo` (triángulo) o `bateria` (ruido) |
| `--beat-frames N` | Cuadros por tiempo, si el tempo detectado sale mal (las líneas de beat no cuadran) |

Qué hace, paso a paso:

1. **FamiStudio** importa el archivo y lo exporta en dos formatos: ensamblador para su motor de sonido
   (`src/songs/<nombre>/music.s`) y texto con cada nota y el cuadro exacto en que suena.
2. **Tempo**: un NSF no trae tempo, así que se estima a partir de los ataques de todas las notas
   (el intervalo más común, duplicado hasta caer entre 100 y 200 BPM).
3. **Charts**, uno por dificultad, generados con las notas del canal del instrumento:
   - se quitan notas demasiado juntas, conservando primero las que caen en el tiempo;
   - a cada nota le toca un carril según su altura respecto a sus vecinas, respetando el contorno:
     si la melodía sube, sube el carril; si repite nota, repite carril.
4. Se escribe `src/songs/<nombre>/song.s` con los datos que necesita el juego (inicio, fin, tempo,
   canal a silenciar) y la canción queda seleccionada en `src/songs/current.s`.

`songs_src/megaman2.nsf` es la versión de *Mega Man 2* que viene como demo de FamiStudio, exportada a NSF
para simular un rip. Ojo: la música de juegos comerciales tiene copyright; esto es un proyecto fan.

## Pruebas

```bash
.\tests\run_tests.ps1
uv run pytest
```

- `run_tests.ps1` corre la ROM en Mesen, sin ventana, con un bot (`tests/autoplay.lua`):
  - **perfect**: acierta todas las notas; el puntaje debe ser exacto y **cada nota del chart debe caer en
    el mismo cuadro en que el motor dispara esa nota** en el canal del jugador (prueba de sincronía).
  - **idle**: no toca nada; todo debe fallar y el canal del jugador debe quedar silenciado.
  - Las capturas de pantalla quedan en `build/test-*/`.
- `pytest` prueba el generador de charts (lectura de FamiStudio, tempo, reducción, carriles).

Requisito de Mesen: el script de Lua necesita permiso para escribir archivos (`AllowIoOsAccess: true` en
el `settings.json`). Si `tools/mesen/` tiene su propio `settings.json`, Mesen corre en modo portable y no
toca tu configuración normal.

## Cómo está organizado el código

| Archivo | Qué hace |
|---|---|
| `src/main.s` | Arranque (`reset`), ciclo principal, interrupción de vblank (`nmi`), variables, paletas |
| `src/highway.s` | La autopista: reloj de la canción, scroll, armado de cada fila de notas |
| `src/gameplay.s` | Control, ventana de acierto, fallos, combo, puntaje |
| `src/hud.s` | Sprites: aros de golpe y marcador |
| `src/audio.s` | Configuración del motor de FamiStudio, arranque/fin de la música, silenciar al fallar |
| `src/famistudio/` | Motor de sonido de FamiStudio 4.5.3 (licencia MIT, sin modificar) |
| `src/songs/` | Canciones convertidas (generadas por `nesband import-song`) |
| `src/chr.s` | Los gráficos (tiles), dibujados como texto |
| `src/nes.inc` | Direcciones de los registros del hardware |
| `nes.cfg` | Mapa de memoria del cartucho (NROM-256) para el linker |
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

### Para aprender 6502 y NES desde cero

- [Famicom Party](https://famicom.party/book/): libro gratis que enseña desde cero con el mismo
  ensamblador (ca65). Es el mejor punto de partida.
- [NESdev Wiki](https://www.nesdev.org/wiki/): la referencia de todo el hardware.
- [Easy 6502](https://skilldrick.github.io/easy6502/): tutorial interactivo del procesador en el navegador.

## Hoja de ruta

1. ~~Prototipo: autopista, notas, aciertos, puntaje~~ ✅
2. ~~Música de verdad: NSF → FamiStudio → motor de sonido, sincronizada al cuadro~~ ✅
3. ~~Generador automático de charts por canal y dificultad~~ ✅ (primera versión)
4. Charts de bajo, teclado y batería (la batería necesita su propio criterio: bombo/tarola/platillo por tipo de ruido)
5. Editor visual de charts para retocar lo generado
6. Menús: selección de canción, instrumento y dificultad; pantalla de resultados
7. Mapper con más espacio (MMC3 o similar) para muchas canciones
8. Multijugador con el Four Score; batería "pro" con la Power Pad; modo con rasgueo para un adaptador de guitarra
