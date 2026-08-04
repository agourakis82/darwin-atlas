#!/usr/bin/env bash
# Fail-closed Sounio runner for the null-engine metamorphic fixture (Fase M4).
#
# Runs the engineered null-metamorphic FASTA + metadata fixtures (homopolymer,
# strictly alternating, and general synthetic controls) through the pinned
# official Sounio build of sounio/src/fasta_stream_fixture.sio in --pipeline
# mode under both null engines, requires the optimized and reference kernels
# byte-identical, persists both deterministic JSONL artifacts, and prints
# input/parameter/artifact SHA-256 evidence. Any missing gate (Sounio
# checkout, official remote, pinned commit, clean tree) blocks with exit 2;
# there is no fallback producer.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/sounio.lock.json"
source_file="$atlas_root/sounio/src/fasta_stream_fixture.sio"
fixture_dir="$atlas_root/data/fixtures/null_metamorphic"
work_host="$(mktemp -d "${TMPDIR:-/tmp}/dosa-null-metamorphic.XXXXXX")"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    command sha256sum "$1" | awk '{print $1}'
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

for f in nullmeta_fixture.fa nullmeta_metadata.tsv \
    parameters_nullmeta_mono_k8.json parameters_nullmeta_dinuc_k8.json \
    dinucleotide_seeds_nullmeta_k8.tsv; do
  if [[ ! -s "$fixture_dir/$f" ]]; then
    echo "BLOCKED: missing null-metamorphic fixture file: $fixture_dir/$f" >&2
    exit 2
  fi
done

echo "sounio_repository=$expected_repo"
echo "sounio_commit=$actual_commit"
echo "sounio_launcher_sha256=$(sha256_file "$SOUNIO_REPO/bin/souc")"
echo "sounio_nullmeta_source_sha256=$source_sha256"
for f in nullmeta_fixture.fa nullmeta_metadata.tsv \
    parameters_nullmeta_mono_k8.json parameters_nullmeta_dinuc_k8.json \
    dinucleotide_seeds_nullmeta_k8.tsv; do
  echo "sounio_nullmeta_input name=$f sha256=$(sha256_file "$fixture_dir/$f")"
done

render_flat() {
  local json_path="$1" flat_path="$2"
  ruby -rjson -rdigest -e '
    raw = File.binread(ARGV[0])
    obj = JSON.parse(raw)
    abort "parameter artifact is not a JSON object" unless obj.is_a?(Hash)
    lines = obj.map do |key, value|
      case value
      when true, false then "#{key}=#{value}"
      when Integer, Float, String then "#{key}=#{value}"
      else abort "non-scalar parameter value for key #{key.inspect}"
      end
    end
    lines << "parameters_sha256=#{Digest::SHA256.hexdigest(raw)}"
    File.binwrite(ARGV[1], lines.join("\n") + "\n")
  ' "$json_path" "$flat_path"
}

# Runs one case as an optimized/optimized/reference triple and requires the
# three runs byte-identical. Arguments: executable, inputs dir, work dir.
run_case_triple() {
  local executable="$1" inputs="$2" work="$3"
  local name="$4" params="$5" expected_lines="$6"
  shift 6
  local seed_args=("$@")
  local opt1="$work/$name.opt1.jsonl"
  local opt2="$work/$name.opt2.jsonl"
  local ref="$work/$name.ref.jsonl"

  "$executable" --pipeline "$inputs/nullmeta_fixture.fa" "$inputs/nullmeta_metadata.tsv" \
    "$inputs/$params.flat" "${seed_args[@]}" > "$opt1"
  "$executable" --pipeline "$inputs/nullmeta_fixture.fa" "$inputs/nullmeta_metadata.tsv" \
    "$inputs/$params.flat" "${seed_args[@]}" > "$opt2"
  "$executable" --pipeline-reference "$inputs/nullmeta_fixture.fa" "$inputs/nullmeta_metadata.tsv" \
    "$inputs/$params.flat" "${seed_args[@]}" > "$ref"

  local sha1 sha2 sha3
  sha1="$(sha256_file "$opt1")"
  sha2="$(sha256_file "$opt2")"
  sha3="$(sha256_file "$ref")"
  if [[ "$sha1" != "$sha2" || "$sha1" != "$sha3" ]]; then
    echo "null-metamorphic kernel divergence for $name: opt1=$sha1 opt2=$sha2 ref=$sha3" >&2
    return 1
  fi
  cp "$opt1" "$work/$name.jsonl"
  local lines
  lines="$(wc -l < "$work/$name.jsonl" | tr -d ' ')"
  if [[ "$lines" -ne "$expected_lines" ]]; then
    echo "null-metamorphic JSONL line count mismatch for $name: expected $expected_lines, got $lines" >&2
    return 1
  fi
  if grep -qvx '{.*}' "$work/$name.jsonl"; then
    echo "null-metamorphic JSONL for $name is contaminated by a non-JSON line" >&2
    return 1
  fi
  echo "DOSA_PIPELINE_KERNEL_EQUIVALENCE name=$name sha256=$sha1"
  echo "DOSA_PIPELINE_CASE name=$name expected_rc=0 actual_rc=0"
}

