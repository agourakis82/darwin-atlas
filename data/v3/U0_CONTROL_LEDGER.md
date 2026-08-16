# U0 control candidate and ledger binding

The source-freeze command takes a tab-separated candidate file with exactly
these ordered columns:

    sequence_accession_version	assembly_accession_version	control_category

The required categories are topology_circular, topology_linear,
ambiguity_present, ambiguity_absent, replicon_chromosome, and
replicon_plasmid. A sequence may satisfy several categories.

Candidates are inclusion requests only. They contain no file path, hash, or
semantic proof because those bytes do not exist before the selected NCBI
package is downloaded. After rehydration, scripts/bind_u0_control_ledger.py
deterministically resolves the exact assembly GBFF, genomic FASTA, or sequence
report, hashes the bytes, and writes the six-column control_ledger.tsv plus an
explicitly bound_unvalidated receipt:

    sequence_accession_version	assembly_accession_version	control_category	asset_kind	package_path	evidence_sha256

Asset kinds are fixed: gbff for topology, fasta for ambiguity, and
sequence_report for replicon class. Within the exact assembly directory the
binder requires exactly one `genomic.gbff` or `*_genomic.gbff`, exactly one
`genomic.fna` or `*_genomic.fna`, and the exact `sequence_report.jsonl`. This
matches NCBI Datasets 18.35.0 package names without choosing the first result
of a recursive search. The binder refuses missing or ambiguous assets,
symlinks, output overwrite, incomplete categories, duplicates, and package
escape.

The separate scripts/validate_u0_control_ledger.py then rejects byte/hash drift,
cross-assembly paths, and assets that do not contain the declared accession. It
proves circular/linear from the GBFF record's LOCUS plus exact VERSION;
ambiguity for the exact FASTA record; and chromosome/plasmid from the exact
sequence-report row with its matching assembly. The binding receipt alone
never proves those claims.

Before a full freeze, `python3 scripts/review_u0_control_candidates.py create`
may run
the same binder and semantic validator against a bounded, already-downloaded
mini-package. Its receipt scope is
`bounded_control_candidate_review_non_scientific`: the six control claims are
semantically qualified from exact package bytes, but no DOSA metric is
computed and the receipt is not a RefSeq freeze, pilot run or scientific
result. The `verify` subcommand reopens every bound file from an already-issued
review receipt and rejects path escape, symlink or byte drift.

On success the freeze binds the candidate file, generated ledger, binding
receipt, and semantic-validation receipt into freeze_receipt.json before the
source manifest is accepted. Synthetic fixtures may test software behavior but
cannot satisfy the public source-control evidence.

`data/v3/u0_control_candidates.tsv` is the current real inclusion request. On
2026-08-15 a bounded fresh NCBI Datasets 18.35.0 package semantically validated
all six claims (review receipt SHA-256
`ff55b413d399315f33e10f76e15cb0badf45cd86e9ec19e105a1534560b80c6d`).
That review computed no DOSA metric and is not release evidence. The main
source freeze must download and validate the selected package again, so the
source-freeze gate remains pending rather than silently reusing v2.1.2 or the
bounded review cache.
