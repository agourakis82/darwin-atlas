# DSLG Atlas Parquet Schema

This document describes the Parquet storage schema for Atlas v2.

## Overview

Atlas v2 uses Apache Parquet for primary storage with:
- Hive-style partitioning for efficient filtering
- CSV views for compatibility
- DuckDB query layer for SQL access

## Partition Strategy

```
dist/atlas_dataset_v2/
├── partitions/
│   └── atlas_replicons/
│       └── source_db={refseq,genbank}/
│           └── replicon_type={CHROMOSOME,PLASMID,OTHER}/
│               └── length_bin={0-50kb,50-200kb,200-1000kb,gt1Mb}/
│                   └── data.parquet
├── csv/
│   └── *.csv (flat views)
└── manifest/
    ├── dataset_manifest.json
    └── checksums.sha256
```

## Table Schemas

### labels_oriter (DoriC, Tier A)

Authoritative ori/ter labels derived from DoriC (required for SOTA++ evaluation).

**Location**:
- `metadata/labels_oriter.parquet` (authoritative source)
- `dist/atlas_dataset_v2/partitions/labels_oriter/data.parquet` (dataset export)

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `replicon_id` | String | FK → atlas_replicons |
| `replicon_accession` | String | NCBI accession (RefSeq) |
| `assembly_accession` | String | NCBI assembly ID (GCF_...) |
| `length_bp` | Int64 | Replicon length |
| `doric_accession` | String | DoriC entry ID |
| `doric_source` | String | {bacteria, archaea, plasmid} |
| `ori_start_bp` | Int64 | Origin start (1-based) |
| `ori_end_bp` | Int64 | Origin end (1-based) |
| `ori_center_bp` | Int64 | Circular midpoint of origin |
| `ori_span_bp` | Int64 | Length of origin interval |
| `ori_wrapped` | Bool | Interval wraps around end |
| `ori_at_content` | Float64 | AT content of oriC |
| `ter_bp` | Int64 | Derived terminus position |
| `ter_derived` | Bool | Always true (derived from ori) |
| `label_tier` | String | Always "A" |
| `label_source` | String | "DoriC" |
| `label_version` | String | DoriC version label |
| `label_confidence` | Float64 | Confidence score |
| `match_method` | String | {exact, nover} |
| `ori_rank` | Int64 | Index for multiple origins |

### oriter_eval (DoriC evaluation)

GC-skew ori/ter predictions evaluated against DoriC labels.

**Location**:
- `metadata/oriter_eval.csv`
- `metadata/oriter_eval_summary.json`

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `replicon_id` | String | FK → atlas_replicons |
| `assembly_accession` | String | NCBI assembly ID |
| `length_bp` | Int64 | Replicon length |
| `ori_label` | Int64 | DoriC ori center |
| `ter_label` | Int64 | DoriC-derived ter |
| `ori_pred` | Int64 | GC-skew ori prediction |
| `ter_pred` | Int64 | GC-skew ter prediction |
| `ori_error` | Int64 | Circular distance (bp) |
| `ter_error` | Int64 | Circular distance (bp) |
| `window_size` | Int64 | GC-skew window size |
| `step` | Int64 | GC-skew step |

### symmetry_spectrum (DoriC subset)

Symmetry spectrum summaries with null-model p/q-values.

**Location**:
- `metadata/symmetry_spectrum.csv`
- `metadata/symmetry_spectrum_summary.json`

**Data Columns** (subset):
| Column | Type | Description |
|--------|------|-------------|
| `shift_min` | Int64 | Minimum shift distance |
| `rev_min` | Int64 | Minimum reverse distance |
| `shift_min_p` | Float64 | Null p-value (shift) |
| `rev_min_p` | Float64 | Null p-value (reverse) |
| `shift_min_q` | Float64 | FDR q-value (shift) |
| `rev_min_q` | Float64 | FDR q-value (reverse) |

### atlas_replicons

Primary table for replicon metadata.

**Partition Columns**:
- `source_db`: {REFSEQ, GENBANK}
- `replicon_type`: {CHROMOSOME, PLASMID, OTHER}
- `length_bin`: {0-50kb, 50-200kb, 200-1000kb, gt1Mb}

**Data Columns**:
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `assembly_accession` | String | No | NCBI assembly ID (GCF_...) |
| `replicon_id` | String | No | Internal stable ID |
| `replicon_accession` | String | Yes | NCBI sequence accession |
| `length_bp` | Int64 | No | Sequence length |
| `gc_fraction` | Float64 | No | GC content [0,1] |
| `taxonomy_id` | Int64 | No | NCBI taxonomy ID |
| `organism_name` | String | No | Organism name |
| `download_date` | Date | No | Download timestamp |
| `checksum_sha256` | String | No | Sequence checksum |

