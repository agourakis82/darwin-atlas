# ADR-0004: DOSA v3 U0 utility-first public contract and fail-closed gates

**Status:** Accepted as a contract; **U0: NOT YET PASSED**.

## Decision

U0 evaluates whether the complete DOSA v3 operator panel is sufficiently
useful and operationally reproducible to authorize the expensive next stages.
U0 is not a single RC k-mer fraction. Every eligible public window contains:

- exact positional `R` and `RC` observations;
- exact k-mer `R` observations for `k=2..8`;
- exact k-mer `RC` observations for `k=1..8`; and
- the null summary for every included observation.

The reverse k-mer `R` observation at `k=1` is omitted because it is identically
zero. Its omission is part of the contract, not missing data.

Each observation carries its effective count and an exact
numerator/denominator pair. The positional numerator is the applicable
position mismatch count for `R` or `RC`; the k-mer numerator is the applicable
imbalance count for that operator and k. The denominator is stored once in the
exact fraction. A decimal display is derived by consumers and is not canonical
analytic evidence.

The canonical parameter object is
[`data/v3/u0_parameters.json`](../data/v3/u0_parameters.json), validated by
[`schemas/dosa_v3_parameters.schema.json`](../schemas/dosa_v3_parameters.schema.json).
It fixes:

- windows 16, 100, 500, and 1000 bases;
- stride equal to window size for each profile;
- the operator panel above over `k=1..8`;
- `euler_wilson_fixed_endpoints_v1`; and
- exactly 1000 null replicates.

Each available null block records `n`, exact mean, MAD, q025, q500, q975, and
the integer `tail_lt`, `tail_eq`, `tail_gt` partition relative to the observed
metric. Unavailable observations or null blocks remain null with a reason code.
The analytic layer contains no p- or q-value fields.

## Public tables

The public payload uses exactly these primary filenames:

| Filename | Role |
| --- | --- |
| `runs.parquet` | One run-level provenance row; parameters, source closure, and producer binding are stored once. |
| `replicons.parquet` | One metadata row per replicon, joined through `replicon_id`. |
| `window_operator_profiles.parquet` | Exact positional and k-mer operator observations and null summaries by window. |
| `replicon_operator_summary.parquet` | Replicon-level roll-ups by window size, operator, and k where applicable. |
| `excluded_records.parquet` | Explicit excluded intervals/records and reason codes. |

`dosa_v3_payload_manifest.schema.json` requires and hash-closes all five as
logical tables. `window_operator_profiles.parquet` is represented as a
partitioned logical table: its top-level manifest entry names the bound v3 CLI
package manifests, and each package manifest closes the physical
`scale=<n>/sha256_bucket=<xx>/part-*.parquet` shards. The U0 gate binds the
top-level public manifest; an operational lookup binds its physical package
manifest and refuses unless that exact package hash is referenced by the
partitioned window-table entry. Source and payload manifests and gate receipts
are supporting artifacts, not extra analytic tables.

The source manifest is externally recoverable: it embeds the fresh query
object and binds its file hash, pins the datasets/dataformat versions and
binary hashes, records versioned assembly and sequence accessions, and closes
the NCBI package catalog/checksum manifest plus every selected FASTA, GBFF, and
sequence-report asset. Only portable package-relative paths are admitted; a
private absolute workstation path is invalid provenance.

## Public-layer reduction

| Removed field/category | Why it is absent | Re-admission criterion |
| --- | --- | --- |
| reverse k-mer `R`, k=1 | Identically zero; it adds no observation and creates a false impression of a tested utility. | Only if the operator definition changes under a new version and is no longer identically zero. |
| `fixed_R`, `fixed_RC` | Descriptive flags, not an independently required U0 measure. | A new ADR demonstrates a decision that depends on the flag and supplies independent validation. |
| repeated denominators or rounded ratios | The exact fraction already has one denominator; duplicates can disagree. | Demonstrate a non-reconstructible quantity and add a cross-field invariant. |
| repeated accession/class/topology metadata | These belong once in `replicons.parquet`. | Demonstrate a valid window-only use that cannot join by `replicon_id`. |
| repeated source-manifest hashes per window | The public payload manifest and the source-index/package closure bind source provenance once; window rows join by `replicon_id`/accession routing. | Demonstrate a source identity that cannot be recovered through the top-level and package bindings. |
| legacy orbit/minimal-period fields | Historical analytic layer, outside the U0 operator panel. | Define a new utility, schema version, and fail-closed receipts. |
| p/q fields | U0 exposes effect/null distributions without admitting an undeclared inferential family. | A reviewed inference ADR fixes hypotheses, units, multiplicity correction, and validation. |

## U0 pass rule

U0 passes only when the public payload declares
`release_state=u0_pilot_evidence`, every operational report has real
`u0_pilot` scope, and both conditions hold:

1. all six mandatory operational requirements are `PASSED` and bound to
   receipts: full Sounio/Julia agreement, query transfer/time ceiling, lookup
   speedup, external source/hash verification, Parquet capacity projection,
   and the public-field utility audit;
2. at least one of the two declared scientific secondary tests is `PASSED` and
   bound to a receipt: the OriC/terminus gate or the RC-equivariance benchmark.

