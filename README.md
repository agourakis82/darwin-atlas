# Darwin Operator Symmetry Atlas (DOSA)

An operator-resolved, provenance-bound atlas of sequence symmetry in complete
bacterial RefSeq replicons.

> **Current state:** specification and implementation migration. This checkout
> does not yet produce a publication-ready atlas. Sounio kernels are partial;
> executable operator and streaming FASTA fixtures now pass independent Julia
> checks. Julia remains a validator, never the canonical producer.

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
implementation roles. The latest evidence-bounded local snapshot is
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

# Must fail unless both implementations are actually available
make cross-validate
```

`make pipeline` is intentionally fail-closed until the verified streaming reader
is connected to the operator kernels and a deterministic artifact writer. The
historical Julia-only pipeline is available only through the explicitly named
`make legacy-julia-pipeline` diagnostic target; its output is not release
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
