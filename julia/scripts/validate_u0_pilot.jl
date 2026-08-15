#!/usr/bin/env julia

"""
Integral independent validator for a manifest-directed DOSA U0 execution.

Sounio remains the canonical producer. Julia returns to parameters, the full
work-unit manifest, source FASTAs, execution plan, logical artifacts and every
Parquet package. It recomputes every analytical row and emits a hash-closed
receipt. Fixture evidence is explicitly non-promotable; only a separately
frozen real pilot may request `u0_pilot` scope.
"""

include(joinpath(@__DIR__, "validate_u0_work_parquet_set.jl"))

pilot_fail(message) = error("U0_PILOT_JULIA_VALIDATION_FAIL: " * message)

mutable struct PilotJSONParser
    bytes::Vector{UInt8}
    index::Int
end

function pilot_skip_ws(parser::PilotJSONParser)
    while parser.index <= length(parser.bytes) && parser.bytes[parser.index] in (0x20, 0x09, 0x0a, 0x0d)
        parser.index += 1
    end
end

function pilot_string(parser::PilotJSONParser)::String
    parser.index <= length(parser.bytes) && parser.bytes[parser.index] == UInt8('"') || pilot_fail("JSON string expected")
    parser.index += 1
    output = UInt8[]
    while parser.index <= length(parser.bytes)
        byte = parser.bytes[parser.index]
        parser.index += 1
        byte == UInt8('"') && return String(output)
        byte >= 0x20 || pilot_fail("control byte in JSON string")
        if byte == UInt8('\\')
            parser.index <= length(parser.bytes) || pilot_fail("truncated JSON escape")
            escaped = parser.bytes[parser.index]
            parser.index += 1
            mapping = Dict(UInt8('"')=>UInt8('"'), UInt8('\\')=>UInt8('\\'), UInt8('/')=>UInt8('/'),
                           UInt8('b')=>0x08, UInt8('f')=>0x0c, UInt8('n')=>0x0a,
                           UInt8('r')=>0x0d, UInt8('t')=>0x09)
            haskey(mapping, escaped) || pilot_fail("unsupported JSON escape")
            push!(output, mapping[escaped])
        else
            push!(output, byte)
        end
    end
    pilot_fail("unterminated JSON string")
end

function pilot_value(parser::PilotJSONParser)
    pilot_skip_ws(parser)
    parser.index <= length(parser.bytes) || pilot_fail("truncated JSON")
    byte = parser.bytes[parser.index]
    if byte == UInt8('{')
        parser.index += 1
        result = Dict{String,Any}()
        pilot_skip_ws(parser)
        if parser.index <= length(parser.bytes) && parser.bytes[parser.index] == UInt8('}')
            parser.index += 1
            return result
        end
        while true
            pilot_skip_ws(parser)
            key = pilot_string(parser)
            haskey(result, key) && pilot_fail("duplicate JSON key: $key")
            pilot_skip_ws(parser)
            parser.index <= length(parser.bytes) && parser.bytes[parser.index] == UInt8(':') || pilot_fail("JSON colon expected")
            parser.index += 1
            result[key] = pilot_value(parser)
            pilot_skip_ws(parser)
            parser.index <= length(parser.bytes) || pilot_fail("truncated JSON object")
            delimiter = parser.bytes[parser.index]
            parser.index += 1
            delimiter == UInt8('}') && return result
            delimiter == UInt8(',') || pilot_fail("JSON object delimiter expected")
        end
    elseif byte == UInt8('[')
        parser.index += 1
        result = Any[]
        pilot_skip_ws(parser)
        if parser.index <= length(parser.bytes) && parser.bytes[parser.index] == UInt8(']')
            parser.index += 1
            return result
        end
        while true
            push!(result, pilot_value(parser))
            pilot_skip_ws(parser)
            parser.index <= length(parser.bytes) || pilot_fail("truncated JSON array")
            delimiter = parser.bytes[parser.index]
            parser.index += 1
            delimiter == UInt8(']') && return result
            delimiter == UInt8(',') || pilot_fail("JSON array delimiter expected")
        end
    elseif byte == UInt8('"')
        return pilot_string(parser)
    elseif byte == UInt8('-') || UInt8('0') <= byte <= UInt8('9')
        start = parser.index
        byte == UInt8('-') && (parser.index += 1)
        parser.index <= length(parser.bytes) || pilot_fail("truncated JSON integer")
        if parser.bytes[parser.index] == UInt8('0')
            parser.index += 1
            parser.index <= length(parser.bytes) && UInt8('0') <= parser.bytes[parser.index] <= UInt8('9') && pilot_fail("noncanonical JSON integer")
        else
            UInt8('1') <= parser.bytes[parser.index] <= UInt8('9') || pilot_fail("invalid JSON integer")
            while parser.index <= length(parser.bytes) && UInt8('0') <= parser.bytes[parser.index] <= UInt8('9')
                parser.index += 1
            end
        end
        raw = String(parser.bytes[start:parser.index-1])
        try
            return parse(Int, raw)
        catch
            pilot_fail("JSON integer exceeds Int")
        end
    end
    for (literal, value) in (("true", true), ("false", false), ("null", nothing))
        raw = Vector{UInt8}(codeunits(literal))
        finish = parser.index + length(raw) - 1
        if finish <= length(parser.bytes) && parser.bytes[parser.index:finish] == raw
            parser.index = finish + 1
            return value
        end
    end
    pilot_fail("invalid JSON value")
