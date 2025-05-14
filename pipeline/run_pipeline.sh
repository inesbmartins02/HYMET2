#!/bin/bash

INPUT=""
OUTDIR="output"
RUN_QC=false
RUN_HOST=false
RUN_ASSEMBLY=false

# --- Função de uso ---
usage() {
  echo "Uso: $0 -i <input.fastq> [-qc] [-hostremoval] [-assembly] [-all]"
  exit 1
}

# --- Parse de argumentos ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      INPUT="$2"
      shift 2
      ;;
    -qc)
      RUN_QC=true
      shift
      ;;
    -hostremoval)
      RUN_HOST=true
      shift
      ;;
    -assembly)
      RUN_ASSEMBLY=true
      shift
      ;;
    -all)
      RUN_QC=true
      RUN_HOST=true
      RUN_ASSEMBLY=true
      shift
      ;;
    *)
      usage
      ;;
  esac
done

# --- Verifica dependências ---
check_dependency() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Erro: $1 não está instalado."
    echo "Use 'conda activate hymet_env' ou veja environment.yml"
    exit 1
  }
}

check_dependency trimmomatic
check_dependency bowtie2
check_dependency spades.py
check_dependency seqtk

# --- Executa cada passo ---
if [ "$RUN_QC" = true ]; then
  echo "### Etapa 1: Quality Control ###"
  bash pipeline/1_trimming/run.sh "$INPUT" "$OUTDIR/clean"
  INPUT="$OUTDIR/clean.fastq"
fi

if [ "$RUN_HOST" = true ]; then
  echo "### Etapa 2: Remoção de Hospedeiro ###"
  bash pipeline/2_host_removal/run.sh "$INPUT" "$OUTDIR/host_removed"
  INPUT="$OUTDIR/host_removed.fastq"
fi

if [ "$RUN_ASSEMBLY" = true ]; then
  echo "### Etapa 3: Assembly ###"
  bash pipeline/3_assembly/run.sh "$INPUT" "$OUTDIR/assembly"
fi

echo "Pipeline concluído."
