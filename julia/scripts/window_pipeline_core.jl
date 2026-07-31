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
