# Implementation status snapshot

**Observed:** 2026-08-03

**Base commit:** Fase L work on branch `codex/u250-dinucleotide-null`, based on
published Fase K commit `0f0aa04ee7c95c7995d21cbe04ebe242798abde6`.
Receipt-bound hashes below identify the exact produced tree and artifacts.

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
| Dual k-mer kernel equivalence | PASS | Scale-oriented rolling-table kernel (`--pipeline`, one fixed 512 KiB 4^8 table, orbits evaluated over observed codes only — including zero-representative orbits) and simple reference kernel (`--pipeline-reference`) required byte-identical on every valid fixture; two optimized runs + one reference run agree on 12/12 (k4) and 84/84 (k8) lines |
| Optimized kernel wall time (k8 fixture) | PASS | Observed-orbit iteration reduced the optimized `--pipeline` k8 fixture run (16 windows, k=1..8, both transforms) from 57.2 s to 1.8 s wall (~3.6 s to ~0.11 s per window) on the Lima `souc-linux` x86-64 guest, with byte-identical JSONL; the full 4^k scan would project to ~290 h for one 4.6 Mbp chromosome at 16/16 windows, the observed-orbit scan to ~9 h |
| Parameter artifact validation | PASS | Canonical JSON hashed and rendered to strict 13-line flat form by the runner; executable revalidates keys/order/domains; eight frozen negative parameter fixtures fail with `PARAM_INVALID` (exit 11) at exact byte offsets |
| Negative metadata fixtures | PASS | `METADATA_INVALID` (exit 9) and two `METADATA_MISMATCH` (exit 10) cases with exact record/offset/byte tuples |
| Base-only Julia mini-pipeline differential | PASS | Independent recomputation matches all four persisted JSONL artifacts byte for byte (192/192 windows across the main, k8, and two null-model cases, tolerance 0) and every negative error tuple exactly (3 metadata + 10 parameter, offsets re-derived from the flat bytes); invariants asserted: denominator == effective_count, `reverse_kmer_imbalance_1_numerator == 0`, ratios in [0,1], transforms are involutions, masked k-mers never cross ambiguity, unavailable implies below-threshold count |
| Window JSONL schema 0.3.0 validation | PASS | All 192 persisted lines validate against `schemas/window_operator_profile.schema.json` with exact 183-field order; all four parameter fixtures (two null-free, two null-model) validate against `schemas/pipeline_parameters.schema.json`; all ten invalid parameter fixtures are rejected |
| Frozen miniature complete-replicon cohort | PASS | Two complete RefSeq assemblies (four circular replicons) acquired with the official NCBI Datasets CLI 18.34.0 and frozen under `data/cohort/mini/`; official NCBI per-file MD5 closure holds for every committed package-derived file; FASTA record lengths match the official sequence reports for all four replicons; `sha256sum -c data/cohort/mini/SHA256SUMS` passes inside `make contract` |
| Complete-replicon engineering smoke | PASS | Optimized kernel ran end to end on plasmid `NC_002127.1` (3,306 bp, circular, pure ACGT) from the frozen cohort: 207 JSONL lines (206 full + one 10 bp partial window) in 5 s wall on the Lima guest, two runs byte-identical (sha256 `b26ecbe6c4d67b346443b3aa5552f28e722f2104c8bbc3d7b8884eca5233b29b`), independent Julia recomputation byte-exact (207/207 windows, tolerance 0); engineering smoke, not the pilot and not a release receipt |
| Canonical product schemas | PASS | `cohort_assemblies`, `atlas_replicons`, and `excluded_records` schemas 0.1.0 parse and fix field order/reason-code enums; contract assertions in `make contract` |
| Engineering canonical products (Fase E) | PASS | All four replicons: Sounio `--replicon-profile` and `--exclusions` products emitted and recomputed byte-exact in Julia (4 profiles, 38 exclusions, tolerance 0); plasmid window products (207 + 5,796 lines) byte-identical across two runs and byte-exact vs the independent Julia recomputation (6,003/6,003 windows); cohort product rebuilt independently from the frozen manifest; chromosome window products deferred to the Fase I benchmark; engineering scope, not the pilot dataset |
| Corrupted-artifact detector check | PASS | Julia rejects a one-digit perturbation of the persisted JSONL (positional, k-mer, and null-summary fields) |
| Deterministic stratified Julia atlas sample (spec §12.2, Fase F) | PASS | Fixed sample definition 0.1.0 (strata: all excluded-status windows, first/last window per record, plus ok windows with `fmix64(seed, record_index, window_index) mod 64 = 0`; seed bound to the first 16 hex of the persisted `parameters_sha256`): 5/207 windows on pOSAK1 and 90/5,796 on pO157 recomputed byte-exact at tolerance 0 by the Julia validator (sample coordinate manifests sha256 `62f51dc9db292406be718eca601d01e1412fd6924c641ff69def4e1c476ecc0f` and `d7ed3e4ad17a41788520a6f89ef0503cb4b9f35d705741866d03cd4f1bf35309`); perturbing a sampled line is rejected while perturbing an unsampled line passes, confirming detector scope; runs wired into `scripts/run_cohort_products.sh` |
| Fixture null-model engine (window schema 0.3.0, Fase G) | PASS | Additive 93-field null block (null_model/null_replicates/null_seed_derivation + per-metric available-count/mean/mad/q025/q975 over exact integer scaled draws); mononucleotide-preserving Fisher-Yates shuffle null (LCG mod 2^31 seeded from the parameter-hash prefix, window_start, record_index, metric index, replicate) executed on two new fixture cases (12 + 84 windows, 8 replicates) and recomputed byte-exact by the independent Base-only Julia engine (192/192 windows, tolerance 0, every shuffled draw identical); optimized and reference kernels byte-identical over all shuffled draws (null_k4 artifact identical across kernel selections); new parameter-negative fixtures rejected (unknown null model; none+8 cross-field violation); executable specification only — the ADR-0002 pilot null (primary model, replicate count, seed derivation) remains proposed and no canonical product carries non-null summaries |
| Exact dinucleotide-null CPU differential (Fase L) | PASS | ADR-0003 fixes `euler_wilson_fixed_endpoints_v1` for an engineering fixture: edge-distinct directed dinucleotide multigraph, fixed endpoints, Wilson loop-erased arborescence, randomized outgoing lists with tree edge last, rejection-sampled bounded choices, and 2^20-step replicate substreams. Official pinned Sounio emitted 64/64 deterministic sequence draws across 8 graph-shape cases; Julia independently recomputed the SHA-256 seed and every output byte, then verified length, endpoints, mononucleotide counts, and all 16 dinucleotide counts at tolerance 0. A one-base artifact perturbation is rejected; an ambiguous input fails closed with exit 12 and no output. Parameters sha256 `45ecde71...`, cases `b471a8a6...`, Sounio source `bb1af8cd...`, artifact `a21e1f20...`. |
| Exact dinucleotide-null U250 fixture (Fase L) | PASS (engineering fixture) | Vitis 2025.1 built the real U250 bitstream (sha256 `b123ea0cfba5284e16e457bc1326435864ef50123e0ec2208666a741b888c9be`, 52,316,448 bytes) and XRT 2.23.0 executed it on BDF `0000:d8:00.1`; all 1,024/1,024 base slots (8 cases × 8 replicates × 16 slots) matched the Julia golden fixture at tolerance 0. Receipt `receipts/dinucleotide-null-556ac81-20260803T171300Z/` binds the official Sounio pin/source/executable/artifact hashes, build artifacts, real-card log, and exactly two preserved shell/DFX critical warnings (`Constraints 18-952`, `Vivado 12-4430`). Engineering fixture only: ADR-0002 remains proposed, `pilot_null_primary=false`, and no biological or performance claim is made. |
| Two-stage engineering run receipt (Fase H) | PASS | `scripts/emit_products_receipt.sh` reruns the Sounio products pipeline from a clean published tree (commit `b3682abb30ec1a284398ad78df6df7e1dd471397`, `dirty=false`, tree sha256 `55720a16fad888e254438d4e9fdf69cfdb2828015161ed940562d24fdf349a88`), emits a stage-1 receipt (`generated_unvalidated`, `validator=null`), runs the full Julia validation suite (Julia 1.12.2, tolerance 0: 4 profiles, 38 exclusions, cohort rebuild, 6,003/6,003 window-product bytes via the stratified sample 5/207 + 90/5,796), and closes a stage-2 receipt (`validated`, 5 commands, 8 artifacts, receipt sha256 `5d03b6d5ea70b8eab414f4831d9cb6ee750a9718261bb7fa2471fe63d4bf157f`) under `receipts/engineering-products-b3682abb-20260801T203932Z/`; the two large window products stay hash-bound in the receipt (not committed); structural receipt check wired into `make contract` (revalidates state/validator/commit and closes sha256 over the six committed receipt artifacts); engineering scope, not a release receipt |
| Arena-safe k-mer metric results (crash 182 fix) | PASS | The native backend allocates struct constructions from a compiler arena never reclaimed inside loops (probe: exit 182 between 1M and 2M constructions); both k-mer kernels returned a `KmerMetric` struct (16 constructions/window), killing `--pipeline` deterministically at window 65,533 (~1,048,5xx constructions, byte-identical death point 440,218,534 across two runs) on chromosome-scale input. The struct was removed in favor of `G_METRIC_*` globals in both kernels and the null-draw path; a 70,000-window synthetic record crosses the former barrier (rc=0); optimized artifacts for all four mini-pipeline fixture cases stay byte-identical to the Fase G published hashes (main `e5564ea3`, k8 `f87bd3f6`, null_k4 `4997efed`, null_k8 `d53de8b3`); optimized/reference kernel equivalence re-passed for main, k8, and null_k4 (null_k8 reference re-run deferred to the Fase J full battery) |
| Chromosome-scale benchmark (G5 evidence, Fase I) | PASS | `scripts/run_chromosome_benchmark.sh` ran the optimized kernel end to end on both frozen-cohort chromosomes at 16/16 windows, k=1..8 (guest phase detached via nohup + driver-log polling): NC_000913.3 290,104/290,104 lines (1,949,472,321 bytes, sha256 `59ad5c34a1f0cf9dfa41c7fee9e94403419c38bf2fe86a8f0c40c99ee3148650`, 4,588 s wall) and NC_002695.2 343,662/343,662 lines (2,309,418,997 bytes, sha256 `6d119d223162bcf27f4f9d5a2ba7fb952f2b1746c93b8dd8db7eaae4933fb0e4`, 4,943 s wall), both at a flat 6,804 kB peak RSS (Linux VmHWM) on the Lima x86-64 guest; structural check parsed every line (183 fields); the deterministic stratified Julia sample (spec §12.2) recomputed 4,464/4,464 and 5,308/5,308 sampled windows byte-exact at tolerance 0; receipt `receipts/chromosome-benchmark-53ccaccb-20260801T225452Z/` (window products hash-bound, not committed; engineering scope, not the pilot, not a release receipt) |
| Full battery rerun from scratch (Fase J) | PASS | Complete battery re-executed from zero on the release tree: operator and FASTA fixtures, the fail-closed mini-pipeline runner AND the independent differential (two full passes; optimized/reference kernel equivalence re-proven on all four cases including null_k8 over every shuffled draw: main `e5564ea3`, k8 `f87bd3f6`, null_k4 `4997efed`, null_k8 `d53de8b3` — all byte-identical to the Fase G published hashes), all negative metadata/parameter fixtures at exact error tuples, complete-replicon smoke differential, and the cohort products runner with Julia recomputation (6,003/6,003 plasmid windows, 4 profiles, 38 exclusions, cohort rebuild, stratified samples, tolerance 0); final marker `BATTERY_ALL_GREEN` (evidence hash `9522186bf15f52661168e99dfcb750f3ac35801b89edc2c7680be270b24c1956`) |
| Two-stage products receipt on the release tree (Fase J) | PASS | `scripts/emit_products_receipt.sh` re-emitted the validated two-stage receipt on the release commit `8bbe89fd2191787d6a5a125ed009629ac6ebfd14` (clean tree): `receipts/engineering-products-8bbe89fd-20260802T144440Z/`, receipt sha256 `7497c34a2fbfeca4c6dc05597d306bc05e95aa159ada0cc81a06af35d8dbc013`, structural check PASS, 5 commands, 8 artifacts, Julia 1.12.2 tolerance 0; wired into `make contract` |
| Engineering release bundle (G6 evidence, Fase J) | PASS (engineering scope) | `scripts/build_release_bundle.sh` produced `release/darwin-atlas-0.1.0-engineering-b04fdefd/`: git-archive tarball of commit `b04fdefd420d1d6b7855b62d9b8f8d6591fecab0` (sha256 `d738a78dc25560bf891f0ebc98242076bdefa485586af6098062e81ce4bd8e80`, 3,343,147 bytes), battery evidence, SHA256SUMS manifest, and `release_receipt.json` binding the archived commit (clean tree), the Sounio pin, the release-tree products receipt, the chromosome benchmark receipt, the battery evidence hash, and the tarball hash; DOI field is an explicit placeholder (`pending`, no deposit made); full hash closure re-verified in `make contract`; engineering release, NOT the pilot release (ADR-0002 remains proposed) |
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
| NCBI Datasets CLI `datasets` | pinned at `~/.local/dosa-tools/ncbi-datasets-v2/datasets` 18.34.0, binary SHA-256 `f1133f8278edc594b9c36082e08140c4cde0acfd2591118e4faf4e5055b3592c` (`dataformat` SHA-256 `625fc7d5760825ae0790280343a1c895069479124982e1648b8241fa47c1f134`) |
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

