# Data Dictionary: Darwin Operator Symmetry Atlas

This document defines all fields in the Darwin Operator Symmetry Atlas output files. All data artifacts conform to FAIR principles and are documented for reproducibility.

---

## File: atlas_replicons.csv

Metadata for each bacterial replicon analyzed in the Atlas.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `assembly_accession` | String | GCF_\d+\.\d+ format | NCBI RefSeq assembly accession |
| `replicon_id` | String | {assembly}\_rep{N} format | Internal stable replicon identifier |
| `replicon_accession` | String \| null | NCBI accession or null | RefSeq replicon accession if available |
| `replicon_type` | Enum | {CHROMOSOME, PLASMID, OTHER} | Type of replicon |
| `length_bp` | Int64 | > 0 | Sequence length in base pairs |
| `gc_fraction` | Float64 | 0.0 <= x <= 1.0 | GC content as fraction |
| `taxonomy_id` | Int64 | Valid NCBI taxid | NCBI Taxonomy ID |
| `taxonomy_name` | String | Non-empty | Species/strain name |
| `source_db` | String | "REFSEQ" | Source database |
| `download_date` | Date | ISO 8601 | Date of data acquisition |
| `checksum_sha256` | String | 64 hex characters | SHA-256 hash of source file |

### Example Row

```csv
GCF_000005845.2,GCF_000005845.2_rep1,NC_000913.3,CHROMOSOME,4641652,0.5079,511145,Escherichia coli str. K-12 substr. MG1655,REFSEQ,2026-01-17,a1b2c3...
```

---

## File: atlas_windows_exact.csv

Exact symmetry metrics computed for sliding windows across all replicons.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `replicon_id` | String | FK -> atlas_replicons | Replicon identifier |
| `window_length` | Int64 | {100, 500, 1000, 5000, 10000} | Window size in base pairs |
| `window_start` | Int64 | 0 <= x < replicon_length | 0-indexed start position (circular) |
| `orbit_ratio` | Float64 | 0.25 <= x <= 1.0 | Normalized orbit size: \|Orbit\| / \|D_n\| |
| `is_palindrome_R` | Bool | true/false | True if sequence is R-fixed (palindrome) |
| `is_fixed_RC` | Bool | true/false | True if sequence is RC-fixed |
| `orbit_size` | Int64 | Divides 2n | Size of orbit under D_n |
| `dmin` | Int64 | 0 <= x <= n | Minimum dihedral Hamming distance |
| `dmin_over_L` | Float64 | 0.0 <= x <= 1.0 | Normalized d_min: d_min / window_length |

### Constraints

- `window_start + window_length` may exceed `replicon_length` for circular wraparound
- `orbit_size` must divide `2 * window_length`
- If `is_palindrome_R = true`, then `orbit_ratio <= 0.5`
- If `is_fixed_RC = true`, then `orbit_ratio <= 0.5`

### Example Row

```csv
GCF_000005845.2_rep1,1000,0,1.0,false,false,2000,548,0.548
```

---

## File: approx_symmetry_stats.csv

Aggregate statistics for approximate symmetry metrics.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `replicon_id` | String | FK -> atlas_replicons | Replicon identifier |
| `window_length` | Int64 | {100, 500, 1000, 5000, 10000} | Window size in base pairs |
| `mean_dmin` | Float64 | >= 0 | Mean d_min across windows |
| `std_dmin` | Float64 | >= 0 | Standard deviation of d_min |
| `mean_dmin_over_L` | Float64 | 0.0 <= x <= 1.0 | Mean normalized d_min |
| `std_dmin_over_L` | Float64 | >= 0 | Std dev of normalized d_min |
| `min_dmin` | Int64 | >= 0 | Minimum d_min observed |
| `max_dmin` | Int64 | <= window_length | Maximum d_min observed |
| `n_windows` | Int64 | > 0 | Number of windows analyzed |

### Example Row

```csv
GCF_000005845.2_rep1,1000,512.3,45.2,0.512,0.045,423,598,4641
```

---

## File: dicyclic_lifts.csv

Verification results for dicyclic group double covers.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `dihedral_order` | Int64 | {4, 8, 16, ...} | Order of dihedral group D_n |
| `dicyclic_order` | Int64 | 2 * dihedral_order | Order of dicyclic group Dic_n |
| `verified_double_cover` | Bool | true/false | True if Dic_n -> D_n is verified |
| `lift_group` | String | "Dic_n" notation | Dicyclic group notation |
| `relations_satisfied` | Bool | true/false | True if all group relations hold |
| `kernel_size` | Int64 | 2 | Size of kernel (should be 2) |

