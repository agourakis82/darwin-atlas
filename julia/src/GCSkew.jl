"""
    GCSkew.jl

GC skew analysis and origin/terminus estimation for bacterial replicons.

GC skew = (G - C) / (G + C) in sliding windows.
Cumulative skew curve used to estimate replication origin (ori) and terminus (ter).
"""

using BioSequences: LongDNA, DNA_G, DNA_C
using DataFrames
using Statistics

export compute_gc_skew, estimate_ori_ter, split_replichores
export GCSkewResult, OriTerEstimate

"""
    GCSkewResult

Results from GC skew analysis.
"""
struct GCSkewResult
    position::Int  # Window center position (bp)
    gc_skew::Float64  # (G - C) / (G + C)
    g_count::Int
    c_count::Int
    window_size::Int
end

"""
    OriTerEstimate

Origin/terminus estimation results.
"""
struct OriTerEstimate
    ori_position::Int  # Estimated origin (bp)
    ter_position::Int  # Estimated terminus (bp)
    ori_confidence::Float64  # Confidence [0, 1]
    ter_confidence::Float64  # Confidence [0, 1]
    gc_skew_amplitude::Float64  # Peak-to-trough amplitude
    window_size::Int
    cumulative_skew_min::Float64
    cumulative_skew_max::Float64
end

"""
    compute_gc_skew(seq::LongDNA, window_size::Int=1000; step::Int=100) -> Vector{GCSkewResult}

Compute GC skew in sliding windows.

# Arguments
- `seq`: DNA sequence to analyze
- `window_size`: Size of sliding window (bp, default: 1000)
- `step`: Step size between windows (bp, default: 100)

# Returns
Vector of GCSkewResult for each window.

# Definition
GC skew = (G - C) / (G + C)

Range: [-1, 1]
- Positive: G-rich
- Negative: C-rich
- Zero: Balanced G/C
"""
function compute_gc_skew(seq::LongDNA, window_size::Int=1000; step::Int=100)::Vector{GCSkewResult}
    n = length(seq)
    n < window_size && return GCSkewResult[]

    results = GCSkewResult[]

    for start_pos in 1:step:n-window_size+1
        window = seq[start_pos:start_pos+window_size-1]

        g_count = count(b -> b == DNA_G, window)
        c_count = count(b -> b == DNA_C, window)
        total_gc = g_count + c_count

        gc_skew = total_gc > 0 ? (g_count - c_count) / total_gc : 0.0

        center_pos = start_pos + window_size ÷ 2
        push!(results, GCSkewResult(center_pos, gc_skew, g_count, c_count, window_size))
    end

    return results
end

"""
    estimate_ori_ter(seq::LongDNA, window_size::Int=1000; step::Int=100) -> OriTerEstimate

Estimate replication origin and terminus from GC skew.

# Method
1. Compute GC skew in sliding windows
2. Compute cumulative skew curve
3. Ori ≈ argmin(cumulative) (minimum cumulative skew)
4. Ter ≈ argmax(cumulative) (maximum cumulative skew)
5. Confidence = amplitude / baseline_noise

# Arguments
- `seq`: DNA sequence to analyze
- `window_size`: Size of sliding window (bp)
- `step`: Step size between windows (bp)

# Returns
OriTerEstimate with positions and confidence scores.

# Validity
- ori_position, ter_position: [0, length(seq))
- ori_confidence, ter_confidence: [0, 1]
- gc_skew_amplitude: ≥ 0
"""
function estimate_ori_ter(seq::LongDNA, window_size::Int=1000; step::Int=100)::OriTerEstimate
    n = length(seq)
    if n < window_size
        # Fallback: assume ori at position 0, ter at midpoint
        return OriTerEstimate(
            0, n ÷ 2,
            0.0, 0.0,
            0.0, window_size,
            0.0, 0.0
        )
    end

    # Compute GC skew
    skew_results = compute_gc_skew(seq, window_size; step=step)
    isempty(skew_results) && error("No GC skew results computed")

    # Compute cumulative skew
    cumulative = Float64[]
    cumsum = 0.0
    for result in skew_results
        cumsum += result.gc_skew
        push!(cumulative, cumsum)
    end

    # Find ori (minimum) and ter (maximum)
    ori_idx = argmin(cumulative)
    ter_idx = argmax(cumulative)

    ori_position = skew_results[ori_idx].position
    ter_position = skew_results[ter_idx].position

    # Compute amplitude
    cum_min = cumulative[ori_idx]
    cum_max = cumulative[ter_idx]
    amplitude = cum_max - cum_min

    # Compute confidence based on amplitude relative to noise
    # Noise estimate: standard deviation of cumulative skew
    cum_std = std(cumulative)
    baseline_noise = max(cum_std, 1e-10)  # Avoid division by zero

    ori_confidence = min(amplitude / (baseline_noise * 2), 1.0)
    ter_confidence = min(amplitude / (baseline_noise * 2), 1.0)

    # Ensure positions are within bounds
    ori_position = max(0, min(ori_position, n - 1))
    ter_position = max(0, min(ter_position, n - 1))

    return OriTerEstimate(
        ori_position,
        ter_position,
        ori_confidence,
        ter_confidence,
        amplitude,
        window_size,
        cum_min,
        cum_max
    )
