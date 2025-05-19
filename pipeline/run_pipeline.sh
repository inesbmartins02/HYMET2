#!/bin/bash


# --- Initial Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INPUT=""
OUTDIR="${SCRIPT_DIR}/output"
RUN_QC=false
RUN_HOST=false
RUN_ASSEMBLY=false
CONVERT_TO_FASTA=false
PARALLEL=false
FORCE_FORMAT=""  # Added format forcing option

# --- Usage Function ---
usage() {
  echo "Usage: $0 -i <input.fastq or directory> [-qc] [-hostremoval] [-assembly] [-convert] [-all] [-o output_dir] [-parallel] [--format fasta|fastq]"
  echo "Options:"
  echo "  -i, --input      Input FASTQ file or directory containing multiple FASTQs"
  echo "  -o, --output     Output directory (default: 'output')"
  echo "  -qc              Run Quality Control"
  echo "  -hostremoval     Run Host DNA Removal"
  echo "  -assembly        Run Assembly"
  echo "  -convert         Convert FASTQ to FASTA"
  echo "  --format         Force input format (fasta or fastq)"
  echo "  -all             Run all processing steps (equivalent to -qc -hostremoval -assembly -convert)"
  echo "  -parallel        Process files in parallel (using GNU Parallel)"
  exit 1
}


# --- Process Single File ---
process_file() {
  local file="$1"
  local base_out="$2"
  local filename=$(basename "${file%.*}")
  local current_input="$file"
  local input_format="fastq"  # Default format

  echo "Processing: $filename"

  # Determine input format
  if [[ "$FORCE_FORMAT" != "" ]]; then
    input_format="$FORCE_FORMAT"
  elif [[ "$file" =~ \.fasta$|\.fa$ ]]; then
    input_format="fasta"
  fi

  # Step 1: Quality Control (only for FASTQ)
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
      
      if [ ! -f "$QC_OUT" ]; then
        echo "ERROR: Trimmed file not found for $filename"
        exit 1
      fi
      
      current_input="$QC_OUT"
    fi
  fi

  # Step 2: Format Conversion
  if [ "$CONVERT_TO_FASTA" = true ]; then
    echo "### Converting to FASTA ###"
    FASTA_FILE="${base_out}/${filename}.fasta"
    
    if [ "$input_format" == "fasta" ]; then
      echo "Input is already FASTA, creating symlink..."
      ln -sf "$(realpath "$current_input")" "$FASTA_FILE"
    else
      seqtk seq -A "$current_input" > "$FASTA_FILE" || {
        echo "ERROR: FASTA conversion failed"
        exit 1
      }
    fi
    
    current_input="$FASTA_FILE"
    input_format="fasta"
  fi

  # Step 3: Host DNA Removal
  if [ "$RUN_HOST" = true ]; then
    echo "### Step 3: Host DNA Removal ###"
    HOST_OUT="${base_out}/${filename}_filtered"
    
    # Run with format specification
    bash "${SCRIPT_DIR}/2_host_removal/run.sh" "$current_input" "$HOST_OUT" "--format $input_format" || {
      echo "ERROR: Host removal failed"
      exit 1
    }
    
    # Find output file
    if [ -f "${HOST_OUT}.fasta" ]; then
      current_input="${HOST_OUT}.fasta"
      input_format="fasta"
    elif [ -f "${HOST_OUT}.fastq" ]; then
      current_input="${HOST_OUT}.fastq"
      input_format="fastq"
    else
      echo "ERROR: No host-free output generated"
      exit 1
    fi
  fi


  # Step 4: Assembly
    if [ "$RUN_ASSEMBLY" = true ]; then
    echo "### Step 4: Assembly ###"
    bash "${SCRIPT_DIR}/3_assembly/run.sh" "$current_input" "${base_out}/${filename}"
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
      if [ ! -e "$INPUT" ]; then
        echo "ERROR: Input '$INPUT' does not exist!"
        exit 1
      fi
      shift 2
      ;;
    --format)
      FORCE_FORMAT="$2"
      if [[ "$FORCE_FORMAT" != "fasta" && "$FORCE_FORMAT" != "fastq" ]]; then
        echo "ERROR: Invalid format '$FORCE_FORMAT'. Use 'fasta' or 'fastq'"
        exit 1
      fi
      shift 2
      ;;
    -qc) RUN_QC=true; shift ;;
    -hostremoval) RUN_HOST=true; shift ;;
    -assembly) RUN_ASSEMBLY=true; shift ;;
    -convert) CONVERT_TO_FASTA=true; shift ;;
    -all)
      RUN_QC=true
      RUN_HOST=true
      RUN_ASSEMBLY=true
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
[ "$PARALLEL" = true ] && check_dependency parallel

# --- Prepare Output Directory ---
mkdir -p "$OUTDIR"
echo "Output directory: $OUTDIR"

# --- Main Processing ---
if [ -d "$INPUT" ]; then
  echo "Processing multiple files from directory: $INPUT"
  
  # Find FASTQ files (.fq, .fastq, .gz variants)
  readarray -t FILES < <(find "$INPUT" -type f \( -name "*.fq" -o -name "*.fastq" -o -name "*.fq.gz" -o -name "*.fastq.gz" \) | sort)
  
  if [ ${#FILES[@]} -eq 0 ]; then
    echo "ERROR: No FASTQ files found in $INPUT"
    echo "Supported formats: .fq, .fastq, .fq.gz, .fastq.gz"
    exit 1
  fi

  echo "Files to process (${#FILES[@]}):"
  printf '• %s\n' "${FILES[@]}"

  if [ "$PARALLEL" = true ]; then
    echo "Parallel mode activated (GNU Parallel)"
    export -f process_file check_dependency
    export SCRIPT_DIR RUN_QC RUN_HOST RUN_ASSEMBLY CONVERT_TO_FASTA
    parallel --bar --jobs 80% "process_file {} \"$OUTDIR\"" ::: "${FILES[@]}"
  else
    for file in "${FILES[@]}"; do
      process_file "$file" "$OUTDIR"
    done
  fi

elif [ -f "$INPUT" ]; then
  echo "Processing single file: $INPUT"
  process_file "$INPUT" "$OUTDIR"
else
  echo "ERROR: Input must be a valid file or directory"
  exit 1
fi

echo -e "\nPipeline completed successfully!"
echo "Results available in: $OUTDIR"