### Example Row

```csv
8,16,true,Dic_4,true,2
```

---

## File: null_model_validation.csv

Statistical validation results comparing observed metrics to null model.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `replicon_id` | String | FK -> atlas_replicons | Replicon identifier |
| `length_bp` | Int64 | > 0 | Sequence length |
| `observed_orbit_ratio` | Float64 | 0.25 <= x <= 1.0 | Observed orbit ratio |
| `null_mean` | Float64 | 0.25 <= x <= 1.0 | Mean orbit ratio from shuffles |
| `null_std` | Float64 | >= 0 | Std dev of shuffled orbit ratios |
| `z_score` | Float64 | Any real | (observed - null_mean) / null_std |
| `p_value` | Float64 | 0.0 <= x <= 1.0 | Two-tailed p-value |
| `n_shuffles` | Int64 | > 0 | Number of GC-preserving shuffles |
| `observed_dmin_norm` | Float64 | 0.0 <= x <= 1.0 | Observed normalized d_min |
| `null_dmin_mean` | Float64 | 0.0 <= x <= 1.0 | Mean d_min from shuffles |

### Interpretation

- `p_value < 0.05`: Observed symmetry significantly different from random
- Negative `z_score`: More symmetric than expected by chance
- Positive `z_score`: Less symmetric than expected by chance

### Example Row

```csv
GCF_000005845.2_rep1,4641652,0.85,0.99,0.02,-7.0,1.3e-12,100,0.42,0.51
```

---

## File: manifest.jsonl

NCBI download manifest in JSON Lines format.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `assembly_accession` | String | GCF_\d+\.\d+ | NCBI assembly accession |
| `replicon_id` | String | Unique | Internal replicon ID |
| `replicon_accession` | String \| null | NCBI accession | RefSeq accession if available |
| `replicon_type` | String | Enum | CHROMOSOME, PLASMID, or OTHER |
| `length_bp` | Int64 | > 0 | Sequence length |
| `gc_fraction` | Float64 | [0, 1] | GC content |
| `taxonomy_id` | Int64 | NCBI taxid | Taxonomy identifier |
| `taxonomy_name` | String | Non-empty | Species name |
| `source_db` | String | "REFSEQ" | Data source |
| `download_date` | String | ISO 8601 | Download timestamp |
| `checksum_sha256` | String | 64 hex | File checksum |

### Example Line

```json
{"assembly_accession":"GCF_000005845.2","replicon_id":"GCF_000005845.2_rep1","replicon_accession":"NC_000913.3","replicon_type":"CHROMOSOME","length_bp":4641652,"gc_fraction":0.5079,"taxonomy_id":511145,"taxonomy_name":"Escherichia coli str. K-12 substr. MG1655","source_db":"REFSEQ","download_date":"2026-01-17","checksum_sha256":"abc123..."}
```

---

## File: checksums.sha256

SHA-256 checksums for all downloaded genome files.

| Format | Description |
|--------|-------------|
| `{hash}  {filename}` | Standard sha256sum format |

### Example

```
a1b2c3d4e5f6...  GCF_000005845.2_genomic.fna.gz
```

---

## Missing Value Conventions

| Convention | Meaning |
|------------|---------|
| Empty string | Field not applicable |
| `null` (JSON) | Field not available |
| `NA` (CSV) | Data not available |
| `-1` (numeric) | Computation failed or not applicable |

---

## Units

| Quantity | Unit |
|----------|------|
| Sequence length | Base pairs (bp) |
| GC content | Fraction (0.0-1.0) |
| Window positions | 0-indexed |
| Distances | Base pairs (Hamming distance) |
| Normalized distances | Dimensionless ratio |

---

## Data Types

| Notation | Description | Examples |
|----------|-------------|----------|
| String | UTF-8 text | "GCF_000005845.2" |
| Int64 | 64-bit signed integer | 4641652 |
| Float64 | IEEE 754 double precision | 0.5079 |
| Bool | Boolean | true, false |
| Enum | Categorical | CHROMOSOME, PLASMID |
| Date | ISO 8601 date | 2026-01-17 |

---

## Versioning

This data dictionary corresponds to:
- Atlas version: 1.0.0
- Schema version: 1.0
- Last updated: 2026-01-18
