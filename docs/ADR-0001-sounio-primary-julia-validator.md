# ADR-0001: Sounio is the canonical producer; Julia is the validator

- **Status:** accepted
- **Date:** 2026-07-30
- **Decision owners:** Darwin Atlas project
- **Specification:** `docs/SCIENTIFIC_SPEC.md` 0.1.0

## Context

The initial repository made Julia responsible for acquisition, orchestration,
scientific computation, table generation, and fallback validation, while
Sounio/Demetrios kernels were optional. That design cannot demonstrate that the
published dataset was produced by Sounio. It can also return success when no
cross-language comparison occurred.

The existing FFI path couples Julia validation to the producer binary. A
publication-grade validator should instead recompute results from the immutable
inputs and compare persisted artifacts.

## Decision

1. Sounio is the only canonical producer of scientific observations.
2. Julia is an independent, read-only validator of persisted Sounio artifacts.
3. Input acquisition uses the official NCBI Datasets CLI plus checksum
   verification. Acquisition is not scientific computation.
4. Production and cross-validation commands fail closed when their required
   implementation is absent.
5. The publication gate compares file artifacts; FFI may remain only as a
   development diagnostic and cannot satisfy the independent-validation gate.
6. The current `demetrios/` path is a legacy migration location for `.sio`
   experiments. It will be renamed only when a real Sounio entry point and
   streaming I/O substrate replace the placeholder kernels.

## Consequences

- Existing Julia-only pipeline output is diagnostic and cannot be released as a
  canonical atlas product.
- Sounio must gain streaming/multi-record FASTA input, ambiguity preservation,
  stable tabular output, and run receipts before the pilot.
- Julia must gain artifact readers and deterministic stratified recomputation.
- A missing Sounio executable blocks production; a missing Julia environment
  blocks publication validation.
- Build success, execution success, and scientific validation are reported as
  separate states.

## Alternatives rejected

- **Julia producer with optional Sounio acceleration:** does not meet the project
  objective that Sounio produce the scientific dataset.
- **Julia fallback when Sounio is missing:** creates false-positive validation.
- **FFI-only comparison:** shares runtime state and does not validate the public
  artifact boundary independently.

