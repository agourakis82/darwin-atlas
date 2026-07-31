#!/usr/bin/env bash
# Fail-closed canonical products runner (Fase E, engineering scope).
#
# Emits the four canonical products of specification 0.1.0 section 11 for the
# frozen miniature cohort at engineering scope (16/16 windows, k=1..8,
# min_kmer_effective_count=1 -- executable-specification parameters, not
# pilot decisions):
#   - cohort_assemblies.jsonl      (mechanical transform of the frozen
#                                   cohort_manifest.jsonl; no scientific
#                                   observations, fixed field order)
#   - atlas_replicons.jsonl        (Sounio --replicon-profile, all 4 replicons)
#   - excluded_records.jsonl       (Sounio --exclusions, all 4 replicons)
#   - window_operator_profiles for the two plasmid replicons (Sounio
#     --pipeline; chromosome-scale windows are deferred to the Fase I
#     benchmark)
# Every Sounio product is then recomputed byte-exact by independent Base-only
# Julia validators. Absence of either implementation is a failure, never a
# fallback. These are engineering products, NOT the pilot dataset and NOT a
# release receipt.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$atlas_root/sounio/src/fasta_stream_fixture.sio"
cohort_dir="$atlas_root/data/cohort/mini"
params_json="$atlas_root/data/fixtures/cohort_smoke/parameters_k8.json"
lock_file="$atlas_root/toolchains/sounio.lock.json"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dosa-cohort-products.XXXXXX")"
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
echo "sounio_products_source_sha256=$source_sha256"
echo "sounio_products_params json=$params_json sha256=$(sha256_file "$params_json")"

# Replicon table in frozen manifest order: seq_acc, alias, assembly accession.
replicons=(
  "NC_000913.3 chr_MG1655 GCF_000005845.2"
  "NC_002695.2 chr_Sakai GCF_000008865.2"
  "NC_002127.1 pOSAK1 GCF_000008865.2"
  "NC_002128.1 pO157 GCF_000008865.2"
)

assembly_fasta() {
  case "$1" in
    GCF_000005845.2) echo "$cohort_dir/assemblies/GCF_000005845.2/GCF_000005845.2_ASM584v2_genomic.fna" ;;
    GCF_000008865.2) echo "$cohort_dir/assemblies/GCF_000008865.2/GCF_000008865.2_ASM886v2_genomic.fna" ;;
    *) echo "unknown assembly: $1" >&2; return 1 ;;
  esac
}

# Extract each replicon record byte-exact (header included) from its frozen
# assembly FASTA and build the per-replicon metadata TSV from the frozen
# replicons.tsv (dropping the derived length_bp column).
for spec in "${replicons[@]}"; do
  read -r acc alias assembly <<<"$spec"
  dir="$work_dir/$alias"
  mkdir -p "$dir"
  awk -v acc=">$acc " '/^>/ { if (found) exit; if (index($0, acc) == 1) found=1 } found' \
    "$(assembly_fasta "$assembly")" > "$dir/record.fa"
  if [[ ! -s "$dir/record.fa" ]]; then
    echo "extraction produced an empty record for $acc" >&2
    exit 1
  fi
  # record_index is local to the single-record run (always 1); the
  # cohort-level index lives in replicons.tsv.
  awk -F'\t' -v acc="$acc" 'NR == 1 { print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6; next } $2 == acc { print "1\t"$2"\t"$3"\t"$4"\t"$5"\t"$6; found=1 } END { if (!found) exit 1 }' \
    "$cohort_dir/replicons.tsv" > "$dir/metadata.tsv"
  echo "sounio_products_replicon acc=$acc alias=$alias assembly=$assembly fasta=$dir/record.fa metadata=$dir/metadata.tsv fasta_sha256=$(sha256_file "$dir/record.fa")"
done

flat_path="$flat_dir/products.flat"
render_flat "$params_json" "$flat_path"
echo "DOSA_PRODUCTS_PARAMS_FLAT flat=$flat_path"

guest_root="/tmp/dosa-cohort-products-${source_sha256:0:12}-$$"
guest_source="$guest_root/fasta_stream_fixture.sio"
guest_inputs="$guest_root/inputs"
guest_work="$guest_root/work"

limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs" "$guest_work"
limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_source"
for spec in "${replicons[@]}"; do
  read -r acc alias _assembly <<<"$spec"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs/$alias"
  limactl copy -y --backend=scp "$work_dir/$alias/record.fa" "$work_dir/$alias/metadata.tsv" "$SOUNIO_LIMA_INSTANCE:$guest_inputs/$alias/"
done
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
output="/tmp/dosa-cohort-products-${commit_short}-${source_short}-${run_id}.elf"

