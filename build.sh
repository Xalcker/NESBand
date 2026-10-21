#!/bin/sh
# Compila la ROM en macOS/Linux: src/main.s -> build/nesband.nes
# Requiere cc65 en el PATH (macOS: brew install cc65)
set -e
cd "$(dirname "$0")"

BIN=tools/cc65/bin
if [ -x "$BIN/ca65" ]; then CA65="$BIN/ca65"; LD65="$BIN/ld65"; else CA65=ca65; LD65=ld65; fi

mkdir -p build
"$CA65" src/main.s -g -I src --bin-include-dir src --bin-include-dir src/famistudio -o build/main.o
"$LD65" -C nes.cfg build/main.o -o build/nesband.nes --dbgfile build/nesband.dbg -m build/nesband.map
echo "Listo: build/nesband.nes"
