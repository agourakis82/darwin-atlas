# U0 manifest/FASTA work-unit composition fixture

This fixture binds two canonical `replicon x scale` work units to two exact
48 bp single-record FASTAs and the immutable U0 parameter bytes. The host
boundary verifies both SHA-256 identities and derives the 64-bit seed ledger
prescribed by ADR-0003. Sounio consumes that bounded ledger and is the only
producer of the complete v3 analytical rows; it does not implement SHA-256
seed derivation internally. Julia independently returns to the parameter,
manifest and FASTA bytes, re-derives each seed, and recomputes every draw,
metric, summary and output byte.

Each synthetic unit contains three non-overlapping 16 bp windows. Multi-line
manifests require explicit `work_unit_id` selection. The binder emits bounded
contiguous shards of at most 32 windows; the checked resume shard starts at
window 1 and its two produced rows are byte-identical to the suffix of the
first full artifact. `plan_u0_eligible_work_shards.py` deterministically
enumerates both units as four two-row-capped ledgers (2,1,2,1 rows) with a
hash-closed pre-execution plan. The plan explicitly says
`scientific_metrics_computed=false`, `sounio_executed=false` and
`gate_u0_pass=false`; it refuses non-ACGT or zero-window units until a
reason-coded exclusion planner exists. This proves bounded multi-unit
selection, sharding and resume semantics. It is not a streaming chromosome
executor, a RefSeq pilot, pilot-wide coverage, Parquet, an execution receipt,
or Gate U0 evidence.

Observed at official Sounio commit
`37de2c9eefe68f3457a2c66004eff68bba5b4446`: full case-ledger SHA-256
`ebb071824c41015d70027b54716983ead2b12fa94854ede6392e5c7344bd66f8`;
three-row Sounio artifact SHA-256
`c0fc4086a191028f5d746e60d48303268f402744a95415d2185750be08ba9941`;
resume case-ledger SHA-256
`bfc95c21837aafdfae55be1e11828b5505421b8f713b400a4437527258ee31a3`;
two-row resume artifact SHA-256
`2e8e45128ff50f65973af7c159180e074ea580009243f7b7e4e72043373e3900`;
second-unit case/artifact SHA-256
`ca2c8797d3ca1ae116a6f5f8ef9eb997d4f5ac3a8514ad18b788d471afcf6429`
and `4473a737412ec59805514038fc2a9737d1ec176d71a0a5010f4277f4956b6f20`.
The shard-plan SHA-256 at shard size 2 is
`081b45724b06b6955b6335bc7e14410e39b56730f2266e5247beb17375cccaf8`.
