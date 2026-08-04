#!/usr/bin/env bash
# Fail-closed Sounio mini-pipeline runner.
#
# Runs the frozen FASTA + metadata + parameter fixtures through the pinned
# official Sounio build of sounio/src/fasta_stream_fixture.sio in --pipeline
# (optimized k-mer kernel) and --pipeline-reference (simple reference kernel)
# modes, requires byte-identical JSONL across repeated optimized runs and the
# reference run, persists the deterministic JSONL artifacts, prints
# input/artifact SHA-256 evidence, and exercises the negative metadata and
# parameter fixtures. Any missing gate (Sounio checkout, official remote,
# pinned commit, clean tree) blocks with exit 2; there is no fallback
# producer.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/sounio.lock.json"
source_file="$atlas_root/sounio/src/fasta_stream_fixture.sio"
fixture_dir="$atlas_root/data/fixtures/mini_pipeline"

# Valid cases: name fasta metadata params_json expected_lines
valid_cases=(
  "main pipeline_fixture.fa pipeline_metadata.tsv parameters_k4.json 12"
  "k8 pipeline_k8_fixture.fa pipeline_k8_metadata.tsv parameters_k8.json 84"
  "null_k4 pipeline_fixture.fa pipeline_metadata.tsv parameters_null_k4.json 12"
  "null_k8 pipeline_k8_fixture.fa pipeline_k8_metadata.tsv parameters_null_k8.json 84"
  "dinucleotide_k4 pipeline_fixture.fa pipeline_metadata.tsv parameters_dinucleotide_k4.json 12"
  "dinucleotide_k8 pipeline_k8_fixture.fa pipeline_k8_metadata.tsv parameters_dinucleotide_k8.json 84"
)
# Negative cases: name metadata params_json expected_rc expected_error
# (all run against pipeline_fixture.fa; parameters are validated first)
negative_cases=(
  "metadata_invalid metadata_invalid.tsv parameters_k4.json 9 METADATA_INVALID"
  "metadata_mismatch metadata_mismatch.tsv parameters_k4.json 10 METADATA_MISMATCH"
  "metadata_short metadata_short.tsv parameters_k4.json 10 METADATA_MISMATCH"
  "param_window_size_zero pipeline_metadata.tsv params_invalid/window_size_zero.json 11 PARAM_INVALID"
  "param_stride_zero pipeline_metadata.tsv params_invalid/stride_zero.json 11 PARAM_INVALID"
  "param_stride_mismatch pipeline_metadata.tsv params_invalid/stride_mismatch.json 11 PARAM_INVALID"
  "param_k_min_two pipeline_metadata.tsv params_invalid/k_min_two.json 11 PARAM_INVALID"
  "param_k_max_nine pipeline_metadata.tsv params_invalid/k_max_nine.json 11 PARAM_INVALID"
  "param_k_max_above_window pipeline_metadata.tsv params_invalid/k_max_above_window.json 11 PARAM_INVALID"
  "param_unknown_policy pipeline_metadata.tsv params_invalid/unknown_policy.json 11 PARAM_INVALID"
  "param_extra_field pipeline_metadata.tsv params_invalid/extra_field.json 11 PARAM_INVALID"
  "param_null_model_unknown pipeline_metadata.tsv params_invalid/null_model_unknown.json 11 PARAM_INVALID"
  "param_null_replicates_mismatch pipeline_metadata.tsv params_invalid/null_replicates_mismatch.json 11 PARAM_INVALID"
)

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dosa-sounio-mini-pipeline.XXXXXX")"
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
# executable accepts: top-level keys in file order, scalar values only,
# then parameters_sha256 bound to the canonical JSON bytes. Domain validation
# is deliberately NOT done here; the Sounio parser is the single source of
# truth and the Julia validator independently re-derives every rejection.
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
echo "sounio_pipeline_source_sha256=$source_sha256"
for input in pipeline_fixture.fa pipeline_k8_fixture.fa \
    pipeline_metadata.tsv pipeline_k8_metadata.tsv \
    metadata_invalid.tsv metadata_mismatch.tsv metadata_short.tsv \
    parameters_k4.json parameters_k8.json \
    parameters_null_k4.json parameters_null_k8.json \
    parameters_dinucleotide_k4.json parameters_dinucleotide_k8.json \
    dinucleotide_seeds_k4.tsv dinucleotide_seeds_k8.tsv; do
  echo "sounio_pipeline_input name=$input sha256=$(sha256_file "$fixture_dir/$input")"
