# Track Specification: Fix Demetrios FFI and Enable Cross-Validation

## Track ID
`ffi_fix_20251223`

## Type
Bug Fix / Critical Infrastructure

## Status
New

## Priority
🔴 Critical (Blocker)

---

## Problem Statement

### Current Issue

The Demetrios FFI (Foreign Function Interface) is not properly exporting symbols marked with `extern "C" fn`, preventing Julia from calling Demetrios functions via `ccall`. This blocks the cross-validation framework, which is essential for:

1. **Computational Correctness**: Verifying that Julia and Demetrios implementations produce identical results
2. **Scientific Reproducibility**: Ensuring reviewers can validate results independently
3. **Demetrios Showcase**: Demonstrating the language's capabilities for scientific computing

### Technical Details

**Symptoms**:
- `nm -D libdarwin_kernels.so` does not show exported symbols
- Julia `ccall` fails with "symbol not found" errors
- Cross-validation tests fail, forcing fallback to Julia-only implementation
- Epistemic computing features of Demetrios are not demonstrated

**Impact**:
- Cross-validation framework is non-functional
- Cannot verify computational correctness between implementations
- Demetrios capabilities are not showcased
- Scientific Data reviewers cannot validate dual implementation claim

**Current Workaround**:
- Using Julia-only implementation for all computations
- Cross-validation is effectively disabled
- Demetrios code exists but is not executed

---

## Goals and Objectives

### Primary Goal
Enable Julia to successfully call Demetrios functions via FFI, allowing full cross-validation between implementations.

### Specific Objectives

1. **Fix Symbol Export**
   - Ensure `extern "C" fn` symbols are properly exported in compiled shared library
   - Verify symbols are visible via `nm -D libdarwin_kernels.so`
   - Confirm C ABI compatibility

2. **Enable Julia FFI Calls**
   - Julia `ccall` successfully invokes Demetrios functions
   - Data marshaling works correctly (Julia types ↔ C types ↔ Demetrios types)
   - No runtime errors or segmentation faults

3. **Restore Cross-Validation**
   - `make cross-validate` passes 100%
   - Julia and Demetrios implementations produce bit-exact results (or within floating-point tolerance)
   - Automated tests verify agreement on all metrics

4. **Document Solution**
   - Root cause analysis documented
   - Solution approach explained
   - Future maintenance guidelines provided

---

## Success Criteria

### Must Have (P0)

- [ ] **Symbol Export Verified**: `nm -D libdarwin_kernels.so` shows all expected `extern "C" fn` symbols
- [ ] **FFI Calls Functional**: Julia can successfully call at least one Demetrios function via `ccall`
- [ ] **Cross-Validation Passing**: `make cross-validate` completes without errors
- [ ] **Bit-Exact Agreement**: Julia and Demetrios produce identical results for test cases

### Should Have (P1)

- [ ] **All Metrics Cross-Validated**: Orbit size, d_min/L, palindrome detection, quaternion lift
- [ ] **Performance Benchmarked**: Demetrios implementation is faster than Julia (expected)
- [ ] **Documentation Complete**: Root cause, solution, and maintenance guide documented
- [ ] **CI Integration**: Cross-validation runs automatically in GitHub Actions

### Nice to Have (P2)

- [ ] **Error Handling**: Graceful handling of FFI errors with informative messages
- [ ] **Memory Safety**: No memory leaks or segmentation faults under stress testing
- [ ] **Fallback Mechanism**: Automatic fallback to Julia if Demetrios library unavailable

---

## Scope

### In Scope

1. **Demetrios Compiler Investigation**
   - Analyze module loader and codegen for symbol export issues
   - Review HIR/HLIR representation of `extern "C" fn`
   - Investigate LLVM linkage settings

2. **FFI Implementation**
   - Fix or workaround symbol export issue
   - Implement proper C ABI wrappers if needed
   - Test data marshaling for all required types

3. **Cross-Validation Framework**
   - Update `julia/src/CrossValidation.jl` to use Demetrios FFI
   - Implement comparison logic with appropriate tolerances
   - Add comprehensive test cases

