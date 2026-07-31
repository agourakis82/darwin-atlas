#!/usr/bin/env julia

"""
Independent Base-only Julia validator for the Sounio operator fixture.

This script intentionally loads no DarwinAtlas module and no external package.
It recomputes the named observations from their sequence labels and compares
them with the persisted stdout artifact produced by Sounio.
"""

if length(ARGS) != 1
    println(stderr, "usage: validate_operator_fixture.jl <sounio-output.log>")
    exit(2)
end

const COMPLEMENT = Dict('A' => 'T', 'T' => 'A', 'C' => 'G', 'G' => 'C')
const OBSERVATION_PATTERN = r"^DOSA_OBSERVATION sequence=([ACGT]+) metric=(delta_R|delta_RC) mismatches=([0-9]+) denominator=([0-9]+)$"

reverse_sequence(sequence::String) = reverse(sequence)
reverse_complement(sequence::String) = String(collect(COMPLEMENT[base] for base in reverse(sequence)))

function hamming(left::String, right::String)::Int
    length(left) == length(right) || error("length mismatch in Julia oracle")
    return count(pair -> pair[1] != pair[2], zip(left, right))
end

function expected_observation(sequence::String, metric::String)::Tuple{Int, Int}
    transformed = if metric == "delta_R"
        reverse_sequence(sequence)
    elseif metric == "delta_RC"
        reverse_complement(sequence)
    else
        error("unknown metric: $metric")
    end
    return hamming(sequence, transformed), length(sequence)
end

lines = readlines(only(ARGS))
"DOSA_SOUNIO_OPERATOR_FIXTURE_OK" in lines || error("Sounio success marker is absent")

observed = Dict{Tuple{String, String}, Tuple{Int, Int}}()
for line in lines
    matched = match(OBSERVATION_PATTERN, line)
    isnothing(matched) && continue
    sequence, metric, mismatches, denominator = matched.captures
    key = (sequence, metric)
    haskey(observed, key) && error("duplicate Sounio observation: $key")
    observed[key] = (parse(Int, mismatches), parse(Int, denominator))
end

required = [
    ("ACGT", "delta_R"),
    ("ACGT", "delta_RC"),
    ("ACCA", "delta_R"),
    ("ACCA", "delta_RC"),
]

Set(keys(observed)) == Set(required) || error(
    "unexpected observation set: $(sort!(collect(keys(observed))))",
)

for key in required
    expected = expected_observation(key...)
    actual = observed[key]
    actual == expected || error("differential mismatch for $key: Sounio=$actual Julia=$expected")
end

println("DOSA_JULIA_DIFFERENTIAL_FIXTURE_OK")
println("validated_observations=$(length(required)) tolerance=0")
