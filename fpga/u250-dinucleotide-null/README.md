# U250 exact dinucleotide-null accelerator

This Fase L directory accelerates the exact fixture contract
`euler_wilson_fixed_endpoints_v1`: Wilson loop-erased random walks select a
rooted directed arborescence, outgoing edge lists are shuffled with the tree
edge last, and the original start-to-end Euler trail is emitted. Edge choices
use rejection sampling over `lecuyer_combined31_substream20_sha64_v1`; the
eight replicate streams are separated by `2^20` generator steps.

The canonical producer is the pinned official Sounio executable in
`sounio/src/dinucleotide_null_fixture.sio`. Julia independently recalculates
the SHA-256 seed, all 64 draws, endpoints, lengths, mononucleotide counts, and
all 16 dinucleotide counts. The generated FPGA header freezes the same 1,024
base slots (8 cases × 8 replicates × 16 slots); C simulation and real U250
execution must match every slot exactly.

This closes only a deterministic engineering fixture. It does not by itself
prove pseudorandom statistical quality, pilot-scale performance, biological
validity, or release eligibility. The scripts load only the reconfigurable
user partition and contain no persistent flash operation.
