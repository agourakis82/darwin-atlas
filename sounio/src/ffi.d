/// FFI Exports for Julia Integration
///
/// C ABI functions callable from Julia via ccall.
/// All exported functions use primitive types and raw pointers.

module ffi;

use operators::{shift, reverse, complement, reverse_complement, hamming_distance, Base, Sequence};
use exact_symmetry::{orbit_size, orbit_ratio, is_palindrome, is_rc_fixed};
use approx_metric::{dmin, dmin_normalized};
use quaternion::{DicyclicGroup, verify_double_cover};

// ============================================================================
// Operator FFI
// ============================================================================

/// Compute Hamming distance between two sequences
///
/// # Safety
/// - `seq_a` and `seq_b` must point to valid memory of length `len`
/// - Both sequences must have the same length
#[export]
#[no_mangle]
pub extern "C" fn darwin_hamming_distance(
    seq_a: *const u8,
    seq_b: *const u8,
    len: usize,
) -> usize {
    unsafe {
        let a = std::slice::from_raw_parts(seq_a, len);
        let b = std::slice::from_raw_parts(seq_b, len);

        a.iter().zip(b.iter()).filter(|(x, y)| x != y).count()
    }
}

// ============================================================================
// Exact Symmetry FFI
// ============================================================================

/// Compute orbit size under dihedral group
#[export]
#[no_mangle]
pub extern "C" fn darwin_orbit_size(
    seq: *const u8,
    len: usize,
) -> usize {
    unsafe {
        let s = std::slice::from_raw_parts(seq, len);
        // Convert u8 to Base (2-bit)
        let bases: Vec<Base> = s.iter().map(|&b| (b & 0x03) as Base).collect();
        orbit_size(&bases)
    }
}

/// Compute orbit ratio
#[export]
#[no_mangle]
pub extern "C" fn darwin_orbit_ratio(
    seq: *const u8,
    len: usize,
) -> f64 {
    unsafe {
        let s = std::slice::from_raw_parts(seq, len);
        let bases: Vec<Base> = s.iter().map(|&b| (b & 0x03) as Base).collect();
        orbit_ratio(&bases)
    }
}

/// Check if sequence is palindrome
#[export]
#[no_mangle]
pub extern "C" fn darwin_is_palindrome(
    seq: *const u8,
    len: usize,
) -> bool {
    unsafe {
        let s = std::slice::from_raw_parts(seq, len);
        let bases: Vec<Base> = s.iter().map(|&b| (b & 0x03) as Base).collect();
        is_palindrome(&bases)
    }
}

/// Check if sequence is RC-fixed
#[export]
#[no_mangle]
pub extern "C" fn darwin_is_rc_fixed(
    seq: *const u8,
    len: usize,
) -> bool {
    unsafe {
        let s = std::slice::from_raw_parts(seq, len);
        let bases: Vec<Base> = s.iter().map(|&b| (b & 0x03) as Base).collect();
        is_rc_fixed(&bases)
    }
}

// ============================================================================
// Approximate Metric FFI
// ============================================================================

/// Compute d_min (minimum dihedral distance)
#[export]
#[no_mangle]
pub extern "C" fn darwin_dmin(
    seq: *const u8,
    len: usize,
    include_rc: bool,
) -> usize {
    unsafe {
        let s = std::slice::from_raw_parts(seq, len);
        let bases: Vec<Base> = s.iter().map(|&b| (b & 0x03) as Base).collect();
        dmin(&bases, include_rc)
    }
}

/// Compute normalized d_min
#[export]
#[no_mangle]
pub extern "C" fn darwin_dmin_normalized(
    seq: *const u8,
    len: usize,
    include_rc: bool,
) -> f64 {
    unsafe {
        let s = std::slice::from_raw_parts(seq, len);
        let bases: Vec<Base> = s.iter().map(|&b| (b & 0x03) as Base).collect();
        dmin_normalized(&bases, include_rc)
    }
}

// ============================================================================
// Quaternion FFI
// ============================================================================

/// Verify dicyclic double cover property
#[export]
#[no_mangle]
pub extern "C" fn darwin_verify_double_cover(n: usize) -> bool {
    let g = DicyclicGroup::new(n);
    verify_double_cover(&g)
}

// ============================================================================
// Version Info
// ============================================================================

/// Get library version string
#[export]
#[no_mangle]
pub extern "C" fn darwin_version() -> *const u8 {
    b"0.1.0\0".as_ptr()
}
