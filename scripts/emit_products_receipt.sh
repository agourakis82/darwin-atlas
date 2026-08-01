#!/usr/bin/env bash
# Two-stage engineering-products run receipt (Fase H).
#
# Stage 1 (producer): reruns scripts/run_cohort_products.sh from a CLEAN atlas
# tree and assembles a run_receipt schema 1.0.0 document in state
# "generated_unvalidated" binding the Sounio producer run: clean commit and
# tree hash, official compiler identity, acquisition record, input manifest,
# parameter hash, orchestration commands with stdout/stderr hashes, and every
# product artifact by sha256.
#
# Stage 2 (validator): reruns the independent Base-only Julia validations over
# the persisted artifacts, persists the validation report, and finalizes the
# receipt in state "validated" with the Julia validator block (version,
# project manifest, executable sample definition, report hash, tolerance 0).
#
# The receipt is assembly/orchestration evidence: no scientific observation is
# computed here. Artifacts are hash-bound; small artifacts are persisted next
# to the receipt, the two plasmid window products (tens of MB) are bound by
# hash and deterministically regenerate via scripts/run_cohort_products.sh.
# A dirty atlas tree BLOCKS with exit 2 (G0 binding requires a clean commit).
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$atlas_root"

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

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- Pre-flight: clean tree, Julia present, receipt dir unique --------------
if [[ -n "$(git status --porcelain)" ]]; then
  echo "BLOCKED: atlas tree is dirty; the G0 receipt binding requires a clean commit" >&2
  exit 2
fi
if ! command -v julia >/dev/null 2>&1; then
  echo "BLOCKED: julia is unavailable; independent validation cannot run" >&2
  exit 2
fi

commit="$(git rev-parse HEAD)"
commit8="${commit:0:8}"
tree_listing="$(mktemp "${TMPDIR:-/tmp}/dosa-receipt-tree.XXXXXX")"
git ls-tree -r HEAD > "$tree_listing"
tree_sha256="$(sha256_file "$tree_listing")"
rm -f "$tree_listing"
run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_id="engineering-products-${commit8}-${run_stamp}"
receipt_dir="$atlas_root/receipts/$run_id"
if [[ -e "$receipt_dir" ]]; then
  echo "BLOCKED: receipt directory already exists: $receipt_dir" >&2
  exit 2
fi
mkdir -p "$receipt_dir"

started_utc="$(utc_now)"

# --- Stage 1: producer run ---------------------------------------------------
products_stdout="$receipt_dir/products_runner.log"
products_stderr="$receipt_dir/products_runner.stderr.log"
set +e
bash "$atlas_root/scripts/run_cohort_products.sh" >"$products_stdout" 2>"$products_stderr"
products_rc=$?
set -e
if [[ "$products_rc" -ne 0 ]]; then
  echo "products runner failed rc=$products_rc; receipt not emitted" >&2
  exit 1
fi

log_field() { grep "^$2=" "$1" | tail -1 | cut -d= -f2-; }

work_dir="$(grep '^DOSA_COHORT_PRODUCTS_OK ' "$products_stdout" | sed 's/.*work_dir=//')"
[[ -d "$work_dir" ]] || { echo "products work_dir missing from runner log" >&2; exit 1; }

params_sha="$(grep '^sounio_products_params ' "$products_stdout" | tail -1 | sed 's/.*sha256=//')"
source_sha="$(log_field "$products_stdout" sounio_products_source_sha256)"
sounio_commit="$(log_field "$products_stdout" sounio_commit)"
launcher_sha="$(log_field "$products_stdout" sounio_launcher_sha256)"
elf_sha="$(log_field "$products_stdout" products_executable_sha256)"
# souc --version prints e.g. "Madaros v0.80.0 -- the Sounio self-hosted compiler"
compiler_version="$(grep -m1 '^Madaros ' "$products_stdout" || true)"
[[ -n "$compiler_version" ]] || compiler_version="souc (pinned checkout $sounio_commit)"

