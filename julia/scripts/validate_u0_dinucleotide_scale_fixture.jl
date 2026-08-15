#!/usr/bin/env julia

"""
Independent Base-only differential validator for the U0 dinucleotide scale
fixture.

This is deliberately a bounded engineering fixture, not a U0 pilot validator.
It independently parses four synthetic canonical windows (16, 100, 500 and
1000 bases), re-derives each SHA-256-domain-separated seed, and regenerates
all 1000 `euler_wilson_fixed_endpoints_v1` draws per case.  It uses Julia
vectors and dictionaries rather than the fixed arrays used by the Sounio
fixture, C++ reference, HIP kernel, or HLS kernel.  Every persisted Sounio
JSONL line must equal the independently reconstructed line byte for byte.

Each regenerated draw is also checked for the defining invariants: length,
fixed first/last base, mononucleotide counts, and all sixteen directed
dinucleotide counts.  The program has no package dependencies, never invokes
Sounio, and never accepts a partial replicate set.

usage:
  validate_u0_dinucleotide_scale_fixture.jl <parameters.json> <cases.tsv> <sounio.jsonl>
"""

using SHA

const SCALES = (16, 100, 500, 1000)
const REPLICATES = 1000
const M1 = Int64(2_147_483_563)
const M2 = Int64(2_147_483_399)
const A1 = Int64(40_014)
const A2 = Int64(40_692)
const JUMP1 = Int64(993_186_111)
const JUMP2 = Int64(1_744_472_178)
const BASE_TO_CODE = Dict('A' => 0, 'C' => 1, 'G' => 2, 'T' => 3)
const CODE_TO_BASE = ('A', 'C', 'G', 'T')
const CASE_HEADER = "case_id\tparameters_sha256\taccession_version\twindow_start\tscale\tseed64\tbases\treplicates"

powermod(A1, 2^20, M1) == JUMP1 || error("U0_SCALE_VALIDATION_FAIL: first substream jump constant drift")
powermod(A2, 2^20, M2) == JUMP2 || error("U0_SCALE_VALIDATION_FAIL: second substream jump constant drift")

fail(message) = error("U0_SCALE_VALIDATION_FAIL: " * message)

mutable struct CombinedRng
    first::Int64
    second::Int64
end

function rng_step!(rng::CombinedRng)::Int64
    rng.first = mod(A1 * rng.first, M1)
    rng.second = mod(A2 * rng.second, M2)
    value = rng.first - rng.second
    value < 1 && (value += M1 - 1)
    return value - 1
end

function bounded!(rng::CombinedRng, bound::Int)::Int
    bound >= 1 || fail("non-positive RNG bound")
    bound == 1 && return 0
    range = M1 - 1
    limit = range - mod(range, bound)
    while true
        value = rng_step!(rng)
        value < limit && return Int(mod(value, bound))
    end
end

"""Derive replicate r directly from the seed and the verified 2^20 jump."""
function replicate_rng(seed64::String, replicate::Int)::CombinedRng
    occursin(r"^[0-9a-f]{16}$", seed64) || fail("malformed seed64")
    1 <= replicate <= REPLICATES || fail("replicate outside 1:$REPLICATES")
    high = parse(UInt64, seed64[1:8]; base=16)
    low = parse(UInt64, seed64[9:16]; base=16)
    first = Int64(1 + mod(high, UInt64(M1 - 1)))
    second = Int64(1 + mod(low, UInt64(M2 - 1)))
    # This loop is intentionally simple and independent of any accelerator
    # jump-ROM implementation.  Its result is the r-th 2^20-separated stream.
    for _ in 2:replicate
        first = mod(first * JUMP1, M1)
        second = mod(second * JUMP2, M2)
    end
    CombinedRng(first, second)
end

function parse_nonnegative_decimal(raw::AbstractString, name::String)::Int
    # `isdigit` accepts Unicode numerals; the Sounio grammar is explicitly
    # byte-ASCII decimal, so accepting (for example) a full-width digit here
    # would create a false Julia/Sounio agreement.
    !isempty(raw) && all(c -> '0' <= c <= '9', raw) ||
        fail("$name is not an ASCII unsigned decimal")
    value = tryparse(Int, raw)
    isnothing(value) && fail("$name overflows Int")
    value
end

function parse_positive_decimal(raw::AbstractString, name::String)::Int
    value = parse_nonnegative_decimal(raw, name)
    value > 0 || fail("$name is not positive")
    value
end

function valid_identifier(raw::AbstractString)::Bool
    !isempty(raw) && all(c -> isascii(c) && (isletter(c) || isdigit(c) || c in ('_', '-', '.')), raw)
end

