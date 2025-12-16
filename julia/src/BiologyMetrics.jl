"""
    BiologyMetrics.jl

Integration module for computing all biology metrics (k-mer, GC skew, IR).

Loads sequences from FASTA files and computes metrics in batch.
"""

using BioSequences: LongDNA, DNA_G, DNA_C
using FASTX: FASTA
using CodecZlib: GzipDecompressorStream
using DataFrames
using CSV
using ProgressMeter
using JSON3
using Dates

# These will be available when included after other modules in DarwinAtlas.jl
# For now, we'll include the necessary functions directly

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
    # Find assembly accession from replicon_id (format: GCF_XXX_repN)
    assembly_acc = match(r"^(GCF_[^_]+)", replicon_id)
    if assembly_acc === nothing
        return nothing
    end

    fasta_path = joinpath(raw_dir, "$(assembly_acc.match)_genomic.fna.gz")
    if !isfile(fasta_path)
        return nothing
    end

    # Extract replicon index from replicon_id
    rep_match = match(r"_rep([0-9]+)$", replicon_id)
    if rep_match === nothing
        return nothing
    end
    rep_idx = parse(Int, rep_match.captures[1])

    # Open FASTA and find the replicon
    open(fasta_path, "r") do io
        reader = FASTA.Reader(GzipDecompressorStream(io))
        current_idx = 0
        for record in reader
            current_idx += 1
            if current_idx == rep_idx
                seq = LongDNA{4}(FASTA.sequence(record))
                close(reader)
                return seq
            end
        end
        close(reader)
    end

    return nothing
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
                    data = JSON3.read(line)
                    push!(records, RepliconRecord(
                        get(data, :assembly_accession, "unknown"),
                        get(data, :replicon_id, "unknown"),
                        get(data, :replicon_accession, nothing),
                        parse_replicon_type(get(data, :replicon_type, "OTHER")),
                        get(data, :length_bp, 0),
                        get(data, :gc_fraction, 0.0),
                        get(data, :taxonomy_id, 0),
                        get(data, :organism_name, "Unknown"),
                        parse_source_db(get(data, :source, "REFSEQ")),
                        today(),
                        get(data, :checksum_sha256, "")
                    ))
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

            # Compute k-mer inversion for k=6 on each replichore
            leading_kmer = compute_kmer_inversion(leading, 6; replichore="leading")
            lagging_kmer = compute_kmer_inversion(lagging, 6; replichore="lagging")

            # Extract x_k for k=6
            x_k_leading = filter(r -> r.k == 6, leading_kmer)
            x_k_lagging = filter(r -> r.k == 6, lagging_kmer)

            push!(replichore_data, (
                replicon_id=replicon_id,
                replichore="leading",
                length_bp=length(leading),
                gc_fraction=gc_content(leading),
                x_k_6=nrow(x_k_leading) > 0 ? x_k_leading.x_k[1] : 0.0
            ))
            push!(replichore_data, (
                replicon_id=replicon_id,
                replichore="lagging",
                length_bp=length(lagging),
                gc_fraction=gc_content(lagging),
                x_k_6=nrow(x_k_lagging) > 0 ? x_k_lagging.x_k[1] : 0.0
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

# Helper functions (duplicated from other modules for standalone use)
function parse_replicon_type(s)
    s_upper = uppercase(string(s))
    if s_upper == "CHROMOSOME"
        return CHROMOSOME
    elseif s_upper == "PLASMID"
        return PLASMID
    else
        return OTHER
    end
end

function parse_source_db(s)
    s_upper = uppercase(string(s))
    if s_upper == "GENBANK"
        return GENBANK
    else
        return REFSEQ
    end
end

# gc_content is available from Operators.jl via DarwinAtlas

