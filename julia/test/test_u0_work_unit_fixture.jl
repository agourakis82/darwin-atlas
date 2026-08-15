#!/usr/bin/env julia

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const VALIDATOR = joinpath(ROOT, "julia", "scripts", "validate_u0_work_unit_fixture.jl")
include(VALIDATOR)

require_work(condition::Bool, message::String) = condition || error(message)

function run_work_validator(parameters, manifest, source_root, artifact, extra...)
    command = `$(Base.julia_cmd()) --startup-file=no $VALIDATOR $parameters $manifest $source_root $artifact $extra`
    captured = IOBuffer()
    process = run(pipeline(command; stdout=captured, stderr=captured); wait=false)
    wait(process)
    success(process), String(take!(captured))
end

parameters = joinpath(ROOT, "data", "v3", "u0_parameters.json")
fixture_root = joinpath(ROOT, "data", "fixtures", "u0_work_unit")
manifest = joinpath(fixture_root, "u0_work_units.tsv")
work = parse_work_unit(parameters, manifest, fixture_root)

function expected_work_line(work, window_index)
    window_start = window_index * work.scale
    bases = work.bases[window_start + 1:window_start + work.scale]
    seed64 = bytes2hex(sha256("$(work.parameter_sha):$(work.accession):$window_start"))[1:16]
    case_id = replace(work.accession, "." => "_") * "_$(work.scale)_$window_index"
    case = (; case_id, parameter_sha=work.parameter_sha, accession=work.accession,
            window_start, scale=work.scale, seed64, bases)
    expected_profile_line(case; run_id="u0-work-unit-fixture")
end

mktempdir() do temporary
    artifact = joinpath(temporary, "work-unit.jsonl")
    expected = [expected_work_line(work, index) for index in 0:(work.total_windows - 1)]
    write(artifact, join(expected, "\n") * "\n")
    passed, output = run_work_validator(parameters, manifest, fixture_root, artifact, "0", "3")
    require_work(passed && occursin("U0_WORK_UNIT_JULIA_DIFFERENTIAL_PASS", output),
                 "valid work-unit artifact failed: $output")

    resumed = joinpath(temporary, "resumed.jsonl")
    write(resumed, join(expected[2:end], "\n") * "\n")
    resume_passed, resume_output = run_work_validator(parameters, manifest, fixture_root, resumed, "1", "2")
    require_work(resume_passed && occursin("start_window=1", resume_output),
                 "valid resumed work-unit artifact failed: $resume_output")

    bytes = read(artifact)
    marker = Vector{UInt8}(codeunits("\"numerator\":"))
    offset = findfirst(==(marker[1]), bytes)
    while !isnothing(offset) && bytes[offset:offset + length(marker) - 1] != marker
        offset = findnext(==(marker[1]), bytes, offset + 1)
    end
    !isnothing(offset) || error("numerator marker missing")
    digit = offset + length(marker)
    bytes[digit] = bytes[digit] == UInt8('9') ? UInt8('8') : bytes[digit] + 1
    perturbed = joinpath(temporary, "perturbed.jsonl")
    write(perturbed, bytes)
    accepted, rejected_output = run_work_validator(parameters, manifest, fixture_root, perturbed)
    require_work(!accepted && occursin("byte mismatch", rejected_output),
                 "Julia accepted or misclassified a one-digit perturbation")
end

println("U0_WORK_UNIT_JULIA_TEST_PASS work_units=1 rows=3 resume_rows=2 metrics=17 perturbation_refused=true")
