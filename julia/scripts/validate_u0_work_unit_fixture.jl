#!/usr/bin/env julia

"""
Independent validator for the manifest/FASTA-to-Sounio work-unit fixture.

Julia reparses the immutable parameter, manifest and FASTA bytes, recomputes
the SHA-derived seed, every Euler/Wilson draw, all 17 analytical blocks and
the complete persisted Sounio JSONL line. It never reads the host-derived case
ledger and therefore tests that composition boundary independently.
"""

include(joinpath(@__DIR__, "validate_u0_window_profile_fixture.jl"))

const WORK_HEADER = join((
    "u0_manifest_version", "work_unit_id", "assembly_accession_version",
    "sequence_accession_version", "replicon_class", "source_locator",
    "source_file_sha256", "sequence_sha256", "sequence_length",
    "declared_alphabet", "parameters_sha256", "scale", "stride", "k_min",
    "k_max", "null_model", "null_replicates",
), '\t')

work_fail(message) = error("U0_WORK_UNIT_VALIDATION_FAIL: " * message)

function reject_work_symlink_components(path::String, label::String)
    absolute = abspath(path)
    parts = splitpath(absolute)
    current = parts[1]
    for part in parts[2:end]
        current = joinpath(current, part)
        islink(current) && work_fail("$label path may not contain symlinks")
    end
end

