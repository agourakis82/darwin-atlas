# DSLG Atlas Dataset — Demetrios Operator Symmetry Atlas

**Version**: {{VERSION}}
**Generated**: {{TIMESTAMP}}
**Git SHA**: {{GIT_SHA}}
**Pipeline Parameters**: MAX={{MAX}}, SEED={{SEED}}

## Description

This dataset contains operator-defined symmetry metrics computed on complete bacterial replicons from NCBI RefSeq. It implements dihedral group D_n actions (identity, reverse, complement, reverse-complement) on circular DNA sequences.

## Contents

```
atlas_snapshot_v1/
├── README_DATASET.md          # This file
├── manifest/
│   ├── manifest.jsonl         # Download manifest with accessions and timestamps
│   ├── checksums.sha256       # SHA256 checksums for all downloaded sequences
│   └── pipeline_metadata.json # Pipeline parameters and versions
├── tables/
│   ├── atlas_replicons.csv    # Core replicon metadata
│   ├── dicyclic_lifts.csv     # Dicyclic group Dic_n verification results
│   └── quaternion_results.csv # Quaternion lift verification
├── epistemic/
│   ├── schema_atlas_knowledge.json      # JSON Schema for Knowledge records
│   ├── atlas_knowledge_report.md        # Validation report (636 records, 7212 checks)
│   └── atlas_knowledge_sample_50.jsonl  # Sample of first 50 Knowledge records
└── figures/                   # (if generated)
```

## Data Dictionary

See `docs/DATA_DICTIONARY.md` in the repository for complete column definitions.

### Quick Reference

**atlas_replicons.csv**
| Column | Type | Description |
|--------|------|-------------|
| assembly_accession | String | NCBI assembly ID (GCF_...) |
| replicon_id | String | Internal stable identifier |
| length_bp | Int64 | Sequence length in base pairs |
| gc_fraction | Float64 | GC content [0.0, 1.0] |
| taxonomy_id | Int64 | NCBI taxonomy ID |
| checksum_sha256 | String | SHA256 of sequence data |

## Provenance

- **Source**: NCBI RefSeq complete bacterial genomes
- **Filter**: Assembly level = "complete genome"
- **Random seed**: {{SEED}} (for reproducible genome selection)
- **Maximum genomes**: {{MAX}}

## Reproducibility

To regenerate this dataset:

```bash
git clone https://github.com/agourakis82/darwin-atlas.git
cd darwin-atlas
git checkout {{GIT_SHA}}
make snapshot MAX={{MAX}} SEED={{SEED}}
```

## Citation

If you use this dataset, please cite:

```bibtex
@misc{agourakis2025dslg,
  author = {Agourakis, Demetrios Chiuratto},
  title = {{DSLG Atlas}: Demetrios Operator Symmetry Atlas},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/agourakis82/darwin-atlas},
  note = {Version {{VERSION}}}
}
```

## License

- **Code**: MIT License
- **Data**: CC-BY 4.0

## Contact

Demetrios Chiuratto Agourakis
Email: demetrios@agourakis.med.br
