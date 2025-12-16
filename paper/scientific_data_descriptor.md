# DSLG Atlas: A Database of Operator-Defined Symmetries in Complete Bacterial Replicons

**Data Descriptor for Scientific Data (Nature Portfolio)**

---

## Abstract

We present DSLG Atlas (Demetrios Operator Symmetry Atlas), a curated database of operator-defined symmetries in complete bacterial replicons from NCBI RefSeq. The atlas implements dihedral group D_n actions (identity, reverse, complement, reverse-complement) on circular DNA sequences, computing exact symmetry metrics (orbit sizes, palindrome detection, reverse-complement fixed sequences) and approximate symmetry measures (minimum normalized dihedral distance d_min/L). The dataset comprises symmetry metrics for bacterial chromosomes and plasmids, with full provenance tracking via an epistemic Knowledge layer. All computations are reproducible through a hybrid Julia/Demetrios pipeline with cross-validation between implementations. The atlas serves as a reference resource for studying sequence symmetry in bacterial genomes.

---

## Background & Summary

Circular bacterial genomes possess intrinsic symmetries under the dihedral group of operators: identity (I), reverse (R), complement (K), and reverse-complement (RC). These operators form the dihedral group D_4 when combined, governing transformations that leave circular DNA molecules invariant under reading direction and strand selection.

Understanding sequence symmetry has applications in:
- Replication origin identification
- Genome assembly validation
- Evolutionary analysis of GC skew patterns
- Detection of mobile genetic elements

DSLG Atlas provides:
1. **Exact symmetry metrics**: Orbit sizes under D_4 action, identification of palindromic (R-fixed) and reverse-complement-fixed sequences
2. **Approximate symmetry metrics**: Minimum normalized dihedral distance d_min/L, measuring deviation from perfect symmetry
3. **Algebraic verification**: Dicyclic group Dic_n double cover verification via quaternion representation
4. **Epistemic provenance**: Full tracking of computation parameters, versions, and validation status

The atlas is generated from NCBI RefSeq complete bacterial genomes using a deterministic pipeline with explicit random seeds for reproducibility.

---

## Methods

### Data Acquisition

Genome sequences are downloaded from NCBI RefSeq using the datasets CLI:
- **Filter**: Assembly level = "complete genome"
- **Source**: NCBI RefSeq bacterial genomes
- **Selection**: Deterministic random sampling with configurable seed and maximum count

Download manifests record:
- Assembly accessions
- Download timestamps
- SHA256 checksums for integrity verification

### Operator Definitions

The four DNA operators form the dihedral group D_4:

| Operator | Symbol | Definition | Mathematical Form |
|----------|--------|------------|-------------------|
| Identity | I | s_i → s_i | σ(i) = s_i |
| Reverse | R | s_i → s_{n-1-i} | σ(i) = s_{n-1-i} |
| Complement | K | s_i → complement(s_i) | A↔T, G↔C |
| Reverse-Complement | RC | R∘K | σ(i) = complement(s_{n-1-i}) |

These operators satisfy the group relations:
- R² = I, K² = I, RC² = I
- R∘K = K∘R = RC

### Exact Symmetry Computation

For each sequence window, we compute:
- **Orbit size**: Number of distinct sequences under D_4 action (1, 2, or 4)
- **Orbit ratio**: orbit_size / 4 (range: 0.25 to 1.0)
- **R-fixed (palindrome)**: seq = R(seq)
- **RC-fixed**: seq = RC(seq)

### Approximate Symmetry Computation

The minimum dihedral distance d_min is computed as:
```
d_min = min{d(seq, σ(seq)) : σ ∈ D_4 \ {I}}
```

Normalized by sequence length: d_min/L ∈ [0, 1].

### Dicyclic Lift Verification

The dicyclic group Dic_n is verified as a double cover of D_n via quaternion representation:
- Elements: {±1, ±i, ±j, ±k, ...} with |Dic_n| = 4n
- Projection: Dic_n → D_n is 2-to-1
- Relations: verified algebraically

### Implementation Architecture

The pipeline uses a layered architecture:
- **Layer 0 (Julia Pure)**: Reference implementation for reproducibility
- **Layer 1 (Julia Orchestration)**: NCBI fetch, validation, pipeline control
- **Layer 2 (Demetrios)**: High-performance kernels with units of measure and refinement types

Cross-validation ensures both implementations produce identical results (tolerance: 0 for integers, 10⁻¹² for floats).

### Epistemic Knowledge Layer

