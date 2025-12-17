#!/usr/bin/env julia
"""
    run_atlas.jl

Unified Atlas pipeline runner with scale support.

Usage:
    julia run_atlas.jl --max 50 --seed 42           # Fast gate (50 replicons)
    julia run_atlas.jl --max 200 --seed 42          # Medium gate
    julia run_atlas.jl --scale 10000 --seed 42      # Scale run
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using ArgParse
using Dates
using DataFrames
using CSV
using JSON3
using SHA

# Include storage module (Parquet writer)
include(joinpath(@__DIR__, "..", "src", "Storage.jl"))

function load_manifest_records(path::String)::Vector{RepliconRecord}
    records = RepliconRecord[]

    open(path, "r") do io
        for line in eachline(io)
            isempty(strip(line)) && continue
            push!(records, JSON3.read(line, RepliconRecord))
        end
    end

    return records
end

function reset_generated_dir(dir::String; keep::Set{String}=Set([".gitkeep"]))
    mkpath(dir)
    for entry in readdir(dir)
        entry in keep && continue
        rm(joinpath(dir, entry); recursive=true, force=true)
    end
    return nothing
end

function reset_dataset_dir(dir::String)
    mkpath(dir)
    for sub in ["partitions", "csv", "manifest"]
        path = joinpath(dir, sub)
        ispath(path) && rm(path; recursive=true, force=true)
    end
    return nothing
end

function parse_args()
    s = ArgParseSettings(
        description = "DSLG Atlas - Unified Pipeline Runner v2.0",
        prog = "run_atlas.jl"
    )

    @add_arg_table! s begin
        "--data-dir", "-d"
            help = "Data directory for downloads"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "data")
        "--output-dir", "-o"
            help = "Output directory for dataset"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "dist", "atlas_dataset_v2")
        "--max", "-m"
            help = "Maximum genomes to process (fast mode)"
            arg_type = Int
            default = 0
        "--scale", "-s"
            help = "Scale target (overrides --max)"
            arg_type = Int
            default = 0
        "--seed"
            help = "Random seed for reproducibility"
            arg_type = Int
            default = 42
        "--skip-download"
            help = "Skip NCBI download, use existing data"
            action = :store_true
        "--skip-metrics"
            help = "Skip metric computation, only generate outputs"
            action = :store_true
        "--csv-only"
            help = "Only generate CSV outputs, skip Parquet"
            action = :store_true
    end

    return ArgParse.parse_args(s)
end

function get_git_sha()
    try
        String(strip(read(`git rev-parse HEAD`, String)))
    catch
        "unknown"
    end
end

function main()
    args = parse_args()

    # Determine effective max
    max_genomes = if args["scale"] > 0
        args["scale"]
    elseif args["max"] > 0
        args["max"]
    else
        200  # Default
    end

    seed = args["seed"]
    data_dir = args["data-dir"]
    output_dir = args["output-dir"]
    git_sha = get_git_sha()

    println("\n" * "="^70)
    println("DSLG ATLAS - Demetrios Operator Symmetry Atlas")
    println("Pipeline Runner v2.0.0")
    println("="^70)
    println("Start time:    $(now())")
    println("Max genomes:   $max_genomes")
    println("Seed:          $seed")
    println("Data dir:      $data_dir")
    println("Output dir:    $output_dir")
    println("Git SHA:       $git_sha")
    println()

    # Setup directories
    mkpath(joinpath(data_dir, "raw"))
    mkpath(joinpath(data_dir, "manifest"))
    reset_dataset_dir(output_dir)

    # Step 1: Download genomes
    records = RepliconRecord[]
    if !args["skip-download"]
        println("\n[Step 1/4] Downloading genomes from NCBI...")
        records = fetch_ncbi(
            output_dir=data_dir,
            max_genomes=max_genomes,
            seed=seed
        )
        println("Downloaded $(length(records)) replicons from NCBI")
    else
        println("\n[Step 1/4] Skipping download (--skip-download)")
        # Load existing records from manifest
        manifest_path = joinpath(data_dir, "manifest", "manifest.jsonl")
        if isfile(manifest_path)
            records = load_manifest_records(manifest_path)
            println("Loaded $(length(records)) records from manifest")
        end
    end

    # Step 2: Technical validation
    println("\n[Step 2/4] Running technical validation...")
    validation = run_technical_validation(data_dir)

    if !validation["all_passed"]
        @warn "Some validation checks failed, continuing with warnings"
    end

    # Step 3: Generate tables (CSV)
    println("\n[Step 3/4] Generating output tables...")
    tables_dir = joinpath(data_dir, "tables")
    reset_generated_dir(tables_dir)

    # Generate basic tables
    generate_tables(data_dir)

    # Compute biology metrics (PR2)
    if !args["skip-metrics"]
        println("\n[Step 3b/4] Computing biology metrics...")
        biology_tables = DarwinAtlas.compute_all_biology_metrics(data_dir; k_max=10, window_size=1000)
        println("Biology metrics computed: $(keys(biology_tables))")
    end

    # Step 4: Write dataset (Parquet + CSV views)
    println("\n[Step 4/4] Writing Atlas dataset...")

    # Load generated tables
    tables = Dict{String, DataFrame}()

    csv_files = [
        "atlas_replicons.csv",
        "dicyclic_lifts.csv",
        "quaternion_results.csv",
        "approx_symmetry_stats.csv",
        "approx_symmetry_summary.csv",
        "kmer_inversion.csv",
        "gc_skew_ori_ter.csv",
        "replichore_metrics.csv",
        "inverted_repeats_summary.csv"
    ]

    for filename in csv_files
        path = joinpath(tables_dir, filename)
        if isfile(path)
            name = replace(filename, ".csv" => "")
            tables[name] = CSV.read(path, DataFrame)
            println("  Loaded $name: $(nrow(tables[name])) rows")
        end
    end

    if args["csv-only"]
        println("\nCSV-only mode, skipping Parquet output")
        # Just copy CSVs to output
        csv_out = joinpath(output_dir, "csv")
        mkpath(csv_out)
        for (name, df) in tables
            CSV.write(joinpath(csv_out, "$name.csv"), df)
        end
    else
        # Write full dataset with Parquet
        params = Dict{String, Any}(
            "max_genomes" => max_genomes,
            "seed" => seed,
            "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
        )

        dataset = write_atlas_dataset(
            tables,
            output_dir;
            version="2.0.0",
            git_sha=git_sha,
            params=params
        )

        println("\nDataset written to: $(dataset.base_path)")
    end

    # Write pipeline metadata
    metadata_path = joinpath(output_dir, "manifest", "pipeline_metadata.json")
    mkpath(dirname(metadata_path))

    metadata = Dict(
        "version" => "2.0.0",
        "timestamp_utc" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "git_sha" => git_sha,
        "parameters" => Dict(
            "max_genomes" => max_genomes,
            "seed" => seed
        ),
        "tables" => Dict(name => nrow(df) for (name, df) in tables),
        "platform" => string(Sys.KERNEL, "-", Sys.ARCH),
        "julia_version" => string(VERSION)
    )

    open(metadata_path, "w") do io
        JSON3.write(io, metadata; allow_inf=true)
    end

    println("\n" * "="^70)
    println("ATLAS PIPELINE COMPLETE")
    println("End time: $(now())")
    println("Output:   $output_dir")
    println("="^70)

    return 0
end

exit(main())
