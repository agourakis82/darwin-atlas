# Initial Concept

Darwin Operator Symmetry Atlas (DOSA) - A reproducible, DOI-versioned database of operator-defined symmetries in complete bacterial replicons, targeting publication in Scientific Data (Nature Portfolio).

---

# Product Guide

## Overview

The Darwin Operator Symmetry Atlas (DOSA) is a reproducible, DOI-versioned scientific database that computes and catalogs operator-defined symmetries in complete bacterial replicons. The project implements a hybrid architecture combining Julia (for orchestration and reference implementation) and Demetrios (for high-performance kernels with epistemic computing), targeting publication in Scientific Data (Nature Portfolio).

## Target Users

### Primary Audiences

1. **Computational Biologists**
   - Researchers investigating bacterial genome structure and symmetry patterns
   - Scientists studying evolutionary conservation of genomic symmetries
   - Analysts exploring relationships between genome organization and biological function

2. **Bioinformaticians**
   - Tool developers building genome analysis and comparative genomics platforms
   - Pipeline engineers requiring validated symmetry computation modules
   - Data scientists performing large-scale bacterial genome studies

3. **Scientific Data Curators**
   - Researchers requiring reproducible, DOI-versioned datasets for publication
   - Data stewards ensuring FAIR (Findable, Accessible, Interoperable, Reusable) principles
   - Journal reviewers validating computational reproducibility

## Core Features

### 1. Exact Symmetry Computation

DOSA computes precise symmetry metrics for bacterial genomes:

- **Orbit Size Calculation**: Determines the number of distinct sequences under dihedral group action
- **Palindrome Detection**: Identifies reverse-complement palindromic sequences
- **RC-Fixed Sequences**: Locates sequences invariant under reverse-complement transformation
- **Fixed Point Analysis**: Computes sequences unchanged by specific operators (S, R, K, RC)

### 2. Approximate Symmetry Metrics

The system calculates normalized dihedral distance metrics:

- **d_min/L Computation**: Minimum normalized dihedral distance for sequence windows
- **Sliding Window Analysis**: Configurable window sizes for multi-scale symmetry detection
- **Statistical Aggregation**: Mean, median, and distribution statistics across replicons
- **Refinement Types**: Demetrios implementation with compile-time bounds checking

### 3. Cross-Validation Framework

Ensures computational correctness through dual implementation:

- **Julia Reference Implementation**: Pure Julia code (Layer 0) for reproducibility guarantee
- **Demetrios High-Performance Kernels**: Optimized implementation (Layer 2) showcasing epistemic computing
- **Automated Comparison**: Bit-exact validation between implementations
- **Continuous Integration**: GitHub Actions workflow for regression testing

### 4. Large-Scale Processing

Designed for efficient processing of extensive genomic datasets:

- **NCBI Integration**: Automated download of ~50,000 complete bacterial replicons
- **Incremental Processing**: Resumable pipelines with configurable batch sizes (MAX parameter)
- **Parallel Computation**: Multi-threaded processing for independent replicons
- **Memory Efficiency**: Streaming processing for large sequence files

### 5. Data Quality and Reproducibility

Comprehensive quality assurance and provenance tracking:

- **DOI Versioning**: Zenodo integration for citable dataset releases
- **Automated Validation Suite**: Technical validation ensuring data integrity
- **Provenance Tracking**: Complete manifest files with NCBI accessions, checksums (SHA-256), and processing metadata
- **Deterministic Processing**: Seeded random number generation for reproducible sampling

### 6. Multiple Output Formats

Flexible data access for diverse use cases:

- **CSV Format**: Human-readable tables for spreadsheet analysis and manual inspection
- **Parquet Format**: Columnar storage for efficient querying and analytics
- **JSONL Metadata**: Machine-readable manifests and processing logs
- **SQL Query Interface**: DuckDB integration for ad-hoc analysis and complex queries

### 7. Scientific Publication Ready

Structured for Scientific Data journal requirements:

