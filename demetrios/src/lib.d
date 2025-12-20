/// Darwin Atlas Kernels - Library Root
///
/// High-performance implementations of genomic symmetry operators
/// showcasing Demetrios' unique capabilities:
///
/// # Capabilities Demonstrated
///
/// 1. **Units of Measure** (Documented, ready for integration)
///    - Dimensional analysis for genomic quantities
///    - See `operators.d` for conceptual examples
///
/// 2. **Refinement Types** (Documented, ready for SMT integration)
///    - Value constraints: `d_min/L ∈ [0, 1]`, `orbit_ratio ∈ [1/(2n), 1.0]`
///    - See `approx_metric.d`, `exact_symmetry.d` for examples
///
/// 3. **Epistemic Computing** (Fully implemented)
///    - Knowledge records with provenance, uncertainty, validity
///    - See `verify_knowledge.d` for validation logic
///
/// 4. **Algebraic Effects** (Implicit, documented)
///    - IO effects for file operations
///    - Allocation effects for data structures
///
/// # Architecture
///
/// - **Layer 2**: High-performance kernels (this library)
/// - **Integration**: Called from Julia via FFI (`ffi.d`)
/// - **Cross-validation**: Pure Julia implementation ensures reproducibility
///
/// # Documentation
///
/// - **README**: `../README.md` - Overview and build instructions
/// - **Capabilities**: `../docs/CAPABILITIES.md` - Detailed capability documentation
/// - **Epistemic**: `../docs/EPISTEMIC_Atlas_Knowledge.md` - Knowledge layer details

module lib;

// Re-export public API (FFI only; other modules require unsupported features).
pub import ffi;
