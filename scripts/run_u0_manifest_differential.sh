#!/usr/bin/env bash
# Execute the strict U0 work-manifest contract in pinned upstream Sounio, then
# independently re-read source FASTA bytes and compare the terminal artifact in
# Base-only Julia.  This is an executable capability boundary, not a U0 PASS.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/sounio.lock.json"
source_file="$atlas_root/sounio/src/u0_manifest_fixture.sio"
fixture_dir="$atlas_root/data/fixtures/u0_manifest"
manifest="$fixture_dir/u0_manifest.tsv"
golden="$fixture_dir/u0_expected_terminal.tsv"
julia_bin="${JULIA_BIN:-julia}"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-manifest.XXXXXX")"
trap 'rm -rf "$temp_root"' EXIT

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "BLOCKED: no SHA-256 utility is available" >&2
    return 2
  fi
}

blocked() {
  echo "BLOCKED: $*" >&2
  exit 2
}

[[ -n "${SOUNIO_REPO:-}" ]] || blocked "set SOUNIO_REPO to the official sounio-lang/sounio checkout"
git -C "$SOUNIO_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || blocked "unusable SOUNIO_REPO: $SOUNIO_REPO"
[[ -x "$SOUNIO_REPO/bin/souc" ]] || blocked "Sounio launcher is not executable: $SOUNIO_REPO/bin/souc"
command -v "$julia_bin" >/dev/null 2>&1 || blocked "Julia validator is unavailable: $julia_bin"

expected_repo="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("repository")' "$lock_file")"
expected_commit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("commit")' "$lock_file")"
actual_remote="$(git -C "$SOUNIO_REPO" remote get-url origin)"
actual_commit="$(git -C "$SOUNIO_REPO" rev-parse HEAD)"
case "$actual_remote" in
  "$expected_repo"|https://github.com/sounio-lang/sounio|git@github.com:sounio-lang/sounio.git) ;;
  *) blocked "Sounio remote is not official: $actual_remote" ;;
esac
[[ "$actual_commit" == "$expected_commit" ]] || blocked "Sounio pin drift: expected=$expected_commit actual=$actual_commit"
[[ -z "$(git -C "$SOUNIO_REPO" status --porcelain)" ]] || blocked "pinned Sounio checkout is dirty"

source_sha="$(sha256_file "$source_file")"
elf_name="dosa-u0-manifest-${expected_commit:0:12}-${source_sha:0:12}.elf"
local_elf="$temp_root/$elf_name"
guest_root="/tmp/dosa-u0-manifest-${expected_commit:0:12}-${source_sha:0:12}"
guest_source="$guest_root/u0_manifest_fixture.sio"
guest_elf="$guest_root/$elf_name"

echo "sounio_repository=$expected_repo"
echo "sounio_commit=$actual_commit"
echo "sounio_launcher_sha256=$(sha256_file "$SOUNIO_REPO/bin/souc")"
echo "sounio_u0_source_sha256=$source_sha"
echo "evidence_scope=fixture"
echo "u0_gate_status=BLOCKED"

if [[ -n "${SOUNIO_LIMA_INSTANCE:-}" ]]; then
  command -v limactl >/dev/null 2>&1 || blocked "limactl unavailable for $SOUNIO_LIMA_INSTANCE"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_root"
  limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_source"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- bash -s -- "$SOUNIO_REPO" "$guest_source" "$guest_elf" <<'SOUNIO_BUILD'
set -euo pipefail
repo="$1"
source_file="$2"
output="$3"
cd "$repo"
"$repo/bin/souc" --version >&2
"$repo/bin/souc" check "$source_file" --science-boundary off >&2
"$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off >&2
sha256sum "$output" | awk '{print "sounio_u0_executable_sha256=" $1}' >&2
SOUNIO_BUILD

  run_case() {
    local input="$1"
    local output="$2"
    shift 2
    local guest_input="$guest_root/$(basename "$input")"
    limactl copy -y --backend=scp "$input" "$SOUNIO_LIMA_INSTANCE:$guest_input" >/dev/null
    if limactl shell "$SOUNIO_LIMA_INSTANCE" -- "$guest_elf" "$guest_input" "$@" >"$output"; then
      return 0
    else
      return $?
    fi
  }
else
  (
    cd "$SOUNIO_REPO"
    "$SOUNIO_REPO/bin/souc" --version >&2
    "$SOUNIO_REPO/bin/souc" check "$source_file" --science-boundary off >&2
    "$SOUNIO_REPO/bin/souc" compile "$source_file" -o "$local_elf" --science-boundary off >&2
  )
  echo "sounio_u0_executable_sha256=$(sha256_file "$local_elf")" >&2
  run_case() {
    local input="$1"
    local output="$2"
    shift 2
    if "$local_elf" "$input" "$@" >"$output"; then
      return 0
    else
      return $?
    fi
  }
fi

artifact="$temp_root/u0-terminal.tsv"
run_case "$manifest" "$artifact"
cmp "$golden" "$artifact"
"$julia_bin" --startup-file=no "$atlas_root/julia/scripts/validate_u0_manifest.jl" "$manifest" "$artifact"

resume_artifact="$temp_root/u0-resume.tsv"
resume_expected="$temp_root/u0-resume-expected.tsv"
{ head -n 1 "$golden"; tail -n +4 "$golden"; } >"$resume_expected"
run_case "$manifest" "$resume_artifact" "NC_000001.1@100"
cmp "$resume_expected" "$resume_artifact"
"$julia_bin" --startup-file=no "$atlas_root/julia/scripts/validate_u0_manifest.jl" \
  "$manifest" "$resume_artifact" "NC_000001.1@100"

for name in invalid_scale_order invalid_stride invalid_path invalid_duplicate_work_unit; do
  output="$temp_root/$name.tsv"
  set +e
  run_case "$fixture_dir/$name.tsv" "$output"
  rc=$?
  set -e
  [[ "$rc" -eq 12 ]] || { echo "FAIL: $name expected Sounio rc=12, got $rc" >&2; exit 1; }
  [[ ! -s "$output" ]] || { echo "FAIL: $name emitted bytes before structural refusal" >&2; exit 1; }
done

# SHA-256 is intentionally outside the pinned Sounio runtime.  A syntactically
# valid but false digest must cross the structural producer boundary and then
# be rejected by Julia's independent byte-level source verification.
invalid_sha_artifact="$temp_root/invalid-sha-terminal.tsv"
run_case "$fixture_dir/invalid_sha.tsv" "$invalid_sha_artifact"
set +e
invalid_sha_log="$temp_root/invalid-sha-julia.log"
"$julia_bin" --startup-file=no "$atlas_root/julia/scripts/validate_u0_manifest.jl" \
  "$fixture_dir/invalid_sha.tsv" "$invalid_sha_artifact" >"$invalid_sha_log" 2>&1
invalid_sha_rc=$?
set -e
[[ "$invalid_sha_rc" -ne 0 ]] || { echo "FAIL: Julia accepted a false source-file SHA-256" >&2; exit 1; }
grep -q 'source file SHA-256 mismatch' "$invalid_sha_log"

echo "sounio_u0_artifact_sha256=$(sha256_file "$artifact")"
echo "sounio_u0_resume_artifact_sha256=$(sha256_file "$resume_artifact")"
echo "U0_MANIFEST_DIFFERENTIAL_FIXTURE_PASS work_units=8 invalid_cases=5 resume_suffix=6 tolerance=0"
echo "U0_MANIFEST_EXECUTOR_BOUND=false"
echo "U0_GATE_PASS=false"
