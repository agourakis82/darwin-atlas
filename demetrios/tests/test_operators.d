/// Tests for genomic operators

module test_operators;

use operators::{shift, reverse, complement, reverse_complement, A, C, G, T};

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

#[test]
fn test_dihedral_relation() {
    let seq = [A, C, G, T, A, C, G, T, A, A];
    let n = seq.len();

    for k in 1..5 {
        let lhs = reverse(&shift(&seq, k));
        let rhs = shift(&reverse(&seq), n - k);
        assert_eq!(lhs, rhs);
    }
}
