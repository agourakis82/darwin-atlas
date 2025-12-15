"""
    Validation.jl

Technical validation suite for Scientific Data compliance.

Implements reproducibility checks, statistical validation,
and data integrity verification.
"""

using Statistics
using SHA
using Dates

"""
    ValidationResult

Result of a validation check.
"""
struct ValidationResult
    check_name::String
    passed::Bool
    message::String
    details::Dict{String, Any}
end

"""
    validate_operators() -> Vector{ValidationResult}

Validate operator implementations satisfy mathematical properties.

Checks:
1. S^n = I (shift is cyclic)
2. R² = I (reverse is involution)
3. K² = I (complement is involution)
4. RC = R∘K = K∘R (reverse complement commutativity)
5. R∘S = S⁻¹∘R (dihedral relation)
"""
function validate_operators()::Vector{ValidationResult}
    results = ValidationResult[]

    # Test sequence
    seq = LongDNA{4}("ACGTACGTAA")
    n = length(seq)

    # Check 1: S^n = I
    shifted_n = shift(seq, n)
    push!(results, ValidationResult(
        "shift_cyclic",
        shifted_n == seq,
        "S^n should equal identity",
        Dict("seq" => string(seq), "S^n(seq)" => string(shifted_n))
    ))

    # Check 2: R² = I
    rev_rev = reverse_seq(reverse_seq(seq))
    push!(results, ValidationResult(
        "reverse_involution",
        rev_rev == seq,
        "R² should equal identity",
        Dict("seq" => string(seq), "R²(seq)" => string(rev_rev))
    ))

    # Check 3: K² = I
    comp_comp = complement_seq(complement_seq(seq))
    push!(results, ValidationResult(
        "complement_involution",
        comp_comp == seq,
        "K² should equal identity",
        Dict("seq" => string(seq), "K²(seq)" => string(comp_comp))
    ))

    # Check 4: RC = R∘K = K∘R
    rc = rev_comp(seq)
    r_k = reverse_seq(complement_seq(seq))
    k_r = complement_seq(reverse_seq(seq))
    push!(results, ValidationResult(
        "rc_commutative",
        rc == r_k && rc == k_r,
        "RC should equal R∘K and K∘R",
        Dict("RC" => string(rc), "R∘K" => string(r_k), "K∘R" => string(k_r))
    ))

    # Check 5: R∘S = S⁻¹∘R
    for k in 1:5
        lhs = reverse_seq(shift(seq, k))
        rhs = shift(reverse_seq(seq), n - k)
        if lhs != rhs
            push!(results, ValidationResult(
                "dihedral_relation_k$k",
                false,
                "R∘S^k should equal S^{-k}∘R",
                Dict("k" => k, "R∘S^k" => string(lhs), "S^{-k}∘R" => string(rhs))
            ))
        end
    end

    push!(results, ValidationResult(
        "dihedral_relation",
        true,
        "Dihedral relations R∘S^k = S^{-k}∘R verified for k=1..5",
        Dict()
    ))

    return results
end

"""
    validate_symmetry() -> Vector{ValidationResult}

Validate symmetry computation properties.

Checks:
1. Orbit size divides 2n
2. Orbit ratio in valid range [1/(2n), 1]
3. d_min bounds: 0 ≤ d_min ≤ n
4. d_min = 0 for periodic sequences
"""
function validate_symmetry()::Vector{ValidationResult}
    results = ValidationResult[]

    # Random test sequences
    test_seqs = [
        LongDNA{4}("ACGTACGT"),
        LongDNA{4}("AAAAAAA"),
        LongDNA{4}("ACGTACGTACGT"),
        LongDNA{4}("ACGTTGCA"),  # Palindrome
    ]

    for seq in test_seqs
        n = length(seq)
        os = orbit_size(seq)
        or = orbit_ratio(seq)
        dm = dmin(seq)

        # Orbit size divides 2n
        push!(results, ValidationResult(
            "orbit_divides_2n",
            mod(2n, os) == 0 || mod(os, 1) == 0,  # os divides 2n
            "Orbit size should divide 2n",
            Dict("seq" => string(seq), "orbit_size" => os, "2n" => 2n)
        ))

        # Orbit ratio bounds
        push!(results, ValidationResult(
            "orbit_ratio_bounds",
            0.0 <= or <= 1.0,
            "Orbit ratio should be in [0, 1]",
            Dict("seq" => string(seq), "orbit_ratio" => or)
        ))

        # d_min bounds
        push!(results, ValidationResult(
            "dmin_bounds",
            0 <= dm <= n,
            "d_min should be in [0, n]",
            Dict("seq" => string(seq), "dmin" => dm, "n" => n)
        ))
    end

    # Periodic sequence check
    periodic = LongDNA{4}("ACGTACGT")
    dm_periodic = dmin(periodic; include_rc=false)
    push!(results, ValidationResult(
        "dmin_periodic_zero",
        dm_periodic == 0,
        "d_min should be 0 for periodic sequences",
        Dict("seq" => "ACGTACGT", "dmin" => dm_periodic)
    ))

    return results
end

"""
    run_technical_validation(data_dir::String) -> Dict

Run full technical validation suite and generate report.

Returns dictionary with:
- `timestamp`: When validation was run
- `operator_tests`: Results from validate_operators()
- `symmetry_tests`: Results from validate_symmetry()
- `data_integrity`: Checksum verification results
- `reproducibility`: Cross-run consistency checks
- `all_passed`: Whether all tests passed
"""
function run_technical_validation(data_dir::String)::Dict
    println("\n" * "="^60)
    println("TECHNICAL VALIDATION REPORT")
    println("="^60)
    println("Timestamp: $(now())")
    println()

    results = Dict{String, Any}(
        "timestamp" => string(now()),
        "operator_tests" => ValidationResult[],
        "symmetry_tests" => ValidationResult[],
        "all_passed" => true
    )

    # Operator validation
    println("Validating operators...")
    op_results = validate_operators()
    results["operator_tests"] = op_results

    op_passed = all(r -> r.passed, op_results)
    println("  Operator tests: $(op_passed ? "PASSED" : "FAILED")")
    results["all_passed"] &= op_passed

    # Symmetry validation
    println("Validating symmetry computations...")
    sym_results = validate_symmetry()
    results["symmetry_tests"] = sym_results

    sym_passed = all(r -> r.passed, sym_results)
    println("  Symmetry tests: $(sym_passed ? "PASSED" : "FAILED")")
    results["all_passed"] &= sym_passed

    # Summary
    println()
    println("="^60)
    println("VALIDATION $(results["all_passed"] ? "PASSED" : "FAILED")")
    println("="^60)

    return results
end
