#!/usr/bin/env julia

# Base-only executable test driver.  It intentionally invokes both validators
# as separate Julia processes so neither can accidentally reuse test state.

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const SCRIPTS = joinpath(ROOT, "julia", "scripts")
const FIXTURES = joinpath(ROOT, "data", "fixtures", "v3_scientific_gates")

function require(condition::Bool, message::String)
    condition || error(message)
end

function evaluate(script::String, fixture::String)::String
    command = `$(Base.julia_cmd()) --startup-file=no $(joinpath(SCRIPTS, script)) $(joinpath(FIXTURES, fixture))`
    strip(read(command, String))
end

function evaluate_path(script::String, path::String)::String
    command = `$(Base.julia_cmd()) --startup-file=no $(joinpath(SCRIPTS, script)) $path`
    strip(read(command, String))
end

function expect_status(script::String, fixture::String, status::String)
    first = evaluate(script, fixture)
    second = evaluate(script, fixture)
    require(first == second, "nondeterministic output for $fixture")
    require(occursin("\"status\":\"$status\"", first), "expected $status for $fixture: $first")
    first
end

oric_pass = expect_status("evaluate_oric_terminus_gate.jl", "oric_pass.tsv", "REFUSE")
require(occursin("\"metric_status\":\"PASS\"", oric_pass), "OriC positive fixture should pass the metric only")
require(occursin("\"evidence_scope\":\"fixture\"", oric_pass), "OriC scope must be explicit")
require(occursin("\"scientific_claim_permitted\":false", oric_pass), "fixture cannot permit a scientific claim")
require(occursin("fixture_scope_not_scientific_evidence", oric_pass), "positive fixture must be refused scientifically")
require(occursin("split_group_cluster_median_v1", oric_pass), "OriC bootstrap must be split-group clustered")
require(occursin("\"oof_records\":8", oric_pass), "OriC fixture must evaluate eight unique OOF records")
require(occursin("\"split_groups\":4", oric_pass), "OriC fixture must retain four split groups")
require(occursin("\"median_relative_error_reduction\":0.725", oric_pass), "OriC fixture should retain 72.5% median reduction")
expect_status("evaluate_oric_terminus_gate.jl", "oric_fail.tsv", "FAIL")
oric_refusal = expect_status("evaluate_oric_terminus_gate.jl", "oric_refuse_leak.tsv", "REFUSE")
require(occursin("split_group_leaks_train_test", oric_refusal), "OriC split-group leakage must be explicit")
oric_oof_refusal = expect_status("evaluate_oric_terminus_gate.jl", "oric_refuse_oof.tsv", "REFUSE")
require(occursin("record_not_exactly_once_test", oric_oof_refusal), "OriC OOF duplication must be explicit")

rc_pass = expect_status("evaluate_rc_equivariance_benchmark.jl", "rc_benchmark_pass.tsv", "REFUSE")
require(occursin("\"metric_status\":\"PASS\"", rc_pass), "RC positive fixture should pass the metric only")
require(occursin("\"evidence_scope\":\"fixture\"", rc_pass), "RC scope must be explicit")
require(occursin("\"scientific_claim_permitted\":false", rc_pass), "RC fixture cannot permit a scientific claim")
require(occursin("fixture_scope_not_scientific_evidence", rc_pass), "RC positive fixture must be refused scientifically")
require(occursin("\"rc_equivariant_auroc\":1.0", rc_pass), "RC fixture should retain exact AUROC 1")
expect_status("evaluate_rc_equivariance_benchmark.jl", "rc_benchmark_fail.tsv", "FAIL")
rc_refusal = expect_status("evaluate_rc_equivariance_benchmark.jl", "rc_benchmark_refuse_leak.tsv", "REFUSE")
require(occursin("taxonomic_group_leaks_train_test", rc_refusal), "RC leakage must be explicit")
rc_duplicate = expect_status("evaluate_rc_equivariance_benchmark.jl", "rc_benchmark_refuse_duplicate_id.tsv", "REFUSE")
require(occursin("duplicate_case_id_across_splits", rc_duplicate), "RC duplicate case IDs must be explicit")
rc_cross_split_leak = expect_status("evaluate_rc_equivariance_benchmark.jl", "rc_benchmark_refuse_cross_split_group.tsv", "REFUSE")
require(occursin("taxonomic_group_leaks_train_test", rc_cross_split_leak), "RC cross-split taxonomic leakage must be explicit")

# A fixture must not become scientific evidence by changing only its scope
# column.  Held-out promotion remains deliberately unavailable until a frozen
# cohort, labels/splits and prediction-derivation receipt are implemented.
mktempdir() do directory
    for (script, fixture) in (
        ("evaluate_oric_terminus_gate.jl", "oric_pass.tsv"),
        ("evaluate_rc_equivariance_benchmark.jl", "rc_benchmark_pass.tsv"),
    )
        source = read(joinpath(FIXTURES, fixture), String)
        relabelled = replace(source, "\tfixture" => "\theld_out_grouped_cohort")
        path = joinpath(directory, fixture)
        write(path, relabelled)
        result = evaluate_path(script, path)
        require(occursin("\"status\":\"REFUSE\"", result), "scope relabel must refuse for $fixture: $result")
        require(occursin("\"metric_status\":\"NOT_EVALUATED\"", result), "held-out metric must stay unevaluated for $fixture")
        require(occursin("held_out_derivation_contract_not_implemented", result), "missing derivation contract must be explicit for $fixture")
        require(occursin("\"scientific_claim_permitted\":false", result), "relabelled fixture cannot permit a scientific claim")
    end
end

println("DOSA_V3_JULIA_SCIENTIFIC_SECONDARY_GATES_PASS fixtures=9 relabel_refusals=2 bootstrap_replicates=1000 fixture_scientific_passes=0")
