# Darwin Operator Symmetry Atlas (DOSA)

A reproducible, DOI-versioned database of operator-defined symmetries in complete bacterial replicons.

[![CI](https://github.com/YOUR_USERNAME/darwin-atlas/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_USERNAME/darwin-atlas/actions/workflows/ci.yml)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)

## Overview

DOSA implements a hybrid architecture combining:
- **Julia** (Layer 0+1): Reference implementation and orchestration
- **Demetrios** (Layer 2): High-performance kernels with epistemic computing

The atlas computes:
- **Exact symmetry metrics**: Orbit sizes, palindrome detection, RC-fixed sequences
- **Approximate symmetry**: d_min/L (minimum normalized dihedral distance)
- **Algebraic verification**: Dicyclic group Dic_n → D_n double cover

## Quick Start

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/darwin-atlas.git
cd darwin-atlas

# Setup (Julia only)
make setup-julia

# Run tests
make test-julia

# Run full pipeline (downloads ~50,000 genomes)
make pipeline MAX=200  # Start small for testing
```

## Directory Structure

```
darwin-atlas/
├── CLAUDE.md           # Detailed project specification
├── README.md           # This file
├── Makefile            # Build orchestration
├── demetrios/          # Demetrios kernels (Layer 2)
├── julia/              # Julia implementation (Layer 0+1)
├── data/               # Output data (gitignored)
└── paper/              # Scientific Data manuscript
```

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

# Skip download (use existing data)
julia --project=julia julia/scripts/run_pipeline.jl --skip-download
```

### Run Tests

```bash
# All tests
make test

# Julia only
make test-julia

# Validation only
make validate
```

### Cross-Validation

```bash
# Compare Demetrios and Julia outputs
make cross-validate
```

## Data Schema

### atlas_replicons.csv
| Column | Type | Description |
|--------|------|-------------|
| assembly_accession | String | NCBI assembly ID |
| replicon_id | String | Internal stable ID |
| length_bp | Int64 | Sequence length |
| gc_fraction | Float64 | GC content [0,1] |

### approx_symmetry_stats.csv
| Column | Type | Description |
|--------|------|-------------|
| replicon_id | String | Foreign key |
| window_length | Int64 | Window size (bp) |
| dmin_normalized | Float64 | d_min / L [0,1] |

## Citation

If you use this dataset, please cite:

```bibtex
@article{agourakis2025dosa,
  title={Darwin Operator Symmetry Atlas: A database of dihedral symmetries in bacterial genomes},
  author={Agourakis, Demetrios Chiuratto},
  journal={Scientific Data},
  year={2025},
  publisher={Nature Publishing Group}
}
```

## License

- **Code**: MIT License
- **Data**: CC-BY 4.0

## Contact

- **Author**: Demetrios Chiuratto Agourakis
- **Email**: demetrios@agourakis.med.br
- **Issues**: GitHub Issues
