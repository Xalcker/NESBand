#!/bin/sh
# Compila la ROM en macOS/Linux: src/main.s -> build/nesband.nes
# Requiere cc65 en el PATH (macOS: brew install cc65)
set -e
cd "$(dirname "$0")"

BIN=tools/cc65/bin
if [ -x "$BIN/ca65" ]; then CA65="$BIN/ca65"; LD65="$BIN/ld65"; else CA65=ca65; LD65=ld65; fi

mkdir -p build

# Lista de canciones (src/songs/list.s): todas las carpetas de src/songs con un song.s, en orden
# alfabético. Se arma en cada compilación porque depende de qué canciones tenga cada quien (las
# importadas de NSF no van en git). Mismo formato que `nesband list-songs`.
names=$(for f in src/songs/*/song.s; do [ -f "$f" ] && basename "$(dirname "$f")"; done | LC_ALL=C sort)
count=$(printf '%s\n' "$names" | grep -c . || true)
if [ "$count" -eq 0 ]; then echo "No hay canciones en src/songs"; exit 1; fi
if [ "$count" -gt 31 ]; then echo "Hay $count canciones y el cartucho tiene 31 slots"; exit 1; fi
{
    printf '; Generado al compilar - lista de canciones de la ROM, en orden alfabetico\n'
    printf '; Cada cancion va en su slot de 16 KB (ver nes.cfg)\nNUM_SONGS = %s\n\n' "$count"
    i=0
    for n in $names; do
        printf 'SONG_SLOT_NUMBER .set %s\n.include "songs/%s/song.s"\n\n' "$i" "$n"
        i=$((i + 1))
    done
    printf '.segment "RODATA"\nsong_table:\n'
    for n in $names; do printf '    .addr song_%s\n' "$n"; done
} > src/songs/list.s

"$CA65" src/main.s -g -I src --bin-include-dir src --bin-include-dir src/famistudio -o build/main.o
"$LD65" -C nes.cfg build/main.o -o build/nesband.nes --dbgfile build/nesband.dbg -m build/nesband.map
echo "Listo: build/nesband.nes"
