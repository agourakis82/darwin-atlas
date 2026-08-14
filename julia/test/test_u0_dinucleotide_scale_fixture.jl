#!/usr/bin/env julia

# Base-only regression driver for the independent U0 scale-fixture oracle.
# It synthesizes a temporary canonical artifact from the oracle's independently
# recomputed draws, then demonstrates that a one-base artifact perturbation is
# refused.  The Sounio differential runner supplies the real producer artifact.

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const VALIDATOR = joinpath(ROOT, "julia", "scripts", "validate_u0_dinucleotide_scale_fixture.jl")
const FIXTURE = joinpath(ROOT, "data", "fixtures", "u0_dinucleotide_scale")
const GENERATOR = joinpath(ROOT, "scripts", "generate_u0_dinucleotide_scale_cases.rb")

# Include before entering the `do`-block so Julia 1.12 world-age rules cannot
# treat the newly loaded oracle methods as younger than the test closure.
include(VALIDATOR)

function require(condition::Bool, message::String)
    condition || error(message)
end

function run_validator(parameters::String, cases::String, artifact::String)
    command = `$(Base.julia_cmd()) --startup-file=no $VALIDATOR $parameters $cases $artifact`
    captured = IOBuffer()
    process = run(pipeline(command; stdout=captured, stderr=captured); wait=false)
    wait(process)
    success(process), String(take!(captured))
end

mktempdir() do temporary
    parameters = joinpath(ROOT, "data", "v3", "u0_parameters.json")
    cases = joinpath(temporary, "cases.tsv")
    artifact = joinpath(temporary, "sounio.jsonl")
    run(`ruby $GENERATOR $parameters $cases`)

    unicode_cases = joinpath(temporary, "unicode-digit.tsv")
    write(unicode_cases, replace(read(cases, String), "\t1000\n" => "\t１０00\n"; count=1))
    unicode_refused = false
    try
        parse_cases(parameters, unicode_cases)
    catch error_value
        unicode_refused = true
        require(occursin("ASCII unsigned decimal", sprint(showerror, error_value)),
                "Unicode-digit case failed for an unexpected reason: $(sprint(showerror, error_value))")
    end
    require(unicode_refused, "validator accepted a Unicode decimal digit")

    missing_case_lf = joinpath(temporary, "cases-missing-terminal-lf.tsv")
    write(missing_case_lf, read(cases)[1:end-1])
    missing_case_lf_refused = false
    try
        parse_cases(parameters, missing_case_lf)
    catch error_value
        missing_case_lf_refused = true
        require(occursin("case TSV must end in LF", sprint(showerror, error_value)),
                "missing case LF failed for an unexpected reason: $(sprint(showerror, error_value))")
    end
    require(missing_case_lf_refused, "validator accepted a case TSV without terminal LF")

    crlf_cases = joinpath(temporary, "cases-crlf.tsv")
    write(crlf_cases, replace(read(cases, String), "\n" => "\r\n"))
    crlf_refused = false
    try
        parse_cases(parameters, crlf_cases)
    catch error_value
        crlf_refused = true
        require(occursin("case TSV must use LF", sprint(showerror, error_value)),
                "CRLF cases failed for an unexpected reason: $(sprint(showerror, error_value))")
    end
    require(crlf_refused, "validator accepted CRLF case TSV")

    parsed = parse_cases(parameters, cases)
    open(artifact, "w") do io
        for case in parsed, replicate in 1:REPLICATES
            println(io, expected_line(case, replicate, shuffled_sequence(case.bases, case.seed64, replicate)))
        end
    end

    passed, output = run_validator(parameters, cases, artifact)
    require(passed, "valid scale fixture failed: $output")
    require(occursin("U0_DINUCLEOTIDE_SCALE_JULIA_DIFFERENTIAL_PASS cases=4", output),
            "valid scale fixture did not pass")

    bytes = read(artifact)
    marker = Vector{UInt8}(codeunits("\"sequence\":\""))
    offset = findfirst(==(marker[1]), bytes)
    while !isnothing(offset) && bytes[offset:offset + length(marker) - 1] != marker
        offset = findnext(==(marker[1]), bytes, offset + 1)
    end
    !isnothing(offset) || error("sequence marker missing from generated artifact")
    base_at = offset + length(marker)
    bytes[base_at] = bytes[base_at] == UInt8('A') ? UInt8('C') : UInt8('A')
    perturbed = joinpath(temporary, "perturbed.jsonl")
    write(perturbed, bytes)
    refused, refusal_output = run_validator(parameters, cases, perturbed)
    require(!refused, "validator accepted a one-base JSONL perturbation")
    require(occursin("JSONL byte mismatch", refusal_output),
            "perturbation failed for an unexpected reason: $refusal_output")

    missing_lf = joinpath(temporary, "missing-terminal-lf.jsonl")
    write(missing_lf, read(artifact)[1:end-1])
    lf_passed, lf_output = run_validator(parameters, cases, missing_lf)
    require(!lf_passed, "validator accepted JSONL without a terminal LF")
    require(occursin("must end in LF", lf_output),
            "missing-LF artifact failed for an unexpected reason: $lf_output")
end

println("U0_DINUCLEOTIDE_SCALE_JULIA_TEST_PASS cases=4 replicates=1000 perturbation_refused=true artifact_terminal_lf_refused=true case_lf_refusals=2 unicode_decimal_refused=true")