end

function pilot_json(path::String, label::String)::Dict{String,Any}
    reject_work_symlink_components(path, label)
    isfile(path) && !islink(path) || pilot_fail("$label must be a regular non-symlink file")
    bytes = read(path)
    !isempty(bytes) && bytes[end] == 0x0a && !(0x0d in bytes) ||
        pilot_fail("$label must be LF-only with terminal LF")
    try
        parser = PilotJSONParser(bytes, 1)
        value = pilot_value(parser)
        pilot_skip_ws(parser)
        parser.index == length(bytes) + 1 || pilot_fail("$label has trailing JSON bytes")
        value isa Dict{String,Any} || pilot_fail("$label must be a JSON object")
        value
    catch error
        pilot_fail("$label is not valid JSON: $(sprint(showerror, error))")
    end
end

pilot_sha(path::String)::String = bytes2hex(sha256(read(path)))

function pilot_integer(value, label::String)::Int
    value isa Integer && value >= 0 || pilot_fail("$label must be a nonnegative integer")
    Int(value)
end

function canonical_json(value)::String
    if value isa AbstractDict
        keys_sorted = sort!(collect(String(key) for key in keys(value)))
        return "{" * join((pilot_quote(key) * ":" * canonical_json(value[key]) for key in keys_sorted), ",") * "}"
    elseif value isa AbstractVector
        return "[" * join((canonical_json(item) for item in value), ",") * "]"
    elseif value === nothing
        return "null"
    elseif value isa Bool
        return value ? "true" : "false"
    elseif value isa Integer
        return string(value)
    elseif value isa AbstractString
        return pilot_quote(value)
    end
    pilot_fail("unsupported receipt JSON value: $(typeof(value))")
end

function pilot_quote(value::AbstractString)::String
    output = IOBuffer()
    write(output, '"')
    for byte in codeunits(value)
        if byte == UInt8('"')
            write(output, "\\\"")
        elseif byte == UInt8('\\')
            write(output, "\\\\")
        elseif byte == 0x0a
            write(output, "\\n")
        elseif byte == 0x0d
            write(output, "\\r")
        elseif byte == 0x09
            write(output, "\\t")
        elseif byte >= 0x20
            write(output, byte)
        else
            pilot_fail("unsupported control byte in receipt string")
        end
    end
    write(output, '"')
    String(take!(output))
end

function parse_set_summary(package_root::String)
    ledger = regular_below(realpath(package_root), "parquet_set_ledger.tsv", "Parquet set ledger")
    rows = read_tsv_lines(ledger, PARQUET_SET_HEADER, "Parquet set ledger")
    package_hashes = Dict{String,Any}()
    total = 0
    for (offset, line) in enumerate(rows)
        fields = split(line, '\t'; keepempty=true)
        length(fields) == 10 || pilot_fail("Parquet set ledger field count drift at row $offset")
        scale = parse_positive_decimal(fields[2], "Parquet scale")
        row_count = parse_positive_decimal(fields[3], "Parquet rows")
        package_relative = fields[4]
        package_parts = safe_relative(package_relative, "package path")
        package_manifest = joinpath(realpath(package_root), package_parts..., "dosa-payload-manifest.json")
        isfile(package_manifest) && !islink(package_manifest) || pilot_fail("package manifest is unavailable")
        observed_sha = pilot_sha(package_manifest)
        observed_sha == fields[5] || pilot_fail("package manifest SHA mismatch at scale $scale")
        package_hashes["scale-$scale"] = observed_sha
        total += row_count
    end
    total, package_hashes