### kmer_inversion (PR2)

k-mer inversion symmetry metrics.

**Partition Columns**:
- `source_db`: {REFSEQ, GENBANK}
- `k`: {1, 2, 3, ..., 10}

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `replicon_id` | String | FK → atlas_replicons |
| `x_k` | Float64 | Inversion score [0,1] |
| `k_l_tau_05` | Int64 | K_L at tau=0.05 |
| `k_l_tau_10` | Int64 | K_L at tau=0.10 |
| `replichore` | String | {whole, leading, lagging} |

### gc_skew_ori_ter (PR2)

GC skew and origin/terminus estimation.

**Partition Columns**:
- `source_db`: {REFSEQ, GENBANK}

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `replicon_id` | String | FK → atlas_replicons |
| `ori_position` | Int64 | Estimated origin (bp) |
| `ter_position` | Int64 | Estimated terminus (bp) |
| `ori_confidence` | Float64 | Confidence [0,1] |
| `ter_confidence` | Float64 | Confidence [0,1] |
| `gc_skew_amplitude` | Float64 | Peak-to-trough amplitude |
| `window_size` | Int64 | Window used for skew |

### replichore_metrics (PR2)

Per-replichore symmetry metrics.

**Partition Columns**:
- `source_db`: {REFSEQ, GENBANK}

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `replicon_id` | String | FK → atlas_replicons |
| `replichore` | String | {leading, lagging} |
| `length_bp` | Int64 | Replichore length |
| `gc_fraction` | Float64 | GC content |
| `x_k_6` | Float64 | k-mer inversion (k=6) |

### inverted_repeats_summary (PR2)

Inverted repeat enrichment analysis.

**Partition Columns**:
- `source_db`: {REFSEQ, GENBANK}

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `replicon_id` | String | FK → atlas_replicons |
| `ir_count` | Int64 | Number of IRs detected |
| `ir_density` | Float64 | IRs per kb |
| `baseline_count` | Float64 | Expected count (baseline) |
| `enrichment_ratio` | Float64 | Observed/expected |
| `p_value` | Float64 | Statistical significance |
| `baseline_method` | String | {markov1, markov2} |
| `stem_min_length` | Int64 | Minimum stem length |
| `loop_max_length` | Int64 | Maximum loop length |

### dicyclic_lifts

Algebraic verification results (not partitioned, small table).

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `dihedral_order` | Int64 | D_n order |
| `lift_group` | String | Dic_n notation |
| `verified_double_cover` | Bool | Verification result |
| `relations_satisfied` | Bool | Group relations hold |

### quaternion_results

Quaternion lift verification (not partitioned, small table).

**Data Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `n` | Int64 | Parameter in Dic_n |
| `dicyclic_order` | Int64 | |Dic_n| |
| `dihedral_order` | Int64 | |D_n| |
| `double_cover_verified` | Bool | Verification result |
| `group_notation` | String | Human-readable |

## Length Bin Definitions

| Bin | Range |
|-----|-------|
| `0-50kb` | 0 ≤ length < 50,000 |
| `50-200kb` | 50,000 ≤ length < 200,000 |
| `200-1000kb` | 200,000 ≤ length < 1,000,000 |
| `gt1Mb` | length ≥ 1,000,000 |

## Query Examples

```sql
-- Count replicons by type and source
SELECT source_db, replicon_type, COUNT(*) as count
FROM read_parquet('dist/atlas_dataset_v2/partitions/atlas_replicons/**/*.parquet',
                  hive_partitioning=true)
GROUP BY source_db, replicon_type;

-- Filter chromosomes > 1Mb
SELECT *
FROM read_parquet('dist/atlas_dataset_v2/partitions/atlas_replicons/**/*.parquet',
                  hive_partitioning=true)
WHERE replicon_type = 'CHROMOSOME' AND length_bin = 'gt1Mb';

-- k-mer inversion at k=6
SELECT replicon_id, x_k, replichore
FROM read_parquet('dist/atlas_dataset_v2/partitions/kmer_inversion/k=6/**/*.parquet',
                  hive_partitioning=true)
WHERE x_k > 0.1;
```

## Versioning

Schema version is tracked in `manifest/dataset_manifest.json`:

```json
{
  "version": "2.0.0",
  "schema_version": "2.0",
  "timestamp_utc": "2025-12-16T...",
  "git_sha": "..."
}
```

---

*Last updated: 2025-12-16*
