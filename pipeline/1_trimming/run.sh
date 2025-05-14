#!/bin/bash

INPUT=$1
OUTPUT_PREFIX=$2
THREADS=4
ADAPTERS_FILE="$(dirname "$0")/adapters.fa"

if [ -z "$INPUT" ] || [ -z "$OUTPUT_PREFIX" ]; then
    echo "Uso: $0 <input.fastq> <output_prefix>"
    exit 1
fi

# Baixa adaptadores se necessário
if [ ! -f "$ADAPTERS_FILE" ]; then
    echo "Baixando adaptadores Illumina padrão..."
    wget https://raw.githubusercontent.com/timflutre/trimmomatic/master/adapters/TruSeq3-SE.fa -O "$ADAPTERS_FILE" || {
        echo "Erro ao baixar adaptadores."
        exit 1
    }
fi

# Executa o Trimmomatic
trimmomatic SE \
  -threads "$THREADS" \
  "$INPUT" \
  "${OUTPUT_PREFIX}.fastq" \
  ILLUMINACLIP:"$ADAPTERS_FILE":2:30:10 \
  SLIDINGWINDOW:4:20 \
  MINLEN:50 || {
    echo "Erro ao executar o Trimmomatic"
    exit 1
}
