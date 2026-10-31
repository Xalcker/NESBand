# Paridad entre versiones

NESBand es el original y la referencia de reglas. Este documento compara las versiones para saber qué le falta a cada una
cuando una mejora entra en alguna.

Versiones: **NES** (NESBand, ensamblador 6502), **GB** (GBBand, ensamblador SM83), **GEN** (GENBand, C con SGDK),
**NG** (NGBand, C con ngdevkit; driver Z80 con SDCC). La futura (SNES) agrega una columna.

> **Regla:** al terminar una mejora en cualquier versión, actualiza este archivo (la fila y la columna) y agrega en
> "Pendientes por versión" lo que falta en las otras. Al cerrar un pendiente, táchalo aquí.

Leyenda: ✅ lo tiene · ❌ falta · 🟡 parcial o por confirmar · n/a no aplica a esa plataforma.

Última revisión: 2026-10-30 (herramientas de PC: bandcore, importadores de GB). Versiones revisadas: NES v0.3.2,
GB v0.0.1 (fase 4), GEN v0.4.0, NG v0.1.0. Esta primera tabla salió de
leer los README, la documentación y el código de los tres repos; los 🟡 son lo que no se pudo confirmar.
NG: ✅ solo donde pasa un caso del arnés de MAME (`tests/run_tests.sh`); 🟡 si está hecho pero solo lo cubren las
pruebas del host o su caso de MAME aún falla. Arnés al 2026-10-30: 34 de 55 casos pasan.

## Núcleo del juego

| Función | NES | GB | GEN | NG | Notas |
|---|---|---|---|---|---|
| 5 carriles y 4 dificultades (3/4/5/5 carriles) | ✅ | ✅ | ✅ | ✅ | |
| Ventana de ±6 cuadros, puntaje 50 × multiplicador (×1 a ×4) | ✅ | ✅ | ✅ | ✅ | |
| Golpe al aire: rompe combo y calla el instrumento | ✅ | ✅ | ✅ | 🟡 | |
| Notas sostenidas (colas) | ✅ | ✅ | ✅ | ✅ | |
| Poder estelar (frases de 4, activar, doble puntaje) | ✅ | ✅ | ✅ | 🟡 | |
| Vida y SIN FALLO | ✅ | ✅ | ✅ | ✅ | |
| Estrellas por % del puntaje (20/40/60/80/95) | ✅ | ✅ | ✅ | ✅ | |
| Pausa | ✅ | ✅ | ✅ | ✅ | |
| Guitarra, teclado, bajo y batería | ✅ | ✅ | ✅ | ✅ | |
| Batería: bombo como barra naranja | ✅ | ✅ | ✅ | 🟡 | |
| Batería: platillos como rombo (solo experto) | ❌ | ❌ | ✅ | 🟡 | Pendiente en NES y GB; el bit `$40` ya viene en el chart |
| 1 jugador | ✅ | ✅ | ✅ | ✅ | |
| 2 jugadores VS (local) | ✅ | ❌ | ✅ | 🟡 | GB: por cable link (fase 5) |
| 2 jugadores Co-Op (revivir con media barra) | ✅ | ❌ | ✅ | 🟡 | GB: por cable link (fase 5) |
| Récord de banda (Co-Op) | ✅ | ❌ | ✅ | 🟡 | |
| 4 jugadores | ❌ | ❌ | ❌ | ❌ | Idea: Four Score en NES |
| Control de 6 botones | n/a | n/a | ✅ | n/a | Propio de la Genesis |
| Velocidad de caída / charts | 6/5/4/3 cuadros por fila | 12/10/8/6 | 6/5/4/3 | 6/5/4/3 | GB cae a la mitad (120 px de recorrido): `min_lane_gap` y charts más ralos |

## Menús y pantallas

| Función | NES | GB | GEN | NG | Notas |
|---|---|---|---|---|---|
| Título con música | ✅ | ✅ | ✅ | ✅ | La música es la de `audio/titulo.txt` |
| Título ilustrado (logo con arte) | ❌ | ❌ | ❌ | ❌ | GB y GEN dibujan el título con letras de tiles; NES lo tiene en `ideas.md` |
| Menú: canción, instrumento, dificultad, fallo | ✅ | ✅ | ✅ | ✅ | |
| Menú: selector de jugadores | ✅ | ❌ | ✅ | ✅ | |
| Récord de lo elegido visible en el menú | ✅ | ✅ | ✅ | ✅ | |
| Resultados (precisión, combo máximo, estrellas) | ✅ | ✅ | ✅ | ✅ | |
| NUEVO RECORD con iniciales estilo arcade | ✅ | ✅ | ✅ | ✅ | |
| Récords en SRAM por canción (hash), instrumento y dificultad | ✅ | ✅ | ✅ | ❌ no sobreviven al apagar | |
| Resultados por jugador y de banda | ✅ | n/a | ✅ | 🟡 | |

