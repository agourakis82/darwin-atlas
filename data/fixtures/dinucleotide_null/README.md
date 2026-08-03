# Exact dinucleotide-null fixtures

Eight deterministic canonical windows exercise open and closed Euler trails,
parallel edges, self-loops, a homopolymer, a unique path, alternating bases,
and endpoint preservation. `case_templates.tsv` is the hand-authored source.
`scripts/generate_dinucleotide_cases.rb` binds it to the exact parameter hash
and derives each 64-bit seed from
`SHA-256(parameters_sha256:accession_version:window_start)`; regeneration must
be byte-identical to `cases.tsv`.

The standalone Sounio fixture emits 8 replicates per case. `invalid_cases.tsv`
contains an ambiguous window and must fail closed with exit 12 and no output.
This is an engineering fixture, not a chromosome-scale null product.
