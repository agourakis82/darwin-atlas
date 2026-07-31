# Implementation status snapshot

**Observed:** 2026-07-31

**Base commit:** the k=1..8 parameterization commit updating this file on
branch `codex/sounio-primary-wip` (published baseline: `bb2926d`);
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
| Frozen mini-pipeline through Sounio | PASS | Parameterized FASTA streaming + metadata TSV association + strict flat parameter validation + non-overlapping windows + `delta_R`/`delta_RC` + masked k-mer composition k=1..8 + explicit exclusions + deterministic JSONL schema 0.2.0; 12 lines (4/4) and 84 lines (16/16) |
| Masked k-mer composition (fixture scope, k=1..8) | PASS | Orbit-paired `reverse_kmer_imbalance_<k>`/`rc_kmer_imbalance_<k>` for k=1..8; explicit `K_OUT_OF_CONFIGURED_RANGE` and `INSUFFICIENT_EFFECTIVE_KMERS` reasons; unavailable combinations null, never zero-filled; k-mer fields independent of positional `status` |
| Dual k-mer kernel equivalence | PASS | Scale-oriented rolling-table kernel (`--pipeline`, one fixed 512 KiB 4^8 table) and simple reference kernel (`--pipeline-reference`) required byte-identical on every valid fixture; two optimized runs + one reference run agree on 12/12 (k4) and 84/84 (k8) lines |
| Parameter artifact validation | PASS | Canonical JSON hashed and rendered to strict 13-line flat form by the runner; executable revalidates keys/order/domains; eight frozen negative parameter fixtures fail with `PARAM_INVALID` (exit 11) at exact byte offsets |
| Negative metadata fixtures | PASS | `METADATA_INVALID` (exit 9) and two `METADATA_MISMATCH` (exit 10) cases with exact record/offset/byte tuples |
| Base-only Julia mini-pipeline differential | PASS | Independent recomputation matches both persisted JSONL artifacts byte for byte (96/96 windows, tolerance 0) and every negative error tuple exactly (3 metadata + 8 parameter, offsets re-derived from the flat bytes); invariants asserted: denominator == effective_count, `reverse_kmer_imbalance_1_numerator == 0`, ratios in [0,1], transforms are involutions, masked k-mers never cross ambiguity, unavailable implies below-threshold count |
| Window JSONL schema 0.2.0 validation | PASS | All 96 persisted lines validate against `schemas/window_operator_profile.schema.json` with exact 90-field order; both parameter fixtures validate against `schemas/pipeline_parameters.schema.json`; all eight invalid parameter fixtures are rejected |
| Corrupted-artifact detector check | PASS | Julia rejects a one-digit perturbation of the persisted JSONL (positional and k-mer fields) |
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

- FASTA source SHA256: `c6cf23101b0fd77beee344f2659091dd1ef3c151aee1a05d722924c249e1fbf6`;
- compiled FASTA ELF SHA256: `61b3e65a98e4232dea0204a8164b425ac359a497dc95d7d41011ea00464f1c92`;
- valid multi-record input SHA256: `a43937529b927c0346b30c0e1c2c01647f73b609773678fd08b91ddc9fe4ad46`;
- Sounio FASTA stdout artifact SHA256: `7be46efdb7968e79551a6157bcce904e91d9e246ae8e3ccf036806fc52948015`.

Mini-pipeline evidence identifiers:

- pipeline source SHA256: `7c2ceb790c7b62dd770f343a79f1dae9ef4b4c75beef8d128b2f0b3bbc99803f`
  (the mini-pipeline is the `--pipeline`/`--pipeline-reference` mode of the
  same `sounio/src/fasta_stream_fixture.sio`; source and ELF changed relative
  to the previous snapshot because the pipeline was parameterized and extended
  to k=1..8 with dual kernels);
