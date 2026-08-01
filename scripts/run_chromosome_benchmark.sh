#!/usr/bin/env bash
# Fail-closed chromosome-scale benchmark runner (Fase I, engineering scope).
#
# Runs the Sounio optimized window pipeline (16/16 windows, k=1..8,
# min_kmer_effective_count=1 -- executable-specification parameters, not
# pilot decisions) over the two chromosome replicons of the frozen miniature
# cohort (NC_000913.3 and NC_002695.2), one timed run per chromosome, with
# wall-clock and peak-RSS (Linux VmHWM polling) measurement on the Lima
# guest. Every product is then checked on the host:
#   - structural check: exact line count (ceil(length_bp/16) from the frozen
#     replicons.tsv) and a strict 183-field JSON parse of every line;
#   - deterministic stratified Julia sample validation (spec 0.1.0 section
#     12.2), recomputing ~1/64 of windows byte-exact at tolerance 0.
# A small benchmark receipt (JSON + logs + sample coordinate manifests) is
# written under receipts/chromosome-benchmark-<commit>-<utc>/; the large
# window products themselves stay in the ephemeral work directory, hash-bound
# in the receipt. Cross-run byte determinism is established at plasmid scale
# by the Fase H engineering receipt; this benchmark runs each chromosome
# once. Absence of either implementation is a failure, never a fallback.
# These are engineering products, NOT the pilot dataset and NOT a release
# receipt.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$atlas_root/sounio/src/fasta_stream_fixture.sio"
cohort_dir="$atlas_root/data/cohort/mini"
params_json="$atlas_root/data/fixtures/cohort_smoke/parameters_k8.json"
lock_file="$atlas_root/toolchains/sounio.lock.json"

started_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ts_compact="$(date -u +%Y%m%dT%H%M%SZ)"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dosa-chromosome-benchmark.XXXXXX")"
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

if [[ -z "${SOUNIO_LIMA_INSTANCE:-}" ]]; then
  echo "BLOCKED: set SOUNIO_LIMA_INSTANCE to the Lima guest running the pinned Linux Madaros" >&2
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

if ! command -v julia >/dev/null 2>&1; then
  echo "BLOCKED: julia is unavailable; independent validation cannot run" >&2
  exit 2
fi

atlas_commit="$(git -C "$atlas_root" rev-parse HEAD)"
atlas_dirty=false
if [[ -n "$(git -C "$atlas_root" status --porcelain)" ]]; then
  atlas_dirty=true
fi

echo "sounio_repository=$expected_repo"
echo "sounio_commit=$actual_commit"
echo "sounio_launcher_sha256=$(sha256_file "$SOUNIO_REPO/bin/souc")"
echo "sounio_products_source_sha256=$source_sha256"
echo "sounio_products_params json=$params_json sha256=$(sha256_file "$params_json")"
echo "atlas_commit=$atlas_commit dirty=$atlas_dirty"

# Chromosome table in frozen manifest order: seq_acc, alias, assembly accession.
chromosomes=(
  "NC_000913.3 chr_MG1655 GCF_000005845.2"
  "NC_002695.2 chr_Sakai GCF_000008865.2"
)

assembly_fasta() {
  case "$1" in
    GCF_000005845.2) echo "$cohort_dir/assemblies/GCF_000005845.2/GCF_000005845.2_ASM584v2_genomic.fna" ;;
    GCF_000008865.2) echo "$cohort_dir/assemblies/GCF_000008865.2/GCF_000008865.2_ASM886v2_genomic.fna" ;;
    *) echo "unknown assembly: $1" >&2; return 1 ;;
  esac
}

expected_lines() {
  awk -F'\t' -v acc="$1" '$2 == acc { print int(($7 + 15) / 16); found=1 } END { if (!found) exit 1 }' \
    "$cohort_dir/replicons.tsv"
}

replicon_length() {
  awk -F'\t' -v acc="$1" '$2 == acc { print $7; found=1 } END { if (!found) exit 1 }' \
    "$cohort_dir/replicons.tsv"
}

# Extract each chromosome record byte-exact (header included) from its frozen
# assembly FASTA and build the per-replicon metadata TSV from the frozen
# replicons.tsv (dropping the derived length_bp column).
for spec in "${chromosomes[@]}"; do
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
  echo "sounio_benchmark_replicon acc=$acc alias=$alias assembly=$assembly length_bp=$(replicon_length "$acc") expected_lines=$(expected_lines "$acc") fasta=$dir/record.fa metadata=$dir/metadata.tsv fasta_sha256=$(sha256_file "$dir/record.fa")"
done

flat_path="$flat_dir/products.flat"
render_flat "$params_json" "$flat_path"
echo "DOSA_PRODUCTS_PARAMS_FLAT flat=$flat_path"

