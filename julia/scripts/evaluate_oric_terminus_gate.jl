#!/usr/bin/env julia

"""
Independent Base-only secondary evaluator for a synthetic/held-out OriC and
terminus localization comparison.  It deliberately consumes predictions only:
it neither fits a model nor calls Sounio.

The TSV contract is exact and requires the strong nested baseline declaration
`gc_skew+dinucleotide_skew+dnaa_motifs` and the additive
`gc_skew+dinucleotide_skew+dnaa_motifs+dosa` declaration on every row.

For each held-out record, error is the mean of the two circular-coordinate
distances, and reduction is (baseline_error - dosa_error) / baseline_error.
Each record must occur once in every fold and exactly once in the test
partition.  The reported confidence lower bound is the 2.5% empirical
quantile of 1,000 split-group-clustered bootstrap medians.  Bootstrap draws use
SplitMix64, seed 0xD05A0C1A20260814, with one modulo draw per sampled cluster;
this is an engineering reproducibility contract, not an inferential claim
about a cohort.
"""

using SHA

const HEADER = "record_id\tsplit_id\tpartition\tsplit_group\tgenus\tspecies\treplicon_length_bp\ttrue_oric_bp\ttrue_terminus_bp\tbaseline_oric_bp\tbaseline_terminus_bp\tdosa_oric_bp\tdosa_terminus_bp\tbaseline_model\tdosa_model\tevidence_scope"
const BASELINE = "gc_skew+dinucleotide_skew+dnaa_motifs"
const DOSA_MODEL = "gc_skew+dinucleotide_skew+dnaa_motifs+dosa"
const EVIDENCE_SCOPES = ("fixture", "held_out_grouped_cohort")
const BOOTSTRAP_REPLICATES = 1000
const BOOTSTRAP_SEED = UInt64(0xD05A0C1A20260814)

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

function median_value(values::Vector{Float64})::Float64
    isempty(values) && error("median requires at least one value")
    ordered = sort(values)
    n = length(ordered)
    isodd(n) ? ordered[(n + 1) ÷ 2] : (ordered[n ÷ 2] + ordered[n ÷ 2 + 1]) / 2
end

function empirical_quantile(values::Vector{Float64}, probability::Float64)::Float64
    isempty(values) && error("quantile requires at least one value")
    index = floor(Int, probability * (length(values) - 1)) + 1
    sort(values)[index]
end

function circular_distance(a::Int, b::Int, length_bp::Int)::Float64
    delta = abs(a - b)
    Float64(min(delta, length_bp - delta))
end

function parse_int(name::AbstractString, raw::AbstractString)::Int
    value = tryparse(Int, raw)
    isnothing(value) && error("invalid integer $name")
    value
end

function infer_evidence_scope(path::String)::String
    isfile(path) || return "unknown"
    lines = readlines(path)
    length(lines) >= 2 && lines[1] == HEADER || return "unknown"
    scopes = Set{String}()
    for line in lines[2:end]
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 16 || return "unknown"
        push!(scopes, String(fields[16]))
    end
    length(scopes) == 1 && first(scopes) in EVIDENCE_SCOPES ? first(scopes) : "unknown"
end

