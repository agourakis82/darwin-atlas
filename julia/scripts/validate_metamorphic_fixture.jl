#!/usr/bin/env julia

"""
Independent Base-only Julia oracle for the Sounio metamorphic fixture.

The implementation uses strings and Julia collection operations rather than
the fixed-array/base-code implementation in Sounio. It recomputes every
required property from the declared fixtures and compares exact persisted
integer observations at tolerance zero.
"""

if length(ARGS) != 1
    println(stderr, "usage: validate_metamorphic_fixture.jl <sounio-output.log>")
    exit(2)
end

const OBSERVATION_PATTERN = r"^DOSA_METAMORPHIC property=([a-z0-9_]+) lhs=([0-9]+) rhs=([0-9]+)$"
const COMPLEMENT = Dict('A' => 'T', 'C' => 'G', 'G' => 'C', 'T' => 'A')
const BASE4 = Dict('A' => 0, 'C' => 1, 'G' => 2, 'T' => 3)

complement(sequence::String) = String(collect(COMPLEMENT[base] for base in sequence))
reverse_complement(sequence::String) = complement(reverse(sequence))

function shift_left(sequence::String, steps::Int)::String
    isempty(sequence) && return sequence
    offset = mod(steps, length(sequence))
    offset == 0 && return sequence
    return sequence[(offset + 1):end] * sequence[1:offset]
end

function base4_code(sequence::String)::Int
    foldl((code, base) -> code * 4 + BASE4[base], sequence; init=0)
end

gc_count(sequence::String) = count(base -> base == 'G' || base == 'C', sequence)

function minimal_period(sequence::String)::Int
    for period in 1:length(sequence)
        length(sequence) % period == 0 || continue
        shift_left(sequence, period) == sequence && return period
    end
    return length(sequence)
end

function circular_canonical_code(sequence::String)::Int
    rc = reverse_complement(sequence)
    return minimum(
        base4_code(shift_left(strand, shift))
        for strand in (sequence, rc), shift in 0:(length(sequence) - 1)
    )
end

const RECORD_VALUES = Dict(11 => 37, 23 => 19, 47 => 53)

function canonical_sorted_output_digest(ids::Vector{Int})::Int
    digest = 0
    for id in sort(ids)
        digest = digest * 97 + id * 7 + RECORD_VALUES[id]
    end
    return digest
end

function record_content_digest(ids::Vector{Int})::Int
    sum((id * 31 + RECORD_VALUES[id] * 17) * (id + 11) for id in ids)
end

w = "ACGTACCA"
shifted = shift_left(w, 3)
rc = reverse_complement(w)
odd = "ACG"
tiled2 = "ACACACAC"
tiled4 = "ACGTACGT"

expected = Dict{String, Tuple{Int, Int}}(
    "reverse_involution" => (base4_code(reverse(reverse(w))), base4_code(w)),
    "complement_involution" => (base4_code(complement(complement(w))), base4_code(w)),
    "rc_involution" => (base4_code(reverse_complement(reverse_complement(w))), base4_code(w)),
    "reverse_complement_commutation" => (base4_code(reverse(complement(w))), base4_code(complement(reverse(w)))),
    "shift_cycle" => (base4_code(shift_left(w, length(w))), base4_code(w)),
    "rc_shift_conjugacy" => (base4_code(reverse_complement(shift_left(reverse_complement(w), 1))), base4_code(shift_left(w, -1))),
    "gc_rc" => (gc_count(w), gc_count(rc)),
    "circular_code_origin" => (circular_canonical_code(w), circular_canonical_code(shifted)),
    "circular_code_strand" => (circular_canonical_code(w), circular_canonical_code(rc)),
    "circular_gc_origin" => (gc_count(w), gc_count(shifted)),
    "circular_gc_strand" => (gc_count(w), gc_count(rc)),
    "circular_period_origin" => (minimal_period(w), minimal_period(shifted)),
    "circular_period_strand" => (minimal_period(w), minimal_period(rc)),
    "odd_not_rc_fixed" => (
        Int(any(base == COMPLEMENT[base] for base in keys(COMPLEMENT)) || odd == reverse_complement(odd)),
        0,
    ),
    "tiled_minimal_period_2" => (minimal_period(tiled2), 2),
    "tiled_minimal_period_4" => (minimal_period(tiled4), 4),
    "record_order_sorted_output" => (
        canonical_sorted_output_digest([11, 23, 47]),
        canonical_sorted_output_digest([47, 11, 23]),
    ),
    "record_order_content_digest" => (
        record_content_digest([11, 23, 47]),
        record_content_digest([23, 47, 11]),
    ),
)

all(pair -> pair[1] == pair[2], values(expected)) || error(
    "Julia metamorphic oracle violated a required property",
)

lines = readlines(only(ARGS))
marker = "DOSA_SOUNIO_METAMORPHIC_FIXTURE_OK observations=$(length(expected))"
marker in lines || error("Sounio metamorphic success marker is absent or has wrong count")

observed = Dict{String, Tuple{Int, Int}}()
for line in lines
    matched = match(OBSERVATION_PATTERN, line)
    isnothing(matched) && continue
    property, lhs, rhs = matched.captures
    haskey(observed, property) && error("duplicate Sounio property: $property")
    observed[property] = (parse(Int, lhs), parse(Int, rhs))
end

Set(keys(observed)) == Set(keys(expected)) || error(
    "unexpected property set: $(sort!(collect(keys(observed))))",
)

for property in sort!(collect(keys(expected)))
    actual = observed[property]
    oracle = expected[property]
    actual == oracle || error(
        "metamorphic mismatch for $property: Sounio=$actual Julia=$oracle",
    )
end

println("DOSA_JULIA_METAMORPHIC_FIXTURE_OK")
println("validated_properties=$(length(expected)) tolerance=0")
