"""
    BiologyMetrics.jl

Integration module for computing all biology metrics (k-mer, GC skew, IR).

Loads sequences from FASTA files and computes metrics in batch.
"""

using BioSequences: LongDNA, DNA_G, DNA_C, DNA_A, DNA_T, DNA_N
using FASTX: FASTA
using CodecZlib: GzipDecompressorStream
using DataFrames
using CSV
using ProgressMeter
using JSON3
using Dates

# Import types from DarwinAtlas
import ..DarwinAtlas: RepliconRecord, CHROMOSOME, PLASMID, OTHER, REFSEQ, GENBANK

export compute_all_biology_metrics

"""
    load_sequence_from_fasta(manifest_path::String, replicon_id::String, raw_dir::String) -> Union{LongDNA, Nothing}

Load a DNA sequence from FASTA file based on replicon_id.

# Arguments
- `manifest_path`: Path to manifest.jsonl
- `replicon_id`: Replicon identifier
- `raw_dir`: Directory containing raw FASTA files

# Returns
LongDNA sequence or Nothing if not found.
"""
function load_sequence_from_fasta(
    manifest_path::String,
    replicon_id::String,
    raw_dir::String
)::Union{LongDNA, Nothing}
    # Find assembly accession from replicon_id (format: GCF_XXX.1_repN)
    # Extract everything before "_rep"
    rep_match = match(r"^(.+?)_rep([0-9]+)$", replicon_id)
    if rep_match === nothing
        return nothing
    end
    
    assembly_acc = rep_match.captures[1]  # e.g., "GCF_043161975.1"
    rep_idx = parse(Int, rep_match.captures[2])

    # Ensure raw_dir is absolute
    raw_dir_abs = abspath(raw_dir)
    if !isdir(raw_dir_abs)
        return nothing
    end

    # Try exact match first (with full version)
    fasta_path = joinpath(raw_dir_abs, "$(assembly_acc)_genomic.fna.gz")
    if !isfile(fasta_path)
        # Try without version suffix (e.g., GCF_043161975.1 -> GCF_043161975)
        base_match = match(r"^(GCF_[0-9]+)", assembly_acc)
        if base_match !== nothing
            # Search for files matching pattern
            all_files = readdir(raw_dir_abs)
            files = filter(f -> startswith(f, base_match.captures[1]) && endswith(f, "_genomic.fna.gz"), all_files)
            if !isempty(files)
                fasta_path = joinpath(raw_dir_abs, files[1])
            else
                return nothing
            end
        else
            return nothing
        end
    end
    
    # Verify file exists
    if !isfile(fasta_path)
        return nothing
    end

    # rep_idx already extracted above

    # Open FASTA and find the replicon
    try
        result_seq = nothing
        open(fasta_path, "r") do io
            reader = FASTA.Reader(GzipDecompressorStream(io))
            current_idx = 0
            for record in reader
                current_idx += 1
                if current_idx == rep_idx
                    # Filter ambiguous bases: convert to N, then filter out N
                    raw_seq = FASTA.sequence(record)
                    # Convert to LongDNA{4} (may contain ambiguous bases like Y, R, etc.)
                    # Filter to keep only canonical bases (A, C, G, T)
                    try
                        seq_raw = LongDNA{4}(raw_seq)
                        # Filter to keep only A, C, G, T (exclude ambiguous bases)
                        canonical_bases = [b for b in seq_raw if b in [DNA_A, DNA_C, DNA_G, DNA_T]]
                        if isempty(canonical_bases)
                            @warn "Sequence for $replicon_id is empty after filtering ambiguous bases"
                            close(reader)
                            return nothing
                        end
                        if length(canonical_bases) < length(seq_raw) * 0.5
                            @warn "Sequence for $replicon_id has >50% ambiguous bases, may be low quality"
                        end
                        result_seq = LongDNA{4}(canonical_bases)
                        close(reader)
                        return result_seq
                    catch e
                        @warn "Failed to parse sequence for $replicon_id (may contain invalid bases): $e"
                        close(reader)
                        return nothing
                    end
                end
            end
            close(reader)
            # If we get here, we didn't find the replicon
            # (This is normal for some assemblies with fewer replicons)
        end
        return result_seq
    catch e
        @warn "Failed to load sequence from $fasta_path for $replicon_id: $e"
        return nothing
    end
end

