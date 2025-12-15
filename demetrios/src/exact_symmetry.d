/// Exact Symmetry Analysis
///
/// Computation of orbit sizes, fixed points, and symmetry detection
/// under the dihedral group action.

module exact_symmetry;

use operators::{shift, reverse, complement, reverse_complement, Sequence};
use std.collections.HashSet;

/// Compute the orbit of a sequence under the dihedral group D_n
/// Returns all distinct transforms: {S^k(w), R∘S^k(w)} for k in 0..n
pub fn compute_orbit(seq: &Sequence) -> HashSet<Sequence> {
    let n = seq.len();
    let mut orbit = HashSet::new();

    let rev = reverse(seq);

    for k in 0..n {
        orbit.insert(shift(seq, k));
        orbit.insert(shift(&rev, k));
    }

    orbit
}

/// Size of the orbit under D_n action
/// Divides 2n; possible values depend on symmetries
#[inline]
pub fn orbit_size(seq: &Sequence) -> usize {
    compute_orbit(seq).len()
}

/// Orbit ratio: |orbit| / (2n)
/// Range: [1/(2n), 1.0]
/// Lower values indicate higher symmetry
#[inline]
pub fn orbit_ratio(seq: &Sequence) -> f64 {
    let n = seq.len();
    if n == 0 { return 1.0; }
    orbit_size(seq) as f64 / (2 * n) as f64
}

/// Check if sequence is a palindrome (fixed under R)
/// R(w) = w
#[inline]
pub fn is_palindrome(seq: &Sequence) -> bool {
    *seq == reverse(seq)
}

/// Check if sequence is fixed under reverse complement
/// RC(w) = w
#[inline]
pub fn is_rc_fixed(seq: &Sequence) -> bool {
    *seq == reverse_complement(seq)
}

/// Check if sequence has k-fold rotational symmetry
/// S^k(w) = w for some k | n
pub fn rotational_period(seq: &Sequence) -> usize {
    let n = seq.len();
    if n == 0 { return 1; }

    for k in 1..=n {
        if n % k == 0 && shift(seq, k) == *seq {
            return k;
        }
    }
    n
}

/// Compute symmetry statistics for a sequence
pub struct SymmetryStats {
    pub length: usize,
    pub orbit_size: usize,
    pub orbit_ratio: f64,
    pub is_palindrome: bool,
    pub is_rc_fixed: bool,
    pub rotational_period: usize,
}

pub fn compute_symmetry_stats(seq: &Sequence) -> SymmetryStats {
    SymmetryStats {
        length: seq.len(),
        orbit_size: orbit_size(seq),
        orbit_ratio: orbit_ratio(seq),
        is_palindrome: is_palindrome(seq),
        is_rc_fixed: is_rc_fixed(seq),
        rotational_period: rotational_period(seq),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use operators::{A, C, G, T};

    #[test]
    fn test_palindrome_detection() {
        // ACGT reversed is TGCA, not palindrome
        assert!(!is_palindrome(&[A, C, G, T]));
        // ACCA reversed is ACCA, palindrome
        assert!(is_palindrome(&[A, C, C, A]));
    }

    #[test]
    fn test_rc_fixed() {
        // ACGT: RC = complement(TGCA) = ACGT, so RC-fixed
        assert!(is_rc_fixed(&[A, C, G, T]));
    }

    #[test]
    fn test_orbit_bounds() {
        let seq = [A, C, G, T];
        let n = seq.len();
        let os = orbit_size(&seq);
        assert!(os >= 1);
        assert!(os <= 2 * n);
    }
}