- pipeline source SHA256: `44e5db4a5b000a8175f3b8bbd732d394c997f8d78f04164d56046552d8798ea7`
  (the mini-pipeline is the `--pipeline`/`--pipeline-reference` mode of the
  same `sounio/src/fasta_stream_fixture.sio`; source and ELF changed relative
  to the previous snapshot because the file gained the `--replicon-profile`
  and `--exclusions` product modes; the pipeline kernels are unchanged);
- compiled mini-pipeline ELF SHA256: `443db0831e6c29dd4711fcf34894430f39ed240dba3c52cfcbe9133173a0b156`;
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

Mini cohort evidence identifiers (`data/cohort/mini/`):

- cohort scope: engineering-scale complete-replicon cohort for gates G2/G3;
  NOT the pilot `core` cohort of specification §8 (that manifest remains
  pending under proposed ADR-0002);
- assemblies: `GCF_000005845.2` (*E. coli* K-12 MG1655; chromosome
  `NC_000913.3`, 4,641,652 bp) and `GCF_000008865.2` (*E. coli* O157:H7
  Sakai; chromosome `NC_002695.2`, 5,498,578 bp; plasmids `NC_002127.1`
  3,306 bp and `NC_002128.1` 92,721 bp); all four replicons declared
  `circular` by the official GenBank LOCUS lines (`topology_locus.txt`);
