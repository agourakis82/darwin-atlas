# Darwin Atlas - Sounio Kernels

**Layer 2**: High-performance kernels with epistemic computing, units of measure, and refinement types.

---

## Overview

This directory contains the Sounio implementation of genomic symmetry operators, showcasing:

- ✅ **Units of Measure**: Dimensional analysis for genomic quantities
- ✅ **Refinement Types**: SMT-backed verification of value constraints
- ✅ **Epistemic Computing**: Knowledge records with provenance and uncertainty
- ✅ **Algebraic Effects**: Composable effect handlers (Alloc, IO)

---

## Architecture

```
sounio/
├── src/
│   ├── lib.sio            # Library root, public API
│   ├── operators.sio      # R/K/RC operators (with units)
│   ├── exact_symmetry.sio # Orbit computation (refinement types)
│   ├── approx_metric.sio  # d_min/L metric (refinement: 0 ≤ x ≤ 1)
│   ├── quaternion.sio     # Dic_n → D_n double cover
│   ├── ffi.sio            # C ABI exports for Julia
│   └── verify_knowledge.sio # Epistemic Knowledge validation
└── tests/                 # External test files
```

---

## Key Features Demonstrated

### 1. Units of Measure

**Concept**: Genomic quantities have physical dimensions (base pairs, nucleotides, etc.)

**Example** (conceptual):
```sio
// Future: when units are fully integrated
type BasePair = Quantity<i64, "bp">;
type Nucleotide = Quantity<u8, "nt">;

fn sequence_length(seq: &Sequence) -> BasePair {
    seq.len() as BasePair  // Automatic unit conversion
}
```

**Current Status**: Units are documented but not yet enforced at type level. The architecture is ready for unit integration.

**Location**: `operators.d`, `exact_symmetry.d`

---

### 2. Refinement Types

**Concept**: Value constraints verified at compile time via SMT solver.

**Example**:
```sio
// d_min_normalized returns value in [0, 1]
// Refinement type ensures constraint:
type NormalizedDistance = { x: f64 | 0.0 <= x && x <= 1.0 }

fn dmin_normalized(seq: &Sequence) -> NormalizedDistance {
    let d = dmin(seq) as f64;
    let len = seq.len() as f64;
    let ratio = d / len;
    // SMT solver verifies: 0 ≤ ratio ≤ 1
    ratio as NormalizedDistance
}
```

**Current Implementation**:
- `approx_metric.d`: `dmin_normalized` returns `f64` with documented constraint `[0, 1]`
- `exact_symmetry.d`: `orbit_ratio` returns `f64` with constraint `[1/(2n), 1.0]`

**Location**: `approx_metric.d`, `exact_symmetry.d`

---

### 3. Epistemic Computing

**Concept**: Track confidence, provenance, and uncertainty through computations.

**Example**:
```sio
// Knowledge[T] wraps values with epistemic metadata
struct Knowledge<T> {
    value: T,
    epsilon: Option<f64>,      // Error bound
    confidence: Option<f64>,   // Confidence in [0, 1]
    validity: ValidityInfo,    // Domain constraints
    provenance: ProvenanceInfo // Source tracing
}

fn orbit_ratio_with_uncertainty(seq: &Sequence) -> Knowledge<f64> {
    let value = exact_symmetry.orbit_ratio(seq);
    Knowledge {
        value,
        epsilon: Some(0.0),  // Exact computation
        confidence: Some(1.0), // Deterministic
        validity: ValidityInfo { holds: true, predicate: "0.25 ≤ x ≤ 1.0" },
        provenance: get_provenance()
    }
}
```

**Current Implementation**:
- `verify_knowledge.d`: Validates Knowledge records from Julia export
- Checks: provenance, epsilon ≥ 0, confidence ∈ [0,1], validity predicates

**Location**: `verify_knowledge.d`

---

### 4. Algebraic Effects

**Concept**: Composable effect handlers for IO, allocation, mutation, etc.

**Example**:
```sio
// Functions declare effects explicitly
fn compute_orbit(seq: &Sequence) -> HashSet<Sequence> with Alloc {
    // Alloc effect: function allocates memory
    let orbit = HashSet::new();
    // ... computation ...
    orbit
}

fn validate_knowledge(path: &str) -> Result<Report, IoError> with IO {
    // IO effect: function performs I/O
    let content = read_file(path)?;
    // ... validation ...
    Ok(report)
}
```

**Current Implementation**:
- `verify_knowledge.d`: Uses `with IO` for file operations
- All functions that allocate use `with Alloc` (implicit in current Demetrios)

**Location**: All modules

---

## Building

```bash
# Build shared library for Julia FFI
souc build --cdylib src/lib.sio -O 3 -o target/release/libdarwin_kernels.so

# Or use Makefile
cd .. && make sounio
```

---

## Integration with Julia

The kernels are called from Julia via FFI:

```julia
# Julia automatically detects and uses Sounio kernels
using DarwinAtlas

# If libdarwin_kernels.so exists, uses Sounio
# Otherwise, falls back to pure Julia implementation
orbit_ratio(sequence)
```

**Location**: `julia/src/DemetriosFFI.jl`

---

## Testing

```bash
# Run Sounio tests (if available)
souc test

# Or use Julia cross-validation
cd .. && make cross-validate
```

---

## Documentation

- **Operators**: `src/operators.sio` - Mathematical definitions
- **Exact Symmetry**: `src/exact_symmetry.sio` - Orbit computation
- **Approximate Metric**: `src/approx_metric.sio` - d_min/L with constraints
- **Quaternion**: `src/quaternion.sio` - Dic_n → D_n verification
- **Epistemic**: `src/verify_knowledge.sio` - Knowledge validation

---

## Future Enhancements

1. **Units Integration**: Add explicit unit types for base pairs, nucleotides
2. **Refinement Types**: Enforce constraints at type level (not just documentation)
3. **GPU Kernels**: Parallelize orbit computation on GPU
4. **More Epistemic**: Expand Knowledge records to all metrics

---

## References

- **Sounio Language**: https://github.com/sounio-lang/sounio
- **Atlas Architecture**: `../CLAUDE.md`
- **Epistemic Computing**: `../docs/EPISTEMIC_Atlas_Knowledge.md`

