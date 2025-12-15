"""
    CrossValidation.jl

Cross-validation between Julia and Demetrios implementations.

Ensures both implementations produce identical results,
catching bugs in either implementation.
"""

using BioSequences: LongDNA, @dna_str
using Random

# Include FFI module
include("DemetriosFFI.jl")

"""
    CrossValidationResult

Result of cross-validation for a single function.
"""
struct CrossValidationResult
    function_name::String
    n_tests::Int
    n_passed::Int
    n_failed::Int
    max_error::Float64
    failed_cases::Vector{Tuple{String, Any, Any}}  # (input_repr, julia_result, demetrios_result)
end

"""
    validate_orbit_size(seqs::Vector{LongDNA}; verbose::Bool=false) -> CrossValidationResult

Cross-validate orbit_size between Julia and Demetrios.
"""
function validate_orbit_size(seqs::Vector{LongDNA}; verbose::Bool=false)::CrossValidationResult
    n_passed = 0
    n_failed = 0
    failed_cases = Tuple{String, Any, Any}[]

    for seq in seqs
        julia_result = orbit_size(seq)
        demetrios_result = demetrios_orbit_size(seq)

        if julia_result == demetrios_result
            n_passed += 1
            verbose && println("  ✓ orbit_size($(string(seq)[1:min(20, end)])...)")
        else
            n_failed += 1
            push!(failed_cases, (string(seq), julia_result, demetrios_result))
            verbose && println("  ✗ orbit_size: Julia=$julia_result, Demetrios=$demetrios_result")
        end
    end

    return CrossValidationResult(
        "orbit_size",
        length(seqs),
        n_passed,
        n_failed,
        0.0,
        failed_cases
    )
end

"""
    validate_orbit_ratio(seqs::Vector{LongDNA}; verbose::Bool=false, tol::Float64=1e-12) -> CrossValidationResult

Cross-validate orbit_ratio between Julia and Demetrios.
"""
function validate_orbit_ratio(seqs::Vector{LongDNA}; verbose::Bool=false, tol::Float64=1e-12)::CrossValidationResult
    n_passed = 0
    n_failed = 0
    max_error = 0.0
    failed_cases = Tuple{String, Any, Any}[]

    for seq in seqs
        julia_result = orbit_ratio(seq)
        demetrios_result = demetrios_orbit_ratio(seq)
        error = abs(julia_result - demetrios_result)
        max_error = max(max_error, error)

        if error < tol
            n_passed += 1
            verbose && println("  ✓ orbit_ratio (error=$error)")
        else
            n_failed += 1
            push!(failed_cases, (string(seq), julia_result, demetrios_result))
            verbose && println("  ✗ orbit_ratio: Julia=$julia_result, Demetrios=$demetrios_result")
        end
    end

    return CrossValidationResult(
        "orbit_ratio",
        length(seqs),
        n_passed,
        n_failed,
        max_error,
        failed_cases
    )
end

"""
    validate_palindrome(seqs::Vector{LongDNA}; verbose::Bool=false) -> CrossValidationResult

Cross-validate is_palindrome between Julia and Demetrios.
"""
function validate_palindrome(seqs::Vector{LongDNA}; verbose::Bool=false)::CrossValidationResult
    n_passed = 0
    n_failed = 0
    failed_cases = Tuple{String, Any, Any}[]

    for seq in seqs
        julia_result = is_palindrome(seq)
        demetrios_result = demetrios_is_palindrome(seq)

        if julia_result == demetrios_result
            n_passed += 1
        else
            n_failed += 1
            push!(failed_cases, (string(seq), julia_result, demetrios_result))
        end
    end

    return CrossValidationResult(
        "is_palindrome",
        length(seqs),
        n_passed,
        n_failed,
        0.0,
        failed_cases
    )
end

"""
    validate_rc_fixed(seqs::Vector{LongDNA}; verbose::Bool=false) -> CrossValidationResult

Cross-validate is_rc_fixed between Julia and Demetrios.
"""
function validate_rc_fixed(seqs::Vector{LongDNA}; verbose::Bool=false)::CrossValidationResult
    n_passed = 0
    n_failed = 0
    failed_cases = Tuple{String, Any, Any}[]

    for seq in seqs
        julia_result = is_rc_fixed(seq)
        demetrios_result = demetrios_is_rc_fixed(seq)

        if julia_result == demetrios_result
            n_passed += 1
        else
            n_failed += 1
            push!(failed_cases, (string(seq), julia_result, demetrios_result))
        end
    end

    return CrossValidationResult(
        "is_rc_fixed",
        length(seqs),
        n_passed,
        n_failed,
        0.0,
        failed_cases
    )
end

"""
    validate_dmin(seqs::Vector{LongDNA}; verbose::Bool=false) -> CrossValidationResult

Cross-validate dmin between Julia and Demetrios.
"""
function validate_dmin(seqs::Vector{LongDNA}; verbose::Bool=false)::CrossValidationResult
    n_passed = 0
    n_failed = 0
    failed_cases = Tuple{String, Any, Any}[]

    for seq in seqs
        julia_result = dmin(seq)
        demetrios_result = demetrios_dmin(seq)

        if julia_result == demetrios_result
            n_passed += 1
        else
            n_failed += 1
            push!(failed_cases, (string(seq), julia_result, demetrios_result))
        end
    end

    return CrossValidationResult(
        "dmin",
        length(seqs),
        n_passed,
        n_failed,
        0.0,
        failed_cases
    )