- retrieval: 2026-07-31T18:04:35Z, NCBI Datasets CLI 18.34.0; download
  package SHA-256 `f1e34c49e83f9889eb265c8bd71f841ef4bac15ef3196ba59e7d60a907d6c6ad`;
  GBFF (topology) package SHA-256 `e1539824ef649046f5222f7babe7fde2eda7c39b04724e502ccf2b96cd38e106`;
- per-assembly genomic FASTA SHA-256:
  `53bb6a51b6e92139ced1e38f74b7938781027c52200922ff03718c2237d23bb4`
  (GCF_000005845.2) and
  `71c2e5c364293c9ba36fc2c7acbcaa75cd6884295fe06260ba198826a8b1ddd3`
  (GCF_000008865.2); official NCBI per-file MD5 manifest in `ncbi_md5sum.txt`;
- `cohort_manifest.jsonl` carries specification §11.1 fields plus provenance
  extensions; `replicons.tsv` fixes the replicon-level record order; every
  frozen byte is pinned in `SHA256SUMS` and verified by `make contract`.

Complete-replicon smoke evidence identifiers (`data/fixtures/cohort_smoke/`):

- input FASTA SHA-256 `972cf4a97b844492784c669d45300ff126dc89176a92c243a79ae9a307ed9562`
  (NC_002127.1 record extracted byte-exact from the frozen cohort assembly);