function parse_rows(path::String)
    lines = readlines(path)
    isempty(lines) && error("empty_tsv")
    lines[1] == HEADER || error("header_mismatch")
    rows = NamedTuple[]
    seen = Set{String}()
    for (relative_line, line) in enumerate(lines[2:end])
        line_number = relative_line + 1
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 16 || error("field_count_line_$line_number")
        record_id, split_id, partition, split_group, genus, species, length_raw, true_ori_raw,
            true_ter_raw, baseline_ori_raw, baseline_ter_raw, dosa_ori_raw,
            dosa_ter_raw, baseline_model, dosa_model, evidence_scope = fields
        all(!isempty, (record_id, split_id, partition, split_group, genus, species, evidence_scope)) ||
            error("empty_identity_or_scope_line_$line_number")
        partition in ("train", "test") || error("invalid_partition_line_$line_number")
        evidence_scope in EVIDENCE_SCOPES || error("invalid_evidence_scope_line_$line_number")
        baseline_model == BASELINE || error("weak_or_unknown_baseline_line_$line_number")
        dosa_model == DOSA_MODEL || error("dosa_model_not_additive_line_$line_number")
        key = "$split_id\t$record_id"
        key in seen && error("duplicate_record_within_split")
        push!(seen, key)
        length_bp = parse_int("replicon_length_bp", length_raw)
        coordinates = map(x -> parse_int("coordinate", x),
            (true_ori_raw, true_ter_raw, baseline_ori_raw, baseline_ter_raw, dosa_ori_raw, dosa_ter_raw))
        length_bp > 1 || error("invalid_replicon_length")
        all(x -> 0 <= x < length_bp, coordinates) || error("coordinate_outside_circular_replicon")
        push!(rows, (; record_id, split_id, partition, split_group, genus, species,
            evidence_scope, length_bp,
            true_ori=coordinates[1], true_ter=coordinates[2], baseline_ori=coordinates[3],
            baseline_ter=coordinates[4], dosa_ori=coordinates[5], dosa_ter=coordinates[6]))
    end
    isempty(rows) && error("no_rows")
    rows
end

function validate_splits(rows)
    scopes = Set(r.evidence_scope for r in rows)
    length(scopes) == 1 || error("mixed_evidence_scopes")
    scope = String(first(scopes))
    split_groups = Set(r.split_group for r in rows)
    length(split_groups) >= 3 || error("insufficient_split_groups")
    split_ids = sort!(unique(r.split_id for r in rows))
    length(split_ids) >= 2 || error("insufficient_held_out_splits")

    group_taxonomy = Dict{String,String}()
    taxonomy_group = Dict{String,String}()
    for row in rows
        taxonomy = "$(row.genus)\t$(row.species)"
        if haskey(group_taxonomy, row.split_group) && group_taxonomy[row.split_group] != taxonomy
            error("split_group_maps_multiple_taxa")
        end
        if haskey(taxonomy_group, taxonomy) && taxonomy_group[taxonomy] != row.split_group
            error("taxon_maps_multiple_split_groups")
        end
        group_taxonomy[row.split_group] = taxonomy
        taxonomy_group[taxonomy] = row.split_group
    end

    records = Dict{String,Vector{NamedTuple}}()
    for row in rows
        push!(get!(records, row.record_id, NamedTuple[]), row)
    end
    expected_splits = Set(split_ids)
    for (record_id, record_rows) in records
        length(record_rows) == length(split_ids) || error("record_missing_or_duplicate_fold:$record_id")
        Set(r.split_id for r in record_rows) == expected_splits || error("record_missing_or_duplicate_fold:$record_id")
        count(r -> r.partition == "test", record_rows) == 1 || error("record_not_exactly_once_test:$record_id")
        anchor = first(record_rows)
        all(r -> r.split_group == anchor.split_group && r.genus == anchor.genus &&
            r.species == anchor.species && r.length_bp == anchor.length_bp &&
            r.true_ori == anchor.true_ori && r.true_ter == anchor.true_ter &&
            r.evidence_scope == anchor.evidence_scope, record_rows) ||
            error("record_identity_drift_across_folds:$record_id")
    end

    test_rows = NamedTuple[]
    for split_id in split_ids
        split_rows = [r for r in rows if r.split_id == split_id]
        assignment = Dict{String,String}()
        for row in split_rows
            if haskey(assignment, row.split_group) && assignment[row.split_group] != row.partition
                error("split_group_leaks_train_test")
            end
            assignment[row.split_group] = row.partition
        end
        any(r -> r.partition == "train", split_rows) || error("split_has_no_train_rows")
        held_out = [r for r in split_rows if r.partition == "test"]
        isempty(held_out) && error("split_has_no_test_rows")
        length(Set(r.split_group for r in held_out)) >= 2 || error("insufficient_held_out_groups")
        append!(test_rows, held_out)
    end
    sort!(test_rows; by=r -> (r.split_group, r.record_id))
    test_rows, scope, length(split_groups)
end

