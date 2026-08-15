#!/usr/bin/env julia

"""
Independently validate every logical Sounio artifact in a resumed work-shard set.

The validator reparses parameters, the complete work-unit manifest and source
FASTAs. It recomputes every draw and analytical row through the existing
Base-only oracle, proves exact window coverage, and verifies all case/artifact
hashes in the execution ledger. It does not validate Parquet and cannot emit a
U0 full-validation receipt.
"""

include(joinpath(@__DIR__, "validate_u0_work_unit_fixture.jl"))

const SET_LEDGER_HEADER = join((
    "run_id", "plan_sha256", "work_unit_id", "sequence_accession_version",
    "scale", "start_window", "rows", "status", "reason_code", "case_path",
    "case_sha256", "artifact_path", "artifact_sha256", "artifact_size_bytes",
), '\t')

set_fail(message) = error("U0_WORK_SHARD_SET_VALIDATION_FAIL: " * message)

function parse_nonnegative_or_zero(raw::AbstractString, label::String)::Int
    occursin(r"^(0|[1-9][0-9]*)$", raw) || set_fail("$label is not canonical decimal")
    try
        parse(Int, raw)
    catch
        set_fail("$label exceeds Int")
    end
end

function safe_relative(raw::AbstractString, label::String)
    parts = split(raw, '/'; keepempty=true)
    !isempty(parts) && !startswith(raw, "/") && all(part -> !isempty(part) && part != "." && part != "..", parts) ||
        set_fail("$label is not a safe relative POSIX path")
    parts
end

function regular_below(root::String, raw::AbstractString, label::String)::String
    parts = safe_relative(raw, label)
    current = root
    for part in parts
        current = joinpath(current, part)
        islink(current) && set_fail("$label path may not contain symlinks")
    end
    isfile(current) && !islink(current) || set_fail("$label is not a regular file")
    startswith(realpath(current), realpath(root) * Base.Filesystem.path_separator) || set_fail("$label escapes root")
    current
end

function expected_manifest_units(manifest_path::String)::Dict{String,NamedTuple}
    bytes = read(manifest_path)
    !isempty(bytes) && bytes[end] == 0x0a && !(0x0d in bytes) || set_fail("manifest must be LF-only with terminal LF")
    lines = split(String(bytes[1:end-1]), '\n'; keepempty=true)
    length(lines) >= 2 && lines[1] == WORK_HEADER || set_fail("manifest header drift")
    units = Dict{String,NamedTuple}()
    order = Tuple{String,Int}[]
    for (offset, line) in enumerate(lines[2:end])
        ordinal = offset + 1
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 17 || set_fail("manifest field count drift at line $ordinal")
        work_id = fields[2]
        accession = fields[4]
        length_bp = parse_positive_decimal(fields[9], "manifest length")
        scale = parse_positive_decimal(fields[12], "manifest scale")
        work_id == "$accession@$scale" || set_fail("manifest work-unit identity drift")
        haskey(units, work_id) && set_fail("manifest has duplicate work-unit ID")
        units[work_id] = (; accession, scale, expected_rows=div(length_bp, scale))
        push!(order, (accession, scale))
    end
    scale_rank(scale) = something(findfirst(==(scale), SCALES), 0)
    issorted(order; by=item -> (item[1], scale_rank(item[2]))) || set_fail("manifest order drift")
    units
end

