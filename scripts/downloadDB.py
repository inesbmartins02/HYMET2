# import os
# import requests
# import gzip
# import shutil
# import csv
# from collections import defaultdict
# from concurrent.futures import ThreadPoolExecutor
# import sys

# # Recebe argumentos da linha de comando
# GENOMES_FILE = sys.argv[1]
# OUTPUT_DIR = sys.argv[2]
# TAXONOMY_FILE = sys.argv[3]
# CACHE_DIR = sys.argv[4]
# LOG_FILE = os.path.join(OUTPUT_DIR, "genome_download_log.txt")  # Caminho para o arquivo de log

# # Garante que os diretórios necessários existam
# os.makedirs(OUTPUT_DIR, exist_ok=True)
# os.makedirs(CACHE_DIR, exist_ok=True)
# os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

# def download_assembly_summary(base_urls, cache_dir):
#     cache_files = {}
#     for base_url in base_urls:
#         if base_url.endswith("assembly_summary_refseq.txt") or base_url.endswith("assembly_summary_genbank.txt"):
#             category = "refseq" if "refseq" in base_url else "genbank"
#             cache_file = os.path.join(cache_dir, f"assembly_summary_{category}.txt")
#         else:
#             category = base_url.strip("/").split("/")[-1]
#             cache_file = os.path.join(cache_dir, f"{category}_assembly_summary.txt")
        
#         if not os.path.exists(cache_file):
#             print(f"Baixando {base_url}...")
#             try:
#                 response = requests.get(base_url, timeout=30)
#                 response.raise_for_status()
#                 with open(cache_file, "w") as f:
#                     f.write(response.text)
#                 print(f"Salvo em cache: {cache_file}")
#             except Exception as e:
#                 print(f"Falha ao baixar {base_url}: {str(e)}")
#                 continue
        
#         cache_files[category] = cache_file
#     return cache_files

# def fetch_genome_by_identifier(identifier, assembly_summaries, output_dir):
#     for category, summary_file in assembly_summaries.items():
#         if search_in_summary(identifier, summary_file, output_dir):
#             return  # Sai da função se o genoma foi encontrado e baixado
    
#     print(f"Identificador {identifier} não encontrado nos summaries.")
#     log_missing_genome(identifier)

# def load_assembly_summary(file_path):
#     records = []
#     with open(file_path, "r") as f:
#         for line in f:
#             if line.startswith("#"):
#                 continue
#             fields = line.strip().split("\t")
#             if len(fields) >= 20:
#                 records.append({
#                     "organism_name": fields[7],
#                     "ftp_path": fields[19],
#                     "taxid": fields[5],
#                     "assembly_accession": fields[0]
#                 })
#     return records

# def search_in_summary(identifier, summary_file, output_dir):
#     with open(summary_file, "r") as f:
#         for line in f:
#             if line.startswith("#"):
#                 continue
#             fields = line.strip().split("\t")
#             if len(fields) > 19 and (fields[0].startswith(identifier) or fields[17].startswith(identifier)):
#                 ftp_path = fields[19]
#                 genomic_fna_url = f"{ftp_path}/{os.path.basename(ftp_path)}_genomic.fna.gz"
#                 species_name = fields[7].replace(" ", "_")
#                 output_file = os.path.join(output_dir, f"{species_name}.genomic.fna")
#                 if os.path.exists(output_file):
#                     print(f"Genoma já existe: {output_file}")
#                     return True
#                 print(f"Baixando genoma de {genomic_fna_url}...")
#                 try:
#                     response = requests.get(genomic_fna_url, stream=True, timeout=30)
#                     response.raise_for_status()
#                     compressed_file = output_file + ".gz"
#                     with open(compressed_file, "wb") as f_out:
#                         for chunk in response.iter_content(chunk_size=8192):
#                             f_out.write(chunk)
#                     with gzip.open(compressed_file, "rb") as gz_file:
#                         with open(output_file, "wb") as out_file:
#                             shutil.copyfileobj(gz_file, out_file)
#                     print(f"Genoma salvo e descomprimido: {output_file}")
#                     os.remove(compressed_file)
#                     return True
#                 except Exception as e:
#                     print(f"Falha ao baixar genoma de {genomic_fna_url}: {str(e)}")
#                     return False
#     return False

