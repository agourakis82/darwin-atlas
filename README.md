# DSLG Atlas — Demetrios Operator Symmetry Atlas

A reproducible, DOI-versioned database of operator-defined symmetries in complete bacterial replicons.

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
[![Release](https://img.shields.io/github/v/release/agourakis82/darwin-atlas)](https://github.com/agourakis82/darwin-atlas/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Data: CC-BY](https://img.shields.io/badge/Data-CC--BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

## Overview

DSLG Atlas implements a hybrid architecture combining:
- **Julia** (Layer 0+1): Reference implementation and orchestration
- **Demetrios** (Layer 2): High-performance kernels with epistemic computing

The atlas computes:
- **Exact symmetry metrics**: Orbit sizes, palindrome detection, RC-fixed sequences
- **Approximate symmetry**: d_min/L (minimum normalized dihedral distance)
- **Algebraic verification**: Dicyclic group Dic_n → D_n double cover
- **Epistemic Knowledge**: Full provenance tracking with validation

## Quick Start

```bash
# Clone repository
git clone https://github.com/agourakis82/darwin-atlas.git
cd darwin-atlas

# Setup Julia dependencies
make setup-julia

# Run tests
make test-julia

# Run pipeline (small test)
make pipeline MAX=50 SEED=42

# Generate epistemic Knowledge layer
make epistemic MAX=50 SEED=42
```

## How to Reproduce

To reproduce the dataset from scratch:

```bash
# 1. Clone at specific version
git clone https://github.com/agourakis82/darwin-atlas.git
cd darwin-atlas
git checkout v0.1.0-epistemic

# 2. Install dependencies
make setup-julia

# 3. Run full pipeline
make pipeline MAX=50 SEED=42

# 4. Generate epistemic layer
make epistemic MAX=50 SEED=42

# 5. Verify checksums
cd data/manifest && sha256sum -c checksums.sha256
```

## How to Create Snapshot

Create a deterministic dataset snapshot for archiving:

```bash
# Build snapshot (requires pipeline + epistemic completed)
make snapshot MAX=50 SEED=42

# Output: dist/atlas_snapshot_v1/
#   ├── README_DATASET.md
#   ├── manifest/
#   ├── tables/
#   ├── epistemic/
#   └── CHECKSUMS.sha256

# Create zip for Zenodo upload
make snapshot-zip
# Output: dist/atlas_snapshot_v1.zip
```

## Directory Structure

```
darwin-atlas/
├── CLAUDE.md              # Detailed project specification
├── CITATION.cff           # Citation metadata
├── README.md              # This file
├── Makefile               # Build orchestration
├── demetrios/             # Demetrios kernels (Layer 2)
├── julia/                 # Julia implementation (Layer 0+1)
├── scripts/               # Build scripts
├── data/                  # Output data (gitignored)
├── dist/                  # Snapshot outputs (gitignored)
├── docs/                  # Documentation
│   ├── DATA_DICTIONARY.md
│   └── ZENODO_DOI.md
└── paper/                 # Scientific Data manuscript
```

## Data Dictionary

See [docs/DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md) for complete schema documentation.

### Core Tables

| File | Description |
|------|-------------|
| `atlas_replicons.csv` | Replicon metadata (accession, length, GC, taxonomy) |
| `dicyclic_lifts.csv` | Dic_n → D_n verification results |
| `quaternion_results.csv` | Quaternion lift verification |

### Epistemic Layer

| File | Description |
|------|-------------|
| `atlas_knowledge.jsonl` | Knowledge records with provenance |
| `schema_atlas_knowledge.json` | JSON Schema definition |
| `atlas_knowledge_report.md` | Validation summary |

## Requirements

### Julia (required)
- Julia 1.10+
- Dependencies in `julia/Project.toml`

### Demetrios (optional)
- Demetrios compiler v0.63.0+
- Features: units, refinement, ffi

## Usage

### Run Pipeline

```bash
# Full pipeline
make pipeline

# With custom parameters
make pipeline MAX=1000 SEED=123
```

### Run Tests

```bash
make test           # All tests
make test-julia     # Julia only
```

### Cross-Validation

```bash
make cross-validate   # Compare Demetrios and Julia outputs
```

## Citation

If you use this dataset, please cite:

```bibtex
@misc{agourakis2025dslg,
  author = {Agourakis, Demetrios Chiuratto},
  title = {{DSLG Atlas}: Demetrios Operator Symmetry Atlas},
  year = {2025},
  publisher = {GitHub/Zenodo},
  url = {https://github.com/agourakis82/darwin-atlas},
  doi = {10.5281/zenodo.XXXXXXX},
  note = {Version 0.1.0-epistemic}
}
```

Or use the CITATION.cff file for automatic citation.

## DOI and Archiving

- **GitHub Release**: [v0.1.0-epistemic](https://github.com/agourakis82/darwin-atlas/releases/tag/v0.1.0-epistemic)
- **Zenodo DOI**: [To be assigned — see docs/ZENODO_DOI.md](docs/ZENODO_DOI.md)

## License

- **Code**: MIT License
- **Data**: CC-BY 4.0

## Contact

- **Author**: Demetrios Chiuratto Agourakis, MD (candidate), Ch.E., LLM, Mac (candidate)
- **Email**: demetrios@agourakis.med.br
- **Issues**: [GitHub Issues](https://github.com/agourakis82/darwin-atlas/issues)
