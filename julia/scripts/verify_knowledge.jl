#!/usr/bin/env julia
"""
    verify_knowledge.jl

Verify Atlas epistemic Knowledge JSONL against Demetrios schema.
Checks:
1. Provenance fields present and non-empty
2. Epsilon/error bounds >= 0
3. Confidence in [0,1]
4. Validity predicate holds for each record
5. No-miracles rule: epsilon constraints

Produces: data/epistemic/atlas_knowledge_report.md
Exit code: 0 if all pass, 1 if failures
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using JSON3
using Dates

struct ValidationResult
    rule::String
    passed::Bool
    message::String
    record_idx::Int
end

# Validation rules
function check_provenance(rec::Dict, idx::Int)::Vector{ValidationResult}
    results = ValidationResult[]
    prov = get(rec, "provenance", nothing)

    if prov === nothing
        push!(results, ValidationResult("provenance_present", false, "Missing provenance object", idx))
        return results
    end

    # Required fields
    required = ["atlas_git_sha", "timestamp_utc"]
    for field in required
        val = get(prov, field, nothing)
        if val === nothing || (val isa String && isempty(val))
            push!(results, ValidationResult("provenance_$field", false, "Missing or empty $field", idx))
        else
            push!(results, ValidationResult("provenance_$field", true, "", idx))
        end
    end

    results
end

function check_epsilon(rec::Dict, idx::Int)::ValidationResult
    eps = get(rec, "epsilon", nothing)
    if eps !== nothing && eps isa Number && eps < 0
        return ValidationResult("epsilon_nonneg", false, "Epsilon $eps < 0", idx)
    end
    ValidationResult("epsilon_nonneg", true, "", idx)
end

function check_confidence(rec::Dict, idx::Int)::ValidationResult
    conf = get(rec, "confidence", nothing)
    if conf !== nothing && conf isa Number
        if conf < 0 || conf > 1
            return ValidationResult("confidence_range", false, "Confidence $conf not in [0,1]", idx)
        end
    end
    ValidationResult("confidence_range", true, "", idx)
end

function check_validity(rec::Dict, idx::Int)::ValidationResult
    validity = get(rec, "validity", nothing)
    if validity === nothing
        return ValidationResult("validity_present", false, "Missing validity object", idx)
    end

    holds = get(validity, "holds", nothing)
    if holds === nothing
        return ValidationResult("validity_holds", false, "Missing validity.holds", idx)
    end

    if holds == false
        metric = get(rec, "metric_name", "unknown")
        value = get(rec, "value", "?")
        pred = get(validity, "predicate", "?")
        return ValidationResult("validity_holds", false, "Validity failed for $metric=$value (predicate: $pred)", idx)
    end

    ValidationResult("validity_holds", true, "", idx)
end

function check_value_constraints(rec::Dict, idx::Int)::Vector{ValidationResult}
    results = ValidationResult[]
    metric = get(rec, "metric_name", "")
    value = get(rec, "value", nothing)

    if value === nothing || ismissing(value)
        return results
    end

    # Specific metric constraints
    if metric == "gc_fraction" && value isa Number
        if !(0.0 <= value <= 1.0)
            push!(results, ValidationResult("gc_fraction_range", false, "gc_fraction=$value not in [0,1]", idx))
        else
            push!(results, ValidationResult("gc_fraction_range", true, "", idx))
        end
    end

    if metric == "orbit_ratio" && value isa Number
        if !(0.25 <= value <= 1.0)
            push!(results, ValidationResult("orbit_ratio_range", false, "orbit_ratio=$value not in [0.25,1]", idx))
        else
            push!(results, ValidationResult("orbit_ratio_range", true, "", idx))
        end
    end

    if metric in ["dmin_over_L", "dmin_normalized"] && value isa Number
        if !(0.0 <= value <= 1.0)
            push!(results, ValidationResult("dmin_range", false, "$metric=$value not in [0,1]", idx))
        else
            push!(results, ValidationResult("dmin_range", true, "", idx))
        end
    end

    if metric == "length_bp" && value isa Number
        if value <= 0
            push!(results, ValidationResult("length_positive", false, "length_bp=$value <= 0", idx))
        else
            push!(results, ValidationResult("length_positive", true, "", idx))
        end
    end

    results
end

function validate_jsonl(path::String)::Tuple{Vector{ValidationResult}, Int}
    all_results = ValidationResult[]
    total_records = 0

    open(path, "r") do io
        for (idx, line) in enumerate(eachline(io))
            isempty(strip(line)) && continue
            total_records += 1

            try
                rec = JSON3.read(line, Dict)

                # Run all checks
                append!(all_results, check_provenance(rec, idx))
                push!(all_results, check_epsilon(rec, idx))
                push!(all_results, check_confidence(rec, idx))
                push!(all_results, check_validity(rec, idx))
                append!(all_results, check_value_constraints(rec, idx))

            catch e
                push!(all_results, ValidationResult("json_parse", false, "Parse error: $e", idx))
            end
        end
    end

    (all_results, total_records)
end

function generate_report(results::Vector{ValidationResult}, total_records::Int, output_path::String)
    failures = filter(r -> !r.passed, results)
    passes = filter(r -> r.passed, results)

    # Group failures by rule
    failures_by_rule = Dict{String,Vector{ValidationResult}}()
    for f in failures
        if !haskey(failures_by_rule, f.rule)
            failures_by_rule[f.rule] = ValidationResult[]
        end
        push!(failures_by_rule[f.rule], f)
    end

    open(output_path, "w") do io
        println(io, "# Atlas Epistemic Knowledge Validation Report")
        println(io)
        println(io, "Generated: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
        println(io)
        println(io, "## Summary")
        println(io)
        println(io, "| Metric | Value |")
        println(io, "|--------|-------|")
        println(io, "| Total Records | $total_records |")
        println(io, "| Total Checks | $(length(results)) |")
        println(io, "| Passed | $(length(passes)) |")
        println(io, "| Failed | $(length(failures)) |")
        println(io, "| Pass Rate | $(round(100 * length(passes) / max(1, length(results)), digits=2))% |")
        println(io)

        if isempty(failures)
            println(io, "## Result: PASSED")
            println(io)
            println(io, "All epistemic invariants satisfied.")
        else
            println(io, "## Result: FAILED")
            println(io)
            println(io, "### Failures by Rule")
            println(io)

            for (rule, rule_failures) in sort(collect(failures_by_rule), by=x->-length(x[2]))
                println(io, "#### $rule ($(length(rule_failures)) failures)")
                println(io)

                # Show top 10
                for f in rule_failures[1:min(10, end)]
                    println(io, "- Record $(f.record_idx): $(f.message)")
                end

                if length(rule_failures) > 10
                    println(io, "- ... and $(length(rule_failures) - 10) more")
                end
                println(io)
            end
        end

        # Validation rules reference
        println(io, "## Validation Rules")
        println(io)
        println(io, "1. **provenance_present**: Provenance object must exist")
        println(io, "2. **provenance_atlas_git_sha**: Git SHA must be present")
        println(io, "3. **provenance_timestamp_utc**: Timestamp must be present")
        println(io, "4. **epsilon_nonneg**: Error bounds must be >= 0")
        println(io, "5. **confidence_range**: Confidence must be in [0,1]")
        println(io, "6. **validity_holds**: Validity predicate must hold")
        println(io, "7. **gc_fraction_range**: GC fraction in [0,1]")
        println(io, "8. **orbit_ratio_range**: Orbit ratio in [0.25,1]")
        println(io, "9. **dmin_range**: d_min/L in [0,1]")
        println(io, "10. **length_positive**: Sequence length > 0")
    end

    length(failures) == 0
end

function main()
    data_dir = get(ARGS, 1, joinpath(@__DIR__, "..", "..", "data"))
    epistemic_dir = joinpath(data_dir, "epistemic")

    jsonl_path = joinpath(epistemic_dir, "atlas_knowledge.jsonl")
    report_path = joinpath(epistemic_dir, "atlas_knowledge_report.md")

    if !isfile(jsonl_path)
        println("ERROR: $jsonl_path not found")
        println("Run export_knowledge.jl first")
        return 1
    end

    println("Validating epistemic knowledge layer...")
    println("  Input: $jsonl_path")

    results, total = validate_jsonl(jsonl_path)
    passed = generate_report(results, total, report_path)

    failures = count(r -> !r.passed, results)
    println("  Total records: $total")
    println("  Checks passed: $(count(r -> r.passed, results))")
    println("  Checks failed: $failures")
    println("  Report: $report_path")

    if passed
        println("\nVALIDATION PASSED")
        return 0
    else
        println("\nVALIDATION FAILED - see report for details")
        return 1
    end
end

exit(main())
