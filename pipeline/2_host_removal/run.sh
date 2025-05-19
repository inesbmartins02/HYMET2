#!/bin/bash

# Configuration
INPUT=$1
OUTPUT_PREFIX=$2
FORMAT_OPTION=${3:-""}  # Optional format specification
THREADS=4
INDEX_DIR="$(dirname "$0")/human_bowtie2_index"
INDEX_PREFIX="${INDEX_DIR}/human"

# Determine format
if [[ "$FORMAT_OPTION" =~ --format\ (fasta|fastq) ]]; then
    FORMAT="${BASH_REMATCH[1]}"
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

if [ ! -f "${INDEX_PREFIX}.1.bt2" ]; then
    echo "ERROR: Bowtie2 index not found at ${INDEX_PREFIX}" >&2
    exit 1
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

echo "Running host removal (${FORMAT} format)..."
bowtie2 "${BOWTIE2_PARAMS[@]}" 2> "${OUTPUT_PREFIX}.log" || {
    if [ ! -f "$OUTPUT" ]; then
        echo "ERROR: Bowtie2 failed and no output created" >&2
        exit 1
    fi
    echo "WARNING: Bowtie2 completed with errors but output was created" >&2
}

# Verify output
if [ ! -s "$OUTPUT" ]; then
    echo "WARNING: Output file is empty - no non-host sequences found"
    # Still exit successfully as this might be expected
fi

echo "Host removal completed. Output: $OUTPUT"
exit 0