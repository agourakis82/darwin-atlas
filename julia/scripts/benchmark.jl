#!/usr/bin/env julia
"""
    benchmark.jl

Benchmark Darwin Atlas operators and symmetry computations.
Compares performance across sequence lengths.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using BioSequences
using Random
using Printf

"""
    generate_sequence(length::Int, seed::Int) -> LongDNA{4}

Generate a pseudo-random DNA sequence.
"""
function generate_sequence(length::Int, seed::Int)::LongDNA{4}
    rng = MersenneTwister(seed)
    bases = [DNA_A, DNA_C, DNA_G, DNA_T]
    return LongDNA{4}([rand(rng, bases) for _ in 1:length])
end

"""
    benchmark_operators(seq::LongDNA, iterations::Int) -> Int

Benchmark operator functions.
"""
function benchmark_operators(seq::LongDNA, iterations::Int)::Int
    total_ops = 0

    for _ in 1:iterations
        # Shift operations
        _ = shift(seq, 1)
        _ = shift(seq, length(seq) ÷ 2)
        total_ops += 2

        # Reverse
        rev = reverse_seq(seq)
        total_ops += 1

        # Complement
        comp = complement_seq(seq)
        total_ops += 1

        # Reverse complement
        rc = rev_comp(seq)
        total_ops += 1

        # Hamming distance
        _ = hamming_distance(seq, rev)
        _ = hamming_distance(seq, rc)
        total_ops += 2
    end

    return total_ops
end

"""
    benchmark_symmetry(seq::LongDNA, iterations::Int) -> Int

Benchmark symmetry detection functions.
"""
function benchmark_symmetry(seq::LongDNA, iterations::Int)::Int
    total_ops = 0

    for _ in 1:iterations
        # Orbit computations
        _ = orbit_size(seq)
        _ = orbit_ratio(seq)
        total_ops += 2

        # Fixed point detection
        _ = is_palindrome(seq)
        _ = is_rc_fixed(seq)
        total_ops += 2
    end

    return total_ops
end

"""
    benchmark_approx(seq::LongDNA, iterations::Int) -> Int

Benchmark approximate metric functions.
"""
function benchmark_approx(seq::LongDNA, iterations::Int)::Int
    total_ops = 0

    for _ in 1:iterations
        # d_min computations (expensive - O(n^2))
        _ = dmin(seq)
        _ = dmin_normalized(seq)
        total_ops += 2
    end

    return total_ops
end

function main()
    println("="^60)
    println("DARWIN ATLAS BENCHMARK - JULIA")
    println("="^60)
    println()

    # Parameters - match Sounio benchmark
    iterations = 100
    seed = 42
    lengths = [10, 50, 100]  # Match Sounio

    results = Dict{String, Vector{Float64}}()
    results["operators"] = Float64[]
    results["symmetry"] = Float64[]
    results["approx"] = Float64[]

    total_time = 0.0
    total_ops = 0

    for (idx, len) in enumerate(lengths)
        seq = generate_sequence(len, seed + idx - 1)

        println("Sequence length: $len")

        # Operators benchmark
        t_ops = @elapsed ops = benchmark_operators(seq, iterations)
        push!(results["operators"], t_ops)
        total_ops += ops
        @printf("  Operators:  %.4f s (%d ops)\n", t_ops, ops)

        # Symmetry benchmark
        t_sym = @elapsed ops = benchmark_symmetry(seq, iterations)
        push!(results["symmetry"], t_sym)
        total_ops += ops
        @printf("  Symmetry:   %.4f s (%d ops)\n", t_sym, ops)

        # Approx benchmark (only for smaller sequences)
        if len <= 100
            iters_approx = iterations ÷ 10
            t_approx = @elapsed ops = benchmark_approx(seq, iters_approx)
            push!(results["approx"], t_approx)
            total_ops += ops
            @printf("  Approx:     %.4f s (%d ops)\n", t_approx, ops)
        end

        total_time += t_ops + t_sym
        if len <= 100
            total_time += results["approx"][end]
        end

        println()
    end

    println("="^60)
    println("SUMMARY")
    println("="^60)
    @printf("Total time:       %.4f s\n", total_time)
    @printf("Total operations: %d\n", total_ops)
    @printf("Ops/second:       %.0f\n", total_ops / total_time)
    println()

    # Breakdown by function type
    println("Time by function type:")
    @printf("  Operators: %.4f s (%.1f%%)\n",
            sum(results["operators"]),
            100 * sum(results["operators"]) / total_time)
    @printf("  Symmetry:  %.4f s (%.1f%%)\n",
            sum(results["symmetry"]),
            100 * sum(results["symmetry"]) / total_time)
    @printf("  Approx:    %.4f s (%.1f%%)\n",
            sum(results["approx"]),
            100 * sum(results["approx"]) / total_time)

    println("="^60)

    return 0
end

exit(main())