function parse_cases(parameters_path::String, cases_path::String)
    isfile(parameters_path) || fail("canonical parameters JSON is missing")
    isfile(cases_path) || fail("case TSV is missing")
    parameter_sha = bytes2hex(sha256(read(parameters_path)))
    text = read(cases_path, String)
    endswith(text, "\n") || fail("case TSV must end in LF")
    occursin('\r', text) && fail("case TSV must use LF")
    lines = split(chop(text), '\n'; keepempty=true)
    !isempty(lines) && lines[1] == CASE_HEADER || fail("case TSV header drift")
    length(lines) == length(SCALES) + 1 || fail("case TSV must contain exactly four cases")
    cases = NamedTuple[]
    seen_case = Set{String}()
    seen_coordinate = Set{Tuple{String,Int}}()
    for (ordinal, line) in enumerate(lines[2:end])
        isempty(line) && fail("blank case line $(ordinal + 1)")
        fields = String.(split(line, '\t'; keepempty=true))
        length(fields) == 8 || fail("field count at case line $(ordinal + 1)")
        case_id, declared_sha, accession, start_raw, scale_raw, seed64, bases, replicates_raw = fields
        case_id == "scale_$(SCALES[ordinal])" || fail("case ID/order at line $(ordinal + 1)")
        valid_identifier(case_id) || fail("unsafe case ID at line $(ordinal + 1)")
        valid_identifier(accession) || fail("unsafe accession at line $(ordinal + 1)")
        declared_sha == parameter_sha || fail("parameters SHA-256 mismatch for $case_id")
        scale = parse_positive_decimal(scale_raw, "$case_id scale")
        scale == SCALES[ordinal] || fail("scale/order mismatch for $case_id")
        window_start = parse_nonnegative_decimal(start_raw, "$case_id window start")
        expected_seed = bytes2hex(sha256("$parameter_sha:$accession:$window_start"))[1:16]
        seed64 == expected_seed || fail("seed derivation mismatch for $case_id")
        occursin(r"^[ACGT]+$", bases) || fail("non-canonical bases for $case_id")
        ncodeunits(bases) == scale || fail("base length/scale mismatch for $case_id")
        parse_positive_decimal(replicates_raw, "$case_id replicates") == REPLICATES ||
            fail("replicate count mismatch for $case_id")
        case_id in seen_case && fail("duplicate case ID $case_id")
        coordinate = (accession, window_start)
        coordinate in seen_coordinate && fail("duplicate accession/window coordinate $coordinate")
        push!(seen_case, case_id)
        push!(seen_coordinate, coordinate)
        push!(cases, (; case_id, parameter_sha, accession, window_start, scale, seed64, bases))
    end
    cases
end

function mononucleotide_counts(sequence::Vector{Char})
    counts = zeros(Int, 4)
    for base in sequence
        code = get(BASE_TO_CODE, base, -1)
        code >= 0 || fail("noncanonical base in internal draw")
        counts[code + 1] += 1
    end
    counts
end

function dinucleotide_counts(sequence::Vector{Char})
    counts = zeros(Int, 4, 4)
    for i in 1:(length(sequence) - 1)
        source = get(BASE_TO_CODE, sequence[i], -1)
        destination = get(BASE_TO_CODE, sequence[i + 1], -1)
        source >= 0 && destination >= 0 || fail("noncanonical dinucleotide in internal draw")
        counts[source + 1, destination + 1] += 1
    end
    counts
end

