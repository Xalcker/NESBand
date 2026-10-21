# Ideas pendientes

## Canciones por importar

Estos NSF ya están en `songs_src/` pero no traen `.m3u`, así que falta saber qué número de pista es cada canción (con `--song N`, desde 0):

| NSF | Pistas |
|---|---|
| Battletoads | 21 |
| Bomberman | 17 |
| Bad Dudes | 31 |
| Back to the Future II & III | 50 |

También falta confirmar de oído el tempo de *Blaster Master* (Area 1). El generador estimó 129 BPM; si las líneas de beat no cuadran, hay que reimportar con `--beat-frames`.

## Dos jugadores (y más)

**Hecho para 2 jugadores** (pantalla dividida con la IRQ del MMC3, estado por jugador en `pstate`,
autopistas de 16 px, menú y resultados por jugador). Queda abajo el análisis original, que sigue
sirviendo para pensar en 4.

**Sí es viable con 2.** Los dos tocan la misma canción, así que el reloj es uno solo: las dos autopistas bajan con el mismo scroll y caben en la misma nametable. Cada fila nueva sigue siendo una sola escritura de 32 tiles que junta las gemas de los dos charts.

Lo que cambia:

- **Autopistas más angostas**: hoy una mide 160 px (5 carriles de 32 px) y la pantalla 256. Con carriles de 16 px, cada autopista mide 80 px y caben dos con espacio en medio. 16 px coincide con la cuadrícula de atributos, así que cada carril conserva su color. La gema llenaría el carril completo, con la línea del borde dibujada dentro de su tile.
- **El límite de 8 sprites por línea**: 10 aros (5 por jugador) en la misma línea no se pueden dibujar como sprites. Solución: la **interrupción de scanline del MMC3**. Arriba de la línea de golpe, la autopista se desplaza; abajo, una franja fija (sin scroll) donde los aros y los marcadores son tiles de fondo. Además libera los sprites y da un HUD fijo para los dos.
- **Estado por jugador**: punteros de carril, puntaje, combo, multiplicador, silenciado y estadísticas pasan a ser arreglos de 2, indexados por jugador. La RAM alcanza (hoy usamos ~600 de 2048 bytes) y el CPU también: juzgar es barato.
- **Control 2**: se lee en `$4017`, con la misma protección contra el glitch del DPCM.
- **Audio**: cada jugador silencia su propio canal, así que deben elegir instrumentos distintos (como en Rock Band). Un modo "versus" con el mismo instrumento solo callaría el canal si fallan los dos.
- **Menú**: el jugador 2 se une con Start en su control; cada quien elige instrumento y dificultad. **Resultados** en dos columnas, más un puntaje de banda.
- **Pruebas**: el bot ya sabe jugar; solo hay que darle el segundo control.

**¿4 jugadores (banda completa con Four Score)?** Posible pero apretado: 4 autopistas de 5 carriles no caben ni a 16 px (320 px). Habría que usar carriles de 8 px (40 px por autopista) y perder los colores por carril, porque la cuadrícula de atributos es de 16 px. Conviene hacer primero 2 jugadores con el estado ya en arreglos, para que escalar después sea cambiar un número y el dibujo.

Orden sugerido:

1. Interrupción de scanline del MMC3 y franja fija abajo (sirve aunque haya un solo jugador).
2. Estado por jugador en arreglos, con 1 jugador (las pruebas actuales deben seguir pasando).
3. Autopistas de 16 px y segundo jugador.
4. Menú, resultados y pruebas de 2 jugadores.

## Pantalla de título ilustrada

Referencia: [referencias/titulo.webp](referencias/titulo.webp)

Logo "NES BAND" grande con relleno degradado, dos guitarras cruzadas, dos controles de NES, notas musicales, estrellas y rayos, con marcos de grecas arriba y abajo.

Qué hay que tener en cuenta para hacerlo en un NES de verdad:

- **Colores**: el fondo solo tiene 4 paletas de 3 colores más un negro común, y cada cuadro de 16×16 px usa una sola paleta. Hay que reducir la imagen a unas 4 combinaciones, por ejemplo: rojo/naranja/amarillo para el logo, azul/celeste/blanco para el contorno y los adornos, gris/blanco/negro para las guitarras y los controles, y una cuarta para las grecas. El degradado del logo se puede imitar con tramado (dithering), como en los juegos de la época.
- **Tiles**: una pantalla así necesita unos 200 tiles distintos. Ahora el fondo y los sprites comparten los 256 tiles de `$0000`. Como ya usamos MMC3, se puede agrandar la CHR-ROM y, en el título, cambiar a un banco de gráficos propio (registros R0/R1 del MMC3).
- **Proceso**: dibujar o convertir la imagen a 256×240 con esas restricciones (por ejemplo, con NES Screen Tool / NEXXT) y escribir un convertidor en `pctools/` que genere los tiles, la nametable y los atributos.
- **Textos**: usar "PRESIONA START" y créditos propios. Hay que evitar "Licensed by Nintendo" y el logo de Nintendo en los controles, porque son marcas registradas.

Ya no depende de nada: el cartucho ya es MMC3. Falta agrandar la CHR-ROM y escribir el convertidor.
