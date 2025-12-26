# Deep Investigation: `extern "C" fn` Functions Not Included from Imported Modules

## Executive Summary

Functions declared as `pub extern "C" fn` in imported modules are correctly parsed and present in the AST after module loading, but are **not included in the HIR** during type checking, resulting in 0 functions being compiled and no symbols exported in the shared library.

**Root Cause**: The type checker's `check_item()` method processes all AST items, but functions from imported modules are not being converted to HIR items, even though they are counted in the initial AST analysis.

## Environment

- **Compiler**: `dc 0.74.0`
- **Platform**: Linux x86_64
- **Target**: `cdylib` (shared library)
- **Repository**: `https://github.com/sounio-lang/sounio.git`

## Problem Statement

When compiling a library that imports another module containing `pub extern "C" fn` functions:

1. ✅ **Parser**: Correctly creates `Item::Function` with `extern_abi: Some(Abi::C)`
2. ✅ **Module Loader**: Successfully merges modules into AST (verified: items from `ffi.d` are in merged AST)
3. ✅ **AST Analysis**: Type checker counts functions in AST (`extern_fn_count = 9`)
4. ❌ **HIR Generation**: Type checker produces HIR with **0 functions**
5. ❌ **HLIR Lowering**: No functions to lower (HIR is empty)
6. ❌ **Code Generation**: No functions to compile
7. ❌ **Symbol Export**: No symbols in `.so` file

## Test Cases

### Test Case 1: Simple File (WORKS ✅)

```d
// test_ffi_parse.d
pub extern "C" fn test_function(x: usize) -> usize {
    return x + 1
}
```

**Result**:
```
Compiled 1 items, 1 functions
nm -D test_ffi.so | grep test_function
# Output: 0000000000001100 T test_function ✅
```