# def log_missing_genome(identifier):
#     with open(LOG_FILE, "a") as log_file:
#         log_file.write(f"Falha ao baixar: {identifier}\n")
#     print(f"Registro de falha adicionado ao log: {identifier}")

# def process_genomes_by_identifier(genomes_file, assembly_summaries, output_dir):
#     with open(genomes_file, "r") as f:
#         identifiers = [line.strip().split('_', 2)[0] + '_' + line.strip().split('_', 2)[1].split('.')[0] for line in f if line.strip()]
#     print(f"Identificadores extraídos: {identifiers}")
    
#     with ThreadPoolExecutor() as executor:
#         executor.map(lambda x: fetch_genome_by_identifier(x, assembly_summaries, output_dir), identifiers)

# def create_detailed_taxonomy_from_directory(genomes_directory, taxonomy_file, all_records):
#     mapping = defaultdict(list)
#     for file in os.listdir(genomes_directory):
#         if file.endswith(".genomic.fna"):
#             file_path = os.path.join(genomes_directory, file)
#             identifiers, gcf = extract_identifiers_and_gcf(file_path)
#             species_name = file.replace(".genomic.fna", "").replace("_", " ")
#             taxid = get_taxid_for_species(species_name.replace("_", " "), all_records)
#             mapping[species_name] = (taxid, identifiers, gcf)
    
#     with open(taxonomy_file, "w", newline="") as csvfile:
#         writer = csv.writer(csvfile, delimiter="\t")
#         writer.writerow(["GCF", "TaxID", "Identifiers"])
#         for species_name, (taxid, identifiers, gcf) in mapping.items():
#             writer.writerow([
#                 gcf if gcf else "",
#                 taxid if taxid != "Unknown TaxID" else "Unknown TaxID",
#                 ";".join(identifiers) if identifiers else ""
#             ])

# def get_taxid_for_species(species_name, records):
#     for record in records:
#         if species_name.lower() in record["organism_name"].lower():
#             return record["taxid"]
#     for record in records:
#         if species_name.lower().split(" ")[0] in record["organism_name"].lower():
#             return record["taxid"]
#     return "Unknown TaxID"

# def extract_identifiers_and_gcf(file_path):
#     identifiers = []
#     gcf = ""
#     with open(file_path, "r") as f:
#         for line in f:
#             if line.startswith(">"):
#                 parts = line[1:].split()
#                 if "GCF" in parts[0]:
#                     gcf = parts[0]
#                 identifiers.append(parts[0])
#     return identifiers, gcf

# # def concatenate_genomes(genomes_directory):
# #     combined_fasta_path = os.path.join(genomes_directory, 'combined_genomes.fasta')
# #     with open(combined_fasta_path, 'w') as combined_fasta:
# #         for file in os.listdir(genomes_directory):
# #             if file.endswith(".genomic.fna"):
# #                 file_path = os.path.join(genomes_directory, file)
# #                 with open(file_path) as genome_file:
# #                     combined_fasta.write(genome_file.read())
# #     print(f"Todos os genomas foram concatenados em: {combined_fasta_path}")

# if __name__ == "__main__":
#     BASE_URLS = [
#         "https://ftp.ncbi.nlm.nih.gov/genomes/refseq/assembly_summary_refseq.txt",
#         "https://ftp.ncbi.nlm.nih.gov/genomes/genbank/assembly_summary_genbank.txt"
#     ]
    
#     assembly_summaries = download_assembly_summary(BASE_URLS, CACHE_DIR)
#     all_records = []
#     for category, summary_file in assembly_summaries.items():
#         all_records.extend(load_assembly_summary(summary_file))
    
#     process_genomes_by_identifier(GENOMES_FILE, assembly_summaries, OUTPUT_DIR)
#     #concatenate_genomes(OUTPUT_DIR)
#     create_detailed_taxonomy_from_directory(OUTPUT_DIR, TAXONOMY_FILE, all_records) 

# ## VERSAO RAPIDA E FINAL
# #!/usr/bin/env python3
# import os
# import sys
# import requests
# import gzip
# import shutil
# import csv
# import logging
# from concurrent.futures import ThreadPoolExecutor, as_completed
# from collections import defaultdict
# from time import sleep

