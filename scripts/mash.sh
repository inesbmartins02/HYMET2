#!/bin/bash

# Recebe argumentos
INPUT_DIR="$1"
MASH_SCREEN="$2"
SCREEN_TAB="$3"
FILTERED_SCREEN="$4"
SORTED_SCREEN="$5"
TOP_HITS="$6"
SELECTED_GENOMES="$7"
INITIAL_THRESHOLD="$8"

# Verifica se o diretório de entrada existe
if [ ! -d "$INPUT_DIR" ]; then
    echo "Erro: Diretório de entrada não encontrado: $INPUT_DIR"
    exit 1
fi

# Encontra arquivos de sequência (suporta .fna, .fa, .fasta)
input_files=()
shopt -s nullglob
input_files+=("$INPUT_DIR"/*.fna)
input_files+=("$INPUT_DIR"/*.fa)
input_files+=("$INPUT_DIR"/*.fasta)
shopt -u nullglob

# Verifica se encontrou arquivos
if [ ${#input_files[@]} -eq 0 ]; then
    echo "Erro: Nenhum arquivo .fna, .fa ou .fasta encontrado em $INPUT_DIR"
    echo "Arquivos existentes no diretório:"
    ls -l "$INPUT_DIR" | head -10
    exit 1
fi

echo "Encontrados ${#input_files[@]} arquivos para processar"

# Passo 1: Executa o mash screen
echo "Executando mash screen..."
mash screen -p 8 -v 0.9 "$MASH_SCREEN" "${input_files[@]}" > "$SCREEN_TAB" || {
    echo "Erro ao executar mash screen"
    exit 1
}

# Verifica se o output foi gerado
if [ ! -s "$SCREEN_TAB" ]; then
    echo "Erro: Nenhum resultado gerado pelo mash screen"
    exit 1
fi

# Processamento dos resultados
sort -u -k5,5 "$SCREEN_TAB" > "$FILTERED_SCREEN"
sort -gr "$FILTERED_SCREEN" > "$SORTED_SCREEN"

# Passo 2: Ajusta o threshold e seleciona os genomas
num_sequences=${#input_files[@]}
min_candidates=$(echo "$num_sequences * 3.25" | bc | awk '{printf("%d\n", $1 + 0.5)}')
min_candidates=$(( min_candidates < 5 ? 5 : min_candidates ))

best_threshold=$INITIAL_THRESHOLD
current_threshold=$INITIAL_THRESHOLD
threshold_found=0

echo "===================================="
echo "Número de sequências de entrada: $num_sequences"
echo "Número mínimo de candidatos esperado: $min_candidates"
echo "===================================="

while (( $(echo "$current_threshold >= 0.70" | bc -l) )); do
    count=$(awk -v t="$current_threshold" '$1 > t' "$SORTED_SCREEN" | wc -l)
    
    echo "Testando threshold: $current_threshold"
    echo "Candidatos encontrados: $count"

    if [ "$count" -ge "$min_candidates" ]; then
        best_threshold=$current_threshold
        threshold_found=1
        break
    fi
    
    current_threshold=$(echo "$current_threshold - 0.01" | bc -l)
done

if [ "$threshold_found" -eq 0 ]; then
    best_threshold=0.71
    count=$(awk -v t="$best_threshold" '$1 > t' "$SORTED_SCREEN" | wc -l)
    echo "Nenhum threshold encontrado. Usando 0.70."
fi

# Filtra com o melhor threshold encontrado
awk -v threshold="$best_threshold" '$1 > threshold' "$SORTED_SCREEN" > "$TOP_HITS"
cut -f5 "$TOP_HITS" > "$SELECTED_GENOMES"

echo "===================================="
echo "Threshold final utilizado: $best_threshold"
echo "Candidatos encontrados: $count"
echo "===================================="

exit 0