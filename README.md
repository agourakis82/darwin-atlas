# Darwin Operator Symmetry Atlas (DOSA)

An operator-resolved calibration resource for reversal and
reverse-complement signals in complete bacterial RefSeq replicons.

The v3 practical objective is precise and testable: given an
`accession.version`, coordinate and scale, return the exact R/RC observation
and its precomputed `n=1000` fixed-endpoint dinucleotide-null distribution so a
researcher does not need to rerun 1000 shuffles.

> **Current state:** DOSA v3 recovery and Gate U0 implementation. **U0 has not
> passed.** This checkout
> does not yet produce a publication-ready atlas. Sounio kernels are partial;
> executable operator, streaming FASTA, and parameterized frozen mini-pipeline
> fixtures (positional metrics plus masked k-mer composition for the
> predeclared pilot range k=1..8, under two byte-equivalent kernels) now pass
> independent Julia checks. The ADR-0003 exact dinucleotide-preserving
> engineering null is integrated additively into the frozen window fixture
> with SHA-derived per-window seeds and eight replicates; ADR-0002 remains
> proposed. A separate synthetic scale fixture now executes exactly 1000
> Euler/Wilson draws at each of 16, 100, 500 and 1000 bp in pinned Sounio. It
> emits both the 4000 raw draws and four complete nested v3 window-profile
> rows containing all 17 published observed/null metric blocks; independent
> Julia reconstructs both artifacts byte-exact. This proves the bounded
> null-draw and analytical-row core at the four U0 scales; it is not the
> manifest-directed U0 producer, a pilot payload, or a receipt. A separate
> bounded work-unit composition fixture now selects two explicit manifest rows
> and binds two exact 48 bp FASTAs to six prescribed SHA-derived seeds. Sounio
> produces six complete profiles and Julia independently reconstructs them
> from the original manifest/FASTA bytes. A resume shard beginning at window 1
> is the byte-exact two-row suffix of the first full output. A deterministic
> pre-execution planner closes four bounded case shards by hash while declaring
> that no Sounio execution or scientific metric has occurred. This is still
> synthetic and does not satisfy exclusion handling, chromosome streaming,
> pilot-wide execution or receipt coverage. A frozen
> miniature cohort of four complete
> circular RefSeq replicons (two assemblies, official NCBI checksum closure)
> is pinned in [`data/cohort/mini/`](data/cohort/mini/README.md); engineering
> canonical products (cohort/replicons/exclusions for all four replicons,
> window products for both plasmids) are emitted by Sounio and reproduced
> byte-exact by independent Julia. Julia remains a validator, never the
> canonical producer. Full-atlas execution, a v3 tag/deposit, and HDD purchase
> remain blocked until all operational U0 requirements and at least one
> secondary scientific test pass with real receipts. The real gate profile is
> fail-closed, explicitly promotion-locked, and still unexercised: it requires payload
> `release_state=u0_pilot_evidence`, a single exact evidence-root/provenance
> closure, persisted Sounio execution/output artifacts plus independent full
> Julia semantic recomputation/agreement, and bound source and scientific
> inputs. The actual U0 executor, integral Julia validator, held-out
> derivation contract and full receipts do not yet exist.

## DOSA v3 utility surface

The public interface is intentionally small:

- `dosa query` locates a calibrated window in typed Parquet shards;
- `dosa calibrate` delegates a new sequence only to an explicitly configured,
  hash-bound Sounio runner; its build attestation is provenance, not by itself
  proof that the scientific result is correct; and
- `dosa verify` checks package inventory, byte sizes, SHA-256 values, binding
  presence and Parquet footer/row/compression integrity without private
  cluster access.

At the current `U0-dev` boundary, `dosa verify` does **not** claim to validate
every scientific row against the v3 JSON Schemas or replace the independent
Julia recomputation receipt. Those are separate mandatory U0/release gates.
The Sounio build attestation likewise binds build identity only; it is not
semantic evidence. Local provenance hashes establish integrity of the closed
artifact set, not external authentication of its author or origin.

