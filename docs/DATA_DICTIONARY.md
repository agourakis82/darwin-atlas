# DSLG Atlas Data Dictionary

This document describes all data tables and files produced by the DSLG Atlas pipeline.

## Table of Contents

1. [Core Tables](#core-tables)
   - [atlas_replicons.csv](#atlas_repliconscsv)
   - [dicyclic_lifts.csv](#dicyclic_liftscsv)
   - [quaternion_results.csv](#quaternion_resultscsv)
2. [Epistemic Knowledge Layer](#epistemic-knowledge-layer)
   - [atlas_knowledge.jsonl](#atlas_knowledgejsonl)
   - [schema_atlas_knowledge.json](#schema_atlas_knowledgejson)
   - [atlas_knowledge_report.md](#atlas_knowledge_reportmd)
3. [Manifest Files](#manifest-files)
   - [manifest.jsonl](#manifestjsonl)
   - [checksums.sha256](#checksumssha256)
   - [pipeline_metadata.json](#pipeline_metadatajson)

---

## Core Tables

### atlas_replicons.csv

**Purpose**: Core metadata for each bacterial replicon analyzed in the Atlas.

**Primary Key**: `replicon_id`

**Foreign Keys**: None (root table)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `assembly_accession` | String | GCF_* format | NCBI RefSeq assembly accession |
| `replicon_id` | String | Unique, not null | Internal stable identifier (`{assembly}_{repN}`) |
| `replicon_type` | Enum | CHROMOSOME, PLASMID, OTHER | Type of replicon |
| `length_bp` | Int64 | > 0 | Sequence length in base pairs |
| `gc_fraction` | Float64 | [0.0, 1.0] | GC content as fraction |
| `taxonomy_id` | Int64 | >= 0 | NCBI taxonomy ID |
| `checksum_sha256` | String | 64 hex chars | SHA256 hash of sequence data |

**Example Row**:
```csv
GCF_043161975.1,GCF_043161975.1_rep1,CHROMOSOME,2552120,0.6524,2754726,636ddb1d...
```

---

### dicyclic_lifts.csv

**Purpose**: Algebraic verification results for dicyclic group Dic_n double covers over dihedral groups D_n.

**Primary Key**: `dihedral_order`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `dihedral_order` | Int64 | {4, 8, 16, ...} | Order of dihedral group D_n |
| `verified_double_cover` | Boolean | true/false | Whether Dic_n → D_n is verified |
| `lift_group` | String | Dic_n notation | Dicyclic group notation |
| `relations_satisfied` | Boolean | true/false | Whether group relations hold |

**Notes**:
- D_4 is the symmetry group of a square (DNA operators: I, R, K, RC)
- Dic_n is the dicyclic group, a double cover of D_n via quaternion representation

**Example Row**:
```csv
4,true,Dic_2,true
```

---

### quaternion_results.csv

**Purpose**: Results of quaternion lift verification for various dicyclic orders.

**Primary Key**: `n` (parameter)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `n` | Int64 | >= 2 | Parameter n in Dic_n |
| `dicyclic_order` | Int64 | = 4n | Order of dicyclic group |
| `dihedral_order` | Int64 | = 2n | Order of corresponding dihedral group |
| `double_cover_verified` | Boolean | true/false | Verification result |
| `group_notation` | String | | Human-readable group relation |

**Example Row**:
```csv
2,8,4,true,Dic_2 → D_2
```

---

## Epistemic Knowledge Layer

The epistemic layer provides structured provenance and validation for all computed values, following Demetrios Knowledge[T] semantics.

### atlas_knowledge.jsonl

**Purpose**: JSONL stream of epistemic Knowledge records with provenance, uncertainty bounds, and validity predicates.

**Format**: JSON Lines (one JSON object per line)

**Schema Reference**: `schema_atlas_knowledge.json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `record_type` | Enum | Yes | One of: `replicon_metric`, `window_metric`, `approx_symmetry`, `dicyclic_lift`, `quaternion_result` |
| `metric_name` | String | Yes | Name of metric (e.g., `gc_fraction`, `length_bp`) |
| `value` | Any | Yes | The metric value (number, string, boolean, or object) |
| `epsilon` | Float64 or null | No | Error bound (>= 0), null if unknown, 0 if exact |
| `confidence` | Float64 or null | No | Epistemic confidence [0,1], null if unknown |
| `validity` | Object | Yes | Contains `holds` (bool) and `predicate` (string) |
| `provenance` | Object | Yes | Contains `atlas_git_sha`, `timestamp_utc`, accessions, parameters |

**Provenance Sub-fields**:

| Field | Type | Description |
|-------|------|-------------|
| `atlas_git_sha` | String | Git commit SHA of pipeline code |
| `atlas_version` | String | Semantic version |
| `timestamp_utc` | ISO8601 | Generation timestamp |
| `assembly_accession` | String | NCBI assembly ID |
| `replicon_id` | String | Replicon identifier |
| `pipeline_seed` | Int | Random seed for reproducibility |
| `pipeline_max` | Int | Maximum genomes parameter |
| `ncbi_filter` | Object | NCBI query filters |

**Example Record**:
```json
{
  "record_type": "replicon_metric",
  "metric_name": "gc_fraction",
  "value": 0.6524,
  "epsilon": null,
  "confidence": null,
  "validity": {"holds": true, "predicate": "0 <= x <= 1"},
  "provenance": {
    "atlas_git_sha": "ce4f76aada...",
    "timestamp_utc": "2025-12-15T22:42:29Z",
    "assembly_accession": "GCF_043161975.1",
    "replicon_id": "GCF_043161975.1_rep1",
    "pipeline_seed": 42,
    "pipeline_max": 50
  }
}
```

---

### schema_atlas_knowledge.json

**Purpose**: JSON Schema (draft-07) defining the structure of Knowledge records.

**Usage**: Validate JSONL records against this schema using any JSON Schema validator.

---

### atlas_knowledge_report.md

**Purpose**: Human-readable validation report summarizing epistemic layer QA.

**Contents**:
- Total record count
- Total checks performed
- Pass/fail counts and rate
- Validation gate descriptions (Schema, Data Integrity, Epistemic Invariants)

---

## Manifest Files

### manifest.jsonl

**Purpose**: Download manifest tracking all fetched genome files.

**Format**: JSON Lines

| Field | Type | Description |
|-------|------|-------------|
| `assembly_accession` | String | NCBI assembly ID |
| `filename` | String | Local filename |
| `url` | String | Download URL |
| `timestamp_utc` | ISO8601 | Download time |
| `checksum_sha256` | String | File checksum |

---

### checksums.sha256

**Purpose**: SHA256 checksums for all downloaded sequence files.

**Format**: Standard sha256sum output (`<hash>  <filename>`)

**Usage**: Verify with `sha256sum -c checksums.sha256`

---

### pipeline_metadata.json

**Purpose**: Pipeline execution metadata for reproducibility.

| Field | Type | Description |
|-------|------|-------------|
| `version` | String | Dataset version |
| `timestamp_utc` | ISO8601 | Snapshot generation time |
| `git_sha` | String | Git commit SHA |
| `parameters.max_genomes` | Int | MAX parameter |
| `parameters.seed` | Int | SEED parameter |
| `julia_version` | String | Julia runtime version |
| `platform` | String | OS and architecture |
| `source` | Object | Data source description |

---

## Units and Ranges

| Metric | Unit | Valid Range |
|--------|------|-------------|
| `length_bp` | base pairs | > 0 |
| `gc_fraction` | fraction | [0.0, 1.0] |
| `orbit_ratio` | fraction | [0.25, 1.0] |
| `d_min_over_L` | fraction | [0.0, 1.0] |
| `epsilon` | same as value | >= 0 |
| `confidence` | fraction | [0.0, 1.0] |

---

## Validation Gates

All data passes through three validation gates:

1. **Gate 1: Schema Compliance** — Structural validity of records
2. **Gate 2: Data Integrity** — Domain constraints (ranges, foreign keys)
3. **Gate 3: Epistemic Invariants** — Demetrios Knowledge[T] rules (e.g., no miracles)

See `atlas_knowledge_report.md` for detailed validation rules.

---

*Last updated: 2025-12-16*
