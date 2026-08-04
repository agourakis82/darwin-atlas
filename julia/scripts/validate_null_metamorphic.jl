#!/usr/bin/env julia

"""
Independent Base-only Julia validator for the null-engine metamorphic
fixture (Fase M4, extending spec section 12.1 around both null engines).

Two layers of evidence, both fail-closed:

1. Byte-exact differential: the validator re-reads the frozen
   null-metamorphic FASTA/metadata, the rendered flat parameter bytes, and
   the dinucleotide seed sidecar, recomputes every JSONL line with the
   shared Base-only engine (window_pipeline_core.jl), and requires exact
   byte equality with the persisted Sounio artifact for both cases.

2. Explicit metamorphic relations over the persisted producer output:
   - MR1 (mononucleotide identity on homopolymers): every null draw of a
     homopolymer window is the source window, so under
     mononucleotide_shuffle each null summary is degenerate
     (mean == q025 == q975, mad == 0, mean == observed metric).
   - MR2 (dinucleotide identity on unique-Euler-circuit windows):
     homopolymer and strictly alternating two-base windows have exactly one
     Eulerian circuit with fixed endpoints, so under dinucleotide_shuffle
     the same degeneracy holds.
   - MR3 (null engines actually randomize on non-degenerate windows):
     strictly alternating windows under mononucleotide_shuffle and the
     general control under both engines exhibit mad > 0 for at least one
     metric.
   - MR4 (summary coherence): for every emitted window and metric,
     null_replicates_available == null_replicates and q025 <= q975.

It loads no packages (Base only), does not execute Sounio, and never falls
back to producing the artifact itself.
"""

if length(ARGS) != 2
    println(stderr, "usage: validate_null_metamorphic.jl <sounio-run.log> <fixture-directory>")
    exit(2)
end

const LOG_PATH = ARGS[1]
const FIXTURE_DIRECTORY = ARGS[2]
include(joinpath(@__DIR__, "window_pipeline_core.jl"))

const CASE_SPECS = [
    (name="nullmeta_mono", params="nullmeta_mono", rc=0),
    (name="nullmeta_dinuc", params="nullmeta_dinuc", rc=0),
]

const DINUCLEOTIDE_SEED_FILES = Dict(
    "nullmeta_dinuc" => "dinucleotide_seeds_nullmeta_k8.tsv",
)

# Records whose every window must produce degenerate null summaries, per
# engine. Homopolymers are identity under any composition-preserving null;
# the strictly alternating window has a unique fixed-endpoint Eulerian
# circuit and is identity only under the dinucleotide engine.
const DEGENERATE_RECORDS = Dict(
    "nullmeta_mono" => Set(["synthetic_homopolymer_a", "synthetic_homopolymer_c"]),
    "nullmeta_dinuc" => Set(["synthetic_homopolymer_a", "synthetic_homopolymer_c", "synthetic_alternating_ac"]),
)