All computed values are wrapped in Knowledge[T] records with:
- **Provenance**: Git SHA, timestamp, NCBI accessions, pipeline parameters
- **Uncertainty**: Error bounds (epsilon ≥ 0)
- **Confidence**: Epistemic confidence [0, 1]
- **Validity**: Domain constraint predicates

---

## Data Records

The dataset is organized into the following files:

### Core Tables

| File | Records | Description |
|------|---------|-------------|
| `atlas_replicons.csv` | ~N | Replicon metadata (accession, length, GC, taxonomy) |
| `dicyclic_lifts.csv` | 3 | Dic_n → D_n verification for n ∈ {2, 4, 8} |
| `quaternion_results.csv` | 3 | Quaternion lift results |

### Epistemic Layer

| File | Format | Description |
|------|--------|-------------|
| `atlas_knowledge.jsonl` | JSONL | Full Knowledge records with provenance |
| `schema_atlas_knowledge.json` | JSON Schema | Record structure definition |
| `atlas_knowledge_report.md` | Markdown | Validation summary |

### Manifest

| File | Description |
|------|-------------|
| `manifest.jsonl` | Download manifest with timestamps |
| `checksums.sha256` | SHA256 hashes for all source files |
| `pipeline_metadata.json` | Pipeline parameters and versions |

See `docs/DATA_DICTIONARY.md` for complete column definitions.

---

## Technical Validation

### Validation Protocol

Data quality is ensured through three validation gates:

**Gate 1: Schema Compliance**
- Provenance object present with required fields
- Git SHA and timestamp recorded
- Pipeline parameters (seed, max) captured
- Assembly and replicon identifiers present

**Gate 2: Data Integrity**
- GC fraction in valid range [0, 1]
- Sequence length positive
- Orbit ratio in valid range [0.25, 1]
- Foreign key integrity (replicon_id exists)

**Gate 3: Epistemic Invariants**
- Error bounds non-negative (epsilon ≥ 0)
- Confidence in valid range [0, 1]
- Validity predicates satisfied
- No miracles (epsilon cannot decrease without explicit derivation)

### Validation Counts

For the v0.1.0-epistemic release:
- **Total Records**: 636
- **Total Checks**: 7,212
- **Passed**: 7,212
- **Failed**: 0
- **Pass Rate**: 100%

### Cross-Validation

Julia and Demetrios implementations are compared:
- Integer values: exact match required
- Floating-point values: |Δ| < 10⁻¹²
- Any divergence is treated as a blocking bug

---

## Usage Notes

### Reproduction

To regenerate the dataset:

```bash
git clone https://github.com/agourakis82/darwin-atlas.git
cd darwin-atlas
make setup-julia
make pipeline MAX=50 SEED=42
make epistemic MAX=50 SEED=42
make snapshot MAX=50 SEED=42
```

### Snapshot Creation

The `make snapshot` command creates a deterministic archive:

```bash
make snapshot MAX=50 SEED=42
# Output: dist/atlas_snapshot_v1/
```

### File Access

CSV files can be read with standard tools:
- Python: `pandas.read_csv()`
- R: `read.csv()`
- Julia: `CSV.read()`

JSONL files are processed line-by-line:
```python
import json
with open("atlas_knowledge.jsonl") as f:
    for line in f:
        record = json.loads(line)
```

---

## Data Availability

The DSLG Atlas dataset is available at:

- **GitHub**: https://github.com/agourakis82/darwin-atlas
- **Zenodo**: [DOI to be assigned upon deposit]

Release: v0.1.0-epistemic

---

## Code Availability

Source code for the DSLG Atlas pipeline is available at:

- **GitHub**: https://github.com/agourakis82/darwin-atlas
- **License**: MIT (code), CC-BY 4.0 (data)

Requirements:
- Julia 1.10+
- Demetrios compiler (optional, for Layer 2)

---

## References

1. NCBI RefSeq Database. https://www.ncbi.nlm.nih.gov/refseq/
2. Scientific Data Data Descriptor Guidelines. https://www.nature.com/sdata/
3. Demetrios Programming Language. https://github.com/Chiuratto-AI/demetrios
4. BioJulia: BioSequences.jl. https://biojulia.net/

---

## Author Contributions

D.C.A. conceived the project, designed the architecture, implemented the pipeline, performed validation, and wrote the manuscript.

---

## Competing Interests

The author declares no competing interests.

---

## Acknowledgements

[To be added]

---

**Corresponding Author**: Demetrios Chiuratto Agourakis (demetrios@agourakis.med.br)

---

*Prepared for Scientific Data (Nature Portfolio) — Data Descriptor format*
*Version: Draft 1.0*
*Date: 2025-12-16*
