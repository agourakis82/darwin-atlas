# Implementation Plan: Fix Demetrios FFI and Enable Cross-Validation

**Track ID**: ffi_fix_20251223  
**Created**: 2025-12-23  
**Status**: New

---

## Overview

This plan implements the fix for Demetrios FFI symbol export issues and restores full cross-validation between Julia and Demetrios implementations. The plan follows Test-Driven Development (TDD) principles as specified in the workflow.

---

## Phase 1: Investigation and Root Cause Analysis

**Goal**: Identify why `extern "C" fn` symbols are not being exported and determine the best solution approach.

### Tasks

- [ ] Task: Analyze Demetrios compiler symbol export mechanism
  - Review Demetrios compiler source code for `extern "C" fn` handling
  - Check HIR/HLIR generation for FFI functions in module loader
  - Investigate LLVM codegen and linkage attribute generation
  - Document findings in `ISSUES/ffi_investigation.md`

- [ ] Task: Build minimal Demetrios FFI test case
  - Create `demetrios/tests/minimal_ffi_test.d` with single `extern "C" fn`
  - Build shared library: `dc build --release --target=cdylib`
  - Verify symbol export: `nm -D libminimal_ffi_test.so`
  - Document whether symbols are visible or not

- [ ] Task: Test FFI call from C program
  - Write minimal C program `demetrios/tests/test_ffi_call.c`
  - Compile and link against Demetrios library
  - Attempt to call exported function
  - Document success or failure with error messages

- [ ] Task: Identify root cause and solution approach
  - Analyze all investigation results
  - Determine if issue is compiler bug, build config, or LLVM linkage
  - Evaluate solution options: (A) compiler fix, (B) C wrapper, (C) alternative FFI
  - Document recommended approach with rationale in `ISSUES/ffi_solution_design.md`

- [ ] Task: Conductor - User Manual Verification 'Phase 1: Investigation and Root Cause Analysis' (Protocol in workflow.md)

---

## Phase 2: Implement FFI Fix

**Goal**: Apply the chosen solution to enable symbol export and FFI calls.

### Tasks

- [ ] Task: Write failing tests for Demetrios FFI functions
  - Create `julia/test/test_demetrios_ffi.jl`
  - Write tests for `compute_orbit_size()` FFI call
  - Write tests for `compute_dmin_normalized()` FFI call
  - Write tests for `detect_palindrome()` FFI call
  - Run tests and confirm they fail (Red phase)

- [ ] Task: Implement chosen FFI solution
  - Apply fix based on Phase 1 decision (compiler fix, C wrapper, or alternative)
  - If compiler fix: Modify Demetrios compiler and rebuild
  - If C wrapper: Create `demetrios/src/ffi_wrapper.c` with C exports
  - If alternative: Implement chosen alternative FFI mechanism
  - Build Demetrios library with fix

- [ ] Task: Verify symbol export after fix
  - Run `nm -D libdarwin_kernels.so` (or equivalent)
  - Confirm all expected symbols are visible
  - Document exported symbols in `demetrios/docs/ffi_api.md`

- [ ] Task: Update Julia FFI module to use fixed library
  - Modify `julia/src/DemetriosFFI.jl` to call exported functions
  - Implement proper type conversions (Julia ↔ C ↔ Demetrios)
  - Add error handling for FFI call failures
  - Add memory management (if needed for complex types)

- [ ] Task: Run tests and verify FFI calls work (Green phase)
  - Run `julia/test/test_demetrios_ffi.jl`
  - Confirm all tests pass
  - Verify no segmentation faults or memory errors
  - Document any floating-point precision differences

- [ ] Task: Conductor - User Manual Verification 'Phase 2: Implement FFI Fix' (Protocol in workflow.md)

---

## Phase 3: Restore Cross-Validation Framework

**Goal**: Enable full cross-validation between Julia and Demetrios implementations.

### Tasks

