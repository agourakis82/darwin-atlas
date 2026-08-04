#!/usr/bin/env julia

"""
Independent Base-only validator for the Sounio mini-pipeline fixture.

The validator re-reads the frozen FASTA, metadata, and rendered flat
parameter bytes, independently re-validates the parameter grammar (strict
13/15-line fixed-order form, exact domains, exact error offsets), re-derives
the metadata association, the parameterized non-overlapping positional
windows, the delta_R / delta_RC metrics, the masked k-mer imbalance fields
for k = 1..8 with explicit unavailable reasons, the fixture null-model
summaries (schema 0.3.0), and every exclusion, then rebuilds the expected
JSONL byte for byte and requires exact equality with the persisted Sounio
artifact. For the negative metadata and parameter fixtures it independently
derives the expected error tuple
(code, record, offset, byte) and requires exact equality.

It loads no packages (Base only), does not execute Sounio, and never falls
back to producing the artifact itself.
"""

if length(ARGS) < 2 || length(ARGS) > 3
    println(stderr, "usage: validate_mini_pipeline.jl <sounio-run.log> <fixture-directory> [case-set]")
    exit(2)
end

const LOG_PATH = only(ARGS[1:1])
const FIXTURE_DIRECTORY = only(ARGS[2:2])
# Case sets: "fixture" is the frozen mini-pipeline battery (19 cases);
# "cohort_smoke" is the complete-replicon engineering smoke (1 case).
const CASE_SET = length(ARGS) == 3 ? ARGS[3] : "fixture"
include(joinpath(@__DIR__, "window_pipeline_core.jl"))

