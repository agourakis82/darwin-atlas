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
work1 = parse_work_unit(parameters, manifest, fixture_root, "NC_000001.1@16")
work2 = parse_work_unit(parameters, manifest, fixture_root, "NC_000002.1@16")
work3 = parse_work_unit(parameters, manifest, fixture_root, "NC_000003.1@16")
work5 = parse_work_unit(parameters, manifest, fixture_root, "NC_000005.1@100")
work6 = parse_work_unit(parameters, manifest, fixture_root, "NC_000006.1@500")
work7 = parse_work_unit(parameters, manifest, fixture_root, "NC_000007.1@1000")

function expected_work_line(work, window_index)
    window_start = window_index * work.scale
    bases = work.bases[window_start + 1:window_start + work.scale]
    if !occursin(r"^[ACGT]+$", bases)
        return expected_excluded_profile_line(work, window_index)
    end
    seed64 = bytes2hex(sha256("$(work.parameter_sha):$(work.accession):$window_start"))[1:16]
    case_id = replace(work.accession, "." => "_") * "_$(work.scale)_$window_index"
    case = (; case_id, parameter_sha=work.parameter_sha, accession=work.accession,
            window_start, scale=work.scale, seed64, bases)
    expected_profile_line(case; run_id="u0-work-unit-fixture")
end

mktempdir() do temporary
    artifact = joinpath(temporary, "work-unit.jsonl")
    expected = [expected_work_line(work1, index) for index in 0:(work1.total_windows - 1)]
    write(artifact, join(expected, "\n") * "\n")
    passed, output = run_work_validator(parameters, manifest, fixture_root, artifact, "0", "3", work1.work_id)
    require_work(passed && occursin("U0_WORK_UNIT_JULIA_DIFFERENTIAL_PASS", output),
                 "valid work-unit artifact failed: $output")
    selected_without_id, missing_id_output = run_work_validator(
        parameters, manifest, fixture_root, artifact, "0", "3")
    require_work(!selected_without_id && occursin("multi-unit manifest requires", missing_id_output),
                 "Julia accepted a multi-unit manifest without explicit selection")

    resumed = joinpath(temporary, "resumed.jsonl")
    write(resumed, join(expected[2:end], "\n") * "\n")
    resume_passed, resume_output = run_work_validator(parameters, manifest, fixture_root, resumed, "1", "2", work1.work_id)
    require_work(resume_passed && occursin("start_window=1", resume_output),
                 "valid resumed work-unit artifact failed: $resume_output")

    artifact2 = joinpath(temporary, "work-unit-2.jsonl")
    expected2 = [expected_work_line(work2, index) for index in 0:(work2.total_windows - 1)]
    write(artifact2, join(expected2, "\n") * "\n")
    passed2, output2 = run_work_validator(parameters, manifest, fixture_root, artifact2, "0", "3", work2.work_id)
    require_work(passed2 && occursin("work_unit_id=$(work2.work_id)", output2),
                 "second valid work-unit artifact failed: $output2")

    artifact3 = joinpath(temporary, "work-unit-3.jsonl")
    expected3 = [expected_work_line(work3, index) for index in 0:(work3.total_windows - 1)]
    write(artifact3, join(expected3, "\n") * "\n")
    count(line -> occursin("\"status\":\"excluded\"", line), expected3) == 1 ||
        error("ambiguous fixture must contain exactly one excluded row")
    passed3, output3 = run_work_validator(parameters, manifest, fixture_root, artifact3, "0", "3", work3.work_id)
    require_work(passed3 && occursin("work_unit_id=$(work3.work_id)", output3),
                 "ambiguous work-unit artifact failed: $output3")

    for (ordinal, work) in zip(5:7, (work5, work6, work7))
        work.total_windows == 1 || error("multiscale work unit must contain exactly one complete window")
        artifact_scale = joinpath(temporary, "work-unit-$ordinal.jsonl")
        write(artifact_scale, expected_work_line(work, 0) * "\n")
        passed_scale, output_scale = run_work_validator(
            parameters, manifest, fixture_root, artifact_scale, "0", "1", work.work_id)
        require_work(passed_scale && occursin("work_unit_id=$(work.work_id)", output_scale),
                     "multiscale work-unit artifact failed: $output_scale")
    end

    partial_refused = false
    try
        parse_work_unit(parameters, manifest, fixture_root, "NC_000004.1@16")
    catch error
        partial_refused = occursin("no complete window artifact", sprint(showerror, error))
    end
    require_work(partial_refused, "Julia did not classify the zero-window work unit")

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
    accepted, rejected_output = run_work_validator(parameters, manifest, fixture_root, perturbed, "0", "3", work1.work_id)
    require_work(!accepted && occursin("byte mismatch", rejected_output),
                 "Julia accepted or misclassified a one-digit perturbation")
end

println("U0_WORK_UNIT_JULIA_TEST_PASS work_units=7 rows=12 scales=4 excluded_rows=1 partial_work_units=1 resume_rows=2 metrics=17 selector_refused=true perturbation_refused=true")
