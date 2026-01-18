#!/usr/bin/env julia
"""
    run_window_pipeline.jl

Execute sliding window analysis pipeline on downloaded genomes.

Usage:
    julia --project=julia julia/scripts/run_window_pipeline.jl [options]

Options:
    --max-replicons N    Maximum replicons to process (default: 0 = all)
    --max-windows N      Maximum windows per replicon (default: 0 = all)
    --window-sizes W     Comma-separated window sizes (default: 100,500,1000)
    --output PATH        Output CSV path (default: data/tables/atlas_windows_exact.csv)
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using BioSequences
using ArgParse
using Dates

function parse_commandline()
    s = ArgParseSettings(description="Run window analysis pipeline")

    @add_arg_table! s begin
        "--max-replicons"
            help = "Maximum replicons to process (0 = all)"
            arg_type = Int
            default = 0
        "--max-windows"
            help = "Maximum windows per replicon (0 = all)"
            arg_type = Int
            default = 100  # Start with limit for testing
        "--window-sizes"
            help = "Comma-separated window sizes"
            arg_type = String
            default = "100,500,1000"
        "--output"
            help = "Output CSV path"
            arg_type = String
            default = "data/tables/atlas_windows_exact.csv"
        "--test"
            help = "Run quick test on synthetic data"
            action = :store_true
    end

    return ArgParse.parse_args(s)
end

function run_synthetic_test()
    println("=" ^ 60)
    println("WINDOW ANALYSIS - SYNTHETIC TEST")
    println("=" ^ 60)
    println()

    # Create test sequence (100 bp)
    seq = randdnaseq(100)
    println("Test sequence length: $(length(seq)) bp")

    # Test window extraction (no wraparound)
    window1 = extract_window(seq, 0, 20)
    println("Window [0:20]: $(length(window1)) bp")
    @assert length(window1) == 20

    # Test window extraction (wraparound)
    window2 = extract_window(seq, 90, 20)
    println("Window [90:110 wrap]: $(length(window2)) bp")
    @assert length(window2) == 20

    # Test window analysis
    result = analyze_window(seq, "test_replicon", 20, 0)
    println()
    println("Window Analysis Result:")
    println("  replicon_id: $(result.replicon_id)")
    println("  window_length: $(result.window_length)")
    println("  window_start: $(result.window_start)")
    println("  orbit_ratio: $(result.orbit_ratio)")
    println("  is_palindrome: $(result.is_palindrome)")
    println("  is_rc_fixed: $(result.is_rc_fixed)")
    println("  orbit_size: $(result.orbit_size)")
    println("  dmin: $(result.dmin)")
    println("  dmin_normalized: $(result.dmin_normalized)")

    # Test batch analysis
    println()
    println("Batch Analysis (window_size=20):")
    results = analyze_replicon_windows(seq, "test_replicon", 20; max_windows=5)
    println("  Analyzed $(length(results)) windows")

    for (i, r) in enumerate(results)
        println("  Window $i: start=$(r.window_start), orbit_ratio=$(round(r.orbit_ratio, digits=3))")
    end

    # Test multiple window sizes
    println()
    println("Multi-size Analysis:")
    for ws in [10, 20, 50]
        results = analyze_replicon_windows(seq, "test", ws; max_windows=3)
        println("  Window size $ws: $(length(results)) windows analyzed")
    end

    println()
    println("=" ^ 60)
    println("SYNTHETIC TEST PASSED")
    println("=" ^ 60)
end

function run_real_pipeline(args)
    println("=" ^ 60)
    println("DARWIN ATLAS - WINDOW ANALYSIS PIPELINE")
    println("=" ^ 60)
    println("Start time: $(now())")
    println()

    # Parse window sizes
    window_sizes = parse.(Int, split(args["window-sizes"], ","))
    println("Window sizes: $window_sizes")
    println("Max replicons: $(args["max-replicons"] == 0 ? "all" : args["max-replicons"])")
    println("Max windows per replicon: $(args["max-windows"] == 0 ? "all" : args["max-windows"])")
    println("Output: $(args["output"])")
    println()

    # Check for manifest
    manifest_path = "data/manifest/manifest.jsonl"
    raw_dir = "data/raw"

    if !isfile(manifest_path)
        error("Manifest not found at $manifest_path. Run 'make pipeline' first to download genomes.")
    end

    # Count replicons in manifest
    n_replicons = countlines(manifest_path)
    println("Found $n_replicons replicons in manifest")

    if args["max-replicons"] > 0
        n_replicons = min(n_replicons, args["max-replicons"])
        println("Processing first $n_replicons replicons")
    end

    println()

    # Run analysis
    analyze_manifest_windows(
        manifest_path,
        raw_dir,
        args["output"];
        window_sizes=window_sizes,
        max_windows_per_replicon=args["max-windows"]
    )

    println()
    println("End time: $(now())")
    println("=" ^ 60)
end

function main()
    args = parse_commandline()

    if args["test"]
        run_synthetic_test()
    else
        run_real_pipeline(args)
    end
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
