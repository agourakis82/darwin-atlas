# DOSA novelty and effective-contribution audit

**Audit date and literature cutoff:** 2026-08-09

**State:** living audit; no scientific novelty claim is established

**Machine-readable registry:** `data/novelty/claims.json`

## Decision

Novelty is not established by the current engineering receipts. They establish
that the proposed measurements can be produced deterministically by Sounio and
checked independently by Julia. They do not establish a new biological result.

The broad claims that DOSA is the first study of reverse-complement symmetry,
the first windowed study, the first reversal-versus-reverse-complement
comparison, the inventor of dinucleotide-preserving shuffling, or the first
provenance-bound genomic resource are explicitly rejected.

The scientifically defensible target is narrower:

> Determine whether a joint, representation-aware decomposition of positional
> reversal/reverse-complement similarity, compositional k-mer orbit imbalance,
> circular origin/strand equivalence and periodicity contains reproducible
> biological structure after exact dinucleotide-preserving null calibration.

That statement is a falsifiable research target, not a result. A second valid
contribution path is a reusable, versioned operator atlas with negative or null
results, provided the released data are complete, auditable and demonstrably
useful.

## Nearest prior art and claim boundary

| Prior work | What it already establishes | Consequence for DOSA |
|---|---|---|
| Baisnee, Hampson and Baldi (2002), DOI `10.1093/bioinformatics/18.8.1021` | Multi-order complementary-strand symmetry across broad biological groups | No first multi-order or broad-taxonomy claim |
| Kong et al. (2009), DOI `10.1371/journal.pone.0007553` | Reverse, complement and reverse-complement comparisons globally and locally across 786 chromosomes | No first operator-separation or complete-genome survey claim |
| Shporer et al. (2016), DOI `10.1186/s12864-016-3012-8` | Normalized inverse-k-mer deviations, reverse comparators, non-overlapping windows and bacterial k-limits near the DOSA range | No novelty from windowing or `k=1..8` alone |
| Bastos et al. (2016), DOI `10.1186/s12859-016-0905-0` | Local exceptional word symmetry with structural controls | Local symmetry is not new by itself |
| Fariselli et al. (2021), DOI `10.1093/bib/bbaa041` | A generalized randomness/maximum-entropy account of Chargaff symmetry | Any residual biological claim must outperform a strong null explanation |
| Altschul and Erickson (1985), DOI `10.1093/oxfordjournals.molbev.a040370`; Jiang et al. (2008), DOI `10.1186/1471-2105-9-192` | Exact dinucleotide/k-let-preserving randomization | DOSA's null implementation is infrastructure, not algorithmic novelty |

## Contribution classes

### Scientific contribution

Scientific novelty requires a preregistered result that survives the exact
dinucleotide null, grouped validation, covariate adjustment, sensitivity
analysis and a held-out cohort. Statistical significance alone is insufficient;
the result must have a stable direction and practically meaningful effect size.

### Data contribution

A negative result can still support an effective contribution if DOSA releases
the complete operator-resolved atlas: immutable accession versions, topology,
coordinates, ambiguity/effective counts, exclusions, null summaries, schemas,
parameters and receipts. Reusability must be shown with at least one independent
downstream analysis, not asserted from metadata volume.

### Engineering contribution

The Sounio-producer/Julia-validator contract is already supported at fixture and
sampled engineering scope. It is not a biological novelty claim. U250 and ROCm
are accelerators only; their output cannot become canonical without the same
Sounio and Julia evidence boundary.

## Novelty and contribution gates

| Gate | Requirement | Current state |
|---|---|---|
| NC0 — prior-art boundary | Search queries, cutoff, closest works and rejected claims are frozen before outcome inspection | PASS for this audit; must be refreshed before submission |
| NC1 — non-redundancy | Joint operator profile adds stable information beyond GC, length, complexity, taxonomy and exact dinucleotide-null summaries | RED — no pilot result |
| NC2 — representation validity | Origin/strand/topology behavior holds in release artifacts, not only fixtures | PARTIAL — metamorphic fixtures pass; pilot artifacts absent |
| NC3 — biological utility | At least one H1-H4 result has a preregistered, meaningful effect and grouped held-out replication | RED — no inferential pilot run |
| NC4 — data utility | Frozen atlas, exclusions, documentation, DOI and an independent reuse demonstration exist | RED — engineering bundle only |
| NC5 — independent reproduction | Release-scope Sounio products and Julia recomputation agree under the declared tolerance | PARTIAL — fixtures and deterministic samples pass |

No claim in `data/novelty/claims.json` may set `release_eligible=true` under
schema version 0.1.0. Promotion requires a reviewed registry/schema revision
that cites the exact passing evidence and refreshes the literature search.

## Kill criteria

The biological novelty route is killed, not reworded, if any of these holds:

1. residual effects disappear after exact dinucleotide-null calibration or
   preregistered covariate control;
2. apparent replication-coordinate or replicon-class effects fail grouped
   assembly/taxonomy-aware validation or reverse in the held-out cohort;
3. one or a few assemblies drive the effect;
4. a closer prior study is found that already implements the full joint design;
5. Sounio and Julia disagree on any release-blocking artifact.

If NC1 or NC3 fails but NC4 and NC5 pass, the honest contribution is a negative
benchmark and reusable data resource. If NC4 also fails, the output remains an
engineering prototype and must not support a publication novelty statement.

## Required next experiment

1. Freeze the pilot cohort, window/effective-count thresholds, replicate count,
   origin annotation policy, covariates and held-out split without examining
   outcome labels.
2. Generate exact-dinucleotide-null window products with Sounio; keep Julia as
   the independent validator and accelerators outside the authority boundary.
3. Test incremental predictive/explanatory value of the joint profile against
   nested baselines: length+GC, then complexity+taxonomy, then dinucleotide-null
   summaries.
4. Evaluate H1-H4 with assembly/taxonomy-aware uncertainty, multiplicity control,
   effect sizes, influence analysis and held-out replication.
5. Promote only the claims whose predeclared falsifiers were not triggered.
