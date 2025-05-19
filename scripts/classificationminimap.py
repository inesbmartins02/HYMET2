#!/usr/bin/env python3
import os
import csv
from collections import defaultdict
import argparse
from multiprocessing import Pool
import logging
import sys
from operator import itemgetter

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

def get_top_lineages(taxid_weights, total_weight, taxonomy_hierarchy, max_options):
    if total_weight == 0:
        return [("Unknown", "root", 0.0)]

    lineage_scores = []
    for taxid, weight in taxid_weights.items():
        if taxid in taxonomy_hierarchy:
            lineage = taxonomy_hierarchy[taxid]
            level = determine_taxonomic_level(lineage)
            confidence = weight / total_weight
            lineage_scores.append((lineage, level, confidence))
    
    # Sort by confidence score descending and limit to max_options
    lineage_scores.sort(key=itemgetter(2), reverse=True)
    return lineage_scores[:max_options] if lineage_scores else [("Unknown", "root", 0.0)]

def process_query(args):
    query, refs, ref_abundance, taxonomy, taxonomy_hierarchy, max_candidates = args
    
    # Check for exact matches first
    exact_matches = [ref for ref, _, is_exact in refs if is_exact and ref in taxonomy]
    if exact_matches:
        taxid = taxonomy[exact_matches[0]]
        if taxid in taxonomy_hierarchy:
            lineage = taxonomy_hierarchy[taxid]
            level = determine_taxonomic_level(lineage)
            return (query, [(lineage, level, 1.0)])
    
    # Calculate weighted lineages for non-exact matches
    taxid_weights, total_weight = calculate_weighted_lineage(refs, ref_abundance, taxonomy)
    top_lineages = get_top_lineages(taxid_weights, total_weight, taxonomy_hierarchy, max_candidates)
    
    return (query, top_lineages)

def main_process(paf_file, taxonomy_file, hierarchy_file, output_file, processes=4, max_candidates=5):
    taxonomy = load_taxonomy_file(taxonomy_file)
    taxonomy_hierarchy = load_taxonomy_hierarchy_file(hierarchy_file)
    query_map, ref_abundance = parse_paf_file(paf_file)

    tasks = [(query, refs, ref_abundance, taxonomy, taxonomy_hierarchy, max_candidates) 
             for query, refs in query_map.items()]

    results = []
    with Pool(processes) as pool:
        results = pool.map(process_query, tasks)

    with open(output_file, 'w') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(['Query', 'Confidence', 'Lineage', 'Taxonomic Level'])
        
        classified = 0
        for query, lineages in results:
            primary_lineage = lineages[0][0]
            if primary_lineage != 'Unknown':
                classified += 1
            
            # Write each lineage (up to max_candidates) as separate rows
            for lineage, level, confidence in lineages[:max_candidates]:
                writer.writerow([query, f"{confidence:.4f}", lineage, level])

    logging.info(f"Classification complete. Results saved to {output_file}")
    logging.info(f"Classified: {classified}/{len(results)} ({classified/len(results):.1%})")
    logging.info(f"Maximum candidates shown per query: {max_candidates}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Advanced LCA/Best Match Taxonomic Classifier")
    parser.add_argument("--paf", required=True, help="Input PAF file")
    parser.add_argument("--taxonomy", required=True, help="Taxonomy mapping file")
    parser.add_argument("--hierarchy", required=True, help="Taxonomy hierarchy file")
    parser.add_argument("--output", required=True, help="Output TSV file")
    parser.add_argument("--processes", type=int, default=4, help="Number of parallel processes")
    parser.add_argument("--max-candidates", type=int, default=5, 
                       help="Maximum number of candidate classifications to show (1-10)")
    
    args = parser.parse_args()
    
    # Validate max-candidates
    if args.max_candidates < 1:
        args.max_candidates = 1
        logging.warning("max-candidates cannot be less than 1. Setting to 1.")
    elif args.max_candidates > 10:
        args.max_candidates = 10
        logging.warning("max-candidates cannot be greater than 10. Setting to 10.")
    
    main_process(
        args.paf,
        args.taxonomy,
        args.hierarchy,
        args.output,
        args.processes,
        args.max_candidates
    )