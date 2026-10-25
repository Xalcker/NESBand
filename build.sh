#!/bin/sh
# Compila la ROM en macOS/Linux: src/main.s -> build/nesband.nes
# Requiere cc65 en el PATH (macOS: brew install cc65)
#
#   ./build.sh                      compilación normal (todas las canciones de src/songs)
#   SOLO="mm1_*" ./build.sh         solo las canciones que coincidan (build/nesband-solo.nes): hay 31 slots
#   NOMBRE=prueba ./build.sh        deja build/nesband-prueba.nes sin pisar build/nesband.nes (con o sin SOLO)
#   ./build.sh --release [versión]  ROM para publicar: solo con las canciones que están en git, en
#                                   build/release/nesband-v<versión>.nes con su .sha256 y la licencia.
#                                   La versión sale del archivo VERSION si no se indica.
#   FUENTE=ruta.pf ./build.sh       con una fuente de 8x8 de tu equipo (.pf de Fonts_MiSTer o .ttf de 8 px),
#                                   solo para tu copia: necesita uv, y el release la ignora siempre
set -e
# (la ruta de la fuente es relativa a donde se llamó, así que se resuelve antes de cambiar de carpeta)
if [ -n "$FUENTE" ]; then
    [ -f "$FUENTE" ] || { echo "No encontré la fuente $FUENTE"; exit 1; }
    FUENTE="$(cd "$(dirname "$FUENTE")" && pwd)/$(basename "$FUENTE")"
fi
cd "$(dirname "$0")"

RELEASE=0
VERSION=""
if [ "$1" = "--release" ]; then
    RELEASE=1
    VERSION="${2:-$(head -n 1 VERSION | tr -d '\r ')}"
fi

BIN=tools/cc65/bin
if [ -x "$BIN/ca65" ]; then CA65="$BIN/ca65"; LD65="$BIN/ld65"; else CA65=ca65; LD65=ld65; fi

if [ "$RELEASE" -eq 1 ]; then OUT=build/release; BASE="nesband-v$VERSION"; elif [ -n "$NOMBRE" ]; then OUT=build; BASE="nesband-$NOMBRE"; elif [ -n "$SOLO" ]; then OUT=build; BASE=nesband-solo; else OUT=build; BASE=nesband; fi
mkdir -p "$OUT"

# Lista de canciones (src/songs/list.s): todas las carpetas de src/songs con un song.s, en orden
# alfabético. Se arma en cada compilación porque depende de qué canciones tenga cada quien (las
# importadas de NSF no van en git). Mismo formato que `nesband list-songs`.
escribir_lista() {
    count=$(printf '%s\n' "$1" | grep -c . || true)
    if [ "$count" -eq 0 ]; then echo "No hay canciones en src/songs"; exit 1; fi
    if [ "$count" -gt 31 ]; then echo "Hay $count canciones y el cartucho tiene 31 slots"; exit 1; fi
    {
        printf '; Generado al compilar - lista de canciones de la ROM, en orden alfabetico\n'
        printf '; Cada cancion va en su slot de 16 KB (ver nes.cfg)\nNUM_SONGS = %s\n\n' "$count"
        i=0
        for n in $1; do
            printf 'SONG_SLOT_NUMBER .set %s\n.include "songs/%s/song.s"\n\n' "$i" "$n"
            i=$((i + 1))
        done
        printf '.segment "RODATA"\nsong_table:\n'
        for n in $1; do printf '    .addr song_%s\n' "$n"; done
    } > src/songs/list.s
}

todas=$(for f in src/songs/*/song.s; do [ -f "$f" ] && basename "$(dirname "$f")"; done | LC_ALL=C sort)
if [ "$RELEASE" -eq 1 ]; then
    # Solo las que git versiona (sus song.s): los originales de NESBand, no lo importado de NSF comerciales
    versionadas=$(git ls-files src/songs | sed -n 's|^src/songs/\([^/]*\)/song\.s$|\1|p')
    names=$(for n in $todas; do printf '%s\n' "$versionadas" | grep -qx "$n" && echo "$n"; done || true)
else
    names="$todas"
fi
# SOLO="mm1_* otra": solo las canciones que coincidan con algún patrón (para tener más canciones locales que slots)
if [ -n "$SOLO" ]; then
    names=$(for n in $names; do for p in $SOLO; do case "$n" in ($p) echo "$n"; break ;; esac; done; done)
    [ -n "$names" ] || { echo "Ninguna canción coincide con SOLO=$SOLO"; exit 1; }
fi
escribir_lista "$names"

# Opciones de compilación (apagadas por defecto; ver src/main.s): LUCES_BATERIA=1, MEDIDOR_TRANSPARENTE=1
OPCIONES=""
[ "$LUCES_BATERIA" = "1" ] && OPCIONES="$OPCIONES -D DRUM_LIGHTS=1"
[ "$MEDIDOR_TRANSPARENTE" = "1" ] && OPCIONES="$OPCIONES -D METER_FLICKER=1"
# Fuente privada (#21): se convierte a build/font_private.s, que src/chr.s incluye con PRIVATE_FONT
if [ -n "$FUENTE" ] && [ "$RELEASE" -eq 1 ]; then
    echo "La ROM de release usa siempre la fuente por defecto: ignoro FUENTE"
elif [ -n "$FUENTE" ]; then
    case "$FUENTE" in
        (*.[tT][tT][fF]) uv run --with pillow nesband build-font --fuente "$FUENTE" --out build/font_private.s ;;
        (*) uv run nesband build-font --fuente "$FUENTE" --out build/font_private.s ;;
    esac
    OPCIONES="$OPCIONES -D PRIVATE_FONT=1 -I build"
fi
# shellcheck disable=SC2086
"$CA65" src/main.s $OPCIONES -g -I src --bin-include-dir src --bin-include-dir src/famistudio -o "$OUT/main.o"
"$LD65" -C nes.cfg "$OUT/main.o" -o "$OUT/$BASE.nes" --dbgfile "$OUT/$BASE.dbg" -m "$OUT/$BASE.map"

if [ "$RELEASE" -eq 1 ]; then
    # Comprobación: el .dbg lista cada archivo que entró a la ROM; una fuente privada nunca se publica
    if grep -q font_private "$OUT/$BASE.dbg"; then
        rm -f "$OUT/$BASE.nes"
        echo "La ROM de release incluye una fuente privada (font_private.s): no se publica"; exit 1
    fi
    # Suma de verificación (formato de sha256sum: "hash  archivo") y la licencia junto a la ROM
    if command -v sha256sum >/dev/null 2>&1; then SUM=$(sha256sum "$OUT/$BASE.nes" | cut -d' ' -f1); else SUM=$(shasum -a 256 "$OUT/$BASE.nes" | cut -d' ' -f1); fi
    printf '%s  %s.nes\n' "$SUM" "$BASE" > "$OUT/$BASE.nes.sha256"
    cp LICENSE "$OUT/LICENSE"
    escribir_lista "$todas"    # la lista de las compilaciones normales vuelve a tener todas las canciones locales
    echo "ROM de release ($(printf '%s\n' "$names" | grep -c .) canciones): $OUT/$BASE.nes"
    echo "SHA-256: $SUM"
else
    echo "Listo: $OUT/$BASE.nes"
fi