guest_root="/tmp/dosa-chrom-bench-${source_sha256:0:12}-$$"
guest_source="$guest_root/fasta_stream_fixture.sio"
guest_inputs="$guest_root/inputs"
guest_work="$guest_root/work"

limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs" "$guest_work"
limactl copy -y --backend=scp "$source_file" "$SOUNIO_LIMA_INSTANCE:$guest_source"
for spec in "${chromosomes[@]}"; do
  read -r acc alias _assembly <<<"$spec"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- mkdir -p "$guest_inputs/$alias"
  limactl copy -y --backend=scp "$work_dir/$alias/record.fa" "$work_dir/$alias/metadata.tsv" "$SOUNIO_LIMA_INSTANCE:$guest_inputs/$alias/"
done
limactl copy -y --backend=scp "$flat_path" "$SOUNIO_LIMA_INSTANCE:$guest_inputs/"

# The guest phase runs detached (nohup on the guest) so a dropped limactl
# session cannot kill hours of chromosome computation; the host polls the
# driver log until the DRIVER_DONE / DRIVER_FAIL marker appears.
driver_src="$work_dir/guest_driver.sh"
cat > "$driver_src" <<'SOUNIO_LINUX_RUNNER'
set -euo pipefail
trap 'echo "DRIVER_FAIL rc=$?"' ERR
repo="$1"
source_file="$2"
inputs="$3"
work="$4"
commit_short="$5"
source_short="$6"
run_id="$7"
expected_mg1655="$8"
expected_sakai="$9"
output="/tmp/dosa-chrom-bench-${commit_short}-${source_short}-${run_id}.elf"

chromosomes=(
  "NC_000913.3 chr_MG1655 $expected_mg1655"
  "NC_002695.2 chr_Sakai $expected_sakai"
)

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (engineering benchmark; not a release receipt)"
"$repo/bin/souc" check "$source_file" --science-boundary off
"$repo/bin/souc" compile "$source_file" -o "$output" --science-boundary off
echo "benchmark_executable_sha256=$(sha256sum "$output" | awk '{print $1}')"
echo "benchmark_guest_uname=$(uname -srmo)"

for spec in "${chromosomes[@]}"; do
  read -r acc alias expected_lines <<<"$spec"
  out="$work/windows_$alias.jsonl"
  start=$(date +%s)
  "$output" --pipeline "$inputs/$alias/record.fa" "$inputs/$alias/metadata.tsv" "$inputs/products.flat" > "$out" &
  pid=$!
  peak=0
  while kill -0 "$pid" 2>/dev/null; do
    rss="$(awk '/^VmHWM:/ { print $2 }' "/proc/$pid/status" 2>/dev/null || true)"
    if [[ -n "$rss" && "$rss" -gt "$peak" ]]; then
      peak="$rss"
    fi
    sleep 0.5
  done
  if ! wait "$pid"; then
    echo "benchmark run failed for $acc" >&2
    exit 1
  fi
  end=$(date +%s)
  lines="$(wc -l < "$out" | tr -d ' ')"
  if [[ "$lines" -ne "$expected_lines" ]]; then
    echo "window product line count mismatch for $acc: expected $expected_lines, got $lines" >&2
    exit 1
  fi
  sha="$(sha256sum "$out" | awk '{print $1}')"
  size="$(stat -c %s "$out")"
  echo "DOSA_BENCH_CASE product=window_operator_profiles acc=$acc alias=$alias expected_lines=$expected_lines lines=$lines sha256=$sha size_bytes=$size wall_seconds=$((end - start)) peak_rss_kb=$peak rc=0"
done
echo "DRIVER_DONE"
SOUNIO_LINUX_RUNNER

limactl copy -y --backend=scp "$driver_src" "$SOUNIO_LIMA_INSTANCE:$guest_root/guest_driver.sh"
limactl shell "$SOUNIO_LIMA_INSTANCE" -- bash -c \
  "nohup bash '$guest_root/guest_driver.sh' '$SOUNIO_REPO' '$guest_source' '$guest_inputs' '$guest_work' '${expected_commit:0:12}' '${source_sha256:0:12}' '$$' '$(expected_lines NC_000913.3)' '$(expected_lines NC_002695.2)' > '$guest_root/driver.log' 2>&1 & echo guest_driver_started"

