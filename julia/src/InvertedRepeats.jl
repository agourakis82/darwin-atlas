"""
    InvertedRepeats.jl

Inverted repeat (IR) detection and enrichment analysis.

Detects stem-loop structures with statistical enrichment vs baseline.
"""

using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T, reverse_complement
using DataFrames
using Random
using Statistics

export detect_inverted_repeats, compute_baseline_shuffle
export compute_ir_enrichment, InvertedRepeat
export count_inverted_repeats_exact

"""
    InvertedRepeat

A detected inverted repeat structure.
"""
struct InvertedRepeat
    start_pos::Int  # Start of first stem (bp, 0-indexed)
    stem_length::Int  # Length of each stem (bp)
    loop_length::Int  # Length of loop (bp)
    end_pos::Int  # End of second stem (bp, 0-indexed)
    match_score::Float64  # Fraction of matching bases in stems
end

@inline function _ir_base_to_2bit(base)::UInt32
    if base == DNA_A
        return 0x00
    elseif base == DNA_C
        return 0x01
    elseif base == DNA_G
        return 0x02
    elseif base == DNA_T
        return 0x03
    end
    error("Invalid DNA base: $base")
end

@inline function _ir_rc_code(code::UInt32, k::Int)::UInt32
    rc = UInt32(0)
    @inbounds for _ in 1:k
        base = code & 0x03
        rc = (rc << 2) | (base ⊻ 0x03)
        code >>= 2
    end
    return rc
end

"""
    count_inverted_repeats_exact(seq::LongDNA; stem_len::Int=8, loop_min::Int=3, loop_max::Int=20) -> Int

Count exact inverted repeats w ... loop ... RC(w) for a fixed stem length.

This is an O(n * (loop_max-loop_min+1)) scan using 2-bit k-mer encoding and is
designed to be tractable on multi-megabase replicons.
"""
function count_inverted_repeats_exact(
    seq::LongDNA;
    stem_len::Int=8,
    loop_min::Int=3,
    loop_max::Int=20
)::Int
    n = length(seq)
    n < 2 * stem_len + loop_min && return 0

    n_kmers = n - stem_len + 1
    n_kmers <= 0 && return 0

    codes = Vector{UInt32}(undef, n_kmers)
    rc_codes = Vector{UInt32}(undef, n_kmers)

    mask = UInt32((1 << (2 * stem_len)) - 1)
    code = UInt32(0)

    @inbounds for i in 1:stem_len
        code = (code << 2) | _ir_base_to_2bit(seq[i])
    end
    codes[1] = code
    rc_codes[1] = _ir_rc_code(code, stem_len)

    @inbounds for i in 2:n_kmers
        code = ((code << 2) & mask) | _ir_base_to_2bit(seq[i + stem_len - 1])
        codes[i] = code
        rc_codes[i] = _ir_rc_code(code, stem_len)
    end

    ir_count = 0
    @inbounds for loop_len in loop_min:loop_max
        max_i = n - 2 * stem_len - loop_len + 1
        max_i <= 0 && continue
        offset = stem_len + loop_len
        for i in 1:max_i
            j = i + offset
            if codes[i] == rc_codes[j]
                ir_count += 1
            end
        end
    end

    return ir_count
end

function expected_ir_count_markov1(
    seq::LongDNA;
    stem_len::Int=8,
    loop_min::Int=3,
    loop_max::Int=20
)::Float64
    n = length(seq)
    n < 2 * stem_len + loop_min && return 0.0

    a = count(b -> b == DNA_A, seq)
    c = count(b -> b == DNA_C, seq)
    g = count(b -> b == DNA_G, seq)
    t = count(b -> b == DNA_T, seq)

    total = a + c + g + t
    total == 0 && return 0.0

    pA = a / total
    pC = c / total
    pG = g / total
    pT = t / total

    # P(w == RC(w')) under an IID (Markov-1) model:
    # sum_b p(b) p(comp(b)) = 2(pA pT + pC pG), then raise to stem_len.
    p_match_pos = 2.0 * (pA * pT + pC * pG)
    p_match = p_match_pos^stem_len

    expected = 0.0
    for loop_len in loop_min:loop_max
        n_struct = n - 2 * stem_len - loop_len + 1
        n_struct <= 0 && continue
        expected += n_struct * p_match
    end

    return expected
end