- persisted smoke JSONL artifact SHA-256
  `b92eac46e3ebd220ddfb99d71676b7c60ccbef57f8e8bb9d3530388435b701cf`
  (207 lines, 90 fields per line; two optimized runs byte-identical);
- smoke ELF SHA-256 `443db0831e6c29dd4711fcf34894430f39ed240dba3c52cfcbe9133173a0b156`
  (identical to the mini-pipeline ELF above — same source, same pin);
- optimized-kernel wall time: 4 s for 207 windows on the Lima `souc-linux`
  x86-64 guest (`DOSA_PIPELINE_TIMING` in the smoke runner log).

Engineering canonical products evidence identifiers (Fase E,
`scripts/run_cohort_products.sh`):

- product schemas: `schemas/cohort_assemblies.schema.json`,
  `schemas/atlas_replicons.schema.json`, `schemas/excluded_records.schema.json`
  (all 0.1.0, fixed field order, `additionalProperties: false`);
- `cohort_assemblies.jsonl` SHA-256
  `dda64346e767bc65bc4d74f4590363768755b56b3b58ac6241b2cca79c5f81a5`
  (2 lines; mechanical fixed-order transform of the frozen manifest, no
  scientific observations);
- `atlas_replicons.jsonl` SHA-256
  `5037581e2e339c2cab5fd2d910252c5cb3ca327e20318889fd33cfb7cdeace8e`
  (4 lines, one per replicon, Sounio `--replicon-profile`);
