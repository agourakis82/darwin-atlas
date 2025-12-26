"""
    NullModels.jl

Null models for symmetry statistics with Markov shuffles.
"""

using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T
using Random
using StatsBase

export markov1_chain_shuffle, markov2_chain_shuffle
export null_pvalue, fdr_bh

const BASES = (DNA_A, DNA_C, DNA_G, DNA_T)

function base_index(b)
    if b == DNA_A
        return 1
    elseif b == DNA_C
        return 2
    elseif b == DNA_G
        return 3
    elseif b == DNA_T
        return 4
    else
        return 1
    end
end

function markov1_model(seq::LongDNA)
    counts = fill(1.0, 4, 4)  # add-1 smoothing
    n = length(seq)
    n < 2 && return counts

    for i in 1:(n - 1)
        a = base_index(seq[i])
        b = base_index(seq[i + 1])
        counts[a, b] += 1
    end
    # Normalize rows
    for i in 1:4
        row_sum = sum(counts[i, :])
        counts[i, :] ./= row_sum
    end
    return counts
end

function markov1_chain_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG)::LongDNA
    n = length(seq)
    n == 0 && return seq
    trans = markov1_model(seq)
    # initial base from empirical distribution
    base_counts = [count(b -> b == BASES[i], seq) for i in 1:4]
    base_probs = base_counts ./ sum(base_counts)
    curr = sample(rng, 1:4; weights=base_probs)
    out = Vector{typeof(seq[1])}(undef, n)
    out[1] = BASES[curr]
    for i in 2:n
        curr = sample(rng, 1:4; weights=trans[curr, :])
        out[i] = BASES[curr]
    end
    return LongDNA{4}(out)
end

function markov2_model(seq::LongDNA)
    counts = fill(1.0, 4, 4, 4)  # P(b3 | b1,b2)
    n = length(seq)
    n < 3 && return counts
    for i in 1:(n - 2)
        a = base_index(seq[i])
        b = base_index(seq[i + 1])
        c = base_index(seq[i + 2])
        counts[a, b, c] += 1
    end
    for a in 1:4, b in 1:4
        s = sum(counts[a, b, :])
        counts[a, b, :] ./= s
    end
    return counts
end

function markov2_chain_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG)::LongDNA
    n = length(seq)
    n == 0 && return seq
    if n < 3
        return markov1_chain_shuffle(seq; rng=rng)
    end
    trans = markov2_model(seq)
    base_counts = [count(b -> b == BASES[i], seq) for i in 1:4]
    base_probs = base_counts ./ sum(base_counts)
    b1 = sample(rng, 1:4; weights=base_probs)
    b2 = sample(rng, 1:4; weights=base_probs)
    out = Vector{typeof(seq[1])}(undef, n)
    out[1] = BASES[b1]
    out[2] = BASES[b2]
    for i in 3:n
        b3 = sample(rng, 1:4; weights=trans[b1, b2, :])
        out[i] = BASES[b3]
        b1, b2 = b2, b3
    end
    return LongDNA{4}(out)
end

"""
    null_pvalue(obs, null_values; tail=:lower) -> Float64

Compute an empirical p-value from a null distribution.
"""
function null_pvalue(obs::Real, null_values::AbstractVector{<:Real}; tail::Symbol=:lower)::Float64
    n = length(null_values)
    n == 0 && return 1.0
    if tail == :lower
        return (sum(v -> v <= obs, null_values) + 1) / (n + 1)
    else
        return (sum(v -> v >= obs, null_values) + 1) / (n + 1)
    end
end

"""
    fdr_bh(pvals) -> Vector{Float64}

Benjamini-Hochberg FDR correction.
"""
function fdr_bh(pvals::AbstractVector{<:Real})::Vector{Float64}
    n = length(pvals)
    order = sortperm(pvals)
    qvals = fill(1.0, n)
    prev = 1.0
    for (rank, idx) in enumerate(reverse(order))
        p = pvals[idx]
        q = min(prev, p * n / (n - rank + 1))
        qvals[idx] = q
        prev = q
    end
    return qvals
end
