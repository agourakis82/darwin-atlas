# Implementation status snapshot

**Observed:** 2026-07-31

**Base commit:** the commit introducing this file on branch
`codex/sounio-primary-wip` (parent: `9897b8ba12f797a80926c85daf77126cf23cf72e`);
the evidence below was produced from that exact tree.

**Specification:** 0.1.0 normative draft

**Sounio pin:** `37de2c9eefe68f3457a2c66004eff68bba5b4446` (observed on the
official `main` at 2026-07-31T01:08:49Z and recorded in
`toolchains/sounio.lock.json`)

This is an evidence snapshot, not a timeless project-status claim. Evidence
from older pins or older source hashes is stale and was regenerated.

## Verified in this snapshot

| Check | Result | Evidence boundary |
|---|---|---|
| Normative documents exist | PASS | `make contract` |
| Receipt schema and window JSONL schema are valid JSON and fix producer/validator roles and `canonical_only` | PASS | Ruby JSON parse plus contract assertions |
| README, CFF, and GitHub Actions YAML parse/format checks | PASS | Ruby YAML parse and `git diff --check` |
| Frozen input checksum closure | PASS | `sha256sum -c data/fixtures/mini_pipeline/SHA256SUMS` inside `make contract` |
| Official pinned Sounio operator fixture | PASS | `souc check`, compile, and execution at `37de2c9eefe68f3457a2c66004eff68bba5b4446` |
| Base-only Julia operator differential fixture | PASS | Four Sounio observations recomputed independently; exact agreement, tolerance 0 |
| Streaming multi-record IUPAC FASTA fixture | PASS | 81 bytes processed in five 17-byte reads; two records; ambiguity preserved |
| Base-only Julia FASTA differential fixture | PASS | Six valid/error cases, two records, counts/hash/offsets exact at tolerance 0 |
| Frozen mini-pipeline through Sounio | PASS | FASTA streaming + metadata TSV association + non-overlapping windows + `delta_R`/`delta_RC` + explicit exclusions + deterministic JSONL; 12 lines from 4 records |
| Negative metadata fixtures | PASS | `METADATA_INVALID` (exit 9) and two `METADATA_MISMATCH` (exit 10) cases with exact record/offset/byte tuples |
| Base-only Julia mini-pipeline differential | PASS | Independent recomputation matches the persisted JSONL byte for byte (12/12 windows, tolerance 0) and every negative error tuple exactly |
| Corrupted-artifact detector check | PASS | Julia rejects a one-digit perturbation of the persisted JSONL |
| Canonical pipeline with missing Sounio producer | BLOCKED as designed, exit 2 | `make pipeline` |
| Mini-pipeline with missing `SOUNIO_REPO` | BLOCKED as designed, exit 2 | `scripts/run_sounio_mini_pipeline.sh` |
| Cross-validation with missing Sounio library | BLOCKED as designed, exit 2 | `julia --project=julia julia/scripts/cross_validation.jl` |
| Modified Julia files parse | PASS | `Meta.parseall` without loading project dependencies |
| Julia validator-development test suite | ENVIRONMENT BLOCKED | Julia 1.12.2 could not precompile its `Pkg` stdlib because `OpenSSL_jll` was absent |

The Julia environment error occurred before the DarwinAtlas package or its tests
loaded. It is not evidence that project tests pass or fail.

## Toolchain availability

| Tool | Observed state |
|---|---|
| Sounio `souc` | official pinned checkout works through Lima `souc-linux`; the host is arm64 and cannot execute the Linux x86-64 Madaros natively |
| NCBI Datasets CLI `datasets` | missing from `PATH` |
| Julia | 1.12.2 present; Base-only validators work; local project `Pkg` dependency broken |

All executable evidence below was produced from the official repository at the
exact commit in `toolchains/sounio.lock.json`. The Sounio launcher SHA256 is
`ad3ee58b3835cccfbf9382fba01498bc61bdcb8402c8ef47c1c3abf26099c008` (unchanged
across the last three pins).

Operator fixture evidence identifiers:

