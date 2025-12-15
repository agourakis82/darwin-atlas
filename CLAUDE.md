# CLAUDE.md — Darwin Operator Symmetry Atlas

## Project Identity

**Name**: Darwin Operator Symmetry Atlas (DOSA)
**Version**: 2.0.0-alpha
**Principal Investigator**: Demetrios Chiuratto Agourakis
**Target Publication**: Scientific Data (Nature Portfolio) — Data Descriptor

---

## Mission Statement

Build a reproducible, DOI-versioned database of operator-defined symmetries in complete bacterial replicons, implementing a hybrid Demetrios + Julia architecture with cross-validation between implementations.

---

## Architecture Overview
```
Layer 3: Artifacts     → CSV/JSONL/Parquet (Zenodo DOI)
Layer 2: Demetrios     → High-performance kernels with epistemic computing
Layer 1: Julia         → Orchestration, NCBI fetch, validation
Layer 0: Julia Pure    → Reference implementation (fallback, cross-validation)
```

---

## Directory Structure (Canonical)
```
darwin-atlas/
├── CLAUDE.md                     # THIS FILE
├── README.md                     # Project documentation
├── Makefile                      # Build orchestration
├── .zenodo.json                  # DOI metadata
├── justfile                      # Alternative to Make (optional)
│
├── demetrios/                    # Layer 2: Demetrios Kernels
│   ├── demetrios.toml            # Project config
│   ├── src/
│   │   ├── lib.d                 # Library root, exports
│   │   ├── operators.d           # S/R/K/RC/M/D/I/V definitions
│   │   ├── exact_symmetry.d      # Fixed points, orbit ratio
│   │   ├── approx_metric.d       # d_min/L with units
│   │   ├── quaternion.d          # Dic_n lift verification
│   │   └── ffi.d                 # C ABI exports for Julia
│   └── tests/
│       ├── test_operators.d
│       ├── test_symmetry.d
│       └── test_quaternion.d
│
├── julia/                        # Layers 0 + 1
│   ├── Project.toml
│   ├── Manifest.toml             # MUST BE COMMITTED
│   ├── src/
│   │   ├── DarwinAtlas.jl        # Module root
│   │   ├── Types.jl              # Shared type definitions
│   │   ├── Operators.jl          # Pure Julia operators (Layer 0)
│   │   ├── ExactSymmetry.jl      # Pure Julia exact symmetry
│   │   ├── ApproxMetric.jl       # Pure Julia approx metric
│   │   ├── QuaternionLift.jl     # Pure Julia quaternion
│   │   ├── NCBIFetch.jl          # NCBI download + manifest
│   │   ├── Validation.jl         # Technical validation suite
│   │   ├── DemetriosFFI.jl       # ccall wrappers (Layer 1→2)
│   │   └── CrossValidation.jl    # Demetrios vs Julia comparison
│   ├── test/
│   │   ├── runtests.jl
│   │   ├── test_operators.jl
│   │   ├── test_symmetry.jl
│   │   ├── test_ffi.jl
│   │   └── test_cross_validation.jl
│   └── scripts/
│       ├── fetch_ncbi.jl
│       ├── run_pipeline.jl
│       ├── generate_tables.jl
│       └── technical_validation.jl
│
├── data/                         # Layer 3: Outputs
│   ├── raw/                      # Downloaded sequences (gitignored)
│   ├── manifest/
│   │   ├── manifest.jsonl
│   │   ├── checksums.sha256
│   │   └── pipeline_metadata.json
│   └── tables/
│       ├── atlas_replicons.csv
│       ├── atlas_windows_exact.csv
│       ├── approx_symmetry_stats.csv
│       ├── approx_symmetry_summary.csv
│       ├── dicyclic_lifts.csv
│       └── quaternion_results.csv
│
├── paper/                        # Scientific Data manuscript
│   ├── main.tex
│   ├── references.bib
│   ├── figures/
│   └── supplementary/
│
└── .github/
    └── workflows/
        └── ci.yml                # Automated testing
```

---

## Technical Specifications

### Operator Definitions (Mathematical Foundation)

