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
writing JSONL. An invalid TSV therefore exits 12 without writing stdout. Its
default mode emits all 4000 shuffled sequences. Its `--profiles` mode reuses
the same draw stream to emit four complete
`dosa_v3_window_profile.schema.json` rows containing positional R/RC and the
published k-mer R (k=2..8) and RC (k=1..8) observations, exact n=1000
mean/MAD/quantiles, and `<`/`=`/`>` tail counts.

The profile validator in Julia independently reconstructs every shuffle,
metric, summary and complete JSON line. A separate stdlib Python validator
checks the structural/cross-field invariants; the integration test also
validates the rows against the public JSON Schema. At official Sounio commit
`37de2c9eefe68f3457a2c66004eff68bba5b4446`, the observed evidence is:

- Sounio source SHA-256 `0ba40491c0202e59d04e5c9ad03c58c33eac9e33681145b2914df88256bc92ee`;
- compiled ELF SHA-256 `9a0b32cd4b90d7494b080b2545aa7aac73f759f56afcadadcc657479236cd023`;
- unchanged 4000-draw artifact SHA-256 `726c2c9fd3f96a27b6ae18d35ad73f203c0cae94bae9f0094618b31db81f2463`;
- four-row profile artifact SHA-256 `f0b5ef9cabaf1e998f5851b6008936b3764f22c8718625cf31de0ac571424016`.

The same executable also accepts a separately pinned one-work-unit mode. Its
host-derived case ledger SHA-256 is
`781326e35a9f32b874c8fa49c3b1249c330a05f1e5625bd9bff67b7a567f7457`
and its complete one-row profile artifact is
`4a81aefafb99ef5beabc3c813cc8f265d52f21fd7df748be04e1dfce0074bea8`.

Passing this fixture establishes neither U0, a manifest/FASTA-driven pilot
executor, an integral pilot receipt, a RefSeq result, Parquet equivalence nor
an accelerator-equivalence claim.
