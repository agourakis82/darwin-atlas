#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <null_draws_host> <null_draws.xclbin>" >&2
  exit 2
fi
readonly host_binary="$1"
readonly xclbin="$2"
readonly xrt_root="${XILINX_XRT:-/opt/xilinx/xrt}"
readonly runtime_libs="${U250_RUNTIME_LIBS:-/opt/dl380-libs}"
readonly xrt_smi="${xrt_root}/bin/xrt-smi"

for required in "${host_binary}" "${xclbin}" "${xrt_smi}"; do
  [[ -r "${required}" ]] || { echo "missing runtime input: ${required}" >&2; exit 2; }
done
[[ -x "${host_binary}" && -x "${xrt_smi}" ]] || {
  echo "runtime executable is not executable" >&2
  exit 2
}

export LD_LIBRARY_PATH="${xrt_root}/lib:${runtime_libs}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
device_report="$(${xrt_smi} examine)"
printf '%s\n' "${device_report}"
grep -Fq "xilinx_u250_gen3x16_xdma_shell_4_1" <<<"${device_report}"
grep -Eq '\|Yes[[:space:]]*\|' <<<"${device_report}"
result="$(${host_binary} "${xclbin}")"
printf '%s\n' "${result}"
[[ "${result}" == "U250_NULL_DRAW_PASS cases=8 metrics=18 replicates=8 draws=1152" ]]
echo "U250_NULL_HARDWARE_PASS"