"""
    detect_inverted_repeats(seq::LongDNA; stem_min::Int=8, loop_min::Int=3, loop_max::Int=20, min_match::Float64=0.8) -> Vector{InvertedRepeat}

Detect inverted repeats in a DNA sequence.

# Arguments
- `seq`: DNA sequence to analyze
- `stem_min`: Minimum stem length (bp, default: 8)
- `loop_min`: Minimum loop length (bp, default: 3)
- `loop_max`: Maximum loop length (bp, default: 20)
- `min_match`: Minimum match fraction in stems (default: 0.8)

# Returns
Vector of InvertedRepeat structures.

# Definition
An inverted repeat consists of:
- Stem 1: sequence w
- Loop: sequence of length L (loop_min ≤ L ≤ loop_max)
- Stem 2: reverse complement of w

Total structure: w ... loop ... RC(w)
"""
function detect_inverted_repeats(
    seq::LongDNA;
    stem_min::Int=8,
    loop_min::Int=3,
    loop_max::Int=20,
    min_match::Float64=0.8
)::Vector{InvertedRepeat}
    n = length(seq)
    irs = InvertedRepeat[]

    # Try all possible stem lengths
    for stem_len in stem_min:min(n ÷ 2, 50)  # Cap at 50bp for efficiency
        # Try all possible loop lengths
        for loop_len in loop_min:loop_max
            # Try all starting positions
            for start in 1:n-stem_len-loop_len-stem_len+1
                stem1_start = start
                stem1_end = start + stem_len - 1
                loop_start = stem1_end + 1
                loop_end = loop_start + loop_len - 1
                stem2_start = loop_end + 1
                stem2_end = stem2_start + stem_len - 1

                if stem2_end > n
                    break  # Can't fit this structure
                end

                # Extract stems
                stem1 = seq[stem1_start:stem1_end]
                stem2 = seq[stem2_start:stem2_end]
                stem2_rc = reverse_complement(stem2)

                # Check match quality
                matches = 0
                for i in 1:stem_len
                    if stem1[i] == stem2_rc[i]
                        matches += 1
                    end
                end

                match_score = matches / stem_len

                if match_score >= min_match
                    push!(irs, InvertedRepeat(
                        stem1_start - 1,  # 0-indexed
                        stem_len,
                        loop_len,
                        stem2_end - 1,  # 0-indexed
                        match_score
                    ))
                end
            end
        end
    end

    return irs
end

"""
    markov1_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG) -> LongDNA

Create a mono-nucleotide Markov shuffle (preserves base composition).

# Arguments
- `seq`: Original sequence
- `rng`: Random number generator

# Returns
Shuffled sequence with same base composition.
"""
function markov1_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG)::LongDNA
    bases = collect(seq)
    shuffle!(rng, bases)
    return LongDNA{4}(bases)
end

"""
    markov2_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG) -> LongDNA

Create a di-nucleotide Markov shuffle (preserves dinucleotide frequencies).

# Arguments
- `seq`: Original sequence
- `rng`: Random number generator

# Returns
Shuffled sequence with same dinucleotide composition.

# Note
This is a simplified implementation. A full Markov-2 shuffle would
preserve transition probabilities, which is more complex.
"""
function markov2_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG)::LongDNA
    # Simplified: shuffle dinucleotides
    n = length(seq)
    n < 2 && return seq

    dinucs = LongDNA{4}[]
    for i in 1:n-1
        push!(dinucs, seq[i:i+1])
    end

    shuffle!(rng, dinucs)

    # Reconstruct sequence
    result = LongDNA{4}()
    for i in 1:length(dinucs)
        if i == 1
            result = dinucs[i]
        else
            # Overlap: take second base only
            result = result * dinucs[i][2]
        end
    end

    return result
end

"""
    compute_baseline_shuffle(seq::LongDNA, method::String="markov1"; rng=Random.GLOBAL_RNG, n_samples::Int=100) -> Float64

Compute expected IR count from baseline shuffle.

# Arguments
- `seq`: Original sequence
- `method`: Shuffle method ("markov1" or "markov2")
- `rng`: Random number generator
- `n_samples`: Number of shuffle samples

# Returns
Mean IR count from shuffled sequences.
"""
function compute_baseline_shuffle(
    seq::LongDNA,
    method::String="markov1";
    rng=Random.GLOBAL_RNG,
    n_samples::Int=100
)::Float64
    shuffle_fn = method == "markov2" ? markov2_shuffle : markov1_shuffle

    ir_counts = Int[]
    for _ in 1:n_samples
        shuffled = shuffle_fn(seq; rng=rng)
        irs = detect_inverted_repeats(shuffled)
        push!(ir_counts, length(irs))
    end

    return mean(ir_counts)
end