- [ ] Task: Write failing tests for cross-validation
  - Create `julia/test/test_cross_validation.jl`
  - Write test for orbit size cross-validation
  - Write test for d_min/L cross-validation
  - Write test for palindrome detection cross-validation
  - Write test for quaternion lift cross-validation
  - Run tests and confirm they fail (Red phase)

- [ ] Task: Implement cross-validation comparison logic
  - Update `julia/src/CrossValidation.jl`
  - Add `compare_orbit_size(julia_result, demetrios_result)` function
  - Add `compare_dmin_normalized(julia_result, demetrios_result)` function
  - Add `compare_palindrome_detection(julia_result, demetrios_result)` function
  - Implement appropriate tolerance for floating-point comparisons

- [ ] Task: Add comprehensive test cases for cross-validation
  - Test with short sequences (10 bp)
  - Test with medium sequences (1000 bp)
  - Test with long sequences (1 Mbp)
  - Test with palindromic sequences
  - Test with sequences containing ambiguous bases (N)
  - Test with edge cases (empty, single nucleotide)

- [ ] Task: Run cross-validation tests (Green phase)
  - Run `julia/test/test_cross_validation.jl`
  - Confirm all tests pass
  - Verify Julia and Demetrios produce identical results (within tolerance)
  - Document any systematic differences

- [ ] Task: Integrate cross-validation into Makefile
  - Update `Makefile` target `cross-validate`
  - Ensure it runs full cross-validation suite
  - Add to CI pipeline (`.github/workflows/ci.yml`)
  - Test `make cross-validate` from clean state

- [ ] Task: Conductor - User Manual Verification 'Phase 3: Restore Cross-Validation Framework' (Protocol in workflow.md)

---

## Phase 4: Testing and Validation

**Goal**: Ensure FFI and cross-validation are robust and production-ready.

### Tasks

- [ ] Task: Write unit tests for all FFI functions
  - Test `compute_orbit_size()` with diverse inputs
  - Test `compute_dmin_normalized()` with diverse inputs
  - Test `detect_palindrome()` with diverse inputs
  - Test `compute_quaternion_lift()` with diverse inputs
  - Verify error handling for invalid inputs

- [ ] Task: Write integration tests for end-to-end pipeline
  - Create `julia/test/test_pipeline_with_cross_validation.jl`
  - Run pipeline on small dataset (10 genomes) with cross-validation enabled
  - Verify all outputs match between Julia and Demetrios
  - Check that no errors or warnings are produced

- [ ] Task: Perform stress testing
  - Test with maximum-length bacterial replicon (~10 Mbp)
  - Test with 100 replicons in batch
  - Monitor memory usage during cross-validation
  - Verify no memory leaks using valgrind or similar tool

- [ ] Task: Benchmark performance comparison
  - Measure Julia-only performance (baseline)
  - Measure Demetrios-only performance
  - Measure cross-validation overhead
  - Document results in `docs/performance_benchmarks.md`

- [ ] Task: Verify test coverage meets requirements
  - Run coverage analysis: `julia --project=julia -e 'using Pkg; Pkg.test(coverage=true)'`
  - Confirm >80% coverage for FFI and cross-validation modules
  - Add additional tests if coverage is insufficient

- [ ] Task: Conductor - User Manual Verification 'Phase 4: Testing and Validation' (Protocol in workflow.md)

---

## Phase 5: Documentation and Finalization

**Goal**: Complete all documentation and prepare for production use.

### Tasks

- [ ] Task: Write root cause analysis document
  - Create `docs/ffi_root_cause_analysis.md`
  - Explain why symbols were not exported originally
  - Document investigation process and findings
  - Include LLVM IR analysis if relevant

- [ ] Task: Document FFI solution implementation
  - Create `docs/ffi_solution_implementation.md`
  - Explain chosen solution approach and rationale
  - Document implementation details (compiler fix, C wrapper, etc.)
  - Include build configuration changes

- [ ] Task: Create FFI API documentation
  - Create `demetrios/docs/ffi_api.md`
  - List all exported functions with signatures
  - Document expected input/output types
  - Provide usage examples from Julia

