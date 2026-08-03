#!/usr/bin/env bash
set -euo pipefail

readonly platform_name="xilinx_u250_gen3x16_xdma_4_1_202210_1"
readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly build_dir="${U250_BUILD_DIR:-${script_dir}/build}"
readonly amd_root="${AMD_VITIS_ROOT:-/opt/amd/2025.1}"
readonly settings="${amd_root}/Vitis/settings64.sh"

if [[ ! -f "${settings}" ]]; then
  echo "missing Vitis settings: ${settings}" >&2
  exit 2
fi

# AMD's settings script reads optional variables such as PYTHONPATH before
# assigning them, so source it with nounset temporarily disabled.
# shellcheck disable=SC1090
set +u
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
platforminfo --platform "${platform}" > "${build_dir}/platforminfo.txt"
v++ --version > "${build_dir}/vpp-version.txt"

v++ -t hw --platform "${platform}" --save-temps -g \
  -c -k vector_add \
  -o "${build_dir}/vector_add.xo" \
  "${script_dir}/src/vector_add.cpp" \
  2>&1 | tee "${build_dir}/compile.log"

v++ -t hw --platform "${platform}" --save-temps -g \
  -l --config "${script_dir}/vector_add.cfg" \
  -o "${build_dir}/vector_add.xclbin" \
  "${build_dir}/vector_add.xo" \
  2>&1 | tee "${build_dir}/link.log"

sha256sum \
  "${script_dir}/src/vector_add.cpp" \
  "${script_dir}/src/host.cpp" \
  "${script_dir}/vector_add.cfg" \
  "${build_dir}/vector_add.xo" \
  "${build_dir}/vector_add.xclbin" \
  > "${build_dir}/SHA256SUMS"

echo "U250_XCLBIN_BUILD_PASS ${build_dir}/vector_add.xclbin"
