# Issue: `extern "C" fn` functions from imported modules not included in compiled output

## Summary

Functions declared as `pub extern "C" fn` in imported modules are not being included in the compiled shared library output, even though they are correctly parsed and present in the AST.

## Environment

- **Compiler Version**: `dc 0.74.0`
- **Target**: `cdylib` (shared library)
- **Platform**: Linux x86_64

## Problem Description

When compiling a library that imports another module containing `pub extern "C" fn` functions, those functions are:
1. ✅ Correctly parsed (verified with test file)
2. ✅ Present in the AST after `module_loader` merges modules
3. ❌ **Not included in the HIR** (0 functions in output)
4. ❌ **Not exported as symbols** in the compiled `.so` file

## Steps to Reproduce

### Test Case 1: Simple file (WORKS)

```d
// test_ffi_parse.d
pub extern "C" fn test_function(x: usize) -> usize {
    return x + 1
}
```

```bash
dc build --cdylib test_ffi_parse.d -O 3 -o test_ffi.so -v
# Output: "Compiled 1 items, 1 functions"
nm -D test_ffi.so | grep test_function
# Output: "0000000000001100 T test_function" ✅
```

### Test Case 2: With imports (FAILS)

```d
// lib.d
pub import ffi;
```

```d
// ffi.d
pub extern "C" fn darwin_version() -> *const c_uchar {
    const VERSION_STR: [u8; 6] = [48, 46, 49, 46, 48, 0]
    return VERSION_STR.as_ptr() as *const c_uchar
}
```

```bash
dc build --cdylib src/lib.d -O 3 -o libdarwin_kernels.so -v
# Output: "Compiled 5 items, 0 functions" ❌
nm -D libdarwin_kernels.so | grep darwin_
# Output: (no symbols found) ❌
```

## Expected Behavior

Functions declared as `pub extern "C" fn` in imported modules should be:
1. Included in the HIR during type checking
2. Included in the HLIR during lowering
3. Compiled to LLVM IR
4. Exported as symbols in the shared library

## Actual Behavior

- Parser correctly creates `Item::Function` with `extern_abi: Some(Abi::C)`
- `module_loader` merges modules into AST (verified: `ffi.d` items are in merged AST)
- Type checker produces HIR with **0 functions** (should include `extern "C" fn` functions)
- No symbols exported in final `.so` file

## Technical Investigation

### Parser (`parser/mod.rs`)

The parser correctly handles `pub extern "C" fn`:

```rust
// Line 269-275: parse_item detects extern "C" fn
TokenKind::Extern => {
    let next1 = ...; // StringLit ("C")
    let next2 = ...; // Fn
    if matches!(next1, TokenKind::StringLit) && matches!(next2, TokenKind::Fn) {
        self.parse_extern_c_fn(visibility, modifiers, attributes)
    }
}

// Line 1948: Creates Item::Function with extern_abi
Ok(Item::Function(FnDef {
    ...
    extern_abi: Some(abi),
    ...
}))
```

### Module Loader (`module_loader.rs`)

The module loader correctly merges modules:

```rust
// Line 128-129: Iterates through all modules
for module in &mut self.modules {
    for item in &module.ast.items {
        // Items from ffi.d are included here
    }
}
```

### Type Checker (`check/mod.rs`)

**Suspected issue**: The type checker may be filtering out functions from imported modules that are not referenced, or `extern "C" fn` functions are not being processed correctly.

## Possible Root Causes

1. **Dead Code Elimination**: Functions from imported modules that are not referenced may be filtered out before type checking
2. **Type Checker Filtering**: The type checker may skip `extern "C" fn` functions from imported modules
3. **HLIR Lowering**: Functions may be filtered during HIR → HLIR lowering
4. **Module Visibility**: `pub import ffi;` may not be sufficient to include the functions

## Workaround Attempted

Tried including functions directly in `lib.d` instead of importing from `ffi.d`, but encountered type inference issues with empty arrays:

```d
// This fails with: Type mismatch: expected `operators::Sequence`, found `[?T0; 0]`
fn ptr_to_sequence(ptr: *const c_uchar, len: usize) -> operators.Sequence {
    if is_null(ptr) || len == 0 {
        return []  // Type inference fails
    }
    ...
}
```

## Impact

This is a **blocking issue** for FFI integration. Libraries that need to export C ABI functions from imported modules cannot do so, forcing workarounds or code duplication.

## Proposed Solutions

1. **Option A**: Modify `module_loader.rs` `into_ast` to explicitly include all `extern "C" fn` functions, regardless of references
2. **Option B**: Modify type checker to always process `extern "C" fn` functions, even if not referenced
3. **Option C**: Add a special flag/attribute for `extern "C" fn` that marks them as "always include"
4. **Option D**: Modify HLIR lowering to preserve `extern "C" fn` functions

## Additional Context

This issue was discovered while integrating Demetrios kernels with Julia via FFI. The Darwin Atlas project requires exporting multiple C ABI functions from a module that imports other modules.

## Files Involved

- `compiler/src/parser/mod.rs` - Parsing (works correctly)
- `compiler/src/module_loader.rs` - Module merging (works correctly)
- `compiler/src/check/mod.rs` - Type checking (suspected issue)
- `compiler/src/hlir/lower.rs` - HIR → HLIR lowering (possible issue)

## Minimal Reproduction

```d
// main.d
pub import ffi;

// ffi.d  
pub extern "C" fn test() -> usize {
    return 42
}
```

```bash
dc build --cdylib main.d -o test.so
nm -D test.so | grep test
# Expected: test symbol present
# Actual: no symbols
```