# MAX_WORKERS = 64
# RETRIES = 2
# TIMEOUT = 15

# def configurar_diretorios(output_dir, cache_dir):
#     os.makedirs(output_dir, exist_ok=True)
#     os.makedirs(cache_dir, exist_ok=True)

# class GenomeDownloader:
#     def __init__(self, output_dir, cache_dir):
#         self.output_dir = output_dir
#         self.cache_dir = cache_dir
#         self.assembly_summaries = self.baixar_assembly_summaries()
#         self.failed_downloads = set()
#         self.successful_downloads = set()
#         self.assembly_data = self.carregar_assembly_summaries()
#         logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

#     def baixar_assembly_summaries(self):
#         summaries = {}
#         urls = [
#             ("https://ftp.ncbi.nlm.nih.gov/genomes/refseq/assembly_summary_refseq.txt", "refseq"),
#             ("https://ftp.ncbi.nlm.nih.gov/genomes/genbank/assembly_summary_genbank.txt", "genbank")
#         ]
        
#         for url, key in urls:
#             cache_file = os.path.join(self.cache_dir, f"assembly_summary_{key}.txt")
#             if not os.path.exists(cache_file):
#                 self.baixar_arquivo(url, cache_file)
#             summaries[key] = cache_file
        
#         return summaries

#     def baixar_arquivo(self, url, destino, retries=RETRIES):
#         for attempt in range(retries):
#             try:
#                 response = requests.get(url, timeout=TIMEOUT)
#                 response.raise_for_status()
#                 with open(destino, 'wb') as f:
#                     f.write(response.content)
#                 return
#             except requests.exceptions.RequestException as e:
#                 logging.warning(f"Tentativa {attempt + 1} de {retries} falhou para {url}: {e}")
#                 if attempt < retries - 1:
#                     sleep(2 ** attempt)  # Exponential backoff
#                 else:
#                     raise

#     def carregar_assembly_summaries(self):
#         assembly_data = {}
#         for key, file_path in self.assembly_summaries.items():
#             with open(file_path, 'r') as f:
#                 for line in f:
#                     if line.startswith('#'):
#                         continue
#                     parts = line.strip().split('\t')
#                     if len(parts) > 19 and parts[19]:
#                         gcf = parts[0]
#                         assembly_data[gcf] = {
#                             'ftp_path': parts[19].replace('ftp://', 'https://'),
#                             'organism_name': parts[7],
#                             'taxid': parts[5],
#                             'file_name': f"{parts[0]}_{parts[1]}.fna"
#                         }
#         return assembly_data

#     def processar_identificadores(self, genomes_file):
#         with open(genomes_file) as f:
#             return [self.extrair_gcf(line.strip()) for line in f if line.strip()]

#     def extrair_gcf(self, filename):
#         parts = filename.split('_')
#         return f"{parts[0]}_{parts[1]}"

#     def executar_downloads(self, identifiers):
#         with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
#             futures = {executor.submit(self.baixar_genoma, gcf): gcf for gcf in identifiers}
#             for future in as_completed(futures):
#                 gcf = futures[future]
#                 try:
#                     result = future.result()
#                     if not result:
#                         self.failed_downloads.add(gcf)
#                 except Exception as e:
#                     logging.error(f"Erro no download de {gcf}: {str(e)}")
#                     self.failed_downloads.add(gcf)

#     def baixar_genoma(self, gcf):
#         metadata = self.assembly_data.get(gcf)
#         if not metadata:
#             return False

#         output_path = os.path.join(self.output_dir, metadata['file_name'])
#         if os.path.exists(output_path):
#             self.successful_downloads.add(metadata['file_name'])
#             return True

#         return self.salvar_genoma(metadata, output_path)

#     def salvar_genoma(self, metadata, output_path, retries=RETRIES):
#         for attempt in range(retries):
#             try:
#                 url = f"{metadata['ftp_path']}/{os.path.basename(metadata['ftp_path'])}_genomic.fna.gz"
#                 with requests.get(url, stream=True, timeout=TIMEOUT) as response:
#                     response.raise_for_status()
                    
