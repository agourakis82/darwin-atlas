# DSLG Atlas v2 — Implementation Plan

**Project**: Darwin Operator Symmetry Atlas (DeOpSym Atlas)  
**Version**: 2.0.0-alpha  
**Author**: Demetrios Chiuratto Agourakis  
**Date**: 2025-12-16

---

## Executive Summary

Transform the Atlas from a CSV-based 50-200 replicon demo into a scalable, queryable, epistemically-typed genomics database supporting 10k-100k replicons with SOTA biological metrics.

**Architecture**: Julia (orchestration) + Demetrios (kernels + epistemic validation)  
**Storage**: Parquet (primary) + CSV (compatibility views)  
**Query**: DuckDB SQL interface  
**Epistemology**: Demetrios L0 Knowledge records (value + epsilon + validity + provenance)

---

## PR Structure

### ✅ PR1: Scale Storage Architecture (COMPLETE)

**Status**: Already implemented in codebase

**Components**:
- Parquet storage with Hive-style partitioning (`julia/src/Storage.jl`)
- DuckDB query layer (`julia/src/QueryLayer.jl`)
- CSV export views for compatibility
- Snapshot builder (`scripts/make_snapshot.sh`)

**Partition Strategy**:
```
partitions/
  source_db={refseq,genbank}/
    replicon_type={chromosome,plasmid,other}/
      length_bin={0-50kb,50-200kb,200-1000kb,gt1Mb}/
        data.parquet
```

**Verification Needed**:
- [x] Deterministic ingestion manifest (overwrite, not append) (`julia/src/NCBIFetch.jl`)
- [x] Deterministic dataset directory reset per run (`julia/scripts/run_atlas.jl`)
- [ ] Run `make atlas MAX=50 SEED=42` and verify Parquet partitions created
- [ ] Test query layer with example queries (`make query QUERY="SELECT * FROM atlas_replicons LIMIT 10"`)
- [ ] Verify dataset manifest + checksums generated in `dist/atlas_dataset_v2/manifest/`

---

### ⚠️ PR2: Biology Metrics (IMPLEMENTED, NEEDS SCALE HARDENING)

**Goal**: Add three high-signal metric families with baselines and validity constraints.

**Current State (in repo)**:
- Implemented modules: `julia/src/KmerInversion.jl`, `julia/src/GCSkew.jl`, `julia/src/InvertedRepeats.jl`, `julia/src/BiologyMetrics.jl`
- Integrated into pipeline runner: `julia/scripts/run_atlas.jl`

**Fixes Applied (this workspace)**:
- Correct manifest parsing into `RepliconRecord` (avoid key mismatches) (`julia/src/BiologyMetrics.jl`)
- Fix test validity constraint for `K_L(tau)` ordering (`julia/test/test_biology_metrics.jl`)

#### 2.1 k-mer Inversion Symmetry

**Module**: `julia/src/KmerInversion.jl` (new)

**Definition**:
```
X_k = mean_w |N(w) - N(RC(w))| / (N(w) + N(RC(w)) + ε)
```

**Parameters**:
- k: 1..10 (default)
- Window: whole replicon, replichore halves (after ori/ter estimation)

**Output Tables**:
- `kmer_inversion`: `replicon_id`, `k`, `x_k`, `k_l_tau_05`, `k_l_tau_10`, `replichore`
- Partitioned by: `source_db`, `k`

**Validity**: X_k ∈ [0, 1], lower = more symmetric

**Baseline**: None (absolute metric)

#### 2.2 GC Skew / Ori-Ter Estimation

**Module**: `julia/src/GCSkew.jl` (new)

**Method**:
1. Compute GC skew = (G-C)/(G+C) in sliding windows (default: 1000 bp)
2. Cumulative skew curve
3. Ori ≈ argmin(cumulative), Ter ≈ argmax(cumulative)
4. Confidence = amplitude / baseline_noise

**Output Tables**:
- `gc_skew_ori_ter`: `replicon_id`, `ori_position`, `ter_position`, `ori_confidence`, `ter_confidence`, `gc_skew_amplitude`, `window_size`
- `replichore_metrics`: `replicon_id`, `replichore`, `length_bp`, `gc_fraction`, `x_k_6` (k-mer inversion for k=6)
- Partitioned by: `source_db`

**Validity**:
- ori_position, ter_position: [0, length_bp)
- ori_confidence, ter_confidence: [0, 1]
- gc_skew_amplitude: ≥ 0

#### 2.3 Inverted Repeats (IR) Enrichment

**Module**: `julia/src/InvertedRepeats.jl` (new)

**Parameters**:
- stem_length ≥ 8 bp
- loop_length ∈ [3, 20] bp

**Baseline**: Mono-nucleotide Markov shuffle (optionally di-nucleotide)

**Output Tables**:
- `inverted_repeats`: Full IR list (can be large; optional sampling)
- `inverted_repeats_summary`: `replicon_id`, `ir_count`, `ir_density`, `baseline_count`, `enrichment_ratio`, `p_value`, `baseline_method`, `stem_min_length`, `loop_max_length`
- Partitioned by: `source_db`

**Validity**:
- ir_count: ≥ 0
- ir_density: ≥ 0 (IRs per kb)
- enrichment_ratio: ≥ 0
- p_value: [0, 1]