"""
    compute_ir_enrichment(
        seq::LongDNA,
        stem_min::Int=8,
        loop_max::Int=20;
        baseline_method::String="markov1",
        n_baseline_samples::Int=100,
        rng=Random.GLOBAL_RNG
    ) -> Dict

Compute IR enrichment vs baseline.

# Arguments
- `seq`: DNA sequence to analyze
- `stem_min`: Minimum stem length
- `loop_max`: Maximum loop length
- `baseline_method`: Shuffle method for baseline
- `n_baseline_samples`: Number of baseline samples
- `rng`: Random number generator

# Returns
Dictionary with:
- `ir_count`: Observed IR count
- `ir_density`: IRs per kb
- `baseline_count`: Expected count from baseline
- `enrichment_ratio`: Observed / expected
- `p_value`: Statistical significance (simplified)
- `baseline_method`: Method used
- `stem_min_length`: Minimum stem length
- `loop_max_length`: Maximum loop length
"""
function compute_ir_enrichment(
    seq::LongDNA,
    stem_min::Int=8,
    loop_max::Int=20;
    stem_max::Int=12,
    loop_min::Int=3,
    baseline_method::String="markov1",
    n_baseline_samples::Int=100,
    rng=Random.GLOBAL_RNG
)::Dict
    # Observed IR count: exact IRs across a small stem-length range for tractability.
    ir_count = 0
    for stem_len in stem_min:stem_max
        ir_count += count_inverted_repeats_exact(
            seq; stem_len=stem_len, loop_min=loop_min, loop_max=loop_max
        )
    end

    # Baseline: Markov-1 analytic expectation (fast, deterministic). Fallback to shuffles if requested.
    baseline_count = if lowercase(baseline_method) in ["markov1", "markov1_analytic"]
        expected = 0.0
        for stem_len in stem_min:stem_max
            expected += expected_ir_count_markov1(
                seq; stem_len=stem_len, loop_min=loop_min, loop_max=loop_max
            )
        end
        expected
    else
        compute_baseline_shuffle(seq, baseline_method; rng=rng, n_samples=n_baseline_samples)
    end

    # Compute enrichment
    enrichment_ratio = baseline_count > 0 ? ir_count / baseline_count : (ir_count > 0 ? Inf : 1.0)

    # Simplified p-value: z-score approximation
    # This is a heuristic; proper p-value would require more sophisticated statistics
    # Using erf approximation for normal CDF: P(Z > z) ≈ 0.5 * (1 - erf(z/√2))
    if baseline_count > 0
        std_dev = sqrt(baseline_count)  # Poisson approximation
        z_score = abs(ir_count - baseline_count) / max(std_dev, 1.0)
        # Approximate normal CDF using error function
        # P(|Z| > z) ≈ 1 - erf(z/√2)
        erf_arg = z_score / sqrt(2.0)
        # Simple erf approximation: erf(x) ≈ tanh(1.128379167 * x)
        erf_approx = tanh(1.128379167 * erf_arg)
        p_value = 1.0 - erf_approx  # Two-tailed
        p_value = max(0.0, min(1.0, p_value))
    else
        p_value = ir_count > 0 ? 0.0 : 1.0
    end

    # Compute density (IRs per kb)
    seq_length_kb = length(seq) / 1000.0
    ir_density = seq_length_kb > 0 ? ir_count / seq_length_kb : 0.0

    return Dict(
        "ir_count" => ir_count,
        "ir_density" => ir_density,
        "baseline_count" => baseline_count,
        "enrichment_ratio" => enrichment_ratio,
        "p_value" => p_value,
        "baseline_method" => baseline_method,
        "stem_min_length" => stem_min,
        "loop_max_length" => loop_max
    )
end

"""
    compute_ir_enrichment_table(
        records::Vector{Tuple{String, LongDNA}},
        stem_min::Int=8,
        loop_max::Int=20;
        baseline_method::String="markov1",
        n_baseline_samples::Int=100
    ) -> DataFrame

Compute IR enrichment for multiple sequences.

# Arguments
- `records`: Vector of (replicon_id, sequence) tuples
- `stem_min`: Minimum stem length
- `loop_max`: Maximum loop length
- `baseline_method`: Shuffle method
- `n_baseline_samples`: Number of baseline samples

# Returns
DataFrame with enrichment statistics.
"""
function compute_ir_enrichment_table(
    records::Vector{Tuple{String, LongDNA}},
    stem_min::Int=8,
    loop_max::Int=20;
    baseline_method::String="markov1_analytic",
    n_baseline_samples::Int=100
)::DataFrame
    rng = Random.MersenneTwister(42)  # Deterministic seed

    results = Dict[]
    for (replicon_id, seq) in records
        result = compute_ir_enrichment(
            seq, stem_min, loop_max;
            baseline_method=baseline_method,
            n_baseline_samples=n_baseline_samples,
            rng=rng
        )
        result["replicon_id"] = replicon_id
        push!(results, result)
    end

    df = DataFrame(
        replicon_id=[r["replicon_id"] for r in results],
        ir_count=[r["ir_count"] for r in results],
        ir_density=[r["ir_density"] for r in results],
        baseline_count=[r["baseline_count"] for r in results],
        enrichment_ratio=[r["enrichment_ratio"] for r in results],
        p_value=[r["p_value"] for r in results],
        baseline_method=[r["baseline_method"] for r in results],
        stem_min_length=[r["stem_min_length"] for r in results],
        loop_max_length=[r["loop_max_length"] for r in results]
    )

    # Validate ranges
    @assert all(df.ir_count .>= 0) "ir_count must be >= 0"
    @assert all(df.ir_density .>= 0) "ir_density must be >= 0"
    @assert all(df.enrichment_ratio .>= 0) "enrichment_ratio must be >= 0"
    @assert all(0.0 .<= df.p_value .<= 1.0) "p_value must be in [0, 1]"

    return df
end