### Test Case 2: With Import (FAILS ❌)

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
// ... 8 more extern "C" fn functions
```

**Result**:
```
Compiled 5 items, 0 functions
nm -D libdarwin_kernels.so | grep darwin_
# Output: (no symbols found) ❌
```

### Test Case 3: Direct Import (FAILS ❌)

```d
// test_ast.d
pub import ffi;
```

**Result**:
```
Compiled 1 items, 0 functions
```

## Code Flow Analysis

### 1. Module Loader (`module_loader.rs`)

**Location**: `src/module_loader.rs:117-145`

```rust
fn into_ast(mut self, root_id: usize) -> Result<Ast> {
    let mut items = Vec::new();
    
    for module in &mut self.modules {
        for item in &module.ast.items {
            // Duplicate check (lines 130-140)
            if let Some(name) = item_name(item) {
                if let Some(prev_path) = defined.get(&name) {
                    return Err(...); // Duplicate error
                }
                defined.insert(name, module.path.clone());
            }
        }
        
        items.append(&mut module.ast.items);  // ✅ Items ARE merged
        node_spans.extend(module.ast.node_spans.drain());
    }
    
    Ok(Ast { items, ... })
}
```

**Verification**: Items from `ffi.d` are correctly merged into the AST. The merged AST contains:
- 1 item from `lib.d`: `Item::Import(ffi)`
- 9 items from `ffi.d`: `Item::Function` with `extern_abi: Some(Abi::C)`
- Total: 10 items

### 2. Type Checker - AST Analysis (`check/mod.rs`)

**Location**: `src/check/mod.rs:358-397`

```rust
fn check_program_internal(&mut self, ast: &Ast) -> Result<Hir> {
    let mut function_count = 0usize;
    let mut extern_fn_count = 0usize;
    
    for item in &ast.items {
        match item {
            Item::Function(f) => {
                function_count += 1;
                if f.extern_abi.is_some() {
                    extern_fn_count += 1;  // ✅ Counts 9 extern functions
                }
            }
            // ...
        }
    }
    
    tracing::debug!(
        functions = function_count,      // Should be 9
        extern_fns = extern_fn_count,    // Should be 9
        "typecheck input AST"
    );
```

**Observation**: The type checker **correctly counts** 9 extern functions in the AST during the initial analysis phase.

### 3. Type Checker - HIR Generation (`check/mod.rs`)

**Location**: `src/check/mod.rs:399-463`

```rust
let mut items = Vec::new();

// First pass: collect ontology prefixes, type definitions, and alignments
for item in &ast.items {
    self.collect_ontology_prefix(item);
    // ...
}

// Second pass: type check items
for item in &ast.items {
    if let Some(hir_item) = self.check_item(item)? {  // ⚠️ Returns Option
        items.push(hir_item);
    }
}

Ok(Hir { items })  // ❌ items is empty for functions
```

**Critical Issue**: `check_item()` returns `Option<HirItem>`. If it returns `None` for imported functions, they won't be included in the HIR.

### 4. `check_item()` Implementation (`check/mod.rs`)

**Location**: `src/check/mod.rs:1164-1200`

```rust
fn check_item(&mut self, item: &Item) -> Result<Option<HirItem>> {
    match item {
        Item::Function(f) => {
            let hir_fn = self.check_function(f)?;
            Ok(Some(HirItem::Function(hir_fn)))  // ✅ Should return Some
        }
        Item::Import(_) => {
            // ⚠️ What does this return?
        }
        // ...
    }
}
```

**Investigation Needed**: Need to verify what `check_item()` returns for:
1. `Item::Function` from the root module
2. `Item::Function` from imported modules
3. `Item::Import` statements

### 5. HLIR Lowering (`hlir/lower.rs`)

**Location**: `src/hlir/lower.rs:44-60`

```rust
fn lower_module(mut self, hir: &Hir) -> HlirModule {
    let mut function_count = 0usize;
    let mut extern_fn_count = 0usize;
    
    for item in &hir.items {  // ⚠️ HIR.items is empty
        if let HirItem::Function(f) = item {
            function_count += 1;
            if f.extern_abi.is_some() {
                extern_fn_count += 1;
            }
        }
    }
    
    tracing::debug!(
        functions = function_count,      // 0 (HIR is empty)
        extern_fns = extern_fn_count,    // 0
        "lowering HIR to HLIR"
    );
}
```

**Observation**: HLIR lowering correctly processes functions from HIR, but HIR is empty, so no functions are lowered.

### 6. Code Generation (`codegen/llvm/codegen.rs`)

**Location**: `src/codegen/llvm/codegen.rs:132-152`

```rust
pub fn compile(&mut self, hlir: &HlirModule) -> &Module<'ctx> {
    let extern_fn_count = hlir
        .functions
        .iter()
        .filter(|f| f.extern_abi.is_some())
        .count();  // 0 (HLIR has no functions)
    
    // Declare all functions first
    for func in &hlir.functions {  // Empty iterator
        self.declare_function(func);
    }
}
```

**Observation**: Code generation correctly handles `extern "C" fn` functions (uses `Linkage::External`), but there are no functions to compile.

## Hypothesis

The issue is in the **type checker's `check_item()` method**. One of the following is happening:

1. **Import Filtering**: `Item::Import` statements are processed, but functions from imported modules are not being checked because they're considered "already processed" or "external".

2. **Visibility/Scope Issue**: Functions from imported modules might not be in the correct scope when `check_item()` is called, causing them to be skipped.

3. **Module Resolution**: The type checker might be treating imported functions as "external declarations" rather than "definitions to compile", causing them to be filtered out.

4. **Dead Code Elimination**: There might be an early dead code elimination pass that removes functions that aren't referenced, and `extern "C" fn` functions from imports aren't considered "referenced" because they're not called from the root module.

## Evidence

### Evidence 1: AST Contains Functions
- Module loader merges modules correctly
- AST analysis counts 9 extern functions
- Functions are present in `ast.items`

### Evidence 2: HIR is Empty
- `check_item()` is called for all AST items
- But `hir.items` is empty (0 functions)
- This means `check_item()` returns `None` for imported functions

### Evidence 3: Simple File Works
- When functions are in the root module (not imported), they work correctly
- This suggests the issue is specific to imported modules

## Proposed Solutions

### Solution 1: Always Include `extern "C" fn` in HIR

Modify `check_item()` or `check_program_internal()` to always include `extern "C" fn` functions, regardless of whether they're from imported modules:

```rust
// In check/mod.rs
fn check_program_internal(&mut self, ast: &Ast) -> Result<Hir> {
    // ... existing code ...
    
    // Always include extern "C" fn functions for FFI export
    for item in &ast.items {
        if let Item::Function(f) = item {
            if f.extern_abi.is_some() {
                // Force inclusion of extern "C" fn functions
                if let Some(hir_item) = self.check_item(item)? {
                    items.push(hir_item);
                }
            }
        }
    }
    
    // ... rest of code ...
}
```

### Solution 2: Modify `check_item()` for Imported Functions

Ensure `check_item()` returns `Some(HirItem::Function(...))` for all functions, including those from imported modules:

```rust
fn check_item(&mut self, item: &Item) -> Result<Option<HirItem>> {
    match item {
        Item::Function(f) => {
            // Always check functions, even from imported modules
            let hir_fn = self.check_function(f)?;
            Ok(Some(HirItem::Function(hir_fn)))
        }
        // ...
    }
}
```

### Solution 3: Post-Process HIR to Include Extern Functions

After HIR generation, scan the AST again and add any missing `extern "C" fn` functions:

```rust
// After generating HIR
for item in &ast.items {
    if let Item::Function(f) = item {
        if f.extern_abi.is_some() {
            // Check if already in HIR
            let in_hir = hir.items.iter().any(|hir_item| {
                if let HirItem::Function(hir_fn) = hir_item {
                    hir_fn.name == f.name
                } else {
                    false
                }
            });
            
            if !in_hir {
                // Add missing extern function
                let hir_fn = self.check_function(f)?;
                hir.items.push(HirItem::Function(hir_fn));
            }
        }
    }
}
```

## Debugging Steps

1. **Add Debug Logging**: Add `tracing::debug!()` calls to track:
   - Which items `check_item()` is called with
   - What `check_item()` returns for each item
   - Whether imported functions are being processed

2. **Verify AST Contents**: Add logging to confirm AST contains functions from `ffi.d`:
   ```rust
   for item in &ast.items {
       if let Item::Function(f) = item {
           tracing::debug!("AST function: {} (extern_abi: {:?})", f.name, f.extern_abi);
       }
   }
   ```

3. **Trace `check_item()` Calls**: Log every call to `check_item()` and its return value:
   ```rust
   fn check_item(&mut self, item: &Item) -> Result<Option<HirItem>> {
       tracing::debug!("check_item: {:?}", item);
       let result = match item { ... };
       tracing::debug!("check_item result: {:?}", result);
       result
   }
   ```

## Impact

This is a **critical blocking issue** for:
- FFI integration with other languages (Julia, Python, C, etc.)
- Library development in Demetrios
- Any use case requiring exported C ABI functions from imported modules

## Related Files

- `compiler/src/module_loader.rs` - Module loading and AST merging
- `compiler/src/check/mod.rs` - Type checking and HIR generation
- `compiler/src/hlir/lower.rs` - HIR to HLIR lowering
- `compiler/src/codegen/llvm/codegen.rs` - LLVM code generation
- `compiler/src/main.rs` - Main compilation pipeline

## Test Files

- `darwin-atlas/demetrios/src/lib.d` - Root module with imports
- `darwin-atlas/demetrios/src/ffi.d` - Module with 9 `extern "C" fn` functions
- `darwin-atlas/demetrios/test_ffi_parse.d` - Simple test file (works)

## Next Steps

1. Add comprehensive debug logging to trace the issue
2. Verify what `check_item()` returns for imported functions
3. Implement one of the proposed solutions
4. Test with the Darwin Atlas project
5. Verify symbols are exported in the compiled library

