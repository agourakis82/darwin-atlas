const SCHEMA_VERSION = "0.3.0"
const METRIC_VERSION = "0.1.0"
const HEADER_ID_BYTES = 256
const KMER_ABS_MAX_K = 8
const WINDOW_MAX_BYTES = 16

# Fixture null-model engine constants (mirror of the Sounio executable
# specification): LCG mod 2^31 with glibc constants, fixture replicate
# ceiling, and the metric index layout 0 = delta_R, 1 = delta_RC, then
# 2k = reverse / 2k+1 = rc k-mer imbalance for k = 1..8. Every quantity is
# exact non-negative integer arithmetic below 2^62; no floating point.
const NULL_LCG_MODULUS = 2_147_483_648
const NULL_LCG_MULTIPLIER = 1_103_515_245
const NULL_LCG_INCREMENT = 12_345
const NULL_MAX_REPLICATES = 1000
const NULL_SEED_DERIVATION = "lcg31_sha8_fixture_v1"
const DINUCLEOTIDE_SEED_DERIVATION = "sha256_parameters_accession_window_first64be_v1"

# Reuse the already independent, fixture-validated Julia graph
# representation of ADR-0003. Its guarded main does not run when included.
include(joinpath(@__DIR__, "validate_dinucleotide_null.jl"))

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
    null_model::String
    null_replicates::Int
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
        # The renderer always appends parameters_sha256 LAST: line 12 in the
        # 13-line form, line 14 in the 15-line form (lines 12/13 then carry
        # the null keys).
        value = flat_value(line, "parameters_sha256")
        (value !== nothing && match(r"^[0-9a-f]{64}$", value) !== nothing) && return true
        model = flat_value(line, "null_model")
        return model in ("none", "mononucleotide_shuffle", "dinucleotide_shuffle")
    elseif line_index == 13
        value = parse_nonnegative(something(flat_value(line, "null_replicates"), ""))
        return value >= 0 && value <= NULL_MAX_REPLICATES
    elseif line_index == 14
        value = flat_value(line, "parameters_sha256")
        return value !== nothing && match(r"^[0-9a-f]{64}$", value) !== nothing
    end
    return false
end

