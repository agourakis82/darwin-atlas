#!/usr/bin/env bash
# Fail-closed complete-replicon engineering smoke.
#
# Runs the official pinned Sounio build of sounio/src/fasta_stream_fixture.sio
# in --pipeline (optimized k-mer kernel) on the smallest complete replicon of
# the frozen mini cohort (NC_002127.1, 3,306 bp, 207 windows at 16/16),
# persists and hashes the JSONL artifact, then requires the independent
# Base-only Julia validator to reproduce every line byte for byte.
#
# This is an engineering smoke at complete-replicon scope, NOT the pilot run
# and NOT a release receipt. Dual-kernel (optimized vs reference) byte
# equivalence remains gated at fixture scope by run_sounio_mini_pipeline.sh;
# here the optimized kernel runs twice (determinism) and the independent
# check is the Julia recomputation. Absence of either implementation is a
# failure, never a fallback.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$atlas_root/sounio/src/fasta_stream_fixture.sio"
fixture_dir="$atlas_root/data/fixtures/cohort_smoke"
lock_file="$atlas_root/toolchains/sounio.lock.json"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dosa-cohort-smoke.XXXXXX")"
flat_dir="$work_dir/params"
mkdir -p "$flat_dir"

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

# Render the canonical parameter JSON into the strict flat key=value form the
# executable accepts (identical rendering to run_sounio_mini_pipeline.sh).
render_flat() {
  ruby -rjson -rdigest -e '
    raw = File.binread(ARGV[0])
    obj = JSON.parse(raw)
    abort "parameter artifact is not a JSON object: #{ARGV[0]}" unless obj.is_a?(Hash)
    lines = obj.map do |key, value|
      case value
      when true, false then "#{key}=#{value}"
      when Integer, Float, String then "#{key}=#{value}"
      else abort "non-scalar parameter value for key #{key.inspect} in #{ARGV[0]}"
      end
    end
    lines << "parameters_sha256=#{Digest::SHA256.hexdigest(raw)}"
    File.binwrite(ARGV[1], lines.join("\n") + "\n")
  ' "$1" "$2"
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
echo "sounio_smoke_source_sha256=$source_sha256"
for input in nc_002127_1.fa nc_002127_1_metadata.tsv parameters_k8.json; do
  echo "sounio_smoke_input name=$input sha256=$(sha256_file "$fixture_dir/$input")"
done

flat_path="$flat_dir/smoke_pOSAK1.flat"
render_flat "$fixture_dir/parameters_k8.json" "$flat_path"
echo "DOSA_PIPELINE_PARAMS name=smoke_pOSAK1 flat=$flat_path sha256=$(sha256_file "$fixture_dir/parameters_k8.json")"

guest_root="/tmp/dosa-cohort-smoke-${source_sha256:0:12}-$$"
guest_source="$guest_root/fasta_stream_fixture.sio"
guest_inputs="$guest_root/inputs"
guest_work="$guest_root/work"

limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs" "$guest_work"
limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_source"
limactl copy -y --backend=scp "$fixture_dir/nc_002127_1.fa" "$fixture_dir/nc_002127_1_metadata.tsv" "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"
limactl copy -y --backend=scp "$flat_path" "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"

limactl shell "$SOUNIO_LIMA_INSTANCE" -- bash -s -- \
  "$SOUNIO_REPO" "$guest_source" "$guest_inputs" "$guest_work" \
  "${expected_commit:0:12}" "${source_sha256:0:12}" "$$" <<'SOUNIO_LINUX_RUNNER'
set -euo pipefail
repo="$1"
source_file="$2"
inputs="$3"
work="$4"
commit_short="$5"
source_short="$6"
run_id="$7"
output="/tmp/dosa-cohort-smoke-${commit_short}-${source_short}-${run_id}.elf"

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (complete-replicon engineering smoke; not a release receipt)"
"$repo/bin/souc" check "$source_file" --science-boundary off
"$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
echo "smoke_executable_sha256=$(sha256sum "$output" | awk '{print $1}')"

opt1="$work/smoke_pOSAK1.opt1.jsonl"
opt2="$work/smoke_pOSAK1.opt2.jsonl"
start=$(date +%s)
"$output" --pipeline "$inputs/nc_002127_1.fa" "$inputs/nc_002127_1_metadata.tsv" "$inputs/smoke_pOSAK1.flat" > "$opt1"
end=$(date +%s)
echo "DOSA_PIPELINE_TIMING name=smoke_pOSAK1 opt_wall_seconds=$((end - start))"
"$output" --pipeline "$inputs/nc_002127_1.fa" "$inputs/nc_002127_1_metadata.tsv" "$inputs/smoke_pOSAK1.flat" > "$opt2"
sha1="$(sha256sum "$opt1" | awk '{print $1}')"
sha2="$(sha256sum "$opt2" | awk '{print $1}')"
if [[ "$sha1" != "$sha2" ]]; then
  echo "cohort smoke determinism failure: opt1=$sha1 opt2=$sha2" >&2
  exit 1
fi
echo "DOSA_PIPELINE_DETERMINISM name=smoke_pOSAK1 runs=2 sha256=$sha1"
cp "$opt1" "$work/smoke_pOSAK1.jsonl"
lines="$(wc -l < "$work/smoke_pOSAK1.jsonl" | tr -d ' ')"
if [[ "$lines" -ne 207 ]]; then
  echo "cohort smoke JSONL line count mismatch: expected 207, got $lines" >&2
  exit 1
fi
if grep -qvx '{.*}' "$work/smoke_pOSAK1.jsonl"; then
  echo "cohort smoke JSONL is contaminated by a non-JSON line" >&2
  exit 1
fi
echo "DOSA_PIPELINE_CASE name=smoke_pOSAK1 expected_rc=0 actual_rc=0"
SOUNIO_LINUX_RUNNER

limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_work/smoke_pOSAK1.jsonl" "$work_dir/smoke_pOSAK1.jsonl"
limactl shell "$SOUNIO_LIMA_INSTANCE" -- rm -rf "$guest_root"

lines="$(wc -l < "$work_dir/smoke_pOSAK1.jsonl" | tr -d ' ')"
sha="$(sha256_file "$work_dir/smoke_pOSAK1.jsonl")"
EXPECTED_JSONL_LINES="$lines" ruby -rjson -e '
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
    abort "JSONL line #{index + 1} has #{object.size} fields, expected 90" unless object.size == 90
  end
' "$work_dir/smoke_pOSAK1.jsonl"

echo "sounio_pipeline_jsonl_artifact_smoke_pOSAK1=$work_dir/smoke_pOSAK1.jsonl"
echo "sounio_pipeline_jsonl_lines_smoke_pOSAK1=$lines"
echo "sounio_pipeline_jsonl_sha256_smoke_pOSAK1=$sha"

if ! command -v julia >/dev/null 2>&1; then
  echo "BLOCKED: julia is unavailable; independent validation cannot run" >&2
  exit 2
fi

# The validator re-reads the runner log it is given; this script's stdout up
# to this point is that log. Emit it to a file for the validator.
log_file="$work_dir/smoke-runner.log"
# Recreate the log lines emitted so far (they went to stdout). The caller is
# expected to tee; to stay self-contained we re-announce the persisted facts.
{
  echo "DOSA_PIPELINE_PARAMS name=smoke_pOSAK1 flat=$flat_path sha256=$(sha256_file "$fixture_dir/parameters_k8.json")"
  echo "DOSA_PIPELINE_CASE name=smoke_pOSAK1 expected_rc=0 actual_rc=0"
  echo "sounio_pipeline_jsonl_artifact_smoke_pOSAK1=$work_dir/smoke_pOSAK1.jsonl"
  echo "sounio_pipeline_jsonl_lines_smoke_pOSAK1=$lines"
  echo "sounio_pipeline_jsonl_sha256_smoke_pOSAK1=$sha"
} > "$log_file"

julia --startup-file=no "$atlas_root/julia/scripts/validate_mini_pipeline.jl" \
  "$log_file" "$fixture_dir" cohort_smoke

echo "sounio_smoke_runner_log=$log_file"
echo "sounio_smoke_runner_log_sha256=$(sha256_file "$log_file")"
