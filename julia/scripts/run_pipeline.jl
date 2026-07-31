#!/usr/bin/env julia
"""
Run the historical Julia-only Darwin Atlas pipeline.

This entry point is noncanonical under ADR-0001. It is retained for migration
diagnostics and MUST NOT produce release-eligible artifacts.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using ArgParse
using Dates

function parse_args()
    s = ArgParseSettings(
        description = "Darwin Operator Symmetry Atlas - Pipeline Runner",
        prog = "run_pipeline.jl"
    )

    @add_arg_table! s begin
        "--data-dir", "-d"
            help = "Data directory"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "data")
        "--max-genomes", "-m"
            help = "Maximum genomes to process"
            arg_type = Int
            default = 200
        "--seed", "-s"
            help = "Random seed"
            arg_type = Int
            default = 42
        "--skip-download"
            help = "Skip NCBI download (use existing data)"
            action = :store_true
        "--validate-only"
            help = "Only run validation, no analysis"
            action = :store_true
    end

    return ArgParse.parse_args(s)
end

function main()
    args = parse_args()

    println("\n" * "="^60)
    println("WARNING: NONCANONICAL LEGACY JULIA PIPELINE")
    println("Sounio is the required producer for release artifacts.")
    println("This run is for migration diagnostics only.")
    println("="^60)
    println("Start time: $(now())")
    println("Data directory: $(args["data-dir"])")
    println()

    data_dir = args["data-dir"]
    mkpath(joinpath(data_dir, "raw"))
    mkpath(joinpath(data_dir, "manifest"))
    mkpath(joinpath(data_dir, "tables"))

    # Step 1: Download genomes (unless skipped)
    if !args["skip-download"]
        println("\n[Step 1] Downloading genomes from NCBI...")
        records = fetch_ncbi(
            output_dir=data_dir,
            max_genomes=args["max-genomes"],
            seed=args["seed"]
        )
        println("Downloaded $(length(records)) replicons")
    else
        println("\n[Step 1] Skipping download (--skip-download)")
    end

    # Step 2: Technical validation
    println("\n[Step 2] Running technical validation...")
    validation = run_technical_validation(data_dir)

    if !validation["all_passed"]
        error("Technical validation failed! Aborting pipeline.")
    end

    if args["validate-only"]
        println("\n[Done] Validation complete (--validate-only)")
        return
    end

    # Step 3: Generate tables
    println("\n[Step 3] Generating output tables...")
    generate_tables(data_dir)

    println("\n" * "="^60)
    println("PIPELINE COMPLETE")
    println("End time: $(now())")
    println("="^60)
end

main()
