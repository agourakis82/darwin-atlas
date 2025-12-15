"""
    ExactSymmetry.jl

Exact symmetry analysis under the dihedral group action.

Computes orbit sizes, fixed points, and symmetry detection.
"""

using BioSequences: LongDNA

"""
    compute_orbit(seq::LongDNA) -> Set{LongDNA}

Compute the orbit of a sequence under the dihedral group D_n.

The orbit consists of all sequences obtainable by applying
shifts S^k and reverse-shifts R∘S^k.

# Returns
Set of all distinct transforms of the input sequence.
"""
function compute_orbit(seq::LongDNA)::Set{LongDNA}
    n = length(seq)
    orbit = Set{LongDNA}()

    rev = reverse_seq(seq)

    for k in 0:n-1
        push!(orbit, shift(seq, k))
        push!(orbit, shift(rev, k))
    end

    return orbit
end

"""
    orbit_size(seq::LongDNA) -> Int

Compute the size of the orbit under D_n action.

The orbit size divides 2n. Possible values depend on symmetries:
- 2n: No symmetry (generic sequence)
- n: Palindrome (R-fixed) but not rotationally symmetric
- 2n/k: k-fold rotational symmetry
- 1: Only possible for n=1

# Examples
```julia
seq = dna"ACGT"
orbit_size(seq)  # Depends on symmetries present
```
"""
function orbit_size(seq::LongDNA)::Int
    return length(compute_orbit(seq))
end

"""
    orbit_ratio(seq::LongDNA) -> Float64

Compute normalized orbit size: |orbit| / (2n).

Range: [1/(2n), 1.0]
- Values near 1.0 indicate low symmetry
- Values near 0 indicate high symmetry

This is the primary symmetry metric for the atlas.
"""
function orbit_ratio(seq::LongDNA)::Float64
    n = length(seq)
    n == 0 && return 1.0
    return orbit_size(seq) / (2 * n)
end

"""
    is_palindrome(seq::LongDNA) -> Bool

Check if sequence is a palindrome (fixed under reverse).

R(w) = w

# Examples
```julia
is_palindrome(dna"ACCA")  # true (reads same forwards and backwards)
is_palindrome(dna"ACGT")  # false
```
"""
function is_palindrome(seq::LongDNA)::Bool
    return seq == reverse_seq(seq)
end

"""
    is_rc_fixed(seq::LongDNA) -> Bool

Check if sequence is fixed under reverse complement.

RC(w) = w

Such sequences are their own complement when read in reverse,
a property important for double-stranded DNA biology.

# Examples
```julia
is_rc_fixed(dna"ACGT")  # true: RC(ACGT) = complement(TGCA) = ACGT
```
"""
function is_rc_fixed(seq::LongDNA)::Bool
    return seq == rev_comp(seq)
end

"""
    rotational_period(seq::LongDNA) -> Int

Find the minimal rotational period of the sequence.

Returns the smallest k > 0 such that S^k(w) = w.
If no such k < n exists, returns n.

# Examples
```julia
rotational_period(dna"ACGTACGT")  # 4 (repeats with period 4)
rotational_period(dna"ACGT")      # 4 (no repetition)
```
"""
function rotational_period(seq::LongDNA)::Int
    n = length(seq)
    n == 0 && return 1

    for k in 1:n-1
        if shift(seq, k) == seq
            return k
        end
    end

    return n
end

"""
    compute_symmetry_stats(seq::LongDNA) -> SymmetryStats

Compute comprehensive symmetry statistics for a sequence.

# Returns
`SymmetryStats` struct containing:
- `length`: Sequence length
- `orbit_size`: Size of dihedral orbit
- `orbit_ratio`: Normalized orbit size
- `is_palindrome`: Whether R-fixed
- `is_rc_fixed`: Whether RC-fixed
- `rotational_period`: Minimal period under shifts
"""
function compute_symmetry_stats(seq::LongDNA)::SymmetryStats
    return SymmetryStats(
        length(seq),
        orbit_size(seq),
        orbit_ratio(seq),
        is_palindrome(seq),
        is_rc_fixed(seq),
        rotational_period(seq)
    )
end
