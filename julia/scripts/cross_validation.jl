#!/usr/bin/env julia
"""
Fail-closed development comparison for Julia vs Sounio kernels.

This transitional script still uses the historical FFI surface. It cannot
satisfy the publication validation gate, which compares persisted artifacts.

Usage:
    julia --project=julia julia/scripts/cross_validation.jl [--verbose] [--seed SEED] [--n-random N]
"""

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const TRANSITIONAL_SOUNIO_LIBRARY = joinpath(
    REPOSITORY_ROOT,
    "demetrios",
    "target",
    "release",
    "libdarwin_kernels.so",
)

# Check the producer boundary before loading Julia packages. This guarantees a
# deterministic blocked result even when the validator environment is absent.
if !isfile(TRANSITIONAL_SOUNIO_LIBRARY)
    println(stderr, "BLOCKED: Sounio producer library is unavailable.")
    println(stderr, "Expected transitional library: $TRANSITIONAL_SOUNIO_LIBRARY")
    println(stderr, "Julia-only checks are not cross-validation and cannot return PASS here.")
    exit(2)
end

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

# Run cross-validation
println("Running transitional Sounio/Julia comparison with:")
println("  Seed: $seed")
println("  Random sequences: $n_random")
println("  Verbose: $verbose")

results = run_cross_validation(; verbose=verbose, n_random=n_random, seed=seed)

# Exit with appropriate code
total_failed = sum(r.n_failed for r in values(results))
exit(total_failed > 0 ? 1 : 0)
