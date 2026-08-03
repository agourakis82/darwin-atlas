#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <dinucleotide_draws_host> <dinucleotide_draws.xclbin>" >&2; exit 2; }
readonly host_binary="$1"
readonly xclbin="$2"
readonly xrt_root="${XILINX_XRT:-/opt/xilinx/xrt}"
readonly runtime_libs="${U250_RUNTIME_LIBS:-/opt/dl380-libs}"
readonly xrt_smi="${xrt_root}/bin/xrt-smi"

for required in "${host_binary}" "${xclbin}" "${xrt_smi}"; do
  [[ -r "${required}" ]] || { echo "missing runtime input: ${required}" >&2; exit 2; }
done
[[ -x "${host_binary}" && -x "${xrt_smi}" ]] || { echo "runtime executable is not executable" >&2; exit 2; }
export LD_LIBRARY_PATH="${xrt_root}/lib:${runtime_libs}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
device_report="$(${xrt_smi} examine)"
printf '%s\n' "${device_report}"
grep -Fq "xilinx_u250_gen3x16_xdma_shell_4_1" <<<"${device_report}"
grep -Eq '\|Yes[[:space:]]*\|' <<<"${device_report}"
result="$(${host_binary} "${xclbin}")"
printf '%s\n' "${result}"
[[ "${result}" == "U250_DINUCLEOTIDE_DRAW_PASS cases=8 replicates=8 slots=1024 tolerance=0" ]]
echo "U250_DINUCLEOTIDE_HARDWARE_PASS"