## Opciones y práctica

| Función | NES | GB | GEN | NG | Notas |
|---|---|---|---|---|---|
| ESPEJO | ✅ | ✅ | ✅ | ✅ | La batería lo ignora |
| VELOCIDAD 100/75/50/125 % | ✅ | ✅ | ✅ | ✅ | |
| CAIDA DE NOTAS (hyperspeed) | ✅ | ✅ | ✅ | ✅ | |
| PRACTICA (bucle 1/4, 1/2, 3/4, final) | ✅ | ✅ | ✅ | 🟡 | |
| INICIO DE LA PRACTICA | ✅ | ✅ | ✅ | 🟡 | |
| Marcas A/B del bucle en la pausa | ✅ | ✅ | ✅ | 🟡 | |
| EFECTO AL FALLAR (SI / SOLO SONIDO / NO) | ✅ | ✅ | ✅ | 🟡 | |
| Cualquier opción distinta de la normal bloquea récords (salvo el efecto) | ✅ | ✅ | ✅ | 🟡 | |

## Audio

| Función | NES | GB | GEN | NG | Notas |
|---|---|---|---|---|---|
| 10 canciones originales | ✅ | ✅ | ✅ | ✅ | |
| Música del título | ✅ | ✅ | ✅ | ✅ | |
| Efectos de menú (mover, aceptar, volver) | ✅ | ✅ | ✅ | 🟡 | |
| 3 efectos de fallo, sin repetir el anterior | ✅ | ✅ | ✅ | 🟡 | |
| El efecto solo suena al rasguear en falso (no con notas que se pasan) | ✅ | ✅ | ✅ | 🟡 | NES desde 26-oct-2026 |
| Temblor y rojo al fallar | ✅ (solo 1 jugador) | ✅ | ✅ | 🟡 (rojo; sin temblor) | |
| Silenciar el canal del instrumento al fallar | ✅ | ✅ | ✅ | 🟡 | |
| Batería con samples | ✅ DPCM | ❌ parches de ruido | ✅ DAC (Z80) | ❌ (ADPCM-A listo en el driver, sin samples) | GB no tiene DPCM: limitación de hardware |

## Escenario

| Función | NES | GB | GEN | NG | Notas |
|---|---|---|---|---|---|
| Público que salta con cada tiempo | ✅ | ✅ | ✅ | 🟡 | |
| Luces que laten con el tiempo | ✅ | ✅ | ✅ | 🟡 | |
| Público quieto sin combo (menos de 10) | ✅ | 🟡 | ✅ | 🟡 | GB: `stage.asm` no revisa el combo; falta ver si otro archivo lo hace |
| Luces cambian de color con el poder estelar | ✅ | ❌ | ✅ | 🟡 | GB cicla 8 colores en cada tiempo siempre |
| Rayo / destello al completar una frase estelar | ✅ | ❌ | ✅ | 🟡 | |
| Luces apagadas si pierden todos | ✅ | ❌ | ✅ | 🟡 | GB: el escenario no mira `wFailed` |
| Escenario con 2 jugadores | ✅ | n/a | ✅ | 🟡 | GEN: truss en medio, torre de luces con público entre las autopistas y balcones con público |
| Autopista en perspectiva | n/a | n/a | ✅ | 🟡 pista fija con sprites (carriles, bordes, aros) y franjas que se mueven solas con la autoanimación del LSPC | Propio de la Genesis |
| Escenario con truss y focos, bocinas y público a contraluz | 🟡 | 🟡 | ✅ | 🟡 | GEN (después de v0.4.0), dibujado en Python al compilar (`escenario.py`). NES y GB tienen su propio escenario: falta comparar el arte |
| Color por carril / paletas CGB | n/a | ✅ | n/a | n/a | |

## Herramientas de PC