if [[ -n "${SOUNIO_LIMA_INSTANCE:-}" ]]; then
  if ! command -v limactl >/dev/null 2>&1; then
    echo "BLOCKED: limactl is unavailable for SOUNIO_LIMA_INSTANCE=$SOUNIO_LIMA_INSTANCE" >&2
    exit 2
  fi

  guest_root="/tmp/dosa-null-metamorphic-${source_sha256:0:12}"
  guest_inputs="$guest_root/inputs"
  guest_work="$guest_root/work"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs" "$guest_work"
  limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_root/fasta_stream_fixture.sio"
  # Flat parameter rendering happens on the host (the guest has no ruby);
  # the rendered bytes are inputs and are hashed into the evidence log.
  render_flat "$fixture_dir/parameters_nullmeta_mono_k8.json" "$work_host/nullmeta_mono.flat"
  render_flat "$fixture_dir/parameters_nullmeta_dinuc_k8.json" "$work_host/nullmeta_dinuc.flat"
  for f in nullmeta_fixture.fa nullmeta_metadata.tsv dinucleotide_seeds_nullmeta_k8.tsv \
      parameters_nullmeta_mono_k8.json parameters_nullmeta_dinuc_k8.json; do
    limactl copy -y --backend=scp "$fixture_dir/$f" "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"
  done
  for name in nullmeta_mono nullmeta_dinuc; do
    limactl copy -y --backend=scp "$work_host/$name.flat" "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"
  done

  limactl shell "$SOUNIO_LIMA_INSTANCE" -- bash -s -- \
    "$SOUNIO_REPO" "$guest_root" "${expected_commit:0:12}" "${source_sha256:0:12}" <<'SOUNIO_LINUX_RUNNER'
set -euo pipefail
repo="$1"
guest_root="$2"
commit_short="$3"
source_short="$4"
inputs="$guest_root/inputs"
work="$guest_root/work"
output="/tmp/dosa-null-metamorphic-${commit_short}-${source_short}.elf"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

render_flat() {
  ruby -rjson -rdigest -e '
    raw = File.binread(ARGV[0])
    obj = JSON.parse(raw)
    abort "parameter artifact is not a JSON object" unless obj.is_a?(Hash)
    lines = obj.map do |key, value|
      case value
      when true, false then "#{key}=#{value}"
      when Integer, Float, String then "#{key}=#{value}"
      else abort "non-scalar parameter value for key #{key.inspect}"
      end
    end
    lines << "parameters_sha256=#{Digest::SHA256.hexdigest(raw)}"
    File.binwrite(ARGV[1], lines.join("\n") + "\n")
  ' "$1" "$2"
}

