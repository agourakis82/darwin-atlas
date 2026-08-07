# Fase P1 — U250 dinucleotide-null throughput probe

Measures real draws/s of the proven Fase L kernel (`dinucleotide_draws`) on the
Alveo U250, turning the envelope estimates in ADR-0002 (~0.5–2M draws/s per
kernel instance) into measured numbers. The probe **reuses the exact Fase L
xclbin** — the kernel takes `case_count` and `replicates` at runtime, so no
Vitis rebuild is needed.

Status: **pending hardware run** (requires network access to the `darwin`
cluster; the probe source, pod manifest, and this runbook are committed ahead
of the run).

## What the probe does (`src/host_throughput.cpp`)

1. **Correctness anchor** — runs the frozen Fase L fixture (8 cases × 8
   replicates, `generated_fixture.hpp`) with tolerance 0. If the anchor fails,
   the probe exits before any throughput measurement.
2. **Throughput sweep** — 1024 synthetic windows (default; up to 4096 via CLI
   arg) cycling through four graph families: homopolymer, strictly alternating,
   branching (`ACAGTGCATCACAGTG`), and splitmix64 pseudo-random. Seeds are
   host-drawn splitmix64 values — this probe measures throughput only; semantic
   seed derivation remains gated by the fixture anchor. Sweep: R ∈ {8, 64, 256,
   1024} replicates.
3. **Integrity check** — on the R=8 batch, every output slot is synced back and
   must be written (no `-2` sentinel), in range `[-1, 3]`, with window endpoints
   preserved.

Markers (grep-able, one per line):

```
U250_DINUCLEOTIDE_THROUGHPUT_ANCHOR cases=8 replicates=8 slots=1024 tolerance=0
U250_DINUCLEOTIDE_THROUGHPUT cases=<N> replicates=<R> draws=<D> wall_ms=<W> draws_per_second=<Q>
U250_DINUCLEOTIDE_THROUGHPUT_INTEGRITY cases=<N> replicates=8 slots_ok=<S>
U250_DINUCLEOTIDE_THROUGHPUT_PASS anchor=ok cases=<N> max_replicates=1024
```

## Runbook

All commands run from a machine with cluster access (kubeconfig
`~/.kube/config-darwin`, context `darwin`). Paths below assume the repo clone
that contains the Fase L build (`build/dinucleotide_draws.xclbin`).

```bash
export KUBECONFIG="$HOME/.kube/config-darwin"
cd fpga/u250-dinucleotide-null

# 1. Start the probe pod (scheduled on the U250 node via device plugin).
kubectl apply -f kubernetes/throughput-pod.yaml
kubectl wait --for=condition=Ready pod/darwin-atlas-u250-throughput --timeout=180s

# 2. Copy sources, fixture header, compile script, and the Fase L xclbin.
kubectl exec -i darwin-atlas-u250-throughput -- mkdir -p /work/src /work/build
kubectl cp src/host_throughput.cpp darwin-atlas-u250-throughput:/work/src/host_throughput.cpp
kubectl cp generated_fixture.hpp   darwin-atlas-u250-throughput:/work/generated_fixture.hpp
kubectl cp compile-host.sh         darwin-atlas-u250-throughput:/work/compile-host.sh
kubectl cp build/dinucleotide_draws.xclbin darwin-atlas-u250-throughput:/work/build/dinucleotide_draws.xclbin

# 3. Compile the probe inside the pod (XRT headers come from the hostPath mount).
kubectl exec -i darwin-atlas-u250-throughput -- bash -lc '
  cd /work &&
  U250_DINUCLEOTIDE_HOST_SOURCE=/work/src/host_throughput.cpp \
  U250_DINUCLEOTIDE_HOST_OUTPUT=/work/build/dinucleotide_throughput_host \
  bash compile-host.sh'

# 4. Run the probe (default 1024 cases; pass a second arg for up to 4096).
kubectl exec -i darwin-atlas-u250-throughput -- bash -lc '
  export LD_LIBRARY_PATH=/opt/xilinx/xrt/lib:/opt/dl380-libs &&
  /opt/xilinx/xrt/bin/xrt-smi examine &&
  /work/build/dinucleotide_throughput_host /work/build/dinucleotide_draws.xclbin' \
  | tee throughput_probe_run1.txt

# 5. Require the PASS marker.
grep -q 'U250_DINUCLEOTIDE_THROUGHPUT_PASS anchor=ok' throughput_probe_run1.txt

# 6. Teardown.
kubectl delete pod darwin-atlas-u250-throughput
```

## After the run

- Record the `U250_DINUCLEOTIDE_THROUGHPUT` lines (R sweep, wall_ms, draws/s)
  as a table in the ADR-0002 evidence annex, alongside the receipt of this run
  (stdout log + sha256 of the probe binary printed by `compile-host.sh`).
- Use the measured draws/s per instance to size the n=1000 dinucleotide pilot
  and the P2 kernel redesign (shared shuffle across the 18 metrics, ROM
  jump-ahead table, in-kernel summaries, N instances).

## Notes

- The output buffer for the default sweep is 1024 cases × 1024 replicates ×
  16 slots × 4 B = 64 MiB; the 4096-case maximum allocates 256 MiB. Both fit a
  single U250 DDR bank under shell `xdma_4_1`.
- The probe binary is a host-side artifact only; the kernel bitstream is
  byte-identical to the one receipted in Fase L
  (`receipts/dinucleotide-null-556ac81-20260803T171300Z/`).