4. **Testing and Validation**
   - Unit tests for individual FFI functions
   - Integration tests for cross-validation
   - Stress tests with large sequences

5. **Documentation**
   - Root cause analysis
   - Solution implementation details
   - Maintenance and troubleshooting guide

### Out of Scope

1. **Performance Optimization**: Focus is on correctness, not speed (separate track)
2. **New Metrics**: Only fix existing metrics, no new features
3. **Knowledge Validator**: Separate issue, will be addressed in future track
4. **Scaling**: Cross-validation at small scale (200 genomes) is sufficient

---

## Technical Approach

### Investigation Phase

1. **Analyze Demetrios Compiler**
   - Review source code for `extern "C" fn` handling
   - Check HIR/HLIR generation for FFI functions
   - Investigate LLVM codegen and linkage

2. **Test Symbol Export**
   - Build minimal Demetrios library with single `extern "C" fn`
   - Verify symbol visibility with `nm -D`
   - Test calling from C program

3. **Identify Root Cause**
   - Determine if issue is in Demetrios compiler or build configuration
   - Check if symbols are generated but not exported
   - Verify LLVM IR contains correct linkage attributes

### Solution Phase

**Option A: Fix Demetrios Compiler (Preferred)**
- Modify compiler to properly export `extern "C" fn` symbols
- Ensure correct LLVM linkage attributes
- Test with darwin-atlas FFI functions

**Option B: C Wrapper Workaround**
- Create thin C wrapper that calls Demetrios functions
- Export C wrapper via traditional FFI
- Less elegant but functional

**Option C: Alternative FFI Mechanism**
- Investigate if Demetrios supports alternative FFI approaches
- Consider JIT compilation if available
- Evaluate trade-offs

### Implementation Phase

1. **Apply Fix**
   - Implement chosen solution (A, B, or C)
   - Build Demetrios library with fix
   - Verify symbol export

2. **Update Julia FFI Module**
   - Modify `julia/src/DemetriosFFI.jl` to use fixed library
   - Implement proper error handling
   - Add type conversions for all required types

3. **Implement Cross-Validation**
   - Update `julia/src/CrossValidation.jl`
   - Add comparison logic with tolerances
   - Implement comprehensive test suite

4. **Testing**
   - Unit tests for each FFI function
   - Integration tests for cross-validation
   - Stress tests with edge cases

---

## Dependencies

### External Dependencies

- **Demetrios Compiler**: May require fix or workaround
- **LLVM**: Correct linkage attributes required
- **Julia**: FFI mechanism via `ccall`

### Internal Dependencies

- **Demetrios Source**: `demetrios/src/ffi.d`, `demetrios/src/operators.d`, etc.
- **Julia FFI Module**: `julia/src/DemetriosFFI.jl`
- **Cross-Validation Module**: `julia/src/CrossValidation.jl`
- **Build System**: `Makefile` targets for building and testing

### Blocking Issues

- None (this is the blocker for other work)

### Blocked By This Track

- Performance optimization (requires working cross-validation)
- Scaling to 10k+ replicons (requires confidence in correctness)
- Scientific Data paper submission (requires demonstrated dual implementation)

---

## Risks and Mitigation

### Risk 1: Demetrios Compiler Fix Required

**Probability**: High  
**Impact**: High  
**Mitigation**: 
- Prepare C wrapper workaround as backup
- Engage with Demetrios maintainers early
- Document workaround approach

### Risk 2: Data Marshaling Complexity

**Probability**: Medium  
**Impact**: Medium  
**Mitigation**:
- Start with simple types (integers, floats)
- Test incrementally with complex types
- Use well-defined C ABI types

### Risk 3: Floating-Point Precision Differences

**Probability**: Medium  
**Impact**: Low  
**Mitigation**:
- Use appropriate tolerances in comparisons
- Document expected precision differences
- Focus on algorithmic correctness, not bit-exact floating-point

### Risk 4: Performance Regression

