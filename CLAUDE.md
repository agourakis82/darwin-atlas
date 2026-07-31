# CLAUDE.md — Darwin Operator Symmetry Atlas

## Read first

The normative scientific contract is `docs/SCIENTIFIC_SPEC.md`. Architecture
decision `docs/ADR-0001-sounio-primary-julia-validator.md` is binding. If code,
older reports, or this file disagree with the specification, the specification
wins.

## Project identity

- Name: Darwin Operator Symmetry Atlas (DOSA)
- Stage: 0.1 specification and producer migration
- Target: Scientific Data Data Descriptor plus DOI-versioned artifacts
- Canonical producer: Sounio
- Independent validator: Julia

## Non-negotiable boundaries

1. Sounio is the only producer of release-candidate scientific observations.
2. Julia reads immutable inputs and persisted Sounio outputs and recomputes a
   deterministic validation sample. It is never a production fallback.
3. A missing Sounio compiler/executable fails production. A missing Julia
   validator blocks publication validation.
4. Cross-language validation at the release gate occurs through file artifacts,
   not shared FFI code.
5. `COMPILES`, `EXECUTES`, and `SCIENTIFICALLY_VALIDATED` are distinct states.
6. Successful compilation of placeholder kernels is not evidence that their
   algorithms are correct.
7. Every release receipt binds the exact compiler and executable SHA256, atlas
   and Sounio commits, input manifest, parameters, commands, outputs, and Julia
   report. A changed bound hash invalidates dependent evidence.
8. Preserve IUPAC ambiguity. Never encode an unknown base as canonical `A`.
9. Keep `julia/Manifest.toml` committed and never delete it in reproduction.
10. Do not claim first-database novelty for palindromes or inverted repeats.

## Mathematical rules

- `{I,R,K,RC}` is `V4`.
- `<S,R>` and `<S,RC>` are distinct `D_n` actions of order `2n`.
- `<S,R,K>` is `D_n x C2` of order `4n`.
- Local windows are linear and do not wrap.
- Whole-replicon rotation/RC canonicalization is allowed only when circularity
  is declared by the source metadata.
- Direct complement Hamming distance is uninformative for canonical DNA.
- Quaternion/dicyclic analysis is supplementary unless a reviewed biological
  hypothesis is added to the specification.

## Current repository boundary

- `demetrios/src/*.sio` is a legacy migration location. Some central kernels are
  placeholders; do not describe the directory as a completed Sounio engine.
- `julia/` contains the historical reference/pipeline code. Treat it as
  validator-development code while it is being separated from acquisition and
  production.
- `SOUNIO_CAPABILITIES_REPORT.md` and `ADAPTATION_REPORT.md` are historical
  compilation reports, not current execution or scientific receipts.
- `schemas/run_receipt.schema.json` is the first machine-readable release
  contract.
- `toolchains/sounio.lock.json` pins an observed commit from the official
  `sounio-lang/sounio` repository. Never substitute a local fork or stale global
  compiler for an evidence run.
- The upstream `examples/real_world/06_darwin_atlas_pipeline.sio` file is a
  bounded synthetic demo, not the canonical DOSA implementation or receipt.
- `sounio/` is the canonical producer surface. The first executable fixture is
  `sounio/src/operator_fixture.sio`; `sounio/src/fasta_stream_fixture.sio`
  establishes chunked multi-record IUPAC parsing and stable parse errors.

## Work sequence

1. Integrate the verified Sounio FASTA reader with ambiguity-safe sequence
   storage, operator kernels, and deterministic JSONL/CSV output.
2. Extend the normative Sounio operators from positional metrics to k-mers.
3. Add executable golden and metamorphic fixtures.
4. Produce a frozen miniature NCBI artifact bundle and Sounio receipt.
5. Refactor Julia into an artifact-level validator and compare the fixture.
6. Run a 20–50 assembly pilot, then the frozen reference cohort.

Do not move to a later step by replacing missing evidence with a fallback.

## Commands

```bash
make status                  # evidence/toolchain status only
make contract                # specification/schema checks
make test-julia              # validator-development tests
SOUNIO_REPO=/path/to/official/sounio make sounio-fixture
SOUNIO_REPO=/path/to/official/sounio make fasta-differential-fixture
make cross-validate          # fail-closed comparison diagnostic
make release-gate            # publication gate; expected red until implemented
```

`make legacy-julia-pipeline` exists only to inspect the old pipeline. Its
artifacts MUST be labelled noncanonical and are not release eligible.

## Coding and review

- Prefer explicit domain types and reason-coded failures.
- Avoid hidden global state and unlogged random seeds.
- Sort persisted records by stable identifiers before hashing.
- Use exact integer arithmetic for counts and declare float tolerances by metric.
- Add a minimal fixture and metamorphic test with every operator change.
- Stop on divergence; retain the inputs and both outputs needed to reproduce it.
- Preserve unrelated user changes and inspect the worktree before edits.

## Publication gate

All gates G0–G6 in `docs/SCIENTIFIC_SPEC.md` must be green. In particular,
generated data without a passing Julia report is `generated_unvalidated`, not
validated. A manuscript or release must not promote observed status into a
claim beyond the receipt.

Last updated: 2026-07-30