end

"""
    validate_dicyclic(ns::Vector{Int}; verbose::Bool=false) -> CrossValidationResult

Cross-validate verify_double_cover between Julia and Demetrios.
"""
function validate_dicyclic(ns::Vector{Int}; verbose::Bool=false)::CrossValidationResult
    n_passed = 0
    n_failed = 0
    failed_cases = Tuple{String, Any, Any}[]

    for n in ns
        g = DicyclicGroup(n)
        julia_result = verify_double_cover(g)
        demetrios_result = demetrios_verify_double_cover(n)

        if julia_result == demetrios_result
            n_passed += 1
        else
            n_failed += 1
            push!(failed_cases, ("Dic_$n", julia_result, demetrios_result))
        end
    end

    return CrossValidationResult(
        "verify_double_cover",
        length(ns),
        n_passed,
        n_failed,
        0.0,
        failed_cases
    )
end

"""
    generate_test_sequences(; n_random::Int=100, seed::Int=42) -> Vector{LongDNA}

Generate a diverse set of test sequences for cross-validation.
"""
function generate_test_sequences(; n_random::Int=100, seed::Int=42)::Vector{LongDNA}
    rng = Random.MersenneTwister(seed)
    seqs = LongDNA{4}[]

    # Fixed test cases
    fixed_cases = [
        dna"ACGT",
        dna"ACGTACGT",
        dna"AAAA",
        dna"ACCA",      # Palindrome
        dna"AACCAA",    # Palindrome
        dna"ACGTTGCA",  # RC-fixed
        dna"GGCC",      # RC-fixed
        dna"ACGTACGTACGT",  # Periodic
    ]
    append!(seqs, fixed_cases)

    # Random sequences of various lengths
    bases = [DNA_A, DNA_C, DNA_G, DNA_T]
    for len in [4, 8, 16, 32, 64, 100]
        for _ in 1:n_random ÷ 6
            seq = LongDNA{4}([rand(rng, bases) for _ in 1:len])
            push!(seqs, seq)
        end
    end

    return seqs
end

"""
    run_cross_validation(; verbose::Bool=true, n_random::Int=100, seed::Int=42) -> Dict

Run full cross-validation suite.

Returns dictionary with results for each function.
"""
function run_cross_validation(; verbose::Bool=true, n_random::Int=100, seed::Int=42)::Dict
    if !demetrios_available()
        error("Demetrios library not available at $LIBPATH")
    end

    println("\n" * "="^60)
    println("CROSS-VALIDATION: Julia vs Demetrios")
    println("="^60)
    println("Demetrios version: $(demetrios_version())")
    println("Random seed: $seed")
    println()

    # Generate test sequences
    seqs = generate_test_sequences(n_random=n_random, seed=seed)
    println("Generated $(length(seqs)) test sequences")
    println()

    results = Dict{String, CrossValidationResult}()

    # Exact symmetry functions
    println("[1/6] Validating orbit_size...")
    results["orbit_size"] = validate_orbit_size(seqs; verbose=verbose)
    print_result(results["orbit_size"])

    println("[2/6] Validating orbit_ratio...")
    results["orbit_ratio"] = validate_orbit_ratio(seqs; verbose=verbose)
    print_result(results["orbit_ratio"])

    println("[3/6] Validating is_palindrome...")
    results["is_palindrome"] = validate_palindrome(seqs; verbose=verbose)
    print_result(results["is_palindrome"])

    println("[4/6] Validating is_rc_fixed...")
    results["is_rc_fixed"] = validate_rc_fixed(seqs; verbose=verbose)
    print_result(results["is_rc_fixed"])

    # Approximate metric
    println("[5/6] Validating dmin...")
    results["dmin"] = validate_dmin(seqs; verbose=verbose)
    print_result(results["dmin"])

    # Quaternion
    println("[6/6] Validating verify_double_cover...")
    results["verify_double_cover"] = validate_dicyclic(collect(2:16); verbose=verbose)
    print_result(results["verify_double_cover"])

    # Summary
    println("\n" * "="^60)
    println("SUMMARY")
    println("="^60)

    total_tests = sum(r.n_tests for r in values(results))
    total_passed = sum(r.n_passed for r in values(results))
    total_failed = sum(r.n_failed for r in values(results))

    println("Total tests: $total_tests")
    println("Passed: $total_passed")
    println("Failed: $total_failed")

    if total_failed > 0
        println("\n⚠️  CROSS-VALIDATION FAILED")
        println("Failed cases:")
        for (name, result) in results
            if result.n_failed > 0
                println("  $name: $(result.n_failed) failures")
                for (input, julia_res, demetrios_res) in result.failed_cases
                    println("    Input: $(input[1:min(40, end)])...")
                    println("    Julia: $julia_res")
                    println("    Demetrios: $demetrios_res")
                end
            end
        end
    else
        println("\n✅ CROSS-VALIDATION PASSED")
    end

    println("="^60)

    return results
end

function print_result(result::CrossValidationResult)
    status = result.n_failed == 0 ? "✓" : "✗"
    println("  $status $(result.function_name): $(result.n_passed)/$(result.n_tests) passed")
    if result.max_error > 0
        println("    Max numerical error: $(result.max_error)")
    end
end