#                     temp_gz = f"{output_path}.gz"
#                     with open(temp_gz, 'wb') as f:
#                         for chunk in response.iter_content(chunk_size=8192):
#                             f.write(chunk)
                    
#                     with gzip.open(temp_gz, 'rb') as f_in:
#                         with open(output_path, 'wb') as f_out:
#                             shutil.copyfileobj(f_in, f_out)
                    
#                     os.remove(temp_gz)
#                     self.successful_downloads.add(metadata['file_name'])
#                     return True
#             except Exception as e:
#                 logging.warning(f"Tentativa {attempt + 1} de {retries} falhou para {metadata['file_name']}: {e}")
#                 if attempt < retries - 1:
#                     sleep(2 ** attempt)  # Exponential backoff
#                 else:
#                     logging.error(f"Falha no download de {metadata['file_name']}: {str(e)}")
#                     return False

#     def create_detailed_taxonomy_from_directory(self, taxonomy_file):
#         mapping = defaultdict(lambda: {"taxid": "Unknown TaxID", "identifiers": set()})
        
#         for file in os.listdir(self.output_dir):
#             if file.endswith(".fna"):
#                 file_path = os.path.join(self.output_dir, file)
#                 gcf = self.extrair_gcf(file)
#                 with open(file_path, "r") as f:
#                     for line in f:
#                         if line.startswith(">"):
#                             identifier = line.split()[0][1:]  # Remove o '>' e pega o identificador
#                             mapping[gcf]["identifiers"].add(identifier)
                
#                 metadata = self.assembly_data.get(gcf, {})
#                 mapping[gcf]["taxid"] = metadata.get('taxid', "Unknown TaxID")
        
#         with open(taxonomy_file, "w", newline="") as csvfile:
#             writer = csv.writer(csvfile, delimiter="\t")
#             writer.writerow(["GCF", "TaxID", "Identifiers"])
#             for gcf, data in mapping.items():
#                 writer.writerow([
#                     gcf,
#                     data["taxid"],
#                     ";".join(data["identifiers"])
#                 ])

#         logging.info(f"Arquivo de taxonomia detalhada salvo em: {taxonomy_file}")

#     def concatenar_genomas(self, output_file):
#         logging.info("Concatenando genomas...")
#         with open(output_file, 'w') as out_f:
#             for filename in self.successful_downloads:
#                 file_path = os.path.join(self.output_dir, filename)
#                 try:
#                     with open(file_path, 'r') as in_f:
#                         shutil.copyfileobj(in_f, out_f)
#                 except FileNotFoundError:
#                     logging.warning(f"Aviso: Arquivo {filename} não encontrado, pulando...")
#         logging.info(f"Genomas concatenados em {output_file}")

# if __name__ == "__main__":
#     if len(sys.argv) != 5:
#         print("Uso: python3 download_genomes.py <genomes_file> <output_dir> <taxonomy_file> <cache_dir>")
#         sys.exit(1)

#     genomes_file = sys.argv[1]
#     output_dir = sys.argv[2]
#     taxonomy_file = sys.argv[3]
#     cache_dir = sys.argv[4]

#     configurar_diretorios(output_dir, cache_dir)
    
#     downloader = GenomeDownloader(output_dir, cache_dir)
#     identifiers = downloader.processar_identificadores(genomes_file)
    
#     logging.info(f"Iniciando download de {len(identifiers)} genomas...")
#     downloader.executar_downloads(identifiers)
#     downloader.create_detailed_taxonomy_from_directory(taxonomy_file)
    
#     combined_genomes_file = os.path.join(output_dir, "combined_genomes.fasta")
#     downloader.concatenar_genomas(combined_genomes_file)
    
#     logging.info("\nResumo:")
#     logging.info(f" - Baixados com sucesso: {len(downloader.successful_downloads)}")
#     logging.info(f" - Falhas: {len(downloader.failed_downloads)}")
#     logging.info(f" - Arquivo combinado: {combined_genomes_file}")

# # TENTAR COM WGET
#!/usr/bin/env python3
import os
import sys
import gzip
import shutil
import csv
import logging
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from collections import defaultdict
from time import sleep