| Symbol | Name | Definition | Group |
|--------|------|------------|-------|
| I | Identity | σ(i) = s_i | D_4 |
| R | Reverse | σ(i) = s_{n-1-i} | D_4 |
| K | Complement | σ(i) = complement(s_i) | D_4 |
| RC | Rev-Comp | σ(i) = complement(s_{n-1-i}) | D_4 |
| S | Shift | σ(i) = s_{(i+1) mod n} | Cyclic |
| M | Mirror | Context-dependent | — |
| D | Dihedral | Full D_n action | D_n |
| V | Vertical | Strand swap | — |

### Data Schema (Canonical)

#### atlas_replicons.csv
```
assembly_accession: String (GCF_...)
replicon_id: String (internal stable ID)
replicon_accession: String? (RefSeq/GenBank)
replicon_type: Enum {chromosome, plasmid, other}
length_bp: Int64 (> 0)
gc_fraction: Float64 (0.0 ≤ x ≤ 1.0)
taxonomy_id: Int64
taxonomy_name: String
source_db: Enum {RefSeq, GenBank}
download_date: Date (ISO 8601)
checksum_sha256: String
```

#### atlas_windows_exact.csv
```
replicon_id: String (FK → atlas_replicons)
window_length: Int64 (bp)
window_start: Int64 (0-indexed, circular)
orbit_ratio: Float64 (0.25 ≤ x ≤ 1.0)
is_palindrome_R: Bool
is_fixed_RC: Bool
orbit_size: Int64 (1, 2, or 4)
```

#### approx_symmetry_stats.csv
```
replicon_id: String
window_length: Int64
window_start: Int64
d_min: Float64 (≥ 0)
d_min_over_L: Float64 (0 ≤ x ≤ 1)
transform_family: Enum {dihedral, RC, identity}
nearest_transform: String
```

#### dicyclic_lifts.csv
```
replicon_id: String
dihedral_order: Int64 (4, 8, 16)
verified_double_cover: Bool
lift_group: String (Dic_n notation)
verification_method: String
num_elements_checked: Int64
relations_satisfied: Bool
```

#### quaternion_results.csv
```
experiment_id: String
condition: Enum {group, semigroup}
chain_length: Int64
n_trials: Int64
seed: Int64
baseline_markov1_acc: Float64
baseline_markov2_acc: Float64
quaternion_acc: Float64
p_value_vs_markov2: Float64
```

---

## Implementation Priorities

### Phase 1: Foundation (Week 1)
1. [ ] Initialize Julia project with dependencies
2. [ ] Implement `Types.jl` with all data structures
3. [ ] Implement `Operators.jl` (pure Julia, Layer 0)
4. [ ] Unit tests for operators (property-based)
5. [ ] Initialize Demetrios project structure

### Phase 2: Core Algorithms (Week 2)
1. [ ] `ExactSymmetry.jl` — orbit computation, fixed points
2. [ ] `ApproxMetric.jl` — d_min calculation, baseline shuffle
3. [ ] `QuaternionLift.jl` — Dic_n verification
4. [ ] Corresponding Demetrios implementations
5. [ ] `DemetriosFFI.jl` — ccall wrappers

### Phase 3: Pipeline (Week 3)
1. [ ] `NCBIFetch.jl` — download, manifest, checksums
2. [ ] `run_pipeline.jl` — end-to-end orchestration
3. [ ] `CrossValidation.jl` — Demetrios vs Julia comparison
4. [ ] `Validation.jl` — Technical validation suite

### Phase 4: Outputs (Week 4)
1. [ ] Generate all CSV tables
2. [ ] `technical_validation.jl` — full validation report
3. [ ] Figures for paper
4. [ ] Zenodo deposit preparation

---

## Coding Standards

