#!/usr/bin/env bash
# Pinned-Sounio runner for the non-scientific Euler/Wilson scale fixture.
#
# This tests a dedicated 16/100/500/1000-base capacity probe only.  It does
# not create a U0 payload, receipt, source freeze, or promotion evidence.
set -euo pipefail

readonly atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly lock_file="${atlas_root}/toolchains/sounio.lock.json"
readonly source_file="${atlas_root}/sounio/src/u0_dinucleotide_scale_fixture.sio"
readonly fixture_dir="${atlas_root}/data/fixtures/u0_dinucleotide_scale"
readonly parameters_file="${atlas_root}/data/v3/u0_parameters.json"
readonly validator="${atlas_root}/julia/scripts/validate_u0_dinucleotide_scale_fixture.jl"
readonly profile_validator="${atlas_root}/julia/scripts/validate_u0_window_profile_fixture.jl"
readonly structure_validator="${atlas_root}/scripts/validate_u0_window_profile_fixture.py"
readonly schema_dir="${atlas_root}/schemas"
readonly temp_dir="$(mktemp -d)"
readonly julia_bin="${JULIA_BIN:-julia}"
readonly instance="${SOUNIO_LIMA_INSTANCE:-}"
guest_root=""

cleanup() {
  if [[ -n "${guest_root}" ]] && command -v limactl >/dev/null 2>&1; then
    limactl shell "${instance}" -- rm -r "${guest_root}" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${temp_dir}"
}
trap cleanup EXIT

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
for required in ruby python3; do
  command -v "${required}" >/dev/null 2>&1 || { echo "BLOCKED: missing ${required}" >&2; exit 2; }
done
python3 -c 'import importlib.metadata; assert importlib.metadata.version("jsonschema") == "4.26.0"' \
  >/dev/null 2>&1 || { echo "BLOCKED: exact jsonschema==4.26.0 is required for profile validation" >&2; exit 2; }
command -v "${julia_bin}" >/dev/null 2>&1 || { echo "BLOCKED: missing Julia validator: ${julia_bin}" >&2; exit 2; }
git -C "${SOUNIO_REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -x "${SOUNIO_REPO}/bin/souc" ]] || {
  echo "BLOCKED: invalid Sounio checkout" >&2
  exit 2
}
[[ -s "${validator}" ]] || { echo "BLOCKED: missing independent Julia scale validator" >&2; exit 2; }
[[ -s "${profile_validator}" ]] || { echo "BLOCKED: missing independent Julia profile validator" >&2; exit 2; }
[[ -s "${structure_validator}" ]] || { echo "BLOCKED: missing profile structure validator" >&2; exit 2; }

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

ruby "${atlas_root}/scripts/generate_u0_dinucleotide_scale_cases.rb" \
  "${parameters_file}" "${temp_dir}/cases.tsv"
cmp "${fixture_dir}/cases.tsv" "${temp_dir}/cases.tsv"

# The checked negative fails during the grammar pass.  This generated negative
# reaches the fourth case of the full dry run before failing on a non-ACGT
# byte, proving that earlier cases still cannot leak partial stdout.
ruby -e '
  lines = File.binread(ARGV[0]).lines
  fields = lines.fetch(-1).chomp.split("\t", -1)
  fields[6] = "N" + fields.fetch(6)[1..]
  lines[-1] = fields.join("\t") + "\n"
  File.binwrite(ARGV[1], lines.join)
' "${fixture_dir}/cases.tsv" "${temp_dir}/invalid-late.tsv"
ruby -e '
  lines = File.binread(ARGV[0]).lines
  lines[1..].each do |line|
    fields = line.chomp.split("\t", -1)
    fields[1] = "0" * 64
    line.replace(fields.join("\t") + "\n")
  end
  File.binwrite(ARGV[1], lines.join)
' "${fixture_dir}/cases.tsv" "${temp_dir}/invalid-parameters.tsv"
ruby -e 'bytes = File.binread(ARGV[0]); File.binwrite(ARGV[1], bytes.sub(/\n\z/, ""))' \
  "${fixture_dir}/cases.tsv" "${temp_dir}/invalid-missing-lf.tsv"
ruby -e 'File.binwrite(ARGV[1], File.binread(ARGV[0]).gsub("\n", "\r\n"))' \
  "${fixture_dir}/cases.tsv" "${temp_dir}/invalid-crlf.tsv"

readonly source_sha="$(sha256_file "${source_file}")"
artifact="${temp_dir}/sounio.jsonl"
profile_artifact="${temp_dir}/profiles.jsonl"

if [[ -n "${instance}" ]]; then
  command -v limactl >/dev/null 2>&1 || { echo "BLOCKED: limactl is unavailable for ${instance}" >&2; exit 2; }
  guest_root="/tmp/dosa-u0-dinuc-scale-${source_sha:0:12}-$$"
  limactl shell "${instance}" -- mkdir -p "${guest_root}"
  limactl copy -y --backend=scp "${source_file}" "${instance}:${guest_root}/fixture.sio"
  limactl copy -y --backend=scp "${fixture_dir}/cases.tsv" "${instance}:${guest_root}/cases.tsv"
  limactl copy -y --backend=scp "${fixture_dir}/invalid_replicates.tsv" "${instance}:${guest_root}/invalid-grammar.tsv"
  limactl copy -y --backend=scp "${temp_dir}/invalid-late.tsv" "${instance}:${guest_root}/invalid-late.tsv"
  limactl copy -y --backend=scp "${temp_dir}/invalid-parameters.tsv" "${instance}:${guest_root}/invalid-parameters.tsv"
  limactl copy -y --backend=scp "${temp_dir}/invalid-missing-lf.tsv" "${instance}:${guest_root}/invalid-missing-lf.tsv"
  limactl copy -y --backend=scp "${temp_dir}/invalid-crlf.tsv" "${instance}:${guest_root}/invalid-crlf.tsv"

  limactl shell "${instance}" -- bash -s -- "${SOUNIO_REPO}" "${guest_root}" <<'SOUNIO_RUN'
