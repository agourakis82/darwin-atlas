"""
    Operators.jl

Pure Julia implementation of genomic sequence operators (Layer 0).

These operators form the generators of the dihedral group D_n acting on
circular DNA sequences of length n.
"""

using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T, reverse, reverse_complement, complement

"""
    shift(seq::LongDNA, k::Int) -> LongDNA

Cyclic shift operator S^k: moves each position i to (i + k) mod n.

Equivalent to rotating the circular sequence by k positions.
S generates the cyclic group C_n, and S^n = I (identity).

# Examples
```julia
seq = dna"ACGT"
shift(seq, 1)  # Returns dna"CGTA"
shift(seq, 4)  # Returns dna"ACGT" (identity)
```
"""
function shift(seq::LongDNA, k::Int)::LongDNA
    n = length(seq)
    n == 0 && return seq

    k = mod(k, n)
    k == 0 && return copy(seq)

    # Circular shift: [k+1:end] ++ [1:k]
    return seq[k+1:end] * seq[1:k]
end

"""
    reverse_seq(seq::LongDNA) -> LongDNA

Reverse operator R: σ(i) = s_{n-1-i}.

R is an involution: R² = I.
Together with S, generates the dihedral group D_n.

# Examples
```julia
seq = dna"ACGT"
reverse_seq(seq)  # Returns dna"TGCA"
```
"""
function reverse_seq(seq::LongDNA)::LongDNA
    return reverse(seq)
end

"""
    complement_seq(seq::LongDNA) -> LongDNA

Complement operator K: replaces each base with its Watson-Crick complement.
A ↔ T, C ↔ G

K is an involution: K² = I.
K commutes with both S and R.

# Examples
```julia
seq = dna"ACGT"
complement_seq(seq)  # Returns dna"TGCA"
```
"""
function complement_seq(seq::LongDNA)::LongDNA
    return complement(seq)
end

"""
    rev_comp(seq::LongDNA) -> LongDNA

Reverse complement operator RC = R ∘ K = K ∘ R.

Biologically represents the opposite strand of double-stranded DNA.
RC is an involution: RC² = I.

# Examples
```julia
seq = dna"ACGT"
rev_comp(seq)  # Returns dna"ACGT" (this sequence is RC-palindromic)
```
"""
function rev_comp(seq::LongDNA)::LongDNA
    return reverse_complement(seq)
end

"""
    hamming_distance(a::LongDNA, b::LongDNA) -> Int

Compute Hamming distance (number of mismatches) between two sequences.

# Arguments
- `a`: First DNA sequence
- `b`: Second DNA sequence (must have same length as `a`)

# Returns
Number of positions where bases differ.

# Throws
- `AssertionError` if sequences have different lengths
"""
function hamming_distance(a::LongDNA, b::LongDNA)::Int
    @assert length(a) == length(b) "Sequences must have equal length"

    count = 0
    for i in 1:length(a)
        if a[i] != b[i]
            count += 1
        end
    end
    return count
end

"""
    gc_content(seq::LongDNA) -> Float64

Compute GC content (fraction of G and C bases).
"""
function gc_content(seq::LongDNA)::Float64
    n = length(seq)
    n == 0 && return 0.0

    gc_count = count(b -> b == DNA_G || b == DNA_C, seq)
    return gc_count / n
end

"""
    gc_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG) -> LongDNA

Create a GC-preserving shuffled version of the sequence.

Maintains exact base composition while randomizing order.
Used as null model for symmetry statistics.
"""
function gc_shuffle(seq::LongDNA; rng=Random.GLOBAL_RNG)::LongDNA
    bases = collect(seq)
    shuffle!(rng, bases)
    return LongDNA{4}(bases)
end
