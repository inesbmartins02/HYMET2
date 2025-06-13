#!/bin/bash

# Configurações
INPUT_CONTIGS="$1"       # Arquivo de contigs (FASTA)
INPUT_READS="$2"         # Reads em FASTQ (já com trimming)
OUTPUT_PREFIX="$3"       # Prefixo de saída
THREADS=${4:-4}          # Threads (padrão: 4)

# Verificar inputs
[ ! -f "$INPUT_CONTIGS" ] && { echo "ERROR: Contigs file not found"; exit 1; }
[ ! -f "$INPUT_READS" ] && { echo "ERROR: Reads file not found"; exit 1; }

# Criar diretório de saída
OUTPUT_DIR="${OUTPUT_PREFIX}"
mkdir -p "$OUTPUT_DIR"

# Caminhos internos
INDEX_DIR="${OUTPUT_DIR}/bowtie2_index"
BAM_FILE="${OUTPUT_DIR}/alignment.sorted.bam"
DEPTH_FILE="${OUTPUT_DIR}/depth.txt"

# 1. Indexar os contigs
echo "Indexing contigs..."
mkdir -p "$INDEX_DIR"
bowtie2-build "$INPUT_CONTIGS" "${INDEX_DIR}/contigs_index" || {
    echo "ERROR: Failed to build Bowtie2 index"
    exit 1
}

# 2. Alinhar reads aos contigs e gerar BAM
echo "Aligning reads to contigs..."
bowtie2 -x "${INDEX_DIR}/contigs_index" -U "$INPUT_READS" -p "$THREADS" -S "${OUTPUT_DIR}/alignment.sam" || {
    echo "ERROR: Bowtie2 alignment failed"
    exit 1
}

# 3. Converter e ordenar BAM
echo "Converting SAM to BAM and sorting..."
samtools view -Sb "${OUTPUT_DIR}/alignment.sam" | samtools sort -o "$BAM_FILE" || {
    echo "ERROR: Failed to sort BAM"
    exit 1
}
samtools index "$BAM_FILE"
rm "${OUTPUT_DIR}/alignment.sam"  # Limpar SAM

# 4. Calcular profundidade de cobertura
echo "Calculating coverage depth..."
jgi_summarize_bam_contig_depths --outputDepth "$DEPTH_FILE" "$BAM_FILE" || {
    echo "ERROR: Failed to calculate depth"
    exit 1
}

# 5. Executar MetaBAT2
echo "Running MetaBAT2..."
metabat2 -i "$INPUT_CONTIGS" \
         -a "$DEPTH_FILE" \
         -o "${OUTPUT_DIR}/bin" \
         -t "$THREADS" \
         --verbose || {
    echo "ERROR: MetaBAT2 failed"
    exit 1
}

# 6. Relatório
NUM_BINS=$(ls ${OUTPUT_DIR}/bin.*.fa 2>/dev/null | wc -l)
echo "----------------------------------------"
echo "MetaBAT2 completed successfully!"
echo "Generated ${NUM_BINS} bins"
echo "Output directory: ${OUTPUT_DIR}"
echo "----------------------------------------"
