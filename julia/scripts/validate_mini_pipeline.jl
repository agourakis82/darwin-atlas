#!/usr/bin/env julia

"""
Independent Base-only validator for the Sounio mini-pipeline fixture.

The validator re-reads the frozen FASTA and metadata bytes, re-derives the
metadata association, the non-overlapping positional windows, the delta_R /
delta_RC metrics, and every exclusion, then rebuilds the expected JSONL
byte for byte and requires exact equality with the persisted Sounio artifact.
For the negative metadata fixtures it independently derives the expected
error tuple (code, record, offset, byte) and requires exact equality.

It loads no packages (Base only), does not execute Sounio, and never falls
back to producing the artifact itself.
"""

if length(ARGS) != 2
    println(stderr, "usage: validate_mini_pipeline.jl <sounio-run.log> <fixture-directory>")
    exit(2)
end

const LOG_PATH = only(ARGS[1:1])
const FIXTURE_DIRECTORY = only(ARGS[2:2])
const WINDOW_BYTES = 4
const SCHEMA_VERSION = "0.1.0"
const METRIC_VERSION = "0.1.0"
const HEADER_ID_BYTES = 256

const IUPAC_INDEX = let mapping = Dict{UInt8, Int}()
    for (index, symbol) in enumerate(codeunits("ACGTRYSWKMBDHVN"))
        mapping[symbol] = index - 1
        mapping[symbol + 0x20] = index - 1
    end
    mapping
end
const COMPLEMENT = [3, 2, 1, 0]

const CASE_SPECS = [
    (name="main", metadata="pipeline_metadata.tsv", rc=0),
    (name="metadata_invalid", metadata="metadata_invalid.tsv", rc=9),
    (name="metadata_mismatch", metadata="metadata_mismatch.tsv", rc=10),
    (name="metadata_short", metadata="metadata_short.tsv", rc=10),
]

struct PipelineError
    code::String
    record::Int
    offset::Int
    byte::Int
end

struct MetadataRow
    sequence_accession_version::String
    assembly_accession_version::String
    replicon_class::String
    declared_topology::String
    source_scope::String
end

json_safe(value::AbstractString) =
    !isempty(value) && all(c -> isascii(c) && (isletter(c) || isdigit(c) || c in ('.', '_', '-')), value)

"""
Validate the metadata text exactly like the Sounio loader. Returns either a
Vector{MetadataRow} or a PipelineError (record is always 0 at load time;
offset is the zero-based byte offset of the offending logical line).
"""
function load_metadata(text::String)
    bytes = codeunits(text)
    n = length(bytes)
    n > 0 || return PipelineError("METADATA_INVALID", 0, 0, -1)

    lines = Tuple{Int, Int}[]  # 1-based inclusive byte ranges, CR stripped, empty lines skipped
    start = 1
    while start <= n + 1
        stop = start
        while stop <= n && bytes[stop] != 0x0a
            stop += 1
        end
        line_end = stop - 1
        if line_end >= start && bytes[line_end] == 0x0d
            line_end -= 1
        end
        line_end >= start && push!(lines, (start, line_end))
        stop > n && break
        start = stop + 1
    end

    isempty(lines) && return PipelineError("METADATA_INVALID", 0, n, -1)
    slice(range) = String(bytes[range[1]:range[2]])

    expected_header = [
        "record_index", "sequence_accession_version", "assembly_accession_version",
        "replicon_class", "declared_topology", "source_scope",
    ]
    split(slice(lines[1]), '\t') == expected_header ||
        return PipelineError("METADATA_INVALID", 0, lines[1][1] - 1, -1)

    rows = MetadataRow[]
    for (position, range) in enumerate(Iterators.drop(lines, 1))
        fields = split(slice(range), '\t')
        length(fields) == 6 || return PipelineError("METADATA_INVALID", 0, range[1] - 1, -1)
        tryparse(Int, fields[1]) == position ||
            return PipelineError("METADATA_INVALID", 0, range[1] - 1, -1)
        all(json_safe, fields[2:6]) || return PipelineError("METADATA_INVALID", 0, range[1] - 1, -1)
        fields[5] in ("circular", "linear", "unknown") ||
            return PipelineError("METADATA_INVALID", 0, range[1] - 1, -1)
        push!(rows, MetadataRow(fields[2], fields[3], fields[4], fields[5], fields[6]))
    end
    isempty(rows) && return PipelineError("METADATA_INVALID", 0, n, -1)
    return rows
