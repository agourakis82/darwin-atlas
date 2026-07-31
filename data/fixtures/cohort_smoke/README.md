# Cohort smoke fixture — engineering smoke at complete-replicon scope

Single-record fixture derived from the frozen miniature cohort
(`data/cohort/mini/`): plasmid `NC_002127.1` (pOSAK1, 3,306 bp, circular,
pure ACGT alphabet) from assembly `GCF_000008865.2` (*E. coli* O157:H7 str.
Sakai). At 16/16 windows this yields 207 JSONL lines (206 full windows plus
one 10 bp partial window).

This is an **engineering smoke**: it proves the Sounio producer and the
independent Julia validator run end to end on a real complete replicon and
agree byte for byte. It is NOT the pilot run of specification §8, NOT a
release receipt, and it does not by itself promote any gate. The fixtures use
`--science-boundary off`.

## Contents

- `nc_002127_1.fa` — the `NC_002127.1` FASTA record extracted byte-exact
  (header included) from the frozen cohort assembly FASTA;
- `nc_002127_1_metadata.tsv` — single-row pipeline metadata mirroring
  `data/cohort/mini/replicons.tsv` (scope `ncbi_complete_replicon`);
- `parameters_k8.json` — byte-identical copy of the k=1..8 mini-pipeline
  fixture parameters (16/16 windows, masked k-mer policy);
- `SHA256SUMS` — pins the three files above.

Kernel coverage note: dual-kernel (optimized vs reference) byte equivalence
is gated at fixture scope by `run_sounio_mini_pipeline.sh`; the reference
kernel is not scale-oriented. The smoke runs the optimized kernel twice
(determinism) and delegates independent recomputation to the Base-only Julia
validator, which is the stronger check at this scope.

Run with:

```bash
SOUNIO_REPO=/path/to/sounio SOUNIO_LIMA_INSTANCE=souc-linux \
  scripts/run_cohort_smoke_differential.sh
```