julia_version="$(julia --startup-file=no --version | awk '{print $3}')"
project_manifest_sha="$(sha256_file "$atlas_root/julia/Project.toml")"
sample_definition_sha="$(sha256_file "$atlas_root/julia/scripts/validate_window_sample.jl")"
input_manifest_sha="$(sha256_file "$atlas_root/data/cohort/mini/SHA256SUMS")"
retrieved_utc="$(ruby -rjson -e 'print JSON.parse(File.readlines(ARGV[0]).first).fetch("retrieval_utc")' "$atlas_root/data/cohort/mini/cohort_manifest.jsonl")"
datasets_version="$(ruby -rjson -e 'print JSON.parse(File.readlines(ARGV[0]).first).fetch("datasets_version")' "$atlas_root/data/cohort/mini/cohort_manifest.jsonl")"

# Persist the small artifacts next to the receipt; window products stay
# hash-bound at their (ephemeral) work-dir paths.
small_artifacts=(cohort_assemblies.jsonl atlas_replicons.jsonl excluded_records.jsonl sample_pOSAK1.txt sample_pO157.txt)
for name in "${small_artifacts[@]}"; do
  cp "$work_dir/$name" "$receipt_dir/$name"
done

artifact_entry() { # name path schema record_count
  local name="$1" path="$2" schema="$3" records="$4"
  ruby -rjson -e '
    h = {"path" => ARGV[0], "media_type" => ARGV[1], "schema" => (ARGV[2] == "null" ? nil : ARGV[2]),
         "sha256" => ARGV[3], "size_bytes" => File.size(ARGV[0])}
    h["record_count"] = Integer(ARGV[4]) if ARGV[4] != "-1"
    print JSON.generate(h)
  ' "$path" "$([[ "$name" == *.jsonl ]] && echo application/jsonl || echo text/plain)" \
    "$schema" "$(sha256_file "$path")" "$records"
}

artifacts_json="[]"
add_artifact() { # name path schema records
  local entry
  entry="$(artifact_entry "$1" "$2" "$3" "$4")"
  artifacts_json="$(ruby -rjson -e 'a = JSON.parse(ARGV[0]); a << JSON.parse(ARGV[1]); print JSON.generate(a)' "$artifacts_json" "$entry")"
}

wc_lines() { wc -l < "$1" | tr -d ' '; }

add_artifact cohort_assemblies.jsonl "$receipt_dir/cohort_assemblies.jsonl" cohort_assemblies.schema.json 2
add_artifact atlas_replicons.jsonl "$receipt_dir/atlas_replicons.jsonl" atlas_replicons.schema.json 4
add_artifact excluded_records.jsonl "$receipt_dir/excluded_records.jsonl" excluded_records.schema.json "$(wc_lines "$receipt_dir/excluded_records.jsonl")"
add_artifact windows_pOSAK1.jsonl "$work_dir/windows_pOSAK1.jsonl" window_operator_profile.schema.json 207
add_artifact windows_pO157.jsonl "$work_dir/windows_pO157.jsonl" window_operator_profile.schema.json 5796
add_artifact sample_pOSAK1.txt "$receipt_dir/sample_pOSAK1.txt" null "$(wc_lines "$receipt_dir/sample_pOSAK1.txt")"
add_artifact sample_pO157.txt "$receipt_dir/sample_pO157.txt" null "$(wc_lines "$receipt_dir/sample_pO157.txt")"
add_artifact products_runner.log "$receipt_dir/products_runner.log" null -1

commands_json="$(ruby -rjson -e '
  print JSON.generate([{
    "argv" => ["bash", "scripts/run_cohort_products.sh"],
    "exit_code" => 0,
    "stdout_sha256" => ARGV[0],
    "stderr_sha256" => ARGV[1],
  }])
' "$(sha256_file "$products_stdout")" "$(sha256_file "$products_stderr")")"

