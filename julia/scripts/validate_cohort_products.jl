#!/usr/bin/env julia

"""
Independent Base-only validator for the engineering canonical products
(Fase E): cohort_assemblies, atlas_replicons, and excluded_records for the
frozen miniature cohort.

The validator re-reads the frozen cohort (manifest, replicons table, assembly
FASTAs), independently re-extracts every replicon record and byte-compares it
with the runner's extracted FASTA, recomputes length, canonical/ambiguous
base counts and the six-decimal GC fraction, rebuilds every atlas_replicons
line byte for byte, replays the window pass to rebuild every excluded_records
line byte for byte, and rebuilds cohort_assemblies.jsonl from the frozen
manifest with the fixed schema field order. Exact byte equality with the
persisted Sounio/orchestrator products is required.

SHA-256 bindings (input_sha256 of each extracted FASTA) are orchestration
values announced in the runner log; the independent integrity check here is
the byte-exact re-extraction from the frozen assembly files, which is
stronger than a hash echo. The validator loads no packages (Base only), does
not execute Sounio, and never falls back to producing the artifacts itself.
"""

if length(ARGS) != 3
    println(stderr, "usage: validate_cohort_products.jl <products.log> <cohort-directory> <work-directory>")
    exit(2)
end

const LOG_PATH = ARGS[1]
const COHORT_DIRECTORY = ARGS[2]
const WORK_DIRECTORY = ARGS[3]

const IUPAC_INDEX = let mapping = Dict{UInt8, Int}()
    for (index, symbol) in enumerate(codeunits("ACGTRYSWKMBDHVN"))
        mapping[symbol] = index - 1
        mapping[symbol + 0x20] = index - 1
    end
    mapping
end

struct RepliconSpec
    acc::String
    alias::String
    assembly::String
    fasta::String
    metadata::String
    fasta_sha256::String
end

function parse_log(path::String)
    replicons = RepliconSpec[]
    params_json = nothing
    flat = nothing
    artifacts = Dict{String, String}()
    for line in eachline(path)
        tokens = split(line)
        isempty(tokens) && continue
        if tokens[1] == "sounio_products_params"
            fields = Dict(split(t, '='; limit=2) for t in tokens[2:end])
            params_json = String(fields["json"])
        elseif tokens[1] == "DOSA_PRODUCTS_PARAMS_FLAT"
            fields = Dict(split(t, '='; limit=2) for t in tokens[2:end])
            flat = String(fields["flat"])
        elseif tokens[1] == "sounio_products_replicon"
            fields = Dict(split(t, '='; limit=2) for t in tokens[2:end])
            push!(replicons, RepliconSpec(
                fields["acc"], fields["alias"], fields["assembly"],
                fields["fasta"], fields["metadata"], fields["fasta_sha256"],
            ))
        elseif tokens[1] == "DOSA_PRODUCT_ARTIFACT"
            fields = Dict(split(t, '='; limit=2) for t in tokens[2:end])
            artifacts[fields["name"]] = fields["path"]
        end
    end
    isnothing(params_json) && error("products log does not announce the parameter JSON")
    isnothing(flat) && error("products log does not announce the flat parameters")
    length(replicons) == 4 || error("products log must announce exactly 4 replicons")
    for name in ("cohort_assemblies", "atlas_replicons", "excluded_records")
        haskey(artifacts, name) || error("products log does not name the $name artifact")
    end
    return replicons, flat, artifacts
end

function parse_flat(path::String)
    values = Dict{String, String}()
    for line in eachline(path)
        pair = split(line, '='; limit=2)
        length(pair) == 2 || error("malformed flat parameter line: $line")
        values[pair[1]] = pair[2]
    end
    window_size = parse(Int, values["window_size"])
    stride = parse(Int, values["stride"])
    k_max = parse(Int, values["k_max"])
    min_effective = parse(Int, values["min_kmer_effective_count"])
    stride == window_size || error("products validator requires stride == window_size")
    return (window_size=window_size, k_max=k_max, min_effective=min_effective)
end

function read_metadata(path::String)
    lines = readlines(path)
    length(lines) == 2 || error("per-replicon metadata must have header + 1 row: $path")
    fields = split(lines[2], '\t')
    length(fields) == 6 || error("metadata row must have 6 fields: $path")
    return (sequence=fields[2], assembly=fields[3], class=fields[4], topology=fields[5])
end

# Locate the single genomic FASTA inside an assembly directory of the frozen
# cohort and extract one record byte-exact (header included), exactly the
# bytes the runner's awk extraction produced.
function extract_record(assembly::String, acc::String)
    dir = joinpath(COHORT_DIRECTORY, "assemblies", assembly)
    fastas = filter(f -> endswith(f, ".fna"), readdir(dir))
    length(fastas) == 1 || error("expected exactly one .fna in $dir")
    bytes = read(joinpath(dir, fastas[1]))
    marker = codeunits(">" * acc * " ")
    record_start = 0
    i = 1
    while i <= length(bytes) - length(marker) + 1
        if bytes[i] == UInt8('>') && (i == 1 || bytes[i - 1] == UInt8('\n')) &&
           bytes[i:i + length(marker) - 1] == marker
            record_start = i
            break
        end
        i += 1
    end
    record_start > 0 || error("record $acc not found in $dir")
    j = record_start + 1
    record_end = length(bytes)
    while j <= length(bytes)
        if bytes[j] == UInt8('>') && bytes[j - 1] == UInt8('\n')
            record_end = j - 1
            break
        end
        j += 1
    end
    return bytes[record_start:record_end]