replicons=(
  "NC_000913.3 chr_MG1655"
  "NC_002695.2 chr_Sakai"
  "NC_002127.1 pOSAK1"
  "NC_002128.1 pO157"
)
plasmids=(
  "NC_002127.1 pOSAK1 207"
  "NC_002128.1 pO157 5796"
)

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (engineering products; not a release receipt)"
"$repo/bin/souc" check "$source_file" --science-boundary off
"$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
echo "products_executable_sha256=$(sha256sum "$output" | awk '{print $1}')"

: > "$work/atlas_replicons.jsonl"
: > "$work/excluded_records.jsonl"

for spec in "${replicons[@]}"; do
  read -r acc alias <<<"$spec"
  sha="$(sha256sum "$inputs/$alias/record.fa" | awk '{print $1}')"
  "$output" --replicon-profile "$inputs/$alias/record.fa" "$inputs/$alias/metadata.tsv" "$inputs/products.flat" "input_sha256=$sha" >> "$work/atlas_replicons.jsonl"
  echo "DOSA_PRODUCT_CASE product=atlas_replicons acc=$acc rc=0"
  start=$(date +%s)
  "$output" --exclusions "$inputs/$alias/record.fa" "$inputs/$alias/metadata.tsv" "$inputs/products.flat" >> "$work/excluded_records.jsonl"
  end=$(date +%s)
  echo "DOSA_PRODUCT_CASE product=excluded_records acc=$acc rc=0"
  echo "DOSA_PRODUCT_TIMING product=excluded_records acc=$acc wall_seconds=$((end - start))"
done

for spec in "${plasmids[@]}"; do
  read -r acc alias expected_lines <<<"$spec"
  opt1="$work/$alias.opt1.jsonl"
  opt2="$work/$alias.opt2.jsonl"
  start=$(date +%s)
  "$output" --pipeline "$inputs/$alias/record.fa" "$inputs/$alias/metadata.tsv" "$inputs/products.flat" > "$opt1"
  end=$(date +%s)
  echo "DOSA_PRODUCT_TIMING product=window_operator_profiles acc=$acc wall_seconds=$((end - start))"
  "$output" --pipeline "$inputs/$alias/record.fa" "$inputs/$alias/metadata.tsv" "$inputs/products.flat" > "$opt2"
  sha1="$(sha256sum "$opt1" | awk '{print $1}')"
  sha2="$(sha256sum "$opt2" | awk '{print $1}')"
  if [[ "$sha1" != "$sha2" ]]; then
    echo "window product determinism failure for $acc: opt1=$sha1 opt2=$sha2" >&2
    exit 1
  fi
  mv "$opt1" "$work/windows_$alias.jsonl"
  rm -f "$opt2"
  lines="$(wc -l < "$work/windows_$alias.jsonl" | tr -d ' ')"
  if [[ "$lines" -ne "$expected_lines" ]]; then
    echo "window product line count mismatch for $acc: expected $expected_lines, got $lines" >&2
    exit 1
  fi
  echo "DOSA_PRODUCT_CASE product=window_operator_profiles acc=$acc rc=0 runs=2 sha256=$sha1"
done
SOUNIO_LINUX_RUNNER

# cohort_assemblies.jsonl: mechanical fixed-order transform of the frozen
# manifest (no scientific observations).
ruby -rjson -e '
  order = %w[schema_version cohort assembly_accession_version taxid organism_name refseq_category assembly_level retrieval_utc datasets_version datasets_cli_sha256 package_md5 package_md5_scope download_package_sha256 topology_package_sha256 genomic_fna_sha256 included]
  rows = File.readlines(ARGV[0], chomp: true).map { |l| JSON.parse(l) }
  abort "cohort manifest must have exactly 2 rows" unless rows.size == 2
  out = rows.map do |row|
    missing = order.reject { |k| row.key?(k) }
    abort "cohort manifest missing keys: #{missing.join(",")}" unless missing.empty?
    JSON.generate(order.map { |k| [k, row[k]] }.to_h)
  end
  File.binwrite(ARGV[1], out.join("\n") + "\n")
' "$cohort_dir/cohort_manifest.jsonl" "$work_dir/cohort_assemblies.jsonl"

for product in atlas_replicons excluded_records; do
  limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_work/$product.jsonl" "$work_dir/$product.jsonl"
done
for spec in "pOSAK1 207" "pO157 5796"; do
  read -r alias expected_lines <<<"$spec"
  limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_work/windows_$alias.jsonl" "$work_dir/windows_$alias.jsonl"
done
limactl shell "$SOUNIO_LIMA_INSTANCE" -- rm -rf "$guest_root"

