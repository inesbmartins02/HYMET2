#!/bin/bash

# Configurações
INPUT_CONTIGS="$1"       # Arquivo de contigs
INPUT_BAM_DIR="$2"       # Diretório com BAMs
OUTPUT_PREFIX="$3"       # Prefixo de saída
THREADS=${4:-4}          # Threads (padrão: 4)

# Verificar inputs
[ ! -f "$INPUT_CONTIGS" ] && { echo "ERROR: Contigs file not found"; exit 1; }
[ ! -d "$INPUT_BAM_DIR" ] && { echo "ERROR: BAM directory not found"; exit 1; }

# Criar diretório de saída
OUTPUT_DIR="${OUTPUT_PREFIX}"
mkdir -p "$OUTPUT_DIR"

# 1. Calcular profundidade
echo "Calculating coverage depth..."
jgi_summarize_bam_contig_depths --outputDepth "${OUTPUT_DIR}/depth.txt" "${INPUT_BAM_DIR}"/*.bam || {
    echo "ERROR: Failed to calculate depth"
    exit 1
}

# 2. Executar MetaBAT2
echo "Running MetaBAT2..."
metabat2 -i "$INPUT_CONTIGS" \
         -a "${OUTPUT_DIR}/depth.txt" \
         -o "${OUTPUT_DIR}/bin" \
         -t "$THREADS" \
         --verbose || {
    echo "ERROR: MetaBAT2 failed"
    exit 1
}

# 3. Relatório simples
NUM_BINS=$(ls ${OUTPUT_DIR}/bin.*.fa 2>/dev/null | wc -l)
echo "----------------------------------------"
echo "MetaBAT2 completed successfully!"
echo "Generated ${NUM_BINS} bins"
echo "Output directory: ${OUTPUT_DIR}"
echo "----------------------------------------"