| Función | NES | GB | GEN | NG | Notas |
|---|---|---|---|---|---|
| Fuentes de importación | NSF, `.fms`, `.ftm` | NSF, FamiStudio texto, GBS, VGM / VGZ | VGM / VGZ | VGM / VGZ (YM2610) | GB: GBS y VGM por la IR (`gbapu.py`); falta probarlos con archivos comerciales |
| Importar VGM / VGZ de su propia plataforma | ❌ | ✅ | ✅ | ✅ | Además del formato chiptune nativo (NSF en NES, GBS en GB). VGM trae comandos para el APU del NES |
| Lector de VGM compartido (`bandcore.vgm`) | ❌ | ✅ | ✅ | ✅ | Mismo resultado que los lectores anteriores (huella de los VGM de `audio/` y VGM sintéticos). NES: cuando importe VGM |
| `band inspect`: chips de un VGM y juego destino | ✅ | ✅ | ✅ | ✅ | Se corre desde `../bandcore`; sirve para los cuatro |
| Generador de charts compartido y `check_playable` | ✅ | ✅ | ✅ | ✅ | Desde `bandcore.chart` y `bandcore.drums` (GB añade su separación de gemas) |
| `reimport` y `list-songs` | ✅ | ✅ | ✅ | ✅ | |
| `preview` (WAV de cada pista de un NSF) | ✅ | ❌ | ❌ | ❌ | GEN usa `channels` para ver los canales |
| Editor de charts en el navegador | ✅ | ✅ | ✅ | ✅ | Páginas y servidor de `bandcore.editor`; cada juego pone su perfil, su reproductor y su `Game` (cargar, generar, exportar) |
| Editor: lógica de ediciones compartida (`bandcore.chartedit`, `ChartNote`, `check_playable`) | ✅ | ✅ | ✅ | ✅ | `reimport` da los mismos charts que antes en los cuatro |
| Editor: «Nueva canción» (importar desde el editor) | ✅ | ✅ | ✅ | ❌ | NG importa con `ngband import-song` |
| Editor: Escuchar con el audio real de la ROM | ✅ | ✅ | ✅ | 🟡 | |
| Editor: M/S por canal | ✅ | ✅ | ✅ | ✅ | |
| Editor: tabla de roles de la batería (`drums.json`) | ✅ | ✅ | ✅ | ✅ | |
| `edits.json` sobrevive a `reimport` | ✅ | ✅ | ✅ | ✅ | |
| VGM con streams del DAC (`$9x`) | n/a | n/a | ❌ | n/a | |

## Build, release y pruebas

| Función | NES | GB | GEN | NG | Notas |
|---|---|---|---|---|---|
| Release reproducible con `.sha256` | ✅ | 🟡 | ✅ | 🟡 | GB: `--release` existe, aún no hay versión publicada (VERSION 0.0.1) |
| Compilar solo algunas canciones (`-Solo`) | ✅ | ✅ | ❌ | ✅ `NGBAND_SONGS` | |
| Nombre alterno (`-Nombre`) | ✅ | ✅ | ❌ | ❌ | |
| Fuente privada | ✅ | ❌ | ❌ | ❌ | |
| Opciones de build propias | `-LucesBateria`, `-MedidorTransparente` | `-Colocacion` | ninguna | `NGBAND_CFLAGS` | |
| Bots: perfecto, nada, machacar | ✅ | ✅ | ✅ | ✅ | |
| Prueba de sincronía (nota del chart = alta de nota del audio) | ✅ | ✅ | ❌ | ✅ | GEN solo cuenta notas, puntaje, audio RMS y cuadros perdidos |
| Sincronía después de pausar | ✅ | ✅ | ❌ | ✅ | |
| Bot "humano" (~90 % termina, ~45 % pierde) | ✅ | ✅ | ❌ | 🟡 | |
| Pruebas de VS, Co-Op, pausa y opciones | ✅ | parcial (sin 2P) | ✅ | 🟡 | |
| Cuadros atrasados (falla con más de 2) | ✅ | ✅ | ✅ | 🟡 la prueba existe; casi todo falla | |
| Probado en hardware real | ✅ MiSTer | ❌ | ❌ | ❌ | GEN: sobre todo el DAC entre el 68000 y el Z80 |
| Emulador de pruebas | Mesen | PyBoy y Mesen | MAME | MAME | |
| Región | NTSC | n/a | NTSC | NTSC | PAL no soportado en NES ni GEN |

## Pendientes por versión

Ordenados más o menos por prioridad. Táchalos con `~~texto~~` al cerrarlos y anota la versión.

### NES
- [ ] Rombo de los platillos (hoy se dibujan como toms; el chart ya trae el bit).
- [ ] Título ilustrado (ver `ideas.md`).
- [ ] 4 jugadores con Four Score (idea).
- [ ] Batería "pro" con la Power Pad y modo con rasgueo (idea).
- [ ] Escuchar un solo grupo de golpes en el editor.
- [ ] Importar VGM / VGZ con los comandos del APU del NES (además de NSF, `.fms` y `.ftm`).
- [ ] Identificar las pistas de NSF sin `.m3u` (Battletoads, Bomberman, Bad Dudes, BTTF).