end

function sequence_of(record::Vector{UInt8})
    lines = split(String(record), '\n')
    seq = UInt8[]
    for (index, line) in enumerate(lines)
        index == 1 && continue  # header
        append!(seq, codeunits(line))
    end
    return seq
end

function six_decimal(numerator::Int, denominator::Int)
    scaled = (numerator * 1_000_000) ÷ denominator
    return string(scaled ÷ 1_000_000, ".", lpad(scaled % 1_000_000, 6, '0'))
end

function profile_line(meta, seq::Vector{UInt8}, fasta_sha256::String)
    counts = zeros(Int, 15)
    for ch in seq
        index = get(IUPAC_INDEX, ch, -1)
        index < 0 && error("non-IUPAC byte in sequence: $(Char(ch))")
        counts[index + 1] += 1
    end
    canonical = sum(counts[1:4])
    ambiguous = sum(counts[5:15])
    gc = counts[2] + counts[3]
    gc_fraction = canonical > 0 ? six_decimal(gc, canonical) : "null"
    return string(
        "{\"schema_version\":\"0.1.0\",\"specification_version\":\"0.1.0\",",
        "\"metric_version\":\"0.1.0\",\"sequence_accession_version\":\"", meta.sequence,
        "\",\"assembly_accession_version\":\"", meta.assembly,
        "\",\"replicon_class\":\"", meta.class,
        "\",\"declared_topology\":\"", meta.topology,
        "\",\"length_bp\":", length(seq),
        ",\"canonical_count\":", canonical,
        ",\"ambiguous_count\":", ambiguous,
        ",\"gc_fraction\":", gc_fraction,
        ",\"input_sha256\":\"", fasta_sha256,
        "\",\"included\":true,\"exclusion_reason\":null}",
    )
end

function exclusion_prefix(level::String, meta, window_start::Int, window_end::Int)
    return string(
        "{\"schema_version\":\"0.1.0\",\"specification_version\":\"0.1.0\",",
        "\"metric_version\":\"0.1.0\",\"exclusion_level\":\"", level,
        "\",\"sequence_accession_version\":\"", meta.sequence,
        "\",\"assembly_accession_version\":\"", meta.assembly,
        "\",\"window_start\":", window_start,
        ",\"window_end\":", window_end,
        ",\"metric\":\"",
    )
end

function replicon_exclusions(meta, seq::Vector{UInt8}, params)
    bases = map(ch -> get(IUPAC_INDEX, ch, -1), seq)
    for base in bases
        base < 0 && error("non-IUPAC byte in sequence")
    end
    lines = String[]
    n = length(bases)
    window_start = 0
    while window_start < n
        window_end = min(window_start + params.window_size, n)
        wlen = window_end - window_start
        partial = wlen < params.window_size
        canonical = true
        for i in (window_start + 1):window_end
            if bases[i] > 3
                canonical = false
                break
            end
        end
        if partial
            push!(lines, string(
                exclusion_prefix("window", meta, window_start, window_end),
                "positional\",\"reason_code\":\"PARTIAL_WINDOW\"}",
            ))
        elseif !canonical
            push!(lines, string(
                exclusion_prefix("window", meta, window_start, window_end),
                "positional\",\"reason_code\":\"AMBIGUOUS_WINDOW\"}",
            ))
        end
        for k in 1:8
            if k > params.k_max
                for transform in ("reverse_kmer_imbalance_", "rc_kmer_imbalance_")
                    push!(lines, string(
                        exclusion_prefix("metric", meta, window_start, window_end),
                        transform, k, "\",\"reason_code\":\"K_OUT_OF_CONFIGURED_RANGE\"}",
                    ))
                end
            else
                run = 0
                effective = 0
                for i in (window_start + 1):window_end
                    if bases[i] <= 3
                        run += 1
                        run >= k && (effective += 1)
                    else
                        run = 0
                    end
                end
                if effective < params.min_effective
                    for transform in ("reverse_kmer_imbalance_", "rc_kmer_imbalance_")
                        push!(lines, string(
                            exclusion_prefix("metric", meta, window_start, window_end),
                            transform, k, "\",\"reason_code\":\"INSUFFICIENT_EFFECTIVE_KMERS\"}",
                        ))
                    end
                end
            end
        end
        window_start = window_end
    end
    return lines
end

