#!/usr/bin/env julia

"""
Independent Base-only validator for the Sounio mini-pipeline fixture.

The validator re-reads the frozen FASTA, metadata, and rendered flat
parameter bytes, independently re-validates the parameter grammar (strict
13-line fixed-order form, exact domains, exact error offsets), re-derives the
metadata association, the parameterized non-overlapping positional windows,
the delta_R / delta_RC metrics, the masked k-mer imbalance fields for
k = 1..8 with explicit unavailable reasons, and every exclusion, then
rebuilds the expected JSONL byte for byte and requires exact equality with
the persisted Sounio artifact. For the negative metadata and parameter
fixtures it independently derives the expected error tuple
(code, record, offset, byte) and requires exact equality.

It loads no packages (Base only), does not execute Sounio, and never falls
back to producing the artifact itself.
"""

if length(ARGS) < 2 || length(ARGS) > 3
    println(stderr, "usage: validate_mini_pipeline.jl <sounio-run.log> <fixture-directory> [case-set]")
    exit(2)
end

const LOG_PATH = only(ARGS[1:1])
const FIXTURE_DIRECTORY = only(ARGS[2:2])
# Case sets: "fixture" is the frozen mini-pipeline battery (13 cases);
# "cohort_smoke" is the complete-replicon engineering smoke (1 case).
const CASE_SET = length(ARGS) == 3 ? ARGS[3] : "fixture"
const SCHEMA_VERSION = "0.2.0"
const METRIC_VERSION = "0.1.0"
const HEADER_ID_BYTES = 256
const KMER_ABS_MAX_K = 8
const WINDOW_MAX_BYTES = 16

const IUPAC_INDEX = let mapping = Dict{UInt8, Int}()
    for (index, symbol) in enumerate(codeunits("ACGTRYSWKMBDHVN"))
        mapping[symbol] = index - 1
        mapping[symbol + 0x20] = index - 1
    end
    mapping
end
const COMPLEMENT = [3, 2, 1, 0]