### GB
- [ ] Escenario: luces ligadas al poder estelar, rayo/destello en la frase estelar y luces apagadas al perder.
- [ ] Confirmar si el público se queda quieto sin combo (y añadir una prueba).
- [ ] Rombo de los platillos.
- [ ] 2 jugadores por cable link: VS, Co-Op, selector en el menú y récord de banda.
- [ ] `preview` de NSF.
- [x] ~~Importador GBS (formato chiptune nativo de la GB).~~ (después de v0.0.1)
- [x] ~~Importar VGM / VGZ con los comandos del DMG (CH1 a CH4).~~ (después de v0.0.1; lee con bandcore)
- [ ] Probar GBS y VGM con archivos comerciales; ofrecerlos también en «Nueva canción» del editor.
- [ ] Primera release publicada (subir VERSION).
- [ ] Probar en hardware real (DMG y CGB).
- [ ] Título ilustrado.
- [ ] Fuente privada.
- [ ] Actualizar el README, que describe la fase 3 (dice que faltan título, opciones, pausa, resultados y récords).
- [ ] Ideas de plataforma: borde Super Game Boy, rumble del MBC5, Game Boy Printer; compresión del stream FRS.

### GEN
- [ ] Prueba de sincronía nota/audio (también después de pausar).
- [ ] Bot "humano" (balance de la vida).
- [ ] `-Solo` y `-Nombre` en `build.sh`.
- [x] ~~Público con 2 jugadores.~~ (después de v0.4.0: torre con público entre las autopistas y balcones)
- [x] ~~Generar los gráficos al compilar (hoy tardan ~2 s al arrancar).~~ (después de v0.4.0: `genband build-gfx`; arranca en ~0.85 s)
- [ ] Probar en hardware (flash cart / MiSTer), sobre todo el DAC.
- [ ] VGM con streams del DAC (`$9x`).
- [ ] `preview` de VGM.
- [ ] Título ilustrado.
- [ ] Fuente privada.
- [ ] Soporte PAL.

### NG
- [x] ~~Autopista: superficie con carriles visibles.~~ (pista fija con sprites y franjas autoanimadas; sin líneas
      de tiempo con sprites)
- [ ] Rendimiento con 2 jugadores (VS pierde ~45 cuadros por canción; 1 jugador ya pasa).
- [ ] Sincronía audio/Chart con fallos y golpes al aire: los comandos de 2 bytes (silenciar, efecto) atrasan la cola
      unos cuadros; con 2 jugadores se llena.
- [ ] Récords: se guardan al inicio de la backup RAM, que es de la BIOS del MVS, y no sobreviven al apagar.
- [ ] Batería con samples ADPCM-A (el driver ya los toca; faltan los samples en la ROM V).
- [ ] Temblor al fallar.
- [ ] Practice en MAME (el bot no ve las vueltas) y calibrar el bot humano.
- [ ] Escuchar el audio con oído (solo verificado por WAV y por la posición del stream).
- [ ] `-Nombre`, `preview` de VGM, título ilustrado, fuente privada.
- [ ] Primera release (falta git) y probar en hardware (MVS/AES, MiSTer).
- [ ] «Nueva canción» en el editor (el menú compartido ya lo soporta: falta `/api/import` y el perfil `import`).

### bandcore (compartido)
[bandcore](https://github.com/Xalcker/bandcore) es un repo hermano (`../bandcore`) que los cuatro usan como dependencia
de uv. Lo que ya está ahí: lector de VGM, `band inspect`, páginas del editor, `chartedit`, `ChartNote` y
`check_playable`.
- [x] ~~Servidor del editor compartido (rutas, abrir, guardar, importar); cada juego solo carga y exporta.~~
      (`bandcore.editor.server`; cada juego define su `Game`)
- [x] ~~Generador de charts (`chart.py`) y batería (`drums.py`), comprobando con `reimport` que los charts no cambien.~~
      (`bandcore.chart` y `bandcore.drums`; `reimport` de 81 canciones, 51 de NES con las comerciales, da archivos
      idénticos byte por byte)
- [ ] Arreglos entre consolas (VGM de un chip a otro por la IR), empezando por NES → FM.
- [ ] Ideas: paquete de canción (`.bandsong`), ROM base + empaquetador sin compiladores, página web para armar la ROM.

### Futuras (SNES)
Punto de partida: la columna NES entera. Cada versión nueva debe importar VGM de su plataforma además de su formato
nativo (SNES: SPC). Antes de empezar, decidir qué plataformas llevan batería con samples, cuántos
jugadores caben en local y cómo se genera el audio (stream de registros o motor propio).
