# U250 fixture null-model accelerator

This directory accelerates the existing schema 0.3.0 executable-fixture null:
the mononucleotide-preserving Fisher-Yates shuffle driven by the exact
`lcg31_sha8_fixture_v1` seed chain. It does **not** accept ADR-0002, promote the
mononucleotide shuffle to the pilot primary null, or make a biological or
performance claim.

The Julia Base-only generator uses the independent string/`Dict` orbit metric
implementation from `julia/scripts/window_pipeline_core.jl` and freezes 1,152
raw scaled draws: 8 cases, 18 metrics, and 8 replicates. The cases include full
canonical windows, self-symmetry, IUPAC ambiguity, a fully ambiguous window, a
partial window, the k=4 configuration, a higher effective-count threshold,
and large coordinates. `verify-fixture.sh` regenerates the C++ header and then
executes the HLS kernel as ordinary C++ against every Julia draw with tolerance
zero.

`build.sh` targets the exact installed U250 development platform and emits a
hardware `.xclbin`. `compile-host.sh` builds the XRT host. `run-hardware.sh`
requires a ready XDMA 4.1 shell, validates all 1,152 hardware results against
the frozen Julia vector, and emits `U250_NULL_HARDWARE_PASS` only on exact
equality. Loading the `.xclbin` affects only the reconfigurable user partition;
these scripts contain no management or persistent-flash operation.
