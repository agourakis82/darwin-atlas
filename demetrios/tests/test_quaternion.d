/// Tests for quaternion lift and dicyclic groups

module test_quaternion;

use quaternion::{Quaternion, DicyclicGroup, dicyclic_element, verify_double_cover};

#[test]
fn test_quaternion_identity() {
    let id = Quaternion::identity();
    let q = Quaternion::new(1.0, 2.0, 3.0, 4.0);
    assert!(id.mul(&q).approx_eq(&q, 1e-10));
}

#[test]
fn test_dicyclic_order() {
    let g = DicyclicGroup::new(4);
    assert_eq!(g.order(), 16);
}

#[test]
fn test_double_cover() {
    for n in 2..=8 {
        let g = DicyclicGroup::new(n);
        assert!(verify_double_cover(&g));
    }
}

#[test]
fn test_generator_relations() {
    let g = DicyclicGroup::new(4);

    // a^{2n} = 1
    let a = dicyclic_element(&g, 1, false);
    let mut a_power = a;
    for _ in 1..8 {
        a_power = a_power.q.mul(&a.q);
    }
    assert!(a_power.q.approx_eq(&Quaternion::identity(), 1e-10));

    // b^2 = a^n
    let b = dicyclic_element(&g, 0, true);
    let b2 = DicyclicElement { q: b.q.mul(&b.q) };
    let an = dicyclic_element(&g, g.n, false);
    assert!(b2.q.approx_eq(&an.q, 1e-10));
}
