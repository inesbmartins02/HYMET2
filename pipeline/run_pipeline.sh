#!/bin/bash

# --- Initial Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INPUT=""
OUTDIR="${SCRIPT_DIR}/output"
RUN_QC=false
RUN_HOST=false
RUN_ASSEMBLY=false
RUN_BINNING=false  # Novo parâmetro para binning
CONVERT_TO_FASTA=false
PARALLEL=false
FORCE_FORMAT="" 
THREADS=4  # Adicionado número de threads

# --- Usage Function ---
usage() {
  echo "Usage: $0 -i <input.fastq or directory> [-qc] [-hostremoval] [-assembly] [-binning] [-convert] [-all] [-o output_dir] [-parallel] [--format fasta|fastq]"
  echo "Options:"
  echo "  -i, --input      Input FASTQ file or directory containing multiple FASTQs"
  echo "  -o, --output     Output directory (default: 'output')"
  echo "  -qc              Run Quality Control"
  echo "  -hostremoval     Run Host DNA Removal"
  echo "  -assembly        Run Assembly"
  echo "  -binning         Run Binning (requires assembly)"
  echo "  -convert         Convert FASTQ to FASTA"
  echo "  --format         Force input format (fasta or fastq)"
  echo "  -all             Run all processing steps (equivalent to -qc -hostremoval -assembly -binning -convert)"
  echo "  -parallel        Process files in parallel (using GNU Parallel)"
  exit 1
}

# --- Process Single File ---
process_file() {
  local file="$1"
  local base_out="$2"
  local filename=$(basename "${file%.*}")
  local current_input="$file"
  local input_format="fastq"

  echo "Processing: $filename"

  # Determine input format
  if [[ "$FORCE_FORMAT" != "" ]]; then
    input_format="$FORCE_FORMAT"
  elif [[ "$file" =~ \.fasta$|\.fa$ ]]; then
    input_format="fasta"
  fi

  # Step 1: Quality Control
  if [ "$RUN_QC" = true ]; then
    if [ "$input_format" != "fastq" ]; then
      echo "WARNING: QC skipped - can only process FASTQ files"
    else
      echo "### Step 1: Quality Control ###"
      QC_OUT="${base_out}/${filename}_trimmed.fastq"
      
      echo "Running trimming..."
      bash "${SCRIPT_DIR}/1_trimming/run.sh" "$current_input" "${base_out}/${filename}"
      
      if [ -f "${base_out}/clean_trimmed.fastq" ]; then
        mv "${base_out}/clean_trimmed.fastq" "$QC_OUT"
      fi
      
      current_input="$QC_OUT"
    fi
  fi

  # Step 2: Format Conversion
  if [ "$CONVERT_TO_FASTA" = true ]; then
    echo "### Converting to FASTA ###"
    FASTA_FILE="${base_out}/${filename}.fasta"
    
    if [ "$input_format" == "fasta" ]; then
      ln -sf "$(realpath "$current_input")" "$FASTA_FILE"
    else
      seqtk seq -A "$current_input" > "$FASTA_FILE"
    fi
    
    current_input="$FASTA_FILE"
    input_format="fasta"
  fi

  # Step 3: Host DNA Removal
  if [ "$RUN_HOST" = true ]; then
    echo "### Step 3: Host DNA Removal ###"
    HOST_OUT="${base_out}/${filename}_filtered"
    bash "${SCRIPT_DIR}/2_host_removal/run.sh" "$current_input" "$HOST_OUT" "human" "--format $input_format"
    
    if [ -f "${HOST_OUT}.fasta" ]; then
      current_input="${HOST_OUT}.fasta"
      input_format="fasta"
    elif [ -f "${HOST_OUT}.fastq" ]; then
      current_input="${HOST_OUT}.fastq"
      input_format="fastq"
    fi
  fi

    # Step 4: Assembly
  if [ "$RUN_ASSEMBLY" = true ]; then
    echo "### Step 4: Assembly ###"
    ASSEMBLY_OUT="${base_out}/${filename}_assembly"
    bash "${SCRIPT_DIR}/3_assembly/run.sh" "$current_input" "$ASSEMBLY_OUT"
    
    # Step 5: Binning (se assembly foi executado e binning foi solicitado)
    if [ "$RUN_BINNING" = true ] && [ -f "${ASSEMBLY_OUT}/contigs.fasta" ]; then
      echo "### Step 5: Binning ###"
      BINNING_OUT="${base_out}/${filename}_bins"
      
      # Passar contigs e reads para o script de binning
      bash "${SCRIPT_DIR}/4_binning/run.sh" \
        "${ASSEMBLY_OUT}/contigs.fasta" \
        "$current_input" \
        "$BINNING_OUT" \
        "$THREADS"
    fi
  fi


  echo "Processing completed for: $filename"
}

# --- Check Dependencies ---
check_dependency() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: $1 is not installed."
    echo "Solution: Activate conda environment with: conda activate hymet_env"
    exit 1
  }
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      INPUT="$2"
      shift 2
      ;;
    --format)
      FORCE_FORMAT="$2"
      shift 2
      ;;
    -qc) RUN_QC=true; shift ;;
    -hostremoval) RUN_HOST=true; shift ;;
    -assembly) RUN_ASSEMBLY=true; shift ;;
    -binning) RUN_BINNING=true; shift ;;  # Novo parâmetro
    -convert) CONVERT_TO_FASTA=true; shift ;;
    -all)
      RUN_QC=true
      RUN_HOST=true
      RUN_ASSEMBLY=true
      RUN_BINNING=true  # Incluído no -all
      CONVERT_TO_FASTA=true
      shift
      ;;
    -parallel) PARALLEL=true; shift ;;
    -h|--help) usage ;;
    *) echo "Invalid option: $1"; usage ;;
  esac
done

[ -z "$INPUT" ] && { echo "ERROR: Specify input with -i"; usage; }

# --- Dependency Check ---
echo "Checking dependencies..."
check_dependency trimmomatic
check_dependency bowtie2
check_dependency spades.py
check_dependency seqtk
check_dependency metabat2  # Nova dependência
[ "$PARALLEL" = true ] && check_dependency parallel

# --- Main Processing ---
mkdir -p "$OUTDIR"

if [ -d "$INPUT" ]; then
  readarray -t FILES < <(find "$INPUT" -type f \( -name "*.fq" -o -name "*.fastq" -o -name "*.fq.gz" -o -name "*.fastq.gz" \) | sort)
  
  if [ "$PARALLEL" = true ]; then
    export -f process_file check_dependency
    export SCRIPT_DIR RUN_QC RUN_HOST RUN_ASSEMBLY RUN_BINNING CONVERT_TO_FASTA THREADS
    parallel --bar --jobs 80% "process_file {} \"$OUTDIR\"" ::: "${FILES[@]}"
  else
    for file in "${FILES[@]}"; do
      process_file "$file" "$OUTDIR"
    done
  fi
elif [ -f "$INPUT" ]; then
  process_file "$INPUT" "$OUTDIR"
else
  echo "ERROR: Input must be a valid file or directory"
  exit 1
fi

echo -e "\nPipeline completed successfully!"
echo "Results available in: $OUTDIR"