"""
Independent vector/dictionary implementation of the fixed-endpoint directed
Euler/Wilson draw.  Parallel edges keep their individual position IDs; this
is essential because Wilson and the outgoing-order shuffle consume them as
distinct edges even when their endpoints coincide.
"""
function shuffled_sequence(original::String, seed64::String, replicate::Int)::String
    labels = collect(original)
    length(labels) >= 2 || fail("Euler/Wilson draw requires at least two bases")
    vertices = Int[get(BASE_TO_CODE, base, -1) for base in labels]
    all(>=(0), vertices) || fail("noncanonical input to Euler/Wilson draw")
    edge_count = length(vertices) - 1
    sources = vertices[1:end-1]
    destinations = vertices[2:end]
    outgoing = Dict(vertex => Int[] for vertex in 0:3)
    active = Set{Int}()
    for edge in 1:edge_count
        push!(outgoing[sources[edge]], edge)
        push!(active, sources[edge])
        push!(active, destinations[edge])
    end
    root = vertices[end]
    rng = replicate_rng(seed64, replicate)

    in_tree = Set(vertex for vertex in 0:3 if !(vertex in active))
    push!(in_tree, root)
    tree_edge = Dict{Int, Int}()
    for start in 0:3
        next_edge = Dict{Int, Int}()
        current = start
        steps = 0
        while !(current in in_tree)
            choices = outgoing[current]
            isempty(choices) && fail("non-Eulerian active vertex $current")
            chosen = choices[bounded!(rng, length(choices)) + 1]
            next_edge[current] = chosen
            current = destinations[chosen]
            steps += 1
            steps <= 4096 || fail("Wilson loop-erased walk exceeded safety bound")
        end
        current = start
        while !(current in in_tree)
            chosen = get(next_edge, current, 0)
            chosen != 0 || fail("Wilson tree edge missing")
            push!(in_tree, current)
            tree_edge[current] = chosen
            current = destinations[chosen]
        end
    end

    ordered = Dict(vertex => copy(outgoing[vertex]) for vertex in 0:3)
    for vertex in 0:3
        edges = ordered[vertex]
        for position in length(edges):-1:2
            other = bounded!(rng, position) + 1
            edges[position], edges[other] = edges[other], edges[position]
        end
        if vertex != root && vertex in active
            edge = get(tree_edge, vertex, 0)
            edge != 0 || fail("active non-root vertex lacks Wilson tree edge")
            at = findfirst(==(edge), edges)
            isnothing(at) && fail("Wilson tree edge absent from outgoing order")
            edges[at], edges[end] = edges[end], edges[at]
        end
    end

    cursor = Dict(vertex => 1 for vertex in 0:3)
    current = vertices[1]
    output = Vector{Char}(undef, length(vertices))
    output[1] = CODE_TO_BASE[current + 1]
    for output_index in 2:length(output)
        at = cursor[current]
        at <= length(ordered[current]) || fail("Euler trail exhausted early")
        edge = ordered[current][at]
        cursor[current] = at + 1
        current = destinations[edge]
        output[output_index] = CODE_TO_BASE[current + 1]
    end
    current == root || fail("Euler trail terminal base drift")
    String(output)
end

function expected_line(case, replicate::Int, draw::String)::String
    # This property order is part of u0_work_shard_executor.sio's
    # fixture protocol.  Keep this serializer intentionally explicit rather
    # than accepting semantically equivalent JSON.
    "{\"case_id\":\"$(case.case_id)\",\"scale\":$(case.scale),\"replicate\":$replicate,\"seed64\":\"$(case.seed64)\",\"sequence\":\"$draw\"}"
end

function validate_case(case, io::IO)::Int
    input = collect(case.bases)
    input_mono = mononucleotide_counts(input)
    input_dinuc = dinucleotide_counts(input)
    distinct = Set{String}()
    for replicate in 1:REPLICATES
        eof(io) && fail("artifact ended before $(case.case_id) replicate $replicate")
        actual = readline(io)
        draw = shuffled_sequence(case.bases, case.seed64, replicate)
        ncodeunits(draw) == case.scale || fail("draw length drift for $(case.case_id) replicate $replicate")
        chars = collect(draw)
        first(chars) == first(input) || fail("first endpoint drift for $(case.case_id) replicate $replicate")
        last(chars) == last(input) || fail("last endpoint drift for $(case.case_id) replicate $replicate")
        mononucleotide_counts(chars) == input_mono || fail("mononucleotide drift for $(case.case_id) replicate $replicate")
        dinucleotide_counts(chars) == input_dinuc || fail("dinucleotide drift for $(case.case_id) replicate $replicate")
        expected = expected_line(case, replicate, draw)
        actual == expected || fail("JSONL byte mismatch for $(case.case_id) replicate $replicate")
        push!(distinct, draw)
    end
    length(distinct)
end

function main(args)
    length(args) == 3 || begin
        println(stderr, "usage: validate_u0_dinucleotide_scale_fixture.jl <parameters.json> <cases.tsv> <sounio.jsonl>")
        exit(2)
    end
    parameters_path, cases_path, artifact_path = args
    isfile(artifact_path) || fail("Sounio JSONL artifact is missing")
    filesize(artifact_path) > 0 || fail("Sounio JSONL artifact is empty")
    open(artifact_path, "r") do io
        seek(io, filesize(artifact_path) - 1)
        read(io, UInt8) == 0x0a || fail("Sounio JSONL artifact must end in LF")
    end
    cases = parse_cases(parameters_path, cases_path)
    distinct_draws = 0
    open(artifact_path, "r") do io
        for case in cases
            distinct_draws += validate_case(case, io)
        end
        eof(io) || fail("artifact contains an unexpected extra JSONL line")
    end
    println("U0_DINUCLEOTIDE_SCALE_JULIA_DIFFERENTIAL_PASS cases=$(length(cases)) scales=16,100,500,1000 replicates=$REPLICATES draws=$(length(cases) * REPLICATES) distinct_case_draws=$distinct_draws tolerance=0")
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
