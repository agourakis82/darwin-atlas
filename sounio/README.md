# Sounio producer

This directory is the canonical Darwin Atlas implementation surface. It targets
the exact official Sounio commit in `toolchains/sounio.lock.json`.

`src/operator_fixture.sio` is the first executable specification fixture. It
implements only the positional operator kernel required by scientific
specification 0.1.0:

- canonical-base validation without coercing ambiguity;
- reverse, complement, and reverse-complement;
- exact Hamming numerators for `delta_R` and `delta_RC`;
- reverse/RC fixed-point checks;
- involution and odd-length RC invariants.

Passing this fixture establishes an executable operator baseline. It does not
establish FASTA ingestion, atlas production, null-model inference, scale, or
scientific validation.

`src/fasta_stream_fixture.sio` is the executable ingestion baseline. It reads
files through repeated 17-byte POSIX reads, preserves the 15 DNA IUPAC symbols,
normalizes case without collapsing ambiguity, supports multiple records, and
emits stable reason codes for malformed input. The independent Julia oracle
recomputes its record summaries and error offsets from the checked-in bytes.

Passing the FASTA fixture establishes streaming parser behavior only. It does
not establish integration with the operator kernels, deterministic release
artifacts, NCBI cohort acquisition, or scale.

The same source also implements the frozen mini-pipeline in `--pipeline` mode:
each FASTA record is associated with a metadata TSV row, split into
non-overlapping windows (size and stride bound by the parameter artifact,
zero-based half-open coordinates, no wraparound), scored with
`delta_R`/`delta_RC` under the `canonical_only` ambiguity policy, and emitted
as deterministic JSONL (schema version `0.2.0`). Windows containing
non-canonical IUPAC symbols are excluded with `AMBIGUOUS_WINDOW`; a trailing
short window is excluded with `PARTIAL_WINDOW`; excluded windows carry null
positional metrics. The frozen inputs live in `data/fixtures/mini_pipeline/`
(a 4/4 fixture with two 16 bp NCBI prefixes — not complete replicons — and
two synthetic controls, plus a 16/16 fixture with three synthetic records)
with SHA-256 checksums in `SHA256SUMS`; each JSONL line is specified by
`schemas/window_operator_profile.schema.json`.

Pipeline parameters are a versioned, checksummed artifact
(`parameters_k4.json`, `parameters_k8.json`), specified by
`schemas/pipeline_parameters.schema.json`. The executable never parses JSON:
the runner hashes the canonical JSON and renders a strict 13-line flat
`key=value` form; the executable re-validates every key, order, and domain
and rejects any deviation with `PARAM_INVALID` (exit 11). Every emitted JSONL
line repeats the canonical `parameters_sha256`, binding output to an exact
parameter instance. Eight frozen negative parameter fixtures
(`params_invalid/`) must each fail with exact byte offsets, reproduced
independently by the Julia validator.

Each window is additionally scored with masked k-mer composition for the full
predeclared pilot range `k=1..8`: canonical k-mers are encoded in base 4,
k-mers containing ambiguous symbols are omitted (a masked k-mer never crosses
an ambiguous symbol), and `reverse_kmer_imbalance_<k>` /
`rc_kmer_imbalance_<k>` are computed over unordered orbits `{u,T(u)}` with
self-transformed k-mers contributing zero to the numerator and their count
once to the denominator (specification §7.2). Availability is explicit per
`k`: `kmer_<k>_unavailable_reason` is `K_OUT_OF_CONFIGURED_RANGE` when `k`
exceeds the configured `k_max` (every field null, never computed),
`INSUFFICIENT_EFFECTIVE_KMERS` when the effective count is below
`min_kmer_effective_count` (integer count, null imbalance fields — never
zero-filled), or null when the metrics are populated. K-mer fields are
independent of the positional `status`: an `AMBIGUOUS_WINDOW` may still emit
k-mer metrics.

Two kernels compute the identical metric: the simple reference kernel
(`--pipeline-reference`, per-code window rescans, the executable form of
specification §7.2) and the scale-oriented kernel (`--pipeline`, one fixed
4^8 = 65536-entry i64 table — 512 KiB, independent of replicon size — with a
single rolling counting pass per window; ambiguity resets the rolling code).
The runner executes each valid fixture twice with the optimized kernel and
once with the reference kernel and requires byte-identical JSONL; the k=1..8
fixture agrees on all 84 windows and the 4/4 regression on all 12.

Three native-backend constraints shape the implementation: `str_slice`
ignores its third argument (suffix only), `str_from_bytes` resolves only
local array handles, and local arrays declared inside hot functions allocate
from a compiler arena that is never reclaimed inside loops (observed:
~1M `kmer_transform` calls with a local `[i64; 8]` buffer exhaust the arena
and abort with exit 182). Bounded spans are built through a local copy
buffer, header tokens are compared byte by byte, and `kmer_transform` is
purely arithmetic (digit reversal without a local array).

Run the mini-pipeline and the independent byte-exact Julia check:

```bash
SOUNIO_REPO=/path/to/sounio \
SOUNIO_LIMA_INSTANCE=souc-linux \
make mini-pipeline-differential-fixture
```

Passing the mini-pipeline fixture establishes an executable end-to-end slice
at the predeclared pilot range k=1..8 over fixture-scale inputs only. It does
not establish null models, run receipts, NCBI cohort acquisition, or scale.

Run against an official pinned Sounio checkout:

```bash
SOUNIO_REPO=/path/to/sounio make sounio-fixture
```

On Apple Silicon, where the official checked Madaros is Linux x86-64, use the
existing Lima execution surface:

```bash
SOUNIO_REPO=/path/to/sounio \
SOUNIO_LIMA_INSTANCE=souc-linux \
make sounio-fixture
```

Run both FASTA implementations against persisted stdout:

```bash
SOUNIO_REPO=/path/to/sounio \
SOUNIO_LIMA_INSTANCE=souc-linux \
make fasta-differential-fixture
```
