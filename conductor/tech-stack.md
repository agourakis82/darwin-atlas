# Technology Stack

## Architecture Overview

DOSA implements a **hybrid architecture** that combines Demetrios and Julia to balance scientific innovation with practical reproducibility:

```
Layer 3: Artifacts     → CSV/JSONL/Parquet (Zenodo DOI)
Layer 2: Demetrios     → High-performance kernels with epistemic computing
Layer 1: Julia         → Orchestration, NCBI fetch, validation
Layer 0: Julia Pure    → Reference implementation (fallback, cross-validation)
```

### Architecture Rationale

1. **Demetrios (Layer 2)**: Core scientific algorithms showcasing refinement types, units of measure, and epistemic computing
2. **Julia (Layers 0-1)**: I/O operations, NCBI integration, orchestration, and reproducibility guarantee for reviewers
3. **Cross-Validation**: Dual implementation ensures computational correctness

---

## Primary Languages

### Demetrios (Layer 2)

**Version**: Latest stable from https://github.com/Chiuratto-AI/demetrios  
**Role**: Core scientific computation layer

**Usage**:
- Operator definitions (S, R, K, RC) with units of measure
- Exact symmetry metrics (orbit size, palindrome detection, fixed points)
- Approximate symmetry metrics (d_min/L with refinement types)
- Quaternion-based dicyclic group verification
- FFI exports for Julia integration

**Key Features Utilized**:
- **Refinement Types**: Encode constraints (e.g., 0 ≤ d_min/L ≤ 1) at compile time
- **Units of Measure**: Type-safe handling of base pairs, nucleotides, distances
- **Epistemic Computing**: Explicit representation of computational assumptions
- **Performance**: Compiled to native code for high-performance execution

**Build System**: Demetrios compiler (`dc`) with `demetrios.toml` configuration

### Julia (Layers 0-1)

**Version**: 1.10 or higher  
**Role**: Orchestration, I/O, validation, and reference implementation

**Usage**:
- NCBI Assembly database fetching via HTTP API
- Sequence parsing (FASTA format)
- Data processing and tabular output (CSV, Parquet)
- SQL query interface (DuckDB)
- Cross-validation between Julia and Demetrios implementations
- Testing and continuous integration
- Pipeline orchestration

**Key Features Utilized**:
- **Rich Ecosystem**: Mature bioinformatics and data science libraries
- **Interactive Development**: REPL for rapid prototyping and debugging
- **Package Management**: Reproducible environments via Project.toml/Manifest.toml
- **FFI Integration**: Seamless C ABI calls to Demetrios shared libraries

---

## Julia Dependencies

### Core Scientific Computing

| Package | Version | Purpose |
|---------|---------|---------|
| **BioSequences** | Latest | DNA sequence manipulation, complement operations |
| **Rotations** | Latest | Quaternion mathematics for Dic_n verification |
| **Statistics** | Stdlib | Statistical aggregation of symmetry metrics |
| **StatsBase** | Latest | Advanced statistical functions |
| **Random** | Stdlib | Seeded random sampling for reproducibility |

### Data Processing

| Package | Version | Purpose |
|---------|---------|---------|
| **DataFrames** | Latest | Tabular data manipulation and aggregation |
| **CSV** | Latest | Human-readable table output |
| **Arrow** | Latest | Efficient columnar data format |
| **Parquet2** | Latest | Parquet format for analytics |
| **DuckDB** | Latest | SQL query interface for datasets |
| **JSON3** | Latest | Metadata and manifest handling |

### I/O and Networking

| Package | Version | Purpose |
|---------|---------|---------|
| **FASTX** | Latest | FASTA/FASTQ sequence file parsing |
| **HTTP** | Latest | NCBI API requests and downloads |
| **CodecZlib** | Latest | Gzip compression for downloaded sequences |
| **SHA** | Stdlib | SHA-256 checksums for provenance |

### Development and Testing

| Package | Version | Purpose |
|---------|---------|---------|
| **Test** | Stdlib | Unit testing framework |
| **BenchmarkTools** | Latest | Performance benchmarking |
| **ProgressMeter** | Latest | Progress bars for long-running pipelines |
| **ArgParse** | Latest | Command-line argument parsing |

### Demetrios Integration

| Package | Version | Purpose |
|---------|---------|---------|
| **Custom FFI Module** | N/A | `ccall` wrappers for Demetrios shared library |

---

## Build System and Tooling

### GNU Make

**Version**: 3.81 or higher  
**Role**: Build orchestration and task automation

**Key Targets**:
- `make setup`: Install Julia and Demetrios dependencies
- `make test`: Run all tests (Julia + Demetrios)
- `make atlas`: Run unified Atlas pipeline
- `make cross-validate`: Verify Julia vs. Demetrios agreement
- `make snapshot`: Build Zenodo dataset snapshot
- `make clean`: Remove build artifacts

**Configuration**:
- `JULIA`: Julia executable path (default: `julia --project=julia`)
- `DEMETRIOS`: Demetrios compiler path (default: `dc`)
- `MAX`: Maximum genomes to process (default: 200)
- `SEED`: Random seed for reproducibility (default: 42)

