# Mini-pipeline fixtures (frozen)

These files are the frozen inputs of the Sounio mini-pipeline executable
specification: streaming FASTA + metadata TSV association + non-overlapping
positional windows + `delta_R`/`delta_RC` + explicit exclusions + deterministic
JSONL. They are inputs to an executable specification, not a release cohort.

## Records in `pipeline_fixture.fa`

1. `NC_000913.3` — **NCBI prefix, positions 1–16 only** (`AGCTTTTCATTCTGAC`),
   *Escherichia coli* str. K-12 substr. MG1655 chromosome. This is a 16 bp
   prefix of the accession, **not a complete replicon**. Assembly
   `GCF_000005845.2`, class `chromosome`, declared topology `circular`.
2. `NC_002128.1` — **NCBI prefix, positions 1–16 only** (`AGCCAGATTTTACCCG`),
   *E. coli* O157:H7 str. Sakai plasmid pO157. This is a 16 bp prefix of the
   accession, **not a complete replicon**. Assembly `GCF_000008865.2`, class
   `plasmid`, declared topology `circular`.
3. `synthetic_ambiguity_control` — **synthetic control** (`ACGTNRYA`) with
   non-canonical IUPAC symbols; its second window must be excluded with
   `AMBIGUOUS_WINDOW`.
4. `synthetic_partial_control` — **synthetic control** (`ACGTA`) whose final
   one-base window must be excluded with `PARTIAL_WINDOW`.

Both 16 bp prefixes were re-verified against NCBI Entrez (`efetch`,
`seq_start=1&seq_stop=16`) on 2026-07-31.

## Metadata

`pipeline_metadata.tsv` is the valid association table (one row per FASTA
record, in record order). The remaining TSVs are negative fixtures:

- `metadata_invalid.tsv` — row 1 declares a topology outside the controlled
  vocabulary; must fail with `METADATA_INVALID` (exit 9).
- `metadata_mismatch.tsv` — row 2 accession does not match the FASTA header;
  must fail with `METADATA_MISMATCH` (exit 10).
- `metadata_short.tsv` — one row missing; must fail with `METADATA_MISMATCH`
  (exit 10).

## Integrity

`SHA256SUMS` pins the bytes of every file above. Any change to an input
invalidates the recorded evidence hashes in `docs/IMPLEMENTATION_STATUS.md`.
