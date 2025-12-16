# Milestone 0 — Repo Discovery + Implementation Plan

**Date**: 2025-12-16  
**Author**: Demetrios Chiuratto Agourakis  
**Status**: ✅ Complete

---

## Discovery Summary

### Current Pipeline Entrypoints

1. **Makefile** (`Makefile`)
   - Primary target: `make atlas MAX=N SEED=N`
   - Unified pipeline: `julia/scripts/run_atlas.jl`
   - Query layer: `make query QUERY="SQL"`
   - Epistemic export: `make epistemic MAX=N SEED=N`
   - Snapshot: `make snapshot MAX=N SEED=N`

2. **Main Pipeline Scripts**
   - `julia/scripts/run_atlas.jl` — Unified Atlas v2 runner (Parquet + CSV)
   - `julia/scripts/run_pipeline.jl` — Legacy CSV-only pipeline
   - `julia/scripts/query_atlas.jl` — DuckDB query interface
   - `julia/scripts/export_knowledge.jl` — Epistemic Knowledge export

### Current Outputs

**CSV Tables** (`data/tables/`):
- `atlas_replicons.csv` — Replicon metadata
- `dicyclic_lifts.csv` — Algebraic verification
- `quaternion_results.csv` — Quaternion lift results

**Parquet Dataset** (`dist/atlas_dataset_v2/`):
- Partitioned by: `source_db`, `replicon_type`, `length_bin`
- CSV views in `csv/` subdirectory
- Manifest + checksums in `manifest/`

**Epistemic Knowledge** (`data/epistemic/`):
- `atlas_knowledge.jsonl` — Knowledge records
- `schema_atlas_knowledge.json` — JSON schema
- `atlas_knowledge_report.md` — Validation report

### NCBI Fetch Implementation

**Location**: `julia/src/NCBIFetch.jl`

**Features**:
- Downloads from NCBI RefSeq assembly_summary.txt
- Filters: `assembly_level == "Complete Genome"`
- Manifest: `data/manifest/manifest.jsonl` (JSONL format)
- Checksums: `data/manifest/checksums.sha256`
- Retry logic with exponential backoff
- Deterministic caching (skip if file exists + checksum matches)

### Demetrios Validator

**Location**: `demetrios/src/verify_knowledge.d`

**Status**: Exists but needs expansion for new metrics (PR3)

---

## Current Architecture Assessment

### ✅ Implemented (Milestone 1 — Scale Architecture)

1. **Parquet Storage** (`julia/src/Storage.jl`)
   - Partitioned write/read
   - Hive-style partitioning
   - CSV export views
   - Length binning strategy

2. **Query Layer** (`julia/src/QueryLayer.jl`)
   - DuckDB integration
   - Example queries for common patterns
   - Schema introspection

3. **NCBI Ingestion**
   - Robust download with retries
   - Manifest tracking
   - Checksum validation

### ❌ Missing (Milestone 2 — Biology Metrics)

1. **k-mer Inversion Symmetry**
   - Module: `julia/src/KmerInversion.jl` (to be created)
   - Tables: `kmer_inversion`, `kmer_inversion_summary`
   - Metrics: X_k, K_L(tau)

2. **GC Skew / Ori-Ter Estimation**
   - Module: `julia/src/GCSkew.jl` (to be created)
   - Tables: `gc_skew_ori_ter`, `replichore_metrics`
   - Metrics: ori_position, ter_position, confidence

3. **Inverted Repeats Enrichment**
   - Module: `julia/src/InvertedRepeats.jl` (to be created)
   - Tables: `inverted_repeats`, `inverted_repeats_summary`
   - Metrics: ir_count, enrichment_ratio, p_value

### ⚠️ Partial (Milestone 3 — Epistemic Knowledge)

1. **Knowledge Export** (`julia/scripts/export_knowledge.jl`)
   - ✅ Exists for current metrics
   - ❌ Needs expansion for new metrics (k-mer, skew, IR)

2. **Validator** (`demetrios/src/verify_knowledge.d`)
   - ✅ Schema validation
   - ❌ Needs join integrity checks
   - ❌ Needs no-miracles rule

---

## Clean Layout Proposal

```
darwin-atlas/
├── julia/
│   ├── src/
│   │   ├── # Core (existing)
│   │   ├── DarwinAtlas.jl
│   │   ├── Types.jl
│   │   ├── Operators.jl
│   │   ├── ExactSymmetry.jl
│   │   ├── ApproxMetric.jl
│   │   ├── QuaternionLift.jl
│   │   │
│   │   ├── # Scale (PR1 - ✅ done)
│   │   ├── Storage.jl              # Parquet + partitioning
│   │   ├── QueryLayer.jl           # DuckDB interface
│   │   │
│   │   ├── # Biology (PR2 - ❌ to implement)
│   │   ├── KmerInversion.jl        # k-mer symmetry
│   │   ├── GCSkew.jl               # Ori/ter estimation
│   │   ├── InvertedRepeats.jl      # IR detection
│   │   │
│   │   ├── # Infrastructure
│   │   ├── NCBIFetch.jl            # Download + manifest
│   │   ├── Validation.jl           # Technical validation
│   │   ├── DemetriosFFI.jl         # FFI wrappers
│   │   ├── CrossValidation.jl      # Demetrios vs Julia
│   │   │
│   │   └── # Epistemic (PR3 - ⚠️ partial)
│   │   └── Knowledge.jl           # Knowledge record creation (extend)
│   │
│   └── scripts/
│       ├── run_atlas.jl            # Unified pipeline
│       ├── query_atlas.jl          # Query interface
│       ├── export_knowledge.jl      # Knowledge export (extend)
│       └── verify_knowledge.jl     # Julia fallback validator
│
├── demetrios/
│   └── src/
│       ├── verify_knowledge.d       # Validator (extend)
│       └── ... (existing kernels)
│
├── dist/                           # Generated (gitignored)
│   └── atlas_dataset_v2/
│       ├── partitions/             # Parquet files
│       ├── csv/                    # CSV views
│       ├── epistemic/              # Knowledge JSONL
│       └── manifest/               # Metadata + checksums
│
└── docs/
    ├── DATA_DICTIONARY.md          # Table schemas (PR4)
    ├── PARQUET_SCHEMA.md           # ✅ Exists
    └── QUERY_EXAMPLES.md           # Query patterns (PR1)
```