function parse_work_unit(parameters_path::String, manifest_path::String, source_root::String,
                         requested_work_unit_id::String="")
    for (path, label) in ((parameters_path, "parameters"), (manifest_path, "manifest"))
        reject_work_symlink_components(path, label)
        isfile(path) && !islink(path) || work_fail("$label must be a regular non-symlink file")
    end
    parameter_sha = bytes2hex(sha256(read(parameters_path)))
    parameter_sha == "68343e046af24a997195eb2583532d3172234b0b9713f2e4296b9b12300bef94" ||
        work_fail("canonical parameter bytes drifted")
    manifest_bytes = read(manifest_path)
    !isempty(manifest_bytes) && manifest_bytes[end] == 0x0a && !(0x0d in manifest_bytes) ||
        work_fail("manifest must be LF-only with terminal LF")
    lines = split(String(manifest_bytes[1:end-1]), '\n'; keepempty=true)
    length(lines) >= 2 && lines[1] == WORK_HEADER || work_fail("manifest header or row count drift")
    isempty(requested_work_unit_id) && length(lines) != 2 &&
        work_fail("multi-unit manifest requires an explicit work_unit_id")
    seen_ids = Set{String}()
    seen_coordinates = Set{Tuple{String,Int}}()
    ordering = Tuple{String,Int}[]
    selected = nothing
    for (row_index, line) in enumerate(lines[2:end])
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 17 || work_fail("manifest row $row_index field count drift")
        (manifest_version, work_id, assembly, accession, replicon_class, locator, raw_sha, sequence_sha,
         length_raw, alphabet, declared_parameter_sha, scale_raw, stride_raw,
         k_min_raw, k_max_raw, null_model, replicates_raw) = fields
        occursin(r"^[A-Z]{1,8}_[0-9]+\.[0-9]+$", accession) || work_fail("sequence accession drift")
        occursin(r"^GC[AF]_[0-9]+\.[0-9]+$", assembly) || work_fail("assembly accession drift")
        scale = parse_positive_decimal(scale_raw, "work-unit scale")
        length_bp = parse_positive_decimal(length_raw, "work-unit length")
        stride = parse_positive_decimal(stride_raw, "work-unit stride")
        manifest_version == "1.0.0" && work_id == "$accession@$scale" || work_fail("work-unit identity drift")
        replicon_class in ("chromosome", "plasmid") && alphabet in ("acgt", "non_acgt") ||
            work_fail("work-unit metadata drift")
        declared_parameter_sha == parameter_sha || work_fail("manifest parameter SHA mismatch")
        scale in SCALES && stride == scale || work_fail("scale/stride drift")
        (k_min_raw, k_max_raw, replicates_raw) == ("1", "8", "1000") || work_fail("numeric contract drift")
        null_model == "euler_wilson_fixed_endpoints_v1" || work_fail("null model drift")
        occursin(r"^[0-9a-f]{64}$", raw_sha) && occursin(r"^[0-9a-f]{64}$", sequence_sha) ||
            work_fail("manifest SHA-256 field drift")
        coordinate = (accession, scale)
        if work_id in seen_ids || coordinate in seen_coordinates
            work_fail("duplicate work-unit identity")
        end
        push!(seen_ids, work_id)
        push!(seen_coordinates, coordinate)
        push!(ordering, coordinate)
        relative = split(locator, '/'; keepempty=true)
        !isempty(relative) && all(part -> !isempty(part) && part != "." && part != "..", relative) ||
            work_fail("unsafe source locator")
        if work_id == requested_work_unit_id || (isempty(requested_work_unit_id) && length(lines) == 2)
            selected = (; work_id, accession, locator, raw_sha, sequence_sha, length_bp, alphabet,
                         scale, relative)
        end
    end
    scale_rank(scale) = something(findfirst(==(scale), SCALES), 0)
    issorted(ordering; by=item -> (item[1], scale_rank(item[2]))) ||
        work_fail("manifest work units are not in canonical accession/scale order")
    isnothing(selected) && work_fail("requested work_unit_id is absent")
    work_id = selected.work_id
    accession = selected.accession
    locator = selected.locator
    raw_sha = selected.raw_sha
    sequence_sha = selected.sequence_sha
    length_bp = selected.length_bp
    alphabet = selected.alphabet
    scale = selected.scale
    relative = selected.relative
    length_bp >= scale || work_fail("selected work unit has no complete window artifact")
    reject_work_symlink_components(source_root, "source root")
    root = realpath(source_root)
    isdir(root) && !islink(source_root) || work_fail("source root is invalid")
    fasta_path = joinpath(root, relative...)
    isfile(fasta_path) && !islink(fasta_path) || work_fail("source FASTA is invalid")
    startswith(realpath(fasta_path), root * Base.Filesystem.path_separator) || work_fail("source escapes root")
    fasta_bytes = read(fasta_path)
    bytes2hex(sha256(fasta_bytes)) == raw_sha || work_fail("raw FASTA SHA mismatch")
    !isempty(fasta_bytes) && fasta_bytes[end] == 0x0a && !(0x0d in fasta_bytes) ||
        work_fail("FASTA must be LF-only with terminal LF")
    fasta_lines = split(String(fasta_bytes[1:end-1]), '\n'; keepempty=true)
    length(fasta_lines) >= 2 && fasta_lines[1] == ">$accession" || work_fail("FASTA accession mismatch")
    all(line -> !startswith(line, ">"), fasta_lines[2:end]) || work_fail("FASTA contains multiple records")
    bases = uppercase(join(fasta_lines[2:end]))
    occursin(r"^[ACGTRYSWKMBDHVN]+$", bases) && ncodeunits(bases) == length_bp || work_fail("FASTA sequence contract drift")
    bytes2hex(sha256(bases)) == sequence_sha || work_fail("normalized sequence SHA mismatch")
    actual_alphabet = occursin(r"^[ACGT]+$", bases) ? "acgt" : "non_acgt"
    actual_alphabet == alphabet || work_fail("declared alphabet does not match normalized FASTA")
    (; work_id, parameter_sha, accession, scale, bases, total_windows=div(length_bp, scale))
end

