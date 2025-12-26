"""
    SymmetrySpectrum.jl

Compute symmetry spectrum and summary features for a sequence.
"""

using BioSequences: LongDNA
using Statistics

export symmetry_spectrum, symmetry_spectrum_summary
export spectrum_entropy, spectrum_peakiness

function symmetry_spectrum(seq::LongDNA; include_rc::Bool=false)
    n = length(seq)
    shifts = Vector{Int}(undef, n)
    revs = Vector{Int}(undef, n)
    rcs = include_rc ? Vector{Int}(undef, n) : Int[]

    if n == 0
        return (shift=shifts, rev=revs, rc=rcs)
    end

    if isdefined(@__MODULE__, :HAS_DEMETRIOS) && HAS_DEMETRIOS[] &&
       isdefined(@__MODULE__, :demetrios_hamming_distance_batch) &&
       (!isdefined(@__MODULE__, :DEMETRIOS_BATCH_ENABLED) || DEMETRIOS_BATCH_ENABLED[])
        seqs_a = Vector{LongDNA}(undef, n)
        shifts_seq = Vector{LongDNA}(undef, n)
        revs_seq = Vector{LongDNA}(undef, n)
        rcs_seq = include_rc ? Vector{LongDNA}(undef, n) : LongDNA[]

        fill!(seqs_a, seq)

        for k in 0:(n - 1)
            s = shift(seq, k)
            shifts_seq[k + 1] = s
            revs_seq[k + 1] = reverse_seq(s)
            if include_rc
                rcs_seq[k + 1] = rev_comp(s)
            end
        end

        shifts_u = demetrios_hamming_distance_batch(seqs_a, shifts_seq)
        revs_u = demetrios_hamming_distance_batch(seqs_a, revs_seq)
        for i in 1:n
            shifts[i] = Int(shifts_u[i])
            revs[i] = Int(revs_u[i])
        end

        if include_rc
            rcs_u = demetrios_hamming_distance_batch(seqs_a, rcs_seq)
            for i in 1:n
                rcs[i] = Int(rcs_u[i])
            end
        end

        return (shift=shifts, rev=revs, rc=rcs)
    end

    for k in 0:(n - 1)
        s = shift(seq, k)
        shifts[k + 1] = hamming_distance_fast(seq, s)
        revs[k + 1] = hamming_distance_fast(seq, reverse_seq(s))
        if include_rc
            rcs[k + 1] = hamming_distance_fast(seq, rev_comp(s))
        end
    end

    return (shift=shifts, rev=revs, rc=rcs)
end

function spectrum_entropy(distances::AbstractVector{<:Real})
    if isempty(distances)
        return 0.0
    end
    maxv = maximum(distances)
    maxv == 0 && return 0.0
    bins = zeros(Int, maxv + 1)
    for v in distances
        bins[Int(v) + 1] += 1
    end
    probs = bins ./ sum(bins)
    entropy = 0.0
    for p in probs
        p == 0 && continue
        entropy -= p * log2(p)
    end
    return entropy
end

function spectrum_peakiness(distances::AbstractVector{<:Real})
    if isempty(distances)
        return 0.0
    end
    μ = mean(distances)
    σ = std(distances)
    σ == 0 && return 0.0
    return (maximum(distances) - μ) / σ
end

"""
    symmetry_spectrum_summary(seq; include_rc=false) -> NamedTuple

Compute summary features for shift/reverse (and optional RC) spectra.
"""
function symmetry_spectrum_summary(seq::LongDNA; include_rc::Bool=false)
    spec = symmetry_spectrum(seq; include_rc=include_rc)

    shift_min = minimum(spec.shift)
    shift_argmin = findfirst(==(shift_min), spec.shift) - 1
    shift_entropy = spectrum_entropy(spec.shift)
    shift_peak = spectrum_peakiness(spec.shift)

    rev_min = minimum(spec.rev)
    rev_argmin = findfirst(==(rev_min), spec.rev) - 1
    rev_entropy = spectrum_entropy(spec.rev)
    rev_peak = spectrum_peakiness(spec.rev)

    rc_min = include_rc ? minimum(spec.rc) : missing
    rc_argmin = include_rc ? (findfirst(==(rc_min), spec.rc) - 1) : missing
    rc_entropy = include_rc ? spectrum_entropy(spec.rc) : missing
    rc_peak = include_rc ? spectrum_peakiness(spec.rc) : missing

    return (
        shift_min=shift_min,
        shift_argmin=shift_argmin,
        shift_entropy=shift_entropy,
        shift_peakiness=shift_peak,
        rev_min=rev_min,
        rev_argmin=rev_argmin,
        rev_entropy=rev_entropy,
        rev_peakiness=rev_peak,
        rc_min=rc_min,
        rc_argmin=rc_argmin,
        rc_entropy=rc_entropy,
        rc_peakiness=rc_peak
    )
end