- compiled mini-pipeline ELF SHA256: `9bb6824a61c09d9f49122a8d630d5992979ccf863d868bb8bb5906c8010a06a5`;
- frozen inputs (also in `data/fixtures/mini_pipeline/SHA256SUMS`):
  - `pipeline_fixture.fa` SHA256: `52837bc09d6394badf8373952142df05d478869d1ebca1046565c5e24f9ab35e` (unchanged);
  - `pipeline_k8_fixture.fa` SHA256: `4c8af28b13c85cc14394312dbd106b32aefa3d3e056550ee2ef484fea0517c75`;
  - `pipeline_metadata.tsv` SHA256: `e29591db8f2532b5e19b6a82f7303a49d6e258386ac381d19085f8b7aadd5e4b` (unchanged);
  - `pipeline_k8_metadata.tsv` SHA256: `2fee5c935ce0a2ee6fdaa735784638b1aec8eb3eab0f6cf51be9d3f582e255eb`;
  - `metadata_invalid.tsv` SHA256: `333727a9331fdc2aa23772a579b1d8ea871d389a08b00723f5881fc47a1adc86` (unchanged);
  - `metadata_mismatch.tsv` SHA256: `451f7e9ec4df3f04ef81a57df790d1a8b9a0adc65ee0c91329e2cd5acf18f168` (unchanged);
  - `metadata_short.tsv` SHA256: `6e63efea4c1a8403beb717bfdbb7a844745a677130b65cf203e9fdda3fd7a28a` (unchanged);
  - `parameters_k4.json` SHA256: `f01f5cd393bdb7c70ae775fbc89ad80743aacc6c3ac59127fcaa156c2c866097`;
  - `parameters_k8.json` SHA256: `fdb6a170e38b7401f19ae4b435d028a045080379f70116a0284f79c6dd1097ce`;
  - eight `params_invalid/*.json` fixtures pinned in `SHA256SUMS`;
- persisted JSONL artifact (4/4, `main`) SHA256:
  `526f4ee21b3fee22efc58ab06b7d5f913862c8f7d2a6f2a9d41fa106e082c8c1`
  (12 lines, 90 fields per line; 10 `ok` windows, 1 `AMBIGUOUS_WINDOW`,
  1 `PARTIAL_WINDOW`);
- persisted JSONL artifact (16/16, `k8`) SHA256:
  `57fc044c62a84fd1b453e1e340feb7cea8a9bc55e348e1f05bb245b9b72a486d`
  (84 lines, 90 fields per line; designed controls for self-reverse/self-RC
  orbits, lowercase+N masking, a fully ambiguous window, a 3 bp partial
  window, a de Bruijn B(4,4) record covering every 4-mer, and a 1024 bp
  deterministic LCG record);
- both artifact hashes are simultaneously the dual-kernel equivalence hashes
  (optimized run 1 == optimized run 2 == reference run);
- JSONL line schema: `schemas/window_operator_profile.schema.json` (0.2.0);
  parameter artifact schema: `schemas/pipeline_parameters.schema.json`.

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

A third constraint was observed in this snapshot: local arrays declared
inside hot functions allocate from a compiler arena that is never reclaimed
inside loops (`lower_array: arena_reset_totals ok=0 sites_reclaimed=0` at
compile time). A `kmer_transform` using a local `[i64; 8]` digit buffer
exhausted the arena after ~1M calls and aborted with exit 182 at a
deterministic point (window 7, k=8, orbit code 65382) in both kernels.
`kmer_transform` is now purely arithmetic (LSB-first digit reversal with no
local array); a 20×65536-call stress loop completes. Per-window local buffers
(for example the 8192-byte span buffer used once per emitted line) remain
safe at fixture scale but must be revisited before replicon-scale runs.

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
| G1 Sounio executable fixtures | PARTIAL | positional, streaming FASTA, and parameterized mini-pipeline fixtures (positional + masked k-mer k=1..8 with dual kernels and strict parameter validation) execute; real-cohort fixtures absent |
| G2 miniature NCBI end-to-end fixture | PASS (fixture scope) | frozen NCBI-prefix + synthetic fixtures run end to end through Sounio to deterministic JSONL at the full predeclared k=1..8 pilot range; scope is 16 bp prefixes plus synthetic sequences, not complete replicons |
| G3 independent Julia differential validation | PARTIAL | operator, six FASTA cases, and both mini-pipeline JSONL artifacts (96/96 windows) reproduced byte-exact at tolerance 0, including independently derived parameter-error offsets; deterministic atlas sample absent |
| G4 schema/provenance/checksum closure | PARTIAL | receipt, window JSONL 0.2.0, and pipeline parameter schemas exist; mini-pipeline input checksum closure verified (including parameter fixtures); no real receipt or canonical artifacts |
| G5 scale benchmark | RED | no pilot executable |
| G6 DOI-ready immutable bundle | RED | upstream gates incomplete |

## Next implementation slice

1. Acquire a frozen miniature cohort of complete replicons with the NCBI
   Datasets CLI and recorded package checksums (Fase D; CLI currently absent
   from `PATH` — do not install without an explicit decision).
2. Emit the canonical products (cohort/replicons/windows/exclusions) with a
   two-stage Sounio run receipt bound to a clean released commit.
3. Add the deterministic Julia atlas sample and null-model fixtures; set the
   pilot `min_kmer_effective_count` per proposed ADR-0002.
4. Repair or replace the local Julia 1.12.2 project environment so the
   validator-development test suite can run.
5. Run the G5 scale benchmark and assemble the G6 release bundle.
