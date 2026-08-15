#!/usr/bin/env julia

"""
Independent Base-only validator for the nested DOSA v3 window-profile fixture.

The Sounio executable emits four complete analytic rows, one synthetic window
at each U0 scale. This validator reuses only the frozen input grammar and RNG
constants from the draw validator. It independently represents k-mer counts in
Julia dictionaries, reconstructs all 4,000 Euler/Wilson draws, recomputes the
17 published operators, exact mean/MAD/quantiles/tails, and requires every
JSONL byte to match. It is fixture evidence, not a pilot receipt.
"""

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const DRAW_VALIDATOR = joinpath(@__DIR__, "validate_u0_dinucleotide_scale_fixture.jl")
include(DRAW_VALIDATOR)

const PROFILE_METRICS = 17

profile_fail(message) = error("U0_PROFILE_VALIDATION_FAIL: " * message)

function positional_numerator(sequence::Vector{Int}, complement::Bool)::Int
    mismatches = 0
    n = length(sequence)
    for i in eachindex(sequence)
        opposite = sequence[n + 1 - i]
        expected = complement ? 3 - opposite : opposite
        mismatches += sequence[i] != expected
    end
    mismatches
end

function kmer_counts(sequence::Vector{Int}, k::Int)::Dict{Int,Int}
    1 <= k <= 8 || profile_fail("k outside 1:8")
    modulus = 4^k
    code = 0
    run = 0
    counts = Dict{Int,Int}()
    for base in sequence
        0 <= base <= 3 || profile_fail("noncanonical base in profile input")
        code = mod(4 * code + base, modulus)
        run += 1
        run >= k && (counts[code] = get(counts, code, 0) + 1)
    end
    counts
end

function transformed_code(code::Int, k::Int, complement::Bool)::Int
    value = code
    output = 0
    for _ in 1:k
        base = mod(value, 4)
        value = div(value, 4)
        transformed = complement ? 3 - base : base
        output = 4 * output + transformed
    end
    output
end

function orbit_numerator(counts::Dict{Int,Int}, k::Int, complement::Bool)::Int
    visited = Set{Int}()
    numerator = 0
    for code in keys(counts)
        code in visited && continue
        partner = transformed_code(code, k, complement)
        push!(visited, code)
        push!(visited, partner)
        numerator += abs(counts[code] - get(counts, partner, 0))
    end
    numerator
end

function profile_metrics(sequence::String)::Tuple{Vector{Int},Vector{Int}}
    bases = Int[get(BASE_TO_CODE, base, -1) for base in sequence]
    all(>=(0), bases) || profile_fail("profile sequence is not ACGT")
    numerators = zeros(Int, PROFILE_METRICS)
    effective = zeros(Int, PROFILE_METRICS)
    numerators[1] = positional_numerator(bases, false)
    effective[1] = length(bases)
    numerators[2] = positional_numerator(bases, true)
    effective[2] = length(bases)
    for k in 1:8
        counts = kmer_counts(bases, k)
        count = sum(values(counts))
        count == length(bases) - k + 1 || profile_fail("k-mer effective-count drift at k=$k")
        if k >= 2
            numerators[k + 1] = orbit_numerator(counts, k, false)
            effective[k + 1] = count
        end
        numerators[9 + k] = orbit_numerator(counts, k, true)
        effective[9 + k] = count
    end
    numerators, effective
end

fraction_json(numerator::Int, denominator::Int) =
    "{\"numerator\":$numerator,\"denominator\":$denominator}"

function null_summary_json(values::Vector{Int}, observed::Int, effective::Int)::String
    length(values) == REPLICATES || profile_fail("null replicate count is not $REPLICATES")
    effective > 0 || profile_fail("non-positive effective count")
    ordered = sort(values)
    total = sum(ordered)
    mad_numerator = sum(abs(REPLICATES * value - total) for value in ordered)
    q025 = ordered[div(25 * (REPLICATES - 1), 100) + 1]
    q500 = ordered[div(500 * (REPLICATES - 1), 1000) + 1]
    q975 = ordered[div(975 * (REPLICATES - 1), 1000) + 1]
    tail_lt = count(<(observed), values)
    tail_eq = count(==(observed), values)
    tail_gt = count(>(observed), values)
    tail_lt + tail_eq + tail_gt == REPLICATES || profile_fail("tail partition drift")
    string(
        "{\"n\":1000,\"mean\":", fraction_json(total, REPLICATES * effective),
        ",\"mad\":", fraction_json(mad_numerator, REPLICATES * REPLICATES * effective),
        ",\"q025\":", fraction_json(q025, effective),
        ",\"q500\":", fraction_json(q500, effective),
        ",\"q975\":", fraction_json(q975, effective),
        ",\"tail_lt\":$tail_lt,\"tail_eq\":$tail_eq,\"tail_gt\":$tail_gt,",
        "\"reason_code\":null}"
    )
