#!/bin/bash

INPUT=$1
OUTPUT_PREFIX=$2
THREADS=4
ADAPTERS_FILE="$(dirname "$0")/adapters.fa"

# Verifica se o arquivo de input existe
if [ ! -f "$INPUT" ]; then
    echo "Erro: Arquivo de input não encontrado: $INPUT"
    exit 1
fi

# Verifica/baixa adaptadores
if [ ! -f "$ADAPTERS_FILE" ]; then
    echo "Baixando adaptadores Illumina..."
    wget https://raw.githubusercontent.com/timflutre/trimmomatic/master/adapters/TruSeq3-SE.fa -O "$ADAPTERS_FILE" || {
        echo "Erro ao baixar adaptadores"
        exit 1
    }
fi

# Verifica se o arquivo de adaptadores existe
if [ ! -f "$ADAPTERS_FILE" ]; then
    echo "Erro: Arquivo de adaptadores não encontrado: $ADAPTERS_FILE"
    exit 1
fi

# Executa o Trimmomatic com todos os parâmetros necessários
echo "Executando Trimmomatic..."
trimmomatic SE \
  -threads "$THREADS" \
  "$INPUT" \
  "${OUTPUT_PREFIX}_trimmed.fastq" \
  "ILLUMINACLIP:${ADAPTERS_FILE}:2:30:10" \
  "SLIDINGWINDOW:4:20" \
  "MINLEN:50" || {
    echo "Erro ao executar Trimmomatic"
    exit 1
}

# Verifica se o arquivo de saída foi criado
if [ ! -f "${OUTPUT_PREFIX}_trimmed.fastq" ]; then
    echo "Erro: Arquivo de saída não gerado: ${OUTPUT_PREFIX}_trimmed.fastq"
    exit 1
fi

echo "Trimmomatic concluído com sucesso!"