poll_failures=0
while true; do
  sleep 60
  if limactl shell "$SOUNIO_LIMA_INSTANCE" -- test -f "$guest_root/driver.log" 2>/dev/null; then
    poll_failures=0
    if limactl shell "$SOUNIO_LIMA_INSTANCE" -- grep -q '^DRIVER_DONE$' "$guest_root/driver.log"; then
      break
    fi
    if limactl shell "$SOUNIO_LIMA_INSTANCE" -- grep -q '^DRIVER_FAIL' "$guest_root/driver.log"; then
      limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_root/driver.log" "$work_dir/guest.log" || true
      echo "guest driver failed; log at $work_dir/guest.log" >&2
      exit 1
    fi
  else
    poll_failures=$((poll_failures + 1))
    if [[ "$poll_failures" -ge 10 ]]; then
      echo "BLOCKED: guest driver log unreachable after repeated polls" >&2
      exit 2
    fi
  fi
done

limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_root/driver.log" "$work_dir/guest.log"
cat "$work_dir/guest.log"

for spec in "${chromosomes[@]}"; do
  read -r acc alias _assembly <<<"$spec"
  limactl copy -y --backend=scp "$SOUNIO_LIMA_INSTANCE:$guest_work/windows_$alias.jsonl" "$work_dir/windows_$alias.jsonl"
done
limactl shell "$SOUNIO_LIMA_INSTANCE" -- rm -rf "$guest_root"

# Structural validation of every chromosome window product (streaming).
expected_mg1655="$(expected_lines NC_000913.3)"
expected_sakai="$(expected_lines NC_002695.2)"
ruby -rjson -e '
  checks = {
    "windows_chr_MG1655.jsonl" => ARGV[1].to_i,
    "windows_chr_Sakai.jsonl" => ARGV[2].to_i,
  }
  checks.each do |name, expected_lines|
    path = "#{ARGV[0]}/#{name}"
    lines = 0
    File.foreach(path) do |line|
      lines += 1
      object = JSON.parse(line)
      abort "#{name} line #{lines} is not a JSON object" unless object.is_a?(Hash)
      abort "#{name} line #{lines} has #{object.size} fields, expected 183" unless object.size == 183
    end
    abort "#{name}: expected #{expected_lines} lines, got #{lines}" unless lines == expected_lines
    puts "benchmark_structural_check name=#{name} lines=#{lines} fields=183 status=pass"
  end
' "$work_dir" "$expected_mg1655" "$expected_sakai" | tee "$work_dir/structural_check.log"

# Deterministic stratified Julia sample validation (spec 0.1.0 section 12.2)
# over each chromosome window product.
for spec in "${chromosomes[@]}"; do
  read -r acc alias _assembly <<<"$spec"
  julia --startup-file=no "$atlas_root/julia/scripts/validate_window_sample.jl" \
    "$work_dir/windows_$alias.jsonl" "$work_dir/$alias/record.fa" \
    "$work_dir/$alias/metadata.tsv" "$flat_path" "$work_dir/sample_$alias.txt" \
    > "$work_dir/sample_check_$alias.log"
  cat "$work_dir/sample_check_$alias.log"
done

