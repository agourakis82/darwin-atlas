# Null-generator quality fixture (Fase N)

Statistical quality gate for both engineering null engines, feeding the
evidence annex of ADR-0002 (which remains **proposed**). This fixture does
not accept ADR-0002, does not set the pilot replicate count, and supports no
biological claim.

## Cases

| case_id        | engine | bases      | draws  | exact support | trails | expected/draw |
|----------------|--------|------------|--------|---------------|--------|---------------|
| mono_blocks    | mono   | AAAACCCC   | 140000 | 70 sequences  | 8!     | 2000.0        |
| dinuc_parallel | dinuc  | ACAGTGCATC | 72000  | 18 sequences  | 36     | 4000.0        |
| dinuc_distinct | dinuc  | AGCATCGTAC | 72000  | 36 sequences  | 36     | 2000.0        |

- `mono` replicates `lcg31_sha8_fixture_v1` (glibc-constant LCG mod 2^31,
  per-replicate seed mix, Fisher-Yates) from `fasta_stream_fixture.sio`, with
  fixed documented `record_index=1` and `metric_index=0`.
- `dinuc` replicates `euler_wilson_fixed_endpoints_v1` (ADR-0003) from
  `dinucleotide_null_fixture.sio` exactly.
- Both nulls are exactly uniform over their distinct-sequence support:
  Fisher-Yates gives every distinct multiset permutation the same fiber size
  `prod_c n_c!`; the Wilson construction is uniform over Eulerian trails and
  every trail sequence has the same multiplicity `prod_(v,w) m_vw!`.
- `dinuc_parallel` exercises parallel edges (multiplicity 2 per sequence,
  CA x 2 in the multigraph); `dinuc_distinct` has 36 trails over 36 distinct
  sequences (multiplicity 1).

## Seeds (`quality_parameters_sha256_v1`)

- mono: `seed_material` = first 16 hex of `parameters_sha256`; the fixture
  consumes the first 8 as `seed_base`, mirroring `null_seed_base_from_sha`.
- dinuc: `seed_material` = `first64be(SHA-256(parameters_sha256 || ":" ||
  accession_version || ":" || window_start))` (ADR-0003 derivation).

`cases.tsv` is frozen; `scripts/generate_null_quality_cases.rb` regenerates
it deterministically and the differential runner plus `make contract`
byte-compare it.

## Gate

`scripts/run_null_quality_differential.sh` compiles the fixture with the
pinned official Sounio (Lima guest, x86_64), runs it twice (byte-identical
determinism gate), and hands the 284000 draws to
`julia/scripts/validate_null_quality.jl`, which re-enumerates each exact
support, verifies every draw's metamorphic invariants, requires full support
coverage, and applies a chi-square uniformity test per case with
pre-declared `alpha=1e-3` (p-values via a Base-only regularized incomplete
gamma with closed-form self-tests). A corruption gate requires the validator
to reject one flipped base in the persisted artifact.

## Result (2026-08-05, Sounio pin `37de2c9e`)

- `dinuc_parallel`: PASS — chi2=18.27 (df=17), p=0.372, coverage 18/18.
- `dinuc_distinct`: PASS — chi2=37.35 (df=35), p=0.362, coverage 36/36.
- `mono_blocks`: **FAIL, structural** — coverage 55/70, chi2=111045 (df=69),
  p~0, frequency ratios 0.17x-5.33x. Root cause (Python replica byte-exact
  against the Sounio artifact): the arithmetic seed family composed with the
  glibc-constant LCG and `state mod (i+1)` Fisher-Yates reaches only 2520 of
  40320 position permutations (6.25%), for ANY seed_base/window/record/metric
  (6 configurations tested); the defect persists at the 16 bp pilot geometry
  (9711/12870 reachable sequences in 200000 consecutive replicates). The
  target therefore fails closed by design; the mono engine as engineered
  cannot serve as the pilot sensitivity null (ADR-0002 evidence annex N1).
  The persisted 284000-draw artifact is hash-bound as
  `dbb556be6866ef9960e1cf3825442cc38eb7931052a0bdf94b054c85801e95db`
  (not committed).
