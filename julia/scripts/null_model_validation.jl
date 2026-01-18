#!/usr/bin/env julia
"""
    null_model_validation.jl

Statistical validation against GC-preserving null model.

Tests whether observed symmetry metrics are significantly different from
random sequences with identical nucleotide composition.

For honest science: provides p-values demonstrating symmetries are non-random.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using BioSequences
using Statistics
using Random
using Distributions
using Printf
using Dates

# Export gc_shuffle if not already exported
if !isdefined(DarwinAtlas, :gc_shuffle)
    include(joinpath(@__DIR__, "..", "src", "Operators.jl"))
end

"""
    NullModelResult

Results from null model comparison for a single sequence.
"""
struct NullModelResult
    replicon_id::String
    length::Int
    real_orbit_ratio::Float64
    mean_shuffle::Float64
    std_shuffle::Float64
    z_score::Float64
    p_value::Float64
    n_shuffles::Int
    real_dmin_norm::Float64
    mean_dmin_shuffle::Float64
end

"""
    compute_null_statistics(seq::LongDNA, replicon_id::String;
                           n_shuffles::Int=100, seed::Int=42) -> NullModelResult

Compare real sequence metrics against GC-shuffled null model.

# Arguments
- `seq`: DNA sequence to analyze
- `replicon_id`: Identifier for the sequence
- `n_shuffles`: Number of shuffle replicates (default: 100)
- `seed`: Random seed for reproducibility

# Returns
`NullModelResult` with z-score and p-value.
"""
function compute_null_statistics(
    seq::LongDNA,
    replicon_id::String;
    n_shuffles::Int=100,
    seed::Int=42
)::NullModelResult

    rng = MersenneTwister(seed)
    n = length(seq)

    # Compute real metrics
    real_orbit_ratio = orbit_ratio(seq)
    real_dmin_norm = dmin_normalized(seq)

    # Generate shuffled sequences and compute metrics
    shuffle_orbit_ratios = Vector{Float64}(undef, n_shuffles)
    shuffle_dmin_norms = Vector{Float64}(undef, n_shuffles)

    for i in 1:n_shuffles
        shuffled = gc_shuffle(seq; rng=rng)
        shuffle_orbit_ratios[i] = orbit_ratio(shuffled)
        shuffle_dmin_norms[i] = dmin_normalized(shuffled)
    end

    # Compute statistics
    mean_or = mean(shuffle_orbit_ratios)
    std_or = std(shuffle_orbit_ratios)

    # Z-score (how many standard deviations from null mean)
    # Note: lower orbit_ratio = more symmetric, so negative z = more symmetric than random
    z_score = std_or > 0 ? (real_orbit_ratio - mean_or) / std_or : 0.0

    # Two-tailed p-value from standard normal
    p_value = 2 * (1 - cdf(Normal(), abs(z_score)))

    return NullModelResult(
        replicon_id,
        n,
        real_orbit_ratio,
        mean_or,
        std_or,
        z_score,
        p_value,
        n_shuffles,
        real_dmin_norm,
        mean(shuffle_dmin_norms)
    )
end

"""
    run_null_model_validation(; n_test_seqs::Int=10, seq_length::Int=1000,
                               n_shuffles::Int=100, seed::Int=42)

Run null model validation on synthetic sequences.

Demonstrates the validation methodology before running on real data.
"""
function run_null_model_validation(;
    n_test_seqs::Int=10,
    seq_length::Int=1000,
    n_shuffles::Int=100,
    seed::Int=42
)
    println("=" ^ 70)
    println("NULL MODEL VALIDATION - STATISTICAL SIGNIFICANCE TEST")
    println("=" ^ 70)
    println()
    println("Parameters:")
    println("  Test sequences: $n_test_seqs")
    println("  Sequence length: $seq_length bp")
    println("  Shuffles per sequence: $n_shuffles")
    println("  Random seed: $seed")
    println()

    rng = MersenneTwister(seed)
    results = Vector{NullModelResult}()

    println("Running null model comparisons...")
    println()

    for i in 1:n_test_seqs
        # Generate random sequence
        seq = randdnaseq(rng, seq_length)
        replicon_id = "synthetic_$i"

        result = compute_null_statistics(seq, replicon_id; n_shuffles=n_shuffles, seed=seed+i)
        push!(results, result)

        @printf("  %s: orbit_ratio=%.4f, null_mean=%.4f, z=%.2f, p=%.4f\n",
                replicon_id, result.real_orbit_ratio, result.mean_shuffle,
                result.z_score, result.p_value)
    end

    # Summary statistics
    println()
    println("-" ^ 70)
    println("SUMMARY")
    println("-" ^ 70)

    z_scores = [r.z_score for r in results]
    p_values = [r.p_value for r in results]

    println(@sprintf("  Mean |z-score|: %.3f", mean(abs.(z_scores))))
    println(@sprintf("  Significant (p < 0.05): %d / %d (%.1f%%)",
                    sum(p_values .< 0.05), length(p_values),
                    100 * sum(p_values .< 0.05) / length(p_values)))
    println(@sprintf("  Highly significant (p < 0.01): %d / %d (%.1f%%)",
                    sum(p_values .< 0.01), length(p_values),
                    100 * sum(p_values .< 0.01) / length(p_values)))

    # For random sequences, we expect ~5% false positives at p < 0.05
    println()
    println("Interpretation:")
    println("  For random sequences, ~5% should be significant at p < 0.05.")
    println("  Higher rates indicate real symmetry patterns in the data.")

    return results
end

"""
    validate_special_sequences()

