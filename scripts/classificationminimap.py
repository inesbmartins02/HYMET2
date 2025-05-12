##### SCRIPT 1: ORIGINAL COM 2 COISAS 0.80 E 30
# #!/usr/bin/env python3
# import os
# import csv
# from collections import defaultdict
# import argparse
# from multiprocessing import Pool
# import logging
# import sys

# # Aumentar o limite de tamanho de campo
# csv.field_size_limit(sys.maxsize)

# # Configuração do logging
# logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

# def load_taxonomy_file(taxonomy_file):
#     taxonomy = {}
#     with open(taxonomy_file, "r") as f:
#         reader = csv.DictReader(f, delimiter="\t")
#         for row in reader:
#             taxid = row["TaxID"]
#             identifiers = row["Identifiers"].split(";")
#             for identifier in identifiers:
#                 normalized_identifier = identifier.strip()
#                 taxonomy[normalized_identifier] = taxid
#     logging.info(f"Loaded {len(taxonomy)} entries from taxonomy file")
#     return taxonomy

# def load_taxonomy_hierarchy_file(taxonomy_hierarchy_file):
#     taxonomy_hierarchy = {}
#     with open(taxonomy_hierarchy_file, "r") as f:
#         reader = csv.DictReader(f, delimiter="\t")
#         for row in reader:
#             taxid = row["TaxID"]
#             lineage = row["Lineage"].strip()  # Mantém a lineage como está
#             taxonomy_hierarchy[taxid] = lineage  # Armazena a lineage diretamente
#     logging.info(f"Loaded {len(taxonomy_hierarchy)} entries from taxonomy hierarchy file")
#     return taxonomy_hierarchy

# def parse_paf_file(paf_file, min_mapping_quality=30, min_coverage=0.8):
#     query_to_refs = defaultdict(list)
#     total_entries = 0
#     filtered_entries = 0
#     with open(paf_file, "r") as f:
#         for line in f:
#             total_entries += 1
#             fields = line.strip().split("\t")
#             query_id = fields[0]
#             query_length = int(fields[1])
#             alignment_length = int(fields[10])
#             ref_id = fields[5]
#             mapping_quality = int(fields[11])
#             coverage = alignment_length / query_length
#             if mapping_quality >= min_mapping_quality and coverage >= min_coverage:
#                 query_to_refs[query_id].append((ref_id, mapping_quality, coverage))
#             else:
#                 filtered_entries += 1
    
#     logging.info(f"Total entries in PAF: {total_entries}")
#     logging.info(f"Filtered entries: {filtered_entries}")
#     logging.info(f"Remaining entries: {len(query_to_refs)}")
#     return query_to_refs

# def determine_lca(taxids, taxonomy_hierarchy, minhits=3, flex=2, min_frequency=0.5):
#     if not taxids:
#         return "Unknown"

#     hierarchies = [taxonomy_hierarchy.get(taxid, []) for taxid in taxids if taxid in taxonomy_hierarchy]
#     if not hierarchies:
#         return "Unknown"

#     lca = []
#     for level in zip(*hierarchies):
#         counts = defaultdict(int)
#         for taxon in level:
#             counts[taxon.split(":")[-1]] += 1

#         total = len(hierarchies)
#         candidates = [taxon for taxon, count in counts.items() if count / total >= min_frequency]

#         if candidates:
#             lca.append(max(candidates, key=lambda x: counts[x]))
#         else:
#             break

#     logging.debug(f"LCA determined: {';'.join(lca)}")
#     return ";".join(lca) if lca else "Unknown"

# def determine_taxonomic_level(classification):
#     levels = ["superkingdom", "phylum", "class", "order", "family", "genus", "species", "strain"]
#     parts = classification.split(";")
#     rank = len(parts) - 1

#     if rank == 0:
#         return "root"
#     elif rank > len(levels):
#         return "strain"
#     elif rank == len(levels) and any(" DSM " in part for part in parts):
#         return "strain"
#     else:
#         return levels[rank - 1]

# def process_query(query, refs, taxonomy, taxonomy_hierarchy):
#     perfect_matches = [(ref, taxonomy.get(ref[0])) for ref in refs if query == ref[0] and ref[0] in taxonomy]
    
#     if len(perfect_matches) == 1:
#         ref, taxid = perfect_matches[0]
        
#         # Obtém a lineage diretamente sem formatação
#         lineage = taxonomy_hierarchy.get(taxid, "Unknown")
        
#         level = determine_taxonomic_level(lineage)  # Determina o nível taxonômico baseado na lineage
#         confidence = 1.0
        
#         logging.debug(f"Perfect match found for query {query}: {lineage}")
        
#         return query, lineage.strip(), level, confidence

#     valid_refs = [(ref[0], taxonomy.get(ref[0])) for ref in refs if ref[0] in taxonomy]
    
#     if not valid_refs:
#         logging.debug(f"No valid references found for query {query}")
        
#         return query, "Unknown", "root", 0.0

