#!/bin/bash

# Recebe argumentos
INPUT_DIR="$1"          # Este argumento não será mais usado para arquivos .fna diretamente.
REFERENCE_SET="$2"     # Caminho para combined_genomes.fasta.
NT_MMI="$3"            # Caminho para o índice do minimap2 (reference.mmi).
RESULTADOS_PAF="$4"    # Caminho para os resultados do alinhamento (resultados.paf).

# Cria o índice do conjunto de referência
echo "Criando índice com minimap2..."
minimap2 -d "$NT_MMI" "$REFERENCE_SET" #geral

# Verifica se a criação do índice foi bem-sucedida
if [ $? -ne 0 ]; then
    echo "Erro ao criar índice com minimap2."
    exit 1
fi

# Executa o alinhamento usando minimap2 (se long reads)
echo "Executando alinhamento com minimap2..."
minimap2 -x asm10 "$NT_MMI" "$INPUT_DIR"/*.fna >"$RESULTADOS_PAF"

# Verifica se o alinhamento foi bem-sucedido
if [ $? -ne 0 ]; then
    echo "Erro ao executar alinhamento com minimap2."
    exit 1
fi

echo "Alinhamento concluído com sucesso! Resultados salvos em $RESULTADOS_PAF."
