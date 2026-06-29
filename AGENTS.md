# AGENTS.md

## Cursor Cloud specific instructions

This repo is the **Darwin Operator Symmetry Atlas (DOSA)**, a scientific-data pipeline.
The runnable/testable component is the **Julia** package in `julia/` (Layers 0+1).
The `demetrios/` kernels (Layer 2) are **optional** and require the `dc`/`souc`
compiler, which is not installed; all `make` targets that touch Demetrios already
no-op gracefully when `dc` is absent. There is **no Python** in this project.

### Toolchain
- Julia 1.10 is installed via `juliaup` (`~/.juliaup/bin`, already on `PATH` in
  login and non-login shells). The startup update script runs
  `julia --project=julia -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'`,
  so dependencies are ready on boot. No need to re-instantiate unless
  `julia/Project.toml` / `julia/Manifest.toml` change.

### How to test / run (standard commands; see `Makefile` and `README.md`)
- Tests: `make test-julia` (or `julia --project=julia -e 'using Pkg; Pkg.test()'`) — 38 tests.
- Run app without network: `julia --project=julia julia/scripts/run_pipeline.jl --skip-download`
  runs technical validation and writes `data/tables/{dicyclic_lifts,quaternion_results}.csv`.
- Full pipeline (downloads genomes): `make pipeline MAX=<n>` — see caveat below.

### Non-obvious caveats
- `make test` / `make pipeline` invoke `julia --project=julia`; ensure the shell has
  `~/.juliaup/bin` on `PATH` (it is, by default here).
- The `make pipeline` / `fetch_ncbi` step downloads from NCBI. The RefSeq
  `assembly_summary.txt` fetch works, but some sampled assemblies' genomic FASTA
  URLs can return an NCBI HTML error page instead of `.fna.gz`; the pipeline logs a
  warning per failure and continues (it does not crash). Core science (operators,
  exact/approx symmetry, quaternion double-cover, table generation) does **not**
  require network and is the primary thing to validate.
- `make clean` deletes `julia/Manifest.toml`; do **not** run it casually — the
  committed `Manifest.toml` is required for reproducibility per the Scientific Data
  workflow.
- Generated CSVs in `data/tables/*.csv` and `data/raw/` are gitignored outputs.