end

function validate_receipt_bindings(parameters_path::String, manifest_path::String,
                                   source_manifest_path::String, source_index_path::String,
                                   payload_manifest_path::String, execution_receipt_path::String,
                                   output_manifest_path::String, evidence_root::String)
    output = pilot_json(output_manifest_path, "Sounio output manifest")
    execution = pilot_json(execution_receipt_path, "Sounio execution receipt")
    output["schema_version"] == "dosa-v3-u0-sounio-output-manifest-1" || pilot_fail("output manifest version drift")
    execution["schema_version"] == "dosa-v3-u0-sounio-execution-receipt-1" || pilot_fail("execution receipt version drift")
    output["parameters_sha256"] == pilot_sha(parameters_path) || pilot_fail("output parameters binding drift")
    output["source_manifest_sha256"] == pilot_sha(source_manifest_path) || pilot_fail("output source-manifest binding drift")
    output["work_unit_manifest_sha256"] == pilot_sha(manifest_path) || pilot_fail("output work-manifest binding drift")
    execution["parameters_sha256"] == pilot_sha(parameters_path) || pilot_fail("execution parameters binding drift")
    execution["source_manifest_sha256"] == pilot_sha(source_manifest_path) || pilot_fail("execution source-manifest binding drift")
    execution["work_unit_manifest_sha256"] == pilot_sha(manifest_path) || pilot_fail("execution work-manifest binding drift")
    execution["output_manifest_sha256"] == pilot_sha(output_manifest_path) || pilot_fail("execution output-manifest binding drift")
    execution["canonical_producer"] == "Sounio" || pilot_fail("canonical producer drift")
    execution["null_model"] == "euler_wilson_fixed_endpoints_v1" || pilot_fail("null model drift")
    execution["null_replicates"] == 1000 || pilot_fail("null replicate drift")
    execution["status"] == "PASS" && execution["all_work_units_complete"] === true ||
        pilot_fail("Sounio execution is incomplete")
    output["all_work_units_complete"] === true || pilot_fail("Sounio output is incomplete")
    rows = pilot_integer(output["rows_emitted"], "output rows")
    rows > 0 || pilot_fail("output manifest has no analytical rows")
    rows == pilot_integer(execution["rows_emitted"], "execution rows") || pilot_fail("execution/output row mismatch")
    pilot_integer(output["work_units_expected"], "expected work units") ==
        pilot_integer(output["work_units_completed"], "completed work units") || pilot_fail("output work units are incomplete")
    pilot_integer(execution["work_units_expected"], "execution expected work units") ==
        pilot_integer(execution["work_units_completed"], "execution completed work units") || pilot_fail("execution work units are incomplete")

    root = realpath(evidence_root)
    artifacts = get(output, "artifacts", nothing)
    artifacts isa AbstractVector && !isempty(artifacts) || pilot_fail("output artifact ledger is empty")
    artifact_rows = 0
    for (index, artifact) in enumerate(artifacts)
        artifact isa AbstractDict || pilot_fail("output artifact $index is not an object")
        relative = String(artifact["path"])
        target = regular_below(root, relative, "Sounio output artifact $index")
        pilot_sha(target) == artifact["sha256"] || pilot_fail("output artifact SHA mismatch at index $index")
        filesize(target) == pilot_integer(artifact["size_bytes"], "artifact size") || pilot_fail("output artifact size mismatch")
        bytes = read(target)
        !isempty(bytes) && bytes[end] == 0x0a && !(0x0d in bytes) || pilot_fail("output artifact grammar drift")
        actual_rows = length(split(String(bytes[1:end-1]), '\n'; keepempty=true))
        expected_rows = pilot_integer(artifact["rows"], "artifact rows")
        actual_rows == expected_rows || pilot_fail("output artifact row mismatch")
        artifact_rows += expected_rows
    end
    artifact_rows == rows || pilot_fail("output artifact rows do not reconcile")

    for (path, label) in ((source_index_path, "source index"), (payload_manifest_path, "payload manifest"))
        pilot_json(path, label)
    end
    rows
end

