# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Darwin Operator Symmetry Atlas (DOSA) — A reproducible database of operator-defined symmetries in bacterial replicons for Scientific Data (Nature Portfolio).

**Architecture**: Hybrid Julia (Layers 0-1) + Sounio (Layer 2) with mandatory cross-validation between implementations.

**NO PYTHON**. This project uses exclusively Julia and Sounio.

## Build Commands

```bash
# Setup
make setup-julia              # Install Julia dependencies
make setup-sounio             # Check Sounio kernels (requires souc compiler)

# Build
make all                      # Full build (setup + sounio + julia + test)
make julia                    # Build Julia package only
make sounio                   # Build Sounio kernels only

# Test
make test                     # Run all tests
make test-julia               # Julia tests only
make test-sounio              # Sounio tests only

# Pipeline
make pipeline MAX=200 SEED=42 # Run analysis pipeline
make cross-validate           # Compare Sounio vs Julia outputs
make validate                 # Run validation only

# Epistemic Knowledge Layer
make epistemic MAX=200        # Export + verify Knowledge JSONL
make export-knowledge         # Export Atlas to Knowledge JSONL
make verify-knowledge         # Verify against Sounio schema

# Reproducibility
make reproduce                # Clean + rebuild + verify checksums
make clean                    # Remove build artifacts
make cleanall                 # Remove all data including downloads
```

### Julia REPL Development

```julia
using Pkg; Pkg.activate("julia")
Pkg.instantiate()                    # First time
Pkg.test()                           # Run test suite
include("julia/scripts/run_pipeline.jl")
```

## Architecture

```
Layer 3: Artifacts     → CSV/JSONL/Parquet (Zenodo DOI)
Layer 2: Sounio        → High-performance kernels with epistemic computing
Layer 1: Julia         → Orchestration, NCBI fetch, validation, FFI to Sounio
Layer 0: Julia Pure    → Reference implementation (fallback, cross-validation)
```

### Core Modules

| Julia Module | Sounio Module | Purpose |
|--------------|---------------|---------|
| `Operators.jl` | `operators.sio` | S/R/K/RC operator definitions |
| `ExactSymmetry.jl` | `exact_symmetry.sio` | Fixed points, orbit ratio |
| `ApproxMetric.jl` | `approx_metric.sio` | d_min/L normalized distance |
| `QuaternionLift.jl` | `quaternion.sio` | Dic_n → D_n verification |
| `SounioFFI.jl` | `ffi.sio` | C ABI bridge |
| `CrossValidation.jl` | — | Implementation comparison |
| `NCBIFetch.jl` | — | Data acquisition + manifest |

### Operator Definitions (D₄ Group)

| Symbol | Name | Definition |
|--------|------|------------|
| I | Identity | σ(i) = s_i |
| R | Reverse | σ(i) = s_{n-1-i} |
| K | Complement | σ(i) = complement(s_i) |
| RC | Rev-Comp | σ(i) = complement(s_{n-1-i}) |

## Critical Constraints

### Cross-Validation Requirement
Sounio and Julia must produce **identical** outputs:
- Tolerance: 0 for discrete values, 1e-12 for floating point
- **Any divergence is a blocking bug** — stop and debug immediately

### Scientific Data Compliance
- NO RESULTS in Data Descriptor — Methods + Data Records + Technical Validation only
- Data citations required with DOIs
- Must work with `git clone` + `make reproduce`

### Reproducibility Requirements
- All random seeds explicit and logged
- `Manifest.toml` must be committed (never gitignored)
- SHA256 checksums for all downloaded data

## Coding Standards

### Julia (BlueStyle)
```julia
"""
    orbit_ratio(seq::LongDNA{4}) -> Float64

Compute orbit ratio: |orbit| / |D₄|.
"""
function orbit_ratio(seq::LongDNA{4})
    orbit_size(seq) / 4.0
end
```
- Concrete types, avoid `Any`
- All exported functions need docstrings
- Property-based testing where applicable

### Sounio
```sounio
/// Orbit ratio: |orbit| / (2n)
#[inline]
pub fn orbit_ratio(seq: &Sequence) -> f64 {
    let n = seq.len();
    if n == 0 { return 1.0; }
    orbit_size(seq) as f64 / (2.0 * n as f64)
}
```
- Use `pub fn` for public functions
- Use `var` for mutable, `let` for immutable bindings
- Use `#[inline]` for hot paths
- Modules with `module name;` and `import module::{items}`

### Commits
```
feat: add quaternion lift verification
fix: correct circular window extraction
test: add property-based tests for operators
```

## Data Schema

### atlas_replicons.csv
| Field | Type | Constraint |
|-------|------|------------|
| assembly_accession | String | GCF_... format |
| replicon_id | String | Internal stable ID |
| replicon_type | Enum | {chromosome, plasmid, other} |
| length_bp | Int64 | > 0 |
| gc_fraction | Float64 | 0.0 ≤ x ≤ 1.0 |
| taxonomy_id | Int64 | NCBI taxid |
| checksum_sha256 | String | 64 hex chars |

### atlas_windows_exact.csv
| Field | Type | Constraint |
|-------|------|------------|
| replicon_id | String | FK → atlas_replicons |
| window_length | Int64 | bp |
| window_start | Int64 | 0-indexed, circular |
| orbit_ratio | Float64 | 0.25 ≤ x ≤ 1.0 |
| is_palindrome_R | Bool | |
| is_fixed_RC | Bool | |
| orbit_size | Int64 | ∈ {1, 2, 4} |

### approx_symmetry_stats.csv
| Field | Type | Constraint |
|-------|------|------------|
| replicon_id | String | |
| window_length | Int64 | |
| d_min | Float64 | ≥ 0 |
| d_min_over_L | Float64 | 0 ≤ x ≤ 1 |
| transform_family | Enum | {dihedral, RC, identity} |

### dicyclic_lifts.csv
| Field | Type | Constraint |
|-------|------|------------|
| dihedral_order | Int64 | 4, 8, 16 |
| verified_double_cover | Bool | |
| lift_group | String | Dic_n notation |
| relations_satisfied | Bool | |

## Target Scale

| Metric | Target |
|--------|--------|
| Replicons | ~50,000 bacterial genomes |
| Window sizes | 100, 500, 1000, 5000, 10000 bp |
| Memory peak | < 64 GB (192 GB available) |
| GPU | L4 24GB + RTX 4000 Ada 20GB available |

## Key Files

| File | Purpose |
|------|---------|
| `julia/src/Types.jl` | All type definitions |
| `julia/src/Operators.jl` | Reference implementation |
| `julia/test/runtests.jl` | Test suite entry |
| `sounio/src/lib.sio` | Sounio library root |
| `sounio/src/operators.sio` | Sounio operators |
| `Makefile` | Build commands |

## External References

- **Sounio Language**: https://github.com/sounio-lang/sounio
- **BioJulia**: BioSequences.jl, FASTX.jl
- **NCBI Datasets API**: Data acquisition

## LLM Offload

Use `llm-offload` for bulk generation to save Anthropic tokens:
- `llm-offload -t expand -p local` - Expand outline (free, local Mistral)
- `llm-offload -t paraphrase -p grok` - Rewrite text (Grok)
- `llm-offload -t scaffold -p local` - Code boilerplate
- `llm-offload -t variations -p minimax` - Generate alternatives
- `llm-offload --list-templates` - See all templates

**Workflow**: Claude designs → llm-offload expands → Claude critiques