const CASE_SPECS = if CASE_SET == "fixture"
    [
    (name="main", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="main", rc=0),
    (name="k8", fasta="pipeline_k8_fixture.fa", metadata="pipeline_k8_metadata.tsv", params="k8", rc=0),
    (name="null_k4", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="null_k4", rc=0),
    (name="null_k8", fasta="pipeline_k8_fixture.fa", metadata="pipeline_k8_metadata.tsv", params="null_k8", rc=0),
    (name="dinucleotide_k4", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="dinucleotide_k4", rc=0),
    (name="dinucleotide_k8", fasta="pipeline_k8_fixture.fa", metadata="pipeline_k8_metadata.tsv", params="dinucleotide_k8", rc=0),
    (name="metadata_invalid", fasta="pipeline_fixture.fa", metadata="metadata_invalid.tsv", params="main", rc=9),
    (name="metadata_mismatch", fasta="pipeline_fixture.fa", metadata="metadata_mismatch.tsv", params="main", rc=10),
    (name="metadata_short", fasta="pipeline_fixture.fa", metadata="metadata_short.tsv", params="main", rc=10),
    (name="param_window_size_zero", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_window_size_zero", rc=11),
    (name="param_stride_zero", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_stride_zero", rc=11),
    (name="param_stride_mismatch", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_stride_mismatch", rc=11),
    (name="param_k_min_two", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_k_min_two", rc=11),
    (name="param_k_max_nine", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_k_max_nine", rc=11),
    (name="param_k_max_above_window", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_k_max_above_window", rc=11),
    (name="param_unknown_policy", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_unknown_policy", rc=11),
    (name="param_extra_field", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_extra_field", rc=11),
    (name="param_null_model_unknown", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_null_model_unknown", rc=11),
    (name="param_null_replicates_mismatch", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_null_replicates_mismatch", rc=11),
]
elseif CASE_SET == "cohort_smoke"
    [(name="smoke_pOSAK1", fasta="nc_002127_1.fa", metadata="nc_002127_1_metadata.tsv", params="smoke_pOSAK1", rc=0)]
elseif CASE_SET == "cohort_plasmids"
    [
    (name="windows_pOSAK1", fasta="pOSAK1/record.fa", metadata="pOSAK1/metadata.tsv", params="windows_pOSAK1", rc=0),
    (name="windows_pO157", fasta="pO157/record.fa", metadata="pO157/metadata.tsv", params="windows_pO157", rc=0),
]
else
    error("unknown case set: $CASE_SET")
end

const DINUCLEOTIDE_SEED_FILES = Dict(
    "dinucleotide_k4" => "dinucleotide_seeds_k4.tsv",
    "dinucleotide_k8" => "dinucleotide_seeds_k8.tsv",
)



function parse_fields(line::String)
    fields = Dict{String, String}()
    for token in Iterators.drop(split(line), 1)
        pair = split(token, '='; limit=2)
        length(pair) == 2 || error("malformed Sounio field: $token")
        fields[pair[1]] = pair[2]
    end
    return fields
end

function parse_runner_log(path::String)
    cases = Dict{String, Dict{String, Any}}()
    params = Dict{String, Dict{String, String}}()
    artifacts = Dict{String, String}()
    artifact_lines = Dict{String, Int}()
    artifact_shas = Dict{String, String}()
    current = nothing

    for line in eachline(path)
        if startswith(line, "DOSA_PIPELINE_CASE ")
            fields = parse_fields(line)
            name = fields["name"]
            haskey(cases, name) && error("duplicate mini-pipeline case: $name")
            cases[name] = Dict{String, Any}(
                "expected_rc" => parse(Int, fields["expected_rc"]),
                "actual_rc" => parse(Int, fields["actual_rc"]),
                "error" => nothing,
            )
            current = name
        elseif startswith(line, "DOSA_FASTA_ERROR ")
            isnothing(current) && error("error appeared before a case marker")
            isnothing(cases[current]["error"]) || error("duplicate error for case $current")
            cases[current]["error"] = parse_fields(line)
        elseif startswith(line, "DOSA_PIPELINE_PARAMS ")
            fields = parse_fields(line)
            name = fields["name"]
            haskey(params, name) && error("duplicate parameter announcement: $name")
            params[name] = fields
        elseif startswith(line, "sounio_pipeline_jsonl_")
            rest = split(line, '='; limit=2)
            key, value = rest[1], rest[2]
            if (m = match(r"^sounio_pipeline_jsonl_artifact_(.+)$", key)) !== nothing
                artifacts[m.captures[1]] = value
            elseif key == "sounio_pipeline_jsonl_artifact"
                artifacts["main"] = value
            elseif (m = match(r"^sounio_pipeline_jsonl_lines_(.+)$", key)) !== nothing
                artifact_lines[m.captures[1]] = parse(Int, value)
            elseif key == "sounio_pipeline_jsonl_lines"
                artifact_lines["main"] = parse(Int, value)
            elseif (m = match(r"^sounio_pipeline_jsonl_sha256_(.+)$", key)) !== nothing
                artifact_shas[m.captures[1]] = value
            elseif key == "sounio_pipeline_jsonl_sha256"
                artifact_shas["main"] = value
            end
        end
    end
    return cases, params, artifacts, artifact_lines, artifact_shas
end

observed, announced_params, artifacts, artifact_lines, artifact_shas =
    parse_runner_log(LOG_PATH)
Set(keys(observed)) == Set(spec.name for spec in CASE_SPECS) || error(
    "unexpected mini-pipeline case set: $(sort!(collect(keys(observed))))",
)
Set(keys(announced_params)) == Set(spec.params for spec in CASE_SPECS) || error(
    "runner did not announce exactly the expected parameter set: " *
    "$(sort!(collect(keys(announced_params))))",
)

# Load and independently validate every announced flat parameter file once.
case_params = Dict{String, Any}()
for (name, fields) in announced_params
    flat_path = fields["flat"]
    isfile(flat_path) || error("announced flat parameter file is missing: $flat_path")
    result = load_parameters(String(read(flat_path)))
    if result isa PipelineParams
        # The runner-announced canonical JSON sha256 must equal the sha256
        # bound into the rendered flat file it produced.
        result.sha256 == fields["sha256"] || error(
            "parameter sha256 divergence for $name: flat binds $(result.sha256) " *
            "but runner announced $(fields["sha256"])",
        )
    end
    case_params[name] = result
end

validated_windows = Ref(0)

for spec in CASE_SPECS
    case = observed[spec.name]
    case["expected_rc"] == spec.rc || error("runner expectation drift for $(spec.name)")
    case["actual_rc"] == spec.rc || error("Sounio exit mismatch for $(spec.name)")

    params_or_error = case_params[spec.params]

    if spec.rc == 11
        # Parameter-negative case: Julia must independently derive the same
        # PARAM_INVALID offset from the rendered flat bytes.
        params_or_error isa PipelineError || error(
            "Julia independently accepted the flat parameters for $(spec.name)",
        )
        params_or_error.code == "PARAM_INVALID" || error(
            "Julia derived a non-parameter error for $(spec.name)",
        )
        observed_error = case["error"]
        isnothing(observed_error) && error("missing Sounio error for $(spec.name)")
        observed_error["code"] == params_or_error.code || error(
            "error code mismatch for $(spec.name): Sounio=$(observed_error["code"]) Julia=$(params_or_error.code)",
        )
        observed_error["record"] == string(params_or_error.record) || error(
            "error record mismatch for $(spec.name): Sounio=$(observed_error["record"]) Julia=$(params_or_error.record)",
        )
        observed_error["offset"] == string(params_or_error.offset) || error(
            "error offset mismatch for $(spec.name): Sounio=$(observed_error["offset"]) Julia=$(params_or_error.offset)",
        )
        observed_error["byte"] == string(params_or_error.byte) || error(
            "error byte mismatch for $(spec.name): Sounio=$(observed_error["byte"]) Julia=$(params_or_error.byte)",
        )
        continue
    end

    params_or_error isa PipelineParams || error(
        "Julia independently rejected the flat parameters for valid case $(spec.name): " *
        "$(params_or_error)",
    )
    params = params_or_error

    metadata_text = String(read(joinpath(FIXTURE_DIRECTORY, spec.metadata)))
    fasta_bytes = read(joinpath(FIXTURE_DIRECTORY, spec.fasta))

    rows_or_error = load_metadata(metadata_text)
    if rows_or_error isa PipelineError
        expected = rows_or_error
        expected_lines = String[]
    else
        seed_file = get(DINUCLEOTIDE_SEED_FILES, spec.name, nothing)
        dinucleotide_seeds = if params.null_model == "dinucleotide_shuffle"
            isnothing(seed_file) && error("missing seed-sidecar declaration for $(spec.name)")
            load_dinucleotide_seeds(joinpath(FIXTURE_DIRECTORY, seed_file), params.sha256)
        else
            Dict{Tuple{String,Int},String}()
        end
        expected_lines, error_or_nothing =
            simulate_pipeline(fasta_bytes, rows_or_error, params, dinucleotide_seeds)
        expected = error_or_nothing
    end

    if spec.rc == 0
        isnothing(expected) || error(
            "Julia independently derived an error for $(spec.name): $(expected)",
        )
        isnothing(case["error"]) || error("unexpected Sounio error for $(spec.name)")

        artifact_path = get(artifacts, spec.name, nothing)
        isnothing(artifact_path) && error("runner log does not name a JSONL artifact for $(spec.name)")
        isfile(artifact_path) || error("persisted JSONL artifact is missing: $artifact_path")
        artifact_sha = get(artifact_shas, spec.name, nothing)
        isnothing(artifact_sha) && error("runner log does not hash the JSONL artifact for $(spec.name)")
        match(r"^[0-9a-f]{64}$", artifact_sha) !== nothing ||
            error("malformed artifact sha256 in runner log for $(spec.name)")
        haskey(artifact_lines, spec.name) ||
            error("runner log does not count the JSONL lines for $(spec.name)")

        expected_bytes = join(expected_lines, "\n") * "\n"
        actual_bytes = String(read(artifact_path))
        actual_bytes == expected_bytes || error(
            "JSONL mismatch for $(spec.name): persisted Sounio artifact differs from the " *
            "independent Julia recomputation (byte-exact comparison)",
        )
        artifact_lines[spec.name] == length(expected_lines) ||
            error("runner JSONL line count mismatch for $(spec.name)")
        validated_windows[] += length(expected_lines)
    else
        expected isa PipelineError || error(
            "Julia independently derived success for negative case $(spec.name)",
        )
        observed_error = case["error"]
        isnothing(observed_error) && error("missing Sounio error for $(spec.name)")
        observed_error["code"] == expected.code || error(
            "error code mismatch for $(spec.name): Sounio=$(observed_error["code"]) Julia=$(expected.code)",
        )
        observed_error["record"] == string(expected.record) || error(
            "error record mismatch for $(spec.name): Sounio=$(observed_error["record"]) Julia=$(expected.record)",
        )
        observed_error["offset"] == string(expected.offset) || error(
            "error offset mismatch for $(spec.name): Sounio=$(observed_error["offset"]) Julia=$(expected.offset)",
        )
        observed_error["byte"] == string(expected.byte) || error(
            "error byte mismatch for $(spec.name): Sounio=$(observed_error["byte"]) Julia=$(expected.byte)",
        )
    end
end

println("DOSA_JULIA_MINI_PIPELINE_DIFFERENTIAL_OK")
println("validated_cases=$(length(CASE_SPECS)) validated_windows=$(validated_windows[]) tolerance=0")
