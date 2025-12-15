#!/usr/bin/env julia
"""
Cross-validation script for Julia vs Demetrios implementations.

Usage:
    julia --project=julia julia/scripts/cross_validation.jl [--verbose] [--seed SEED] [--n-random N]
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas

# Parse command line arguments
verbose = "--verbose" in ARGS || "-v" in ARGS
seed = 42
n_random = 100

for i in 1:length(ARGS)
    if ARGS[i] == "--seed" && i < length(ARGS)
        seed = parse(Int, ARGS[i+1])
    elseif ARGS[i] == "--n-random" && i < length(ARGS)
        n_random = parse(Int, ARGS[i+1])
    end
end

# Check if Demetrios is available
if !DarwinAtlas.HAS_DEMETRIOS[]
    println("⚠️  Demetrios library not found")
    println("   Expected location: demetrios/target/release/libdarwin_kernels.so")
    println("   Build with: make demetrios")
    println()
    println("Running Julia-only validation instead...")
    println()

    # Run Julia validation as fallback
    results = run_technical_validation(joinpath(@__DIR__, "..", "..", "data"))

    if results["all_passed"]
        println("\n✅ Julia implementation validated successfully")
        exit(0)
    else
        println("\n❌ Julia validation failed")
        exit(1)
    end
end

# Run cross-validation
println("Running cross-validation with:")
println("  Seed: $seed")
println("  Random sequences: $n_random")
println("  Verbose: $verbose")

results = run_cross_validation(; verbose=verbose, n_random=n_random, seed=seed)

# Exit with appropriate code
total_failed = sum(r.n_failed for r in values(results))
exit(total_failed > 0 ? 1 : 0)

