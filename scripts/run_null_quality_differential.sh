#!/usr/bin/env bash
# Fail-closed differential runner for the Fase N null-generator quality gate.
#
# Compiles sounio/src/null_quality_fixture.sio with the pinned official
# Sounio build inside the Lima guest (x86_64), executes the frozen quality
# cases twice, requires byte-identical artifacts (determinism gate), then
# runs the independent standard-library-only Julia validator, which
# re-enumerates the exact null support, checks containment and full
# coverage, and applies a chi-square uniformity test with pre-declared
# alpha=1e-3 per case. Any missing gate (Sounio checkout, official remote,
# pinned commit, clean tree, frozen cases drift) blocks with exit 2; there
# is no fallback producer.
set -euo pipefail

readonly atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly lock_file="${atlas_root}/toolchains/sounio.lock.json"
readonly source_file="${atlas_root}/sounio/src/null_quality_fixture.sio"
readonly fixture_dir="${atlas_root}/data/fixtures/null_quality"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    command sha256sum "$1" | awk '{print $1}'
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
  *) echo "BLOCKED: unofficial Sounio remote" >&2 ;;
esac
[[ -z "$(git -C "${SOUNIO_REPO}" status --porcelain)" ]] || {
  echo "BLOCKED: pinned Sounio checkout is dirty" >&2
  exit 2
}

"${atlas_root}/scripts/generate_null_quality_cases.rb" \
  "${fixture_dir}/parameters.json" "${fixture_dir}/case_templates.tsv" "${temp_dir}/cases.tsv"
cmp "${fixture_dir}/cases.tsv" "${temp_dir}/cases.tsv"

readonly instance="${SOUNIO_LIMA_INSTANCE:-souc-linux}"
readonly source_sha="$(sha256_file "${source_file}")"
readonly guest_root="/tmp/dosa-null-quality-${source_sha:0:12}-$$"
limactl shell "${instance}" -- mkdir -p "${guest_root}"
limactl copy -y --backend=scp "${source_file}" "${instance}:${guest_root}/fixture.sio"
limactl copy -y --backend=scp "${fixture_dir}/cases.tsv" "${instance}:${guest_root}/cases.tsv"

limactl shell "${instance}" -- bash -s -- "${SOUNIO_REPO}" "${guest_root}" <<'SOUNIO_RUN'
set -euo pipefail
repo="$1"
root="$2"
cd "${repo}"
"${repo}/bin/souc" check "${root}/fixture.sio" --science-boundary off
"${repo}/bin/souc" compile "${root}/fixture.sio" -o "${root}/fixture.elf" --science-boundary off
echo "sounio_executable_sha256=$(sha256sum "${root}/fixture.elf" | awk '{print $1}')"
"${root}/fixture.elf" "${root}/cases.tsv" > "${root}/run1.txt"
"${root}/fixture.elf" "${root}/cases.tsv" > "${root}/run2.txt"
cmp "${root}/run1.txt" "${root}/run2.txt"
test "$(wc -l < "${root}/run1.txt")" -eq 284003
SOUNIO_RUN

limactl copy -y --backend=scp "${instance}:${guest_root}/run1.txt" "${temp_dir}/sounio.txt"
julia --startup-file=no "${atlas_root}/julia/scripts/validate_null_quality.jl" \
  "${fixture_dir}/cases.tsv" "${temp_dir}/sounio.txt"
if [[ -n "${NULL_QUALITY_ARTIFACT_OUT:-}" ]]; then
  cp "${temp_dir}/sounio.txt" "${NULL_QUALITY_ARTIFACT_OUT}"
fi

# Corruption gate: flipping one base in one persisted draw must be rejected
# by the independent validator.
cp "${temp_dir}/sounio.txt" "${temp_dir}/perturbed.txt"
ruby -e 'p=ARGV[0]; lines=File.readlines(p,chomp:true); i=lines.index{|l| l =~ /\A[ACGT]+\z/}; abort "no draw line found" unless i; s=lines[i]; s[0] = s[0] == "A" ? "C" : "A"; lines[i]=s; File.write(p, lines.join("\n") + "\n")' "${temp_dir}/perturbed.txt"
set +e
julia --startup-file=no "${atlas_root}/julia/scripts/validate_null_quality.jl" \
  "${fixture_dir}/cases.tsv" "${temp_dir}/perturbed.txt" \
  >"${temp_dir}/perturb.log" 2>&1
perturb_rc=$?
set -e
[[ "${perturb_rc}" -ne 0 ]] || { echo "validator accepted a perturbed draw" >&2; exit 1; }

echo "sounio_repository=${expected_repo}"
echo "sounio_commit=${actual_commit}"
echo "sounio_launcher_sha256=$(sha256_file "${SOUNIO_REPO}/bin/souc")"
echo "sounio_source_sha256=${source_sha}"
echo "parameters_sha256=$(sha256_file "${fixture_dir}/parameters.json")"
echo "cases_sha256=$(sha256_file "${fixture_dir}/cases.tsv")"
echo "artifact_sha256=$(sha256_file "${temp_dir}/sounio.txt")"
echo "NULL_QUALITY_DIFFERENTIAL_PASS cases=3 draws=284000 alpha=0.001 tolerance=exact-support"
limactl shell "${instance}" -- rm -r "${guest_root}"
