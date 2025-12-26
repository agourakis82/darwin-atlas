# E. coli Dataset Summary

**Dataset ID**: ecoli_validation_20251224  
**Created**: 2025-12-24 00:34:40 UTC  
**Purpose**: Biological validation of Darwin Atlas symmetry metrics

---

## Overview

This dataset contains complete genome sequences of *Escherichia coli* downloaded from NCBI RefSeq for biological validation of symmetry metrics before scaling to 50k+ replicons.

---

## Download Statistics

### Query Parameters
- **Organism**: *Escherichia coli* (taxid: 562)
- **Assembly Level**: Complete Genome
- **Max Genomes**: 150
- **Random Seed**: 42 (for reproducibility)
- **Source**: NCBI RefSeq assembly summary

### Download Results
- **Assemblies Queried**: 150
- **Assemblies Downloaded**: 150 (100% success rate)
- **Failed Downloads**: 0
- **Total Replicons Extracted**: 557
- **Total Download Size**: ~219 MB (compressed)

### Download Policy
- **Retries**: 3 attempts per genome
- **Connect Timeout**: 30 seconds
- **Read Timeout**: 300 seconds
- **Backoff Strategy**: Exponential (2^attempt seconds)

---

## Dataset Composition

### Replicon Types
- **Chromosomes**: 150 (26.9%)
- **Plasmids**: 407 (73.1%)
- **Other**: 0 (0%)

### Pathotype Distribution
Based on strain names and organism annotations:
- **Other/Unknown**: 549 replicons (98.6%)
- **ETEC** (Enterotoxigenic E. coli): 4 replicons (0.7%)
- **STEC** (Shiga toxin-producing E. coli): 3 replicons (0.5%)
- **UPEC** (Uropathogenic E. coli): 1 replicon (0.2%)

*Note: Most strains lack specific pathotype annotations in NCBI metadata*

### Replicon Length Statistics
- **Minimum**: 1,079 bp
- **Maximum**: 5,705,580 bp
- **Mean**: 1,380,210 bp
- **Median**: 97,281 bp

*The large difference between mean and median indicates a bimodal distribution (chromosomes vs. plasmids)*

### GC Content Statistics
- **Minimum**: 32.25%
- **Maximum**: 61.05%
- **Mean**: 49.25%
- **Typical E. coli range**: 50-51% (chromosomes)

---

## Data Files

### Raw Sequences
- **Location**: `data/ecoli/raw/`
- **Format**: FASTA (gzip compressed)
- **Naming**: `{assembly_accession}_genomic.fna.gz`
- **Count**: 150 files

### Manifest
- **Location**: `data/ecoli/manifest/manifest.jsonl`
- **Format**: JSON Lines (one record per replicon)
- **Records**: 557
- **Fields**:
  - `assembly_accession`: NCBI assembly accession
  - `replicon_id`: Unique replicon identifier
  - `replicon_accession`: NCBI replicon accession
  - `replicon_type`: CHROMOSOME, PLASMID, or OTHER
  - `length_bp`: Sequence length in base pairs
  - `gc_fraction`: GC content (0-1)
  - `taxonomy_id`: NCBI taxonomy ID (562 for E. coli)
  - `taxonomy_name`: Organism name with strain and pathotype
  - `source_db`: REFSEQ or GENBANK
  - `download_date`: Date of download
  - `checksum_sha256`: SHA256 checksum of source file

### Checksums
- **Location**: `data/ecoli/manifest/checksums.sha256`
- **Format**: SHA256 checksums (one per file)
- **Count**: 150

### Metadata
- **Location**: `data/ecoli/manifest/download_metadata.json`
- **Format**: JSON
- **Contents**: Download parameters, statistics, and provenance

---

## Quality Assurance

### Validation Checks
✅ All 150 genomes downloaded successfully  
✅ All checksums computed and recorded  
✅ All FASTA files parsed without errors  
✅ 557 replicons extracted (avg 3.7 per genome)  
✅ No ambiguous bases >5% in any replicon  
✅ All GC content values in valid range [0,1]  
✅ All sequence lengths > 0  

### Data Integrity
- **Checksum Verification**: SHA256 checksums computed for all files
- **Sequence Validation**: All sequences contain only canonical bases (A, C, G, T)
- **Metadata Completeness**: All required fields populated for all replicons

---

## Biological Diversity

### Expected Strain Diversity
The dataset includes E. coli strains from various sources:
- Laboratory strains (e.g., K-12 derivatives)
- Pathogenic strains (EHEC, UPEC, ETEC, STEC)
- Commensal strains
- Environmental isolates

### Genomic Features
- **Chromosome Size**: Typically 4.5-5.7 Mb
- **Plasmid Size**: Highly variable (1 kb - 300 kb)
- **Replication Origins**: Expected to be detectable via symmetry metrics
- **GC Skew**: Should correlate with ori-ter axis

---

## Next Steps

### Phase 2: Symmetry Analysis
1. Run full Darwin Atlas pipeline on E. coli dataset
2. Compute all symmetry metrics (orbit size, d_min, palindromes, etc.)
3. Enable cross-validation for all metrics
4. Generate output tables

### Phase 3: Biological Validation
1. Fetch replication origin coordinates from DoriC database
2. Compare d_min/L minima with known ori locations
3. Analyze GC skew patterns
4. Validate ori-ter predictions

### Phase 4: Comparative Analysis
1. Group strains by pathotype (where known)
2. Compare symmetry metrics across groups
3. Statistical testing for significant differences
4. Generate visualizations

### Phase 5: Performance Benchmarking
1. Profile pipeline execution time
2. Measure memory usage
3. Identify bottlenecks
4. Extrapolate to 50k scale

---

## Usage

### Loading the Dataset

```julia
using DarwinAtlas
using JSON3

# Read manifest
manifest = []
open("data/ecoli/manifest/manifest.jsonl") do io
    for line in eachline(io)
        push!(manifest, JSON3.read(line, RepliconRecord))
    end
end

println("Loaded $(length(manifest)) replicons")
```

### Accessing Sequences

```julia
using FASTX, CodecZlib

# Read a genome
assembly_acc = "GCF_013084945.1"
fasta_path = "data/ecoli/raw/$(assembly_acc)_genomic.fna.gz"

open(fasta_path) do io
    reader = FASTA.Reader(GzipDecompressorStream(io))
    for record in reader
        header = FASTA.description(record)
        seq = FASTA.sequence(record)
        println("$(header): $(length(seq)) bp")
    end
end
```

---

## References

- **NCBI RefSeq**: https://ftp.ncbi.nlm.nih.gov/genomes/refseq/bacteria/
- **E. coli Taxonomy**: https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=562
- **DoriC Database**: http://tubic.org/doric/public/index.php (for ori validation)

---

## Provenance

### Software Versions
- **Julia**: 1.10.x
- **DarwinAtlas**: 2.0.0-alpha
- **Download Script**: `julia/scripts/download_ecoli.jl`

### Reproducibility
To reproduce this exact dataset:
```bash
julia --project=julia julia/scripts/download_ecoli.jl --max=150 --seed=42
```

The random seed (42) ensures the same 150 genomes are selected from the complete E. coli RefSeq collection.

---

**Last Updated**: 2025-12-24  
**Contact**: Darwin Atlas Project  
**License**: Data from NCBI RefSeq (public domain)