stage1_receipt() {
  local state="$1" finished="$2" validator_json="$3" cmds="$4"
  ruby -rjson -e '
    receipt = {
      "schema_version" => "1.0.0",
      "specification_version" => "0.1.0",
      "run_id" => ARGV[0],
      "state" => ARGV[1],
      "started_utc" => ARGV[2],
      "finished_utc" => ARGV[3],
      "atlas_source" => {"commit" => ARGV[4], "dirty" => false, "tree_sha256" => ARGV[5]},
      "producer" => {
        "language" => "Sounio",
        "language_source_commit" => ARGV[6],
        "compiler_path" => ARGV[7],
        "compiler_version" => ARGV[8],
        "compiler_sha256" => ARGV[9],
        "executable_sha256" => ARGV[10],
      },
      "acquisition" => {
        "tool" => "NCBI Datasets CLI",
        "version" => ARGV[11],
        "retrieved_utc" => ARGV[12],
        "filters" => {
          "assembly_accessions" => ["GCF_000005845.2", "GCF_000008865.2"],
          "scope" => "engineering-mini-cohort",
          "assembly_levels" => ["Complete Genome"],
        },
        "package_checksums_verified" => true,
      },
      "input_manifest_sha256" => ARGV[13],
      "parameters_sha256" => ARGV[14],
      "commands" => JSON.parse(ARGV[15]),
      "artifacts" => JSON.parse(ARGV[16]),
      "validator" => (ARGV[17] == "null" ? nil : JSON.parse(ARGV[17])),
    }
    print JSON.pretty_generate(receipt)
  ' "$run_id" "$state" "$started_utc" "$finished" \
    "$commit" "$tree_sha256" \
    "$sounio_commit" "${SOUNIO_REPO}/bin/souc" "$compiler_version" "$launcher_sha" "$elf_sha" \
    "$datasets_version" "$retrieved_utc" "$input_manifest_sha" "$params_sha" \
    "$cmds" "$artifacts_json" "$validator_json"
}

stage1_receipt generated_unvalidated "$(utc_now)" null "$commands_json" \
  > "$receipt_dir/run_receipt_stage1.json"
echo "DOSA_RUN_RECEIPT_STAGE1 run_id=$run_id sha256=$(sha256_file "$receipt_dir/run_receipt_stage1.json")"

# --- Stage 2: independent Julia validation -----------------------------------
windows_log="$work_dir/windows-runner.log"
products_log="$(log_field "$products_stdout" sounio_products_runner_log)"
flat_path="$work_dir/params/products.flat"
report="$receipt_dir/validation_report.txt"
: > "$report"

run_validator() { # label argv...
  local label="$1"; shift
  local out="$receipt_dir/${label}.stdout.log" err="$receipt_dir/${label}.stderr.log"
  set +e
  "$@" >"$out" 2>"$err"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "validator $label failed rc=$rc" >&2
    cat "$err" >&2
    exit 1
  fi
  {
    echo "DOSA_RECEIPT_VALIDATION label=$label rc=0"
    echo "argv=$*"
    cat "$out"
  } >> "$report"
  commands_json="$(ruby -rjson -e '
    c = JSON.parse(ARGV[0])
    c << {"argv" => ARGV[1..-3], "exit_code" => 0,
          "stdout_sha256" => ARGV[-2], "stderr_sha256" => ARGV[-1]}
    print JSON.generate(c)
  ' "$commands_json" "$@" "$(sha256_file "$out")" "$(sha256_file "$err")")"
}

run_validator validate_cohort_plasmids \
  julia --startup-file=no "$atlas_root/julia/scripts/validate_mini_pipeline.jl" \
  "$windows_log" "$work_dir" cohort_plasmids

run_validator validate_cohort_products \
  julia --startup-file=no "$atlas_root/julia/scripts/validate_cohort_products.jl" \
  "$products_log" "$atlas_root/data/cohort/mini" "$work_dir"

run_validator validate_window_sample_pOSAK1 \
  julia --startup-file=no "$atlas_root/julia/scripts/validate_window_sample.jl" \
  "$work_dir/windows_pOSAK1.jsonl" "$work_dir/pOSAK1/record.fa" \
  "$work_dir/pOSAK1/metadata.tsv" "$flat_path" "$receipt_dir/sample_check_pOSAK1.txt"

