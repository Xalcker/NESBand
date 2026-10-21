# Ideas pendientes

## Pantalla de título ilustrada

Referencia: [referencias/titulo.webp](referencias/titulo.webp)

Logo "NES BAND" grande con relleno degradado, dos guitarras cruzadas, dos controles de NES, notas musicales, estrellas y rayos, con marcos de grecas arriba y abajo.

Qué hay que tener en cuenta para hacerlo en un NES de verdad:

- **Colores**: el fondo solo tiene 4 paletas de 3 colores más un negro común, y cada cuadro de 16×16 px usa una sola paleta. Hay que reducir la imagen a unas 4 combinaciones, por ejemplo: rojo/naranja/amarillo para el logo, azul/celeste/blanco para el contorno y los adornos, gris/blanco/negro para las guitarras y los controles, y una cuarta para las grecas. El degradado del logo se puede imitar con tramado (dithering), como en los juegos de la época.
- **Tiles**: una pantalla así necesita unos 200 tiles distintos. Ahora el fondo y los sprites comparten los 256 tiles de `$0000`, así que habría que separar los sprites a la tabla `$1000` o cambiar de banco de CHR, lo que requiere un mapper.
- **Proceso**: dibujar o convertir la imagen a 256×240 con esas restricciones (por ejemplo, con NES Screen Tool / NEXXT) y escribir un convertidor en `pctools/` que genere los tiles, la nametable y los atributos.
- **Textos**: usar "PRESIONA START" y créditos propios. Hay que evitar "Licensed by Nintendo" y el logo de Nintendo en los controles, porque son marcas registradas.

Depende de: pasar a un mapper con más CHR (MMC3 o similar).
