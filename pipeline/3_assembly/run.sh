#!/bin/bash

INPUT=$1
OUTDIR=$2
THREADS=4

mkdir -p "$OUTDIR"

spades.py --only-assembler -s "$INPUT" -o "$OUTDIR" -t "$THREADS" || {
    echo "Erro ao executar SPAdes"
    exit 1
}