run_validator validate_window_sample_pO157 \
  julia --startup-file=no "$atlas_root/julia/scripts/validate_window_sample.jl" \
  "$work_dir/windows_pO157.jsonl" "$work_dir/pO157/record.fa" \
  "$work_dir/pO157/metadata.tsv" "$flat_path" "$receipt_dir/sample_check_pO157.txt"

# The independently re-derived sample manifests must equal the persisted ones.
cmp -s "$receipt_dir/sample_check_pOSAK1.txt" "$receipt_dir/sample_pOSAK1.txt" || {
  echo "sample manifest divergence for pOSAK1" >&2; exit 1; }
cmp -s "$receipt_dir/sample_check_pO157.txt" "$receipt_dir/sample_pO157.txt" || {
  echo "sample manifest divergence for pO157" >&2; exit 1; }

validator_json="$(ruby -rjson -e '
  print JSON.generate({
    "language" => "Julia",
    "version" => ARGV[0],
    "project_manifest_sha256" => ARGV[1],
    "sample_definition_sha256" => ARGV[2],
    "report_sha256" => ARGV[3],
    "status" => "pass",
    "absolute_tolerance" => 0,
  })
' "$julia_version" "$project_manifest_sha" "$sample_definition_sha" "$(sha256_file "$report")")"

stage1_receipt validated "$(utc_now)" "$validator_json" "$commands_json" \
  > "$receipt_dir/run_receipt.json"

# --- Structural receipt closure (hand-rolled; no jsonschema dependency) ------
ruby -rjson -e '
  schema = JSON.parse(File.read(ARGV[0]))
  [ARGV[1], ARGV[2]].each_with_index do |path, stage|
    r = JSON.parse(File.read(path))
    missing = schema.fetch("required").reject { |k| r.key?(k) }
    abort "receipt #{path} missing required keys: #{missing.join(",")}" unless missing.empty?
    abort "receipt #{path} has unknown keys" unless (r.keys - schema.fetch("required") - ["validator"]).empty?
    abort "schema_version drift" unless r["schema_version"] == "1.0.0"
    abort "producer language drift" unless r.dig("producer", "language") == "Sounio"
    abort "artifacts must be non-empty" if r["artifacts"].empty?
    r["artifacts"].each do |a|
      abort "artifact sha malformed" unless a["sha256"] =~ /\A[a-f0-9]{64}\z/
      abort "artifact path missing: #{a["path"]}" unless File.file?(a["path"])
      require "digest"
      actual = Digest::SHA256.file(a["path"]).hexdigest
      abort "artifact sha divergence for #{a["path"]}" unless actual == a["sha256"]
      abort "artifact size divergence for #{a["path"]}" unless File.size(a["path"]) == a["size_bytes"]
    end
    r["commands"].each do |c|
      abort "command without argv" if c["argv"].empty?
      abort "non-zero exit code in receipt" unless c["exit_code"] == 0
    end
    if stage == 0
      abort "stage 1 must be generated_unvalidated" unless r["state"] == "generated_unvalidated"
      abort "stage 1 must have a null validator" unless r["validator"].nil?
    else
      abort "stage 2 must be validated" unless r["state"] == "validated"
      v = r["validator"] or abort "stage 2 missing validator"
      abort "validator language drift" unless v["language"] == "Julia"
      abort "validator status must be pass" unless v["status"] == "pass"
      abort "tolerance must be zero" unless v["absolute_tolerance"] == 0
      abort "atlas tree must be clean in a validated receipt" if r.dig("atlas_source", "dirty")
      require "digest"
      abort "report sha divergence" unless Digest::SHA256.file(ARGV[3]).hexdigest == v["report_sha256"]
    end
  end
  puts "receipt_structural_check=PASS stages=2 artifacts=#{JSON.parse(File.read(ARGV[2]))["artifacts"].size}"
' "$atlas_root/schemas/run_receipt.schema.json" \
  "$receipt_dir/run_receipt_stage1.json" "$receipt_dir/run_receipt.json" "$report"

echo "DOSA_RUN_RECEIPT_OK run_id=$run_id commit=$commit receipt_sha256=$(sha256_file "$receipt_dir/run_receipt.json")"
