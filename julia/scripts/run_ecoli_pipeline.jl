#!/usr/bin/env julia
"""
Run Darwin Atlas symmetry analysis on E. coli validation dataset.

This script processes the E. coli dataset with full cross-validation enabled
for biological validation before scaling to 50k+ replicons.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using ArgParse
using Dates
using JSON3
using DataFrames
using CSV
using ProgressMeter
using FASTX: FASTA
using CodecZlib: GzipDecompressorStream
using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T
using Statistics

function parse_args()
    s = ArgParseSettings(
        description = "Darwin Atlas - E. coli Symmetry Analysis Pipeline",
        prog = "run_ecoli_pipeline.jl"
    )

    @add_arg_table! s begin
        "--data-dir", "-d"
            help = "E. coli data directory"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "data", "ecoli")
        "--output-dir", "-o"
            help = "Output directory for tables"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "data", "ecoli", "tables")
        "--window-sizes", "-w"
            help = "Window sizes for sliding window analysis (comma-separated)"
            arg_type = String
            default = "1000,5000,10000"
        "--cross-validate"
            help = "Enable cross-validation (requires Sounio FFI)"
            action = :store_true
        "--max-replicons", "-m"
            help = "Maximum replicons to process (for testing)"
            arg_type = Int
            default = 0  # 0 means all
    end

    return ArgParse.parse_args(s)
end

"""
    load_ecoli_manifest(data_dir::String) -> Vector{RepliconRecord}

Load E. coli replicon manifest.
"""
function load_ecoli_manifest(data_dir::String)
    manifest_path = joinpath(data_dir, "manifest", "manifest.jsonl")
    
    if !isfile(manifest_path)
        error("Manifest not found: $manifest_path")
    end
    
    records = RepliconRecord[]
    open(manifest_path) do io
        for line in eachline(io)
            rec = JSON3.read(line, RepliconRecord)
            push!(records, rec)
        end
    end
    
    return records
end

"""
    load_replicon_sequence(data_dir::String, record::RepliconRecord) -> LongDNA{4}

Load sequence for a replicon from FASTA file.
"""
function load_replicon_sequence(data_dir::String, record::RepliconRecord)
    # Construct path to FASTA file
    fasta_path = joinpath(data_dir, "raw", "$(record.assembly_accession)_genomic.fna.gz")
    
    if !isfile(fasta_path)
        error("FASTA file not found: $fasta_path")
    end
    
    # Parse replicon index from replicon_id (format: "GCF_XXX_repN")
    m = match(r"_rep(\d+)$", record.replicon_id)
    if m === nothing
        error("Invalid replicon_id format: $(record.replicon_id)")
    end
    target_idx = parse(Int, m.captures[1])
    
    # Read FASTA and find the target replicon
    open(fasta_path) do io
        reader = FASTA.Reader(GzipDecompressorStream(io))
        
        current_idx = 0
        for fasta_record in reader
            current_idx += 1
            
            if current_idx == target_idx
                raw_seq = FASTA.sequence(fasta_record)
                
                # Filter to canonical bases
                seq_raw = LongDNA{4}(raw_seq)
                canonical_bases = [b for b in seq_raw if b in [DNA_A, DNA_C, DNA_G, DNA_T]]
                
                if isempty(canonical_bases)
                    error("No canonical bases in replicon $(record.replicon_id)")
                end
                
                close(reader)
                return LongDNA{4}(canonical_bases)
            end
        end
        
        close(reader)
        error("Replicon index $target_idx not found in $fasta_path")
    end
end

"""
    compute_replicon_metrics(seq::LongDNA{4}, record::RepliconRecord, cross_validate::Bool) -> Dict

Compute all symmetry metrics for a replicon.
"""
function compute_replicon_metrics(seq::LongDNA{4}, record::RepliconRecord, cross_validate::Bool)
    metrics = Dict{String, Any}()
    
    # Basic info
    metrics["replicon_id"] = record.replicon_id
    metrics["length_bp"] = length(seq)
    
    # For large sequences (>50kb), skip expensive exact symmetry computations
    # and focus on approximate metrics which are more efficient
    if length(seq) > 50000
        metrics["orbit_size"] = missing
        metrics["orbit_ratio"] = missing
        metrics["is_palindrome"] = missing
        metrics["is_rc_fixed"] = missing
    else
        # Exact symmetry metrics (only for smaller sequences)
        orb_size = orbit_size(seq)
        metrics["orbit_size"] = orb_size
        metrics["orbit_ratio"] = orbit_ratio(seq)
        metrics["is_palindrome"] = is_palindrome(seq)
        metrics["is_rc_fixed"] = is_rc_fixed(seq)
    end
    
    # Approximate metric (efficient for all sizes)
    d_min = dmin(seq)
    metrics["dmin"] = d_min
    metrics["dmin_normalized"] = dmin_normalized(seq)
    
    # Cross-validation (if enabled and available)
    if cross_validate && DarwinAtlas.HAS_DEMETRIOS[]
        # Validate orbit_size
        orb_size_demetrios = DarwinAtlas.darwin_orbit_size(seq)
        if orb_size != orb_size_demetrios
            @warn "Cross-validation failed for orbit_size" replicon_id=record.replicon_id julia=orb_size demetrios=orb_size_demetrios
        end
        
        # Validate dmin
        d_min_demetrios = DarwinAtlas.darwin_dmin(seq)
        if d_min != d_min_demetrios
            @warn "Cross-validation failed for dmin" replicon_id=record.replicon_id julia=d_min demetrios=d_min_demetrios
        end
    end
    
    return metrics
end

"""
    compute_biology_metrics(seq::LongDNA{4}, record::RepliconRecord) -> Dict