end

function format_ratio(numerator::Int, denominator::Int)
    scaled = div(numerator * 1_000_000, denominator)
    string(div(scaled, 1_000_000), ".", lpad(string(mod(scaled, 1_000_000)), 6, '0'))
end

"""Build one JSONL line with the exact Sounio field order and formatting."""
function emit_window(row::MetadataRow, record_index::Int, window_index::Int,
                     window_start::Int, window::Vector{Int})
    window_length = length(window)
    window_end = window_start + window_length
    partial = window_length < WINDOW_BYTES
    canonical = all(base -> 0 <= base <= 3, window)
    excluded = partial || !canonical

    reverse_mismatches = 0
    rc_mismatches = 0
    if !excluded
        for i in 1:window_length
            opposite = window[window_length - i + 1]
            window[i] != opposite && (reverse_mismatches += 1)
            window[i] != COMPLEMENT[opposite + 1] && (rc_mismatches += 1)
        end
    end

    io = IOBuffer()
    print(io, "{\"schema_version\":\"", SCHEMA_VERSION, "\",\"metric_version\":\"", METRIC_VERSION,
        "\",\"assembly_accession_version\":\"", row.assembly_accession_version,
        "\",\"sequence_accession_version\":\"", row.sequence_accession_version,
        "\",\"replicon_class\":\"", row.replicon_class,
        "\",\"declared_topology\":\"", row.declared_topology,
        "\",\"source_scope\":\"", row.source_scope,
        "\",\"record_index\":", record_index,
        ",\"window_index\":", window_index,
        ",\"window_start\":", window_start,
        ",\"window_end\":", window_end,
        ",\"window_length\":", window_length,
        ",\"ambiguity_policy\":\"canonical_only\",\"status\":\"",
        excluded ? "excluded" : "ok", "\",\"reason_code\":")
    if partial
        print(io, "\"PARTIAL_WINDOW\"")
    elseif !canonical
        print(io, "\"AMBIGUOUS_WINDOW\"")
    else
        print(io, "null")
    end
    print(io, ",\"effective_count\":", excluded ? 0 : window_length)
    print(io, ",\"delta_R_mismatches\":", excluded ? "null" : string(reverse_mismatches))
    print(io, ",\"delta_RC_mismatches\":", excluded ? "null" : string(rc_mismatches))
    print(io, ",\"denominator\":", excluded ? "null" : string(window_length))
    print(io, ",\"delta_R\":", excluded ? "null" : format_ratio(reverse_mismatches, window_length))
    print(io, ",\"delta_RC\":", excluded ? "null" : format_ratio(rc_mismatches, window_length))
    print(io, ",\"fixed_R\":", excluded ? "null" : string(reverse_mismatches == 0))
    print(io, ",\"fixed_RC\":", excluded ? "null" : string(rc_mismatches == 0))
    print(io, "}")
    return String(take!(io))
end