### Git

**Version**: 2.0 or higher  
**Role**: Version control and collaboration

**Key Practices**:
- Semantic versioning for releases (tags: `v2.0.0`, `v2.1.0`)
- Atomic commits with descriptive messages
- Committed `julia/Manifest.toml` for reproducibility
- GitHub Actions for CI/CD

---

## Data Formats

### CSV (Comma-Separated Values)

**Purpose**: Human-readable tabular data  
**Usage**: Primary output format for atlas tables  
**Tools**: Excel, R, Python pandas, Julia DataFrames

**Files**:
- `atlas_replicons.csv`: Replicon metadata
- `atlas_windows_exact.csv`: Exact symmetry metrics per window
- `approx_symmetry_stats.csv`: Approximate symmetry statistics

### Parquet (Apache Parquet)

**Purpose**: Efficient columnar storage for analytics  
**Usage**: High-performance querying and large-scale analysis  
**Tools**: DuckDB, Apache Spark, Python pandas, Julia DataFrames

**Files**:
- `atlas_replicons.parquet`: Replicon metadata (columnar)
- `atlas_windows_exact.parquet`: Exact symmetry metrics (columnar)
- `approx_symmetry_stats.parquet`: Approximate symmetry (columnar)

### JSONL (JSON Lines)

**Purpose**: Machine-readable metadata and manifests  
**Usage**: Provenance tracking, processing logs  
**Tools**: `jq`, Python, Julia JSON3

**Files**:
- `manifest.jsonl`: NCBI accessions, checksums, download metadata
- `run_metadata.jsonl`: Pipeline parameters, timestamps, versions

### FASTA

**Purpose**: Biological sequence format  
**Usage**: Input sequences from NCBI  
**Tools**: BioSequences.jl, BioPython, BLAST

**Files**:
- `data/raw/*.fna.gz`: Downloaded genomic sequences (gitignored)

---

## External Services and APIs

### NCBI Assembly Database

**URL**: https://www.ncbi.nlm.nih.gov/assembly/  
**Purpose**: Source of complete bacterial replicon sequences  
**API**: NCBI E-utilities and FTP access  
**Authentication**: None required (public data)

**Usage**:
- Query for complete bacterial genomes
- Download FASTA sequences via FTP
- Retrieve assembly metadata (accessions, taxonomy, quality)

**Rate Limiting**: Respect NCBI guidelines (max 3 requests/second without API key)

### Zenodo

**URL**: https://zenodo.org/  
**Purpose**: DOI assignment and dataset archival  
**API**: Zenodo REST API for uploads  
**Authentication**: API token (stored securely, not committed)

**Usage**:
- Upload dataset snapshots (CSV, Parquet, metadata)
- Assign DOI for each release
- Version management for dataset updates

**Metadata**: `.zenodo.json` file with title, authors, description, license

### GitHub Actions

**URL**: https://github.com/features/actions  
**Purpose**: Continuous integration and testing  
**Configuration**: `.github/workflows/ci.yml`

**Workflows**:
- **CI**: Run tests on push/PR (Julia + Demetrios)
- **Cross-Validation**: Verify Julia vs. Demetrios agreement
- **Build**: Test pipeline on small dataset (MAX=50)

**Runners**: Ubuntu latest (Linux)

---

## Development Environment

### Required Software

| Software | Minimum Version | Purpose |
|----------|----------------|---------|
| **Julia** | 1.10 | Primary language (Layers 0-1) |
| **Demetrios Compiler** | Latest | Core algorithms (Layer 2) |
| **GNU Make** | 3.81 | Build orchestration |
| **Git** | 2.0 | Version control |
| **GCC/Clang** | Modern | C compiler for Demetrios FFI |

### Optional Software

| Software | Purpose |
|----------|---------|
| **DuckDB CLI** | Interactive SQL queries on datasets |
| **jq** | JSON/JSONL manipulation |
| **curl/wget** | Manual NCBI downloads |

### System Requirements

**Minimum**:
- **OS**: Linux, macOS, or WSL2 (Windows)
- **RAM**: 8 GB (for small datasets, MAX=200)
- **Storage**: 20 GB (downloaded sequences + outputs)
- **CPU**: 2 cores

**Recommended**:
- **RAM**: 16+ GB (for large datasets, MAX=10000+)
- **Storage**: 100+ GB (full NCBI dataset)
- **CPU**: 8+ cores (parallel processing)

---

## Dependency Management

### Julia Dependencies

**Reproducibility**: Committed `julia/Manifest.toml` ensures exact versions

**Installation**:
```bash
cd darwin-atlas
julia --project=julia -e 'using Pkg; Pkg.instantiate()'
```

**Updates** (use cautiously):
```bash
julia --project=julia -e 'using Pkg; Pkg.update()'
# Commit updated Manifest.toml only after thorough testing
```

### Demetrios Dependencies

**Installation**: Follow https://github.com/Chiuratto-AI/demetrios

**Version Tracking**: Document Demetrios compiler version in:
- `.zenodo.json` metadata
- `README.md` installation instructions
- CI workflow configuration

