#!/usr/bin/env bash
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/sounio.lock.json"
source_file="$atlas_root/sounio/src/fasta_stream_fixture.sio"
fixture_dir="$atlas_root/data/fixtures/fasta"
fixture_names=(
  valid_multi_record.fa
  invalid_symbol.fa
  sequence_before_header.fa
  empty_header.fa
  empty_sequence.fa
  no_records.fa
)
fixture_rcs=(0 6 3 4 5 7)

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

if [[ -z "${SOUNIO_REPO:-}" ]]; then
  echo "BLOCKED: set SOUNIO_REPO to a checkout of the official sounio-lang/sounio repository" >&2
  exit 2
fi

if [[ ! -d "$SOUNIO_REPO/.git" || ! -x "$SOUNIO_REPO/bin/souc" ]]; then
  echo "BLOCKED: SOUNIO_REPO is not a usable Sounio checkout: $SOUNIO_REPO" >&2
  exit 2
fi

expected_repo="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("repository")' "$lock_file")"
expected_commit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("commit")' "$lock_file")"
actual_remote="$(git -C "$SOUNIO_REPO" remote get-url origin)"
actual_commit="$(git -C "$SOUNIO_REPO" rev-parse HEAD)"
source_sha256="$(sha256_file "$source_file")"

case "$actual_remote" in
  "$expected_repo"|https://github.com/sounio-lang/sounio|git@github.com:sounio-lang/sounio.git) ;;
  *)
    echo "BLOCKED: Sounio remote is not the official repository: $actual_remote" >&2
    exit 2
    ;;
esac

if [[ "$actual_commit" != "$expected_commit" ]]; then
  echo "BLOCKED: Sounio checkout does not match the pinned commit" >&2
  echo "expected=$expected_commit" >&2
  echo "actual=$actual_commit" >&2
  exit 2
fi

if [[ -n "$(git -C "$SOUNIO_REPO" status --porcelain)" ]]; then
  echo "BLOCKED: pinned Sounio checkout is dirty" >&2
  exit 2
fi

echo "sounio_repository=$expected_repo"
echo "sounio_commit=$actual_commit"
echo "sounio_launcher_sha256=$(sha256_file "$SOUNIO_REPO/bin/souc")"
echo "sounio_fasta_source_sha256=$source_sha256"
for name in "${fixture_names[@]}"; do
  echo "sounio_fasta_input name=$name sha256=$(sha256_file "$fixture_dir/$name")"
done

run_cases() {
  local executable="$1"
  local inputs="$2"
  local i name expected actual output

  for ((i = 0; i < ${#fixture_names[@]}; i++)); do
    name="${fixture_names[$i]}"
    expected="${fixture_rcs[$i]}"
    set +e
    output="$("$executable" "$inputs/$name" 2>&1)"
    actual=$?
    set -e

    echo "DOSA_FASTA_CASE name=${name%.fa} expected_rc=$expected actual_rc=$actual"
    printf '%s\n' "$output"
    if [[ "$actual" -ne "$expected" ]]; then
      echo "Fasta fixture exit mismatch for $name" >&2
      return 1
    fi
    if [[ "$expected" -eq 0 ]]; then
      grep -q '^DOSA_SOUNIO_FASTA_STREAM_OK ' <<<"$output"
    else
      grep -q '^DOSA_FASTA_ERROR ' <<<"$output"
    fi
  done
}

run_native_fixture() {
  local repo="$1"
  local source="$2"
  local inputs="$3"
  local output="/tmp/dosa-fasta-fixture-${expected_commit:0:12}-${source_sha256:0:12}.elf"

  cd "$repo"
  "$repo/bin/souc" --version
  echo "science_boundary=off (streaming executable specification; not a release receipt)"
  "$repo/bin/souc" check "$source" --science-boundary off
  "$repo/bin/souc" compile "$source" -o "$output" --science-boundary off
  echo "fasta_fixture_executable_sha256=$(sha256_file "$output")"
  run_cases "$output" "$inputs"
}

if [[ -n "${SOUNIO_LIMA_INSTANCE:-}" ]]; then
  if ! command -v limactl >/dev/null 2>&1; then
    echo "BLOCKED: limactl is unavailable for SOUNIO_LIMA_INSTANCE=$SOUNIO_LIMA_INSTANCE" >&2
    exit 2
  fi

  guest_root="/tmp/dosa-fasta-fixture-${source_sha256:0:12}"
  guest_source="$guest_root/fasta_stream_fixture.sio"
  guest_inputs="$guest_root/inputs"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs"
  limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_source"
  limactl copy -y --backend=scp "$fixture_dir"/*.fa "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"

  limactl shell "$SOUNIO_LIMA_INSTANCE" -- bash -s -- \
    "$SOUNIO_REPO" "$guest_source" "$guest_inputs" "${expected_commit:0:12}" "${source_sha256:0:12}" <<'SOUNIO_LINUX_RUNNER'
set -euo pipefail
repo="$1"
source_file="$2"
fixture_dir="$3"
commit_short="$4"
source_short="$5"
output="/tmp/dosa-fasta-fixture-${commit_short}-${source_short}.elf"
fixture_names=(
  valid_multi_record.fa
  invalid_symbol.fa
  sequence_before_header.fa
  empty_header.fa
  empty_sequence.fa
  no_records.fa
)
fixture_rcs=(0 6 3 4 5 7)

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (streaming executable specification; not a release receipt)"
"$repo/bin/souc" check "$source_file" --science-boundary off
"$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
echo "fasta_fixture_executable_sha256=$(sha256sum "$output" | awk '{print $1}')"

for ((i = 0; i < ${#fixture_names[@]}; i++)); do
  name="${fixture_names[$i]}"
  expected="${fixture_rcs[$i]}"
  set +e
  case_output="$("$output" "$fixture_dir/$name" 2>&1)"
  actual=$?
  set -e

  echo "DOSA_FASTA_CASE name=${name%.fa} expected_rc=$expected actual_rc=$actual"
  printf '%s\n' "$case_output"
  if [[ "$actual" -ne "$expected" ]]; then
    echo "Fasta fixture exit mismatch for $name" >&2
    exit 1
  fi
  if [[ "$expected" -eq 0 ]]; then
    grep -q '^DOSA_SOUNIO_FASTA_STREAM_OK ' <<<"$case_output"
  else
    grep -q '^DOSA_FASTA_ERROR ' <<<"$case_output"
  fi
done
SOUNIO_LINUX_RUNNER
else
  run_native_fixture "$SOUNIO_REPO" "$source_file" "$fixture_dir"
fi
