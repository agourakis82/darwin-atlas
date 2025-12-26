# Issue: Type inference fails for empty arrays with type aliases

## Summary

The Demetrios compiler fails to infer the correct type for empty arrays (`[]`) when used with type aliases, causing "Type mismatch: expected `[u8; 0]`, found `[u8; 0]`" errors even though the types appear identical.

## Environment

- **Compiler Version**: `dc 0.74.0`
- **Platform**: Linux x86_64

## Problem Description

When using a type alias (e.g., `type Sequence = [u8]`), returning an empty array `[]` from a function that should return the aliased type causes a type mismatch error, even though `[u8; 0]` should be compatible with `[u8]`.

## Steps to Reproduce

### Test Case 1: Simple function with type alias

```d
type Sequence = [u8];

fn test_empty() -> Sequence {
    return []  // Error: Type mismatch
}
```

**Result**:
```
Error: × Type errors:
  │ Type mismatch: expected `[u8; 0]`, found `[u8; 0]`
```

### Test Case 2: Using shift function (which returns [])

```d
type Sequence = [u8];

fn shift(seq: &Sequence, k: usize) -> Sequence {
    let n = seq.len()
    if n == 0 { return [] }  // This works in operators.d
    return seq[0..1]
}

fn test_shift() -> Sequence {
    let empty: [u8] = []
    return shift(&empty, 0)  // Error: Type mismatch
}
```

**Result**:
```
Error: × Type errors:
  │ Type mismatch: expected `[u8; 0]`, found `[u8; 0]`
```

### Test Case 3: Real-world example (ffi.d)

```d
import operators;

type c_uchar = u8;

fn ptr_to_sequence(ptr: *const c_uchar, len: usize) -> operators.Sequence {
    if is_null(ptr) || len == 0 {
        // All of these fail:
        return [];  // Error
        // let empty: operators.Sequence = []; return empty;  // Error
        // let empty: [u8] = []; return operators.shift(&empty, 0);  // Error
    }
    // ...
}
```

**Result**:
```
Error: × Type errors:
  │ Type mismatch: expected `[u8; 0]`, found `[u8; 0]`
  │ Type mismatch: expected Named { name: "Sequence", args: [] }, found Unit
```

## Expected Behavior

Empty arrays `[]` should be inferable as any array type, including type aliases:
- `[]` should be inferable as `[u8]`
- `[]` should be inferable as `type Sequence = [u8]`
- Functions returning `[]` should work when the return type is a type alias

## Actual Behavior

- Empty arrays cannot be inferred as type aliases
- Even explicit type annotations (`let empty: operators.Sequence = []`) fail
- The error message shows identical types (`[u8; 0]` vs `[u8; 0]`), suggesting a bug in type comparison

## Workaround Attempted

1. **Explicit type annotation**: `let empty: operators.Sequence = []` - **FAILS**
2. **Using shift function**: `operators.shift(&empty, 0)` - **FAILS** (empty array type issue)
3. **Building from scratch**: `var seq: operators.Sequence = []` then appending - **FAILS** (initialization issue)

## Impact

This is a **blocking issue** for:
- FFI functions that need to return empty sequences
- Any function using type aliases that may return empty arrays
- Code that needs to handle empty collections gracefully

## Related Code

The `operators.shift` function in `operators.d` successfully returns `[]`:

```d
pub fn shift(seq: &Sequence, k: usize) -> Sequence {
    let n = seq.len()
    if n == 0 { return [] }  // ✅ This works!
    // ...
}
```

This suggests the issue is specific to:
1. Type aliases from other modules (`operators.Sequence`)
2. Or certain contexts (like FFI functions)

## Hypothesis

The type checker may be:
1. Not properly resolving type aliases when comparing empty array types
2. Using structural type comparison that fails for empty arrays
3. Having issues with cross-module type alias resolution

## Files Involved

- `darwin-atlas/demetrios/src/ffi.d` - `ptr_to_sequence` function
- `darwin-atlas/demetrios/src/operators.d` - `Sequence` type alias and `shift` function

## Minimal Reproduction

```d
// test_empty_alias.d
type MyArray = [u8];

fn test() -> MyArray {
    return []  // Should work but doesn't
}
```

```bash
dc build --cdylib test_empty_alias.d -o test.so
# Error: Type mismatch: expected `[u8; 0]`, found `[u8; 0]`
```

## Additional Context

This issue was discovered while implementing FFI functions for the Darwin Atlas project. The `ptr_to_sequence` helper function needs to return an empty sequence when the input pointer is null or length is 0, but this is currently impossible due to the type inference bug.