const COHORT_PRODUCT_ORDER = [
    "schema_version", "cohort", "assembly_accession_version", "taxid",
    "organism_name", "refseq_category", "assembly_level", "retrieval_utc",
    "datasets_version", "datasets_cli_sha256", "package_md5",
    "package_md5_scope", "download_package_sha256",
    "topology_package_sha256", "genomic_fna_sha256", "included",
]

# Tiny JSON value reader for the flat manifest rows (objects of string keys
# to string/integer/boolean values) and writer with the exact Ruby
# JSON.generate compact byte layout for the value types used here.
function parse_manifest_row(line::String)
    fields = Dict{String, Any}()
    body = strip(line)
    startswith(body, "{") && endswith(body, "}") || error("manifest row is not a JSON object")
    inner = body[2:end - 1]
    i = firstindex(inner)
    while i <= lastindex(inner)
        # key
        inner[i] == '"' || error("manifest parse: expected key quote")
        j = i + 1
        while inner[j] != '"'
            j += 1
        end
        key = inner[i + 1:j - 1]
        j += 1
        inner[j] == ':' || error("manifest parse: expected colon")
        j += 1
        if inner[j] == '"'
            k = j + 1
            value = IOBuffer()
            while inner[k] != '"'
                if inner[k] == '\\'
                    k += 1
                    c = inner[k]
                    print(value, c == 'u' ? Char(parse(Int, inner[k + 1:k + 4]; base=16)) : c)
                    c == 'u' && (k += 4)
                else
                    print(value, inner[k])
                end
                k += 1
            end
            fields[key] = String(take!(value))
            j = k + 1
        else
            k = j
            while k <= lastindex(inner) && inner[k] != ','
                k += 1
            end
            raw = inner[j:k - 1]
            if raw == "true"
                fields[key] = true
            elseif raw == "false"
                fields[key] = false
            else
                fields[key] = parse(Int, raw)
            end
            j = k
        end
        j <= lastindex(inner) && inner[j] == ',' && (j += 1)
        i = j
    end
    return fields
end

function json_compact(value)
    if value isa Bool
        return value ? "true" : "false"
    elseif value isa Integer
        return string(value)
    else
        out = IOBuffer()
        print(out, '"')
        for ch in value
            if ch == '"' || ch == '\\'
                print(out, '\\', ch)
            elseif ch < ' '
                print(out, "\\u", lpad(string(Int(ch); base=16), 4, '0'))
            else
                print(out, ch)
            end
        end
        print(out, '"')
        return String(take!(out))
    end
end

function expected_cohort_lines()
    manifest = joinpath(COHORT_DIRECTORY, "cohort_manifest.jsonl")
    rows = readlines(manifest)
    length(rows) == 2 || error("cohort manifest must have exactly 2 rows")
    lines = String[]
    for row in rows
        fields = parse_manifest_row(row)
        parts = String[]
        for key in COHORT_PRODUCT_ORDER
            haskey(fields, key) || error("cohort manifest missing key: $key")
            push!(parts, string(json_compact(key), ":", json_compact(fields[key])))
        end
        push!(lines, string("{", join(parts, ","), "}"))
    end
    return lines
end

replicons, flat_path, artifacts = parse_log(LOG_PATH)
params = parse_flat(flat_path)

# 1. cohort_assemblies: independent rebuild from the frozen manifest.
expected_cohort = expected_cohort_lines()
actual_cohort = readlines(artifacts["cohort_assemblies"])
actual_cohort == expected_cohort || error(
    "cohort_assemblies.jsonl differs from the independent manifest rebuild",
)

validated_replicons = Ref(0)

profile_lines = String[]
exclusion_lines = String[]
for spec in replicons
    record = extract_record(spec.assembly, spec.acc)
    runner_record = read(spec.fasta)
    record == runner_record || error(
        "extracted FASTA for $(spec.acc) differs from the frozen assembly bytes",
    )
    meta = read_metadata(spec.metadata)
    meta.sequence == spec.acc || error("metadata accession drift for $(spec.acc)")
    meta.assembly == spec.assembly || error("metadata assembly drift for $(spec.acc)")
    seq = sequence_of(record)
    push!(profile_lines, profile_line(meta, seq, spec.fasta_sha256))
    append!(exclusion_lines, replicon_exclusions(meta, seq, params))
    validated_replicons[] += 1
end

actual_profiles = readlines(artifacts["atlas_replicons"])
actual_profiles == profile_lines || error(
    "atlas_replicons.jsonl differs from the independent Julia recomputation " *
    "(byte-exact comparison)",
)

actual_exclusions = readlines(artifacts["excluded_records"])
actual_exclusions == exclusion_lines || error(
    "excluded_records.jsonl differs from the independent Julia recomputation " *
    "(byte-exact comparison)",
)
validated_exclusions = length(exclusion_lines)

println("DOSA_JULIA_COHORT_PRODUCTS_OK")
println("validated_products=3 validated_replicons=$(validated_replicons[]) " *
        "validated_exclusions=$validated_exclusions tolerance=0")
