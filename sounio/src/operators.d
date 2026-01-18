/// Genomic Sequence Operators
///
/// Mathematical definitions of operators acting on DNA sequences.
/// These form the generators of the dihedral group D_n.

module operators;

use std.mem;

/// DNA base type with 2-bit encoding
/// A=0b00, C=0b01, G=0b10, T=0b11
type Base = u2;

const A: Base = 0b00;
const C: Base = 0b01;
const G: Base = 0b10;
const T: Base = 0b11;

/// DNA sequence as packed 2-bit array
type Sequence = [Base];

/// Shift operator S: σ(i) = s_{(i+1) mod n}
/// Generates cyclic group C_n
#[inline]
pub fn shift(seq: &Sequence, k: usize) -> Sequence {
    let n = seq.len();
    if n == 0 { return []; }
    let k = k % n;
    seq[k..] ++ seq[..k]
}

/// Reverse operator R: σ(i) = s_{n-1-i}
/// Order 2 element, R^2 = I
#[inline]
pub fn reverse(seq: &Sequence) -> Sequence {
    seq.reverse()
}

/// Complement operator K: σ(i) = complement(s_i)
/// A↔T, C↔G
#[inline]
pub fn complement_base(b: Base) -> Base {
    // XOR with 0b11 swaps A↔T and C↔G
    b ^ 0b11
}

#[inline]
pub fn complement(seq: &Sequence) -> Sequence {
    seq.map(complement_base)
}

/// Reverse complement RC = R ∘ K = K ∘ R
/// Biologically: opposite strand reading
#[inline]
pub fn reverse_complement(seq: &Sequence) -> Sequence {
    complement(reverse(seq))
}

/// Hamming distance between two sequences
#[inline]
pub fn hamming_distance(a: &Sequence, b: &Sequence) -> usize {
    assert!(a.len() == b.len(), "Sequences must have equal length");
    a.zip(b).count(|(x, y)| x != y)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shift_identity() {
        let seq = [A, C, G, T];
        assert_eq!(shift(&seq, 0), seq);
        assert_eq!(shift(&seq, 4), seq);
    }

    #[test]
    fn test_reverse_involution() {
        let seq = [A, C, G, T];
        assert_eq!(reverse(&reverse(&seq)), seq);
    }

    #[test]
    fn test_complement_involution() {
        let seq = [A, C, G, T];
        assert_eq!(complement(&complement(&seq)), seq);
    }

    #[test]
    fn test_rc_composition() {
        let seq = [A, C, G, T];
        assert_eq!(reverse_complement(&seq), complement(&reverse(&seq)));
        assert_eq!(reverse_complement(&seq), reverse(&complement(&seq)));
    }
}
