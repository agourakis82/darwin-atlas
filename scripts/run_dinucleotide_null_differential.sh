#!/usr/bin/env bash
set -euo pipefail

readonly atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly lock_file="${atlas_root}/toolchains/sounio.lock.json"
readonly source_file="${atlas_root}/sounio/src/dinucleotide_null_fixture.sio"
readonly fixture_dir="${atlas_root}/data/fixtures/dinucleotide_null"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ -z "${SOUNIO_REPO:-}" ]]; then
  echo "BLOCKED: set SOUNIO_REPO to the pinned official Sounio checkout" >&2
  exit 2
fi
for required in ruby julia limactl; do
  command -v "${required}" >/dev/null 2>&1 || { echo "BLOCKED: missing ${required}" >&2; exit 2; }
done
[[ -d "${SOUNIO_REPO}/.git" && -x "${SOUNIO_REPO}/bin/souc" ]] || {
  echo "BLOCKED: invalid Sounio checkout" >&2
  exit 2
}

expected_commit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("commit")' "${lock_file}")"
expected_repo="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("repository")' "${lock_file}")"
actual_commit="$(git -C "${SOUNIO_REPO}" rev-parse HEAD)"
actual_remote="$(git -C "${SOUNIO_REPO}" remote get-url origin)"
[[ "${actual_commit}" == "${expected_commit}" ]] || { echo "BLOCKED: Sounio pin mismatch" >&2; exit 2; }
case "${actual_remote}" in
  "${expected_repo}"|https://github.com/sounio-lang/sounio|git@github.com:sounio-lang/sounio.git) ;;
  *) echo "BLOCKED: unofficial Sounio remote" >&2; exit 2 ;;
esac
[[ -z "$(git -C "${SOUNIO_REPO}" status --porcelain)" ]] || {
  echo "BLOCKED: pinned Sounio checkout is dirty" >&2
  exit 2
}

"${atlas_root}/scripts/generate_dinucleotide_cases.rb" \
  "${fixture_dir}/parameters.json" "${fixture_dir}/case_templates.tsv" "${temp_dir}/cases.tsv"
cmp "${fixture_dir}/cases.tsv" "${temp_dir}/cases.tsv"

readonly instance="${SOUNIO_LIMA_INSTANCE:-souc-linux}"
readonly source_sha="$(sha256_file "${source_file}")"
readonly guest_root="/tmp/dosa-dinucleotide-${source_sha:0:12}-$$"
limactl shell "${instance}" -- mkdir -p "${guest_root}"
limactl copy -y --backend=scp "${source_file}" "${instance}:${guest_root}/fixture.sio"
limactl copy -y --backend=scp "${fixture_dir}/cases.tsv" "${instance}:${guest_root}/cases.tsv"
limactl copy -y --backend=scp "${fixture_dir}/invalid_cases.tsv" "${instance}:${guest_root}/invalid.tsv"

limactl shell "${instance}" -- bash -s -- "${SOUNIO_REPO}" "${guest_root}" <<'SOUNIO_RUN'
set -euo pipefail
repo="$1"
root="$2"
cd "${repo}"
"${repo}/bin/souc" check "${root}/fixture.sio" --science-boundary off
"${repo}/bin/souc" compile "${root}/fixture.sio" -o "${root}/fixture.elf" --science-boundary off
"${root}/fixture.elf" "${root}/cases.tsv" > "${root}/run1.jsonl"
"${root}/fixture.elf" "${root}/cases.tsv" > "${root}/run2.jsonl"
cmp "${root}/run1.jsonl" "${root}/run2.jsonl"
test "$(wc -l < "${root}/run1.jsonl")" -eq 64
set +e
"${root}/fixture.elf" "${root}/invalid.tsv" > "${root}/invalid.out"
invalid_rc=$?
set -e
test "${invalid_rc}" -eq 12
test ! -s "${root}/invalid.out"
SOUNIO_RUN

limactl copy -y --backend=scp "${instance}:${guest_root}/run1.jsonl" "${temp_dir}/sounio.jsonl"
julia --startup-file=no "${atlas_root}/julia/scripts/validate_dinucleotide_null.jl" \
  "${fixture_dir}/parameters.json" "${fixture_dir}/cases.tsv" "${temp_dir}/sounio.jsonl"

cp "${temp_dir}/sounio.jsonl" "${temp_dir}/perturbed.jsonl"
ruby -e 'p=ARGV[0]; s=File.read(p); at=s.index(%q{"sequence":"}); abort "sequence marker missing" unless at; at += 13; s[at] = s[at] == "A" ? "C" : "A"; File.write(p,s)' "${temp_dir}/perturbed.jsonl"
set +e
julia --startup-file=no "${atlas_root}/julia/scripts/validate_dinucleotide_null.jl" \
  "${fixture_dir}/parameters.json" "${fixture_dir}/cases.tsv" "${temp_dir}/perturbed.jsonl" \
  >"${temp_dir}/perturb.log" 2>&1
perturb_rc=$?
set -e
[[ "${perturb_rc}" -ne 0 ]] || { echo "validator accepted a perturbed draw" >&2; exit 1; }

echo "sounio_repository=${expected_repo}"
echo "sounio_commit=${actual_commit}"
echo "sounio_source_sha256=${source_sha}"
echo "parameters_sha256=$(sha256_file "${fixture_dir}/parameters.json")"
echo "cases_sha256=$(sha256_file "${fixture_dir}/cases.tsv")"
echo "artifact_sha256=$(sha256_file "${temp_dir}/sounio.jsonl")"
echo "DINUCLEOTIDE_NULL_DIFFERENTIAL_PASS cases=8 replicates=8 draws=64 tolerance=0"
limactl shell "${instance}" -- rm -r "${guest_root}"