end

function observation_json(metric::Int, k::Union{Nothing,Int},
                          observed_numerators::Vector{Int}, effective::Vector{Int},
                          draws::Vector{Vector{Int}})::String
    1 <= metric <= PROFILE_METRICS || profile_fail("metric index outside profile")
    prefix = isnothing(k) ? "{" : "{\"k\":$k,"
    string(
        prefix,
        "\"effective_count\":", effective[metric],
        ",\"observed\":", fraction_json(observed_numerators[metric], effective[metric]),
        ",\"null_summary\":",
        null_summary_json(draws[metric], observed_numerators[metric], effective[metric]),
        ",\"reason_code\":null}"
    )
end

function expected_profile_line(case; run_id::String="u0-profile-fixture")::String
    observed_numerators, effective = profile_metrics(case.bases)
    draws = [Int[] for _ in 1:PROFILE_METRICS]
    for replicate in 1:REPLICATES
        draw = shuffled_sequence(case.bases, case.seed64, replicate)
        numerators, draw_effective = profile_metrics(draw)
        draw_effective == effective || profile_fail("effective-count drift in $(case.case_id) replicate $replicate")
        for metric in 1:PROFILE_METRICS
            push!(draws[metric], numerators[metric])
        end
    end
    div(case.window_start, case.scale) * case.scale == case.window_start ||
        profile_fail("window start is not aligned for $(case.case_id)")
    kmer_r = join(
        (observation_json(k + 1, k, observed_numerators, effective, draws) for k in 2:8), ","
    )
    kmer_rc = join(
        (observation_json(9 + k, k, observed_numerators, effective, draws) for k in 1:8), ","
    )
    string(
        "{\"run_id\":\"$run_id\",\"replicon_id\":\"$(case.accession)\",",
        "\"window_size\":$(case.scale),\"window_index\":$(div(case.window_start, case.scale)),",
        "\"window_start\":$(case.window_start),\"window_end\":$(case.window_start + case.scale),",
        "\"status\":\"eligible\",\"reason_code\":null,",
        "\"positional_r\":", observation_json(1, nothing, observed_numerators, effective, draws),
        ",\"positional_rc\":", observation_json(2, nothing, observed_numerators, effective, draws),
        ",\"kmer_r\":[", kmer_r, "],\"kmer_rc\":[", kmer_rc, "]}"
    )
end

function validate_profiles(parameters_path::String, cases_path::String, artifact_path::String)
    isfile(artifact_path) || profile_fail("Sounio profile JSONL is missing")
    filesize(artifact_path) > 0 || profile_fail("Sounio profile JSONL is empty")
    open(artifact_path, "r") do io
        seek(io, filesize(artifact_path) - 1)
        read(io, UInt8) == 0x0a || profile_fail("profile JSONL must end in LF")
    end
    cases = parse_cases(parameters_path, cases_path)
    open(artifact_path, "r") do io
        for case in cases
            eof(io) && profile_fail("profile artifact ended before $(case.case_id)")
            actual = readline(io)
            expected = expected_profile_line(case)
            actual == expected || profile_fail("byte mismatch for $(case.case_id)")
        end
        eof(io) || profile_fail("profile artifact has extra rows")
    end
    println("U0_WINDOW_PROFILE_JULIA_DIFFERENTIAL_PASS rows=4 metrics=17 replicates=1000 draws=4000 scales=16,100,500,1000 tolerance=0")
end

function main_profile(args)
    length(args) == 3 || begin
        println(stderr, "usage: validate_u0_window_profile_fixture.jl <parameters.json> <cases.tsv> <profiles.jsonl>")
        exit(2)
    end
    validate_profiles(args...)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main_profile(ARGS)
end