# Every case binds a FASTA, a metadata TSV, and a named rendered flat
# parameter file (path announced by the runner log). Parameter-negative
# cases never reach FASTA processing: the executable validates parameters
# first and must exit 11 (PARAM_INVALID).
const CASE_SPECS = if CASE_SET == "fixture"
    [
    (name="main", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="main", rc=0),
    (name="k8", fasta="pipeline_k8_fixture.fa", metadata="pipeline_k8_metadata.tsv", params="k8", rc=0),
    (name="metadata_invalid", fasta="pipeline_fixture.fa", metadata="metadata_invalid.tsv", params="main", rc=9),
    (name="metadata_mismatch", fasta="pipeline_fixture.fa", metadata="metadata_mismatch.tsv", params="main", rc=10),
    (name="metadata_short", fasta="pipeline_fixture.fa", metadata="metadata_short.tsv", params="main", rc=10),
    (name="param_window_size_zero", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_window_size_zero", rc=11),
    (name="param_stride_zero", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_stride_zero", rc=11),
    (name="param_stride_mismatch", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_stride_mismatch", rc=11),
    (name="param_k_min_two", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_k_min_two", rc=11),
    (name="param_k_max_nine", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_k_max_nine", rc=11),
    (name="param_k_max_above_window", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_k_max_above_window", rc=11),
    (name="param_unknown_policy", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_unknown_policy", rc=11),
    (name="param_extra_field", fasta="pipeline_fixture.fa", metadata="pipeline_metadata.tsv", params="param_extra_field", rc=11),
]
elseif CASE_SET == "cohort_smoke"
    [(name="smoke_pOSAK1", fasta="nc_002127_1.fa", metadata="nc_002127_1_metadata.tsv", params="smoke_pOSAK1", rc=0)]
else
    error("unknown case set: $CASE_SET")
end

const DNA_BASES = "ACGT"
const DNA_COMPLEMENT = Dict('A' => 'T', 'C' => 'G', 'G' => 'C', 'T' => 'A')

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

struct PipelineParams
    window_size::Int
    stride::Int
    k_max::Int
    min_kmer_effective_count::Int
    sha256::String
end

json_safe(value::AbstractString) =
    !isempty(value) && all(c -> isascii(c) && (isletter(c) || isdigit(c) || c in ('.', '_', '-')), value)

# ---------------------------------------------------------------------------
# Flat parameter grammar (independent mirror of the Sounio strict parser)
# ---------------------------------------------------------------------------

"""Mirror of parse_nonnegative_i64: decimal digits only, empty or any
non-digit yields -1. Parsed in BigInt so over-i64 inputs cannot wrap into a
falsely valid domain."""
function parse_nonnegative(raw::AbstractString)
    isempty(raw) && return BigInt(-1)
    all(isdigit, raw) || return BigInt(-1)
    parse(BigInt, raw)
end

"""
Extract the value of `expected_key=value` from `line`, or `nothing` when the
key or the '=' separator does not match exactly (mirror of flat_param_value,
which returns the empty string and thereby fails every domain check).
"""
function flat_value(line::AbstractString, expected_key::AbstractString)
    startswith(line, expected_key) || return nothing
    length(line) > ncodeunits(expected_key) || return nothing
    codeunits(line)[ncodeunits(expected_key) + 1] == UInt8('=') || return nothing
    String(codeunits(line)[ncodeunits(expected_key) + 2:end])
end

"""
Validate one flat parameter line (0-based `line_index`) against the strict
grammar, threading the window size exactly like the Sounio validator.
Returns true/false; `state` accumulates window_size for the stride/k_max
cross-checks.
"""
function validate_param_line(line::AbstractString, line_index::Int, state::Ref{Int})
    if line_index == 0
        return flat_value(line, "schema_version") == "1.0.0"
    elseif line_index == 1
        return flat_value(line, "specification_version") == "0.1.0"
    elseif line_index == 2
        value = parse_nonnegative(something(flat_value(line, "window_size"), ""))
        (value < 1 || value > WINDOW_MAX_BYTES) && return false
        state[] = Int(value)
        return true
    elseif line_index == 3
        value = parse_nonnegative(something(flat_value(line, "stride"), ""))
        return value > 0 && value == state[]
    elseif line_index == 4
        return parse_nonnegative(something(flat_value(line, "k_min"), "")) == 1
    elseif line_index == 5
        value = parse_nonnegative(something(flat_value(line, "k_max"), ""))
        return value >= 1 && value <= KMER_ABS_MAX_K && value <= state[]
    elseif line_index == 6
        return parse_nonnegative(something(flat_value(line, "min_kmer_effective_count"), "")) >= 1
    elseif line_index == 7
        return flat_value(line, "positional_ambiguity_policy") == "canonical_only"
    elseif line_index == 8
        return flat_value(line, "kmer_ambiguity_policy") == "masked"
    elseif line_index == 9
        return flat_value(line, "coordinate_system") == "zero_based_half_open"
    elseif line_index == 10
        return flat_value(line, "window_wraparound") == "false"
    elseif line_index == 11
        return flat_value(line, "output_order") == "manifest_record_then_window_start"
    elseif line_index == 12
        value = flat_value(line, "parameters_sha256")
        return value !== nothing && match(r"^[0-9a-f]{64}$", value) !== nothing
    end
    return false
end

"""
Independently validate the rendered flat parameter bytes with Sounio's exact
semantics: CR stripped, empty lines skipped, at most 13 non-empty lines in
fixed order, error offset is the zero-based byte offset of the offending
line, and a wrong line count fails at offset n (total byte count). Returns
either a PipelineParams or a PipelineError.
"""
function load_parameters(text::String)
    bytes = codeunits(text)
    n = length(bytes)
    n > 0 || return PipelineError("PARAM_INVALID", 0, 0, -1)

    lines = Tuple{Int, Int}[]  # 0-based [start, stop) byte ranges, CR stripped, empty skipped
    start = 1  # 1-based Julia cursor; Sounio offset is start - 1
    while start <= n + 1
        stop = start
        while stop <= n && bytes[stop] != 0x0a
            stop += 1
        end
        line_end = stop - 1
        if line_end >= start && bytes[line_end] == 0x0d
            line_end -= 1
        end
        line_end >= start && push!(lines, (start - 1, line_end - 1))
        stop > n && break
        start = stop + 1
    end

    window_state = Ref(0)
    for (index, range) in enumerate(lines)
        index > 13 && return PipelineError("PARAM_INVALID", 0, range[1], -1)
        line = String(bytes[range[1] + 1:range[2] + 1])
        validate_param_line(line, index - 1, window_state) ||
            return PipelineError("PARAM_INVALID", 0, range[1], -1)
    end
    length(lines) == 13 || return PipelineError("PARAM_INVALID", 0, n, -1)

    slice(i) = String(bytes[lines[i][1] + 1:lines[i][2] + 1])
    PipelineParams(
        Int(parse_nonnegative(flat_value(slice(3), "window_size"))),
        Int(parse_nonnegative(flat_value(slice(4), "stride"))),
        Int(parse_nonnegative(flat_value(slice(6), "k_max"))),
        Int(parse_nonnegative(flat_value(slice(7), "min_kmer_effective_count"))),
        flat_value(slice(13), "parameters_sha256"),
    )
end

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

"""
Enumerate the canonical k-mers of a window as strings, independently of the
Sounio base-4 encoding. Spans containing a non-canonical IUPAC symbol are
omitted (masked policy); they are never coerced to a canonical base, so a
masked k-mer never crosses an ambiguous symbol.
"""
function valid_kmers(window::Vector{Int}, k::Int)
    kmers = String[]
    for start in 1:(length(window) - k + 1)
        span = window[start:start + k - 1]
        all(base -> 0 <= base <= 3, span) || continue
        push!(kmers, join(DNA_BASES[base + 1] for base in span))
    end
    return kmers
end

"""
Orbit-paired k-mer imbalance for a transform T (an involution), following
specification 0.1.0 §7.2: unordered pairs {u,T(u)}, self-transformed k-mers
contribute zero to the numerator and their count once to the denominator. The
orbit representative is min(u, T(u)) over the union of observed k-mers and
their transforms, so zero-count partners are enumerated exactly once. An
unavailable combination (below the configured minimum effective count) is
never zero-filled.
"""
function kmer_imbalance(kmers::Vector{String}, transform, min_effective::Int)
    effective = length(kmers)
    effective >= min_effective ||
        return (effective=effective, available=false, numerator=0, denominator=0)

    counts = Dict{String, Int}()
    for u in kmers
        all(c -> c in ('A', 'C', 'G', 'T'), u) || error(
            "invariant violated: masked k-mer $u contains a non-canonical base",
        )
        counts[u] = get(counts, u, 0) + 1
    end

    candidates = Set{String}()
    for u in keys(counts)
        v = transform(u)
        transform(v) == u || error(
            "invariant violated: transform is not an involution at $u",
        )
        push!(candidates, u)
        push!(candidates, v)
    end

    numerator = 0
    denominator = 0
    for u in candidates
        v = transform(u)
        u == min(u, v) || continue
        if u == v
            denominator += counts[u]
        else
            left = get(counts, u, 0)
            right = get(counts, v, 0)
            numerator += abs(left - right)
            denominator += left + right
        end
    end
    return (effective=effective, available=denominator > 0,
            numerator=numerator, denominator=denominator)
end

reverse_transform(u::String) = reverse(u)
rc_transform(u::String) = String(reverse(map(c -> DNA_COMPLEMENT[c], collect(u))))

"""Append the masked k-mer fields for k = 1..8 in exact Sounio order, with
explicit unavailable reasons, and assert the specification invariants on the
independent recomputation."""
function print_kmer_fields(io::IOBuffer, window::Vector{Int}, params::PipelineParams)
    print(io, ",\"kmer_ambiguity_policy\":\"masked\",\"kmer_min_effective_count\":",
        params.min_kmer_effective_count)
    for k in 1:KMER_ABS_MAX_K
        print(io, ",\"kmer_", k, "_effective_count\":")
        if k > params.k_max
            # Outside the configured range: nothing was computed, null
            # everywhere, never zero-filled.
            print(io, "null,\"kmer_", k, "_unavailable_reason\":\"K_OUT_OF_CONFIGURED_RANGE\"")
            for prefix in ("reverse", "rc")
                print(io, ",\"", prefix, "_kmer_imbalance_", k, "_numerator\":null")
                print(io, ",\"", prefix, "_kmer_imbalance_", k, "_denominator\":null")
                print(io, ",\"", prefix, "_kmer_imbalance_", k, "\":null")
            end
            continue
        end

        kmers = valid_kmers(window, k)
        reverse_metric = kmer_imbalance(kmers, reverse_transform, params.min_kmer_effective_count)
        rc_metric = kmer_imbalance(kmers, rc_transform, params.min_kmer_effective_count)

        for (label, metric) in (("reverse", reverse_metric), ("rc", rc_metric))
            if metric.available
                metric.denominator == metric.effective || error(
                    "invariant violated at k=$k ($label): denominator $(metric.denominator) " *
                    "!= effective_count $(metric.effective)",
                )
                0 <= metric.numerator <= metric.denominator || error(
                    "invariant violated at k=$k ($label): ratio outside [0,1]",
                )
            else
                metric.effective < params.min_kmer_effective_count || error(
                    "invariant violated at k=$k ($label): unavailable metric with " *
                    "$(metric.effective) valid k-mers",
                )
            end
        end
        if reverse_metric.available && k == 1
            reverse_metric.numerator == 0 || error(
                "invariant violated: reverse_kmer_imbalance_1_numerator must be 0",
            )
        end

        print(io, reverse_metric.effective, ",\"kmer_", k, "_unavailable_reason\":")
        if !reverse_metric.available
            print(io, "\"INSUFFICIENT_EFFECTIVE_KMERS\"")
        else
            print(io, "null")
        end
        for (prefix, metric) in (("reverse", reverse_metric), ("rc", rc_metric))
            print(io, ",\"", prefix, "_kmer_imbalance_", k, "_numerator\":",
                metric.available ? string(metric.numerator) : "null")
            print(io, ",\"", prefix, "_kmer_imbalance_", k, "_denominator\":",
                metric.available ? string(metric.denominator) : "null")
            print(io, ",\"", prefix, "_kmer_imbalance_", k, "\":",
                metric.available ? format_ratio(metric.numerator, metric.denominator) : "null")
        end
    end
end

"""Build one JSONL line with the exact Sounio field order and formatting."""
function emit_window(row::MetadataRow, record_index::Int, window_index::Int,
                     window_start::Int, window::Vector{Int}, params::PipelineParams)
    window_length = length(window)
    window_end = window_start + window_length
    partial = window_length < params.window_size
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
        "\",\"parameters_sha256\":\"", params.sha256,
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
    print_kmer_fields(io, window, params)
    print(io, "}")
    return String(take!(io))
end

"""
Replicate the Sounio --pipeline driver: stream the FASTA bytes, associate
each record with its metadata row, and either emit every JSONL line or return
the first PipelineError with Sounio's precedence. Returns (lines, error).
"""
function simulate_pipeline(fasta::Vector{UInt8}, rows::Vector{MetadataRow}, params::PipelineParams)
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
            push!(lines, emit_window(rows[record_index], record_index, window_count, window_start, window, params))
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
        if length(window) == params.window_size
            push!(lines, emit_window(rows[record_index], record_index, window_count, window_start, window, params))
            window_start += params.window_size
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
    params = Dict{String, Dict{String, String}}()
    artifacts = Dict{String, String}()
    artifact_lines = Dict{String, Int}()
    artifact_shas = Dict{String, String}()
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
        elseif startswith(line, "DOSA_PIPELINE_PARAMS ")
            fields = parse_fields(line)
            name = fields["name"]
            haskey(params, name) && error("duplicate parameter announcement: $name")
            params[name] = fields
        elseif startswith(line, "sounio_pipeline_jsonl_")
            rest = split(line, '='; limit=2)
            key, value = rest[1], rest[2]
            if (m = match(r"^sounio_pipeline_jsonl_artifact_(.+)$", key)) !== nothing
                artifacts[m.captures[1]] = value
            elseif key == "sounio_pipeline_jsonl_artifact"
                artifacts["main"] = value
            elseif (m = match(r"^sounio_pipeline_jsonl_lines_(.+)$", key)) !== nothing
                artifact_lines[m.captures[1]] = parse(Int, value)
            elseif key == "sounio_pipeline_jsonl_lines"
                artifact_lines["main"] = parse(Int, value)
            elseif (m = match(r"^sounio_pipeline_jsonl_sha256_(.+)$", key)) !== nothing
                artifact_shas[m.captures[1]] = value
            elseif key == "sounio_pipeline_jsonl_sha256"
                artifact_shas["main"] = value
            end
        end
    end
    return cases, params, artifacts, artifact_lines, artifact_shas
end

observed, announced_params, artifacts, artifact_lines, artifact_shas =
    parse_runner_log(LOG_PATH)
Set(keys(observed)) == Set(spec.name for spec in CASE_SPECS) || error(
    "unexpected mini-pipeline case set: $(sort!(collect(keys(observed))))",
)
Set(keys(announced_params)) == Set(spec.params for spec in CASE_SPECS) || error(
    "runner did not announce exactly the expected parameter set: " *
    "$(sort!(collect(keys(announced_params))))",
)

# Load and independently validate every announced flat parameter file once.
case_params = Dict{String, Any}()
for (name, fields) in announced_params
    flat_path = fields["flat"]
    isfile(flat_path) || error("announced flat parameter file is missing: $flat_path")
    result = load_parameters(String(read(flat_path)))
    if result isa PipelineParams
        # The runner-announced canonical JSON sha256 must equal the sha256
        # bound into the rendered flat file it produced.
        result.sha256 == fields["sha256"] || error(
            "parameter sha256 divergence for $name: flat binds $(result.sha256) " *
            "but runner announced $(fields["sha256"])",
        )
    end
    case_params[name] = result
end

validated_windows = Ref(0)

for spec in CASE_SPECS
    case = observed[spec.name]
    case["expected_rc"] == spec.rc || error("runner expectation drift for $(spec.name)")
    case["actual_rc"] == spec.rc || error("Sounio exit mismatch for $(spec.name)")

    params_or_error = case_params[spec.params]

    if spec.rc == 11
        # Parameter-negative case: Julia must independently derive the same
        # PARAM_INVALID offset from the rendered flat bytes.
        params_or_error isa PipelineError || error(
            "Julia independently accepted the flat parameters for $(spec.name)",
        )
        params_or_error.code == "PARAM_INVALID" || error(
            "Julia derived a non-parameter error for $(spec.name)",
        )
        observed_error = case["error"]
        isnothing(observed_error) && error("missing Sounio error for $(spec.name)")
        observed_error["code"] == params_or_error.code || error(
            "error code mismatch for $(spec.name): Sounio=$(observed_error["code"]) Julia=$(params_or_error.code)",
        )
        observed_error["record"] == string(params_or_error.record) || error(
            "error record mismatch for $(spec.name): Sounio=$(observed_error["record"]) Julia=$(params_or_error.record)",
        )
        observed_error["offset"] == string(params_or_error.offset) || error(
            "error offset mismatch for $(spec.name): Sounio=$(observed_error["offset"]) Julia=$(params_or_error.offset)",
        )
        observed_error["byte"] == string(params_or_error.byte) || error(
            "error byte mismatch for $(spec.name): Sounio=$(observed_error["byte"]) Julia=$(params_or_error.byte)",
        )
        continue
    end

    params_or_error isa PipelineParams || error(
        "Julia independently rejected the flat parameters for valid case $(spec.name): " *
        "$(params_or_error)",
    )
    params = params_or_error

    metadata_text = String(read(joinpath(FIXTURE_DIRECTORY, spec.metadata)))
    fasta_bytes = read(joinpath(FIXTURE_DIRECTORY, spec.fasta))

    rows_or_error = load_metadata(metadata_text)
    if rows_or_error isa PipelineError
        expected = rows_or_error
        expected_lines = String[]
    else
        expected_lines, error_or_nothing = simulate_pipeline(fasta_bytes, rows_or_error, params)
        expected = error_or_nothing
    end

    if spec.rc == 0
        isnothing(expected) || error(
            "Julia independently derived an error for $(spec.name): $(expected)",
        )
        isnothing(case["error"]) || error("unexpected Sounio error for $(spec.name)")

        artifact_path = get(artifacts, spec.name, nothing)
        isnothing(artifact_path) && error("runner log does not name a JSONL artifact for $(spec.name)")
        isfile(artifact_path) || error("persisted JSONL artifact is missing: $artifact_path")
        artifact_sha = get(artifact_shas, spec.name, nothing)
        isnothing(artifact_sha) && error("runner log does not hash the JSONL artifact for $(spec.name)")
        match(r"^[0-9a-f]{64}$", artifact_sha) !== nothing ||
            error("malformed artifact sha256 in runner log for $(spec.name)")
        haskey(artifact_lines, spec.name) ||
            error("runner log does not count the JSONL lines for $(spec.name)")

        expected_bytes = join(expected_lines, "\n") * "\n"
        actual_bytes = String(read(artifact_path))
        actual_bytes == expected_bytes || error(
            "JSONL mismatch for $(spec.name): persisted Sounio artifact differs from the " *
            "independent Julia recomputation (byte-exact comparison)",
        )
        artifact_lines[spec.name] == length(expected_lines) ||
            error("runner JSONL line count mismatch for $(spec.name)")
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