**Probability**: Low  
**Impact**: Low  
**Mitigation**:
- Benchmark before and after
- Optimize FFI overhead if needed
- Accept minor overhead for correctness

---

## Testing Strategy

### Unit Tests

**Demetrios FFI Functions**:
- Test each exported function individually
- Verify correct return values for known inputs
- Test edge cases (empty sequences, maximum length, etc.)

**Julia FFI Wrappers**:
- Test type conversions (Julia ↔ C ↔ Demetrios)
- Verify error handling
- Test memory management (no leaks)

### Integration Tests

**Cross-Validation**:
- Compare Julia vs. Demetrios for all metrics
- Test on diverse sequences (short, long, palindromic, etc.)
- Verify agreement within tolerances

**End-to-End**:
- Run full pipeline with cross-validation enabled
- Process small dataset (50 genomes)
- Verify all outputs match

### Stress Tests

**Large Sequences**:
- Test with maximum-length bacterial replicons (~10 Mbp)
- Verify no memory issues or crashes

**Edge Cases**:
- Empty sequences
- Single-nucleotide sequences
- Sequences with ambiguous bases (N)
- Palindromic sequences

---

## Documentation Requirements

### Technical Documentation

1. **Root Cause Analysis**
   - Detailed explanation of why symbols were not exported
   - Analysis of Demetrios compiler behavior
   - LLVM IR inspection results

2. **Solution Documentation**
   - Chosen approach and rationale
   - Implementation details
   - Build configuration changes

3. **FFI API Documentation**
   - List of exported functions
   - Function signatures and types
   - Usage examples from Julia

### User Documentation

1. **Build Instructions**
   - How to build Demetrios library with FFI
   - Required compiler flags and options
   - Troubleshooting common issues

2. **Cross-Validation Guide**
   - How to run cross-validation
   - Interpreting results
   - Expected tolerances

### Maintenance Documentation

1. **Future Considerations**
   - How to add new FFI functions
   - Testing requirements for FFI changes
   - Compatibility with future Demetrios versions

---

## Timeline Estimate

**Total Duration**: 2-3 weeks

### Week 1: Investigation and Solution Design
- Days 1-2: Analyze Demetrios compiler and identify root cause
- Days 3-4: Design solution approach (fix vs. workaround)
- Day 5: Prototype minimal FFI example

### Week 2: Implementation
- Days 1-2: Implement chosen solution
- Days 3-4: Update Julia FFI module and cross-validation
- Day 5: Initial testing and debugging

### Week 3: Testing and Documentation
- Days 1-2: Comprehensive testing (unit, integration, stress)
- Days 3-4: Documentation (technical, user, maintenance)
- Day 5: Final validation and CI integration

---

## Acceptance Criteria

This track is complete when:

1. ✅ `nm -D libdarwin_kernels.so` shows all expected symbols
2. ✅ Julia can call Demetrios functions without errors
3. ✅ `make cross-validate` passes 100%
4. ✅ Julia and Demetrios produce identical results (within tolerance)
5. ✅ All tests pass (unit, integration, stress)
6. ✅ Documentation is complete and reviewed
7. ✅ CI pipeline includes cross-validation checks
8. ✅ No memory leaks or segmentation faults

---

## References

- [ROADMAP.md](../../ROADMAP.md) - Project roadmap with priorities
- [EVOLUTION_PLAN.md](../../EVOLUTION_PLAN.md) - Detailed evolution plan
- [DEMETRIOS_MISSING_FEATURES.md](../../DEMETRIOS_MISSING_FEATURES.md) - Known Demetrios limitations
- [julia/src/DemetriosFFI.jl](../../julia/src/DemetriosFFI.jl) - Current FFI implementation
- [julia/src/CrossValidation.jl](../../julia/src/CrossValidation.jl) - Cross-validation framework
- [demetrios/src/ffi.d](../../demetrios/src/ffi.d) - Demetrios FFI exports

---

**Created**: 2025-12-23  
**Last Updated**: 2025-12-23  
**Track ID**: ffi_fix_20251223
