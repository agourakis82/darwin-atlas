#!/usr/bin/env julia

"""
Independently validate the logical content reopened from U0 fixture Parquet.

Python/DuckDB is treated only as a transport boundary. Julia hashes every
package manifest and Parquet payload, requires byte-identical logical and
round-trip JSONL, then independently recomputes every scientific row from the
immutable work-unit manifest and FASTA bytes. No U0 pilot receipt is emitted.
"""

include(joinpath(@__DIR__, "validate_u0_work_shard_set.jl"))

const PARQUET_SET_HEADER = join((
    "run_id", "scale", "rows", "package_path", "package_manifest_sha256",
    "logical_path", "logical_sha256", "roundtrip_path", "roundtrip_sha256",
    "payload_count",
), '\t')
const PARQUET_PAYLOAD_HEADER = join((
    "run_id", "scale", "package_path", "payload_path", "payload_sha256",
    "payload_size_bytes", "rows", "compression",
), '\t')

parquet_fail(message) = error("U0_WORK_PARQUET_VALIDATION_FAIL: " * message)

function read_tsv_lines(path::String, expected_header::String, label::String)
    isfile(path) && !islink(path) || parquet_fail("$label must be a regular file")
    bytes = read(path)
    !isempty(bytes) && bytes[end] == 0x0a && !(0x0d in bytes) ||
        parquet_fail("$label must be LF-only with terminal LF")
    lines = split(String(bytes[1:end-1]), '\n'; keepempty=true)
    length(lines) >= 2 && lines[1] == expected_header || parquet_fail("$label header or row count drift")
    lines[2:end]
end

function hash_regular_below(root::String, raw::AbstractString, expected_sha::AbstractString,
                            label::String)::String
    path = regular_below(root, String(raw), label)
    occursin(r"^[0-9a-f]{64}$", expected_sha) || parquet_fail("$label SHA-256 syntax drift")
    bytes2hex(sha256(read(path))) == expected_sha || parquet_fail("$label SHA-256 mismatch")
    path
end

function manifest_unit_order(manifest_path::String)
    bytes = read(manifest_path)
    !isempty(bytes) && bytes[end] == 0x0a && !(0x0d in bytes) || parquet_fail("manifest grammar drift")
    lines = split(String(bytes[1:end-1]), '\n'; keepempty=true)
    length(lines) >= 2 && lines[1] == WORK_HEADER || parquet_fail("manifest header drift")
    result = NamedTuple[]
    for line in lines[2:end]
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 17 || parquet_fail("manifest field count drift")
        accession = fields[4]
        scale = parse_positive_decimal(fields[12], "manifest scale")
        work_id = fields[2]
        length_bp = parse_positive_decimal(fields[9], "manifest length")
        push!(result, (; accession, scale, work_id, expected_rows=div(length_bp, scale)))
    end
    result
end

function expected_scale_lines(parameters_path::String, manifest_path::String,
                              source_root::String, run_id::AbstractString, scale::Int)
    expected = String[]
    for unit in manifest_unit_order(manifest_path)
        unit.scale == scale && unit.expected_rows > 0 || continue
        work = parse_work_unit(parameters_path, manifest_path, source_root, String(unit.work_id))
        for window_index in 0:(work.total_windows - 1)
            window_start = window_index * scale
            window_end = window_start + scale
            bases = work.bases[window_start + 1:window_end]
            if occursin(r"^[ACGT]+$", bases)
                seed64 = bytes2hex(sha256("$(work.parameter_sha):$(work.accession):$window_start"))[1:16]
                case_id = replace(work.accession, "." => "_") * "_$(scale)_$window_index"
                case = (; case_id, parameter_sha=work.parameter_sha, accession=work.accession,
                        window_start, scale, seed64, bases)
                push!(expected, expected_profile_line(case; run_id=String(run_id)))
            else
                push!(expected, expected_excluded_profile_line(work, window_index; run_id=String(run_id)))
            end
        end
    end
    expected
end