"""
Replicate the Sounio --pipeline driver: stream the FASTA bytes, associate each
record with its metadata row, and either emit every JSONL line or return the
first PipelineError with Sounio's precedence. Returns (lines, error).
"""
function simulate_pipeline(fasta::Vector{UInt8}, rows::Vector{MetadataRow})
    lines = String[]
    record_index = 0
    have_header = false
    in_header = false
    at_line_start = true
    header_nonspace = 0
    header_token_done = false
    header_id = UInt8[]
    sequence_length = 0
    window = Int[]
    window_start = 0
    window_count = 0
    bytes_read = 0

    function finish_record(offset, byte)
        sequence_length <= 0 && return PipelineError("EMPTY_SEQUENCE", record_index, offset, byte)
        if !isempty(window)
            push!(lines, emit_window(rows[record_index], record_index, window_count, window_start, window))
            empty!(window)
            window_count += 1
        end
        return nothing
    end

    function validate_header(offset)
        isempty(header_id) && return PipelineError("EMPTY_HEADER", record_index, offset, -1)
        record_index > length(rows) && return PipelineError("METADATA_MISMATCH", record_index, offset, -1)
        String(copy(header_id)) == rows[record_index].sequence_accession_version ||
            return PipelineError("METADATA_MISMATCH", record_index, offset, -1)
        return nothing
    end

    for byte in fasta
        offset = bytes_read
        bytes_read += 1
        byte == 0x0d && continue

        if byte == 0x0a
            if in_header
                header_nonspace > 0 ||
                    return (lines, PipelineError("EMPTY_HEADER", record_index, offset, Int(byte)))
                error = validate_header(offset)
                isnothing(error) || return (lines, error)
                in_header = false
            end
            at_line_start = true
            continue
        end

        if at_line_start && byte == UInt8('>')
            if have_header
                error = finish_record(offset, Int(byte))
                isnothing(error) || return (lines, error)
            end
            record_index += 1
            empty!(header_id)
            header_nonspace = 0
            header_token_done = false
            sequence_length = 0
            empty!(window)
            window_start = 0
            window_count = 0
            have_header = true
            in_header = true
            at_line_start = false
            continue
        end

        at_line_start = false
        if in_header
            if byte != 0x20 && byte != 0x09
                header_nonspace += 1
            end
            if !header_token_done
                if byte == 0x20 || byte == 0x09
                    header_token_done = true
                else
                    length(header_id) >= HEADER_ID_BYTES &&
                        return (lines, PipelineError("HEADER_TOKEN_TOO_LONG", record_index, offset, Int(byte)))
                    push!(header_id, byte)
                end
            end
            continue
        end

        have_header || return (lines, PipelineError("SEQUENCE_BEFORE_HEADER", record_index, offset, Int(byte)))
        index = get(IUPAC_INDEX, byte, -1)
        index >= 0 || return (lines, PipelineError("INVALID_SYMBOL", record_index, offset, Int(byte)))
        sequence_length += 1
        push!(window, index)
        if length(window) == WINDOW_BYTES
            push!(lines, emit_window(rows[record_index], record_index, window_count, window_start, window))
            window_start += WINDOW_BYTES
            empty!(window)
            window_count += 1
        end
    end

    if in_header
        header_nonspace > 0 || return (lines, PipelineError("EMPTY_HEADER", record_index, bytes_read, -1))
        error = validate_header(bytes_read)
        isnothing(error) || return (lines, error)
    end
    have_header || return (lines, PipelineError("NO_RECORDS", record_index, bytes_read, -1))
    error = finish_record(bytes_read, -1)
    isnothing(error) || return (lines, error)
    record_index == length(rows) ||
        return (lines, PipelineError("METADATA_MISMATCH", record_index, bytes_read, -1))
    return (lines, nothing)
