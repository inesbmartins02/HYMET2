#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw(time);
use Cwd 'abs_path';
use Getopt::Long;

# User-configurable parameters
my $mash_threshold_refseq = 0.98;   # Threshold for RefSeq
my $mash_threshold_gtdb = 0.98;     # Threshold for GTDB
my $mash_threshold_custom = 0.98;  # Threshold for custom database
my $classification_processes = 8;    # Number of processes for classification
my $max_top_candidates = 5;          # Default maximum number of top candidates to show

# Get command line options
GetOptions(
    "max-candidates=i" => \$max_top_candidates,
    # You can add other options here if needed
) or die "Error in command line arguments\n";

# Validate max candidates
$max_top_candidates = 1 if $max_top_candidates < 1;
$max_top_candidates = 10 if $max_top_candidates > 10;  # Setting a reasonable upper limit
print "Maximum top candidates to display: $max_top_candidates\n";

# Base paths
my $base_path = '.';

# Prompt the user for the input directory (where the .fna files are located)
print "Please enter the path to the input directory (containing .fna files): ";
chomp(my $input_dir = <STDIN>);

# Validate the input directory
unless (-d $input_dir) {
    die "Error: The input directory '$input_dir' does not exist.\n";
}

my $output_dir = "$base_path/output";
my $data_dir = "$base_path/data";
my $cache_dir = "$base_path/cache";

# Script paths
my $mash_script = "$base_path/scripts/mash.sh";
my $download_script = "$base_path/scripts/downloadDB.py";
my $minimap_script = "$base_path/scripts/minimap2.sh";
my $mashmap_script = "$base_path/scripts/mashmap.sh";
my $classification_minimap = "$base_path/scripts/classificationminimap.py";
my $classification_mashmap = "$base_path/scripts/classificationmashmap.py";

# MASH sketch files
my %sketch_files = (
    refseq => "$data_dir/sketch1.msh",   # RefSeq
    gtdb => "$data_dir/sketch2.msh",     # GTDB
    custom => "$data_dir/sketch3.msh"    # Custom
);

# Important files
my $taxonomy_file = "$data_dir/detailed_taxonomy.tsv";
my $hierarchy_file = "$data_dir/taxonomy_hierarchy.tsv";

# Create directories if they don't exist
mkdir $output_dir unless -d $output_dir;
mkdir $data_dir unless -d $data_dir;
mkdir "$data_dir/downloaded_genomes" unless -d "$data_dir/downloaded_genomes";
mkdir $cache_dir unless -d $cache_dir;

sub run_command {
    my ($command) = @_;
    print "Executing: $command\n";
    my $output = `$command 2>&1`;
    my $exit_status = $? >> 8;
   
    if ($exit_status == 0) {
        print "Success\n";
        print "$output\n" if $output;
    } else {
        print "Execution error:\n$output\n";
        exit($exit_status);
    }
    return $exit_status;
}

# Function to safely concatenate files
sub safe_concat {
    my ($output_file, @input_files) = @_;
    unlink $output_file if -e $output_file;
    
    # Method 1: Use find + xargs (better for many files)
    if (scalar(@input_files) > 100) {
        my $input_dir = $input_files[0];
        $input_dir =~ s/\/[^\/]+$//;
        run_command("find '$input_dir' -type f -name '*.fna' -print0 | xargs -0 cat > '$output_file'");
    }
    # Method 2: Process directly in Perl (for few files)
    else {
        open(my $out, '>', $output_file) or die "Cannot create $output_file: $!";
        foreach my $file (@input_files) {
            open(my $in, '<', $file) or die "Cannot read $file: $!";
            while (<$in>) { print $out $_; }
            close $in;
        }
        close $out;
    }
    
    die "Failed to create $output_file" unless -s $output_file;
}

# Function to check input .fna files
sub check_input_files {
    my $dir = shift;
    unless (-d $dir) {
        die "ERROR: Input directory not found:\n$dir";
    }
    
    my @fna_files = glob("$dir/*.fna");
    unless (@fna_files) {
        die "ERROR: No .fna files found in:\n$dir\nExisting files:\n".join("\n", glob("$dir/*"));
    }
    return @fna_files;
}

my $start_time = time();

# Step 1: Check input files
my @input_files = check_input_files($input_dir);
print "Found ".scalar(@input_files)." .fna files in input directory\n";

# Step 2: Verify MASH sketch files
foreach my $db (keys %sketch_files) {
    unless (-e $sketch_files{$db}) {
        die "ERROR: Sketch file not found for $db: $sketch_files{$db}";
    }
}

# Step 3: Run MASH for each database
my @selected_genomes_files;

foreach my $db (keys %sketch_files) {
    my $threshold = $db eq 'refseq' ? $mash_threshold_refseq :
                    $db eq 'gtdb' ? $mash_threshold_gtdb :
                    $mash_threshold_custom;
    
    my $out_prefix = "$output_dir/$db";
    push @selected_genomes_files, "${out_prefix}_selected.txt";
    
    run_command("$mash_script '$input_dir' '$sketch_files{$db}' ".
               "'${out_prefix}_screen.tab' '${out_prefix}_filtered.tab' ".
               "'${out_prefix}_sorted.tab' '${out_prefix}_top_hits.tab' ".
               "'${out_prefix}_selected.txt' $threshold");
}

