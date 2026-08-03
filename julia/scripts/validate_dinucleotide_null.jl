#!/usr/bin/env julia

# Independent standard-library-only validator for the Fase L Sounio artifact.
# The graph is represented with Julia vectors/dictionaries, rather than the
# fixed-array layout used by Sounio and the U250 kernel.

using SHA

const REPLICATES = 8
const M1 = Int64(2_147_483_563)
const M2 = Int64(2_147_483_399)
const A1 = Int64(40_014)
const A2 = Int64(40_692)
const JUMP1 = Int64(993_186_111) # A1^(2^20) mod M1
const JUMP2 = Int64(1_744_472_178) # A2^(2^20) mod M2

powermod(A1, 2^20, M1) == JUMP1 || error("first substream jump constant drift")
powermod(A2, 2^20, M2) == JUMP2 || error("second substream jump constant drift")

mutable struct CombinedRng
    first::Int64
    second::Int64
end

function rng_step!(rng::CombinedRng)
    rng.first = mod(A1 * rng.first, M1)
    rng.second = mod(A2 * rng.second, M2)
    value = rng.first - rng.second
    value < 1 && (value += M1 - 1)
    value - 1
end

function bounded!(rng::CombinedRng, bound::Int)
    bound <= 1 && return 0
    range = M1 - 1
    limit = range - mod(range, bound)
    while true
        value = rng_step!(rng)
        value < limit && return Int(mod(value, bound))
    end
end

function replicate_rng(seed64::AbstractString, replicate::Int)
    length(seed64) == 16 || error("seed64 length drift")
    high = parse(UInt64, seed64[1:8]; base=16)
    low = parse(UInt64, seed64[9:16]; base=16)
    first = Int64(1 + mod(high, UInt64(M1 - 1)))
    second = Int64(1 + mod(low, UInt64(M2 - 1)))
    for _ in 2:replicate
        first = mod(first * JUMP1, M1)
        second = mod(second * JUMP2, M2)
    end
    CombinedRng(first, second)
end

function parse_cases(parameters_path::String, cases_path::String)
    parameter_sha = bytes2hex(sha256(read(parameters_path)))
    rows = readlines(cases_path)
    isempty(rows) && error("empty cases")
    rows[1] == "case_id\tparameters_sha256\taccession_version\twindow_start\tseed64\tbases" ||
        error("case header drift")
    cases = NamedTuple[]
    for row in rows[2:end]
        fields = split(row, '\t'; keepempty=true)
        length(fields) == 6 || error("case field count drift")
        case_id, recorded_sha, accession, window_start_raw, seed64, bases = fields
        recorded_sha == parameter_sha || error("parameter SHA drift for $case_id")
        window_start = parse(Int, window_start_raw)
        material = "$parameter_sha:$accession:$window_start"
        expected_seed = bytes2hex(sha256(material))[1:16]
        seed64 == expected_seed || error("seed derivation drift for $case_id")
        occursin(r"^[ACGT]{1,16}$", bases) || error("noncanonical case $case_id")
        push!(cases, (; case_id, accession, window_start, seed64, bases))
    end
    cases
end

function dinucleotide_counts(sequence::AbstractString)
    index = Dict('A'=>1, 'C'=>2, 'G'=>3, 'T'=>4)
    counts = zeros(Int, 4, 4)
    chars = collect(sequence)
    for i in 1:length(chars)-1
        counts[index[chars[i]], index[chars[i + 1]]] += 1
    end
    counts
end

