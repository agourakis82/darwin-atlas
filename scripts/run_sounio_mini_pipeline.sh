#!/usr/bin/env bash
# Fail-closed Sounio mini-pipeline runner.
#
# Runs the frozen FASTA + metadata fixtures through the pinned official Sounio
# build of sounio/src/fasta_stream_fixture.sio in --pipeline mode, persists the
# deterministic JSONL artifact, prints input/artifact SHA-256 evidence, and
# exercises the negative metadata fixtures. Any missing gate (Sounio checkout,
# official remote, pinned commit, clean tree) blocks with exit 2; there is no
# fallback producer.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/sounio.lock.json"
source_file="$atlas_root/sounio/src/fasta_stream_fixture.sio"
fixture_dir="$atlas_root/data/fixtures/mini_pipeline"
expected_jsonl_lines=12

case_names=(main metadata_invalid metadata_mismatch metadata_short)
case_metadata=(
  pipeline_metadata.tsv
  metadata_invalid.tsv
  metadata_mismatch.tsv
  metadata_short.tsv
)
case_rcs=(0 9 10 10)
case_errors=("" METADATA_INVALID METADATA_MISMATCH METADATA_MISMATCH)

artifact="$(mktemp "${TMPDIR:-/tmp}/dosa-sounio-mini-pipeline.jsonl.XXXXXX")"

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
echo "sounio_pipeline_source_sha256=$source_sha256"
echo "sounio_pipeline_input name=pipeline_fixture.fa sha256=$(sha256_file "$fixture_dir/pipeline_fixture.fa")"
for meta in "${case_metadata[@]}"; do
  echo "sounio_pipeline_input name=$meta sha256=$(sha256_file "$fixture_dir/$meta")"
done

check_main_artifact() {
  local path="$1"
  local lines
  lines="$(wc -l < "$path" | tr -d ' ')"
  if [[ "$lines" -ne "$expected_jsonl_lines" ]]; then
    echo "mini-pipeline JSONL line count mismatch: expected $expected_jsonl_lines, got $lines" >&2
    return 1
  fi
  if grep -qvx '{.*}' "$path"; then
    echo "mini-pipeline JSONL is contaminated by a non-JSON line" >&2
    return 1
  fi
  EXPECTED_JSONL_LINES="$expected_jsonl_lines" ruby -rjson -e '
    lines = File.readlines(ARGV[0], chomp: true)
    expected = Integer(ENV.fetch("EXPECTED_JSONL_LINES"))
    abort "expected #{expected} JSONL objects, got #{lines.size}" unless lines.size == expected
    lines.each_with_index do |line, index|
      begin
        object = JSON.parse(line)
      rescue JSON::ParserError => e
        abort "JSONL line #{index + 1} is not valid JSON: #{e.message}"
      end
      abort "JSONL line #{index + 1} is not a JSON object" unless object.is_a?(Hash)
      abort "JSONL line #{index + 1} has #{object.size} fields, expected 53" unless object.size == 53
    end
  ' "$path"
}

