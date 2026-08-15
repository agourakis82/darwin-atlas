# U0 manifest/FASTA work-shard composition fixture

This fixture binds seven canonical `replicon x scale` work units to immutable
U0 parameter bytes and exact single-record FASTAs: three 48 bp sources, one
8 bp source, and one ACGT source of exactly 100, 500 and 1000 bp. The first two
48 bp sources are ACGT, the third contains one ambiguous window, and the 8 bp
source has no complete 16 bp window. Each added multiscale source contributes
exactly one complete window, avoiding accidental weighting by sequence length.

The host boundary verifies source and normalized SHA-256 identities and derives
the 64-bit seed ledger prescribed by ADR-0003. Each case row also carries an
explicit portable `run_id`. Sounio refuses a ledger whose run ID differs from
the invocation, consumes the bounded ledger, and is the only producer of the
v3 analytical JSONL rows. It does not implement SHA-256 internally. Julia
independently returns to parameters, manifest and FASTA bytes, re-derives every
seed, and recomputes every draw, metric, summary and output byte.

The three original executable units contain three non-overlapping 16 bp windows
each; the three added units contain one window at 100, 500 and 1000 bp. Together
they yield eleven eligible profiles and one exact `NULL_INPUT_NOT_ACGT`
excluded profile. The 8 bp unit remains in the plan as `PARTIAL_WINDOW` and has
no shard. Multi-line manifests require explicit `work_unit_id` selection.
The binder emits contiguous shards of at most 16 windows so a worst-case
1000 bp ledger remains below the executor's 32 KiB input ceiling; the checked resume
shard starts at window 1 and is the byte-exact suffix of the first full output.

`plan_u0_eligible_work_shards.py` produces plan version 3 and binds `run_id`,
nine case ledgers, twelve expected rows, one excluded window and one excluded work
unit. `execute_u0_work_shard_plan.py` executes missing shards with Sounio and,
on restart, reopens and reuses only exact existing artifacts. The checked first
pass executes 9/9 shards and the second reuses 9/9. The Base-only Julia set
validator proves exact coverage of all twelve complete windows and rejects a
single-digit perturbation.

The fixture runner then concatenates the canonical rows by scale, deposits the
window and common schemas plus source/execution bindings, and writes six
accession-bucketed Zstandard Parquet payloads across all four U0 scales.
Pinned DuckDB reopens the payloads to byte-identical JSONL, a second package is
byte-identical, and Julia recomputes all twelve reopened rows from parameters,
manifest and FASTA. Independent Parquet-byte and round-trip-JSON alterations
are refused.

This remains bounded synthetic evidence. It does not emit the real multiscale
U0 output manifest, execution receipt, public payload manifest, full-pilot
Julia receipt, Gate U0 PASS or an HDD authorization.

Observed at official Sounio commit
`37de2c9eefe68f3457a2c66004eff68bba5b4446`:

- source SHA-256 `687830a2b14e2f7ad9f54126acc674439152df9c15f3d726dc9e5b7990da4c4f`;
- ELF SHA-256 `61442b174cf31df500e4df6fb9e69a7bb8c3d915744f42b8eaa3e3fc6556aaa5`;
- default-run full/resume case SHA-256 values
  `9e14bd26a3c1081527d5294bee409338d4602f210f45fad86c71efbb857e3f00`
  and `11057fb07e5f8c740a6d3dd2737d8b984790a27797f0cea0e5341ea8a6ceb3c1`;
- second/third case SHA-256 values
  `bd5ad80f37757200cf396d6f71715a21d3a716e8faad8abf7cf95cac959aa3ea`
  and `9f696aa4a817fc37c396c5ea6c1dc619b593871bf62ab017510b0e0642f4bf83`;
- unchanged full/resume/second/third Sounio artifact SHA-256 values
  `c0fc4086a191028f5d746e60d48303268f402744a95415d2185750be08ba9941`,
  `2e8e45128ff50f65973af7c159180e074ea580009243f7b7e4e72043373e3900`,
  `4473a737412ec59805514038fc2a9737d1ec176d71a0a5010f4277f4956b6f20`
  and `4f263ed9a86c2275c502d6d75f50176a97048b80f063d5e4f6ea4537dd6e3ad7`;
- default fixture plan SHA-256
  `aa000b69a865c26b84c5184d24bc040c57ed0e06ff694fd7879987f9ffe052b4`;
- complete-set plan and execution-ledger SHA-256 values
  `cdf4740244808a953924abfb6c5f6f10f4628a63396e3fdad45d05bcf40d24ec`
  and `11388b5fd2aae1ca6973b524c444820a29446847446d3f84759d282b8292c5e1`;
- deterministic Parquet-set manifest, set-ledger and payload-ledger SHA-256
  values `ce3b79d6f86a9075e8f3ffa8ae1b3e4e9534db64d8579182efb928eed2c96f5e`,
  `577bd3910988135e2bdd9edaa6667883580ca9513fc3b0c1afe58a14337cf8a9`
  and `5d40e189fd8df9a86bcc00ebf9a0ecb976af339ea044356a96a66b4b3d319c1f`.