"""
Independently validate the rendered flat parameter bytes with Sounio's exact
semantics: CR stripped, empty lines skipped, at most 15 non-empty lines in
fixed order, error offset is the zero-based byte offset of the offending
line, and a wrong line count (anything but 13 or 15) or a null-model
cross-field violation fails at offset n (total byte count). Returns either a
PipelineParams or a PipelineError.
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
        index > 15 && return PipelineError("PARAM_INVALID", 0, range[1], -1)
        line = String(bytes[range[1] + 1:range[2] + 1])
        validate_param_line(line, index - 1, window_state) ||
            return PipelineError("PARAM_INVALID", 0, range[1], -1)
    end
    # Exactly 13 lines (null engine off) or exactly 15 lines (explicit
    # null_model/null_replicates); any other count fails at offset n.
    length(lines) in (13, 15) || return PipelineError("PARAM_INVALID", 0, n, -1)

    slice(i) = String(bytes[lines[i][1] + 1:lines[i][2] + 1])
    null_model = "none"
    null_replicates = 0
    sha256 = flat_value(slice(13), "parameters_sha256")
    if length(lines) == 15
        null_model = flat_value(slice(13), "null_model")
        null_replicates = Int(parse_nonnegative(flat_value(slice(14), "null_replicates")))
        sha256 = flat_value(slice(15), "parameters_sha256")
    end
    # Cross-field rule (mirror of the Sounio loader): none requires 0
    # replicates, the shuffle model requires at least one; violations fail at
    # offset n like the line-count rule.
    (null_model == "none" && null_replicates != 0) &&
        return PipelineError("PARAM_INVALID", 0, n, -1)
    (null_model == "mononucleotide_shuffle" && null_replicates < 1) &&
        return PipelineError("PARAM_INVALID", 0, n, -1)
    (null_model == "dinucleotide_shuffle" && null_replicates < 1) &&
        return PipelineError("PARAM_INVALID", 0, n, -1)

    PipelineParams(
        Int(parse_nonnegative(flat_value(slice(3), "window_size"))),
        Int(parse_nonnegative(flat_value(slice(4), "stride"))),
        Int(parse_nonnegative(flat_value(slice(6), "k_max"))),
        Int(parse_nonnegative(flat_value(slice(7), "min_kmer_effective_count"))),
        sha256,
        null_model,
        null_replicates,
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

# ---------------------------------------------------------------------------
# Fixture null-model engine (window schema 0.3.0; spec 0.1.0 section 9
# sensitivity null). Exact mirror of the Sounio executable specification:
# mononucleotide-preserving Fisher-Yates shuffle driven by an LCG mod 2^31
# (glibc constants), seeded per (parameter hash prefix, window_start,
# record_index, metric index, replicate). Summaries over the available
# replicate draws of the scaled integer ratios floor(x*1e6/den): floored
# mean, exact mean absolute deviation from the rational mean, and
# nearest-rank q025/q975. All integer arithmetic; no floating point. The
# ADR-0002 pilot null remains proposed and is not fixed here.
# ---------------------------------------------------------------------------

null_lcg_step(state::Int) = mod(state * NULL_LCG_MULTIPLIER + NULL_LCG_INCREMENT, NULL_LCG_MODULUS)

function null_seed_state(seed_base::Int, window_start::Int, record_index::Int,
                         metric_index::Int, replicate::Int)
    mod(seed_base + window_start * 1_000_003 + record_index * 1_000_033 +
        metric_index * 100_043 + replicate * 1_009, NULL_LCG_MODULUS)
end

function null_shuffle!(window::Vector{Int}, state::Int)
    for i in length(window):-1:2
        state = null_lcg_step(state)
        j = state % i + 1
        window[i], window[j] = window[j], window[i]
    end
    return state
end

"""One positional null draw over the shuffled window (metric 0 = delta_R,
1 = delta_RC): the scaled integer ratio floor(mismatches*1e6/length)."""
function null_positional_draw(window::Vector{Int}, metric_index::Int)
    mismatches = 0
    len = length(window)
    for i in 1:len
        opposite = window[len - i + 1]
        if metric_index == 0
            window[i] != opposite && (mismatches += 1)
        else
            window[i] != COMPLEMENT[opposite + 1] && (mismatches += 1)
        end
    end
    return div(mismatches * 1_000_000, len)
end

"""One k-mer null draw over the shuffled window; -1 when the draw is
unavailable (masked below the configured minimum effective count)."""
function null_kmer_draw(window::Vector{Int}, metric_index::Int, min_effective::Int)
    k = div(metric_index, 2)
    transform = isodd(metric_index) ? rc_transform : reverse_transform
    metric = kmer_imbalance(valid_kmers(window, k), transform, min_effective)
    metric.available || return -1
    return div(metric.numerator * 1_000_000, metric.denominator)
end

"""Available scaled draws for one metric over all configured replicates."""
function run_null_replicates(window::Vector{Int}, params::PipelineParams, seed_base::Int,
                             window_start::Int, record_index::Int, metric_index::Int)
    values = Int[]
    for replicate in 1:params.null_replicates
        state = null_seed_state(seed_base, window_start, record_index, metric_index, replicate)
        shuffled = copy(window)
        null_shuffle!(shuffled, state)
        scaled = metric_index < 2 ? null_positional_draw(shuffled, metric_index) :
            null_kmer_draw(shuffled, metric_index, params.min_kmer_effective_count)
        scaled >= 0 && push!(values, scaled)
    end
    return values
end

"""Parse and independently validate a frozen dinucleotide seed sidecar.
Every seed is recomputed from the canonical parameter hash, accession, and
window start; duplicate coordinates are rejected."""
function load_dinucleotide_seeds(path::String, parameters_sha::String)
    rows = readlines(path)
    isempty(rows) && error("empty dinucleotide seed sidecar")
    rows[1] == "sequence_accession_version\twindow_start\tseed64" ||
        error("dinucleotide seed header drift")
    seeds = Dict{Tuple{String,Int},String}()
    for row in rows[2:end]
        fields = split(row, '\t'; keepempty=true)
        length(fields) == 3 || error("dinucleotide seed field-count drift")
        accession, start_raw, seed64 = fields
        json_safe(accession) || error("unsafe dinucleotide seed accession")
        start = parse(Int, start_raw)
        start >= 0 || error("negative dinucleotide seed window start")
        expected = bytes2hex(sha256("$parameters_sha:$accession:$start"))[1:16]
        seed64 == expected || error("dinucleotide seed derivation drift at $accession:$start")
        key = (accession, start)
        haskey(seeds, key) && error("duplicate dinucleotide seed coordinate $key")
        seeds[key] = seed64
    end
    isempty(seeds) && error("dinucleotide seed sidecar has no data")
    seeds
end

function integer_window(sequence::AbstractString)
    mapping = Dict('A'=>0, 'C'=>1, 'G'=>2, 'T'=>3)
    [mapping[base] for base in sequence]
end

"""Available scaled draws for one metric under ADR-0003. The same
window/replicate sequence draw is reused for every metric; only the metric
projection changes."""
function run_dinucleotide_replicates(window::Vector{Int}, params::PipelineParams,
                                     accession::String, window_start::Int,
                                     metric_index::Int,
                                     seeds::Dict{Tuple{String,Int},String})
    seed64 = get(seeds, (accession, window_start), nothing)
    isnothing(seed64) && error("missing dinucleotide seed for $accession:$window_start")
    alphabet = ['A', 'C', 'G', 'T']
    original = String([alphabet[base + 1] for base in window])
    original_counts = dinucleotide_counts(original)
    values = Int[]
    for replicate in 1:params.null_replicates
        shuffled = shuffled_sequence(original, seed64, replicate)
        length(shuffled) == length(original) || error("dinucleotide draw length drift")
        first(shuffled) == first(original) || error("dinucleotide first endpoint drift")
        last(shuffled) == last(original) || error("dinucleotide last endpoint drift")
        dinucleotide_counts(shuffled) == original_counts || error("dinucleotide count drift")
        sort(collect(shuffled)) == sort(collect(original)) || error("mononucleotide count drift")
        draw = integer_window(shuffled)
        scaled = metric_index < 2 ? null_positional_draw(draw, metric_index) :
            null_kmer_draw(draw, metric_index, params.min_kmer_effective_count)
        scaled >= 0 && push!(values, scaled)
    end
    values
end

const NULL_METRIC_NAMES = let names = String["delta_R", "delta_RC"]
    for k in 1:KMER_ABS_MAX_K
        push!(names, "reverse_kmer_imbalance_$k", "rc_kmer_imbalance_$k")
    end
    names
end

format_scaled(scaled::Int) = format_ratio(scaled, 1_000_000)

"""Five null fields for a metric whose observed value is null (or when the
null engine is off): everything null, never zero-filled."""
function print_null_metric_unavailable(io::IOBuffer, metric_index::Int)
    name = NULL_METRIC_NAMES[metric_index + 1]
    print(io, ",\"", name, "_null_replicates_available\":null,\"", name,
        "_null_mean\":null,\"", name, "_null_mad\":null,\"", name,
        "_null_q025\":null,\"", name, "_null_q975\":null")
end

function print_null_metric_fields(io::IOBuffer, metric_index::Int, values::Vector{Int})
    name = NULL_METRIC_NAMES[metric_index + 1]
    available = length(values)
    print(io, ",\"", name, "_null_replicates_available\":", available,
        ",\"", name, "_null_mean\":")
    if available == 0
        print(io, "null,\"", name, "_null_mad\":null,\"", name,
            "_null_q025\":null,\"", name, "_null_q975\":null")
        return
    end
    sorted = sort(values)
    total = sum(sorted)
    mean = div(total, available)
    # Exact mean absolute deviation from the rational mean total/available:
    # sum(|available*x_i - total|) / available^2, all integer.
    mad = div(sum(x -> abs(available * x - total), sorted), available * available)
    q025 = sorted[div(25 * (available - 1), 100) + 1]
    q975 = sorted[div(975 * (available - 1), 1000) + 1]
    print(io, format_scaled(mean), ",\"", name, "_null_mad\":", format_scaled(mad),
        ",\"", name, "_null_q025\":", format_scaled(q025),
        ",\"", name, "_null_q975\":", format_scaled(q975))
end

"""Append the schema 0.3.0 null-model block (93 fields) in exact Sounio
order. Observed k-mer availability is decided by the effective count alone,
proven equivalent to the orbit denominator rule."""
function print_null_fields(io::IOBuffer, window::Vector{Int}, params::PipelineParams,
                           record_index::Int, window_start::Int, excluded::Bool,
                           accession::String,
                           dinucleotide_seeds::Dict{Tuple{String,Int},String})
    enabled = params.null_model in ("mononucleotide_shuffle", "dinucleotide_shuffle") &&
        params.null_replicates > 0
    if enabled
        print(io, ",\"null_model\":\"", params.null_model, "\",\"null_replicates\":",
            params.null_replicates, ",\"null_seed_derivation\":\"",
            params.null_model == "mononucleotide_shuffle" ? NULL_SEED_DERIVATION :
                DINUCLEOTIDE_SEED_DERIVATION, "\"")
        if params.null_model == "dinucleotide_shuffle" && excluded
            for metric_index in 0:17
                print_null_metric_unavailable(io, metric_index)
            end
            return
        end
        seed_base = parse(Int, params.sha256[1:8], base=16)
        values_for(metric_index) = params.null_model == "mononucleotide_shuffle" ?
            run_null_replicates(window, params, seed_base, window_start, record_index, metric_index) :
            run_dinucleotide_replicates(window, params, accession, window_start,
                                        metric_index, dinucleotide_seeds)
        for metric_index in 0:1
            if excluded
                print_null_metric_unavailable(io, metric_index)
            else
                print_null_metric_fields(io, metric_index, values_for(metric_index))
            end
        end
        for k in 1:KMER_ABS_MAX_K
            for complement in 0:1
                metric_index = 2 * k + complement
                effective = length(valid_kmers(window, k))
                if k > params.k_max || effective < params.min_kmer_effective_count
                    print_null_metric_unavailable(io, metric_index)
                else
                    print_null_metric_fields(io, metric_index, values_for(metric_index))
                end
            end
        end
        return
    end
    print(io, ",\"null_model\":null,\"null_replicates\":null,\"null_seed_derivation\":null")
    for metric_index in 0:17
        print_null_metric_unavailable(io, metric_index)
    end
end

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
                     window_start::Int, window::Vector{Int}, params::PipelineParams,
                     dinucleotide_seeds::Dict{Tuple{String,Int},String})
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
    print_null_fields(io, window, params, record_index, window_start, excluded,
                      row.sequence_accession_version, dinucleotide_seeds)
    print(io, "}")
    return String(take!(io))
end

"""
Replicate the Sounio --pipeline driver: stream the FASTA bytes, associate
each record with its metadata row, and either emit every JSONL line or return
the first PipelineError with Sounio's precedence. Returns (lines, error).
"""
function simulate_pipeline(fasta::Vector{UInt8}, rows::Vector{MetadataRow}, params::PipelineParams,
                           dinucleotide_seeds::Dict{Tuple{String,Int},String}=Dict{Tuple{String,Int},String}())
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
            push!(lines, emit_window(rows[record_index], record_index, window_count,
                                     window_start, window, params, dinucleotide_seeds))
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
            push!(lines, emit_window(rows[record_index], record_index, window_count,
                                     window_start, window, params, dinucleotide_seeds))
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