"""
    compute_all_biology_metrics(data_dir::String; k_max::Int=10, window_size::Int=1000) -> Dict{String, DataFrame}

Compute all biology metrics for replicons in the dataset.

# Arguments
- `data_dir`: Data directory containing manifest and raw FASTA files
- `k_max`: Maximum k-mer length (default: 10)
- `window_size`: Window size for GC skew (default: 1000)

# Returns
Dictionary mapping table names to DataFrames:
- "kmer_inversion": k-mer inversion symmetry
- "gc_skew_ori_ter": GC skew and ori/ter estimates
- "replichore_metrics": Per-replichore metrics
- "inverted_repeats_summary": IR enrichment

# Side Effects
Writes CSV files to data_dir/tables/
"""
function compute_all_biology_metrics(
    data_dir::String;
    k_max::Int=10,
    window_size::Int=1000
)::Dict{String, DataFrame}
    manifest_path = joinpath(data_dir, "manifest", "manifest.jsonl")
    raw_dir = joinpath(data_dir, "raw")
    tables_dir = joinpath(data_dir, "tables")

    mkpath(tables_dir)

    # Load replicon records
    records = RepliconRecord[]
    if isfile(manifest_path)
        open(manifest_path, "r") do io
            for line in eachline(io)
                isempty(strip(line)) && continue
                try
                    push!(records, JSON3.read(line, RepliconRecord))
                catch e
                    @warn "Failed to parse manifest line: $e"
                end
            end
        end
    end

    if isempty(records)
        @warn "No replicon records found"
        return Dict{String, DataFrame}()
    end

    println("Computing biology metrics for $(length(records)) replicons...")

    # Load sequences
    println("Loading sequences...")
    seq_records = Tuple{String, LongDNA}[]
    p = Progress(length(records); desc="Loading: ", showspeed=true)

    for rec in records
        seq = load_sequence_from_fasta(manifest_path, rec.replicon_id, raw_dir)
        if seq !== nothing
            push!(seq_records, (rec.replicon_id, seq))
        end
        next!(p)
    end

    println("\nLoaded $(length(seq_records)) sequences")

    # Compute k-mer inversion
    println("Computing k-mer inversion symmetry...")
    kmer_df = compute_kmer_inversion_batch(seq_records, k_max)
    CSV.write(joinpath(tables_dir, "kmer_inversion.csv"), kmer_df)
    println("  - kmer_inversion.csv: $(nrow(kmer_df)) rows")

    # Compute GC skew and ori/ter
    println("Computing GC skew and ori/ter estimates...")
    gc_skew_df = compute_gc_skew_table(seq_records, window_size)
    CSV.write(joinpath(tables_dir, "gc_skew_ori_ter.csv"), gc_skew_df)
    println("  - gc_skew_ori_ter.csv: $(nrow(gc_skew_df)) rows")

    # Compute replichore metrics
    println("Computing replichore metrics...")
    replichore_data = []
    for (replicon_id, seq) in seq_records
        # Find ori/ter for this replicon
        ori_ter_row = filter(r -> r.replicon_id == replicon_id, gc_skew_df)
        if nrow(ori_ter_row) > 0
            ori = ori_ter_row.ori_position[1]
            ter = ori_ter_row.ter_position[1]

            # Split replichores
            leading, lagging = split_replichores(seq, ori, ter)

            # Compute k-mer inversion for k=6 on each replichore (single k, fast path)
            leading_res = compute_kmer_inversion_for_k(leading, 6)
            lagging_res = compute_kmer_inversion_for_k(lagging, 6)

            push!(replichore_data, (
                replicon_id=replicon_id,
                replichore="leading",
                length_bp=length(leading),
                gc_fraction=gc_content(leading),
                x_k_6=leading_res.x_k
            ))
            push!(replichore_data, (
                replicon_id=replicon_id,
                replichore="lagging",
                length_bp=length(lagging),
                gc_fraction=gc_content(lagging),
                x_k_6=lagging_res.x_k
            ))
        end
    end
    replichore_df = DataFrame(replichore_data)
    CSV.write(joinpath(tables_dir, "replichore_metrics.csv"), replichore_df)
    println("  - replichore_metrics.csv: $(nrow(replichore_df)) rows")

    # Compute inverted repeats
    println("Computing inverted repeat enrichment...")
    ir_df = compute_ir_enrichment_table(seq_records; n_baseline_samples=50)  # Reduced for speed
    CSV.write(joinpath(tables_dir, "inverted_repeats_summary.csv"), ir_df)
    println("  - inverted_repeats_summary.csv: $(nrow(ir_df)) rows")

    return Dict(
        "kmer_inversion" => kmer_df,
        "gc_skew_ori_ter" => gc_skew_df,
        "replichore_metrics" => replichore_df,
        "inverted_repeats_summary" => ir_df
    )
end
