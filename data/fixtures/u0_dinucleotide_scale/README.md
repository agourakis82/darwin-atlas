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

- Sounio source SHA-256 `7c372d6c98d3960685da77fe9ee1518a9db0de395a8222d4a80e59c9294a917a`;
- compiled ELF SHA-256 `810fa4453dbf5d0848e8b8c50c9e0265f9dfc0b0bde4f2c9051b9685a054df04`;
- unchanged 4000-draw artifact SHA-256 `726c2c9fd3f96a27b6ae18d35ad73f203c0cae94bae9f0094618b31db81f2463`;
- four-row profile artifact SHA-256 `f0b5ef9cabaf1e998f5851b6008936b3764f22c8718625cf31de0ac571424016`.

The same executable also accepts a bounded work-unit shard mode (1 to 32
windows) and an explicit start-window coordinate. The host derives the seed
ledger; Sounio validates its grammar and coordinates and consumes it, while
Julia independently re-derives the seeds from the immutable inputs. The
three-row full case/artifact hashes are `ebb071824c41015d70027b54716983ead2b12fa94854ede6392e5c7344bd66f8`
and `c0fc4086a191028f5d746e60d48303268f402744a95415d2185750be08ba9941`.
The two-row resume case/artifact hashes are
`bfc95c21837aafdfae55be1e11828b5505421b8f713b400a4437527258ee31a3`
and `2e8e45128ff50f65973af7c159180e074ea580009243f7b7e4e72043373e3900`;
the resume artifact is byte-identical to rows 2-3 of the full artifact.
An independently selected second work unit produces a three-row case ledger
`ca2c8797d3ca1ae116a6f5f8ef9eb997d4f5ac3a8514ad18b788d471afcf6429`
and deterministic Sounio artifact
`4473a737412ec59805514038fc2a9737d1ec176d71a0a5010f4277f4956b6f20`,
also recomputed byte-exact by Julia.

Passing this fixture establishes neither U0, a manifest/FASTA-driven pilot
executor, an integral pilot receipt, a RefSeq result, Parquet equivalence nor
an accelerator-equivalence claim.
