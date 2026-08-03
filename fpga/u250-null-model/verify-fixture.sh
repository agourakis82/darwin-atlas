#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

for required in julia g++; do
  if ! command -v "${required}" >/dev/null 2>&1; then
    echo "missing fixture dependency: ${required}" >&2
    exit 2
  fi
done

julia "${script_dir}/julia/generate_fixture_header.jl" \
  "${script_dir}/fixtures/null_draw_cases.tsv" \
  "${temp_dir}/generated_fixture.hpp"
cmp "${script_dir}/generated_fixture.hpp" "${temp_dir}/generated_fixture.hpp"

g++ -std=c++17 -O2 -Wall -Wextra -Werror -Wno-unknown-pragmas \
  "${script_dir}/src/csim.cpp" "${script_dir}/src/null_draws.cpp" \
  -o "${temp_dir}/null_draws_csim"
"${temp_dir}/null_draws_csim"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${script_dir}/fixtures/null_draw_cases.tsv" "${script_dir}/generated_fixture.hpp"
else
  shasum -a 256 "${script_dir}/fixtures/null_draw_cases.tsv" "${script_dir}/generated_fixture.hpp"
fi
echo "U250_NULL_FIXTURE_CONTRACT_PASS"