# Structural validation of every product.
ruby -rjson -e '
  checks = {
    "cohort_assemblies.jsonl" => [2, 16],
    "atlas_replicons.jsonl" => [4, 14],
    "windows_pOSAK1.jsonl" => [207, 90],
    "windows_pO157.jsonl" => [5796, 90],
  }
  checks.each do |name, (expected_lines, expected_fields)|
    lines = File.readlines("#{ARGV[0]}/#{name}", chomp: true)
    abort "#{name}: expected #{expected_lines} lines, got #{lines.size}" unless lines.size == expected_lines
    lines.each_with_index do |line, index|
      object = JSON.parse(line)
      abort "#{name} line #{index + 1} is not a JSON object" unless object.is_a?(Hash)
      abort "#{name} line #{index + 1} has #{object.size} fields, expected #{expected_fields}" unless object.size == expected_fields
    end
  end
  excluded = File.readlines("#{ARGV[0]}/excluded_records.jsonl", chomp: true)
  excluded.each_with_index do |line, index|
    object = JSON.parse(line)
    abort "excluded_records line #{index + 1} is not a JSON object" unless object.is_a?(Hash)
    abort "excluded_records line #{index + 1} has #{object.size} fields, expected 10" unless object.size == 10
  end
  puts "products_structural_check=PASS excluded_records_lines=#{excluded.size}"
' "$work_dir"

# Announce product artifacts.
for name in cohort_assemblies atlas_replicons excluded_records windows_pOSAK1 windows_pO157; do
  lines="$(wc -l < "$work_dir/$name.jsonl" | tr -d ' ')"
  echo "DOSA_PRODUCT_ARTIFACT name=$name path=$work_dir/$name.jsonl lines=$lines sha256=$(sha256_file "$work_dir/$name.jsonl")"
done

# Self-contained products log for the independent products validator.
products_log="$work_dir/products.log"
params_sha="$(sha256_file "$params_json")"
{
  echo "sounio_products_params json=$params_json sha256=$params_sha"
  echo "DOSA_PRODUCTS_PARAMS_FLAT flat=$flat_path"
  for spec in "${replicons[@]}"; do
    read -r acc alias assembly <<<"$spec"
    echo "sounio_products_replicon acc=$acc alias=$alias assembly=$assembly fasta=$work_dir/$alias/record.fa metadata=$work_dir/$alias/metadata.tsv fasta_sha256=$(sha256_file "$work_dir/$alias/record.fa")"
  done
  for name in cohort_assemblies atlas_replicons excluded_records; do
    echo "DOSA_PRODUCT_ARTIFACT name=$name path=$work_dir/$name.jsonl lines=$(wc -l < "$work_dir/$name.jsonl" | tr -d ' ') sha256=$(sha256_file "$work_dir/$name.jsonl")"
  done
} > "$products_log"

# Windows products: reuse the gated mini-pipeline validator with the
# cohort_plasmids case set.
windows_log="$work_dir/windows-runner.log"
{
  echo "DOSA_PIPELINE_PARAMS name=windows_pOSAK1 flat=$flat_path sha256=$params_sha"
  echo "DOSA_PIPELINE_PARAMS name=windows_pO157 flat=$flat_path sha256=$params_sha"
  for spec in "windows_pOSAK1 pOSAK1" "windows_pO157 pO157"; do
    read -r case_name alias <<<"$spec"
    echo "DOSA_PIPELINE_CASE name=$case_name expected_rc=0 actual_rc=0"
    echo "sounio_pipeline_jsonl_artifact_$case_name=$work_dir/windows_$alias.jsonl"
    echo "sounio_pipeline_jsonl_lines_$case_name=$(wc -l < "$work_dir/windows_$alias.jsonl" | tr -d ' ')"
    echo "sounio_pipeline_jsonl_sha256_$case_name=$(sha256_file "$work_dir/windows_$alias.jsonl")"
  done
} > "$windows_log"

if ! command -v julia >/dev/null 2>&1; then
  echo "BLOCKED: julia is unavailable; independent validation cannot run" >&2
  exit 2
fi

julia --startup-file=no "$atlas_root/julia/scripts/validate_mini_pipeline.jl" \
  "$windows_log" "$work_dir" cohort_plasmids

julia --startup-file=no "$atlas_root/julia/scripts/validate_cohort_products.jl" \
  "$products_log" "$cohort_dir" "$work_dir"

# Deterministic stratified sample validation (spec 12.2) over each plasmid
# window product; the coordinates file hash binds the sample in the report.
for alias in pOSAK1 pO157; do
  julia --startup-file=no "$atlas_root/julia/scripts/validate_window_sample.jl" \
    "$work_dir/windows_$alias.jsonl" "$work_dir/$alias/record.fa" \
    "$work_dir/$alias/metadata.tsv" "$flat_path" "$work_dir/sample_$alias.txt"
  echo "DOSA_SAMPLE_ARTIFACT name=windows_$alias coordinates=$work_dir/sample_$alias.txt sha256=$(sha256_file "$work_dir/sample_$alias.txt")"
done

echo "sounio_products_runner_log=$products_log"
echo "sounio_products_runner_log_sha256=$(sha256_file "$products_log")"
echo "DOSA_COHORT_PRODUCTS_OK work_dir=$work_dir"
