#!/bin/bash

# Configuration
INPUT=$1
OUTPUT_PREFIX=$2
REFERENCE=${3:-"human"}  # Default to human
FORMAT_OPTION=${4:-""}   # Optional format specification
THREADS=4
INDEX_DIR="$(dirname "$0")/bowtie2_indices"
INDEX_PREFIX="${INDEX_DIR}/${REFERENCE}"
REFERENCE_URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz"

# Function to build Bowtie2 index
build_bowtie2_index() {
    echo "Building Bowtie2 index for ${REFERENCE}..."
    
    # Create index directory if not exists
    mkdir -p "$INDEX_DIR"
    
    # Download reference genome if needed
    if [ ! -f "${INDEX_DIR}/reference.fna" ]; then
        echo "Downloading human reference genome..."
        if ! wget -O "${INDEX_DIR}/reference.fna.gz" "$REFERENCE_URL"; then
            echo "ERROR: Failed to download reference genome" >&2
            exit 1
        fi
        gunzip "${INDEX_DIR}/reference.fna.gz"
    fi
    
    # Build index
    echo "This may take a while (30-60 minutes)..."
    if ! bowtie2-build "${INDEX_DIR}/reference.fna" "$INDEX_PREFIX"; then
        echo "ERROR: Failed to build Bowtie2 index" >&2
        exit 1
    fi
    
    # Cleanup
    rm "${INDEX_DIR}/reference.fna"
    echo "Successfully built Bowtie2 index at ${INDEX_PREFIX}"
}

# Determine format
if [[ "$FORMAT_OPTION" == "--format fastq" ]]; then
    FORMAT="fastq"
elif [[ "$FORMAT_OPTION" == "--format fasta" ]]; then
    FORMAT="fasta"
elif [[ "$INPUT" =~ \.fasta$|\.fa$ ]]; then
    FORMAT="fasta"
else
    FORMAT="fastq"
fi

# Validate input
if [ ! -f "$INPUT" ]; then
    echo "ERROR: Input file not found: $INPUT" >&2
    exit 1
fi

# Check and build index if needed
if [ ! -f "${INDEX_PREFIX}.1.bt2" ]; then
    echo "Bowtie2 index not found for ${REFERENCE}"
    
    # Ask for user confirmation (time and disk space intensive)
    read -p "This will download ~3GB and build indexes (needs 8GB RAM). Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user"
        exit 1
    fi
    
    build_bowtie2_index
fi

# Set output file
OUTPUT="${OUTPUT_PREFIX}.${FORMAT}"

# Bowtie2 parameters
BOWTIE2_PARAMS=(
    -x "$INDEX_PREFIX"
    -U "$INPUT"
    --un "$OUTPUT"
    --very-sensitive-local
    --no-unal
    -p "$THREADS"
)

[ "$FORMAT" == "fasta" ] && BOWTIE2_PARAMS+=(-f)

# Memory management
MAX_MEM=$(free -m | awk '/Mem:/ {print int($2*0.7)}')
ulimit -v $((MAX_MEM * 1024))

echo "Running ${REFERENCE} removal (${FORMAT} format)..."
bowtie2 "${BOWTIE2_PARAMS[@]}" 2> "${OUTPUT_PREFIX}.log" || {
    if [ ! -f "$OUTPUT" ]; then
        echo "ERROR: Bowtie2 failed and no output created" >&2
        exit 1
    fi
    echo "WARNING: Bowtie2 completed with errors but output was created" >&2
}

# Verify output
if [ ! -s "$OUTPUT" ]; then
    echo "WARNING: Output file is empty - no non-${REFERENCE} sequences found"
fi

echo "${REFERENCE} removal completed. Output: $OUTPUT"
exit 0