- **Standardized Schema**: Well-defined data tables with typed columns and foreign keys
- **Comprehensive Documentation**: README, CLAUDE.md, and inline code documentation
- **Reproducible Builds**: Committed Julia Manifest.toml and Makefile orchestration
- **LaTeX Manuscript**: Integrated paper/ directory with manuscript and figures

## Goals and Success Criteria

### Primary Goals

1. **Scientific Publication**: Acceptance in Scientific Data (Nature Portfolio) as a Data Descriptor
2. **Community Adoption**: Cited usage by computational biology and bioinformatics researchers
3. **Computational Reproducibility**: Independent verification of results by reviewers and users
4. **Language Showcase**: Demonstrate Demetrios capabilities for scientific computing

### Success Metrics

- **Dataset Completeness**: Process ≥50,000 complete bacterial replicons from NCBI
- **Computational Accuracy**: 100% agreement between Julia and Demetrios implementations
- **Test Coverage**: ≥80% code coverage across both implementations
- **Performance**: Process full dataset within reasonable time (<24 hours on standard hardware)
- **Reproducibility**: Bit-exact results across different systems and Julia/Demetrios versions

## Technical Constraints

### Language Requirements

- **NO PYTHON**: Project exclusively uses Julia (Layers 0-1) and Demetrios (Layer 2)
- **Julia Version**: Requires Julia 1.10 or higher
- **Demetrios Compiler**: Optional but recommended for high-performance execution

### Data Sources

- **NCBI Assembly Database**: Primary source for complete bacterial replicons
- **RefSeq Quality**: Focus on complete, high-quality reference sequences
- **Licensing**: All data must be publicly accessible and redistributable

### Computational Requirements

- **Memory**: Sufficient RAM for loading multi-megabase sequences
- **Storage**: ~10-50 GB for downloaded sequences and output tables
- **CPU**: Multi-core processor recommended for parallel processing

## Architecture Principles

### Layered Design

```
Layer 3: Artifacts     → CSV/JSONL/Parquet (Zenodo DOI)
Layer 2: Demetrios     → High-performance kernels with epistemic computing
Layer 1: Julia         → Orchestration, NCBI fetch, validation
Layer 0: Julia Pure    → Reference implementation (fallback, cross-validation)
```

### Why This Architecture?

1. **Demetrios Showcase**: Demonstrates units of measure, refinement types, and epistemic computing
2. **Reproducibility Guarantee**: Julia implementation ensures reviewers can verify results without Demetrios
3. **Cross-Validation**: Dual implementation catches bugs and ensures correctness
4. **Performance**: Demetrios kernels provide optimized execution for production runs

## User Workflows

### Researcher Workflow

1. Download DOSA dataset from Zenodo (DOI link)
2. Load CSV/Parquet files into analysis environment (R, Julia, Python, DuckDB)
3. Query symmetry metrics for specific replicons or taxonomic groups
4. Cite dataset DOI in publications

### Developer Workflow

1. Clone darwin-atlas repository
2. Run `make setup` to install dependencies
3. Execute `make test` to verify installation
4. Run `make atlas MAX=50` for small-scale testing
5. Examine output in `data/tables/` directory

### Contributor Workflow

1. Fork repository and create feature branch
2. Implement changes in Julia and/or Demetrios
3. Run `make test` and `make cross-validate` to ensure correctness
4. Submit pull request with passing CI checks

## Future Enhancements

### Potential Extensions

- **Taxonomic Analysis**: Symmetry patterns across bacterial phyla and families
- **Visualization Dashboard**: Interactive web interface for exploring symmetry distributions
- **API Service**: REST API for programmatic access to symmetry computations
- **Extended Operators**: Additional group actions beyond dihedral group D_n
- **Eukaryotic Genomes**: Extend analysis to larger, more complex genomes

### Community Contributions

- **Algorithm Improvements**: Optimized implementations of symmetry metrics
- **Additional Metrics**: New measures of genomic symmetry and structure
- **Documentation**: Tutorials, examples, and use case studies
- **Testing**: Expanded test suites and edge case coverage
