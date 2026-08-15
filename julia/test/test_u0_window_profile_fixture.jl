#!/usr/bin/env julia

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const VALIDATOR = joinpath(ROOT, "julia", "scripts", "validate_u0_window_profile_fixture.jl")
const STRUCTURE_VALIDATOR = joinpath(ROOT, "scripts", "validate_u0_window_profile_fixture.py")
include(VALIDATOR)

require_profile(condition::Bool, message::String) = condition || error(message)

function run_profile_validator(parameters::String, cases::String, artifact::String)
    command = `$(Base.julia_cmd()) --startup-file=no $VALIDATOR $parameters $cases $artifact`
    captured = IOBuffer()
    process = run(pipeline(command; stdout=captured, stderr=captured); wait=false)
    wait(process)
    success(process), String(take!(captured))
end

mktempdir() do temporary
    parameters = joinpath(ROOT, "data", "v3", "u0_parameters.json")
    cases_path = joinpath(ROOT, "data", "fixtures", "u0_dinucleotide_scale", "cases.tsv")
    cases = parse_cases(parameters, cases_path)
    artifact = joinpath(temporary, "profiles.jsonl")
    open(artifact, "w") do io
        for case in cases
            println(io, expected_profile_line(case))
        end
    end

    structure_output = read(`python3 $STRUCTURE_VALIDATOR $artifact`, String)
    require_profile(occursin("U0_WINDOW_PROFILE_STRUCTURE_PASS", structure_output),
                    "profile structure marker missing")

    passed, output = run_profile_validator(parameters, cases_path, artifact)
    require_profile(passed, "valid profile artifact failed: $output")
    require_profile(occursin("U0_WINDOW_PROFILE_JULIA_DIFFERENTIAL_PASS", output),
                    "valid profile marker missing")

    bytes = read(artifact)
    marker = Vector{UInt8}(codeunits("\"numerator\":"))
    offset = findfirst(==(marker[1]), bytes)
    while !isnothing(offset) && bytes[offset:offset + length(marker) - 1] != marker
        offset = findnext(==(marker[1]), bytes, offset + 1)
    end
    !isnothing(offset) || error("profile numerator marker missing")
    digit = offset + length(marker)
    UInt8('0') <= bytes[digit] <= UInt8('9') || error("profile numerator is not decimal")
    bytes[digit] = bytes[digit] == UInt8('9') ? UInt8('8') : bytes[digit] + 1
    perturbed = joinpath(temporary, "perturbed.jsonl")
    write(perturbed, bytes)
    perturbation_passed, perturbation_output = run_profile_validator(parameters, cases_path, perturbed)
    require_profile(!perturbation_passed, "Julia accepted a one-digit profile perturbation")
    require_profile(occursin("byte mismatch", perturbation_output),
                    "profile perturbation failed for an unexpected reason: $perturbation_output")

    missing_lf = joinpath(temporary, "missing-lf.jsonl")
    write(missing_lf, read(artifact)[1:end-1])
    lf_passed, lf_output = run_profile_validator(parameters, cases_path, missing_lf)
    require_profile(!lf_passed, "Julia accepted profile JSONL without terminal LF")
    require_profile(occursin("must end in LF", lf_output),
                    "missing profile LF failed for an unexpected reason: $lf_output")
end

println("U0_WINDOW_PROFILE_JULIA_TEST_PASS rows=4 metrics=17 perturbation_refused=true terminal_lf_refused=true")
