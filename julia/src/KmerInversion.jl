"""
    KmerInversion.jl

k-mer inversion symmetry analysis (Generalized Chargaff / RC parity).

Computes the deviation from perfect reverse-complement symmetry in k-mer counts.
"""

using BioSequences: LongDNA, LongSequence, DNAAlphabet, DNA_A, DNA_C, DNA_G, DNA_T, reverse_complement
using DataFrames
using Statistics

export compute_kmer_inversion, compute_kmer_inversion_for_k
export KmerInversionResult

@inline function _kmer_base_to_2bit(base)::UInt32
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

@inline function _kmer_rc_code(code::UInt32, k::Int)::UInt32
    rc = UInt32(0)
    @inbounds for _ in 1:k
        base = code & 0x03
        rc = (rc << 2) | (base ⊻ 0x03)
        code >>= 2
    end
    return rc
end

const _RC_LUT_CACHE = Dict{Int, Vector{UInt32}}()

function _rc_lut(k::Int)::Vector{UInt32}
    if haskey(_RC_LUT_CACHE, k)
        return _RC_LUT_CACHE[k]
    end

    n_codes = 1 << (2 * k)  # 4^k
    lut = Vector{UInt32}(undef, n_codes)
    @inbounds for idx in 1:n_codes
        lut[idx] = _kmer_rc_code(UInt32(idx - 1), k)
    end
    _RC_LUT_CACHE[k] = lut
    return lut
end

"""
    count_kmer_codes_circular(seq::LongDNA, k::Int) -> Vector{Int32}

Count all k-mers in a circular DNA sequence using a 2-bit encoding.

Returns a dense count vector of length 4^k, indexed by k-mer code + 1.
"""
function count_kmer_codes_circular(seq::LongDNA, k::Int)::Vector{Int32}
    n = length(seq)
    n < k && return Int32[]

    n_codes = 1 << (2 * k)  # 4^k
    counts = zeros(Int32, n_codes)

    mask = UInt32(n_codes - 1)
    code = UInt32(0)

    # Seed first k-mer at start position 1
    @inbounds for i in 1:k
        code = (code << 2) | _kmer_base_to_2bit(seq[i])
    end
    counts[Int(code) + 1] += 1

    # Rolling update for start positions 2..n (circular wrap)
    @inbounds for start in 2:n
        next_pos = start + k - 1
        base = _kmer_base_to_2bit(next_pos <= n ? seq[next_pos] : seq[next_pos - n])
        code = ((code << 2) & mask) | base
        counts[Int(code) + 1] += 1
    end

    return counts
end

"""
    KmerInversionResult

Results from k-mer inversion symmetry analysis.
"""
struct KmerInversionResult
    k::Int
    x_k::Float64  # Inversion symmetry score [0, 1]
    k_l_tau_05::Int  # K_L at tau=0.05
    k_l_tau_10::Int  # K_L at tau=0.10
    total_kmers::Int
    symmetric_kmers::Int  # k-mers with N(w) == N(RC(w))
end

"""
    compute_kmer_inversion_for_k(seq::LongDNA, k::Int; eps::Float64=1e-10) -> KmerInversionResult

Compute k-mer inversion symmetry for a specific k.

# Arguments
- `seq`: DNA sequence to analyze
- `k`: k-mer length
- `eps`: Small epsilon to avoid division by zero

# Returns
KmerInversionResult with X_k, K_L statistics.

# Definition
X_k = mean_w |N(w) - N(RC(w))| / (N(w) + N(RC(w)) + ε)

where:
- N(w) is the count of k-mer w
- RC(w) is the reverse complement of w
- The mean is over all distinct k-mers (considering w and RC(w) as a pair)

# Validity
- X_k ∈ [0, 1]
- X_k = 0: Perfect RC symmetry (Chargaff's second parity rule)
- X_k = 1: Maximum asymmetry
"""
function compute_kmer_inversion_for_k(seq::LongDNA, k::Int; eps::Float64=1e-10)::KmerInversionResult
    n = length(seq)
    if n < k
        return KmerInversionResult(k, 1.0, 0, 0, 0, 0)
    end

    # Dense circular k-mer counts (2-bit encoding)
    counts = count_kmer_codes_circular(seq, k)
    lut = _rc_lut(k)

    sum_asym = 0.0
    total_pairs = 0
    symmetric_count = 0
    k_l_tau_05 = 0
    k_l_tau_10 = 0

    n_codes = length(counts)
    @inbounds for idx in 1:n_codes
        code = UInt32(idx - 1)
        rc = lut[idx]
        code > rc && continue  # process each (w, RC(w)) pair once

        count_w = Int(counts[idx])
        count_rc = Int(counts[Int(rc) + 1])
        total = count_w + count_rc
        total == 0 && continue

        total_pairs += 1
        asym = abs(count_w - count_rc) / (total + eps)
        sum_asym += asym

        asym < eps && (symmetric_count += 1)
        asym > 0.05 && (k_l_tau_05 += 1)
        asym > 0.10 && (k_l_tau_10 += 1)
    end

    x_k = total_pairs == 0 ? 1.0 : (sum_asym / total_pairs)

    return KmerInversionResult(
        k,
        x_k,
        k_l_tau_05,
        k_l_tau_10,
        total_pairs,
        symmetric_count
    )