function validate_u0_work_parquet_set(parameters_path::String, manifest_path::String,
                                      source_root::String, package_root::String)
    for (path, label) in ((parameters_path, "parameters"), (manifest_path, "manifest"))
        reject_work_symlink_components(path, label)
        isfile(path) && !islink(path) || parquet_fail("$label must be a regular file")
    end
    reject_work_symlink_components(package_root, "package root")
    isdir(package_root) && !islink(package_root) || parquet_fail("package root must be a real directory")
    root = realpath(package_root)
    set_ledger = regular_below(root, "parquet_set_ledger.tsv", "Parquet set ledger")
    payload_ledger = regular_below(root, "parquet_payload_ledger.tsv", "Parquet payload ledger")

    payload_counts = Dict{Tuple{String,Int,String},Int}()
    payload_rows = Dict{Tuple{String,Int,String},Int}()
    observed_payload_paths = Set{String}()
    for (offset, line) in enumerate(read_tsv_lines(payload_ledger, PARQUET_PAYLOAD_HEADER, "payload ledger"))
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 8 || parquet_fail("payload ledger field count drift at row $(offset + 1)")
        (run_id, scale_raw, package_relative, payload_relative, payload_sha,
         size_raw, rows_raw, compression) = fields
        occursin(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", run_id) || parquet_fail("payload run_id drift")
        scale = parse_positive_decimal(scale_raw, "payload scale")
        scale in SCALES || parquet_fail("payload scale is outside the U0 contract")
        size = parse_positive_decimal(size_raw, "payload size")
        rows = parse_positive_decimal(rows_raw, "payload rows")
        compression == "zstd" || parquet_fail("payload compression drift")
        package_parts = safe_relative(package_relative, "package path")
        package_path = joinpath(root, package_parts...)
        isdir(package_path) && !islink(package_path) || parquet_fail("package path is not a real directory")
        payload_parts = safe_relative(payload_relative, "payload path")
        payload_path = joinpath(package_path, payload_parts...)
        isfile(payload_path) && !islink(payload_path) || parquet_fail("Parquet payload is unavailable")
        startswith(realpath(payload_path), realpath(package_path) * Base.Filesystem.path_separator) ||
            parquet_fail("Parquet payload escapes its package")
        filesize(payload_path) == size || parquet_fail("Parquet payload size mismatch")
        bytes2hex(sha256(read(payload_path))) == payload_sha || parquet_fail("Parquet payload SHA-256 mismatch")
        relative_payload = relpath(payload_path, root)
        relative_payload in observed_payload_paths && parquet_fail("duplicate Parquet payload path")
        push!(observed_payload_paths, relative_payload)
        key = (run_id, scale, package_relative)
        payload_counts[key] = get(payload_counts, key, 0) + 1
        payload_rows[key] = get(payload_rows, key, 0) + rows
    end

    total_rows = 0
    run_id = ""
    scales = Int[]
    package_paths = Set{String}()
    for (offset, line) in enumerate(read_tsv_lines(set_ledger, PARQUET_SET_HEADER, "Parquet set ledger"))
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 10 || parquet_fail("set ledger field count drift at row $(offset + 1)")
        (row_run_id, scale_raw, rows_raw, package_relative, package_manifest_sha,
         logical_relative, logical_sha, roundtrip_relative, roundtrip_sha,
         payload_count_raw) = fields
        run_id = isempty(run_id) ? String(row_run_id) : run_id
        row_run_id == run_id || parquet_fail("set ledger mixes run IDs")
        occursin(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", run_id) || parquet_fail("set run_id drift")
        scale = parse_positive_decimal(scale_raw, "set scale")
        scale in SCALES && !(scale in scales) || parquet_fail("duplicate or invalid packaged scale")
        push!(scales, scale)
        rows = parse_positive_decimal(rows_raw, "set rows")
        payload_count = parse_positive_decimal(payload_count_raw, "set payload count")
        package_relative in package_paths && parquet_fail("duplicate package path")
        push!(package_paths, package_relative)
        package_parts = safe_relative(package_relative, "package path")
        package_path = joinpath(root, package_parts...)
        isdir(package_path) && !islink(package_path) || parquet_fail("package path is unavailable")
        package_manifest = joinpath(package_path, "dosa-payload-manifest.json")
        isfile(package_manifest) && !islink(package_manifest) || parquet_fail("package manifest is unavailable")
        bytes2hex(sha256(read(package_manifest))) == package_manifest_sha || parquet_fail("package manifest SHA-256 mismatch")
        logical_path = hash_regular_below(root, logical_relative, logical_sha, "logical JSONL")
        roundtrip_path = hash_regular_below(root, roundtrip_relative, roundtrip_sha, "round-trip JSONL")
        logical_bytes = read(logical_path)
        roundtrip_bytes = read(roundtrip_path)
        logical_bytes == roundtrip_bytes || parquet_fail("Parquet round-trip differs from canonical Sounio JSONL at scale $scale")
        !isempty(roundtrip_bytes) && roundtrip_bytes[end] == 0x0a && !(0x0d in roundtrip_bytes) ||
            parquet_fail("round-trip JSONL grammar drift")
        actual = split(String(roundtrip_bytes[1:end-1]), '\n'; keepempty=true)
        length(actual) == rows || parquet_fail("round-trip row count mismatch at scale $scale")
        expected = expected_scale_lines(parameters_path, manifest_path, source_root, run_id, scale)
        length(expected) == rows || parquet_fail("manifest-derived row count mismatch at scale $scale")
        for index in eachindex(expected)
            actual[index] == expected[index] || parquet_fail("independent Julia byte mismatch at scale $scale row $index")
        end
        key = (run_id, scale, package_relative)
        get(payload_counts, key, 0) == payload_count || parquet_fail("payload count does not reconcile at scale $scale")
        get(payload_rows, key, 0) == rows || parquet_fail("payload rows do not reconcile at scale $scale")
        total_rows += rows
    end
    issorted(scales) || parquet_fail("packaged scales are not in canonical order")
    expected_scales = sort(unique(unit.scale for unit in manifest_unit_order(manifest_path) if unit.expected_rows > 0))
    scales == expected_scales || parquet_fail("packaged scale set does not cover all nonempty work units")
    actual_parquet = Set{String}()
    for (directory, subdirectories, files) in walkdir(root; topdown=true, follow_symlinks=false)
        any(name -> islink(joinpath(directory, name)), vcat(subdirectories, files)) &&
            parquet_fail("package tree contains a symlink")
        for name in files
            endswith(name, ".parquet") && push!(actual_parquet, relpath(joinpath(directory, name), root))
        end
    end
    actual_parquet == observed_payload_paths || parquet_fail("package tree has missing or unmanifested Parquet payloads")
    println("U0_WORK_PARQUET_JULIA_PASS run_id=$run_id scales=$(length(scales)) rows=$total_rows payloads=$(length(observed_payload_paths)) tolerance=0 roundtrip_byte_exact=1 fixture_scope_nonpromotable=1")
end

function main_work_parquet(args)
    length(args) == 4 || begin
        println(stderr, "usage: validate_u0_work_parquet_set.jl <parameters.json> <manifest.tsv> <source-root> <package-root>")
        exit(2)
    end
    validate_u0_work_parquet_set(args...)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main_work_parquet(ARGS)
end