- [ ] Task: Write cross-validation user guide
  - Create `docs/cross_validation_guide.md`
  - Explain how to run cross-validation
  - Document how to interpret results
  - Explain expected tolerances for floating-point comparisons

- [ ] Task: Update build and installation instructions
  - Update `README.md` with FFI build requirements
  - Document required compiler flags and options
  - Add troubleshooting section for common FFI issues
  - Update `Makefile` help text

- [ ] Task: Write maintenance documentation
  - Create `docs/ffi_maintenance.md`
  - Document how to add new FFI functions
  - Explain testing requirements for FFI changes
  - Discuss compatibility with future Demetrios versions

- [ ] Task: Update ROADMAP and EVOLUTION_PLAN
  - Mark "Fix FFI Demetrios" as complete in `ROADMAP.md`
  - Update status in `EVOLUTION_PLAN.md`
  - Document lessons learned
  - Update next steps and priorities

- [ ] Task: Conductor - User Manual Verification 'Phase 5: Documentation and Finalization' (Protocol in workflow.md)

---

## Quality Gates

Before marking this track complete, verify:

- [ ] All tests pass (unit, integration, stress)
- [ ] Test coverage >80% for FFI and cross-validation modules
- [ ] `make cross-validate` passes 100%
- [ ] Julia and Demetrios produce identical results (within documented tolerance)
- [ ] No memory leaks detected
- [ ] No segmentation faults under stress testing
- [ ] All documentation complete and reviewed
- [ ] CI pipeline includes cross-validation checks
- [ ] Build instructions tested on clean environment

---

## Success Metrics

### Technical Metrics
- ✅ Symbol export verified: `nm -D` shows all expected symbols
- ✅ FFI calls functional: Julia successfully calls Demetrios functions
- ✅ Cross-validation passing: 100% agreement on test cases
- ✅ Test coverage: >80% for new/modified code
- ✅ Performance: Demetrios faster than Julia (expected)

### Process Metrics
- ✅ All phases completed on schedule
- ✅ All quality gates passed
- ✅ Documentation complete
- ✅ CI integration successful

### Scientific Metrics
- ✅ Computational correctness verified
- ✅ Dual implementation demonstrated
- ✅ Reproducibility guaranteed
- ✅ Ready for Scientific Data submission

---

## Risk Mitigation

### If Demetrios Compiler Fix is Not Feasible
- **Fallback**: Implement C wrapper workaround
- **Timeline Impact**: +2-3 days
- **Quality Impact**: Minimal (functionality preserved)

### If Floating-Point Differences are Significant
- **Mitigation**: Document differences and use appropriate tolerances
- **Timeline Impact**: +1 day for analysis
- **Quality Impact**: None (expected behavior)

### If Performance Regression Occurs
- **Mitigation**: Profile and optimize FFI overhead
- **Timeline Impact**: +2-3 days
- **Quality Impact**: None (correctness prioritized over speed)

---

## Dependencies

### External
- Demetrios compiler (may need fix)
- LLVM (correct linkage attributes)
- Julia (FFI via `ccall`)

### Internal
- `demetrios/src/ffi.d`
- `julia/src/DemetriosFFI.jl`
- `julia/src/CrossValidation.jl`
- `Makefile`

---

## Timeline

**Total Duration**: 2-3 weeks

- **Phase 1**: 3-4 days (Investigation)
- **Phase 2**: 4-5 days (Implementation)
- **Phase 3**: 3-4 days (Cross-Validation)
- **Phase 4**: 3-4 days (Testing)
- **Phase 5**: 2-3 days (Documentation)

---

## Notes

- This plan follows TDD principles: Write failing tests (Red) → Implement (Green) → Refactor
- Each phase includes a manual verification checkpoint per workflow protocol
- Test coverage must be >80% before marking tasks complete
- All commits follow semantic commit message format
- Git notes will be used to attach task summaries to commits

---

**Plan Version**: 1.0  
**Last Updated**: 2025-12-23