# Configurações globais
MAX_WORKERS = 64  # Número máximo de threads para downloads paralelos
RETRIES = 3       # Número máximo de tentativas por download
TIMEOUT = 15      # Tempo limite (em segundos) para cada tentativa de download

# Configuração de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def configurar_diretorios(output_dir, cache_dir):
    """
    Cria os diretórios de saída e cache, se não existirem.
    """
    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(cache_dir, exist_ok=True)

class GenomeDownloader:
    def __init__(self, output_dir, cache_dir):
        self.output_dir = output_dir
        self.cache_dir = cache_dir
        self.assembly_summaries = self.baixar_assembly_summaries()
        self.failed_downloads = set()
        self.successful_downloads = set()
        self.assembly_data = self.carregar_assembly_summaries()

    def baixar_assembly_summaries(self):
        """
        Baixa os arquivos de sumário de assembly do NCBI (RefSeq e GenBank).
        """
        summaries = {}
        urls = [
            ("https://ftp.ncbi.nlm.nih.gov/genomes/refseq/assembly_summary_refseq.txt", "refseq"),
            ("https://ftp.ncbi.nlm.nih.gov/genomes/genbank/assembly_summary_genbank.txt", "genbank")
        ]
        
        for url, key in urls:
            cache_file = os.path.join(self.cache_dir, f"assembly_summary_{key}.txt")
            if not os.path.exists(cache_file):
                self.baixar_arquivo_wget(url, cache_file)
            summaries[key] = cache_file
        
        return summaries

    def baixar_arquivo_wget(self, url, destino, retries=RETRIES):
        """
        Baixa um arquivo usando wget.
        """
        for attempt in range(retries):
            try:
                comando = [
                    "wget",
                    "-O", destino,
                    "-q",  # Modo silencioso
                    "--tries=3",
                    "--timeout=15",
                    url
                ]
                subprocess.run(comando, check=True)
                return
            except subprocess.CalledProcessError as e:
                logging.warning(f"Tentativa {attempt + 1} de {retries} falhou para {url}: {e}")
                if attempt < retries - 1:
                    sleep(2 ** attempt)  # Exponential backoff
                else:
                    raise

    def carregar_assembly_summaries(self):
        """
        Carrega os dados dos arquivos de sumário de assembly.
        """
        assembly_data = {}
        for key, file_path in self.assembly_summaries.items():
            with open(file_path, 'r') as f:
                for line in f:
                    if line.startswith('#'):
                        continue
                    parts = line.strip().split('\t')
                    if len(parts) > 19 and parts[19]:
                        gcf = parts[0]
                        assembly_data[gcf] = {
                            'ftp_path': parts[19].replace('ftp://', 'https://'),
                            'organism_name': parts[7],
                            'taxid': parts[5],
                            'file_name': f"{parts[0]}_{parts[1]}.fna"
                        }
        return assembly_data

    def processar_identificadores(self, genomes_file):
        """
        Processa o arquivo de identificadores de genomas.
        """
        with open(genomes_file) as f:
            return [self.extrair_gcf(line.strip()) for line in f if line.strip()]

    def extrair_gcf(self, filename):
        """
        Extrai o identificador GCF de um nome de arquivo.
        """
        parts = filename.split('_')
        return f"{parts[0]}_{parts[1]}"

    def executar_downloads(self, identifiers):
        """
        Executa os downloads em paralelo usando ThreadPoolExecutor.
        """
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = {executor.submit(self.baixar_genoma, gcf): gcf for gcf in identifiers}
            for future in as_completed(futures):
                gcf = futures[future]
                try:
                    result = future.result()
                    if not result:
                        self.failed_downloads.add(gcf)
                except Exception as e:
                    logging.error(f"Erro no download de {gcf}: {str(e)}")
                    self.failed_downloads.add(gcf)

    def baixar_genoma(self, gcf):
        """
        Baixa um genoma usando wget.
        """
        metadata = self.assembly_data.get(gcf)
        if not metadata:
            return False

        output_path = os.path.join(self.output_dir, metadata['file_name'])
        if os.path.exists(output_path):
            self.successful_downloads.add(metadata['file_name'])
            return True

        return self.salvar_genoma(metadata, output_path)

    def salvar_genoma(self, metadata, output_path, retries=RETRIES):
        """
        Baixa e salva um genoma usando wget.
        """
        url = f"{metadata['ftp_path']}/{os.path.basename(metadata['ftp_path'])}_genomic.fna.gz"
        temp_gz = f"{output_path}.gz"

        for attempt in range(retries):
            try:
                comando = [
                    "wget",
                    "-O", temp_gz,
                    "-q",
                    "--tries=3",
                    "--timeout=15",
                    url
                ]
                subprocess.run(comando, check=True)

                with gzip.open(temp_gz, 'rb') as f_in:
                    with open(output_path, 'wb') as f_out:
                        shutil.copyfileobj(f_in, f_out)

                os.remove(temp_gz)
                self.successful_downloads.add(metadata['file_name'])
                return True
            except subprocess.CalledProcessError as e:
                logging.warning(f"Tentativa {attempt + 1} de {retries} falhou para {metadata['file_name']}: {e}")
                if attempt < retries - 1:
                    sleep(2 ** attempt)
                else:
                    logging.error(f"Falha no download de {metadata['file_name']}: {str(e)}")
                    return False

    def create_detailed_taxonomy_from_directory(self, taxonomy_file):
        """
        Cria um arquivo de taxonomia detalhada a partir dos genomas baixados.
        """
        mapping = defaultdict(lambda: {"taxid": "Unknown TaxID", "identifiers": set()})
        
        for file in os.listdir(self.output_dir):
            if file.endswith(".fna"):
                file_path = os.path.join(self.output_dir, file)
                gcf = self.extrair_gcf(file)
                with open(file_path, "r") as f:
                    for line in f:
                        if line.startswith(">"):
                            identifier = line.split()[0][1:]  # Remove o '>' e pega o identificador
                            mapping[gcf]["identifiers"].add(identifier)
                
                metadata = self.assembly_data.get(gcf, {})
                mapping[gcf]["taxid"] = metadata.get('taxid', "Unknown TaxID")
        
        with open(taxonomy_file, "w", newline="") as csvfile:
            writer = csv.writer(csvfile, delimiter="\t")
            writer.writerow(["GCF", "TaxID", "Identifiers"])
            for gcf, data in mapping.items():
                writer.writerow([
                    gcf,
                    data["taxid"],
                    ";".join(data["identifiers"])
                ])

        logging.info(f"Arquivo de taxonomia detalhada salvo em: {taxonomy_file}")

    def concatenar_genomas(self, output_file):
        """
        Concatena todos os genomas baixados em um único arquivo.
        """
        logging.info("Concatenando genomas...")
        with open(output_file, 'w') as out_f:
            for filename in self.successful_downloads:
                file_path = os.path.join(self.output_dir, filename)
                try:
                    with open(file_path, 'r') as in_f:
                        shutil.copyfileobj(in_f, out_f)
                except FileNotFoundError:
                    logging.warning(f"Aviso: Arquivo {filename} não encontrado, pulando...")
        logging.info(f"Genomas concatenados em {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Uso: python3 download_genomes.py <genomes_file> <output_dir> <taxonomy_file> <cache_dir>")
        sys.exit(1)

    genomes_file = sys.argv[1]
    output_dir = sys.argv[2]
    taxonomy_file = sys.argv[3]
    cache_dir = sys.argv[4]

    configurar_diretorios(output_dir, cache_dir)
    
    downloader = GenomeDownloader(output_dir, cache_dir)
    identifiers = downloader.processar_identificadores(genomes_file)
    
    logging.info(f"Iniciando download de {len(identifiers)} genomas...")
    downloader.executar_downloads(identifiers)
    downloader.create_detailed_taxonomy_from_directory(taxonomy_file)
    
    combined_genomes_file = os.path.join(output_dir, "combined_genomes.fasta")
    downloader.concatenar_genomas(combined_genomes_file)
    
    logging.info("\nResumo:")
    logging.info(f" - Baixados com sucesso: {len(downloader.successful_downloads)}")
    logging.info(f" - Falhas: {len(downloader.failed_downloads)}")
    logging.info(f" - Arquivo combinado: {combined_genomes_file}")