# Step 4: Combine results from all three databases
safe_concat("$output_dir/combined_selected.txt", @selected_genomes_files);
run_command("sort -u -o '$output_dir/selected_genomes.txt' '$output_dir/combined_selected.txt'");

# Verify if the combined genome list was generated
unless (-s "$output_dir/selected_genomes.txt") {
    die "ERROR: Failed to generate combined selected genomes list";
}

# Step 5: Download genomes
run_command("python3 '$download_script' '$output_dir/selected_genomes.txt' ".
           "'$data_dir/downloaded_genomes' '$taxonomy_file' '$cache_dir'");

# Step 6: Analyze downloaded genomes
my $large_count = 0;
my $small_count = 0;
my @large_genomes;
my @small_genomes;

opendir(my $dh, "$data_dir/downloaded_genomes") or die "Cannot open directory: $!";
while (my $file = readdir $dh) {
    next unless $file =~ /\.fna$/;
    my $filepath = "$data_dir/downloaded_genomes/$file";
    
    # Estimate genome size
    my $size = -s $filepath;
    
    if ($size > 1_000_000_000) { # >1GB
        push @large_genomes, $filepath;
        $large_count++;
    } else {
        push @small_genomes, $filepath;
        $small_count++;
    }
}
closedir $dh;

my $total_genomes = $large_count + $small_count;
my $large_proportion = $total_genomes > 0 ? ($large_count / $total_genomes) * 100 : 0;

print "====================================\n";
print " DOWNLOADED GENOME STATISTICS\n";
print "====================================\n";
print " Total genomes: $total_genomes\n";
print " Large genomes (>1GB): $large_count ($large_proportion%)\n";
print " Small genomes: $small_count\n";
print "====================================\n";

# Step 7: Execute appropriate workflow based on size
if ($large_proportion > 70) {
    print "Predominance of large genomes (>70%), using MashMap\n";
    
    # Concatenate inputs for MashMap (safe method)
    my $concatenated_input = "$output_dir/concatenated_input.fasta";
    safe_concat($concatenated_input, @input_files);
    print "Input genomes concatenated into $concatenated_input for MashMap.\n";

    # Process each large genome
    foreach my $genome (@large_genomes) {
        my $base = $genome =~ s/.*\/([^\/]+)\.fna$/$1/r;
        run_command("$mashmap_script '$concatenated_input' '$genome' '$output_dir/${base}_mashmap.out' 8");
        run_command("python3 '$classification_mashmap' --mashmap '$output_dir/${base}_mashmap.out' ".
                   "--taxonomy '$taxonomy_file' --hierarchy '$hierarchy_file' ".
                   "--output '$output_dir/${base}_classified.tsv' --processes 8 ".
                   "--max-candidates $max_top_candidates");
    }
} else {
    print "Predominance of small genomes, using Minimap2\n";
    
    if (@small_genomes) {
        my $combined_small = "$data_dir/downloaded_genomes/combined_genomes.fasta";
        safe_concat($combined_small, @small_genomes);
        
        run_command("$minimap_script '$input_dir' '$combined_small' ".
                   "'$output_dir/reference.mmi' '$output_dir/resultados.paf'");
        run_command("python3 '$classification_minimap' --paf '$output_dir/resultados.paf' ".
                   "--taxonomy '$taxonomy_file' --hierarchy '$hierarchy_file' ".
                   "--output '$output_dir/classified_sequences.tsv' --processes 8 ".
                   "--max-candidates $max_top_candidates");
    } else {
        print "WARNING: No small genomes found to process with Minimap2!\n";
    }
}

# Step 8: Consolidate results
my $final_output = "$output_dir/final_classifications.tsv";
open(my $out, ">", $final_output) or die "Cannot create $final_output: $!";
print $out "Query\tLineage\tTaxonomic Level\tConfidence\n";

# Add MashMap results
foreach my $genome (@large_genomes) {
    my $base = $genome =~ s/.*\/([^\/]+)\.fna$/$1/r;
    my $file = "$output_dir/${base}_classified.tsv";
    if (-e $file) {
        open(my $in, "<", $file) or next;
        while (<$in>) {
            print $out $_ unless $. == 1; # Skip header
        }
        close $in;
    }
}

# Add Minimap2 results
if (-e "$output_dir/classified_sequences.tsv") {
    open(my $in, "<", "$output_dir/classified_sequences.tsv") or die $!;
    while (<$in>) {
        print $out $_ unless $. == 1; # Skip header
    }
    close $in;
}

close $out;

my $end_time = time();
my $execution_time = $end_time - $start_time;

print "\nProcessing completed successfully!\n";
print "Total execution time: ".sprintf("%.2f", $execution_time)." seconds\n";
print "Final results in: $final_output\n";
print "Used sketch files:\n";
foreach my $db (keys %sketch_files) {
    print " - $db: $sketch_files{$db}\n";
}