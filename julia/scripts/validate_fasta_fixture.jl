#!/usr/bin/env julia

"""
Independent Base-only validator for the Sounio streaming FASTA fixture.

The validator parses the checked-in bytes itself, recomputes every per-record
IUPAC count and order-sensitive hash, and derives expected parser errors. It
does not load DarwinAtlas, the Sounio executable, or any external package.
"""

if length(ARGS) != 2
    println(stderr, "usage: validate_fasta_fixture.jl <sounio-output.log> <fixture-directory>")
    exit(2)
end

const OUTPUT_PATH = only(ARGS[1:1])
const FIXTURE_DIRECTORY = only(ARGS[2:2])
const CHUNK_BYTES = 17
const HASH_MODULUS = 1_000_000_007
const SYMBOL_NAMES = ["a", "c", "g", "t", "r", "y", "s", "w", "k", "m", "b", "d", "h", "v", "n"]

const IUPAC_INDEX = let mapping = Dict{UInt8, Int}()
    for (index, symbol) in enumerate(codeunits("ACGTRYSWKMBDHVN"))
        mapping[symbol] = index
        mapping[symbol + 0x20] = index
    end
    mapping
end

const CASE_SPECS = [
    (name="valid_multi_record", file="valid_multi_record.fa", rc=0),
    (name="invalid_symbol", file="invalid_symbol.fa", rc=6),
    (name="sequence_before_header", file="sequence_before_header.fa", rc=3),
    (name="empty_header", file="empty_header.fa", rc=4),
    (name="empty_sequence", file="empty_sequence.fa", rc=5),
    (name="no_records", file="no_records.fa", rc=7),
]

function error_result(code::String, rc::Int, record::Int, offset::Int, byte::Int, records)
    return (
        ok=false,
        rc=rc,
        records=records,
        error=Dict(
            "code" => code,
            "record" => string(record),
            "offset" => string(offset),
            "byte" => string(byte),
        ),
    )
end

function summarize_record(index::Int, sequence::Vector{Int})
    counts = zeros(Int, length(SYMBOL_NAMES))
    hash_mod = 0
    for symbol_index in sequence
        counts[symbol_index] += 1
        hash_mod = mod(hash_mod * 131 + symbol_index, HASH_MODULUS)
    end

    fields = Dict(
        "index" => string(index),
        "length" => string(length(sequence)),
        "canonical" => string(sum(@view counts[1:4])),
        "ambiguous" => string(sum(@view counts[5:15])),
        "hash_mod" => string(hash_mod),
    )
    for (name, count) in zip(SYMBOL_NAMES, counts)
        fields[name] = string(count)
    end
    return fields
end

function parse_reference(path::String)
    data = read(path)
    records = Vector{Dict{String, String}}()
    sequence = Int[]
    have_header = false
    in_header = false
    at_line_start = true
    header_nonspace = 0
    record_index = 0

    for (position, byte) in enumerate(data)
        offset = position - 1
        byte == 0x0d && continue

        if byte == 0x0a
            if in_header
                header_nonspace > 0 || return error_result(
                    "EMPTY_HEADER", 4, record_index, offset, Int(byte), records,
                )
                in_header = false
            end
            at_line_start = true
            continue
        end

        if at_line_start && byte == UInt8('>')
            if have_header
                isempty(sequence) && return error_result(
                    "EMPTY_SEQUENCE", 5, record_index, offset, Int(byte), records,
                )
                push!(records, summarize_record(record_index, sequence))
            end
            empty!(sequence)
            record_index += 1
            header_nonspace = 0
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
            continue
        end

        have_header || return error_result(
            "SEQUENCE_BEFORE_HEADER", 3, record_index, offset, Int(byte), records,
        )
        symbol_index = get(IUPAC_INDEX, byte, 0)
        symbol_index > 0 || return error_result(
            "INVALID_SYMBOL", 6, record_index, offset, Int(byte), records,
        )
        push!(sequence, symbol_index)
    end

    if in_header && header_nonspace <= 0
        return error_result("EMPTY_HEADER", 4, record_index, length(data), -1, records)
    end
    have_header || return error_result("NO_RECORDS", 7, 0, length(data), -1, records)
    isempty(sequence) && return error_result(
        "EMPTY_SEQUENCE", 5, record_index, length(data), -1, records,
    )
    push!(records, summarize_record(record_index, sequence))
    return (ok=true, rc=0, records=records, error=nothing)
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

