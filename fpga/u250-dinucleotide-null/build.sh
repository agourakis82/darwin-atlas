#!/usr/bin/env bash
set -euo pipefail

readonly platform_name="xilinx_u250_gen3x16_xdma_4_1_202210_1"
readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly build_dir="${U250_DINUCLEOTIDE_BUILD_DIR:-${script_dir}/build}"
readonly amd_root="${AMD_VITIS_ROOT:-/opt/amd/2025.1}"
readonly settings="${amd_root}/Vitis/settings64.sh"

[[ -f "${settings}" ]] || { echo "missing Vitis settings: ${settings}" >&2; exit 2; }
set +u
# shellcheck disable=SC1090
source "${settings}"
set -u
platform="${U250_PLATFORM_XPFM:-}"
if [[ -z "${platform}" ]]; then
  platform="$(find /opt/xilinx/platforms -type f -name "${platform_name}.xpfm" -print -quit 2>/dev/null || true)"
fi
[[ -n "${platform}" && -f "${platform}" ]] || { echo "missing platform: ${platform_name}" >&2; exit 2; }

mkdir -p "${build_dir}"
cd "${build_dir}"
platforminfo --platform "${platform}" > platforminfo.txt
v++ --version > vpp-version.txt
v++ -t hw --platform "${platform}" --save-temps -g \
  -c -k dinucleotide_draws -o dinucleotide_draws.xo \
  "${script_dir}/src/dinucleotide_draws.cpp" 2>&1 | tee compile.log
v++ -t hw --platform "${platform}" --save-temps -g \
  -l --config "${script_dir}/dinucleotide_draws.cfg" \
  -o dinucleotide_draws.xclbin dinucleotide_draws.xo 2>&1 | tee link.log
sha256sum "${script_dir}/src/dinucleotide_draws.cpp" \
  "${script_dir}/src/host.cpp" "${script_dir}/generated_fixture.hpp" \
  "${script_dir}/dinucleotide_draws.cfg" dinucleotide_draws.xo \
  dinucleotide_draws.xclbin > SHA256SUMS
echo "U250_DINUCLEOTIDE_XCLBIN_BUILD_PASS ${build_dir}/dinucleotide_draws.xclbin"