**Integration**:
- Add metric computation to `julia/scripts/run_atlas.jl`
- Write tables to Parquet partitions
- Export CSV views

**Tests**:
- Unit tests on toy sequences
- Validity range checks
- Baseline comparison tests

**Acceptance**:
- `make atlas MAX=200 SEED=42` produces all biology metric tables
- Each metric has documented validity constraints
- Runtime acceptable (< 1h for MAX=200)

---

### ⚠️ PR3: Epistemic Knowledge Everywhere (PARTIAL)

**Goal**: Emit ALL atlas outputs as epistemic Knowledge records with strict validation gates.

#### 3.1 Expanded Knowledge Schema

**New Record Types**:
- `kmer_metric`: k-mer inversion symmetry metrics
- `skew_metric`: GC skew and ori/ter metrics
- `ir_metric`: Inverted repeat enrichment metrics
- `replichore_metric`: Per-replichore metrics

**Schema Fields** (per record):
```json
{
  "record_type": "kmer_metric|skew_metric|ir_metric|...",
  "metric_name": "x_k_6|ori_position|ir_enrichment_ratio|...",
  "value": <number|string|object>,
  "epsilon": <number|null>,
  "confidence": <number|null>,
  "validity": {"holds": true, "predicate": "..."},
  "provenance": {
    "atlas_git_sha": "...",
    "assembly_accession": "...",
    "replicon_id": "...",
    "k": 6,
    "replichore": "leading|lagging|whole",
    "baseline_spec": "markov1|markov2|shuffle",
    "timestamp_utc": "...",
    ...
  }
}
```

#### 3.2 Extend Export Script

**File**: `julia/scripts/export_knowledge.jl`

**Tasks**:
- Add export functions for k-mer metrics
- Add export functions for GC skew metrics
- Add export functions for IR metrics
- Add export functions for replichore metrics
- Add validity predicates for new metrics
- Document epsilon/confidence assignment rules

#### 3.3 Enhance Validator

**File**: `demetrios/src/verify_knowledge.d`

**Validation Gates**:

1. **Schema Compliance**
   - All required fields present
   - Types correct
   - Enum values valid

2. **Data Integrity**
   - Ranges valid (gc_fraction ∈ [0,1], etc.)
   - Foreign keys exist (every `replicon_id` in knowledge must exist in `atlas_replicons`)
   - Join integrity checks

3. **Epistemic Invariants**
   - epsilon ≥ 0
   - confidence ∈ [0,1]
   - No miracles: epsilon cannot decrease across `derived_from` edges unless derivation rule allows

**Output**: Validation report with top offenders

**Julia Fallback**: `julia/scripts/verify_knowledge.jl` (same checks, used when Demetrios unavailable)

**Acceptance**:
- `make epistemic MAX=50 SEED=42` passes all gates
- Validator report shows 0 failures
- Knowledge JSONL includes all metric types

---

## Implementation Timeline

### Phase 1: Verify PR1 (Scale Storage) — 1 day
- [ ] Run fast gate: `make atlas MAX=50 SEED=42`
- [ ] Verify Parquet partitions created correctly
- [ ] Test query layer with example queries
- [ ] Document any issues found

### Phase 2: Implement PR2 (Biology Metrics) — 5-7 days
- [ ] Day 1-2: Implement `KmerInversion.jl` + tests
- [ ] Day 3-4: Implement `GCSkew.jl` + `replichore_metrics` + tests
- [ ] Day 5-6: Implement `InvertedRepeats.jl` + baseline + tests
- [ ] Day 7: Integration into pipeline + end-to-end test

### Phase 3: Complete PR3 (Epistemic Knowledge) — 3-4 days
- [ ] Day 1: Expand Knowledge schema + export functions
- [ ] Day 2: Enhance Demetrios validator (join integrity + no-miracles)
- [ ] Day 3: Julia fallback validator
- [ ] Day 4: End-to-end epistemic pipeline test

---

## Command Reference

```bash
# Fast gate (50 replicons, ~5-10 min)
make atlas MAX=50 SEED=42

# Medium gate (200 replicons, ~30-60 min)
make atlas MAX=200 SEED=42

# Scale run (10k replicons, ~4-8 hours)
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

## Acceptance Criteria

### PR1 (Scale Storage)
- ✅ Parquet storage implemented
- ✅ DuckDB query layer functional
- ⚠️ Needs verification run

### PR2 (Biology Metrics)
- ❌ k-mer inversion symmetry: Not implemented
- ❌ GC skew / ori-ter: Not implemented
- ❌ Inverted repeats: Not implemented
- ❌ Integration into pipeline: Not done

### PR3 (Epistemic Knowledge)
- ⚠️ Knowledge export exists but needs expansion
- ⚠️ Validator exists but needs enhancement
- ❌ Join integrity checks: Not implemented
- ❌ No-miracles rule: Not implemented

---

## Next Steps

1. **Immediate**: Verify PR1 (run fast gate, test query layer)
2. **Week 1**: Implement PR2 (biology metrics)
3. **Week 2**: Complete PR3 (epistemic knowledge expansion)

---

*Last updated: 2025-12-16*