# Records that must exhibit non-degenerate (randomized) null summaries.
const RANDOMIZED_RECORDS = Dict(
    "nullmeta_mono" => Set(["synthetic_alternating_ac", "synthetic_general_control"]),
    "nullmeta_dinuc" => Set(["synthetic_general_control"]),
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

    for line in eachline(path)
        if startswith(line, "DOSA_PIPELINE_CASE ")
            fields = parse_fields(line)
            name = fields["name"]
            haskey(cases, name) && error("duplicate null-metamorphic case: $name")
            cases[name] = Dict{String, Any}(
                "expected_rc" => parse(Int, fields["expected_rc"]),
                "actual_rc" => parse(Int, fields["actual_rc"]),
            )
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
            elseif (m = match(r"^sounio_pipeline_jsonl_lines_(.+)$", key)) !== nothing
                artifact_lines[m.captures[1]] = parse(Int, value)
            elseif (m = match(r"^sounio_pipeline_jsonl_sha256_(.+)$", key)) !== nothing
                artifact_shas[m.captures[1]] = value
            end
        end
    end
    return cases, params, artifacts, artifact_lines, artifact_shas
end

json_number(line::String, key::String) =
    match(Regex("\\\"$(key)\\\":(-?[0-9]+(?:\\.[0-9]+)?)"), line)

function json_field(line::String, key::String)::Union{Float64, Nothing}
    matched = json_number(line, key)
    isnothing(matched) && return nothing
    return parse(Float64, matched.captures[1])
end

function json_string(line::String, key::String)::String
    matched = match(Regex("\\\"$(key)\\\":\\\"([^\\\"]*)\\\""), line)
    isnothing(matched) && error("missing string field $key in persisted line")
    return matched.captures[1]
end

function json_int(line::String, key::String)::Int
    matched = match(Regex("\\\"$(key)\\\":([0-9]+)"), line)
    isnothing(matched) && error("missing integer field $key in persisted line")
    return parse(Int, matched.captures[1])
end

observed, announced_params, artifacts, artifact_lines, artifact_shas =
    parse_runner_log(LOG_PATH)
Set(keys(observed)) == Set(spec.name for spec in CASE_SPECS) || error(
    "unexpected null-metamorphic case set: $(sort!(collect(keys(observed))))",
)
Set(keys(announced_params)) == Set(spec.params for spec in CASE_SPECS) || error(
    "runner did not announce exactly the expected parameter set: " *
    "$(sort!(collect(keys(announced_params))))",
)

case_params = Dict{String, Any}()
for (name, fields) in announced_params
    flat_path = fields["flat"]
    isfile(flat_path) || error("announced flat parameter file is missing: $flat_path")
    result = load_parameters(String(read(flat_path)))
    result isa PipelineParams || error(
        "Julia independently rejected the flat parameters for $name",
    )
    result.sha256 == fields["sha256"] || error(
        "parameter sha256 divergence for $name: flat binds $(result.sha256) " *
        "but runner announced $(fields["sha256"])",
    )
    case_params[name] = result
end

metadata_text = String(read(joinpath(FIXTURE_DIRECTORY, "nullmeta_metadata.tsv")))
fasta_bytes = read(joinpath(FIXTURE_DIRECTORY, "nullmeta_fixture.fa"))
rows_or_error = load_metadata(metadata_text)
rows_or_error isa Vector{MetadataRow} || error(
    "Julia independently derived a metadata error for the null-metamorphic fixture",
)

validated_windows = Ref(0)
degenerate_windows = Ref(0)
randomized_windows = Ref(0)
coherent_blocks = Ref(0)

for spec in CASE_SPECS
    case = observed[spec.name]
    case["expected_rc"] == spec.rc || error("runner expectation drift for $(spec.name)")
    case["actual_rc"] == spec.rc || error("Sounio exit mismatch for $(spec.name)")

    params = case_params[spec.params]
    seed_file = get(DINUCLEOTIDE_SEED_FILES, spec.name, nothing)
    dinucleotide_seeds = if params.null_model == "dinucleotide_shuffle"
        isnothing(seed_file) && error("missing seed-sidecar declaration for $(spec.name)")
        load_dinucleotide_seeds(joinpath(FIXTURE_DIRECTORY, seed_file), params.sha256)
    else
        Dict{Tuple{String,Int},String}()
    end

    expected_lines, error_or_nothing =
        simulate_pipeline(fasta_bytes, rows_or_error, params, dinucleotide_seeds)
    isnothing(error_or_nothing) || error(
        "Julia independently derived an error for $(spec.name): $(error_or_nothing)",
    )

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

    metrics = vcat(
        ["delta_R", "delta_RC"],
        ["reverse_kmer_imbalance_$k" for k in 1:params.k_max],
        ["rc_kmer_imbalance_$k" for k in 1:params.k_max],
    )

    degenerate_records = DEGENERATE_RECORDS[spec.name]
    randomized_records = RANDOMIZED_RECORDS[spec.name]

    for line in expected_lines
        accession = json_string(line, "sequence_accession_version")
        window_start = json_int(line, "window_start")
        coordinate = "$accession:$window_start"

        degenerate_metrics = 0
        randomized_metrics = 0

        for metric in metrics
            mean = json_field(line, "$(metric)_null_mean")
            isnothing(mean) && continue  # metric unavailable for this window

            mad = json_field(line, "$(metric)_null_mad")
            q025 = json_field(line, "$(metric)_null_q025")
            q975 = json_field(line, "$(metric)_null_q975")
            available = json_field(line, "$(metric)_null_replicates_available")
            observed_value = json_field(line, metric)
            (isnothing(mad) || isnothing(q025) || isnothing(q975) || isnothing(available)) &&
                error("partial null block for $metric at $coordinate")
            isnothing(observed_value) &&
                error("null summary emitted for unavailable metric $metric at $coordinate")

            # MR4: summary coherence on every emitted block.
            available == Float64(params.null_replicates) || error(
                "MR4 violated for $metric at $coordinate: available=$available " *
                "but null_replicates=$(params.null_replicates)",
            )
            q025 <= q975 || error(
                "MR4 violated for $metric at $coordinate: q025=$q025 > q975=$q975",
            )
            mad >= 0.0 || error(
                "MR4 violated for $metric at $coordinate: negative mad=$mad",
            )
            coherent_blocks[] += 1

            if accession in degenerate_records
                # MR1/MR2: identity draws imply fully degenerate summaries.
                mad == 0.0 || error(
                    "MR1/MR2 violated for $metric at $coordinate: mad=$mad on an identity-null window",
                )
                q025 == mean && q975 == mean || error(
                    "MR1/MR2 violated for $metric at $coordinate: " *
                    "q025=$q025 mean=$mean q975=$q975 not degenerate",
                )
                abs(mean - observed_value) <= 5e-7 || error(
                    "MR1/MR2 violated for $metric at $coordinate: " *
                    "null mean=$mean diverges from observed=$observed_value",
                )
                degenerate_metrics += 1
            elseif accession in randomized_records && mad > 0.0
                randomized_metrics += 1
            end
        end

        if accession in degenerate_records
            degenerate_metrics > 0 || error(
                "no metric carried a null block on degenerate window $coordinate",
            )
            degenerate_windows[] += 1
        elseif accession in randomized_records
            # MR3: the engines must actually randomize non-degenerate windows.
            randomized_metrics > 0 || error(
                "MR3 violated at $coordinate: every null summary is degenerate " *
                "on a window that must randomize",
            )
            randomized_windows[] += 1
        end
    end
end

println("DOSA_JULIA_NULL_METAMORPHIC_OK")
println(
    "validated_cases=$(length(CASE_SPECS)) validated_windows=$(validated_windows[]) " *
    "degenerate_windows=$(degenerate_windows[]) randomized_windows=$(randomized_windows[]) " *
    "coherent_null_blocks=$(coherent_blocks[]) tolerance=0",
)