- `excluded_records.jsonl` SHA-256
  `675e77982e03bd1a0c95c6a856fdeda399a14fcd24d59c058d0c48a6f36d19d0`
  (38 lines: 4 partial-window positional exclusions plus k-mer
  below-threshold exclusions on the partial windows; Sounio `--exclusions`);
- plasmid window products: pOSAK1 207 lines SHA-256
  `b92eac46e3ebd220ddfb99d71676b7c60ccbef57f8e8bb9d3530388435b701cf`
  (byte-identical to the smoke artifact — same input, same parameters) and
  pO157 5,796 lines SHA-256
  `ead81fbcf81877711303d57ef20f41108faeaacffd718d100a30e3b68fb0e40d`;
- independent Julia recomputation: both plasmid window products byte-exact
  (6,003/6,003 windows) and all three non-window products byte-exact
  (4 replicon profiles, 38 exclusions, cohort product rebuilt from the
  frozen manifest), tolerance 0;
- timings on the Lima guest: chromosome exclusions passes 22-27 s each
  (O(n) availability rule), pO157 window product 125 s for 5,796 windows;
- chromosome-scale window products remain deferred to the Fase I benchmark.

## Pinned upstream compatibility findings

At the current pin, the native x86-64 backend implements
`str_slice(s, start, end)` as a suffix operation that ignores its third
argument, and `str_from_bytes` resolves only local array handles, not globals
(`self-hosted/native/codegen_x86_linux.sio`). The fixture therefore builds
bounded spans by copying bytes into a local buffer before `str_from_bytes`,
and compares header tokens byte by byte. Any future upstream bump must re-run
all fixture gates.

