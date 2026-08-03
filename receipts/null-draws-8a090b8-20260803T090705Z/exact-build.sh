#!/usr/bin/env bash
set -euo pipefail

readonly platform_name="xilinx_u250_gen3x16_xdma_4_1_202210_1"
readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly build_dir="${U250_NULL_BUILD_DIR:-${script_dir}/build}"
readonly amd_root="${AMD_VITIS_ROOT:-/opt/amd/2025.1}"
readonly settings="${amd_root}/Vitis/settings64.sh"

if [[ ! -f "${settings}" ]]; then
  echo "missing Vitis settings: ${settings}" >&2
  exit 2
fi
set +u
# shellcheck disable=SC1090
source "${settings}"
set -u

platform="${U250_PLATFORM_XPFM:-}"
if [[ -z "${platform}" ]]; then
  platform="$(find /opt/xilinx/platforms -type f -name "${platform_name}.xpfm" -print -quit 2>/dev/null || true)"
fi
if [[ -z "${platform}" || ! -f "${platform}" ]]; then
  echo "missing development platform: ${platform_name}" >&2
  exit 2
fi

mkdir -p "${build_dir}"
cd "${build_dir}"
platforminfo --platform "${platform}" > platforminfo.txt
v++ --version > vpp-version.txt
v++ -t hw --platform "${platform}" --save-temps -g \
  -c -k null_draws -o null_draws.xo "${script_dir}/src/null_draws.cpp" \
  2>&1 | tee compile.log
v++ -t hw --platform "${platform}" --save-temps -g \
  -l --config "${script_dir}/null_draws.cfg" \
  -o null_draws.xclbin null_draws.xo \
  2>&1 | tee link.log
sha256sum \
  "${script_dir}/src/null_draws.cpp" \
  "${script_dir}/src/host.cpp" \
  "${script_dir}/generated_fixture.hpp" \
  "${script_dir}/null_draws.cfg" \
  null_draws.xo null_draws.xclbin > SHA256SUMS
echo "U250_NULL_XCLBIN_BUILD_PASS ${build_dir}/null_draws.xclbin"
