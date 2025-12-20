/// FFI Exports for Julia Integration
///
/// C ABI functions callable from Julia via ccall.
/// All exported functions use primitive types and raw pointers.

module ffi;

// NOTE: Keep this module pointer-only; Vec/method calls currently panic in codegen.

// ============================================================================
// Pointer helpers
// ============================================================================

fn complement_base(b: u8) -> u8 {
    return b ^ 3
}

fn read_at(ptr: *const u8, idx: usize) -> u8 {
    return ptr[idx as i64]
}

fn shift_index(idx: usize, shift: usize, len: usize) -> usize {
    var pos = idx + shift;
    if pos >= len {
        pos = pos - len;
    }
    return pos
}

fn shift_value(ptr: *const u8, len: usize, shift: usize, idx: usize) -> u8 {
    let pos = shift_index(idx, shift, len);
    return read_at(ptr, pos)
}

fn rev_shift_value(ptr: *const u8, len: usize, shift: usize, idx: usize) -> u8 {
    let pos = shift_index(idx, shift, len);
    let rev_idx = len - 1 - pos;
    return read_at(ptr, rev_idx)
}

fn rc_shift_value(ptr: *const u8, len: usize, shift: usize, idx: usize) -> u8 {
    return complement_base(rev_shift_value(ptr, len, shift, idx))
}

// ============================================================================
// Core computations (pointer-only, no Vec)
// ============================================================================

fn hamming_distance_ptr(a_ptr: *const u8, b_ptr: *const u8, len: usize) -> usize {
    var count: usize = 0;
    var i: usize = 0;
    while i < len {
        if read_at(a_ptr, i) != read_at(b_ptr, i) {
            count = count + 1;
        }
        i = i + 1;
    }
    return count
}

fn hamming_distance_shift(ptr: *const u8, len: usize, shift: usize) -> usize {
    var count: usize = 0;
    var i: usize = 0;
    while i < len {
        if read_at(ptr, i) != shift_value(ptr, len, shift, i) {
            count = count + 1;
        }
        i = i + 1;
    }
    return count
}

fn hamming_distance_rev_shift(ptr: *const u8, len: usize, shift: usize) -> usize {
    var count: usize = 0;
    var i: usize = 0;
    while i < len {
        if read_at(ptr, i) != rev_shift_value(ptr, len, shift, i) {
            count = count + 1;
        }
        i = i + 1;
    }
    return count
}

fn hamming_distance_rc_shift(ptr: *const u8, len: usize, shift: usize) -> usize {
    var count: usize = 0;
    var i: usize = 0;
    while i < len {
        if read_at(ptr, i) != rc_shift_value(ptr, len, shift, i) {
            count = count + 1;
        }
        i = i + 1;
    }
    return count
}

fn eq_shift_shift(ptr: *const u8, len: usize, k1: usize, k2: usize) -> bool {
    var i: usize = 0;
    while i < len {
        if shift_value(ptr, len, k1, i) != shift_value(ptr, len, k2, i) {
            return false
        }
        i = i + 1;
    }
    return true
}

fn eq_shift_rev(ptr: *const u8, len: usize, k_shift: usize, k_rev: usize) -> bool {
    var i: usize = 0;
    while i < len {
        if shift_value(ptr, len, k_shift, i) != rev_shift_value(ptr, len, k_rev, i) {
            return false
        }
        i = i + 1;
    }
    return true
}

fn eq_rev_rev(ptr: *const u8, len: usize, k1: usize, k2: usize) -> bool {
    var i: usize = 0;
    while i < len {
        if rev_shift_value(ptr, len, k1, i) != rev_shift_value(ptr, len, k2, i) {
            return false
        }
        i = i + 1;
    }
    return true
}

fn orbit_size_ptr(ptr: *const u8, len: usize) -> usize {
    if len == 0 {
        return 1
    }

    var count: usize = 0;

    // Process all 2n transforms in order: S^0, S^1, ..., S^{n-1}, R∘S^0, R∘S^1, ..., R∘S^{n-1}
    // For each transform, check if it's equal to any previously seen transform
    
    // First, process all shifts S^k (k from 0 to n-1)
    var k: usize = 0;
    while k < len {
        var is_new = true;
        
        // Check against all previously processed transforms
        // 1. Check against previous shifts S^j (j < k)
        var j: usize = 0;
        while j < k {
            if eq_shift_shift(ptr, len, k, j) {
                is_new = false;
                j = k;
            } else {
                j = j + 1;
            }
        }
        
        if is_new {
            count = count + 1;
        }
        k = k + 1;
    }

    // Then, process all reverse shifts R∘S^k (k from 0 to n-1)
    // Check each against ALL previously seen transforms (all S^j AND previous R∘S^j)
    k = 0;
    while k < len {
        var is_new = true;
        
        // Check against ALL shifts S^j (all n shifts have been processed)
        var j: usize = 0;
        while j < len {
            if eq_shift_rev(ptr, len, j, k) {
                is_new = false;
                j = len;
            } else {
                j = j + 1;
            }
        }
        
        // Check against previous reverse shifts R∘S^j (j < k)
        if is_new {
            j = 0;
            while j < k {
                if eq_rev_rev(ptr, len, k, j) {
                    is_new = false;
                    j = k;
                } else {
                    j = j + 1;
                }
            }
        }

        if is_new {
            count = count + 1;
        }
        k = k + 1;
    }

    return count
}