end

"""
    compute_kmer_inversion(seq::LongDNA, k_max::Int=10; replichore::Union{String, Nothing}=nothing) -> DataFrame

Compute k-mer inversion symmetry for k = 1 to k_max.

# Arguments
- `seq`: DNA sequence to analyze
- `k_max`: Maximum k-mer length (default: 10)
- `replichore`: Optional label ("whole", "leading", "lagging") for provenance

# Returns
DataFrame with columns:
- `k`: k-mer length
- `x_k`: Inversion symmetry score [0, 1]
- `k_l_tau_05`: Number of k-mer pairs with asymmetry > 0.05
- `k_l_tau_10`: Number of k-mer pairs with asymmetry > 0.10
- `total_kmers`: Total number of distinct k-mer pairs
- `symmetric_kmers`: Number of symmetric k-mer pairs
- `replichore`: Replichore label (if provided)

# Validity Constraints
- x_k ∈ [0, 1]
- k_l_tau_05 ≥ 0, k_l_tau_10 ≥ 0
- k_l_tau_05 ≥ k_l_tau_10 ≥ 0
- k_l_tau_10 ≤ total_kmers
"""
function compute_kmer_inversion(
    seq::LongDNA,
    k_max::Int=10;
    replichore::Union{String, Nothing}=nothing
)::DataFrame
    results = KmerInversionResult[]

    for k in 1:k_max
        result = compute_kmer_inversion_for_k(seq, k)
        push!(results, result)
    end

    # Build DataFrame
    df = DataFrame(
        k=[r.k for r in results],
        x_k=[r.x_k for r in results],
        k_l_tau_05=[r.k_l_tau_05 for r in results],
        k_l_tau_10=[r.k_l_tau_10 for r in results],
        total_kmers=[r.total_kmers for r in results],
        symmetric_kmers=[r.symmetric_kmers for r in results]
    )

    if replichore !== nothing
        df.replichore = fill(replichore, nrow(df))
    end

    # Validate ranges
    @assert all(0.0 .<= df.x_k .<= 1.0) "x_k must be in [0, 1]"
    @assert all(df.k_l_tau_05 .>= 0) "k_l_tau_05 must be >= 0"
    @assert all(df.k_l_tau_10 .>= 0) "k_l_tau_10 must be >= 0"
    # Note: k_l_tau_05 can be > k_l_tau_10 if there are k-mers with asymmetry between 0.05 and 0.10
    # Actually, k_l_tau_05 should be >= k_l_tau_10 (more restrictive threshold = fewer k-mers)
    # So the assertion should be: k_l_tau_05 >= k_l_tau_10
    @assert all(df.k_l_tau_05 .>= df.k_l_tau_10) "k_l_tau_05 must be >= k_l_tau_10 (more restrictive threshold)"
    @assert all(df.k_l_tau_10 .<= df.total_kmers) "k_l_tau_10 must be <= total_kmers"

    return df
end

"""
    compute_kmer_inversion_batch(records::Vector{Tuple{String, LongDNA}}, k_max::Int=10) -> DataFrame

Compute k-mer inversion for multiple sequences.

# Arguments
- `records`: Vector of (replicon_id, sequence) tuples
- `k_max`: Maximum k-mer length

# Returns
DataFrame with all results, including `replicon_id` column.
"""
function compute_kmer_inversion_batch(
    records::Vector{Tuple{String, LongDNA}},
    k_max::Int=10
)::DataFrame
    if isempty(records)
        return DataFrame(
            replicon_id=String[],
            k=Int[],
            x_k=Float64[],
            k_l_tau_05=Int[],
            k_l_tau_10=Int[],
            total_kmers=Int[],
            symmetric_kmers=Int[],
            replichore=String[]
        )
    end

    all_results = DataFrame[]

    for (replicon_id, seq) in records
        df = compute_kmer_inversion(seq, k_max; replichore="whole")
        df.replicon_id = fill(replicon_id, nrow(df))
        push!(all_results, df)
    end

    return isempty(all_results) ? DataFrame() : vcat(all_results...)
end