---

## Implementation Plan: 3 PRs

### PR1: Scale Storage + Snapshot (Milestone 1)

**Status**: ✅ **COMPLETE** (already implemented)

**What exists**:
- Parquet storage with partitioning
- DuckDB query layer
- CSV export views
- Snapshot builder skeleton

**What to verify**:
- [ ] `make atlas MAX=50 SEED=42` produces Parquet + CSV
- [ ] Partitioning works correctly
- [ ] Query layer can read partitions
- [ ] Manifest + checksums generated

**Files**:
- `julia/src/Storage.jl` ✅
- `julia/src/QueryLayer.jl` ✅
- `julia/scripts/run_atlas.jl` ✅
- `scripts/make_snapshot.sh` (verify exists)

---

### PR2: Biology Metrics (Milestone 2)

**Status**: ❌ **TO IMPLEMENT**

**New Modules**:
1. `julia/src/KmerInversion.jl`
   - Function: `compute_kmer_inversion(seq, k_max=10)`
   - Output: DataFrame with columns: `replicon_id`, `k`, `x_k`, `k_l_tau_05`, `k_l_tau_10`, `replichore`

2. `julia/src/GCSkew.jl`
   - Function: `estimate_ori_ter(seq, window_size=1000)`
   - Output: DataFrame with: `replicon_id`, `ori_position`, `ter_position`, `ori_confidence`, `ter_confidence`, `gc_skew_amplitude`
   - Function: `split_replichores(seq, ori, ter)`
   - Output: `(leading_replichore, lagging_replichore)`

3. `julia/src/InvertedRepeats.jl`
   - Function: `detect_inverted_repeats(seq, stem_min=8, loop_max=20)`
   - Function: `compute_baseline_shuffle(seq, method="markov1")`
   - Output: DataFrame with: `replicon_id`, `ir_count`, `ir_density`, `baseline_count`, `enrichment_ratio`, `p_value`

**Integration**:
- Add metric computation to `julia/scripts/run_atlas.jl`
- Write tables to Parquet partitions
- Export CSV views

**Tests**:
- Unit tests for each metric on toy sequences
- Validity range checks
- Baseline comparison tests

**Acceptance**:
- `make atlas MAX=200 SEED=42` produces all biology metric tables
- Each metric has documented validity constraints
- Runtime acceptable (< 1h for MAX=200)

---

### PR3: Epistemic Knowledge Everywhere (Milestone 3)

**Status**: ⚠️ **PARTIAL** (needs expansion)

**Tasks**:

1. **Expand Knowledge Schema**
   - Add record types: `kmer_metric`, `skew_metric`, `ir_metric`, `replichore_metric`
   - Add validity predicates for new metrics
   - Document epsilon/confidence assignment rules

2. **Extend Export Script** (`julia/scripts/export_knowledge.jl`)
   - Export k-mer inversion metrics
   - Export GC skew metrics
   - Export IR enrichment metrics
   - Export replichore metrics

3. **Enhance Validator** (`demetrios/src/verify_knowledge.d`)
   - Join integrity: every `replicon_id` in knowledge must exist in `atlas_replicons`
   - Range checks for all metric values
   - No-miracles rule: epsilon cannot decrease without derivation rule
   - Report top offenders

4. **Julia Fallback Validator** (`julia/scripts/verify_knowledge.jl`)
   - Same checks as Demetrios validator
   - Used when Demetrios compiler unavailable

**Acceptance**:
- `make epistemic MAX=50 SEED=42` passes all gates
- Validator report shows 0 failures
- Knowledge JSONL includes all metric types

---

## Next Steps

1. **Verify PR1** (Scale Storage)
   - Run `make atlas MAX=50 SEED=42`
   - Check Parquet partitions created
   - Test query layer

2. **Implement PR2** (Biology Metrics)
   - Create `KmerInversion.jl`
   - Create `GCSkew.jl`
   - Create `InvertedRepeats.jl`
   - Integrate into pipeline
   - Add tests

3. **Complete PR3** (Epistemic Knowledge)
   - Extend Knowledge export
   - Enhance validator
   - Test full epistemic pipeline

---

## Command Reference

```bash
# Fast gate (50 replicons)
make atlas MAX=50 SEED=42

# Medium gate (200 replicons)
make atlas MAX=200 SEED=42

# Scale run (10k replicons)
make atlas SCALE=10000 SEED=42

# Query examples
make query QUERY="SELECT * FROM atlas_replicons LIMIT 10"
make query-examples

# Epistemic validation
make epistemic MAX=50 SEED=42

# Snapshot for Zenodo
make snapshot MAX=200 SEED=42
```

---

*Last updated: 2025-12-16*

