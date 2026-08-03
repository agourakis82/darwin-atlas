# ADR-0003: Exact dinucleotide-null engineering contract

- **Status:** accepted
- **Date:** 2026-08-03
- **Scope:** deterministic executable fixture and accelerator equivalence
- **Related pilot decision:** ADR-0002 remains proposed

## Context

“Dinucleotide-preserving shuffle” is not a complete executable definition. A
reproducible implementation must fix the multigraph construction, terminal
conditions, arborescence sampler, edge ordering, bounded random draws, seed
encoding, and replicate stream separation. Fase K accelerated only the older
mononucleotide sensitivity fixture and therefore could not establish the
candidate primary null from ADR-0002.

## Decision

The Fase L engineering fixture uses
`euler_wilson_fixed_endpoints_v1`:

1. Each adjacent canonical base pair is a distinct directed edge in a
   four-vertex multigraph. Parallel edges remain distinct while sampling.
2. The first and last bases are fixed. The last base is the root of a directed
   arborescence sampled by Wilson loop-erased random walks over outgoing edge
   instances.
3. Each outgoing edge list is Fisher-Yates shuffled. For every active
   non-root vertex, its arborescence edge is moved to the final position.
   Walking the lists from the original first base yields the randomized Euler
   trail.
4. Every bounded selection uses rejection sampling, never raw modulo alone.
5. The per-window base seed is exactly the first 64 big-endian bits of
   `SHA-256(parameters_sha256 || ":" || accession_version || ":" ||
   window_start)`, preserving the derivation proposed by ADR-0002. Because the
   pinned Sounio compiler has no SHA-256 primitive, a frozen sidecar carries
   the 16 lowercase seed hex digits; Julia independently recomputes and rejects
   any mismatch.
6. The deterministic generator is the two-component combined multiplicative
   generator from L'Ecuyer's portable construction (`a1=40014`,
   `m1=2147483563`, `a2=40692`, `m2=2147483399`). Replicate streams are
   separated by `2^20` steps using independently checked jump multipliers.
7. Inputs containing non-ACGT bases are unavailable for this primary-null
   candidate and fail closed in the standalone fixture. They are never
   coerced, deleted, or randomly resolved.

## Required evidence

- pinned official Sounio produces every frozen sequence draw;
- Julia independently recomputes the SHA seed, generator, graph walk, exact
  output bytes, endpoints, length, base counts, and all 16 dinucleotide counts;
- the HLS C simulation and real U250 hardware match every frozen Julia base
  slot with tolerance zero;
- corruption of one persisted Sounio draw is rejected;
- the receipt records the Sounio pin, source/input hashes, Vitis platform,
  XRT/card identity, build warnings, and hardware log.

## Boundary

Acceptance of this ADR fixes only the engineering fixture semantics. It does
not accept ADR-0002, set the pilot replicate count, validate pseudorandom
quality, integrate the model into chromosome-scale products, establish a
performance result, or support a biological claim. Those remain separate
gates.

## References

- Altschul and Erickson (1985), exact dinucleotide-preserving permutations as
  Eulerian walks: <https://pubmed.ncbi.nlm.nih.gov/3870875/>
- Jiang et al. (2008), uShuffle's uniform k-let-preserving Euler/Wilson
  construction: <https://doi.org/10.1186/1471-2105-9-192>
- Wilson (1996), loop-erased random-walk spanning trees:
  <https://doi.org/10.1145/237814.237880>
- L'Ecuyer (1988), portable combined random-number generators:
  <https://doi.org/10.1145/62959.62969>