function validate_work_shard_set(parameters_path::String, manifest_path::String,
                                 source_root::String, plan_directory::String,
                                 execution_directory::String)
    for (path, label) in ((plan_directory, "plan directory"), (execution_directory, "execution directory"))
        reject_work_symlink_components(path, label)
        isdir(path) && !islink(path) || set_fail("$label must be a real directory")
    end
    plan_path = regular_below(plan_directory, "work_shard_plan.json", "work-shard plan")
    ledger_path = regular_below(execution_directory, "execution_ledger.tsv", "execution ledger")
    plan_sha = bytes2hex(sha256(read(plan_path)))
    bytes = read(ledger_path)
    !isempty(bytes) && bytes[end] == 0x0a && !(0x0d in bytes) || set_fail("execution ledger must be LF-only with terminal LF")
    lines = split(String(bytes[1:end-1]), '\n'; keepempty=true)
    length(lines) >= 2 && lines[1] == SET_LEDGER_HEADER || set_fail("execution ledger header drift")
    units = expected_manifest_units(manifest_path)
    coverage = Dict(work_id => Set{Int}() for work_id in keys(units))
    excluded = Set{String}()
    artifact_paths = Set{String}()
    seen_coordinates = Set{Tuple{String,Int}}()
    run_id = ""
    completed_shards = 0
    total_rows = 0
    for (offset, line) in enumerate(lines[2:end])
        ordinal = offset + 1
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 14 || set_fail("execution ledger field count drift at line $ordinal")
        (row_run_id, row_plan_sha, work_id, accession, scale_raw, start_raw, rows_raw,
         status, reason_code, case_relative, case_sha, artifact_relative,
         artifact_sha, artifact_size_raw) = fields
        occursin(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", row_run_id) || set_fail("run_id drift at line $ordinal")
        isempty(run_id) ? (run_id = row_run_id) : row_run_id == run_id || set_fail("mixed run_id in execution ledger")
        row_plan_sha == plan_sha || set_fail("plan SHA mismatch at line $ordinal")
        haskey(units, work_id) || set_fail("unknown work-unit ID at line $ordinal")
        unit = units[work_id]
        scale = parse_positive_decimal(scale_raw, "ledger scale")
        accession == unit.accession && scale == unit.scale || set_fail("work-unit coordinate drift at line $ordinal")
        coordinate = (work_id, parse(Int, start_raw))
        coordinate in seen_coordinates && set_fail("duplicate work-unit/start coordinate")
        push!(seen_coordinates, coordinate)
        rows = parse_nonnegative_or_zero(rows_raw, "ledger rows")
        artifact_size = parse_nonnegative_or_zero(artifact_size_raw, "artifact size")
        if status == "complete"
            isempty(reason_code) || set_fail("complete shard has a reason code")
            start = parse_nonnegative_or_zero(start_raw, "start window")
            1 <= rows <= 16 && start + rows <= unit.expected_rows || set_fail("complete shard interval drift")
            case_path = regular_below(plan_directory, case_relative, "case ledger")
            artifact_path = regular_below(execution_directory, artifact_relative, "Sounio artifact")
            occursin(r"^[0-9a-f]{64}$", case_sha) && bytes2hex(sha256(read(case_path))) == case_sha || set_fail("case SHA mismatch")
            occursin(r"^[0-9a-f]{64}$", artifact_sha) && bytes2hex(sha256(read(artifact_path))) == artifact_sha || set_fail("artifact SHA mismatch")
            filesize(artifact_path) == artifact_size || set_fail("artifact size mismatch")
            artifact_relative in artifact_paths && set_fail("duplicate artifact path")
            push!(artifact_paths, artifact_relative)
            for index in start:(start + rows - 1)
                index in coverage[work_id] && set_fail("overlapping window coverage")
                push!(coverage[work_id], index)
            end
            validate_work_unit(parameters_path, manifest_path, source_root, artifact_path,
                               start, rows, String(work_id), String(run_id))
            completed_shards += 1
            total_rows += rows
        elseif status == "excluded"
            start_raw == "-1" && rows == 0 && unit.expected_rows == 0 || set_fail("excluded work-unit interval drift")
            reason_code == "PARTIAL_WINDOW" || set_fail("excluded work-unit reason drift")
            all(isempty, (case_relative, case_sha, artifact_relative, artifact_sha)) && artifact_size == 0 ||
                set_fail("excluded work unit must not bind shard artifacts")
            work_id in excluded && set_fail("duplicate excluded work unit")
            push!(excluded, work_id)
        else
            set_fail("unknown execution status at line $ordinal")
        end
    end
    for (work_id, unit) in units
        if unit.expected_rows == 0
            work_id in excluded || set_fail("zero-window work unit is not reason-coded")
            isempty(coverage[work_id]) || set_fail("zero-window work unit has artifact coverage")
        else
            work_id in excluded && set_fail("complete work unit is incorrectly excluded")
            coverage[work_id] == Set(0:(unit.expected_rows - 1)) || set_fail("incomplete work-unit coverage: $work_id")
        end
    end
    observed_files = Set{String}()
    for (root, directories, files) in walkdir(execution_directory; topdown=true, follow_symlinks=false)
        any(name -> islink(joinpath(root, name)), vcat(directories, files)) && set_fail("execution tree contains a symlink")
        for name in files
            push!(observed_files, relpath(joinpath(root, name), execution_directory))
        end
    end
    observed_files == union(artifact_paths, Set(["execution_ledger.tsv"])) || set_fail("execution tree has missing or unmanifested files")
    println("U0_WORK_SHARD_SET_JULIA_PASS run_id=$run_id work_units=$(length(units)) shards=$completed_shards rows=$total_rows excluded_work_units=$(length(excluded)) tolerance=0 fixture_scope_nonpromotable=1")
end

function main_work_shard_set(args)
    length(args) == 5 || begin
        println(stderr, "usage: validate_u0_work_shard_set.jl <parameters.json> <manifest.tsv> <source-root> <plan-directory> <execution-directory>")
        exit(2)
    end
    validate_work_shard_set(args...)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main_work_shard_set(ARGS)
end
