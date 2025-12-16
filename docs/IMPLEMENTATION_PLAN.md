# DSLG Atlas v2 Implementation Plan

## Overview

Transform the Atlas from a CSV-based 50-200 replicon demo into a scalable, queryable, epistemically-typed genomics database supporting 10k-100k replicons.

## PR Structure

### PR1: Scale Storage Architecture
- Parquet primary storage with partitions
- CSV export views for compatibility
- DuckDB query layer
- Deterministic snapshot v2 builder

### PR2: Biology Metrics (SOTA Signal)
- k-mer inversion symmetry (Generalized Chargaff)
- GC skew / ori-ter estimation with confidence
- Inverted repeats enrichment analysis

### PR3: Epistemic Knowledge Everywhere
- Expanded Knowledge schema for all metrics
- Comprehensive validation gates
- Join integrity verification
- No-miracles rule enforcement

## Directory Structure (Target)

```
darwin-atlas/
├── julia/
│   ├── src/
│   │   ├── DarwinAtlas.jl          # Main module
│   │   ├── Types.jl                 # Core types
│   │   ├── NCBIFetch.jl            # NCBI ingestion
│   │   │
│   │   ├── # Core metrics (existing)
│   │   ├── Operators.jl
│   │   ├── ExactSymmetry.jl
│   │   ├── ApproxMetric.jl
│   │   │
│   │   ├── # Scale storage (PR1)
│   │   ├── Storage.jl              # Parquet read/write
│   │   ├── Partitions.jl           # Partition strategy
│   │   ├── QueryLayer.jl           # DuckDB interface
│   │   │
│   │   ├── # Biology metrics (PR2)
│   │   ├── KmerInversion.jl        # k-mer symmetry
│   │   ├── GCSkew.jl               # Ori/ter estimation
│   │   ├── InvertedRepeats.jl      # IR detection
│   │   │
│   │   ├── # Epistemic (PR3)
│   │   ├── Knowledge.jl            # Knowledge record creation
│   │   └── KnowledgeValidation.jl  # Validation gates
│   │
│   └── scripts/
│       ├── run_pipeline.jl         # Main pipeline
│       ├── run_atlas.jl            # Unified atlas runner (PR1)
│       ├── query_atlas.jl          # DuckDB queries (PR1)
│       └── export_knowledge.jl     # Knowledge export (PR3)
│
├── dist/                            # Generated snapshots (gitignored)
│   └── atlas_dataset_v2/
│       ├── partitions/              # Parquet files
│       │   ├── source_db=refseq/
│       │   │   ├── replicon_type=chromosome/
│       │   │   └── replicon_type=plasmid/
│       │   └── source_db=genbank/
│       ├── csv/                     # CSV export views
│       ├── epistemic/               # Knowledge JSONL
│       └── manifest/                # Checksums + metadata
│
└── docs/
    ├── DATA_DICTIONARY.md
    ├── PARQUET_SCHEMA.md           # PR1
    └── QUERY_EXAMPLES.md           # PR1
```

## Milestone 1: Scale Storage (PR1)

### 1.1 Dependencies
Add to `julia/Project.toml`:
- Arrow.jl (Parquet read/write)
- DuckDB.jl (query layer)

### 1.2 Partition Strategy
```
partitions/
  source_db={refseq,genbank}/
    replicon_type={chromosome,plasmid,other}/
      length_bin={0-50kb,50-200kb,200-1000kb,gt1Mb}/
        data_XXXXXXXX.parquet
```

Benefits:
- Efficient filtering by common query patterns
- Parallel processing per partition
- Incremental updates possible

### 1.3 Tables (Parquet + CSV views)

| Table | Partition Keys | Estimated Rows (100k scale) |
|-------|---------------|----------------------------|
| atlas_replicons | source_db, replicon_type, length_bin | ~100k |
| kmer_inversion | source_db, k | ~1M (100k × 10 k-values) |
| gc_skew_ori_ter | source_db | ~100k |
| replichore_metrics | source_db | ~200k |
| inverted_repeats_summary | source_db | ~100k |

### 1.4 Query Layer
DuckDB provides:
- SQL interface over Parquet
- Fast aggregations
- Join validation queries

Example queries in `scripts/query_atlas.jl`:
```sql
-- Replicons with extreme GC skew
SELECT replicon_id, gc_skew_amplitude, ori_confidence
FROM read_parquet('dist/atlas_dataset_v2/partitions/**/*.parquet')
WHERE gc_skew_amplitude > 0.1

-- k-mer inversion outliers by taxa
SELECT taxonomy_id, AVG(x_k) as mean_inversion
FROM kmer_inversion
WHERE k = 6
GROUP BY taxonomy_id
HAVING mean_inversion > 0.1
```

### 1.5 Make Targets
```makefile
# Unified atlas command
atlas: setup
    julia --project=julia julia/scripts/run_atlas.jl \
        --max $(MAX) --seed $(SEED) --scale $(SCALE)

# Query helper
query:
    julia --project=julia julia/scripts/query_atlas.jl $(QUERY)
```

## Milestone 2: Biology Metrics (PR2)

### 2.1 k-mer Inversion Symmetry

**Definition**: For k-mer w, compute:
```
X_k = mean_w |N(w) - N(RC(w))| / (N(w) + N(RC(w)) + ε)
```

**Parameters**:
- k: 1..10 (default)
- Window: whole replicon, replichore halves

**Validity**: X_k ∈ [0, 1], lower = more symmetric

### 2.2 GC Skew / Ori-Ter Estimation

**Method**:
1. Compute GC skew = (G-C)/(G+C) in sliding windows
2. Cumulative skew curve
3. Ori ≈ argmin(cumulative), Ter ≈ argmax(cumulative)
4. Confidence = amplitude / baseline_noise

**Outputs**:
- ori_position, ter_position (bp)
- ori_confidence, ter_confidence [0,1]
- gc_skew_amplitude

### 2.3 Inverted Repeats (IR)

**Parameters**:
- stem_length ≥ 8
- loop_length ∈ [3, 20]

**Baseline**: Mono/di-nucleotide Markov shuffle

**Outputs**:
- ir_count, ir_density
- enrichment_ratio vs baseline
- p_value

## Milestone 3: Epistemic Knowledge (PR3)

### 3.1 Expanded Schema

```json
{
  "record_type": "replicon_metric|kmer_metric|skew_metric|ir_metric|...",
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
    ...
  }
}
```

### 3.2 Validation Gates

**Gate 1: Schema Compliance**
- All required fields present
- Types correct

**Gate 2: Data Integrity**
- Ranges valid (gc_fraction ∈ [0,1], etc.)
- Foreign keys exist (replicon_id in atlas_replicons)

**Gate 3: Epistemic Invariants**
- epsilon ≥ 0
- confidence ∈ [0,1]
- No miracles: epsilon cannot decrease without derivation rule

## Command Reference

```bash
# Fast gate (50 replicons)
make atlas MAX=50 SEED=42

# Medium gate (200 replicons)
make atlas MAX=200 SEED=42

# Scale run (10k replicons)
make atlas SCALE=10000 SEED=42

# Query
make query QUERY="SELECT * FROM atlas_replicons LIMIT 10"

# Epistemic validation
make epistemic MAX=50 SEED=42

# Snapshot for Zenodo
make snapshot MAX=200 SEED=42
```

## Timeline

- PR1: Scale storage → establishes foundation
- PR2: Biology metrics → adds scientific value
- PR3: Knowledge everywhere → ensures rigor

---

*Author: Demetrios Chiuratto Agourakis*
*Date: 2025-12-16*
