# DOSA v3 Data Descriptor — utility-first outline

**Manuscript state: blocked pending U0.** This outline is not a result claim.

## Resource statement

DOSA v3 is a reusable calibration resource: it returns exact bacterial-window
R/RC operator observations together with 1000-draw fixed-endpoint
dinucleotide-null summaries. The primary reuse claim is avoided recomputation,
measured as lookup speedup under a public accession/coordinate query.

## Background & Summary

- Define the recurring user task and the cost of on-demand exact shuffling.
- State the narrow R/RC operator panel and null model.
- Do not claim that reversal, reverse complement, k-mer symmetry, or exact
  dinucleotide shuffling is new.
- Report U0 operational results and one successful secondary application, if
  and only if their receipts pass.

## Methods

1. Fresh RefSeq `Complete Genome` source freeze and deterministic U0 selection.
2. Manifest-directed Sounio production by `replicon × scale`.
3. R9700 null-summary coprocessing, U250 hardware equivalence, and Sounio CPU
   fixture reference with explicit artifact boundaries.
4. Independent full Julia recomputation from persisted inputs and outputs.
5. Typed Parquet/Zstandard packaging with accession-SHA buckets and bounded
   shards; no scientific computation in DuckDB.
6. Receipt and remote-inventory closure.

## Data Records

- `runs.parquet`
- `replicons.parquet`
- `window_operator_profiles.parquet`
- `replicon_operator_summary.parquet`
- `excluded_records.parquet`
- frozen source manifest, parameters, schemas, data dictionary, payload
  manifest and validation receipts

Every filename, byte count and SHA-256 must be present in the public payload
manifest. Control files do not make false self-hash claims.

## Technical Validation

- byte-exact Sounio/Julia agreement for 100% of U0 and full-release rows;
- null replicate and tail-partition invariants;
- deterministic rerun and checkpoint/resume equivalence;
- query transfer/time and ≥100× lookup-speed measurements;
- source-sequence recovery and verification from outside the cluster;
- Parquet capacity projection from real U0 bytes with 2× margin;
- field-utility audit; and
- at least one preregistered secondary scientific PASS.

## Usage Notes

Document `dosa query`, `dosa calibrate`, and `dosa verify` from a clean public
download. State reason codes and the absence of p/q values. Provide one command
that verifies the deposit without private infrastructure.

## Kill rule

If both secondary scientific tests fail, stop before the full atlas. Publish
or retain the pilot as a negative benchmark and revise the scientific object.
No generic phrase such as “may reveal patterns”, “helps understand evolution”,
or “is useful for AI” is admissible without a named test, strong baseline and
measured result.

The Cayley–Dickson/RNA study is separate and cannot justify this dataset.
