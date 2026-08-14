#!/usr/bin/env julia

"""
Independent Base-only evaluator for paired RC-equivariant versus
non-equivariant violation predictions.  Each case must carry exactly R, RC,
and ORIGIN_SHIFT views with one injected binary violation label.  A taxonomic
group is genus+species and may appear in exactly one partition per split.

AUROC is rank-sum AUROC with average ranks for tied IEEE Float64 scores.  The
reported paired bootstrap is stratified by injected label at the case level,
preserves all three transformations in each sampled case, uses SplitMix64 seed
0xD05A0A0C20260814, and has 1,000 fixed replicates.  The bootstrap is descriptive; the declared pass
criterion is exactly equivariant AUROC >= 0.90 plus leakage-free splits.  A
fixture may pass that metric contract but is refused as scientific evidence.
"""

using SHA

const HEADER = "case_id\tsplit_id\tpartition\tgenus\tspecies\ttransform\tviolation_label\trc_equivariant_score\tnon_equivariant_score\tevidence_scope"
const TRANSFORMS = ("R", "RC", "ORIGIN_SHIFT")
const EVIDENCE_SCOPES = ("fixture", "held_out_grouped_cohort")
const BOOTSTRAP_REPLICATES = 1000
# Hexadecimal digits cannot contain U; this value is the frozen machine seed.
const BOOTSTRAP_SEED = UInt64(0xD05A0A0C20260814)

mutable struct SplitMix64
    state::UInt64
end

function next_u64!(rng::SplitMix64)::UInt64
    rng.state += UInt64(0x9E3779B97F4A7C15)
    z = rng.state
    z = (z ⊻ (z >> 30)) * UInt64(0xBF58476D1CE4E5B9)
    z = (z ⊻ (z >> 27)) * UInt64(0x94D049BB133111EB)
    z ⊻ (z >> 31)
end

draw_index!(rng::SplitMix64, bound::Int) = Int(next_u64!(rng) % UInt64(bound)) + 1

function empirical_quantile(values::Vector{Float64}, probability::Float64)::Float64
    isempty(values) && error("quantile requires values")
    sort(values)[floor(Int, probability * (length(values) - 1)) + 1]
end

function parse_score(raw::AbstractString, field::AbstractString)::Float64
    value = tryparse(Float64, raw)
    (isnothing(value) || !isfinite(value)) && error("invalid_score_$field")
    value
end

function infer_evidence_scope(path::String)::String
    isfile(path) || return "unknown"
    lines = readlines(path)
    length(lines) >= 2 && lines[1] == HEADER || return "unknown"
    scopes = Set{String}()
    for line in lines[2:end]
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 10 || return "unknown"
        push!(scopes, String(fields[10]))
    end
    length(scopes) == 1 && first(scopes) in EVIDENCE_SCOPES ? first(scopes) : "unknown"
end

function parse_rows(path::String)
    lines = readlines(path)
    isempty(lines) && error("empty_tsv")
    lines[1] == HEADER || error("header_mismatch")
    rows = NamedTuple[]
    seen = Set{String}()
    case_splits = Dict{String,String}()
    for (relative_line, line) in enumerate(lines[2:end])
        line_number = relative_line + 1
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 10 || error("field_count_line_$line_number")
        case_id, split_id, partition, genus, species, transform, label_raw, rc_raw,
            nonrc_raw, evidence_scope = fields
        all(!isempty, (case_id, split_id, partition, genus, species, evidence_scope)) ||
            error("empty_identity_or_scope_line_$line_number")
        partition in ("train", "test") || error("invalid_partition_line_$line_number")
        evidence_scope in EVIDENCE_SCOPES || error("invalid_evidence_scope_line_$line_number")
        transform in TRANSFORMS || error("unknown_transform_line_$line_number")
        label_raw in ("0", "1") || error("invalid_violation_label_line_$line_number")
        key = "$split_id\t$case_id\t$transform"
        key in seen && error("duplicate_case_transform")
        push!(seen, key)
        if haskey(case_splits, case_id) && case_splits[case_id] != split_id
            error("duplicate_case_id_across_splits:$case_id")
        end
        case_splits[case_id] = split_id
        push!(rows, (; case_id, split_id, partition, genus, species, transform,
            evidence_scope,
            label=parse(Int, label_raw), rc_score=parse_score(rc_raw, "rc_equivariant"),
            nonrc_score=parse_score(nonrc_raw, "non_equivariant")))
    end
    isempty(rows) && error("no_rows")
    rows