finished_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Benchmark receipt directory (small evidence files only; the window products
# stay in the ephemeral work directory, hash-bound in the receipt).
run_id="chromosome-benchmark-${atlas_commit:0:8}-$ts_compact"
receipt_dir="$atlas_root/receipts/$run_id"
mkdir -p "$receipt_dir"
cp "$work_dir/guest.log" "$work_dir/structural_check.log" "$receipt_dir/"
for spec in "${chromosomes[@]}"; do
  read -r acc alias _assembly <<<"$spec"
  cp "$work_dir/sample_$alias.txt" "$work_dir/sample_check_$alias.log" "$receipt_dir/"
done

julia_version="$(julia --startup-file=no -e 'print(VERSION)')"
params_sha="$(sha256_file "$params_json")"

ruby -rjson -e '
  facts = {
    "run_id" => ARGV[0],
    "started_utc" => ARGV[1],
    "finished_utc" => ARGV[2],
    "atlas_commit" => ARGV[3],
    "atlas_dirty" => ARGV[4] == "true",
    "sounio_repository" => ARGV[5],
    "sounio_commit" => ARGV[6],
    "sounio_launcher_sha256" => ARGV[7],
    "products_source_sha256" => ARGV[8],
    "parameters_json" => ARGV[9],
    "parameters_sha256" => ARGV[10],
    "guest_instance" => ARGV[11],
    "host_uname" => ARGV[12],
    "julia_version" => ARGV[13],
  }
  receipt_dir = ARGV[14]
  work_dir = ARGV[15]

  guest = File.read("#{receipt_dir}/guest.log")
  executable_sha256 = guest[/^benchmark_executable_sha256=([0-9a-f]{64})/, 1]
  abort "guest log missing executable sha256" unless executable_sha256
  guest_uname = guest[/^benchmark_guest_uname=(.+)$/, 1]
  abort "guest log missing uname" unless guest_uname

  cases = guest.scan(/^DOSA_BENCH_CASE (.*)$/).flatten.map do |line|
    kv = line.split.map { |t| t.split("=", 2) }.to_h
    %w[product acc alias expected_lines lines sha256 size_bytes wall_seconds peak_rss_kb rc].each do |k|
      abort "guest case missing #{k}" unless kv.key?(k)
    end
    kv
  end
  abort "expected exactly 2 benchmark cases" unless cases.size == 2

  results = cases.map do |kv|
    alias_name = kv.fetch("alias")
    sample_log = File.read("#{receipt_dir}/sample_check_#{alias_name}.log")
    report = sample_log[/^DOSA_SAMPLE_REPORT (.*)$/, 1]
    abort "sample log missing report for #{alias_name}" unless report
    skv = report.split.map { |t| t.split("=", 2) }.to_h
    abort "sample validation did not pass for #{alias_name}" unless sample_log.include?("DOSA_SAMPLE_OK")
    coordinates = File.binread("#{receipt_dir}/sample_#{alias_name}.txt")
    require "digest"
    {
      "accession" => kv.fetch("acc"),
      "alias" => alias_name,
      "expected_lines" => kv.fetch("expected_lines").to_i,
      "lines" => kv.fetch("lines").to_i,
      "sha256" => kv.fetch("sha256"),
      "size_bytes" => kv.fetch("size_bytes").to_i,
      "wall_seconds" => kv.fetch("wall_seconds").to_i,
      "peak_rss_kb" => kv.fetch("peak_rss_kb").to_i,
      "work_dir_path" => "#{work_dir}/windows_#{alias_name}.jsonl",
      "sample" => {
        "definition_version" => "0.1.0",
        "total_windows" => skv.fetch("total_windows").to_i,
        "sampled" => skv.fetch("sampled").to_i,
        "validated" => skv.fetch("validated").to_i,
        "tolerance" => skv.fetch("tolerance").to_i,
        "coordinates_sha256" => Digest::SHA256.hexdigest(coordinates),
        "status" => "pass",
      },
    }
  end

  receipt = {
    "receipt_kind" => "chromosome_scale_benchmark",
    "receipt_version" => "0.1.0",
    "specification_version" => "0.1.0",
    "engineering_scope" => true,
    "release_eligible" => false,
    "run_id" => facts.fetch("run_id"),
    "started_utc" => facts.fetch("started_utc"),
    "finished_utc" => facts.fetch("finished_utc"),
    "atlas_source" => { "commit" => facts.fetch("atlas_commit"), "dirty" => facts.fetch("atlas_dirty") },
    "producer" => {
      "language" => "Sounio",
      "repository" => facts.fetch("sounio_repository"),
      "commit" => facts.fetch("sounio_commit"),
      "launcher_sha256" => facts.fetch("sounio_launcher_sha256"),
      "products_source_sha256" => facts.fetch("products_source_sha256"),
      "executable_sha256" => executable_sha256,
    },
    "parameters" => { "json" => facts.fetch("parameters_json"), "sha256" => facts.fetch("parameters_sha256") },
    "environment" => {
      "guest_instance" => facts.fetch("guest_instance"),
      "guest_uname" => guest_uname,
      "host_uname" => facts.fetch("host_uname"),
    },
    "validator" => {
      "language" => "Julia",
      "version" => facts.fetch("julia_version"),
      "mode" => "deterministic_stratified_sample specification 0.1.0 section 12.2",
      "tolerance" => 0,
      "status" => "pass",
    },
    "determinism_note" => "one timed run per chromosome; cross-run byte determinism established at plasmid scale by receipts/engineering-products-b3682abb-20260801T203932Z; this source (post crash-182 arena fix) reproduces the Fase G published fixture hashes byte-exact on all four mini-pipeline cases",
    "memory_note" => "peak RSS is the Linux VmHWM high-water mark of the pipeline process polled every 0.5 s on the guest",
    "results" => results,
  }
  File.binwrite("#{receipt_dir}/benchmark_receipt.json", JSON.pretty_generate(receipt) + "\n")
  puts "benchmark_receipt=#{receipt_dir}/benchmark_receipt.json"
' "$run_id" "$started_utc" "$finished_utc" "$atlas_commit" "$atlas_dirty" \
  "$expected_repo" "$actual_commit" "$(sha256_file "$SOUNIO_REPO/bin/souc")" \
  "$source_sha256" "$params_json" "$params_sha" "$SOUNIO_LIMA_INSTANCE" \
  "$(uname -srmo)" "$julia_version" "$receipt_dir" "$work_dir"

echo "DOSA_CHROMOSOME_BENCHMARK_OK run_id=$run_id receipt_dir=$receipt_dir work_dir=$work_dir"
