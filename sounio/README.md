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
non-overlapping 4-base windows (stride 4, zero-based half-open coordinates, no
wraparound), scored with `delta_R`/`delta_RC` under the `canonical_only`
ambiguity policy, and emitted as deterministic JSONL. Windows containing
non-canonical IUPAC symbols are excluded with `AMBIGUOUS_WINDOW`; a trailing
short window is excluded with `PARTIAL_WINDOW`; excluded windows carry null
metrics. The frozen inputs live in `data/fixtures/mini_pipeline/` (two 16 bp
NCBI prefixes — not complete replicons — and two synthetic controls) with
SHA-256 checksums in `SHA256SUMS`; each JSONL line is specified by
`schemas/window_operator_profile.schema.json`.

Two native-backend constraints shape the implementation: `str_slice` ignores
its third argument (suffix only), and `str_from_bytes` resolves only local
array handles. Bounded spans are built through a local copy buffer, and header
tokens are compared byte by byte.

Run the mini-pipeline and the independent byte-exact Julia check:

```bash
SOUNIO_REPO=/path/to/sounio \
SOUNIO_LIMA_INSTANCE=souc-linux \
make mini-pipeline-differential-fixture
```

Passing the mini-pipeline fixture establishes an executable end-to-end slice
only. It does not establish k-mer composition, null models, run receipts, NCBI
cohort acquisition, or scale.

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