set -euo pipefail
repo="$1"
root="$2"
cd "${repo}"
"${repo}/bin/souc" check "${root}/fixture.sio" --science-boundary off
"${repo}/bin/souc" compile "${root}/fixture.sio" -o "${root}/fixture.elf" --science-boundary off
echo "sounio_executable_sha256=$(sha256sum "${root}/fixture.elf" | awk '{print $1}')"
"${root}/fixture.elf" "${root}/cases.tsv" > "${root}/run1.jsonl"
"${root}/fixture.elf" "${root}/cases.tsv" > "${root}/run2.jsonl"
cmp "${root}/run1.jsonl" "${root}/run2.jsonl"
test "$(wc -l < "${root}/run1.jsonl")" -eq 4000
"${root}/fixture.elf" "${root}/cases.tsv" --profiles > "${root}/profiles1.jsonl"
"${root}/fixture.elf" "${root}/cases.tsv" --profiles > "${root}/profiles2.jsonl"
cmp "${root}/profiles1.jsonl" "${root}/profiles2.jsonl"
test "$(wc -l < "${root}/profiles1.jsonl")" -eq 4
for invalid in invalid-grammar invalid-late invalid-parameters invalid-missing-lf invalid-crlf; do
  set +e
  "${root}/fixture.elf" "${root}/${invalid}.tsv" > "${root}/${invalid}.out"
  invalid_rc=$?
  set -e
  test "${invalid_rc}" -eq 12
  test ! -s "${root}/${invalid}.out"
done
SOUNIO_RUN
  limactl copy -y --backend=scp "${instance}:${guest_root}/run1.jsonl" "${artifact}"
  limactl copy -y --backend=scp "${instance}:${guest_root}/profiles1.jsonl" "${profile_artifact}"
else
  readonly executable="${temp_dir}/fixture.elf"
  (
    cd "${SOUNIO_REPO}"
    "${SOUNIO_REPO}/bin/souc" check "${source_file}" --science-boundary off
    "${SOUNIO_REPO}/bin/souc" compile "${source_file}" -o "${executable}" --science-boundary off
  )
  echo "sounio_executable_sha256=$(sha256_file "${executable}")"
  "${executable}" "${fixture_dir}/cases.tsv" > "${artifact}"
  "${executable}" "${fixture_dir}/cases.tsv" > "${temp_dir}/run2.jsonl"
  cmp "${artifact}" "${temp_dir}/run2.jsonl"
  [[ "$(wc -l < "${artifact}")" -eq 4000 ]]
  "${executable}" "${fixture_dir}/cases.tsv" --profiles > "${profile_artifact}"
  "${executable}" "${fixture_dir}/cases.tsv" --profiles > "${temp_dir}/profiles2.jsonl"
  cmp "${profile_artifact}" "${temp_dir}/profiles2.jsonl"
  [[ "$(wc -l < "${profile_artifact}")" -eq 4 ]]
  for invalid in \
    "${fixture_dir}/invalid_replicates.tsv" \
    "${temp_dir}/invalid-late.tsv" \
    "${temp_dir}/invalid-parameters.tsv" \
    "${temp_dir}/invalid-missing-lf.tsv" \
    "${temp_dir}/invalid-crlf.tsv"; do
    set +e
    "${executable}" "${invalid}" > "${temp_dir}/invalid.out"
    invalid_rc=$?
    set -e
    [[ "${invalid_rc}" -eq 12 ]]
    [[ ! -s "${temp_dir}/invalid.out" ]]
  done
fi

"${julia_bin}" --startup-file=no "${validator}" \
  "${parameters_file}" "${fixture_dir}/cases.tsv" "${artifact}"
python3 "${structure_validator}" "${profile_artifact}" --schema-dir "${schema_dir}"
"${julia_bin}" --startup-file=no "${profile_validator}" \
  "${parameters_file}" "${fixture_dir}/cases.tsv" "${profile_artifact}"

echo "sounio_repository=${expected_repo}"
echo "sounio_commit=${actual_commit}"
echo "sounio_launcher_sha256=$(sha256_file "${SOUNIO_REPO}/bin/souc")"
echo "sounio_source_sha256=${source_sha}"
echo "parameters_sha256=$(sha256_file "${parameters_file}")"
echo "cases_sha256=$(sha256_file "${fixture_dir}/cases.tsv")"
echo "artifact_sha256=$(sha256_file "${artifact}")"
echo "profile_artifact_sha256=$(sha256_file "${profile_artifact}")"
echo "U0_SCALE_INVALID_REFUSAL_PASS cases=5 rc=12 bytes=0"
echo "U0_DINUCLEOTIDE_SCALE_FIXTURE_PASS cases=4 scales=4 replicates=1000 draws=4000 tolerance=0"
echo "U0_WINDOW_PROFILE_FIXTURE_PASS rows=4 metrics=17 null_replicates=1000 tolerance=0"