fn is_palindrome_ptr(ptr: *const u8, len: usize) -> bool {
    var i: usize = 0;
    while i < len {
        if read_at(ptr, i) != read_at(ptr, len - 1 - i) {
            return false
        }
        i = i + 1;
    }
    return true
}

fn is_rc_fixed_ptr(ptr: *const u8, len: usize) -> bool {
    var i: usize = 0;
    while i < len {
        if read_at(ptr, i) != complement_base(read_at(ptr, len - 1 - i)) {
            return false
        }
        i = i + 1;
    }
    return true
}

fn dmin_ptr(ptr: *const u8, len: usize, include_rc: bool) -> usize {
    if len == 0 {
        return 0
    }

    var min_dist: usize = len;

    // Shifts (exclude identity)
    var k: usize = 1;
    while k < len {
        let d = hamming_distance_shift(ptr, len, k);
        if d < min_dist {
            min_dist = d;
        }
        k = k + 1;
    }

    // Reverse shifts (include k=0)
    k = 0;
    while k < len {
        let d = hamming_distance_rev_shift(ptr, len, k);
        if d < min_dist {
            min_dist = d;
        }
        k = k + 1;
    }

    if include_rc {
        k = 0;
        while k < len {
            let d = hamming_distance_rc_shift(ptr, len, k);
            if d < min_dist {
                min_dist = d;
            }
            k = k + 1;
        }
    }

    return min_dist
}

// ============================================================================
// Exported C Functions
// ============================================================================

pub extern "C" fn darwin_hamming_distance(seq_a: *const u8, seq_b: *const u8, len: usize) -> usize {
    if len == 0 {
        return 0
    }
    return hamming_distance_ptr(seq_a, seq_b, len)
}

pub extern "C" fn darwin_orbit_size(seq: *const u8, len: usize) -> usize {
    return orbit_size_ptr(seq, len)
}

pub extern "C" fn darwin_orbit_ratio(seq: *const u8, len: usize) -> f64 {
    if len == 0 {
        return 1.0
    }
    let size: f64 = orbit_size_ptr(seq, len) as f64;
    let denom: f64 = (2 * len) as f64;
    return size / denom
}

pub extern "C" fn darwin_is_palindrome(seq: *const u8, len: usize) -> bool {
    if len == 0 {
        return true
    }
    return is_palindrome_ptr(seq, len)
}

pub extern "C" fn darwin_is_rc_fixed(seq: *const u8, len: usize) -> bool {
    if len == 0 {
        return true
    }
    return is_rc_fixed_ptr(seq, len)
}

pub extern "C" fn darwin_dmin(seq: *const u8, len: usize, include_rc: bool) -> usize {
    return dmin_ptr(seq, len, include_rc)
}

pub extern "C" fn darwin_dmin_normalized(seq: *const u8, len: usize, include_rc: bool) -> f64 {
    if len == 0 {
        return 0.0
    }
    let d: f64 = dmin_ptr(seq, len, include_rc) as f64;
    let len_f: f64 = len as f64;
    return d / len_f
}

// Integer-only proof of the double cover in Dic_n without quaternion math.
// Uses the relation: -a^k = a^(k+n), and projection maps k -> k mod n.
pub extern "C" fn darwin_verify_double_cover(n: usize) -> bool {
    if n < 2 {
        return false
    }
    let limit = 2 * n;
    var k: usize = 0;
    while k < limit {
        let proj = k % n;
        let neg_k = (k + n) % limit;
        let proj_neg = neg_k % n;
        if proj != proj_neg {
            return false
        }
        k = k + 1;
    }
    return true
}

// Temporarily disabled - pointer-returning globals not supported in typechecker.
// pub extern "C" fn darwin_version() -> *const u8 {
//     null_ptr()
// }