end

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
    artifact = nothing
    artifact_lines = nothing
    artifact_sha = nothing
    current = nothing

    for line in eachline(path)
        if startswith(line, "DOSA_PIPELINE_CASE ")
            fields = parse_fields(line)
            name = fields["name"]
            haskey(cases, name) && error("duplicate mini-pipeline case: $name")
            cases[name] = Dict{String, Any}(
                "expected_rc" => parse(Int, fields["expected_rc"]),
                "actual_rc" => parse(Int, fields["actual_rc"]),
                "error" => nothing,
            )
            current = name
        elseif startswith(line, "DOSA_FASTA_ERROR ")
            isnothing(current) && error("error appeared before a case marker")
            isnothing(cases[current]["error"]) || error("duplicate error for case $current")
            cases[current]["error"] = parse_fields(line)
        elseif startswith(line, "sounio_pipeline_jsonl_artifact=")
            artifact = split(line, '='; limit=2)[2]
        elseif startswith(line, "sounio_pipeline_jsonl_lines=")
            artifact_lines = parse(Int, split(line, '='; limit=2)[2])
        elseif startswith(line, "sounio_pipeline_jsonl_sha256=")
            artifact_sha = split(line, '='; limit=2)[2]
        end
    end
    return cases, artifact, artifact_lines, artifact_sha
end

observed, artifact_path, artifact_lines, artifact_sha = parse_runner_log(LOG_PATH)
Set(keys(observed)) == Set(spec.name for spec in CASE_SPECS) || error(
    "unexpected mini-pipeline case set: $(sort!(collect(keys(observed))))",
)
isnothing(artifact_path) && error("runner log does not name a JSONL artifact")
isnothing(artifact_sha) && error("runner log does not hash the JSONL artifact")
match(r"^[0-9a-f]{64}$", artifact_sha) !== nothing || error("malformed artifact sha256 in runner log")
isfile(artifact_path) || error("persisted JSONL artifact is missing: $artifact_path")

fasta_bytes = read(joinpath(FIXTURE_DIRECTORY, "pipeline_fixture.fa"))
validated_windows = Ref(0)

for spec in CASE_SPECS
    metadata_text = String(read(joinpath(FIXTURE_DIRECTORY, spec.metadata)))
    case = observed[spec.name]

    case["expected_rc"] == spec.rc || error("runner expectation drift for $(spec.name)")
    case["actual_rc"] == spec.rc || error("Sounio exit mismatch for $(spec.name)")

    rows_or_error = load_metadata(metadata_text)
    if rows_or_error isa PipelineError
        expected = rows_or_error
        expected_lines = String[]
    else
        expected_lines, error_or_nothing = simulate_pipeline(fasta_bytes, rows_or_error)
        expected = error_or_nothing
    end

    if spec.rc == 0
        isnothing(expected) || error(
            "Julia independently derived an error for $(spec.name): $(expected)",
        )
        isnothing(case["error"]) || error("unexpected Sounio error for $(spec.name)")

        expected_bytes = join(expected_lines, "\n") * "\n"
        actual_bytes = String(read(artifact_path))
        actual_bytes == expected_bytes || error(
            "JSONL mismatch for $(spec.name): persisted Sounio artifact differs from the " *
            "independent Julia recomputation (byte-exact comparison)",
        )
        artifact_lines == length(expected_lines) || error("runner JSONL line count mismatch")
        validated_windows[] += length(expected_lines)
    else
        expected isa PipelineError || error(
            "Julia independently derived success for negative case $(spec.name)",
        )
        observed_error = case["error"]
        isnothing(observed_error) && error("missing Sounio error for $(spec.name)")
        observed_error["code"] == expected.code || error(
            "error code mismatch for $(spec.name): Sounio=$(observed_error["code"]) Julia=$(expected.code)",
        )
        observed_error["record"] == string(expected.record) || error(
            "error record mismatch for $(spec.name): Sounio=$(observed_error["record"]) Julia=$(expected.record)",
        )
        observed_error["offset"] == string(expected.offset) || error(
            "error offset mismatch for $(spec.name): Sounio=$(observed_error["offset"]) Julia=$(expected.offset)",
        )
        observed_error["byte"] == string(expected.byte) || error(
            "error byte mismatch for $(spec.name): Sounio=$(observed_error["byte"]) Julia=$(expected.byte)",
        )
    end
end

println("DOSA_JULIA_MINI_PIPELINE_DIFFERENTIAL_OK")
println("validated_cases=$(length(CASE_SPECS)) validated_windows=$(validated_windows[]) tolerance=0")
