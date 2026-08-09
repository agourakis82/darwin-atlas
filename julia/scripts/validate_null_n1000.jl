#!/usr/bin/env julia

"""
Independent Base-only validator for the Fase P3 null_replicates n=1000 run.

Re-reads the rendered flat parameter bytes for the null_k4 case with
null_replicates=1000, independently re-validates the parameter grammar,
re-derives the metadata association, windows, metrics and the fixture
mononucleotide null-model summaries at n=1000, then rebuilds the expected
JSONL byte for byte and requires exact equality with the persisted Sounio
artifact produced by the re-ceilinged fasta_fixture_p3 binary.

Loads no packages (Base only), does not execute Sounio, and never falls
back to producing the artifact itself. Companion to the frozen
validate_mini_pipeline.jl battery validator; does not modify it.

usage: validate_null_n1000.jl <flat-params> <fixture-directory> <sounio-jsonl>
"""

if length(ARGS) != 3
    println(stderr, "usage: validate_null_n1000.jl <flat-params> <fixture-directory> <sounio-jsonl>")
    exit(2)
end

const FLAT_PATH = ARGS[1]
const FIXTURE_DIRECTORY = ARGS[2]
const JSONL_PATH = ARGS[3]

include(joinpath(@__DIR__, "window_pipeline_core.jl"))

isfile(FLAT_PATH) || error("flat parameter file is missing: $FLAT_PATH")
isfile(JSONL_PATH) || error("Sounio JSONL artifact is missing: $JSONL_PATH")

params_or_error = load_parameters(String(read(FLAT_PATH)))
params_or_error isa PipelineParams || error(
    "Julia independently rejected the n=1000 flat parameters: $(params_or_error)",
)
const params = params_or_error
params.null_replicates == 1000 || error(
    "expected null_replicates=1000, parsed $(params.null_replicates)",
)
params.null_model == "mononucleotide_shuffle" || error(
    "expected null_model=mononucleotide_shuffle, parsed $(params.null_model)",
)

metadata_text = String(read(joinpath(FIXTURE_DIRECTORY, "pipeline_metadata.tsv")))
fasta_bytes = read(joinpath(FIXTURE_DIRECTORY, "pipeline_fixture.fa"))

rows_or_error = load_metadata(metadata_text)
rows_or_error isa PipelineError && error(
    "Julia independently derived a metadata error: $(rows_or_error)",
)

n1000_lines, n1000_error =
    simulate_pipeline(fasta_bytes, rows_or_error, params, Dict{Tuple{String,Int},String}())
isnothing(n1000_error) || error(
    "Julia independently derived an error for the n=1000 case: $(n1000_error)",
)

expected_bytes = join(n1000_lines, "\n") * "\n"
actual_bytes = String(read(JSONL_PATH))
actual_bytes == expected_bytes || error(
    "JSONL mismatch: persisted Sounio n=1000 artifact differs from the " *
    "independent Julia recomputation (byte-exact comparison)",
)

println("DOSA_JULIA_NULL_N1000_DIFFERENTIAL_OK")
println("validated_windows=$(length(n1000_lines)) null_replicates=$(params.null_replicates) tolerance=0")
