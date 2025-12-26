# Metadata Outputs

This directory stores versioned metadata files required for SOTA++ evaluation.

## Files

- `labels_oriter.parquet`: Tier A ori/ter labels derived from DoriC.
- `oriter_eval.csv`: GC-skew ori/ter evaluation vs DoriC.
- `oriter_eval_summary.json`: Summary stats for ori/ter evaluation.
- `symmetry_spectrum.csv`: Spectrum summaries with null p/q-values.
- `symmetry_spectrum_summary.json`: Summary stats for spectrum run.
- `doric_version.json`: DoriC download provenance (URL, checksum, version).
- `doric_coverage.json`: Coverage stats for DoriC ↔ replicon matches.

Raw DoriC archives and CSVs are stored under `data/doric/` (gitignored).
