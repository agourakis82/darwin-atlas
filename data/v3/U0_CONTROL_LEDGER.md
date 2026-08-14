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
sequence_report for replicon class. The binder refuses missing conventional
NCBI filenames, symlinks, output overwrite, incomplete categories, duplicates,
and package escape.

The separate scripts/validate_u0_control_ledger.py then rejects byte/hash drift,
cross-assembly paths, and assets that do not contain the declared accession. It
proves circular/linear from the GBFF record's LOCUS plus exact VERSION;
ambiguity for the exact FASTA record; and chromosome/plasmid from the exact
sequence-report row with its matching assembly. The binding receipt alone
never proves those claims.

On success the freeze binds the candidate file, generated ledger, binding
receipt, and semantic-validation receipt into freeze_receipt.json before the
source manifest is accepted. Synthetic fixtures may test software behavior but
cannot satisfy the public source-control evidence.

No real candidate set or fresh package is frozen yet. Consequently the
source-freeze gate remains blocked rather than silently reusing v2.1.2.