function bootstrap_lower(clustered_reductions::Dict{String,Vector{Float64}})::Float64
    groups = sort!(collect(keys(clustered_reductions)))
    length(groups) >= 2 || error("bootstrap_requires_multiple_split_groups")
    rng = SplitMix64(BOOTSTRAP_SEED)
    samples = Float64[]
    for _ in 1:BOOTSTRAP_REPLICATES
        sampled = Float64[]
        for _ in eachindex(groups)
            append!(sampled, clustered_reductions[groups[draw_index!(rng, length(groups))]])
        end
        push!(samples, median_value(sampled))
    end
    empirical_quantile(samples, 0.025)
end

json_number(value::Float64) = string(round(value; digits=6))
sha256_file(path::String) = bytes2hex(SHA.sha256(read(path)))
const EVALUATOR_SHA256 = sha256_file(@__FILE__)

function emit(status::String; evidence_scope::String="unknown", metric_status::String="NOT_EVALUATED",
              reason::String="", n::Int=0, n_groups::Int=0,
              median_reduction::Float64=0.0, ci_lower::Float64=0.0,
              input_sha256::String="unavailable")
    print("{\"kind\":\"dosa_oric_terminus_secondary_gate\",\"status\":\"$status\",")
    print("\"metric_status\":\"$metric_status\",\"evidence_scope\":\"$evidence_scope\",")
    print("\"evaluator_language\":\"Julia\",\"evaluator_sha256\":\"$EVALUATOR_SHA256\",\"input_predictions_sha256\":\"$input_sha256\",")
    print("\"scientific_claim_permitted\":$(status == "PASS" && evidence_scope == "held_out_grouped_cohort"),")
    print("\"baseline\":\"$BASELINE\",\"dosa_model\":\"$DOSA_MODEL\",")
    print("\"bootstrap\":{\"algorithm\":\"splitmix64_modulo_split_group_cluster_median_v1\",\"seed\":\"0xD05A0C1A20260814\",\"replicates\":$BOOTSTRAP_REPLICATES,\"ci_lower_quantile\":0.025},")
    print("\"oof_records\":$n,\"split_groups\":$n_groups,\"median_relative_error_reduction\":$(json_number(median_reduction)),\"bootstrap_ci_lower\":$(json_number(ci_lower))")
    !isempty(reason) && print(",\"reason\":\"$reason\"")
    println("}")
end

function main(args, scope_ref::Base.RefValue{String})
    length(args) == 1 || error("usage: evaluate_oric_terminus_gate.jl <predictions.tsv>")
    input_sha256 = sha256_file(args[1])
    scope_ref[] = infer_evidence_scope(args[1])
    rows = parse_rows(args[1])
    scopes = Set(r.evidence_scope for r in rows)
    length(scopes) == 1 && (scope_ref[] = String(first(scopes)))
    test_rows, evidence_scope, n_groups = validate_splits(rows)
    evidence_scope == "held_out_grouped_cohort" &&
        error("held_out_derivation_contract_not_implemented")
    reductions = Dict{String,Vector{Float64}}()
    for row in test_rows
        baseline_error = (circular_distance(row.true_ori, row.baseline_ori, row.length_bp) +
                          circular_distance(row.true_ter, row.baseline_ter, row.length_bp)) / 2
        baseline_error > 0 || error("undefined_relative_reduction_zero_baseline_error")
        dosa_error = (circular_distance(row.true_ori, row.dosa_ori, row.length_bp) +
                      circular_distance(row.true_ter, row.dosa_ter, row.length_bp)) / 2
        push!(get!(reductions, row.split_group, Float64[]),
              (baseline_error - dosa_error) / baseline_error)
    end
    all_reductions = reduce(vcat, values(reductions))
    observed_median = median_value(all_reductions)
    lower = bootstrap_lower(reductions)
    metric_status = observed_median >= 0.10 && lower > 0.0 ? "PASS" : "FAIL"
    status = metric_status == "PASS" && evidence_scope == "fixture" ? "REFUSE" : metric_status
    reason = status == "REFUSE" ? "fixture_scope_not_scientific_evidence" :
             status == "FAIL" ? "median_reduction_below_10pct_or_ci_not_positive" : ""
    emit(status; evidence_scope, metric_status, n=length(all_reductions), n_groups,
         median_reduction=observed_median, ci_lower=lower, reason, input_sha256)
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
