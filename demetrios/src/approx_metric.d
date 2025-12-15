/// Approximate Symmetry Metric
///
/// Computation of d_min/L: minimum normalized Hamming distance
/// to any non-identity dihedral transform.

module approx_metric;

use operators::{shift, reverse, reverse_complement, hamming_distance, Sequence};

/// Minimum distance to any non-identity transform in the dihedral group
/// d_min(w) = min_{g ∈ D_n \ {id}} H(w, g(w))
///
/// Transforms tested:
/// - S^k for k in 1..n (cyclic shifts, excluding identity)
/// - R∘S^k for k in 0..n (reverse then shift)
/// - RC∘S^k for k in 0..n (reverse complement then shift, if include_rc)
pub fn dmin(seq: &Sequence, include_rc: bool) -> usize {
    let n = seq.len();
    if n == 0 { return 0; }

    let mut min_dist = n;  // Maximum possible

    // S^k transforms (k=1..n-1, excluding identity k=0)
    for k in 1..n {
        let shifted = shift(seq, k);
        let d = hamming_distance(seq, &shifted);
        min_dist = min_dist.min(d);
    }

    // R∘S^k transforms (k=0..n-1)
    let rev = reverse(seq);
    for k in 0..n {
        let shifted_rev = shift(&rev, k);
        let d = hamming_distance(seq, &shifted_rev);
        min_dist = min_dist.min(d);
    }

    // RC∘S^k transforms (optional)
    if include_rc {
        let rc = reverse_complement(seq);
        for k in 0..n {
            let shifted_rc = shift(&rc, k);
            let d = hamming_distance(seq, &shifted_rc);
            min_dist = min_dist.min(d);
        }
    }

    min_dist
}

/// Normalized d_min: d_min / L
/// Range: [0, 1] where 0 = exact symmetry, 1 = maximum asymmetry
#[inline]
pub fn dmin_normalized(seq: &Sequence, include_rc: bool) -> f64 {
    let n = seq.len();
    if n == 0 { return 0.0; }
    dmin(seq, include_rc) as f64 / n as f64
}

/// Identify which transform achieves d_min
pub enum NearestTransform {
    Shift(usize),           // S^k
    ReverseShift(usize),    // R∘S^k
    RCShift(usize),         // RC∘S^k
}

pub fn nearest_transform(seq: &Sequence, include_rc: bool) -> (usize, NearestTransform) {
    let n = seq.len();
    if n == 0 { return (0, NearestTransform::Shift(0)); }

    let mut min_dist = n;
    let mut nearest = NearestTransform::Shift(1);

    // S^k transforms
    for k in 1..n {
        let d = hamming_distance(seq, &shift(seq, k));
        if d < min_dist {
            min_dist = d;
            nearest = NearestTransform::Shift(k);
        }
    }

    // R∘S^k transforms
    let rev = reverse(seq);
    for k in 0..n {
        let d = hamming_distance(seq, &shift(&rev, k));
        if d < min_dist {
            min_dist = d;
            nearest = NearestTransform::ReverseShift(k);
        }
    }

    // RC∘S^k transforms
    if include_rc {
        let rc = reverse_complement(seq);
        for k in 0..n {
            let d = hamming_distance(seq, &shift(&rc, k));
            if d < min_dist {
                min_dist = d;
                nearest = NearestTransform::RCShift(k);
            }
        }
    }

    (min_dist, nearest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use operators::{A, C, G, T};

    #[test]
    fn test_dmin_bounds() {
        let seq = [A, C, G, T];
        let d = dmin(&seq, true);
        assert!(d <= seq.len());
    }

    #[test]
    fn test_dmin_normalized_range() {
        let seq = [A, C, G, T, A, C, G, T];
        let dn = dmin_normalized(&seq, true);
        assert!(dn >= 0.0);
        assert!(dn <= 1.0);
    }

    #[test]
    fn test_periodic_sequence() {
        // ACGTACGT has shift symmetry S^4 = id
        let seq = [A, C, G, T, A, C, G, T];
        let d = dmin(&seq, false);
        assert_eq!(d, 0);  // S^4(seq) = seq
    }
}