end

function group_cases(rows)
    scopes = Set(r.evidence_scope for r in rows)
    length(scopes) == 1 || error("mixed_evidence_scopes")
    scope = String(first(scopes))
    all_groups = Set("$(r.genus)\t$(r.species)" for r in rows)
    length(all_groups) >= 3 || error("insufficient_taxonomic_groups")
    split_ids = sort!(unique(r.split_id for r in rows))
    length(split_ids) >= 2 || error("insufficient_held_out_splits")
    global_assignment = Dict{String,String}()
    for row in rows
        group = "$(row.genus)\t$(row.species)"
        if haskey(global_assignment, group) && global_assignment[group] != row.partition
            error("taxonomic_group_leaks_train_test")
        end
        global_assignment[group] = row.partition
    end
    cases = Dict{Tuple{String,String},Vector{NamedTuple}}()
    for row in rows
        push!(get!(cases, (row.split_id, row.case_id), NamedTuple[]), row)
    end
    normalized = NamedTuple[]
    for ((split_id, case_id), entries) in cases
        length(entries) == 3 || error("case_missing_required_transform")
        sort!(entries; by=r -> r.transform)
        Set(r.transform for r in entries) == Set(TRANSFORMS) || error("case_transform_set_mismatch")
        first_entry = entries[1]
        all(r -> r.partition == first_entry.partition && r.genus == first_entry.genus &&
            r.species == first_entry.species && r.label == first_entry.label &&
            r.evidence_scope == first_entry.evidence_scope, entries) ||
            error("case_metadata_or_label_drift")
        ordered = Dict(r.transform => r for r in entries)
        push!(normalized, (; split_id, case_id, partition=first_entry.partition,
            genus=first_entry.genus, species=first_entry.species, label=first_entry.label,
            entries=[ordered[t] for t in TRANSFORMS]))
    end
    tests = NamedTuple[]
    for split_id in split_ids
        split_cases = [c for c in normalized if c.split_id == split_id]
        assignment = Dict{String,String}()
        for c in split_cases
            group = "$(c.genus)\t$(c.species)"
            if haskey(assignment, group) && assignment[group] != c.partition
                error("taxonomic_group_leaks_train_test")
            end
            assignment[group] = c.partition
        end
        any(c -> c.partition == "train", split_cases) || error("split_has_no_train_cases")
        held_out = [c for c in split_cases if c.partition == "test"]
        length(held_out) >= 4 || error("insufficient_held_out_cases")
        length(Set("$(c.genus)\t$(c.species)" for c in held_out)) >= 2 || error("insufficient_held_out_groups")
        count(c -> c.label == 1, held_out) >= 2 || error("insufficient_positive_held_out_cases")
        count(c -> c.label == 0, held_out) >= 2 || error("insufficient_negative_held_out_cases")
        append!(tests, held_out)
    end
    sort!(tests; by=c -> (c.split_id, c.case_id))
    tests, scope
end

function exact_auroc(labels::Vector{Int}, scores::Vector{Float64})::Float64
    length(labels) == length(scores) || error("auc_length_mismatch")
    positives = count(==(1), labels)
    negatives = count(==(0), labels)
    positives > 0 && negatives > 0 || error("auc_requires_both_labels")
    order = sortperm(scores; alg=Base.Sort.MergeSort)
    rank_sum = 0.0
    at = 1
    while at <= length(order)
        stop = at
        while stop < length(order) && scores[order[stop + 1]] == scores[order[at]]
            stop += 1
        end
        average_rank = (at + stop) / 2
        for i in at:stop
            labels[order[i]] == 1 && (rank_sum += average_rank)
        end
        at = stop + 1
    end
    (rank_sum - positives * (positives + 1) / 2) / (positives * negatives)
end

function flatten_cases(cases)
    labels = Int[]
    rc = Float64[]
    nonrc = Float64[]
    for case in cases, entry in case.entries
        push!(labels, case.label)
        push!(rc, entry.rc_score)
        push!(nonrc, entry.nonrc_score)
    end
    labels, rc, nonrc
end

