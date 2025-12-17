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
    count_kmers(seq::LongDNA, k::Int) -> Dict{LongDNA, Int}

Count all k-mers in a DNA sequence (circular).

# Arguments
- `seq`: DNA sequence to analyze
- `k`: k-mer length

# Returns
Dictionary mapping k-mer sequences to their counts.
"""
function count_kmers(seq::LongDNA, k::Int)::Dict{LongDNA, Int}
    n = length(seq)
    n < k && return Dict{LongDNA, Int}()

    counts = Dict{LongDNA, Int}()

    # Count k-mers in circular sequence
    for i in 1:n
        kmer_bases = Vector{eltype(seq)}()
        for j in 0:k-1
            pos = mod1(i + j, n)  # Circular indexing
            push!(kmer_bases, seq[pos])
        end
        kmer = LongDNA{4}(kmer_bases)
        counts[kmer] = get(counts, kmer, 0) + 1
    end

    return counts
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

    # Count all k-mers
    kmer_counts = count_kmers(seq, k)

    # Compute asymmetry for each k-mer pair (w, RC(w))
    asymmetries = Float64[]
    total_pairs = 0
    symmetric_count = 0

    processed = Set{LongDNA}()

    for (kmer, count_w) in kmer_counts
        if kmer in processed
            continue
        end

        rc_kmer = reverse_complement(kmer)
        count_rc = get(kmer_counts, rc_kmer, 0)

        # Mark both as processed
        push!(processed, kmer)
        if rc_kmer != kmer  # Avoid double-counting palindromic k-mers
            push!(processed, rc_kmer)
        end

        # Compute asymmetry
        total = count_w + count_rc
        if total > 0
            asymmetry = abs(count_w - count_rc) / (total + eps)
            push!(asymmetries, asymmetry)
            total_pairs += 1

            if asymmetry < eps  # Effectively symmetric
                symmetric_count += 1
            end
        end
    end

    # Compute X_k (mean asymmetry)
    x_k = isempty(asymmetries) ? 1.0 : mean(asymmetries)

    # Compute K_L: number of k-mers with asymmetry > tau
    k_l_tau_05 = count(a -> a > 0.05, asymmetries)
    k_l_tau_10 = count(a -> a > 0.10, asymmetries)

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
