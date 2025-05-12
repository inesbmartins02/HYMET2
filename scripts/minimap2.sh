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

# #!/bin/bash

# # Parâmetros
# INPUT_DIR="$1"          # Diretório de entrada com .fna
# REFERENCE_SET="$2"     # Genoma de referência combinado
# NT_MMI="$3"            # Índice do minimap2
# RESULTADOS_PAF="$4"    # Arquivo de saída .paf

# # Configurações de performance para genomas grandes
# PRESET="asm20"         # Preset para genomas eucarióticos grandes
# KMER_SIZE=21           # Tamanho do k-mer (maior = menos sensível)
# WINDOW_SIZE=20         # Janela de minimizadores
# THREADS=16             # Ajuste conforme seus núcleos de CPU
# SPLIT_SIZE="8G"        # Divisão do índice para controle de memória

# # 1. Criar índice otimizado
# echo "Criando índice com preset $PRESET..."
# minimap2 -x $PRESET -d "$NT_MMI" -k $KMER_SIZE -w $WINDOW_SIZE "$REFERENCE_SET"

# # Verificação de erro
# if [ $? -ne 0 ]; then
#     echo "Erro na criação do índice!"
#     exit 1
# fi

# # 2. Preparar ambiente para divisão de índice
# mkdir -p tmp_split_index  # Diretório para arquivos temporários

# # 3. Executar alinhamento com parâmetros acelerados
# echo "Iniciando alinhamento acelerado..."
# minimap2 -x $PRESET \
#     -t $THREADS \
#     -I $SPLIT_SIZE \
#     --split-prefix=tmp_split_index/idx \
#     -k $KMER_SIZE \
#     -w $WINDOW_SIZE \
#     -n 3 \
#     -r 2000 \
#     -g 10000 \
#     -N 50 \
#     "$NT_MMI" \
#     "$INPUT_DIR"/*.fna > "$RESULTADOS_PAF"

# # Verificação final
# if [ $? -eq 0 ]; then
#     echo "Alinhamento concluído! Resultados: $RESULTADOS_PAF"
#     rm -rf tmp_split_index  # Limpeza opcional
# else
#     echo "Erro durante o alinhamento!"
#     exit 1
# fi