run_cases() {
  local executable="$1"
  local inputs="$2"
  local artifact_out="$3"
  local i name meta expected expected_error actual output

  for ((i = 0; i < ${#case_names[@]}; i++)); do
    name="${case_names[$i]}"
    meta="${case_metadata[$i]}"
    expected="${case_rcs[$i]}"
    expected_error="${case_errors[$i]}"
    set +e
    output="$("$executable" --pipeline "$inputs/pipeline_fixture.fa" "$inputs/$meta" 2>&1)"
    actual=$?
    set -e

    echo "DOSA_PIPELINE_CASE name=$name expected_rc=$expected actual_rc=$actual"
    if [[ "$actual" -ne "$expected" ]]; then
      printf '%s\n' "$output" >&2
      echo "mini-pipeline exit mismatch for $name" >&2
      return 1
    fi

    if [[ "$expected" -eq 0 ]]; then
      printf '%s\n' "$output" > "$artifact_out"
      check_main_artifact "$artifact_out"
    else
      grep -q "^DOSA_FASTA_ERROR code=$expected_error " <<<"$output"
      grep "^DOSA_FASTA_ERROR " <<<"$output"
      if grep -q '^DOSA_SOUNIO_FASTA_STREAM_OK ' <<<"$output"; then
        echo "negative mini-pipeline case $name emitted a success summary" >&2
        return 1
      fi
    fi
  done
}

run_native() {
  local repo="$1"
  local output="/tmp/dosa-mini-pipeline-${expected_commit:0:12}-${source_sha256:0:12}.elf"

  cd "$repo"
  "$repo/bin/souc" --version
  echo "science_boundary=off (streaming executable specification; not a release receipt)"
  "$repo/bin/souc" check "$source_file" --science-boundary off
  "$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
  echo "mini_pipeline_executable_sha256=$(sha256_file "$output")"
  run_cases "$output" "$fixture_dir" "$artifact"
}

if [[ -n "${SOUNIO_LIMA_INSTANCE:-}" ]]; then
  if ! command -v limactl >/dev/null 2>&1; then
    echo "BLOCKED: limactl is unavailable for SOUNIO_LIMA_INSTANCE=$SOUNIO_LIMA_INSTANCE" >&2
    exit 2
  fi

  guest_root="/tmp/dosa-mini-pipeline-${source_sha256:0:12}"
  guest_source="$guest_root/fasta_stream_fixture.sio"
  guest_inputs="$guest_root/inputs"
  guest_artifact="$guest_root/pipeline.jsonl"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs"
  limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_source"
  limactl copy -y --backend=scp "$fixture_dir"/pipeline_fixture.fa "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"
  limactl copy -y --backend=scp "$fixture_dir"/*.tsv "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"

  limactl shell "$SOUNIO_LIMA_INSTANCE" -- bash -s -- \
    "$SOUNIO_REPO" "$guest_source" "$guest_inputs" "$guest_artifact" \
    "${expected_commit:0:12}" "${source_sha256:0:12}" "$expected_jsonl_lines" <<'SOUNIO_LINUX_RUNNER'
set -euo pipefail
repo="$1"
source_file="$2"
fixture_dir="$3"
artifact_out="$4"
commit_short="$5"
source_short="$6"
expected_jsonl_lines="$7"
output="/tmp/dosa-mini-pipeline-${commit_short}-${source_short}.elf"
case_names=(main metadata_invalid metadata_mismatch metadata_short)
case_metadata=(
  pipeline_metadata.tsv
  metadata_invalid.tsv
  metadata_mismatch.tsv
  metadata_short.tsv
)
case_rcs=(0 9 10 10)
case_errors=("" METADATA_INVALID METADATA_MISMATCH METADATA_MISMATCH)

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (streaming executable specification; not a release receipt)"
"$repo/bin/souc" check "$source_file" --science-boundary off
"$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
echo "mini_pipeline_executable_sha256=$(sha256sum "$output" | awk '{print $1}')"

for ((i = 0; i < ${#case_names[@]}; i++)); do
  name="${case_names[$i]}"
  meta="${case_metadata[$i]}"
  expected="${case_rcs[$i]}"
  expected_error="${case_errors[$i]}"
  set +e
  case_output="$("$output" --pipeline "$fixture_dir/pipeline_fixture.fa" "$fixture_dir/$meta" 2>&1)"
  actual=$?
  set -e

  echo "DOSA_PIPELINE_CASE name=$name expected_rc=$expected actual_rc=$actual"
  if [[ "$actual" -ne "$expected" ]]; then
    printf '%s\n' "$case_output" >&2
    echo "mini-pipeline exit mismatch for $name" >&2
    exit 1
  fi

  if [[ "$expected" -eq 0 ]]; then
    printf '%s\n' "$case_output" > "$artifact_out"
    lines="$(wc -l < "$artifact_out" | tr -d ' ')"
    if [[ "$lines" -ne "$expected_jsonl_lines" ]]; then
      echo "mini-pipeline JSONL line count mismatch: expected $expected_jsonl_lines, got $lines" >&2
      exit 1
    fi
    if grep -qvx '{.*}' "$artifact_out"; then
      echo "mini-pipeline JSONL is contaminated by a non-JSON line" >&2
      exit 1
    fi
  else
    grep -q "^DOSA_FASTA_ERROR code=$expected_error " <<<"$case_output"
    grep "^DOSA_FASTA_ERROR " <<<"$case_output"
    if grep -q '^DOSA_SOUNIO_FASTA_STREAM_OK ' <<<"$case_output"; then
      echo "negative mini-pipeline case $name emitted a success summary" >&2
      exit 1
    fi
  fi
done
SOUNIO_LINUX_RUNNER

  limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_artifact" "$artifact"
  check_main_artifact "$artifact"
else
  run_native "$SOUNIO_REPO"
fi

echo "sounio_pipeline_jsonl_artifact=$artifact"
echo "sounio_pipeline_jsonl_lines=$(wc -l < "$artifact" | tr -d ' ')"
echo "sounio_pipeline_jsonl_sha256=$(sha256_file "$artifact")"