function paired_bootstrap_delta(test_cases)::Tuple{Float64,Float64}
    positives = [c for c in test_cases if c.label == 1]
    negatives = [c for c in test_cases if c.label == 0]
    rng = SplitMix64(BOOTSTRAP_SEED)
    deltas = Float64[]
    for _ in 1:BOOTSTRAP_REPLICATES
        sampled = NamedTuple[]
        append!(sampled, (positives[draw_index!(rng, length(positives))] for _ in eachindex(positives)))
        append!(sampled, (negatives[draw_index!(rng, length(negatives))] for _ in eachindex(negatives)))
        labels, rc, nonrc = flatten_cases(sampled)
        push!(deltas, exact_auroc(labels, rc) - exact_auroc(labels, nonrc))
    end
    empirical_quantile(deltas, 0.025), empirical_quantile(deltas, 0.975)
end

json_number(value::Float64) = string(round(value; digits=6))
sha256_file(path::String) = bytes2hex(SHA.sha256(read(path)))
const EVALUATOR_SHA256 = sha256_file(@__FILE__)

function emit(status::String; evidence_scope::String="unknown", metric_status::String="NOT_EVALUATED",
              reason::String="", n_cases::Int=0, rc_auc::Float64=0.0,
              nonrc_auc::Float64=0.0, ci_lower::Float64=0.0, ci_upper::Float64=0.0,
              input_sha256::String="unavailable")
    print("{\"kind\":\"dosa_rc_equivariance_secondary_benchmark\",\"status\":\"$status\",")
    print("\"metric_status\":\"$metric_status\",\"evidence_scope\":\"$evidence_scope\",")
    print("\"evaluator_language\":\"Julia\",\"evaluator_sha256\":\"$EVALUATOR_SHA256\",\"input_predictions_sha256\":\"$input_sha256\",")
    print("\"scientific_claim_permitted\":$(status == "PASS" && evidence_scope == "held_out_grouped_cohort"),")
    print("\"transformations\":[\"R\",\"RC\",\"ORIGIN_SHIFT\"],")
    print("\"auroc_contract\":\"rank_sum_average_ties_float64_v1\",")
    print("\"bootstrap\":{\"algorithm\":\"splitmix64_stratified_case_paired_delta_v1\",\"seed\":\"0xD05A0A0C20260814\",\"replicates\":$BOOTSTRAP_REPLICATES,\"ci_quantiles\":[0.025,0.975]},")
    print("\"held_out_cases\":$n_cases,\"rc_equivariant_auroc\":$(json_number(rc_auc)),\"non_equivariant_auroc\":$(json_number(nonrc_auc)),\"paired_delta_ci_lower\":$(json_number(ci_lower)),\"paired_delta_ci_upper\":$(json_number(ci_upper))")
    !isempty(reason) && print(",\"reason\":\"$reason\"")
    println("}")
end

function main(args, scope_ref::Base.RefValue{String})
    length(args) == 1 || error("usage: evaluate_rc_equivariance_benchmark.jl <predictions.tsv>")
    input_sha256 = sha256_file(args[1])
    scope_ref[] = infer_evidence_scope(args[1])
    rows = parse_rows(args[1])
    scopes = Set(r.evidence_scope for r in rows)
    length(scopes) == 1 && (scope_ref[] = String(first(scopes)))
    test_cases, evidence_scope = group_cases(rows)
    evidence_scope == "held_out_grouped_cohort" &&
        error("held_out_derivation_contract_not_implemented")
    labels, rc, nonrc = flatten_cases(test_cases)
    rc_auc = exact_auroc(labels, rc)
    nonrc_auc = exact_auroc(labels, nonrc)
    lower, upper = paired_bootstrap_delta(test_cases)
    metric_status = rc_auc >= 0.90 ? "PASS" : "FAIL"
    status = metric_status == "PASS" && evidence_scope == "fixture" ? "REFUSE" : metric_status
    reason = status == "REFUSE" ? "fixture_scope_not_scientific_evidence" :
             status == "FAIL" ? "rc_equivariant_auroc_below_0_90" : ""
    emit(status; evidence_scope, metric_status, n_cases=length(test_cases), rc_auc,
         nonrc_auc, ci_lower=lower, ci_upper=upper, reason, input_sha256)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    scope_ref = Ref("unknown")
    try
        main(ARGS, scope_ref)
    catch err
        input_sha256 = length(ARGS) == 1 && isfile(ARGS[1]) ? sha256_file(ARGS[1]) : "unavailable"
        emit("REFUSE"; evidence_scope=scope_ref[],
             reason=replace(sprint(showerror, err), '"' => '\''), input_sha256)
    end
end
