# Data Sources: Darwin Operator Symmetry Atlas

This document provides complete provenance information for all data used in the Darwin Operator Symmetry Atlas, ensuring FAIR compliance and reproducibility.

---

## Primary Data Source: NCBI RefSeq

### Source Database

| Attribute | Value |
|-----------|-------|
| Database | NCBI Reference Sequence Database (RefSeq) |
| URL | https://www.ncbi.nlm.nih.gov/refseq/ |
| API Version | NCBI Datasets API v2 |
| FTP Mirror | https://ftp.ncbi.nlm.nih.gov/genomes/refseq/bacteria/ |

### Assembly Summary

| Attribute | Value |
|-----------|-------|
| Source File | `assembly_summary.txt` |
| URL | https://ftp.ncbi.nlm.nih.gov/genomes/refseq/bacteria/assembly_summary.txt |
| Format | Tab-separated values (TSV) |
| Update Frequency | Daily |

### Query Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Taxon | Bacteria | Focus on prokaryotic genomes |
| Assembly Level | Complete Genome | Ensure full replicon coverage |
| Source | RefSeq | Curated, non-redundant sequences |
| Random Seed | 42 | Reproducible sampling |

---

## Data Acquisition Protocol

### Download Procedure

1. **Query Assembly Summary**
   - Download `assembly_summary.txt` from NCBI RefSeq FTP
   - Filter for `assembly_level == "Complete Genome"`
   - Extract FTP paths for genomic FASTA files

2. **Random Sampling**
   - Use Mersenne Twister PRNG with seed=42
   - Shuffle complete genome list
   - Select first N genomes (N = target count)

3. **Genome Download**
   - Convert FTP URLs to HTTPS for reliability
   - Download `*_genomic.fna.gz` files
   - Retry up to 3 times with exponential backoff
   - Skip already-downloaded files (idempotent)

4. **Checksum Verification**
   - Compute SHA-256 hash of each downloaded file
   - Store in `checksums.sha256` manifest
   - Verify integrity on subsequent runs

### File Naming Convention

| Pattern | Example | Description |
|---------|---------|-------------|
| `{accession}_genomic.fna.gz` | `GCF_000005845.2_genomic.fna.gz` | Compressed FASTA |
| `{accession}_rep{N}` | `GCF_000005845.2_rep1` | Replicon identifier |

---

## Manifest Format

### manifest.jsonl

JSON Lines format with one record per replicon:

```json
{
  "assembly_accession": "GCF_000005845.2",
  "replicon_id": "GCF_000005845.2_rep1",
  "replicon_accession": "NC_000913.3",
  "replicon_type": "CHROMOSOME",
  "length_bp": 4641652,
  "gc_fraction": 0.5079,
  "taxonomy_id": 511145,
  "taxonomy_name": "Escherichia coli str. K-12 substr. MG1655",
  "source_db": "REFSEQ",
  "download_date": "2026-01-18",
  "checksum_sha256": "abc123..."
}
```

### checksums.sha256

Standard sha256sum format:

```
abc123def456...  GCF_000005845.2_genomic.fna.gz
```

---

## Replicon Classification

Replicons are classified based on FASTA header content:

| Type | Detection Rule |
|------|----------------|
| CHROMOSOME | Header contains "chromosome" OR is first sequence |
| PLASMID | Header contains "plasmid" |
| OTHER | All other sequences |

---

## Reproducibility

### Exact Reproduction

To reproduce the exact dataset:

```bash
# Clone repository
git clone https://github.com/agourakis82/darwin-atlas.git
cd darwin-atlas

# Download genomes with same seed
make pipeline MAX=1000 SEED=42

# Verify checksums
sha256sum -c data/manifest/checksums.sha256
```

### Version Tracking

| Component | Version | Purpose |
|-----------|---------|---------|
| NCBI RefSeq | r226 (2026-01) | Source database version |
| Julia | 1.12.x | Analysis runtime |
| BioSequences.jl | 3.x | Sequence handling |
| HTTP.jl | 1.x | Network requests |

---

## Data Quality

### Inclusion Criteria

1. Complete genome assembly (not draft)
2. RefSeq accession (GCF_* prefix)
3. Valid FTP path in assembly summary
4. Successful download and checksum

### Exclusion Criteria

1. Draft or scaffold-level assemblies
2. GenBank-only assemblies (no RefSeq)
3. Assemblies with "na" FTP path
4. Failed downloads after 3 retries

---

## Legal and Attribution

### License

NCBI GenBank/RefSeq data is in the public domain. From NCBI:

> "The GenBank database is in the public domain and is not subject to copyright restrictions."

### Citation

When using this dataset, please cite:

1. **Darwin Atlas**:
   ```
   Gourakis, A. (2026). Darwin Operator Symmetry Atlas: A database of
   operator-defined symmetries in bacterial replicons. Scientific Data.
   DOI: [pending]
   ```

2. **NCBI RefSeq**:
   ```
   O'Leary NA, et al. (2016). Reference sequence (RefSeq) database at NCBI:
   current status, taxonomic expansion, and functional annotation.
   Nucleic Acids Research 44(D1):D733-45. DOI: 10.1093/nar/gkv1189
   ```

---

## Data Access

### Direct Download

| Resource | URL |
|----------|-----|
| Zenodo Archive | https://doi.org/10.5281/zenodo.[pending] |
| GitHub Repository | https://github.com/agourakis82/darwin-atlas |

### Programmatic Access

```julia
using DarwinAtlas

# Download genomes
records = fetch_ncbi(
    output_dir="data",
    max_genomes=1000,
    seed=42
)

# Load manifest
manifest = load_manifest("data/manifest/manifest.jsonl")
```

---

## Change Log

| Date | Change | Genomes |
|------|--------|---------|
| 2026-01-17 | Initial download | 200 |
| 2026-01-18 | Expanded dataset | 1000 |

---

## Contact

For data questions or issues:
- GitHub Issues: https://github.com/agourakis82/darwin-atlas/issues
- Email: [project maintainer email]
