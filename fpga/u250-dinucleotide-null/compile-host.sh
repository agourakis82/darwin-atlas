#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly source_file="${U250_DINUCLEOTIDE_HOST_SOURCE:-${script_dir}/src/host.cpp}"
readonly output_file="${U250_DINUCLEOTIDE_HOST_OUTPUT:-${script_dir}/build/dinucleotide_draws_host}"
readonly xrt_root="${XILINX_XRT:-/opt/xilinx/xrt}"

for required in g++ sha256sum; do
  command -v "${required}" >/dev/null 2>&1 || { echo "missing runtime build dependency: ${required}" >&2; exit 2; }
done
[[ -f "${xrt_root}/include/xrt/xrt_device.h" && -f "${xrt_root}/lib/libxrt_coreutil.so" ]] || {
  echo "missing XRT development files under ${xrt_root}" >&2
  exit 2
}
mkdir -p "$(dirname "${output_file}")"
g++ -std=c++17 -O2 -Wall -Wextra -Werror \
  -isystem "${xrt_root}/include" "${source_file}" \
  -L"${xrt_root}/lib" -Wl,-rpath,"${xrt_root}/lib" \
  -lxrt_coreutil -luuid -pthread -o "${output_file}"
sha256sum "${source_file}" "${script_dir}/generated_fixture.hpp" "${output_file}"
echo "U250_DINUCLEOTIDE_HOST_BUILD_PASS ${output_file}"
