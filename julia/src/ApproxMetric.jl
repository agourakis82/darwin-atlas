"""
    ApproxMetric.jl

Approximate symmetry metric: d_min/L computation.

Measures how close a sequence is to having exact dihedral symmetry.
"""

using BioSequences: LongDNA

"""
    dmin(seq::LongDNA; include_rc::Bool=true) -> Int

Compute minimum Hamming distance to any non-identity dihedral transform.

d_min(w) = min_{g ∈ G \\ {id}} H(w, g(w))

where G is the transform group (dihedral or extended with RC).

# Arguments
- `seq`: DNA sequence to analyze
- `include_rc`: Whether to include reverse-complement transforms (default: true)

# Returns
Minimum Hamming distance (0 = exact symmetry under some transform).

# Transforms Tested
- S^k for k ∈ {1, ..., n-1} (cyclic shifts, excluding identity)
- R∘S^k for k ∈ {0, ..., n-1} (reverse then shift)
- RC∘S^k for k ∈ {0, ..., n-1} (reverse complement then shift, if include_rc)
"""
function dmin(seq::LongDNA; include_rc::Bool=true)::Int
    n = length(seq)
    n == 0 && return 0

    min_dist = n  # Maximum possible distance

    # S^k transforms (k = 1 to n-1, excluding identity k=0)
    for k in 1:n-1
        shifted = shift(seq, k)
        d = hamming_distance(seq, shifted)
        min_dist = min(min_dist, d)
    end

    # R∘S^k transforms (k = 0 to n-1)
    rev = reverse_seq(seq)
    for k in 0:n-1
        shifted_rev = shift(rev, k)
        d = hamming_distance(seq, shifted_rev)
        min_dist = min(min_dist, d)
    end

    # RC∘S^k transforms (optional)
    if include_rc
        rc = rev_comp(seq)
        for k in 0:n-1
            shifted_rc = shift(rc, k)
            d = hamming_distance(seq, shifted_rc)
            min_dist = min(min_dist, d)
        end
    end

    return min_dist
end

"""
    dmin_normalized(seq::LongDNA; include_rc::Bool=true) -> Float64

Compute normalized minimum dihedral distance: d_min / L.

Range: [0, 1]
- 0: Exact symmetry under some transform
- 1: Maximum asymmetry (rare in practice)

This is the primary approximate symmetry metric for the atlas.
"""
function dmin_normalized(seq::LongDNA; include_rc::Bool=true)::Float64
    n = length(seq)
    n == 0 && return 0.0
    return dmin(seq; include_rc=include_rc) / n
end

"""
    nearest_transform(seq::LongDNA; include_rc::Bool=true) -> NearestTransform

Find the transform that achieves d_min.

# Returns
`NearestTransform` struct with:
- `family`: Type of transform (SHIFT, REVERSE_SHIFT, or RC_SHIFT)
- `k`: Shift amount
- `distance`: Hamming distance (equals d_min)
"""
function nearest_transform(seq::LongDNA; include_rc::Bool=true)::NearestTransform
    n = length(seq)
    n == 0 && return NearestTransform(SHIFT, 0, 0)

    min_dist = n
    best_family = SHIFT
    best_k = 1

    # S^k transforms
    for k in 1:n-1
        d = hamming_distance(seq, shift(seq, k))
        if d < min_dist
            min_dist = d
            best_family = SHIFT
            best_k = k
        end
    end

    # R∘S^k transforms
    rev = reverse_seq(seq)
    for k in 0:n-1
        d = hamming_distance(seq, shift(rev, k))
        if d < min_dist
            min_dist = d
            best_family = REVERSE_SHIFT
            best_k = k
        end
    end

    # RC∘S^k transforms
    if include_rc
        rc = rev_comp(seq)
        for k in 0:n-1
            d = hamming_distance(seq, shift(rc, k))
            if d < min_dist
                min_dist = d
                best_family = RC_SHIFT
                best_k = k
            end
        end
    end

    return NearestTransform(best_family, best_k, min_dist)
end