run_case_triple() {
  local name="$1" params="$2" expected_lines="$3"
  shift 3
  local seed_args=("$@")
  local opt1="$work/$name.opt1.jsonl"
  local opt2="$work/$name.opt2.jsonl"
  local ref="$work/$name.ref.jsonl"

  "$output" --pipeline "$inputs/nullmeta_fixture.fa" "$inputs/nullmeta_metadata.tsv" \
    "$inputs/$params.flat" "${seed_args[@]}" > "$opt1"
  "$output" --pipeline "$inputs/nullmeta_fixture.fa" "$inputs/nullmeta_metadata.tsv" \
    "$inputs/$params.flat" "${seed_args[@]}" > "$opt2"
  "$output" --pipeline-reference "$inputs/nullmeta_fixture.fa" "$inputs/nullmeta_metadata.tsv" \
    "$inputs/$params.flat" "${seed_args[@]}" > "$ref"

  local sha1 sha2 sha3
  sha1="$(sha256_file "$opt1")"
  sha2="$(sha256_file "$opt2")"
  sha3="$(sha256_file "$ref")"
  if [[ "$sha1" != "$sha2" || "$sha1" != "$sha3" ]]; then
    echo "null-metamorphic kernel divergence for $name: opt1=$sha1 opt2=$sha2 ref=$sha3" >&2
    exit 1
  fi
  cp "$opt1" "$work/$name.jsonl"
  local lines
  lines="$(wc -l < "$work/$name.jsonl" | tr -d ' ')"
  if [[ "$lines" -ne "$expected_lines" ]]; then
    echo "null-metamorphic JSONL line count mismatch for $name: expected $expected_lines, got $lines" >&2
    exit 1
  fi
  if grep -qvx '{.*}' "$work/$name.jsonl"; then
    echo "null-metamorphic JSONL for $name is contaminated by a non-JSON line" >&2
    exit 1
  fi
  echo "DOSA_PIPELINE_KERNEL_EQUIVALENCE name=$name sha256=$sha1"
  echo "DOSA_PIPELINE_CASE name=$name expected_rc=0 actual_rc=0"
}

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (null-metamorphic executable specification; not a release receipt)"
"$repo/bin/souc" check "$guest_root/fasta_stream_fixture.sio" --science-boundary off
"$repo/bin/souc" compile "$guest_root/fasta_stream_fixture.sio" -o "$output" --science-boundary off
echo "nullmeta_executable_sha256=$(sha256_file "$output")"

run_case_triple "nullmeta_mono" "nullmeta_mono" 4
run_case_triple "nullmeta_dinuc" "nullmeta_dinuc" 4 "$inputs/dinucleotide_seeds_nullmeta_k8.tsv"
SOUNIO_LINUX_RUNNER

  for name in nullmeta_mono nullmeta_dinuc; do
    limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_work/$name.jsonl" "$work_host/$name.jsonl"
  done
else
  inputs_host="$work_host/inputs"
  mkdir -p "$inputs_host"
  for f in nullmeta_fixture.fa nullmeta_metadata.tsv dinucleotide_seeds_nullmeta_k8.tsv; do
    cp "$fixture_dir/$f" "$inputs_host/"
  done
  output="/tmp/dosa-null-metamorphic-${expected_commit:0:12}-${source_sha256:0:12}.elf"
  cd "$SOUNIO_REPO"
  "$SOUNIO_REPO/bin/souc" --version
  echo "science_boundary=off (null-metamorphic executable specification; not a release receipt)"
  "$SOUNIO_REPO/bin/souc" check "$source_file" --science-boundary off
  "$SOUNIO_REPO/bin/souc" compile "$source_file" -o "$output" --science-boundary off
  echo "nullmeta_executable_sha256=$(sha256_file "$output")"

  render_flat "$fixture_dir/parameters_nullmeta_mono_k8.json" "$inputs_host/nullmeta_mono.flat"
  render_flat "$fixture_dir/parameters_nullmeta_dinuc_k8.json" "$inputs_host/nullmeta_dinuc.flat"

  run_case_triple "$output" "$inputs_host" "$work_host" "nullmeta_mono" "nullmeta_mono" 4
  run_case_triple "$output" "$inputs_host" "$work_host" "nullmeta_dinuc" "nullmeta_dinuc" 4 \
    "$inputs_host/dinucleotide_seeds_nullmeta_k8.tsv"
fi

echo "DOSA_PIPELINE_PARAMS name=nullmeta_mono flat=$work_host/nullmeta_mono.flat sha256=$(sha256_file "$fixture_dir/parameters_nullmeta_mono_k8.json")"
echo "DOSA_PIPELINE_PARAMS name=nullmeta_dinuc flat=$work_host/nullmeta_dinuc.flat sha256=$(sha256_file "$fixture_dir/parameters_nullmeta_dinuc_k8.json")"
for name in nullmeta_mono nullmeta_dinuc; do
  echo "sounio_pipeline_jsonl_artifact_$name=$work_host/$name.jsonl"
  echo "sounio_pipeline_jsonl_lines_$name=$(wc -l < "$work_host/$name.jsonl" | tr -d ' ')"
  echo "sounio_pipeline_jsonl_sha256_$name=$(sha256_file "$work_host/$name.jsonl")"
done