function expected_excluded_profile_line(work, window_index::Int)
    reason = "NULL_INPUT_NOT_ACGT"
    null_summary = "{\"n\":0,\"mean\":null,\"mad\":null,\"q025\":null,\"q500\":null,\"q975\":null,\"tail_lt\":null,\"tail_eq\":null,\"tail_gt\":null,\"reason_code\":\"$reason\"}"
    observation = "{\"effective_count\":0,\"observed\":null,\"null_summary\":$null_summary,\"reason_code\":\"$reason\"}"
    kmer_r = join(["{\"k\":$k,\"effective_count\":0,\"observed\":null,\"null_summary\":$null_summary,\"reason_code\":\"$reason\"}" for k in 2:8], ",")
    kmer_rc = join(["{\"k\":$k,\"effective_count\":0,\"observed\":null,\"null_summary\":$null_summary,\"reason_code\":\"$reason\"}" for k in 1:8], ",")
    window_start = window_index * work.scale
    "{\"run_id\":\"u0-work-unit-fixture\",\"replicon_id\":\"$(work.accession)\",\"window_size\":$(work.scale),\"window_index\":$window_index,\"window_start\":$window_start,\"window_end\":$(window_start + work.scale),\"status\":\"excluded\",\"reason_code\":\"$reason\",\"positional_r\":$observation,\"positional_rc\":$observation,\"kmer_r\":[$kmer_r],\"kmer_rc\":[$kmer_rc]}"
end

function validate_work_unit(parameters_path::String, manifest_path::String,
                            source_root::String, artifact_path::String,
                            start_window::Int=0, expected_rows::Int=-1,
                            work_unit_id::String="")
    work = parse_work_unit(parameters_path, manifest_path, source_root, work_unit_id)
    0 <= start_window < work.total_windows || work_fail("start window outside work unit")
    isfile(artifact_path) && !islink(artifact_path) || work_fail("Sounio artifact is missing")
    bytes = read(artifact_path)
    !isempty(bytes) && bytes[end] == 0x0a && !(0x0d in bytes) || work_fail("artifact must be LF-only with terminal LF")
    lines = split(String(bytes[1:end-1]), '\n'; keepempty=true)
    !isempty(lines) && length(lines) <= 32 || work_fail("artifact shard must contain 1:32 rows")
    expected_rows >= 0 && length(lines) != expected_rows && work_fail("artifact row count mismatch")
    start_window + length(lines) <= work.total_windows || work_fail("artifact exceeds work unit")
    for (offset, actual) in enumerate(lines)
        window_index = start_window + offset - 1
        window_start = window_index * work.scale
        window_end = window_start + work.scale
        bases = work.bases[window_start + 1:window_end]
        case_id = replace(work.accession, "." => "_") * "_$(work.scale)_$window_index"
        if occursin(r"^[ACGT]+$", bases)
            seed64 = bytes2hex(sha256("$(work.parameter_sha):$(work.accession):$window_start"))[1:16]
            case = (; case_id, parameter_sha=work.parameter_sha, accession=work.accession,
                    window_start, scale=work.scale, seed64, bases)
            expected = expected_profile_line(case; run_id="u0-work-unit-fixture")
        else
            expected = expected_excluded_profile_line(work, window_index)
        end
        actual == expected || work_fail("byte mismatch for $case_id")
    end
    println("U0_WORK_UNIT_JULIA_DIFFERENTIAL_PASS work_unit_id=$(work.work_id) rows=$(length(lines)) metrics=17 replicates=1000 start_window=$start_window tolerance=0")
end

function main_work(args)
    4 <= length(args) <= 7 || begin
        println(stderr, "usage: validate_u0_work_unit_fixture.jl <parameters.json> <manifest.tsv> <source-root> <profiles.jsonl> [start-window [expected-rows [work-unit-id]]]")
        exit(2)
    end
    start_window = length(args) >= 5 ? parse_nonnegative_decimal(args[5], "start window") : 0
    expected_rows = length(args) >= 6 ? parse_positive_decimal(args[6], "expected rows") : -1
    work_unit_id = length(args) == 7 ? args[7] : ""
    validate_work_unit(args[1], args[2], args[3], args[4], start_window, expected_rows, work_unit_id)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main_work(ARGS)
end
