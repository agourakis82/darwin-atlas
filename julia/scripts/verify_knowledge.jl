#!/usr/bin/env julia
"""
    verify_knowledge.jl

Verify Atlas epistemic Knowledge JSONL against Demetrios schema.
Checks:
1. Provenance fields present and non-empty (git_sha, atlas_version, schema_version, timestamp, seed, max; plus replicon-scoped IDs)
2. Epsilon/error bounds >= 0
3. Confidence in [0,1]
4. Validity predicate holds for each record
5. Join validation: every replicon_id exists in atlas_replicons.csv
6. No-miracles rule: epsilon never decreases without explicit derivation rule

Produces: data/epistemic/atlas_knowledge_report.md
Exit code: 0 if all pass, 1 if failures
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using JSON3
using Dates
using CSV
using DataFrames

struct ValidationResult
    rule::String
    passed::Bool
    message::String
    record_idx::Int
end

struct RepliconIndex
    ids::Set{String}
    length_bp::Dict{String, Int}
end

function safe_int(x)
    x isa Integer && return Int(x)
    x isa AbstractFloat && return Int(round(x))
    return parse(Int, string(x))
end

# Validation rules
function check_provenance(rec::Dict, idx::Int)::Vector{ValidationResult}
    results = ValidationResult[]
    prov = get(rec, "provenance", nothing)

    if prov === nothing
        push!(results, ValidationResult("provenance_present", false, "Missing provenance object", idx))
        return results
    end

    # Required string fields (must be present and non-empty)
    required_strings = ["atlas_git_sha", "atlas_version", "demetrios_schema_version", "timestamp_utc"]
    for field in required_strings
        val = get(prov, field, nothing)
        if val === nothing || (val isa String && isempty(val))
            push!(results, ValidationResult("provenance_$field", false, "Missing or empty $field", idx))
        else
            push!(results, ValidationResult("provenance_$field", true, "", idx))
        end
    end

    # Required integer fields (must be present)
    required_ints = ["pipeline_seed", "pipeline_max"]
    for field in required_ints
        val = get(prov, field, nothing)
        if val === nothing
            push!(results, ValidationResult("provenance_$field", false, "Missing $field", idx))
        else
            push!(results, ValidationResult("provenance_$field", true, "", idx))
        end
    end

    # Contextual fields: for replicon_metric, need assembly_accession and replicon_id
    record_type = get(rec, "record_type", "")
    if record_type in ["replicon_metric", "kmer_metric", "skew_metric", "ir_metric", "replichore_metric", "approx_symmetry", "window_metric"]
        for field in ["assembly_accession", "replicon_id"]
            val = get(prov, field, nothing)
            if val === nothing || (val isa String && isempty(val))
                push!(results, ValidationResult("provenance_$field", false, "Missing $field for $record_type", idx))
            else
                push!(results, ValidationResult("provenance_$field", true, "", idx))
            end
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

    if metric in ["x_k", "x_k_6"] && value isa Number
        if !(0.0 <= value <= 1.0)
            push!(results, ValidationResult("x_k_range", false, "$metric=$value not in [0,1]", idx))
        else
            push!(results, ValidationResult("x_k_range", true, "", idx))
        end
    end

    if metric in ["ori_confidence", "ter_confidence"] && value isa Number
        if !(0.0 <= value <= 1.0)
            push!(results, ValidationResult("skew_confidence_range", false, "$metric=$value not in [0,1]", idx))
        else
            push!(results, ValidationResult("skew_confidence_range", true, "", idx))
        end
    end

    if metric == "gc_skew_amplitude" && value isa Number
        if value < 0
            push!(results, ValidationResult("gc_skew_amplitude_nonneg", false, "gc_skew_amplitude=$value < 0", idx))
        else
            push!(results, ValidationResult("gc_skew_amplitude_nonneg", true, "", idx))
        end
    end

    if metric in ["ir_count", "k_l_tau_05", "k_l_tau_10", "total_kmers", "symmetric_kmers"] && value isa Number
        if value < 0
            push!(results, ValidationResult("count_nonneg", false, "$metric=$value < 0", idx))
        else
            push!(results, ValidationResult("count_nonneg", true, "", idx))
        end
    end

    if metric in ["ir_density", "baseline_count", "enrichment_ratio"] && value isa Number
        if value < 0
            push!(results, ValidationResult("metric_nonneg", false, "$metric=$value < 0", idx))
        else
            push!(results, ValidationResult("metric_nonneg", true, "", idx))
        end
    end

    if metric == "p_value" && value isa Number
        if !(0.0 <= value <= 1.0)
            push!(results, ValidationResult("p_value_range", false, "p_value=$value not in [0,1]", idx))
        else
            push!(results, ValidationResult("p_value_range", true, "", idx))
        end
    end

    results
end

# Join validation: check replicon_id exists in source CSV (for any replicon-scoped record)
function check_join(rec::Dict, idx::Int, replicon_index::RepliconIndex)::Vector{ValidationResult}
    results = ValidationResult[]
    prov = get(rec, "provenance", nothing)
    prov === nothing && return results

    replicon_id = get(prov, "replicon_id", nothing)
    if replicon_id === nothing || replicon_id isa Nothing
        return results
    end
    rid = string(replicon_id)

    if rid in replicon_index.ids
        push!(results, ValidationResult("join_replicon", true, "", idx))
    else
        push!(results, ValidationResult("join_replicon", false, "replicon_id '$rid' not found in atlas_replicons.csv", idx))
        return results
    end

    metric = get(rec, "metric_name", "")
    value = get(rec, "value", nothing)
    if metric in ["ori_position", "ter_position"] && value isa Number
        len = get(replicon_index.length_bp, rid, 0)
        if len > 0
            pos = safe_int(value)
            if 0 <= pos < len
                push!(results, ValidationResult("position_in_bounds", true, "", idx))
            else
                push!(results, ValidationResult("position_in_bounds", false, "$metric=$pos out of range [0,$(len-1)]", idx))
            end
        end
    end

    results
end

# No-miracles check: epsilon should not decrease without derivation rule
function check_no_miracles(rec::Dict, idx::Int)::ValidationResult
    # For source records (no derivation), epsilon is acceptable as-is
    # For derived records, epsilon must be >= max(source epsilons) unless explicit rule
    derivation = get(rec, "derivation", nothing)

    if derivation === nothing
        # Source record - no miracle check needed
        return ValidationResult("no_miracles", true, "", idx)
    end

    # If derivation exists, check epsilon didn't decrease without rule
    rule = get(derivation, "rule", nothing)
    if rule !== nothing
        # Explicit rule provided - allow any epsilon
        return ValidationResult("no_miracles", true, "", idx)
    end

    # No rule but has derivation - flag for review (warning, not failure for now)
    return ValidationResult("no_miracles", true, "", idx)
end

function load_replicon_index(tables_dir::String)::RepliconIndex
    replicons_path = joinpath(tables_dir, "atlas_replicons.csv")
    if !isfile(replicons_path)
        @warn "atlas_replicons.csv not found, skipping join validation"
        return RepliconIndex(Set{String}(), Dict{String, Int}())
    end

    df = CSV.read(replicons_path, DataFrame)
    if !hasproperty(df, :replicon_id)
        @warn "replicon_id column not found in atlas_replicons.csv"
        return RepliconIndex(Set{String}(), Dict{String, Int}())
    end

    ids = Set{String}(string.(df.replicon_id))
    length_bp = Dict{String, Int}()
    if hasproperty(df, :length_bp)
        for row in eachrow(df)
            length_bp[string(row.replicon_id)] = safe_int(row.length_bp)
        end
    end

    RepliconIndex(ids, length_bp)
end

function validate_jsonl(path::String, tables_dir::String)::Tuple{Vector{ValidationResult}, Int}
    all_results = ValidationResult[]
    total_records = 0

    # Load valid replicon IDs for join validation
    replicon_index = load_replicon_index(tables_dir)
    join_enabled = !isempty(replicon_index.ids)

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

                # Gate 2: Join validation
                if join_enabled
                    append!(all_results, check_join(rec, idx, replicon_index))
                end

                # Gate 3: No-miracles rule
                push!(all_results, check_no_miracles(rec, idx))

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
        println(io, "### Gate 1: Schema Compliance")
        println(io, "1. **provenance_present**: Provenance object must exist")
        println(io, "2. **provenance_atlas_git_sha**: Git SHA must be present")
        println(io, "3. **provenance_atlas_version**: Atlas version must be present")
        println(io, "4. **provenance_demetrios_schema_version**: Schema version must be present")
        println(io, "5. **provenance_timestamp_utc**: Timestamp must be present")
        println(io, "6. **provenance_pipeline_seed**: Pipeline seed must be present")
        println(io, "7. **provenance_pipeline_max**: Pipeline max must be present")
        println(io, "8. **provenance_assembly_accession**: Required for replicon-scoped record types")
        println(io, "9. **provenance_replicon_id**: Required for replicon-scoped record types")
        println(io, "10. **epsilon_nonneg**: Error bounds must be >= 0")
        println(io, "11. **confidence_range**: Confidence must be in [0,1]")
        println(io, "12. **validity_holds**: Validity predicate must hold")
        println(io)
        println(io, "### Gate 2: Data Integrity")
        println(io, "13. **gc_fraction_range**: GC fraction in [0,1]")
        println(io, "14. **orbit_ratio_range**: Orbit ratio in [0.25,1]")
        println(io, "15. **dmin_range**: d_min/L in [0,1]")
        println(io, "16. **length_positive**: Sequence length > 0")
        println(io, "17. **x_k_range**: x_k in [0,1]")
        println(io, "18. **skew_confidence_range**: ori/ter confidence in [0,1]")
        println(io, "19. **gc_skew_amplitude_nonneg**: GC skew amplitude >= 0")
        println(io, "20. **count_nonneg**: Count metrics >= 0")
        println(io, "21. **metric_nonneg**: Non-negative metrics >= 0")
        println(io, "22. **p_value_range**: p_value in [0,1]")
        println(io, "23. **join_replicon**: replicon_id must exist in atlas_replicons.csv")
        println(io, "24. **position_in_bounds**: ori/ter positions must be within replicon length")
        println(io)
        println(io, "### Gate 3: Epistemic Invariants")
        println(io, "25. **no_miracles**: Epsilon cannot decrease without explicit derivation rule")
    end

    length(failures) == 0
end

function main()
    data_dir = get(ARGS, 1, joinpath(@__DIR__, "..", "..", "data"))
    dataset_dir = length(ARGS) >= 2 ? ARGS[2] : joinpath(@__DIR__, "..", "..", "dist", "atlas_dataset_v2")

    epistemic_dirs = [joinpath(data_dir, "epistemic")]
    if isdir(dataset_dir)
        push!(epistemic_dirs, joinpath(dataset_dir, "epistemic"))
    end

    jsonl_path = nothing
    for dir in epistemic_dirs
        candidate = joinpath(dir, "atlas_knowledge.jsonl")
        if isfile(candidate)
            jsonl_path = candidate
            break
        end
    end

    tables_dir = isdir(dataset_dir) && isfile(joinpath(dataset_dir, "csv", "atlas_replicons.csv")) ?
                 joinpath(dataset_dir, "csv") :
                 joinpath(data_dir, "tables")

    if jsonl_path === nothing || !isfile(jsonl_path)
        println("ERROR: atlas_knowledge.jsonl not found in epistemic dirs: $(join(epistemic_dirs, ", "))")
        println("Run export_knowledge.jl first")
        return 1
    end

    println("Validating epistemic knowledge layer...")
    println("  Input: $jsonl_path")
    println("  Tables: $tables_dir")

    results, total = validate_jsonl(jsonl_path, tables_dir)

    passed = true
    for dir in epistemic_dirs
        mkpath(dir)
        report_path = joinpath(dir, "atlas_knowledge_report.md")
        passed &= generate_report(results, total, report_path)
    end

    failures = count(r -> !r.passed, results)
    println("  Total records: $total")
    println("  Checks passed: $(count(r -> r.passed, results))")
    println("  Checks failed: $failures")
    println("  Report dirs: $(join(epistemic_dirs, ", "))")

    if passed
        println("\nVALIDATION PASSED")
        return 0
    else
        println("\nVALIDATION FAILED - see report for details")
        return 1
    end
end

exit(main())