**Build**:
```bash
cd demetrios
dc build --release --target=cdylib
```

---

## Cross-Language Integration

### Demetrios → Julia FFI

**Mechanism**: C ABI via shared library (`.so`, `.dylib`, `.dll`)

**Workflow**:
1. Demetrios exports functions with `extern "C"` ABI
2. Demetrios compiler builds shared library (`libdemetrios_atlas.so`)
3. Julia uses `ccall` to invoke Demetrios functions
4. Data marshaling: Convert Julia types ↔ C types ↔ Demetrios types

**Example**:
```julia
# Julia side (DemetriosFFI.jl)
function compute_orbit_size(sequence::LongDNA)
    seq_ptr = pointer(sequence)
    seq_len = length(sequence)
    result = ccall(
        (:demetrios_compute_orbit_size, libdemetrios_atlas),
        Int64,
        (Ptr{UInt8}, Int64),
        seq_ptr, seq_len
    )
    return result
end
```

```demetrios
// Demetrios side (ffi.d)
extern "C" fn demetrios_compute_orbit_size(seq_ptr: *const u8, seq_len: i64) -> i64 {
    let sequence = unsafe { std::slice::from_raw_parts(seq_ptr, seq_len as usize) };
    compute_orbit_size_internal(sequence)
}
```

---

## Testing Strategy

### Unit Tests

**Julia**: `julia/test/runtests.jl` using `Test` stdlib  
**Demetrios**: `demetrios/tests/` using Demetrios test framework

**Coverage Target**: ≥80% code coverage

### Integration Tests

**Cross-Validation**: `julia/scripts/cross_validation.jl`
- Compare Julia vs. Demetrios results
- Assert bit-exact agreement (or within floating-point tolerance)

### Validation Tests

**Technical Validation**: `julia/src/Validation.jl`
- Verify data integrity (checksums, schema)
- Check metric ranges (e.g., 0 ≤ d_min/L ≤ 1)
- Validate provenance (NCBI accessions exist)

### CI/CD

**GitHub Actions**: `.github/workflows/ci.yml`
- Run on every push and pull request
- Test on Ubuntu (Linux)
- Small dataset test (MAX=50, SEED=42)

---

## Performance Considerations

### Demetrios Optimizations

- **Compile Flags**: `--release` for production builds
- **Target**: `cdylib` for shared library
- **Refinement Types**: Compile-time bounds checking (zero runtime cost)

### Julia Optimizations

- **Type Stability**: Ensure functions are type-stable for performance
- **Precompilation**: Use `Pkg.precompile()` to reduce startup time
- **Parallelism**: Multi-threading for independent replicons (`Threads.@threads`)
- **Memory**: Streaming processing for large files (avoid loading entire dataset)

### Profiling

**Julia**: `@profile`, `@benchmark` from BenchmarkTools  
**Demetrios**: Built-in profiling tools (if available)

---

## Licensing

### Code

**License**: MIT License  
**Rationale**: Permissive, allows commercial use, widely adopted

**Files**:
- All Julia source code (`julia/src/`, `julia/test/`, `julia/scripts/`)
- All Demetrios source code (`demetrios/src/`, `demetrios/tests/`)
- Build scripts (`Makefile`, `.github/workflows/`)

### Data

**License**: CC-BY 4.0 (Creative Commons Attribution)  
**Rationale**: Requires attribution, allows redistribution and derivatives

**Files**:
- All output datasets (`data/tables/*.csv`, `*.parquet`)
- Metadata and manifests (`data/manifest/*.jsonl`)

### Documentation

**License**: CC-BY 4.0  
**Rationale**: Same as data for consistency

**Files**:
- README.md, CLAUDE.md, CITATION.cff
- Paper manuscript (`paper/main.tex`)

---

## Future Technology Considerations

### Potential Additions

1. **Web API**: REST API for programmatic access (FastAPI, Rocket.rs, or Demetrios HTTP server)
2. **Visualization**: Interactive dashboard (Julia Genie, Plotly Dash, or web frontend)
3. **Database**: PostgreSQL or SQLite for structured storage (currently flat files)
4. **Containerization**: Docker for reproducible environments
5. **Cloud Deployment**: AWS S3, Google Cloud Storage for large datasets

### Technology Constraints

- **NO PYTHON**: Maintain Julia + Demetrios exclusivity
- **Reproducibility First**: Any new technology must not compromise reproducibility
- **FAIR Compliance**: All additions must support FAIR data principles

---

## Summary

DOSA's hybrid architecture leverages:

1. **Demetrios**: Core scientific algorithms with epistemic computing
2. **Julia**: Mature ecosystem for I/O, orchestration, and validation
3. **Cross-Validation**: Dual implementation ensures correctness
4. **Open Standards**: CSV, Parquet, JSONL for interoperability
5. **Reproducibility**: Committed dependencies, semantic versioning, DOI archival

This stack balances innovation (Demetrios showcase) with pragmatism (Julia ecosystem) to deliver a reproducible, high-quality scientific dataset.
