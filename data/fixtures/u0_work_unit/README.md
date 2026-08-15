# U0 manifest/FASTA work-unit composition fixture

This fixture binds one canonical `replicon x scale` work unit to an exact
48 bp single-record FASTA and the immutable U0 parameter bytes. The host
boundary verifies both SHA-256 identities and derives the 64-bit seed ledger
prescribed by ADR-0003. Sounio consumes that bounded ledger and is the only
producer of the complete v3 analytical rows; it does not implement SHA-256
seed derivation internally. Julia independently returns to the parameter,
manifest and FASTA bytes, re-derives each seed, and recomputes every draw,
metric, summary and output byte.

This is deliberately one synthetic work unit containing three non-overlapping
16 bp windows. The binder can emit bounded contiguous shards of at most 32
windows; the checked resume shard starts at window 1 and its two produced rows
are byte-identical to the suffix of the full three-row artifact. This proves
bounded composition and resume semantics for the already-validated manifest
and analytical cores. It is not a streaming chromosome executor, a RefSeq
pilot, pilot-wide coverage, Parquet, an execution receipt, or Gate U0 evidence.

Observed at official Sounio commit
`37de2c9eefe68f3457a2c66004eff68bba5b4446`: full case-ledger SHA-256
`ebb071824c41015d70027b54716983ead2b12fa94854ede6392e5c7344bd66f8`;
three-row Sounio artifact SHA-256
`c0fc4086a191028f5d746e60d48303268f402744a95415d2185750be08ba9941`;
resume case-ledger SHA-256
`bfc95c21837aafdfae55be1e11828b5505421b8f713b400a4437527258ee31a3`;
two-row resume artifact SHA-256
`2e8e45128ff50f65973af7c159180e074ea580009243f7b7e4e72043373e3900`.