function validate_u0_pilot(args)
    length(args) == 14 || begin
        println(stderr, "usage: validate_u0_pilot.jl <parameters.json> <work-units.tsv> <source-root> <plan-directory> <execution-directory> <package-root> <evidence-root> <source-manifest.json-or-tsv> <source-index.json> <payload-manifest.json> <sounio-execution-receipt.json> <sounio-output-manifest.json> <evidence-scope> <receipt-output.json>")
        exit(2)
    end
    (parameters_path, manifest_path, source_root, plan_directory, execution_directory,
     package_root, evidence_root, source_manifest_path, source_index_path,
     payload_manifest_path, execution_receipt_path, output_manifest_path,
     evidence_scope, receipt_output) = args
    evidence_scope in ("fixture-only-nonpromotable", "u0_pilot") || pilot_fail("unsupported evidence scope")
    if evidence_scope == "u0_pilot"
        realpath(source_manifest_path) != realpath(manifest_path) ||
            pilot_fail("u0_pilot scope requires a distinct frozen source manifest")
        source_document = pilot_json(source_manifest_path, "real-pilot source manifest")
        get(source_document, "schema_version", nothing) == "3.0.0" || pilot_fail("real-pilot source manifest version drift")
        get(source_document, "source_provider", nothing) == "NCBI_Datasets" || pilot_fail("real-pilot source provider drift")
        selected = get(source_document, "selected_records", nothing)
        selected isa AbstractVector && !isempty(selected) || pilot_fail("real-pilot source manifest has no selected records")
    end
    reject_work_symlink_components(receipt_output, "receipt output")
    !ispath(receipt_output) && isdir(dirname(receipt_output)) && !islink(dirname(receipt_output)) ||
        pilot_fail("receipt output must be absent below a real directory")

    validate_work_shard_set(parameters_path, manifest_path, source_root, plan_directory, execution_directory)
    validate_u0_work_parquet_set(parameters_path, manifest_path, source_root, package_root)
    rows = validate_receipt_bindings(
        parameters_path, manifest_path, source_manifest_path, source_index_path,
        payload_manifest_path, execution_receipt_path, output_manifest_path, evidence_root,
    )
    parquet_rows, package_hashes = parse_set_summary(package_root)
    parquet_rows == rows || pilot_fail("logical and Parquet row counts differ")

    implementation = abspath(@__FILE__)
    project = normpath(joinpath(@__DIR__, "..", "Project.toml"))
    manifest = normpath(joinpath(@__DIR__, "..", "Manifest.toml"))
    receipt = Dict{String,Any}(
        "schema_version" => "dosa-v3-u0-julia-validation-receipt-1",
        "receipt_id" => "$(basename(dirname(receipt_output)))-julia-validation",
        "evidence_scope" => evidence_scope,
        "status" => "PASS",
        "language" => "Julia",
        "version" => string(VERSION),
        "implementation_path" => "julia/scripts/validate_u0_pilot.jl",
        "implementation_sha256" => pilot_sha(implementation),
        "project_sha256" => pilot_sha(project),
        "manifest_sha256" => pilot_sha(manifest),
        "parameters_sha256" => pilot_sha(parameters_path),
        "source_manifest_sha256" => pilot_sha(source_manifest_path),
        "work_unit_manifest_sha256" => pilot_sha(manifest_path),
        "source_index_sha256" => pilot_sha(source_index_path),
        "payload_manifest_sha256" => pilot_sha(payload_manifest_path),
        "sounio_execution_receipt_sha256" => pilot_sha(execution_receipt_path),
        "sounio_output_manifest_sha256" => pilot_sha(output_manifest_path),
        "full_pilot_recomputed" => evidence_scope == "u0_pilot",
        "rows_recomputed" => rows,
        "disagreements" => 0,
        "absolute_tolerance" => 0,
        "package_manifest_sha256s" => package_hashes,
        "parquet_rows_recomputed" => parquet_rows,
        "parquet_disagreements" => 0,
    )
    open(receipt_output, "w") do io
        write(io, canonical_json(receipt), "\n")
    end
    gate_pass = evidence_scope == "u0_pilot"
    println(
        "U0_PILOT_JULIA_INTEGRAL_PASS evidence_scope=$evidence_scope " *
        "rows=$rows parquet_rows=$parquet_rows packages=$(length(package_hashes)) tolerance=0 " *
        "gate_u0_pass=$gate_pass"
    )
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    validate_u0_pilot(ARGS)
end
