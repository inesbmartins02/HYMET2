#!/bin/bash

INPUT=$1
OUTPUT=$2
THREADS=4
HOST_INDEX="pipeline/2_host_removal/human_bowtie2_index"

if [ ! -f "${HOST_INDEX}.1.bt2" ]; then
    echo "Índice Bowtie2 para o hospedeiro não encontrado."
    echo "Crie com: bowtie2-build host_genome.fasta $HOST_INDEX"
    exit 1
fi

bowtie2 -x "$HOST_INDEX" -U "$INPUT" --un "$OUTPUT.fastq" -p "$THREADS" || {
    echo "Erro ao executar Bowtie2"
    exit 1
}
