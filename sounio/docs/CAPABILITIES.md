# Demetrios Capabilities Demonstrated in Darwin Atlas

This document details how the Darwin Atlas showcases Demetrios' unique capabilities.

---

## 1. Units of Measure

### Concept

Demetrios supports **dimensional analysis** at compile time, preventing unit errors.

### Current Status

**Documented but not yet enforced**: The architecture is ready for unit integration, but explicit unit types are not yet implemented in the Demetrios compiler.

### Where It Would Be Used

#### Operators (`operators.d`)

```d
// Future implementation with units
use units::{bp, nt};

type BasePair = Quantity<i64, "bp">;
type Nucleotide = Quantity<u8, "nt">;

fn sequence_length(seq: &Sequence) -> BasePair {
    seq.len() as BasePair  // Automatic unit conversion
}

fn shift(seq: &Sequence, k: BasePair) -> Sequence {
    // Compiler ensures k has correct unit
    // Prevents: shift(seq, 3.5) // Error: expected BasePair, found f64
}
```

#### Exact Symmetry (`exact_symmetry.d`)

```d
fn orbit_size(seq: &Sequence) -> BasePair {
    // Orbit size has same unit as sequence length
    compute_orbit(seq).len() as BasePair
}
```

### Benefits

- **Type Safety**: Prevents mixing base pairs with nucleotides
- **Documentation**: Units make code self-documenting
- **Error Prevention**: Catches unit mismatches at compile time

---

## 2. Refinement Types

### Concept

**Refinement types** add constraints to base types, verified by SMT solver at compile time.

### Current Implementation

Constraints are **documented** but not yet enforced at type level. The code structure is ready for refinement type integration.

### Examples in Code

#### Normalized Distance (`approx_metric.d`)

```d
/// Returns value in [0.0, 1.0]
/// Future: type NormalizedDistance = { x: f64 | 0.0 <= x && x <= 1.0 }
pub fn dmin_normalized(seq: &Sequence) -> f64 {
    let d = dmin(seq) as f64;
    let len = seq.len() as f64;
    // SMT solver would verify: 0 ≤ d/len ≤ 1
    d / len
}
```

**Mathematical Proof**:
- `d_min(w) ∈ [0, n]` where n = |w|
- Therefore: `d_min(w) / n ∈ [0, 1]`

#### Orbit Ratio (`exact_symmetry.d`)

```d
/// Returns value in [1/(2n), 1.0]
/// Future: type OrbitRatio = { r: f64 | 1.0/(2.0*n) <= r && r <= 1.0 }
pub fn orbit_ratio(seq: &Sequence) -> f64 {
    let n = seq.len();
    let size = orbit_size(seq) as f64;
    let denom = (2 * n) as f64;
    // SMT solver would verify: 1/(2n) ≤ size/(2n) ≤ 1
    size / denom
}
```

**Mathematical Proof**:
- Orbit size ∈ {1, 2, 4, ..., 2n} (Lagrange's theorem)
- Therefore: `size / (2n) ∈ [1/(2n), 1.0]`

### Benefits

- **Correctness**: Constraints verified at compile time
- **Documentation**: Types document invariants
- **Refactoring Safety**: SMT solver catches constraint violations

---

## 3. Epistemic Computing

### Concept

**Epistemic computing** tracks confidence, provenance, and uncertainty through computations.

### Current Implementation

**Fully implemented** in `verify_knowledge.d`.

### Knowledge Record Schema

```d
struct Knowledge<T> {
    value: T,                    // The metric value
    epsilon: Option<f64>,         // Error bound (≥ 0)
    confidence: Option<f64>,     // Confidence in [0, 1]
    validity: ValidityInfo,       // Domain constraints
    provenance: ProvenanceInfo    // Source tracing
}
```

### Validation Rules

1. **Epsilon Constraint**: `epsilon >= 0` (error bounds cannot be negative)
2. **Confidence Constraint**: `confidence ∈ [0, 1]` (probability-like measure)
3. **Validity Predicate**: Domain constraints hold (e.g., `0 ≤ orbit_ratio ≤ 1`)
4. **Provenance**: All provenance fields present and non-empty
5. **Join Integrity**: `replicon_id` exists in `atlas_replicons.csv`
6. **No-Miracles**: Epsilon cannot decrease without explicit rule

### Example Usage

```d
// Validate Knowledge record
match validate_knowledge_file("atlas_knowledge.jsonl") {
    Ok(report) => {
        // All epistemic invariants satisfied
        println!("Validation passed: {} records", report.total_records);
    }
    Err(e) => {
        // Epistemic violation detected
        println!("Validation failed: {}", e);
    }
}
```

### Benefits

- **Reproducibility**: Full traceability to source data
- **Uncertainty Propagation**: Explicit error bounds
- **Regulatory Compliance**: FDA/EMA-style provenance
- **Scientific Rigor**: Confidence scores and validity checks

---

## 4. Algebraic Effects

### Concept

**Algebraic effects** provide composable effect handlers for IO, allocation, mutation, etc.

### Current Implementation

Effects are **implicit** in current Demetrios but documented in function signatures.

### Examples in Code

#### IO Effect (`verify_knowledge.d`)

```d
/// Uses IO effect for file operations
pub fn validate_knowledge_file(path: &str) -> Result<Report, IoError> with IO {
    // IO effect: function performs I/O
    let content = read_file(path)?;  // ? propagates IO errors
    // ... validation ...
    Ok(report)
}
```

#### Allocation Effect (All modules)

```d
/// Uses Alloc effect (implicit in current Demetrios)
fn compute_orbit(seq: &Sequence) -> HashSet<Sequence> with Alloc {
    // Alloc effect: function allocates memory
    let orbit = HashSet::new();
    // ... computation ...
    orbit
}
```

### Benefits

- **Composability**: Effects compose naturally
- **Type Safety**: Effect system tracks side effects
- **Optimization**: Compiler can optimize based on effects

---

## 5. GPU-Native (Future)

### Concept

Demetrios supports **first-class GPU memory regions and kernel syntax**.

### Potential Application

Parallelize orbit computation across multiple sequences:

```d
// Future: GPU kernel for parallel orbit computation
kernel fn parallel_orbit_size(
    sequences: &[Sequence],
    results: &mut [usize]
) {
    let i = gpu.thread_id.x;
    results[i] = orbit_size(&sequences[i]);
}
```

### Current Status

**Not yet implemented** in Darwin Atlas, but architecture is ready.

---

## Summary

| Capability | Status | Location | Demonstrated? |
|------------|--------|----------|---------------|
| Units of Measure | ⚠️ Documented | `operators.d` | ⚠️ Partial |
| Refinement Types | ⚠️ Documented | `approx_metric.d`, `exact_symmetry.d` | ⚠️ Partial |
| Epistemic Computing | ✅ Implemented | `verify_knowledge.d` | ✅ Yes |
| Algebraic Effects | ⚠️ Implicit | All modules | ⚠️ Partial |
| GPU-Native | ❌ Not used | - | ❌ No |

---

## Future Enhancements

1. **Enforce Units**: Add explicit unit types when compiler supports
2. **Enforce Refinements**: Add SMT-backed refinement types
3. **Expand Epistemic**: Apply Knowledge records to all metrics
4. **GPU Kernels**: Parallelize computation on GPU
5. **Effect Documentation**: Make effects explicit in all functions