function shuffled_sequence(original::AbstractString, seed64::AbstractString, replicate::Int)
    vertices = Dict('A'=>0, 'C'=>1, 'G'=>2, 'T'=>3)
    labels = collect(original)
    edges = [(id=i - 1, src=vertices[labels[i]], dst=vertices[labels[i + 1]])
             for i in 1:length(labels)-1]
    outgoing = Dict(v => Int[] for v in 0:3)
    active = Set{Int}()
    for edge in edges
        push!(outgoing[edge.src], edge.id)
        push!(active, edge.src)
        push!(active, edge.dst)
    end
    destination = Dict(edge.id => edge.dst for edge in edges)
    root = vertices[last(labels)]
    rng = replicate_rng(seed64, replicate)

    # Wilson's algorithm, storing the last edge selected from every visited
    # vertex. Revisiting a vertex overwrites that suffix and erases the loop.
    in_tree = Set(v for v in 0:3 if !(v in active))
    push!(in_tree, root)
    tree_edge = Dict{Int,Int}()
    for start in 0:3
        next_edge = Dict{Int,Int}()
        current = start
        safety = 0
        while !(current in in_tree)
            isempty(outgoing[current]) && error("non-Eulerian fixture graph")
            chosen = outgoing[current][bounded!(rng, length(outgoing[current])) + 1]
            next_edge[current] = chosen
            current = destination[chosen]
            safety += 1
            safety <= 4096 || error("Wilson safety bound")
        end
        current = start
        while !(current in in_tree)
            chosen = next_edge[current]
            push!(in_tree, current)
            tree_edge[current] = chosen
            current = destination[chosen]
        end
    end

    ordered = Dict(v => copy(outgoing[v]) for v in 0:3)
    for vertex in 0:3
        list = ordered[vertex]
        for i in length(list):-1:2
            j = bounded!(rng, i) + 1
            list[i], list[j] = list[j], list[i]
        end
        if vertex != root && vertex in active
            at = findfirst(==(tree_edge[vertex]), list)
            isnothing(at) && error("tree edge missing")
            list[at], list[end] = list[end], list[at]
        end
    end

    inverse = ['A', 'C', 'G', 'T']
    cursor = Dict(v => 1 for v in 0:3)
    current = vertices[first(labels)]
    output = Char[inverse[current + 1]]
    for _ in edges
        at = cursor[current]
        at <= length(ordered[current]) || error("Euler trail exhausted early")
        chosen = ordered[current][at]
        cursor[current] = at + 1
        current = destination[chosen]
        push!(output, inverse[current + 1])
    end
    current == root || error("Euler trail terminal drift")
    String(output)
end

function expected_lines(cases)
    lines = String[]
    distinct_draws = 0
    for case in cases
        observed = Set{String}()
        for replicate in 1:REPLICATES
            shuffled = shuffled_sequence(case.bases, case.seed64, replicate)
            length(shuffled) == length(case.bases) || error("length drift")
            first(shuffled) == first(case.bases) || error("first endpoint drift")
            last(shuffled) == last(case.bases) || error("last endpoint drift")
            dinucleotide_counts(shuffled) == dinucleotide_counts(case.bases) ||
                error("dinucleotide count drift")
            sort(collect(shuffled)) == sort(collect(case.bases)) || error("mononucleotide count drift")
            push!(observed, shuffled)
            push!(lines, "{\"case_id\":\"$(case.case_id)\",\"replicate\":$replicate," *
                         "\"seed64\":\"$(case.seed64)\",\"sequence\":\"$shuffled\"}")
        end
        distinct_draws += length(observed)
    end
    lines, distinct_draws
end

function main(args)
    length(args) == 3 || error("usage: validate_dinucleotide_null.jl <parameters.json> <cases.tsv> <sounio.jsonl>")
    cases = parse_cases(args[1], args[2])
    expected, distinct = expected_lines(cases)
    actual = readlines(args[3])
    length(actual) == length(expected) || error("line count mismatch: $(length(actual)) != $(length(expected))")
    for i in eachindex(expected)
        actual[i] == expected[i] || error("byte mismatch at line $i\nexpected=$(expected[i])\nactual=$(actual[i])")
    end
    println("DINUCLEOTIDE_JULIA_DIFFERENTIAL_PASS cases=$(length(cases)) replicates=$REPLICATES draws=$(length(expected)) distinct_case_draws=$distinct tolerance=0")
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