- fixture source SHA256: `18c44b447b7e82716c31eaf0b318c7552028eb97593156aed606463d3ee8099c`;
- compiled ELF SHA256: `3df4963d3ff43ac518d7f7aff21dad255ec6671caa3deacaefa7f3398b4d9082`
  (bit-identical to the previous pin's build);
- Sounio stdout artifact SHA256: `7a530525483a31c62bbf2f9c0cd382b69830c167a4d30a41a09568f223f98dda`
  (differs from the previous snapshot only because the runner log embeds the
  pinned commit).

FASTA fixture evidence identifiers:

- FASTA source SHA256: `5084d9e3facb97509fe79d7b6f0bcd59533f1db287b8b899bf43e25ef30dbf27`;
- compiled FASTA ELF SHA256: `30fe6f7f9eef19491eb1ad14daf4ee11c21a6d807617773f1d103417e542c224`;
- valid multi-record input SHA256: `a43937529b927c0346b30c0e1c2c01647f73b609773678fd08b91ddc9fe4ad46`;
- Sounio FASTA stdout artifact SHA256: `f058cce4e867012c0bfd23186ca030ffd0d30a3642d929c3cdebe964c07587a4`.

Mini-pipeline evidence identifiers:

- pipeline source SHA256: `5084d9e3facb97509fe79d7b6f0bcd59533f1db287b8b899bf43e25ef30dbf27`
  (the mini-pipeline is the `--pipeline` mode of the same
  `sounio/src/fasta_stream_fixture.sio`; the compiled ELF is the same
  `30fe6f7f…` build);
- frozen inputs (also in `data/fixtures/mini_pipeline/SHA256SUMS`):
  - `pipeline_fixture.fa` SHA256: `52837bc09d6394badf8373952142df05d478869d1ebca1046565c5e24f9ab35e`;
  - `pipeline_metadata.tsv` SHA256: `e29591db8f2532b5e19b6a82f7303a49d6e258386ac381d19085f8b7aadd5e4b`;
  - `metadata_invalid.tsv` SHA256: `333727a9331fdc2aa23772a579b1d8ea871d389a08b00723f5881fc47a1adc86`;
  - `metadata_mismatch.tsv` SHA256: `451f7e9ec4df3f04ef81a57df790d1a8b9a0adc65ee0c91329e2cd5acf18f168`;
  - `metadata_short.tsv` SHA256: `6e63efea4c1a8403beb717bfdbb7a844745a677130b65cf203e9fdda3fd7a28a`;
- persisted JSONL artifact SHA256: `fe07e8f45ea6d2ab0ab7409ee439bb1543707ed7cf6f9049686d194bbf5e2a52`
  (12 lines; 10 `ok` windows, 1 `AMBIGUOUS_WINDOW`, 1 `PARTIAL_WINDOW`);
- JSONL line schema: `schemas/window_operator_profile.schema.json`.

The fixtures deliberately use `--science-boundary off`; they are executable
specification checks, not release receipts. The two NCBI records are 16 bp
prefixes of `NC_000913.3` and `NC_002128.1` (re-verified against Entrez
`efetch` on 2026-07-31), not complete replicons; the other two records are
synthetic controls. See `data/fixtures/mini_pipeline/README.md`.

## Pinned upstream compatibility findings

At the current pin, the native x86-64 backend implements
`str_slice(s, start, end)` as a suffix operation that ignores its third
argument, and `str_from_bytes` resolves only local array handles, not globals
(`self-hosted/native/codegen_x86_linux.sio`). The fixture therefore builds
bounded spans by copying bytes into a local buffer before `str_from_bytes`,
and compares header tokens byte by byte. Any future upstream bump must re-run
all fixture gates.

The earlier finding at `3bdcabda266ccb47ba6072258fd9fc1675a3a389` still
stands: the upstream `stdlib/genomics/io/fasta.sio` reader is in-memory,
`Seq256`-bound, and decodes `N`/`n` to canonical code zero. DOSA does not
reuse the upstream FASTA reader as its canonical ingestion boundary; any later
upstream replacement must repeat the same IUPAC/error differential checks at
the then-current pin. The upstream `examples/real_world/06_darwin_atlas_pipeline.sio`
remains reference material only (64-record cap, synthetic sequences, `djb2`
labeled as SHA-256, 256-character analysis cap).

## Release gates

| Gate | State | Missing evidence |
|---|---|---|
| G0 source/compiler binding | PARTIAL | official compiler/source/executable hashes recorded; atlas tree is not a clean released commit |
| G1 Sounio executable fixtures | PARTIAL | positional, streaming FASTA, and mini-pipeline fixtures execute; k-mer and full fixture set absent |
| G2 miniature NCBI end-to-end fixture | PASS (fixture scope) | frozen NCBI-prefix + synthetic fixture runs end to end through Sounio to deterministic JSONL; scope is positional windows over 16 bp prefixes, not complete replicons |
| G3 independent Julia differential validation | PARTIAL | operator, six FASTA cases, and the complete mini-pipeline JSONL (12/12 windows) reproduced byte-exact at tolerance 0; deterministic atlas sample absent |
| G4 schema/provenance/checksum closure | PARTIAL | receipt and window JSONL schemas exist; mini-pipeline input checksum closure verified; no real receipt or canonical artifacts |
| G5 scale benchmark | RED | no pilot executable |
| G6 DOI-ready immutable bundle | RED | upstream gates incomplete |

## Next implementation slice

1. Extend the Sounio baseline from positional metrics to k-mer composition,
   then add null-model complexity only after differential fixtures pass.
2. Promote the JSONL writer toward the canonical `window_operator_profiles`
   product fields (metric version is already emitted) and bind a real
   `run_receipt.json` to a clean released commit.
3. Acquire a frozen miniature cohort of complete replicons with the NCBI
   Datasets CLI and recorded package checksums.
4. Repair or replace the local Julia 1.12.2 project environment so the
   validator-development test suite can run.
