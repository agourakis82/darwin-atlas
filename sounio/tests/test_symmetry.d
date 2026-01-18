/// Tests for exact and approximate symmetry

module test_symmetry;

use exact_symmetry::{orbit_size, orbit_ratio, is_palindrome, is_rc_fixed};
use approx_metric::{dmin, dmin_normalized};
use operators::{A, C, G, T};

#[test]
fn test_orbit_bounds() {
    let seq = [A, C, G, T];
    let n = seq.len();
    let os = orbit_size(&seq);

    assert!(os >= 1);
    assert!(os <= 2 * n);
}

#[test]
fn test_palindrome_detection() {
    assert!(!is_palindrome(&[A, C, G, T]));
    assert!(is_palindrome(&[A, C, C, A]));
}

#[test]
fn test_rc_fixed() {
    // ACGT: RC = complement(TGCA) = ACGT
    assert!(is_rc_fixed(&[A, C, G, T]));
}

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
    assert_eq!(d, 0);
}
