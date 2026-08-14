# U0 dinucleotide scale fixture

This is a capacity and semantic-regression fixture for the future U0 producer.
It is not a cohort, source manifest, U0 output, biological result, or release
receipt.

`cases.tsv` contains exactly four canonical synthetic windows (16, 100, 500,
and 1000 bases), each with exactly 1000 requested Euler/Wilson draws.  The
canonical `data/v3/u0_parameters.json` bytes domain-separate the specified
seed derivation.  `scripts/generate_u0_dinucleotide_scale_cases.rb` regenerates
the checked-in cases byte for byte. The dedicated Sounio fixture also pins the
expected parameter SHA, accession, coordinate and derived seed for each row;
the runner's generator comparison binds those literals back to the canonical
parameter bytes. Input is strict ASCII TSV with LF line endings and a terminal
LF.

The dedicated Sounio executable uses two full validation/dry-run passes before
writing JSONL.  An invalid TSV therefore exits 12 without writing stdout.
Passing it establishes neither U0 nor an accelerator equivalence claim.