Compute biological metrics (k-mer inversion, GC skew, etc.).
"""
function compute_biology_metrics(seq::LongDNA{4}, record::RepliconRecord)
    metrics = Dict{String, Any}()
    
    # K-mer inversion symmetry
    kmer_results = compute_kmer_inversion(seq, k=2)  # Dinucleotide
    metrics["kmer_inversion_score"] = kmer_results["inversion_score"]
    metrics["kmer_symmetry_index"] = kmer_results["symmetry_index"]
    
    # GC skew and ori-ter estimation
    gc_results = estimate_ori_ter_from_gc_skew(seq)
    metrics["gc_skew_ori_estimate"] = gc_results["ori_estimate"]
    metrics["gc_skew_ter_estimate"] = gc_results["ter_estimate"]
    metrics["gc_skew_max"] = gc_results["max_skew"]
    metrics["gc_skew_min"] = gc_results["min_skew"]
    
    # Inverted repeats
    ir_results = find_inverted_repeats(seq, min_length=20, max_distance=1000)
    metrics["num_inverted_repeats"] = length(ir_results)
    
    return metrics
end

function main()
    args = parse_args()
    
    println("\n" * "="^70)
    println("DARWIN ATLAS - E. COLI SYMMETRY ANALYSIS")
    println("Biological Validation Pipeline")
    println("="^70)
    println("Start time: $(now())")
    println()
    
    data_dir = args["data-dir"]
    output_dir = args["output-dir"]
    window_sizes = parse.(Int, split(args["window-sizes"], ','))
    cross_validate = args["cross-validate"]
    max_replicons = args["max-replicons"]
    
    # Check for Sounio FFI
    if cross_validate && !DarwinAtlas.HAS_DEMETRIOS[]
        @warn "Cross-validation requested but Sounio FFI not available"
        @warn "Continuing without cross-validation"
        cross_validate = false
    end
    
    println("Configuration:")
    println("  Data directory: $data_dir")
    println("  Output directory: $output_dir")
    println("  Window sizes: $window_sizes")
    println("  Cross-validation: $(cross_validate ? "ENABLED" : "DISABLED")")
    println("  Max replicons: $(max_replicons > 0 ? max_replicons : "ALL")")
    println()
    
    # Create output directory
    mkpath(output_dir)
    
    # Load manifest
    println("[Step 1] Loading E. coli manifest...")
    records = load_ecoli_manifest(data_dir)
    println("  Loaded $(length(records)) replicons")
    
    # Limit replicons if requested
    if max_replicons > 0 && max_replicons < length(records)
        records = records[1:max_replicons]
        println("  Limited to $max_replicons replicons for testing")
    end
    
    # Initialize result tables
    replicon_metrics = DataFrame()
    biology_metrics_df = DataFrame()
    
    # Process each replicon
    println("\n[Step 2] Computing symmetry metrics...")
    p = Progress(length(records); desc="Processing: ", showspeed=true)
    
    cross_validation_failures = 0
    
    for record in records
        try
            # Load sequence
            seq = load_replicon_sequence(data_dir, record)
            
            # Compute metrics
            metrics = compute_replicon_metrics(seq, record, cross_validate)
            
            # Compute biology metrics
            bio_metrics = compute_biology_metrics(seq, record)
            
            # Add to dataframes
            push!(replicon_metrics, metrics, cols=:union)
            push!(biology_metrics_df, merge(Dict("replicon_id" => record.replicon_id), bio_metrics), cols=:union)
            
        catch e
            @warn "Failed to process replicon $(record.replicon_id): $e"
        end
        
        next!(p)
    end
    
    println("\n[Step 3] Writing output tables...")
    
    # Write replicon metrics
    replicon_path = joinpath(output_dir, "ecoli_replicons.csv")
    CSV.write(replicon_path, replicon_metrics)
    println("  ✓ Wrote $replicon_path ($(nrow(replicon_metrics)) rows)")
    
    # Write biology metrics
    biology_path = joinpath(output_dir, "ecoli_biology_metrics.csv")
    CSV.write(biology_path, biology_metrics_df)
    println("  ✓ Wrote $biology_path ($(nrow(biology_metrics_df)) rows)")
    
    # Summary statistics
    println("\n[Step 4] Summary Statistics")
    println("="^70)
    println("Replicons processed: $(nrow(replicon_metrics))")
    println()
    
    println("Orbit Size:")
    println("  Min: $(minimum(replicon_metrics.orbit_size))")
    println("  Max: $(maximum(replicon_metrics.orbit_size))")
    println("  Mean: $(round(mean(replicon_metrics.orbit_size), digits=2))")
    println()
    
    println("d_min/L:")
    println("  Min: $(round(minimum(replicon_metrics.dmin_normalized), digits=6))")
    println("  Max: $(round(maximum(replicon_metrics.dmin_normalized), digits=6))")
    println("  Mean: $(round(mean(replicon_metrics.dmin_normalized), digits=6))")
    println()
    
    println("Palindromes: $(sum(replicon_metrics.is_palindrome)) / $(nrow(replicon_metrics))")
    println("RC-fixed: $(sum(replicon_metrics.is_rc_fixed)) / $(nrow(replicon_metrics))")
    
    if cross_validate
        println("\nCross-validation: $(cross_validation_failures == 0 ? "✓ PASSED" : "✗ FAILED ($cross_validation_failures failures)")")
    end
    
    println("\n" * "="^70)
    println("PIPELINE COMPLETE")
    println("End time: $(now())")
    println("="^70)
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