function parse_sounio_output(path::String)
    cases = Dict{String, Dict{String, Any}}()
    current = nothing

    for line in eachline(path)
        if startswith(line, "DOSA_FASTA_CASE ")
            fields = parse_fields(line)
            name = fields["name"]
            haskey(cases, name) && error("duplicate Sounio FASTA case: $name")
            cases[name] = Dict{String, Any}(
                "expected_rc" => parse(Int, fields["expected_rc"]),
                "actual_rc" => parse(Int, fields["actual_rc"]),
                "records" => Vector{Dict{String, String}}(),
                "error" => nothing,
                "summary" => nothing,
            )
            current = name
        elseif startswith(line, "DOSA_FASTA_RECORD ")
            isnothing(current) && error("record appeared before a case marker")
            push!(cases[current]["records"], parse_fields(line))
        elseif startswith(line, "DOSA_FASTA_ERROR ")
            isnothing(current) && error("error appeared before a case marker")
            isnothing(cases[current]["error"]) || error("duplicate error for case $current")
            cases[current]["error"] = parse_fields(line)
        elseif startswith(line, "DOSA_SOUNIO_FASTA_STREAM_OK ")
            isnothing(current) && error("summary appeared before a case marker")
            isnothing(cases[current]["summary"]) || error("duplicate summary for case $current")
            cases[current]["summary"] = parse_fields(line)
        end
    end
    return cases
end

observed = parse_sounio_output(OUTPUT_PATH)
Set(keys(observed)) == Set(spec.name for spec in CASE_SPECS) || error(
    "unexpected Sounio FASTA case set: $(sort!(collect(keys(observed))))",
)

validated_records = Ref(0)
for spec in CASE_SPECS
    path = joinpath(FIXTURE_DIRECTORY, spec.file)
    expected = parse_reference(path)
    case = observed[spec.name]

    case["expected_rc"] == spec.rc || error("runner expectation drift for $(spec.name)")
    case["actual_rc"] == spec.rc || error("Sounio exit mismatch for $(spec.name)")
    expected.rc == spec.rc || error("Julia reference exit mismatch for $(spec.name)")

    if expected.ok
        isnothing(case["error"]) || error("unexpected Sounio error for $(spec.name)")
        case["records"] == expected.records || error(
            "record mismatch for $(spec.name): Sounio=$(case["records"]) Julia=$(expected.records)",
        )
        summary = case["summary"]
        isnothing(summary) && error("missing Sounio success summary for $(spec.name)")
        summary["records"] == string(length(expected.records)) || error("record total mismatch")
        summary["bytes"] == string(filesize(path)) || error("byte total mismatch")
        summary["chunk_bytes"] == string(CHUNK_BYTES) || error("chunk size mismatch")
        summary["chunks"] == string(cld(filesize(path), CHUNK_BYTES)) || error("chunk count mismatch")
        parse(Int, summary["chunks"]) > 1 || error("valid fixture did not cross a read boundary")
        validated_records[] += length(expected.records)
    else
        isempty(case["records"]) || error("unexpected completed records for $(spec.name)")
        isnothing(case["summary"]) || error("invalid case emitted a success summary")
        case["error"] == expected.error || error(
            "error mismatch for $(spec.name): Sounio=$(case["error"]) Julia=$(expected.error)",
        )
    end
end

println("DOSA_JULIA_FASTA_DIFFERENTIAL_OK")
println("validated_cases=$(length(CASE_SPECS)) validated_records=$(validated_records[]) tolerance=0")