Passing neither scientific secondary test blocks U0 even when all operations
pass. Passing one scientific test does not waive any operational requirement.
Fixture or mixed-scope evidence cannot pass U0. Merely changing a fixture's
scope label and recomputing its local hashes also cannot pass: the regression
test `U0_GATE_SCOPE_RELABEL_EXPLOIT_REJECTED_PASS` freezes this refusal. The
receipt schema encodes the conjunction and the exact requirement identifiers.

The present implementation has a second, explicit promotion lock. A
real-scope invocation stops with `U0_PROMOTION_LOCKED` before evidence
adjudication while the canonical multiscale Sounio executor, integral Julia
validator, and six frozen held-out derivation roles are absent. Independently,
the two Julia secondary evaluators refuse `held_out_grouped_cohort` inputs
until that derivation contract is implemented. This is intentional: fixture
mathematics may be tested now, but no scope label can create scientific
evidence.

The executable U0 aggregator does not accept threshold-shaped JSON alone. It
requires an immutable evidence root and a provenance manifest that closes
exactly the required 29 artifact roles by normalized relative path, byte size,
and SHA-256. Every supplied artifact must be the exact regular, non-symlink
file below that root; missing roles, extra roles, path escape, symlinks, size
drift, or hash drift fail closed.

The closure includes the versioned operational/scientific reports and inputs;
parameters; full source manifest, source-integrity receipt and portable source
index; deterministic selection, discovery reports, control/freeze evidence and
full-replicon inventory; the exact work-unit manifest; payload manifest;
Sounio build attestation/build receipt and real execution/output receipts; and
the independent full Julia validation receipt. The selector is rerun from the
frozen discovery reports, control claims are revalidated from their package
bytes, and the work-unit set must equal every selected accession crossed with
all four scales. The gate opens every logical Sounio output, validates each
JSONL row against the public schema and cross-field invariants, and proves
exact window-index coverage. It then opens every package manifest and
Zstandard Parquet shard, reruns the capacity projection, and binds each logical
Sounio output to exactly one package. Reports that contain the payload hash are
closed by the top-level provenance/final receipt rather than embedded back
into that payload, avoiding a cryptographic self-reference. Query evidence is
also bound through raw/canonical/normalized sequence hashes. Removal of the
promotion lock will additionally require held-out reports to bind the frozen
derivation closure and rerun both Julia evaluators with a pinned runtime.

The Sounio build attestation binds the official repository commit, producer
source, compiler, and executable bytes, but remains explicitly non-semantic.
Semantic evidence comes from the separately hash-bound real Sounio
execution/output artifacts plus independent full Julia recomputation and their
agreement receipt. The provenance manifest states
`authenticity_boundary=integrity_closure_not_external_authentication`: this
local closure detects substitution or drift after binding, but is not external
identity authentication. Public recovery and remote inventory receipts remain
separate requirements.

## Stage and release gates

**U0 is NOT YET PASSED.** Therefore:

- full-atlas execution is `BLOCKED_UNTIL_U0`;
- HDD purchase is `BLOCKED_UNTIL_U0`; and
- data release is `BLOCKED`.

The current manifest-directed fixture proves parsing, ordering, resume and
explicit refusal behavior. The separate multiscale capacity fixture binds the
canonical parameter bytes and proves 1000 exact Euler/Wilson draws at each of
16, 100, 500 and 1000 bp against an independent Julia oracle. Neither fixture
is the manifest-directed U0 executor: they do not emit the v3 window schema,
null summaries, Parquet, work-unit receipts or pilot agreement. The current
CLI verifier proves package/hash/footer integrity, not full v3 row semantics.
Parts of the real provenance validator are scaffolded, but the admission
profile is deliberately locked and has not been exercised end to end: no
actual U0 Sounio executor/output manifest, execution receipt, full-pilot Julia
recomputation receipt, or frozen scientific derivation closure exists. Known
deeper source/package/report/runtime closures must also be completed before
the lock can be removed. These are blockers, not deferred claims.

After U0, full-atlas execution and an HDD purchase may become permitted work.
An HDD purchase is never a scientific result, U0 criterion, or data-release
prerequisite.

A DOSA v3 data release requires U0 plus four full-scope passing receipts:
Sounio producer, independent Julia recomputation, payload/hash closure, and
external-use demonstration. The full producer/Julia receipts—not a hardware
purchase—establish the full-scope computation. Missing or mismatching receipts
fail closed.

## v2 preservation boundary

No v2 schema, fixture, script, receipt, release bundle, or documentation is
rewritten. `window_operator_profile.schema.json` and existing fixture artifacts
retain their historical columns and rounded/additive layout as engineering
regression evidence. They are not silently converted into v3 Parquet tables,
do not establish U0, and cannot substitute for v3 receipts.

## Consequences

- The public layer preserves the whole declared R/RC operator panel while
  removing fields without a demonstrated public use.
- Exact fractions, effective counts, null quantiles, tail partitions, and
  reason codes remain independently auditable.
- Full-atlas/HDD expenditure waits for U0 evidence, while release remains tied
  to scientific and reproducibility receipts rather than hardware ownership.