DuckDB/Parquet performs projection, joins and packaging only. It never
computes a DOSA scientific metric. The complete U0 contract, data reduction
and kill rule are in
[`ADR-0004`](docs/ADR-0004-v3-u0-utility-first-fail-closed-gates.md); the
field-level public contract is in
[`DOSA_V3_PUBLIC_DATA_DICTIONARY.md`](docs/DOSA_V3_PUBLIC_DATA_DICTIONARY.md).

## Scientific scope

DOSA separates four concepts that must not be collapsed into one score:

- positional reversal and reverse-complement similarity;
- reverse-complement symmetry of k-mer composition;
- sequence periodicity;
- representation equivalence under origin/strand changes for circular dsDNA.

The project does not claim to be the first study of reverse-complement
symmetry, the first windowed/operator comparison, or the inventor of exact
dinucleotide shuffling. The falsifiable novelty target is narrower: test
whether a joint, representation-aware decomposition of positional and
compositional operators retains reproducible biological structure after exact
dinucleotide-null calibration. The multiterabyte atlas is authorized only if
U0 proves the operational utility and at least one of the preregistered
OriC/terminus or model-violation tests. If both fail, the pilot is preserved as
a negative benchmark and the full atlas is not generated. The prior-art boundary,
rejected claims, kill criteria and evidence gates are frozen in
[`docs/NOVELTY_AUDIT.md`](docs/NOVELTY_AUDIT.md); no scientific novelty is
currently established.