Two further constraints were observed while adding the product emitters.
First, `level` is a reserved word: a function parameter named `level` makes
the parser fail with an unlocated "Parse failed for module 0: 1 errors"
diagnostic. Second, string literals of ~110 or more bytes are rotated by the
native backend — the final byte wraps to the front of the printed string
(observed with a 110-byte JSON prefix, which printed as `"` + first 109
bytes). All emitted literals are therefore kept short and JSON lines are
assembled from multiple `print` calls; the byte-exact Julia differential
would catch any regression here.

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
| G0 source/compiler binding | PASS (engineering scope) | official compiler/source/executable hashes recorded; validated two-stage engineering receipts bound to clean published commits (`b3682abb`, `8bbe89fd`); engineering release tag `v0.1.0-engineering` published on the release commit; pilot-scale release binding pending (ADR-0002 proposed) |
| G1 Sounio executable fixtures | PARTIAL | positional, streaming FASTA, and parameterized mini-pipeline fixtures execute; the mononucleotide sensitivity engine and ADR-0003 exact dinucleotide-preserving candidate both execute under independent differentials; complete-replicon smoke and product modes execute on the frozen cohort; the metamorphic suite of spec §12.1 remains absent |
| G2 miniature NCBI end-to-end fixture | PASS (fixture scope + engineering products) | frozen NCBI-prefix + synthetic fixtures run end to end through Sounio to deterministic JSONL at the full predeclared k=1..8 pilot range; the frozen cohort additionally yields byte-validated engineering products: replicon profiles and exclusions for all four replicons, window products for both plasmids, and chromosome-scale window products for both chromosomes (Fase I benchmark); the canonical pilot run is pending |
| G3 independent Julia differential validation | PARTIAL | operator, six FASTA cases, all four mini-pipeline JSONL artifacts (192/192 windows including both mononucleotide-null cases), and all 64 Fase L exact dinucleotide-preserving sequence draws are reproduced byte-exact at tolerance 0; complete-replicon smoke, 6,003 plasmid windows, non-window products, and deterministic samples of both chromosome products also agree. Full non-sampled chromosome-scale recomputation and pilot-null product validation remain open. |
| G4 schema/provenance/checksum closure | PARTIAL | receipt, window JSONL 0.3.0 (183 fields with the additive null block), pipeline parameter (with optional null keys), and the three product schemas exist; mini-pipeline input checksum closure verified (including parameter fixtures); frozen cohort checksum closure verified against official NCBI MD5s; validated two-stage products and U250 dinucleotide engineering receipts are hash-closed and structurally re-checked in `make contract`; release-scope canonical pilot artifacts and receipt pending |
| G5 scale benchmark | PASS (engineering scope) | chromosome-scale window products for both frozen-cohort chromosomes with timing and memory receipts: NC_000913.3 290,104 windows in 4,588 s wall and NC_002695.2 343,662 windows in 4,943 s wall on the Lima x86-64 guest, both at a flat 6,804 kB peak RSS, recorded in `receipts/chromosome-benchmark-53ccaccb-20260801T225452Z/`; the pilot-scale executable and pilot parameters remain undecided (ADR-0002 proposed) |
| G6 DOI-ready immutable bundle | PARTIAL (engineering scope) | engineering-scope immutable bundle exists (`release/darwin-atlas-0.1.0-engineering-b04fdefd/`) with a release receipt hash-closing the tarball, the battery evidence, and both receipts; DOI assignment pending (explicit `pending` placeholder, no deposit); pilot-grade release still blocked on the G1 metamorphic suite (spec §12.1), full (non-sampled) chromosome-scale Julia recomputation (G3), and the ADR-0002 pilot decisions |

## Next implementation slice

1. Integrate the ADR-0003 exact dinucleotide candidate into persisted
   window-product summaries without changing Sounio's canonical-producer role.
2. Repair or replace the local Julia 1.12.2 project environment so the
   validator-development test suite can run.
3. Validate generator quality and pilot-scale runtime, then set the final
   replicate count and threshold under ADR-0002 (still proposed).