#     taxids = [taxid for _, taxid in valid_refs]
    
#     lca_classification = determine_lca(taxids, taxonomy_hierarchy)
    
#     cleaned_classification = lca_classification
    
#     level = determine_taxonomic_level(cleaned_classification)
    
#     confidence = len(valid_refs) / len(refs)
    
#     logging.debug(f"Classification for query {query}: {cleaned_classification}, level: {level}, confidence: {confidence}")
    
#     return query, cleaned_classification.strip(), level, confidence

# def process_classification(paf_file,
#                            taxonomy_file,
#                            taxonomy_hierarchy_file,
#                            output_file,
#                            num_processes=4,
#                            min_mapping_quality=30,
#                            min_coverage=0.8):
    
#    taxonomy = load_taxonomy_file(taxonomy_file)
   
#    taxonomy_hierarchy = load_taxonomy_hierarchy_file(taxonomy_hierarchy_file)
   
#    query_to_refs = parse_paf_file(paf_file,
#                       min_mapping_quality,
#                       min_coverage)

#    results = []  # Inicializa results como uma lista vazia

#    try:
#        with Pool(num_processes) as p:
#            results = p.starmap(process_query,
#                           [(query,
#                             refs,
#                             taxonomy,
#                             taxonomy_hierarchy) for query,
#                            refs in query_to_refs.items()])
#    except Exception as e:
#        logging.error(f"An error occurred during processing: {e}")

#    classified_count = 0
   
#    with open(output_file,
#              'w') as outfile:
       
#        writer = csv.writer(outfile,
#                        delimiter='\t')
       
#        writer.writerow(["Query", 
#                         'Lineage', 
#                         'Taxonomic Level', 
#                         'Confidence'])

#        for query, lineage, level, confidence in results:

#            if lineage != 'Unknown':
#                classified_count += 1
           
#            writer.writerow([query.strip(),
#                             lineage.strip(),
#                             level,
#                             f"{confidence:.2f}"])

#    logging.info(f"Total queries processed: {len(results)}")
#    logging.info(f"Queries classified: {classified_count}")
#    logging.info(f"Queries unclassified: {len(results) - classified_count}")
#    print(
#        f"Classificação LCA/Best Match com nível taxonômico e confiança salva em '{output_file}'")

# if __name__ == "__main__":
#    parser = argparse.ArgumentParser(description="Classify sequences using LCA/Best Match approach")
   
#    parser.add_argument("--paf", required=True,
#                        help="Path to the PAF file")
   
#    parser.add_argument("--taxonomy", required=True,
#                        help="Path to the detailed taxonomy file")
   
#    parser.add_argument("--hierarchy", required=True,
#                        help="Path to the taxonomy hierarchy file")
   
#    parser.add_argument("--output", required=True,
#                        help="Path to the output file")
   
#    parser.add_argument("--processes", type=int,
#                        default=4,
#                        help="Number of processes to use")
   
#    parser.add_argument("--min_quality", type=int,
#                        default=30,
#                        help="Minimum mapping quality")
   
#    parser.add_argument("--min_coverage", type=float,
#                        default=0.8,
#                        help="Minimum alignment coverage")

#    args = parser.parse_args()

#    process_classification(args.paf, args.taxonomy, args.hierarchy,args.output,args.processes,args.min_quality,args.min_coverage)




### SCRIPT 3 LCA + BEST MATCH -deepseek otimos resultados
# !/usr/bin/env python3
import os
import csv
from collections import defaultdict
import argparse
from multiprocessing import Pool
import logging
import sys

