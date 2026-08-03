#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly atlas_root="$(cd "${script_dir}/../.." && pwd)"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

for required in julia g++; do
  command -v "${required}" >/dev/null 2>&1 || { echo "missing fixture dependency: ${required}" >&2; exit 2; }
done
julia --startup-file=no "${script_dir}/julia/generate_fixture_header.jl" \
  "${atlas_root}/data/fixtures/dinucleotide_null/parameters.json" \
  "${atlas_root}/data/fixtures/dinucleotide_null/cases.tsv" \
  "${temp_dir}/generated_fixture.hpp"
cmp "${script_dir}/generated_fixture.hpp" "${temp_dir}/generated_fixture.hpp"
g++ -std=c++17 -O2 -Wall -Wextra -Werror -Wno-unknown-pragmas \
  "${script_dir}/src/csim.cpp" "${script_dir}/src/dinucleotide_draws.cpp" \
  -o "${temp_dir}/dinucleotide_csim"
"${temp_dir}/dinucleotide_csim"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${atlas_root}/data/fixtures/dinucleotide_null/cases.tsv" "${script_dir}/generated_fixture.hpp"
else
  shasum -a 256 "${atlas_root}/data/fixtures/dinucleotide_null/cases.tsv" "${script_dir}/generated_fixture.hpp"
fi
echo "U250_DINUCLEOTIDE_FIXTURE_CONTRACT_PASS"
