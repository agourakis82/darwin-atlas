# Implementation status snapshot

**Observed:** 2026-07-30  
**Base commit:** `c895b7e4717a22fb8a60696edbac1d46fd21e94f`  
**Specification:** 0.1.0 normative draft

This is an evidence snapshot, not a timeless project-status claim.

## Verified in this snapshot

| Check | Result | Evidence boundary |
|---|---|---|
| Normative documents exist | PASS | `make contract` |
| Receipt schema is valid JSON and fixes producer/validator roles | PASS | Ruby JSON parse plus contract assertions |
| README, CFF, and GitHub Actions YAML parse/format checks | PASS | Ruby YAML parse and `git diff --check` |
| Official pinned Sounio operator fixture | PASS | `souc check`, compile, and execution at `3bdcabda266ccb47ba6072258fd9fc1675a3a389` |
| Base-only Julia differential fixture | PASS | Four Sounio observations recomputed independently; exact agreement, tolerance 0 |
| Streaming multi-record IUPAC FASTA fixture | PASS | 81 bytes processed in five 17-byte reads; two records; ambiguity preserved |
| Base-only Julia FASTA differential fixture | PASS | Six valid/error cases, two records, counts/hash/offsets exact at tolerance 0 |
| Canonical pipeline with missing Sounio producer | BLOCKED as designed, exit 2 | `make pipeline` |
| Cross-validation with missing Sounio library | BLOCKED as designed, exit 2 | `julia --project=julia julia/scripts/cross_validation.jl` |
| Modified Julia files parse | PASS | `Meta.parseall` without loading project dependencies |
| Julia validator-development test suite | ENVIRONMENT BLOCKED | Julia 1.12.2 could not precompile its `Pkg` stdlib because `OpenSSL_jll` was absent |

The Julia environment error occurred before the DarwinAtlas package or its tests
loaded. It is not evidence that project tests pass or fail.

## Toolchain availability

| Tool | Observed state |
|---|---|
| Sounio `souc` | official pinned checkout works through Lima `souc-linux`; not installed on host `PATH` |
| NCBI Datasets CLI `datasets` | missing from `PATH` |
| Julia | 1.12.2 present; Base-only validator works; local project `Pkg` dependency broken |

The passing executable fixture was built from the official repository and the
exact commit in `toolchains/sounio.lock.json`. The evidence identifiers were:

- Sounio launcher SHA256: `ad3ee58b3835cccfbf9382fba01498bc61bdcb8402c8ef47c1c3abf26099c008`;
- fixture source SHA256: `18c44b447b7e82716c31eaf0b318c7552028eb97593156aed606463d3ee8099c`;
- compiled ELF SHA256: `3df4963d3ff43ac518d7f7aff21dad255ec6671caa3deacaefa7f3398b4d9082`;
- Sounio stdout artifact SHA256: `344d5807b9bb3faa7cd13a39566f78f7071159d52bb0fc4914ed280dab480f49`.

The fixture deliberately used `--science-boundary off`; it is an executable
specification check, not a release receipt.

The FASTA evidence identifiers were:

- FASTA source SHA256: `b86431b754d587749f5baa9848f396a2b68a63cccbc729530c3f28d42746357a`;
- compiled FASTA ELF SHA256: `fbb51c6edd8a5295e5b45f792b4e4c0088de734d9f62057338d112e8c572fec2`;
- valid multi-record input SHA256: `a43937529b927c0346b30c0e1c2c01647f73b609773678fd08b91ddc9fe4ad46`;
- Sounio FASTA stdout artifact SHA256: `7d810b7d1245a23c7605e18ce369dfe49ae65d73c351b6223f12bcac77d3c877`.

All six fixture input hashes are printed by `run_sounio_fasta_fixture.sh`.

## Pinned upstream compatibility finding

At Sounio commit `3bdcabda266ccb47ba6072258fd9fc1675a3a389`, the upstream
`stdlib/genomics/io/fasta.sio` reader is in-memory, limited to `Seq256`, and
decodes `N`/`n` to canonical code zero. The upstream `genomics/dihedral.sio`,
`types.sio`, and `tests.sio` surfaces are disabled pending parser support.

DOSA therefore does not reuse the current upstream FASTA reader as its canonical
ingestion boundary. A project-owned streaming executable fixture now closes the
minimal parsing contract; any later upstream replacement must repeat the same
IUPAC/error differential checks.

The same pinned upstream includes
`examples/real_world/06_darwin_atlas_pipeline.sio`, a useful CLI/dialect demo
but not a canonical DOSA producer. It caps selection at 64 records, generates
synthetic sequences even when accessions come from an assembly summary, labels
a `djb2` value as `checksum_sha256`, and analyzes at most 256 FASTA characters.
Those behaviors violate the frozen-input, checksum, and full-replicon contracts,
so the example is treated as reference material only.

## Release gates

| Gate | State | Missing evidence |
|---|---|---|
| G0 source/compiler binding | PARTIAL | official compiler/source/executable hashes recorded; atlas tree is not a clean released commit |
| G1 Sounio executable fixtures | PARTIAL | positional and streaming FASTA fixtures execute; k-mer, writer, and full fixture set absent |
| G2 miniature NCBI end-to-end fixture | RED | reader exists but operator/writer integration and frozen NCBI metadata are absent |
| G3 independent Julia differential validation | PARTIAL | operator and six FASTA cases match exactly; deterministic atlas sample absent |
| G4 schema/provenance/checksum closure | PARTIAL | receipt schema exists; no real receipt or canonical artifacts |
| G5 scale benchmark | RED | no pilot executable |
| G6 DOI-ready immutable bundle | RED | upstream gates incomplete |

## Next implementation slice

1. Connect the verified streaming reader to the positional operator kernel.
2. Define a deterministic JSONL writer and a tiny frozen FASTA/metadata fixture.
3. Extend the Sounio baseline from positional metrics to k-mer composition,
   then add null-model complexity only after differential fixtures pass.
4. Repair or replace the local Julia 1.12.2 project environment, then extend
   the Base-only artifact oracle to the miniature pipeline outputs.