### Julia
- **Style**: Follow BlueStyle (https://github.com/invenia/BlueStyle)
- **Types**: Use concrete types, avoid `Any`
- **Docstrings**: Required for all exported functions
- **Tests**: Property-based testing with Supposition.jl where applicable
- **Manifest.toml**: ALWAYS commit, NEVER add to .gitignore

### Demetrios
- **Style**: Follow project conventions in Chiuratto-AI/demetrios
- **Units**: Use units of measure for all physical quantities
- **Refinement**: Use refinement types for domain constraints
- **Effects**: Explicitly declare all effects (IO, Alloc, GPU)
- **FFI**: All exports must have C ABI via `#[export]`

### General
- **Commits**: Conventional commits (feat:, fix:, docs:, test:, refactor:)
- **Branches**: `main` protected, develop on feature branches
- **CI**: All tests must pass before merge

---

## Dependencies

### Julia (Project.toml)
```toml
[deps]
BioSequences = "7e6ae17a-..."
FASTX = "c2308a5c-..."
CSV = "336ed68f-..."
DataFrames = "a93c6f00-..."
JSON3 = "0f8b85d8-..."
SHA = "ea8e919c-..."
HTTP = "cd3eb016-..."
Quaternions = "94ee1d12-..."
CUDA = "052768ef-..."  # Optional
Statistics = "10745b16-..."
Test = "8dfed614-..."
Supposition = "..."  # Property-based testing

[compat]
julia = "1.10"
```

### Demetrios
- Compiler: v0.63.0+
- Features: `--features full` (units, refinement, gpu, ffi)

---

## Critical Constraints

### Scientific Data Compliance
1. **NO RESULTS IN DATA DESCRIPTOR**: Methods + Data Records + Technical Validation only
2. **Data citations**: DOI required for all datasets
3. **Reproducibility**: Must work with `git clone` + `make reproduce`

### Reproducibility Requirements
1. All random seeds must be explicit and logged
2. Manifest.toml committed (Julia)
3. Cargo.lock equivalent for Demetrios
4. SHA256 checksums for all downloaded data
5. Pipeline metadata JSON with versions, timestamps, parameters

### Cross-Validation Criteria
- Demetrios and Julia implementations must produce **identical** outputs
- Tolerance: 0 for discrete values, 1e-12 for floating point
- Any divergence is a **blocking bug**

---

## Commands Reference

### Build
```bash
# Full build
make all

# Demetrios only
make demetrios

# Julia only
make julia

# Tests
make test

# Cross-validation
make cross-validate

# Full pipeline
make pipeline

# Reproducibility check (clean + rebuild + compare checksums)
make reproduce
```

### Julia REPL
```julia
# Activate project
using Pkg; Pkg.activate("julia")

# Run tests
Pkg.test()

# Run pipeline
include("julia/scripts/run_pipeline.jl")
```

### Demetrios
```bash
cd demetrios
dc build --release --target=cdylib
dc test
```

---

## Error Handling Protocol

When encountering errors:

1. **Compilation errors**: Fix immediately, do not proceed
2. **Test failures**: Investigate root cause, fix before continuing
3. **Cross-validation divergence**: STOP. This is critical. Debug until resolved.
4. **NCBI fetch failures**: Implement retry with exponential backoff
5. **Memory issues**: Profile, optimize, or batch processing

---

## Communication Protocol

### Progress Updates
After completing each major component, provide:
1. What was implemented
2. Test results summary
3. Any deviations from plan
4. Next steps

### Blocking Issues
If blocked, clearly state:
1. What is blocking
2. What was attempted
3. Proposed solutions
4. Decision needed from PI

---

## Quality Gates

Before marking Phase complete:

- [ ] All unit tests pass
- [ ] No compiler warnings (Julia: `--warn-overwrite`, Demetrios: `-W all`)
- [ ] Documentation complete for new functions
- [ ] Cross-validation passes (if applicable)
- [ ] Code reviewed (self-review checklist below)

### Self-Review Checklist
- [ ] No hardcoded paths
- [ ] No magic numbers (use named constants)
- [ ] Error messages are informative
- [ ] Edge cases handled
- [ ] Performance acceptable for target scale

---

## Target Scale

- **Replicons**: ~50,000 complete bacterial genomes
- **Window sizes**: 100, 500, 1000, 5000, 10000 bp
- **Processing time target**: < 24h on single node (L4 GPU available)
- **Memory budget**: 192 GB DDR5 available, target < 64 GB peak

---

## References

1. SkewDB paper and repository (template for Data Descriptor)
2. Scientific Data Data Descriptor guidelines
3. Demetrios Language Specification (Chiuratto-AI/demetrios)
4. BioJulia documentation
5. NCBI Datasets API documentation

---

## Contact

- **PI**: Demetrios Chiuratto Agourakis
- **Repository**: [to be filled]
- **Issues**: GitHub Issues for this repository

---

*Last updated: 2025-12-15*
*CLAUDE.md version: 1.0.0*
