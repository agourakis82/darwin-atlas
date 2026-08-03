# Darwin Operator Symmetry Atlas (DOSA)

An operator-resolved, provenance-bound atlas of sequence symmetry in complete
bacterial RefSeq replicons.

> **Current state:** specification and implementation migration. This checkout
> does not yet produce a publication-ready atlas. Sounio kernels are partial;
> executable operator, streaming FASTA, and parameterized frozen mini-pipeline
> fixtures (positional metrics plus masked k-mer composition for the
> predeclared pilot range k=1..8, under two byte-equivalent kernels) now pass
> independent Julia checks. A frozen miniature cohort of four complete
> circular RefSeq replicons (two assemblies, official NCBI checksum closure)
> is pinned in [`data/cohort/mini/`](data/cohort/mini/README.md); engineering
> canonical products (cohort/replicons/exclusions for all four replicons,
> window products for both plasmids) are emitted by Sounio and reproduced
> byte-exact by independent Julia. Julia remains a validator, never the
> canonical producer.

## Scientific scope

DOSA separates four concepts that must not be collapsed into one score:

- positional reversal and reverse-complement similarity;
- reverse-complement symmetry of k-mer composition;
- sequence periodicity;
- representation equivalence under origin/strand changes for circular dsDNA.

The project does not claim to be the first database of palindromes or inverted
repeats. The novelty target is the operator-resolved dataset, its explicitly
controlled null models, and evidence bound to the producing compiler and
artifacts.

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

# Run Julia validator-development tests (not a production run)
make test-julia

# Check, compile, and execute with an official pinned Sounio checkout
SOUNIO_REPO=/path/to/sounio make sounio-fixture

# Apple Silicon: execute the official Linux x86-64 Madaros in Lima
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux make sounio-fixture

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
# cases (mononucleotide-preserving shuffle null summaries, an executable
# specification; the ADR-0002 pilot null remains proposed), and recompute it
# byte-exact in Julia
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

# Must fail unless both implementations are actually available
make cross-validate
```

`make pipeline` is intentionally fail-closed until the canonical cohort
pipeline (run receipts, k-mer/null-model metrics, release artifacts) exists;
the mini-pipeline fixture is an executable specification, not that pipeline.
The historical Julia-only pipeline is available only through the explicitly
named `make legacy-julia-pipeline` diagnostic target; its output is not release
eligible.

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