done
for invalid in "$fixture_dir"/params_invalid/*.json; do
  echo "sounio_pipeline_input name=params_invalid/$(basename "$invalid") sha256=$(sha256_file "$invalid")"
done

# Render every parameter JSON into its flat form and announce it. Parameter
# names match the case names; valid cases announce under their case name.
announce_params() {
  local name="$1" json_rel="$2"
  local json_path="$fixture_dir/$json_rel"
  local flat_path="$flat_dir/$name.flat"
  render_flat "$json_path" "$flat_path"
  echo "DOSA_PIPELINE_PARAMS name=$name flat=$flat_path sha256=$(sha256_file "$json_path")"
}

# Render every parameter JSON into its flat form and announce it. Valid cases
# announce under their case name; parameter-negative cases announce their own
# invalid rendering; metadata-negative cases reuse the "main" parameters and
# are not announced separately.
for spec in "${valid_cases[@]}"; do
  read -r name _fasta _meta params_json _lines <<<"$spec"
  announce_params "$name" "$params_json"
done
for spec in "${negative_cases[@]}"; do
  read -r name _meta params_json _rc _err <<<"$spec"
  if [[ "$params_json" == params_invalid/* ]]; then
    announce_params "$name" "$params_json"
  fi
done

check_artifact() {
  local path="$1" expected_lines="$2"
  local lines
  lines="$(wc -l < "$path" | tr -d ' ')"
  if [[ "$lines" -ne "$expected_lines" ]]; then
    echo "mini-pipeline JSONL line count mismatch: expected $expected_lines, got $lines" >&2
    return 1
  fi
  if grep -qvx '{.*}' "$path"; then
    echo "mini-pipeline JSONL is contaminated by a non-JSON line" >&2
    return 1
  fi
  EXPECTED_JSONL_LINES="$expected_lines" ruby -rjson -e '
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
      abort "JSONL line #{index + 1} has #{object.size} fields, expected 183" unless object.size == 183
    end
  ' "$path"
}

run_guest() {
  local guest_root="/tmp/dosa-mini-pipeline-${source_sha256:0:12}-$$"
  local guest_source="$guest_root/fasta_stream_fixture.sio"
  local guest_inputs="$guest_root/inputs"
  local guest_work="$guest_root/work"

  limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs" "$guest_work"
  limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_source"
  limactl copy -y --backend=scp "$fixture_dir"/pipeline_fixture.fa "$fixture_dir"/pipeline_k8_fixture.fa "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"
  limactl copy -y --backend=scp "$fixture_dir"/*.tsv "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"
  limactl copy -y --backend=scp "$flat_dir"/*.flat "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"

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
output="/tmp/dosa-mini-pipeline-${commit_short}-${source_short}-${run_id}.elf"

valid_cases=(
  "main pipeline_fixture.fa pipeline_metadata.tsv main 12"
  "k8 pipeline_k8_fixture.fa pipeline_k8_metadata.tsv k8 84"
  "null_k4 pipeline_fixture.fa pipeline_metadata.tsv null_k4 12"
  "null_k8 pipeline_k8_fixture.fa pipeline_k8_metadata.tsv null_k8 84"
  "dinucleotide_k4 pipeline_fixture.fa pipeline_metadata.tsv dinucleotide_k4 12"
  "dinucleotide_k8 pipeline_k8_fixture.fa pipeline_k8_metadata.tsv dinucleotide_k8 84"
)
negative_cases=(
  "metadata_invalid metadata_invalid.tsv main 9 METADATA_INVALID"
  "metadata_mismatch metadata_mismatch.tsv main 10 METADATA_MISMATCH"
  "metadata_short metadata_short.tsv main 10 METADATA_MISMATCH"
  "param_window_size_zero pipeline_metadata.tsv param_window_size_zero 11 PARAM_INVALID"
  "param_stride_zero pipeline_metadata.tsv param_stride_zero 11 PARAM_INVALID"
  "param_stride_mismatch pipeline_metadata.tsv param_stride_mismatch 11 PARAM_INVALID"
  "param_k_min_two pipeline_metadata.tsv param_k_min_two 11 PARAM_INVALID"
  "param_k_max_nine pipeline_metadata.tsv param_k_max_nine 11 PARAM_INVALID"
  "param_k_max_above_window pipeline_metadata.tsv param_k_max_above_window 11 PARAM_INVALID"
  "param_unknown_policy pipeline_metadata.tsv param_unknown_policy 11 PARAM_INVALID"
  "param_extra_field pipeline_metadata.tsv param_extra_field 11 PARAM_INVALID"
  "param_null_model_unknown pipeline_metadata.tsv param_null_model_unknown 11 PARAM_INVALID"
  "param_null_replicates_mismatch pipeline_metadata.tsv param_null_replicates_mismatch 11 PARAM_INVALID"
)

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (streaming executable specification; not a release receipt)"
"$repo/bin/souc" check "$source_file" --science-boundary off
"$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
echo "mini_pipeline_executable_sha256=$(sha256sum "$output" | awk '{print $1}')"

for spec in "${valid_cases[@]}"; do
  read -r name fasta meta params expected_lines <<<"$spec"
  seed_args=()
  if [[ "$name" == "dinucleotide_k4" ]]; then seed_args=("$inputs/dinucleotide_seeds_k4.tsv"); fi
  if [[ "$name" == "dinucleotide_k8" ]]; then seed_args=("$inputs/dinucleotide_seeds_k8.tsv"); fi
  opt1="$work/$name.opt1.jsonl"
  opt2="$work/$name.opt2.jsonl"
  ref="$work/$name.ref.jsonl"
  "$output" --pipeline "$inputs/$fasta" "$inputs/$meta" "$inputs/$params.flat" "${seed_args[@]}" > "$opt1"
  "$output" --pipeline "$inputs/$fasta" "$inputs/$meta" "$inputs/$params.flat" "${seed_args[@]}" > "$opt2"
  "$output" --pipeline-reference "$inputs/$fasta" "$inputs/$meta" "$inputs/$params.flat" "${seed_args[@]}" > "$ref"
  sha1="$(sha256sum "$opt1" | awk '{print $1}')"
  sha2="$(sha256sum "$opt2" | awk '{print $1}')"
  sha3="$(sha256sum "$ref" | awk '{print $1}')"
  if [[ "$sha1" != "$sha2" || "$sha1" != "$sha3" ]]; then
    echo "mini-pipeline kernel divergence for $name: opt1=$sha1 opt2=$sha2 ref=$sha3" >&2
    exit 1
  fi
  echo "DOSA_PIPELINE_KERNEL_EQUIVALENCE name=$name sha256=$sha1"
  cp "$opt1" "$work/$name.jsonl"
  lines="$(wc -l < "$work/$name.jsonl" | tr -d ' ')"
  if [[ "$lines" -ne "$expected_lines" ]]; then
    echo "mini-pipeline JSONL line count mismatch for $name: expected $expected_lines, got $lines" >&2
    exit 1
  fi
  if grep -qvx '{.*}' "$work/$name.jsonl"; then
    echo "mini-pipeline JSONL for $name is contaminated by a non-JSON line" >&2
    exit 1
  fi
  echo "DOSA_PIPELINE_CASE name=$name expected_rc=0 actual_rc=0"
done

# A dinucleotide parameter artifact without its frozen seed sidecar must fail
# before any JSONL is emitted. Keep this marker separate from DOSA_PIPELINE_CASE
# so the independent 19-case parameter/metadata oracle remains stable.
set +e
missing_seed_output="$("$output" --pipeline "$inputs/pipeline_fixture.fa" \
  "$inputs/pipeline_metadata.tsv" "$inputs/dinucleotide_k4.flat" 2>&1)"
missing_seed_rc=$?
set -e
echo "DOSA_DINUCLEOTIDE_SEED_CASE name=missing_sidecar expected_rc=11 actual_rc=$missing_seed_rc"
if [[ "$missing_seed_rc" -ne 11 ]] || \
   ! grep -q '^DOSA_FASTA_ERROR code=PARAM_INVALID record=0 offset=0 byte=-1$' <<<"$missing_seed_output" || \
   grep -q '^{' <<<"$missing_seed_output"; then
  printf '%s\n' "$missing_seed_output" >&2
  echo "dinucleotide missing-sidecar case did not fail closed" >&2
  exit 1
fi

for spec in "${negative_cases[@]}"; do
  read -r name meta params expected expected_error <<<"$spec"
  set +e
  case_output="$("$output" --pipeline "$inputs/pipeline_fixture.fa" "$inputs/$meta" "$inputs/$params.flat" 2>&1)"
  actual=$?
  set -e

  echo "DOSA_PIPELINE_CASE name=$name expected_rc=$expected actual_rc=$actual"
  if [[ "$actual" -ne "$expected" ]]; then
    printf '%s\n' "$case_output" >&2
    echo "mini-pipeline exit mismatch for $name" >&2
    exit 1
  fi

  grep -q "^DOSA_FASTA_ERROR code=$expected_error " <<<"$case_output"
  grep "^DOSA_FASTA_ERROR " <<<"$case_output"
  if grep -q '^DOSA_SOUNIO_FASTA_STREAM_OK ' <<<"$case_output"; then
    echo "negative mini-pipeline case $name emitted a success summary" >&2
    exit 1
  fi
done
SOUNIO_LINUX_RUNNER

  for spec in "${valid_cases[@]}"; do
    read -r name _fasta _meta _params expected_lines <<<"$spec"
    limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_work/$name.jsonl" "$work_dir/$name.jsonl"
    check_artifact "$work_dir/$name.jsonl" "$expected_lines"
  done
}

run_native() {
  local repo="$1"
  local output="/tmp/dosa-mini-pipeline-${expected_commit:0:12}-${source_sha256:0:12}-$$.elf"

  cd "$repo"
  "$repo/bin/souc" --version
  echo "science_boundary=off (streaming executable specification; not a release receipt)"
  "$repo/bin/souc" check "$source_file" --science-boundary off
  "$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
  echo "mini_pipeline_executable_sha256=$(sha256_file "$output")"

  for spec in "${valid_cases[@]}"; do
    read -r name fasta meta params expected_lines <<<"$spec"
    local opt1="$work_dir/$name.opt1.jsonl"
    local opt2="$work_dir/$name.opt2.jsonl"
    local ref="$work_dir/$name.ref.jsonl"
    local -a seed_args=()
    if [[ "$name" == "dinucleotide_k4" ]]; then seed_args=("$fixture_dir/dinucleotide_seeds_k4.tsv"); fi
    if [[ "$name" == "dinucleotide_k8" ]]; then seed_args=("$fixture_dir/dinucleotide_seeds_k8.tsv"); fi
    "$output" --pipeline "$fixture_dir/$fasta" "$fixture_dir/$meta" "$flat_dir/$params.flat" "${seed_args[@]}" > "$opt1"
    "$output" --pipeline "$fixture_dir/$fasta" "$fixture_dir/$meta" "$flat_dir/$params.flat" "${seed_args[@]}" > "$opt2"
    "$output" --pipeline-reference "$fixture_dir/$fasta" "$fixture_dir/$meta" "$flat_dir/$params.flat" "${seed_args[@]}" > "$ref"
    local sha1 sha2 sha3
    sha1="$(sha256_file "$opt1")"
    sha2="$(sha256_file "$opt2")"
    sha3="$(sha256_file "$ref")"
    if [[ "$sha1" != "$sha2" || "$sha1" != "$sha3" ]]; then
      echo "mini-pipeline kernel divergence for $name: opt1=$sha1 opt2=$sha2 ref=$sha3" >&2
      return 1
    fi
    echo "DOSA_PIPELINE_KERNEL_EQUIVALENCE name=$name sha256=$sha1"
    mv "$opt1" "$work_dir/$name.jsonl"
    check_artifact "$work_dir/$name.jsonl" "$expected_lines"
    echo "DOSA_PIPELINE_CASE name=$name expected_rc=0 actual_rc=0"
  done

  local missing_seed_output missing_seed_rc
  set +e
  missing_seed_output="$("$output" --pipeline "$fixture_dir/pipeline_fixture.fa" \
    "$fixture_dir/pipeline_metadata.tsv" "$flat_dir/dinucleotide_k4.flat" 2>&1)"
  missing_seed_rc=$?
  set -e
  echo "DOSA_DINUCLEOTIDE_SEED_CASE name=missing_sidecar expected_rc=11 actual_rc=$missing_seed_rc"
  if [[ "$missing_seed_rc" -ne 11 ]] || \
     ! grep -q '^DOSA_FASTA_ERROR code=PARAM_INVALID record=0 offset=0 byte=-1$' <<<"$missing_seed_output" || \
     grep -q '^{' <<<"$missing_seed_output"; then
    printf '%s\n' "$missing_seed_output" >&2
    echo "dinucleotide missing-sidecar case did not fail closed" >&2
    return 1
  fi

  for spec in "${negative_cases[@]}"; do
    read -r name meta params expected expected_error <<<"$spec"
    local actual output_text
    set +e
    output_text="$("$output" --pipeline "$fixture_dir/pipeline_fixture.fa" "$fixture_dir/$meta" "$flat_dir/$params.flat" 2>&1)"
    actual=$?
    set -e

    echo "DOSA_PIPELINE_CASE name=$name expected_rc=$expected actual_rc=$actual"
    if [[ "$actual" -ne "$expected" ]]; then
      printf '%s\n' "$output_text" >&2
      echo "mini-pipeline exit mismatch for $name" >&2
      return 1
    fi

    grep -q "^DOSA_FASTA_ERROR code=$expected_error " <<<"$output_text"
    grep "^DOSA_FASTA_ERROR " <<<"$output_text"
    if grep -q '^DOSA_SOUNIO_FASTA_STREAM_OK ' <<<"$output_text"; then
      echo "negative mini-pipeline case $name emitted a success summary" >&2
      return 1
    fi
  done
}

if [[ -n "${SOUNIO_LIMA_INSTANCE:-}" ]]; then
  if ! command -v limactl >/dev/null 2>&1; then
    echo "BLOCKED: limactl is unavailable for SOUNIO_LIMA_INSTANCE=$SOUNIO_LIMA_INSTANCE" >&2
    exit 2
  fi
  run_guest
else
  run_native "$SOUNIO_REPO"
fi

echo "sounio_pipeline_jsonl_artifact=$work_dir/main.jsonl"
echo "sounio_pipeline_jsonl_lines=$(wc -l < "$work_dir/main.jsonl" | tr -d ' ')"
echo "sounio_pipeline_jsonl_sha256=$(sha256_file "$work_dir/main.jsonl")"
echo "sounio_pipeline_jsonl_artifact_k8=$work_dir/k8.jsonl"
echo "sounio_pipeline_jsonl_lines_k8=$(wc -l < "$work_dir/k8.jsonl" | tr -d ' ')"
echo "sounio_pipeline_jsonl_sha256_k8=$(sha256_file "$work_dir/k8.jsonl")"
echo "sounio_pipeline_jsonl_artifact_null_k4=$work_dir/null_k4.jsonl"
echo "sounio_pipeline_jsonl_lines_null_k4=$(wc -l < "$work_dir/null_k4.jsonl" | tr -d ' ')"
echo "sounio_pipeline_jsonl_sha256_null_k4=$(sha256_file "$work_dir/null_k4.jsonl")"
echo "sounio_pipeline_jsonl_artifact_null_k8=$work_dir/null_k8.jsonl"
echo "sounio_pipeline_jsonl_lines_null_k8=$(wc -l < "$work_dir/null_k8.jsonl" | tr -d ' ')"
echo "sounio_pipeline_jsonl_sha256_null_k8=$(sha256_file "$work_dir/null_k8.jsonl")"
echo "sounio_pipeline_jsonl_artifact_dinucleotide_k4=$work_dir/dinucleotide_k4.jsonl"
echo "sounio_pipeline_jsonl_lines_dinucleotide_k4=$(wc -l < "$work_dir/dinucleotide_k4.jsonl" | tr -d ' ')"
echo "sounio_pipeline_jsonl_sha256_dinucleotide_k4=$(sha256_file "$work_dir/dinucleotide_k4.jsonl")"
echo "sounio_pipeline_jsonl_artifact_dinucleotide_k8=$work_dir/dinucleotide_k8.jsonl"
echo "sounio_pipeline_jsonl_lines_dinucleotide_k8=$(wc -l < "$work_dir/dinucleotide_k8.jsonl" | tr -d ' ')"
echo "sounio_pipeline_jsonl_sha256_dinucleotide_k8=$(sha256_file "$work_dir/dinucleotide_k8.jsonl")"