csv.field_size_limit(sys.maxsize)

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def load_taxonomy_file(taxonomy_file):
    taxonomy = {}
    with open(taxonomy_file, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            taxid = row["TaxID"]
            for identifier in row["Identifiers"].split(";"):
                cleaned_id = identifier.strip()
                if cleaned_id:
                    taxonomy[cleaned_id] = taxid
    logging.info(f"Loaded {len(taxonomy)} taxonomy mappings")
    return taxonomy

def load_taxonomy_hierarchy_file(taxonomy_hierarchy_file):
    hierarchy = {}
    with open(taxonomy_hierarchy_file, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            taxid = row["TaxID"]
            hierarchy[taxid] = row["Lineage"].strip()
    logging.info(f"Loaded {len(hierarchy)} taxonomy hierarchies")
    return hierarchy

def parse_paf_file(paf_file):
    query_map = defaultdict(list)
    ref_counts = defaultdict(int)
    
    with open(paf_file, "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) < 11:
                continue
                
            query_id = parts[0]
            query_len = int(parts[1])
            ref_id = parts[5]
            align_len = int(parts[10])
            
            coverage = align_len / query_len if query_len > 0 else 0
            is_exact = (query_id == ref_id) and (coverage >= 0.99)
            
            query_map[query_id].append((ref_id, coverage, is_exact))
            ref_counts[ref_id] += 1

    logging.info(f"Processed {len(query_map)} queries from PAF file")
    return query_map, ref_counts

def determine_taxonomic_level(lineage):
    rank_order = [
        'superkingdom', 'phylum', 'class', 'order',
        'family', 'genus', 'species', 'strain'
    ]
    
    current_level = None
    for part in lineage.split(';'):
        part = part.strip()
        if ':' in part:
            rank, name = part.split(':', 1)
            rank = rank.strip().lower()
            if rank in rank_order:
                if current_level is None:
                    current_level = rank
                else:
                    current_index = rank_order.index(current_level)
                    new_index = rank_order.index(rank)
                    if new_index > current_index:
                        current_level = rank
    return current_level if current_level is not None else 'root'

def calculate_weighted_lineage(refs, ref_abundance, taxonomy):
    taxid_weights = defaultdict(float)
    total_weight = 0.0
    
    for ref_id, coverage, _ in refs:
        if ref_id not in taxonomy:
            continue
            
        taxid = taxonomy[ref_id]
        weight = coverage * ref_abundance.get(ref_id, 1)
        taxid_weights[taxid] += weight
        total_weight += weight
    
    return taxid_weights, total_weight

def determine_lca(taxid_weights, total_weight, taxonomy_hierarchy):
    if total_weight == 0:
        return "Unknown", "root", 0.0

    lineages = []
    for taxid, weight in taxid_weights.items():
        if taxid in taxonomy_hierarchy:
            lineage = taxonomy_hierarchy[taxid].split(";")
            lineages.append((lineage, weight/total_weight))

    if not lineages:
        return "Unknown", "root", 0.0

    consensus = {}
    confidence = 1.0
    rank_order = [
        'superkingdom', 'phylum', 'class', 'order',
        'family', 'genus', 'species', 'strain'
    ]

    for rank in rank_order:
        level_counts = defaultdict(float)
        for lineage, weight in lineages:
            for part in lineage:
                if part.startswith(f"{rank}:"):
                    level_counts[part] += weight
                    break
        
        if level_counts:
            best_match, conf = max(level_counts.items(), key=lambda x: x[1])
            consensus[rank] = best_match
            confidence *= conf
        else:
            break  # Stop at first missing rank

    lineage_parts = [consensus.get(rank) for rank in rank_order if consensus.get(rank)]
    if not lineage_parts:
        return "Unknown", "root", 0.0

    full_lineage = ";".join(lineage_parts)
    level = determine_taxonomic_level(full_lineage)
    return full_lineage, level, min(confidence, 1.0)

def process_query(args):
    query, refs, ref_abundance, taxonomy, taxonomy_hierarchy = args
    
    # Check for exact matches first
    exact_matches = [ref for ref, _, is_exact in refs if is_exact and ref in taxonomy]
    if exact_matches:
        taxid = taxonomy[exact_matches[0]]
        if taxid in taxonomy_hierarchy:
            lineage = taxonomy_hierarchy[taxid]
            level = determine_taxonomic_level(lineage)
            return (query, lineage, level, 1.0)

    # Calculate LCA for non-exact matches
    taxid_weights, total_weight = calculate_weighted_lineage(refs, ref_abundance, taxonomy)
    lineage, level, confidence = determine_lca(taxid_weights, total_weight, taxonomy_hierarchy)
    
    return (query, lineage, level, confidence)

def main_process(paf_file, taxonomy_file, hierarchy_file, output_file, processes=4):
    taxonomy = load_taxonomy_file(taxonomy_file)
    taxonomy_hierarchy = load_taxonomy_hierarchy_file(hierarchy_file)
    query_map, ref_abundance = parse_paf_file(paf_file)

    tasks = [(query, refs, ref_abundance, taxonomy, taxonomy_hierarchy) 
             for query, refs in query_map.items()]

    results = []
    with Pool(processes) as pool:
        results = pool.map(process_query, tasks)

    with open(output_file, 'w') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(['Query', 'Lineage', 'Taxonomic Level', 'Confidence'])
        
        classified = 0
        for query, lineage, level, confidence in results:
            if lineage != 'Unknown':
                classified += 1
            writer.writerow([query, lineage, level, f"{confidence:.4f}"])

    logging.info(f"Classification complete. Results saved to {output_file}")
    logging.info(f"Classified: {classified}/{len(results)} ({classified/len(results):.1%})")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Advanced LCA/Best Match Taxonomic Classifier")
    parser.add_argument("--paf", required=True, help="Input PAF file")
    parser.add_argument("--taxonomy", required=True, help="Taxonomy mapping file")
    parser.add_argument("--hierarchy", required=True, help="Taxonomy hierarchy file")
    parser.add_argument("--output", required=True, help="Output TSV file")
    parser.add_argument("--processes", type=int, default=4, help="Number of parallel processes")
    
    args = parser.parse_args()
    
    main_process(
        args.paf,
        args.taxonomy,
        args.hierarchy,
        args.output,
        args.processes
    )