Test null model on sequences with known symmetry properties.
"""
function validate_special_sequences()
    println()
    println("=" ^ 70)
    println("SPECIAL SEQUENCE VALIDATION")
    println("=" ^ 70)
    println()

    # Test 1: Highly symmetric (periodic) sequence
    periodic = LongDNA{4}(repeat("ACGT", 250))  # 1000 bp, period 4
    result_periodic = compute_null_statistics(periodic, "periodic_ACGT_x250")
    println("Periodic (ACGT×250):")
    @printf("  orbit_ratio=%.4f, null_mean=%.4f, z=%.2f, p=%.2e\n",
            result_periodic.real_orbit_ratio, result_periodic.mean_shuffle,
            result_periodic.z_score, result_periodic.p_value)
    println("  Expected: Very low orbit_ratio, highly significant negative z")

    println()

    # Test 2: Palindromic sequence
    half = randdnaseq(500)
    palindrome = half * reverse(half)
    result_palindrome = compute_null_statistics(palindrome, "palindrome_1000bp")
    println("Palindrome (1000 bp):")
    @printf("  orbit_ratio=%.4f, null_mean=%.4f, z=%.2f, p=%.2e\n",
            result_palindrome.real_orbit_ratio, result_palindrome.mean_shuffle,
            result_palindrome.z_score, result_palindrome.p_value)
    println("  Expected: orbit_ratio ~0.5, significant negative z")

    println()

    # Test 3: Random sequence (control)
    random_seq = randdnaseq(1000)
    result_random = compute_null_statistics(random_seq, "random_1000bp")
    println("Random (1000 bp, control):")
    @printf("  orbit_ratio=%.4f, null_mean=%.4f, z=%.2f, p=%.4f\n",
            result_random.real_orbit_ratio, result_random.mean_shuffle,
            result_random.z_score, result_random.p_value)
    println("  Expected: orbit_ratio ~1.0, non-significant z")

    println()
    println("=" ^ 70)
end

"""
    write_validation_report(results::Vector{NullModelResult}, output_path::String)

Write validation results to markdown report.
"""
function write_validation_report(results::Vector{NullModelResult}, output_path::String)
    open(output_path, "w") do io
        println(io, "# Null Model Validation Report")
        println(io)
        println(io, "Generated: $(now())")
        println(io)
        println(io, "## Methodology")
        println(io)
        println(io, "For each sequence, we compare the observed `orbit_ratio` against a null")
        println(io, "distribution generated by GC-preserving shuffles. This tests whether the")
        println(io, "observed symmetry is significantly different from random expectation.")
        println(io)
        println(io, "- **Null model**: 100 GC-shuffled sequences per replicon")
        println(io, "- **Test statistic**: z-score = (observed - null_mean) / null_std")
        println(io, "- **Significance**: Two-tailed p-value from standard normal distribution")
        println(io)
        println(io, "## Results")
        println(io)
        println(io, "| Replicon | Length | orbit_ratio | null_mean | z-score | p-value |")
        println(io, "|----------|--------|-------------|-----------|---------|---------|")

        for r in results
            @printf(io, "| %s | %d | %.4f | %.4f | %.2f | %.4f |\n",
                    r.replicon_id, r.length, r.real_orbit_ratio,
                    r.mean_shuffle, r.z_score, r.p_value)
        end

        println(io)
        println(io, "## Summary Statistics")
        println(io)

        z_scores = [r.z_score for r in results]
        p_values = [r.p_value for r in results]

        println(io, "- Mean |z-score|: $(round(mean(abs.(z_scores)), digits=3))")
        println(io, "- Significant (p < 0.05): $(sum(p_values .< 0.05)) / $(length(p_values))")
        println(io, "- Highly significant (p < 0.01): $(sum(p_values .< 0.01)) / $(length(p_values))")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io, "Under the null hypothesis (no real symmetry), we expect ~5% of sequences")
        println(io, "to appear significant at p < 0.05 by chance. Rates substantially higher")
        println(io, "than this indicate genuine symmetry patterns in the genomic data.")
    end

    println("Validation report written to: $output_path")
end

function main()
    # Run synthetic validation
    results = run_null_model_validation(n_test_seqs=20, seq_length=500, n_shuffles=100)

    # Test special sequences
    validate_special_sequences()

    # Write report
    mkpath("docs")
    write_validation_report(results, "docs/VALIDATION_REPORT.md")

    println()
    println("=" ^ 70)
    println("NULL MODEL VALIDATION COMPLETE")
    println("=" ^ 70)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