The normative definitions, hypotheses, schemas, and release gates are in
[`docs/SCIENTIFIC_SPEC.md`](docs/SCIENTIFIC_SPEC.md). Architecture decision
[`ADR-0001`](docs/ADR-0001-sounio-primary-julia-validator.md) defines the
implementation roles; [`ADR-0002`](docs/ADR-0002-pilot-parameter-decisions.md)
(proposed) records the pilot parameter decisions ahead of cohort acquisition;
[`ADR-0003`](docs/ADR-0003-dinucleotide-null-engineering-contract.md) fixes the
exact Euler/Wilson engineering-fixture semantics without accepting the pilot.
The latest evidence-bounded local snapshot is
[`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md).

## Architecture

```text
NCBI Datasets CLI + checksums
              |
              v
immutable accession.version manifest
              |
              v
Sounio canonical producer --------> data artifacts + run receipt
              |                                  |
              +----------------------------------+
                                                 v
                                  independent Julia validator
                                                 |
                                                 v
                                  comparison/publication gate
```

- **Sounio is required for production.** No other implementation may silently
  substitute for it.
- **Julia validates persisted artifacts independently.** It is not a production
  fallback.
- **A missing validator is not a pass.** Sounio can generate development output,
  but release remains blocked until Julia validation succeeds.
- **File artifacts are the scientific boundary.** FFI comparisons are allowed
  only as development diagnostics.

## Evidence states

The repository reports these states separately:

1. `COMPILES`: Sounio accepted a source file.
2. `EXECUTES`: a hashed executable ran successfully on a named fixture.
3. `SCIENTIFICALLY_VALIDATED`: schemas, provenance, metamorphic properties, and
   independent Julia recomputation all passed.

Older capability reports document compilation experiments only. They are not
receipts for a completed atlas pipeline.

## Repository map

```text
docs/                         normative specification and decisions
schemas/                      machine-readable release contracts
demetrios/src/*.sio           legacy migration location for Sounio experiments
sounio/                       canonical Sounio producer implementation
julia/                        independent validator under migration
data/                         local inputs and generated artifacts
.github/workflows/ci.yml      contract and validator-development checks
```

The legacy `demetrios/` directory remains migration evidence. Removing or
renaming it waits until the canonical `sounio/` surface contains the integrated
FASTA-to-artifact pipeline and stable output writer.

## Development commands

```bash
# Show current toolchain and implementation status
make status

# Validate the normative documentation and JSON contracts
make contract

# Validate the v3 U0 contracts and synthetic fail-closed gates. This cannot
# promote U0 to PASS; the real path also remains explicitly promotion-locked.
make u0-contract

# Once a real six-category candidate file is reviewed, download the fresh
# selected package, bind exact asset hashes, and prove every control claim.
# The command requires a clean tree and pinned NCBI binaries.
DOSA_DATASETS_BIN=/path/to/pinned/datasets \
DOSA_DATAFORMAT_BIN=/path/to/pinned/dataformat \
  scripts/freeze_u0_refseq_snapshot.sh \
  /path/to/new-snapshot /path/to/control_candidates.tsv

# Package/query/verify a logical Sounio artifact once DuckDB is installed.
# Missing DuckDB is an explicit dependency error, never a fallback format.
cli/bin/dosa --help

# The capacity measurement opens real Parquet footers and requires the exact
# pinned DuckDB version; a text file renamed .parquet is rejected.
make u0-cli-integration

# Run Julia validator-development tests (not a production run)
make test-julia

# Check, compile, and execute with an official pinned Sounio checkout
SOUNIO_REPO=/path/to/sounio make sounio-fixture

# Apple Silicon: execute the official Linux x86-64 Madaros in Lima
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux make sounio-fixture

# Bounded U0 scale probe: four synthetic windows at 16/100/500/1000 bp,
# exactly 1000 fixed-endpoint Euler/Wilson draws each. Pinned Sounio emits the
# 4000-draw JSONL plus four complete v3 profile rows; independent Base-only
# Julia regenerates every shuffle, metric, summary and complete row byte-exact.
# The same runner exercises a three-window manifest/FASTA shard and proves
# that a two-window resumed run is the exact byte suffix of the full output.
# This is engineering fixture evidence only and cannot unlock Gate U0.
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  make u0-dinucleotide-scale-fixture

# Compile/execute in Sounio, persist stdout, then recompute in Base-only Julia
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  make operator-differential-fixture

# Stream multi-record FASTA in Sounio and recompute records/errors in Julia
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  make fasta-differential-fixture

# Run the frozen mini-pipeline (versioned parameter JSON -> strict flat
# validation -> FASTA + metadata -> windows -> delta_R/delta_RC -> masked
# k-mer imbalance k=1..8 -> exclusions -> deterministic JSONL 0.3.0), with
# byte-equivalent optimized and reference kernels, the fixture null-model
# cases (mononucleotide-preserving and exact dinucleotide-preserving shuffle
# summaries, both executable engineering specifications; the ADR-0002 pilot
# null remains proposed), and recompute them byte-exact in Julia
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  make mini-pipeline-differential-fixture

# Complete-replicon engineering smoke: run the optimized kernel on plasmid
# NC_002127.1 (207 windows) from the frozen mini cohort twice for
# determinism and recompute it byte-exact in Julia (not the pilot, not a
# release receipt)
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  make cohort-smoke-differential

# Engineering canonical products (Fase E): cohort_assemblies (all assemblies),
# atlas_replicons + excluded_records (all four replicons), and window products
# for both plasmids, each recomputed byte-exact in independent Base-only
# Julia (engineering scope; chromosome windows deferred to the benchmark).
# The same runner also applies the deterministic stratified Julia sample of
# spec 12.2 to each plasmid window product (Fase F): a fixed stratum
# definition seeded from the persisted parameter hash selects windows whose
# recomputation must match byte-exact
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  make cohort-products

# Two-stage engineering run receipt (Fase H): rerun the products pipeline from
# a clean tree, emit a stage-1 receipt (generated_unvalidated, no validator),
# run the full Julia validation suite, and close a stage-2 validated receipt
# under receipts/<run_id>/ (fails closed with exit 2 on a dirty tree; the two
# large window products stay hash-bound in the receipt, not committed)
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  scripts/emit_products_receipt.sh

# Chromosome-scale benchmark (Fase I): run the optimized kernel on both
# frozen-cohort chromosomes (290,104 + 343,662 windows) with wall-clock and
# peak-RSS measurement, structural checks, and deterministic stratified Julia
# sample validation; writes a small benchmark receipt under
# receipts/chromosome-benchmark-<commit>-<utc>/ (window products hash-bound,
# not committed; engineering scope, not the pilot)
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  scripts/run_chromosome_benchmark.sh

# Engineering release bundle (Fase J): from a clean tree, archive the commit,
# bind the battery evidence (must end with BATTERY_ALL_GREEN), the validated
# products receipt, and the benchmark receipt into release/<bundle_id>/ with
# a release receipt (DOI is an explicit placeholder; engineering scope)
scripts/build_release_bundle.sh <battery_log> <products_receipt_run_id>

# Fase L CPU differential: pinned Sounio produces 64 exact
# dinucleotide-preserving sequence draws; Julia independently recomputes the
# SHA-derived seeds, every byte, endpoints, and all 16 dinucleotide counts.
SOUNIO_REPO=/path/to/pinned/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  scripts/run_dinucleotide_null_differential.sh

# Regenerate the Julia golden header and compare all 1,024 base slots against
# the HLS kernel in C simulation. Real-card closure additionally requires the
# build, host, and hardware scripts documented under fpga/u250-dinucleotide-null.
make u250-dinucleotide-contract

# The validated engineering-fixture hardware receipt is hash-closed under
# receipts/dinucleotide-null-556ac81-20260803T171300Z/. It records the real
# U250 execution, official pinned-Sounio differential, and the two inherited
# shell/DFX critical warnings; it does not promote the ADR-0002 pilot null.

# Fase M0-M2 window integration: the same mini-pipeline command now exercises
# parameters_dinucleotide_{k4,k8}.json plus frozen per-window seed sidecars.
# Sounio remains the sole producer; Julia independently regenerates every
# Euler/Wilson draw and every 183-field JSONL line at tolerance zero. This is
# fixture-scope engineering evidence, not pilot selection, biology, or a
# performance claim.

# Must fail unless both implementations are actually available
make cross-validate
```

`make pipeline` is intentionally fail-closed until the canonical cohort
pipeline (run receipts, k-mer/null-model metrics, release artifacts) exists;
the mini-pipeline fixture is an executable specification, not that pipeline.
The historical Julia-only pipeline is available only through the explicitly
named `make legacy-julia-pipeline` diagnostic target; its output is not release
eligible.

For v3, `make u0-gate` is separately fail-closed until all real pilot paths are
provided beneath `U0_EVIDENCE_ROOT`: the agreement, query, speed, capacity,
field-audit and scientific reports; their OriC/model inputs; parameters; source
manifest, integrity receipt and source index; payload manifest; frozen
selection/discovery/control/full-inventory evidence; the exact work-unit
manifest; Sounio build attestation/build receipt plus execution receipt/output
manifest; the full Julia semantic recomputation receipt; the Julia executable;
and `U0_PILOT_PROVENANCE`, whose current scaffold closes 29 file roles by
relative path, size and SHA-256. Fixture evidence exercises the evaluator
but is structurally unable to authorize the full atlas or an HDD purchase. A
regression test rejects fixture reports whose scope labels and hashes are
rewritten to resemble a pilot. An explicit `U0_PROMOTION_LOCKED` check runs
before real evidence adjudication; the Julia scientific evaluators separately
refuse held-out scope. The lock is not removable until the actual n=1000
multiscale executor, integral Sounio/Julia receipts, held-out derivation roles,
and the remaining source/package/report/runtime closures exist.

Because the official Sounio repository moves rapidly, fixture runners accept
only the clean commit pinned in `toolchains/sounio.lock.json`. Refresh that pin
deliberately before a new evidence run; a moving branch name is never part of a
scientific receipt.

## Planned data products

- `cohort_assemblies`: immutable acquisition cohort and checksums;
- `atlas_replicons`: replicon metadata, topology, ambiguity, and inclusion;
- `window_operator_profiles`: positional and compositional operator metrics;
- `replicon_operator_summary`: periodicity and whole-replicon summaries;
- `excluded_records`: complete reason-coded exclusions;
- `run_receipt.json`: compiler, source, input, parameter, command, artifact, and
  validator bindings.

The run receipt schema is
[`schemas/run_receipt.schema.json`](schemas/run_receipt.schema.json).

## Reproducibility rules

- Freeze every NCBI accession with its version and package checksum.
- Preserve IUPAC ambiguity; never coerce `N` to `A`.
- Keep `julia/Manifest.toml` committed.
- Record the Sounio compiler path, version, and SHA256 together with the
  produced executable SHA256.
- Invalidate downstream evidence whenever a bound hash changes.
- Require exact agreement for discrete fields and predeclared tolerances for
  floating-point fields.

## Licensing and citation

- Code: MIT
- Released data: CC BY 4.0
- Citation metadata: [`CITATION.cff`](CITATION.cff)

Release and DOI placeholders are intentionally not presented as completed
publication identifiers.