end

"""
    split_replichores(seq::LongDNA, ori::Int, ter::Int) -> Tuple{LongDNA, LongDNA}

Split a circular replicon into leading and lagging replichores.

# Arguments
- `seq`: Circular DNA sequence
- `ori`: Origin position (bp, 0-indexed)
- `ter`: Terminus position (bp, 0-indexed)

# Returns
Tuple of (leading_replichore, lagging_replichore).

# Note
For circular sequences, we extract:
- Leading: from ori to ter (forward direction)
- Lagging: from ter to ori (forward direction, wrapping around)
"""
function split_replichores(seq::LongDNA, ori::Int, ter::Int)::Tuple{LongDNA, LongDNA}
    n = length(seq)
    ori = mod(ori, n)
    ter = mod(ter, n)

    # Leading replichore: ori to ter (forward)
    if ori < ter
        leading = seq[ori+1:ter]
    else
        # Wraps around
        leading = seq[ori+1:end] * seq[1:ter]
    end

    # Lagging replichore: ter to ori (forward, opposite strand)
    if ter < ori
        lagging = seq[ter+1:ori]
    else
        # Wraps around
        lagging = seq[ter+1:end] * seq[1:ori]
    end

    return (leading, lagging)
end

"""
    compute_gc_skew_table(records::Vector{Tuple{String, LongDNA}}, window_size::Int=1000) -> DataFrame

Compute GC skew and ori/ter estimates for multiple sequences.

# Arguments
- `records`: Vector of (replicon_id, sequence) tuples
- `window_size`: Window size for GC skew computation

# Returns
DataFrame with columns:
- `replicon_id`: Replicon identifier
- `ori_position`: Estimated origin (bp)
- `ter_position`: Estimated terminus (bp)
- `ori_confidence`: Confidence [0, 1]
- `ter_confidence`: Confidence [0, 1]
- `gc_skew_amplitude`: Peak-to-trough amplitude
- `window_size`: Window size used
"""
function compute_gc_skew_table(
    records::Vector{Tuple{String, LongDNA}},
    window_size::Int=1000
)::DataFrame
    results = OriTerEstimate[]

    for (replicon_id, seq) in records
        estimate = estimate_ori_ter(seq, window_size)
        push!(results, estimate)
    end

    df = DataFrame(
        replicon_id=[r[1] for r in records],
        ori_position=[r.ori_position for r in results],
        ter_position=[r.ter_position for r in results],
        ori_confidence=[r.ori_confidence for r in results],
        ter_confidence=[r.ter_confidence for r in results],
        gc_skew_amplitude=[r.gc_skew_amplitude for r in results],
        window_size=[r.window_size for r in results]
    )

    # Validate ranges
    seq_lengths = [length(r[2]) for r in records]
    @assert all(0 .<= df.ori_position .< seq_lengths) "ori_position out of range"
    @assert all(0 .<= df.ter_position .< seq_lengths) "ter_position out of range"
    @assert all(0.0 .<= df.ori_confidence .<= 1.0) "ori_confidence must be in [0, 1]"
    @assert all(0.0 .<= df.ter_confidence .<= 1.0) "ter_confidence must be in [0, 1]"
    @assert all(df.gc_skew_amplitude .>= 0.0) "gc_skew_amplitude must be >= 0"

    return df
end

