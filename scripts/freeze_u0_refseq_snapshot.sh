#!/usr/bin/env bash
# Freeze the fresh RefSeq Complete Genome inputs needed by the DOSA v3 U0 pilot.
#
# Acquisition and routing only: this script never computes DOSA metrics.  It
# refuses dirty source trees, tool drift, incomplete control candidates, output
# overwrite, and a local pending bundle larger than the 200 GiB policy limit.
#
# --from-discovery continues from an authenticated dehydrated archive plus
# rehydrated sequence reports. It does not rerun the universe download.
# --resume-package retries selected-package rehydrate in an existing snapshot
# that has not yet written freeze_receipt.json.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/ncbi-datasets.lock.json"
query_file="$atlas_root/data/v3/refseq_bacteria_complete_query.json"
selector="$atlas_root/scripts/select_u0_pilot.py"
control_ledger_binder="$atlas_root/scripts/bind_u0_control_ledger.py"
control_ledger_validator="$atlas_root/scripts/validate_u0_control_ledger.py"
source_manifest_builder="$atlas_root/scripts/build_u0_source_manifest.py"
sequence_report_merger="$atlas_root/scripts/merge_u0_package_sequence_reports.py"
download_estimator="$atlas_root/scripts/estimate_u0_selected_download.py"
rehydrate_completeness="$atlas_root/scripts/assert_u0_rehydrate_complete.py"
DATASETS_WORKERS=30
export GODEBUG="${GODEBUG:-http2client=0}"

usage() {
  echo "usage: $0 OUTPUT_DIRECTORY CONTROL_CANDIDATES.tsv" >&2
  echo "       $0 --from-discovery DISCOVERY_DIR --expected-dehydrated-sha256 HEX [--expected-assembly-count N] [--resume-package] OUTPUT_DIRECTORY CONTROL_CANDIDATES.tsv" >&2
  exit 2
}

from_discovery=""
expected_dehydrated_sha=""
expected_assembly_count=""
resume_package=""
positional=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --from-discovery)
      [[ "$#" -ge 2 ]] || usage
      from_discovery="$2"
      shift 2
      ;;
    --expected-dehydrated-sha256)
      [[ "$#" -ge 2 ]] || usage
      expected_dehydrated_sha="$2"
      shift 2
      ;;
    --expected-assembly-count)
      [[ "$#" -ge 2 ]] || usage
      expected_assembly_count="$2"
      shift 2
      ;;
    --resume-package)
      resume_package="1"
      shift
      ;;
    -*)
      usage
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

[[ "${#positional[@]}" -eq 2 ]] || usage
output_dir="${positional[0]}"
control_candidates_source="${positional[1]}"

if [[ -n "$from_discovery" ]]; then
  [[ -n "$expected_dehydrated_sha" ]] || {
    echo "BLOCKED: --from-discovery requires --expected-dehydrated-sha256" >&2
    exit 2
  }
  [[ -n "$expected_assembly_count" ]] || expected_assembly_count=64971
else
  [[ -z "$expected_dehydrated_sha" && -z "$expected_assembly_count" ]] || {
    echo "BLOCKED: discovery authentication flags require --from-discovery" >&2
    exit 2
  }
fi

datasets_bin="${DOSA_DATASETS_BIN:-$(command -v datasets || true)}"
dataformat_bin="${DOSA_DATAFORMAT_BIN:-$(command -v dataformat || true)}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "BLOCKED: no SHA-256 utility" >&2
    return 2
  fi
}

[[ -x "$datasets_bin" ]] || { echo "BLOCKED: DOSA_DATASETS_BIN is not executable" >&2; exit 2; }
[[ -x "$dataformat_bin" ]] || { echo "BLOCKED: DOSA_DATAFORMAT_BIN is not executable" >&2; exit 2; }
[[ -s "$control_candidates_source" ]] || {
  echo "BLOCKED: control candidates are missing or empty: $control_candidates_source" >&2
  exit 2
}
if [[ -n "$resume_package" ]]; then
  [[ -n "$from_discovery" ]] || {
    echo "BLOCKED: --resume-package requires --from-discovery" >&2
    exit 2
  }
  [[ -d "$output_dir" && ! -L "$output_dir" ]] || {
    echo "BLOCKED: resume package directory is missing: $output_dir" >&2
    exit 2
  }
  [[ ! -e "$output_dir/freeze_receipt.json" ]] || {
    echo "BLOCKED: refusing to overwrite an existing freeze receipt: $output_dir/freeze_receipt.json" >&2
    exit 2
  }
else
  [[ ! -e "$output_dir" ]] || { echo "BLOCKED: refusing to overwrite snapshot directory: $output_dir" >&2; exit 2; }
fi
[[ -z "$(git -C "$atlas_root" status --porcelain)" ]] || {
  echo "BLOCKED: snapshot freeze requires a clean atlas source tree" >&2
  exit 2
}

expected_datasets_sha="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("datasets").fetch("sha256")' "$lock_file")"
expected_dataformat_sha="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("dataformat").fetch("sha256")' "$lock_file")"
expected_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("datasets").fetch("version")' "$lock_file")"
actual_datasets_sha="$(sha256_file "$datasets_bin")"
actual_dataformat_sha="$(sha256_file "$dataformat_bin")"
actual_version="$($datasets_bin version | sed -n 's/^datasets version: //p')"
[[ "$actual_datasets_sha" == "$expected_datasets_sha" ]] || { echo "BLOCKED: datasets SHA-256 drift" >&2; exit 2; }
[[ "$actual_dataformat_sha" == "$expected_dataformat_sha" ]] || { echo "BLOCKED: dataformat SHA-256 drift" >&2; exit 2; }
[[ "$actual_version" == "$expected_version" ]] || { echo "BLOCKED: datasets version drift" >&2; exit 2; }

mkdir -p "$output_dir/reports" "$output_dir/discovery" "$output_dir/package"
cp "$control_candidates_source" "$output_dir/control_candidates.tsv"
control_candidates="$output_dir/control_candidates.tsv"
assembly_report="$output_dir/reports/assembly_data_report.jsonl"
sequence_report="$output_dir/reports/sequence_data_report.jsonl"
merge_receipt="$output_dir/reports/sequence_report_merge_receipt.json"
discovery_catalog="$output_dir/reports/dataset_catalog.json"
selection="$output_dir/u0_pilot_selection.jsonl"
full_replicon_inventory="$output_dir/full_replicon_inventory.jsonl"
estimate_receipt="$output_dir/selected_download_estimate.json"

if [[ -n "$from_discovery" ]]; then
  freeze_mode="continue_from_discovery"
  [[ -d "$from_discovery" && ! -L "$from_discovery" ]] || {
    echo "BLOCKED: discovery directory is missing: $from_discovery" >&2
    exit 2
  }
  discovery_zip="$from_discovery/refseq_complete_dehydrated.zip"
  [[ -f "$discovery_zip" && ! -L "$discovery_zip" ]] || {
    echo "BLOCKED: discovery archive is missing: $discovery_zip" >&2
    exit 2
  }
  discovery_archive_sha="$(sha256_file "$discovery_zip")"
  [[ "$discovery_archive_sha" == "$expected_dehydrated_sha" ]] || {
    echo "BLOCKED: discovery archive SHA-256 drift" >&2
    exit 2
  }
  discovery_data="$from_discovery/unpacked/ncbi_dataset/data"
  [[ -d "$discovery_data" && ! -L "$discovery_data" ]] || {
    echo "BLOCKED: discovery unpacked data root is missing" >&2
    exit 2
  }
  [[ -f "$discovery_data/assembly_data_report.jsonl" && ! -L "$discovery_data/assembly_data_report.jsonl" ]] || {
    echo "BLOCKED: discovery assembly report is missing" >&2
    exit 2
  }
  [[ -f "$discovery_data/dataset_catalog.json" && ! -L "$discovery_data/dataset_catalog.json" ]] || {
    echo "BLOCKED: discovery dataset catalog is missing" >&2
    exit 2
  }
  if command -v sha256sum >/dev/null 2>&1; then
    zip_assembly_sha="$(unzip -p "$discovery_zip" ncbi_dataset/data/assembly_data_report.jsonl | sha256sum | awk '{print $1}')"
  else
    zip_assembly_sha="$(unzip -p "$discovery_zip" ncbi_dataset/data/assembly_data_report.jsonl | shasum -a 256 | awk '{print $1}')"
  fi
  unpacked_assembly_sha="$(sha256_file "$discovery_data/assembly_data_report.jsonl")"
  [[ "$zip_assembly_sha" == "$unpacked_assembly_sha" ]] || {
    echo "BLOCKED: unpacked assembly report does not match the authenticated discovery archive" >&2
    exit 2
  }
  if [[ -z "$resume_package" ]]; then
    cp "$discovery_zip" "$output_dir/discovery/refseq_complete_dehydrated.zip"
    cp "$discovery_data/assembly_data_report.jsonl" "$assembly_report"
    cp "$discovery_data/dataset_catalog.json" "$discovery_catalog"
    python3 "$sequence_report_merger" \
      --data-root "$discovery_data" \
      --assembly-report "$assembly_report" \
      --output "$sequence_report" \
      --receipt "$merge_receipt" \
      --expected-assembly-count "$expected_assembly_count"
  fi
else
  [[ -z "$resume_package" ]] || {
    echo "BLOCKED: --resume-package requires --from-discovery" >&2
    exit 2
  }
  freeze_mode="full_discovery"
  "$datasets_bin" download genome taxon bacteria \
    --assembly-level complete \
    --assembly-source RefSeq \
    --assembly-version current \
    --include genome,gbff,seq-report \
    --dehydrated \
    --no-progressbar \
    --filename "$output_dir/discovery/refseq_complete_dehydrated.zip"
  discovery_archive_sha="$(sha256_file "$output_dir/discovery/refseq_complete_dehydrated.zip")"
  unzip -q "$output_dir/discovery/refseq_complete_dehydrated.zip" -d "$output_dir/discovery/unpacked"
  cp "$output_dir/discovery/unpacked/ncbi_dataset/data/assembly_data_report.jsonl" "$assembly_report"
  cp "$output_dir/discovery/unpacked/ncbi_dataset/data/dataset_catalog.json" "$discovery_catalog"
  "$datasets_bin" rehydrate \
    --directory "$output_dir/discovery/unpacked" \
    --match sequence_report.jsonl \
    --max-workers "$DATASETS_WORKERS" \
    --no-progressbar
  python3 "$sequence_report_merger" \
    --data-root "$output_dir/discovery/unpacked/ncbi_dataset/data" \
    --assembly-report "$assembly_report" \
    --output "$sequence_report" \
    --receipt "$merge_receipt"
fi

if [[ -n "$resume_package" ]]; then
  for required in \
    "$output_dir/discovery/refseq_complete_dehydrated.zip" \
    "$assembly_report" \
    "$sequence_report" \
    "$merge_receipt" \
    "$discovery_catalog" \
    "$selection" \
    "$full_replicon_inventory" \
    "$estimate_receipt" \
    "$output_dir/assembly_accessions.txt" \
    "$output_dir/package/ncbi_dataset_dehydrated.zip" \
    "$output_dir/package/rehydrated/ncbi_dataset/fetch.txt"
  do
    [[ -f "$required" && ! -L "$required" && -s "$required" ]] || {
      echo "BLOCKED: resume artifact missing or empty: $required" >&2
      exit 2
    }
  done
  output_discovery_sha="$(sha256_file "$output_dir/discovery/refseq_complete_dehydrated.zip")"
  [[ "$output_discovery_sha" == "$expected_dehydrated_sha" ]] || {
    echo "BLOCKED: snapshot discovery archive SHA-256 drift" >&2
    exit 2
  }
fi

[[ -s "$assembly_report" && -s "$sequence_report" && -s "$merge_receipt" ]] || {
  echo "BLOCKED: discovery reports were not materialized" >&2
  exit 2
}

if [[ -z "$resume_package" ]]; then
python3 - "$sequence_report" "$full_replicon_inventory" <<'PY'
import json, pathlib, re, sys
source, target = map(pathlib.Path, sys.argv[1:])
accession_re = re.compile(r"^[A-Z][A-Z0-9_]*\.[0-9]+$")
records = {}
for line_number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), start=1):
    if not line:
        continue
    row = json.loads(line)
    snake_accession = row.get("refseq_accession")
    camel_accession = row.get("refseqAccession")
    if snake_accession is not None and camel_accession is not None and snake_accession != camel_accession:
        raise SystemExit(f"BLOCKED: conflicting RefSeq accession fields in sequence report line {line_number}")
    accession = snake_accession if snake_accession is not None else camel_accession
    length = row.get("length")
    if not isinstance(accession, str) or accession_re.fullmatch(accession) is None:
        raise SystemExit(f"BLOCKED: invalid RefSeq accession in sequence report line {line_number}")
    if isinstance(length, bool) or not isinstance(length, int) or length < 1:
        raise SystemExit(f"BLOCKED: invalid sequence length in sequence report line {line_number}")
    if accession in records and records[accession] != length:
        raise SystemExit(f"BLOCKED: conflicting duplicate sequence report row: {accession}")
    records[accession] = length
if not records:
    raise SystemExit("BLOCKED: full replicon inventory would be empty")
with target.open("x", encoding="utf-8", newline="\n") as handle:
    for accession in sorted(records):
        handle.write(json.dumps({"sequence_accession_version": accession, "length_bp": records[accession]}, sort_keys=True, separators=(",", ":")) + "\n")
PY

python3 "$selector" \
  --assemblies "$assembly_report" \
  --sequences "$sequence_report" \
  --control-candidates "$control_candidates" \
  --output "$selection"

python3 "$download_estimator" \
  --selection "$selection" \
  --catalog "$discovery_catalog" \
  --output "$estimate_receipt"

python3 - "$selection" "$output_dir/assembly_accessions.txt" <<'PY'
import json, pathlib, sys
source, target = map(pathlib.Path, sys.argv[1:])
assemblies = sorted({json.loads(line)["assembly_accession_version"] for line in source.read_text().splitlines() if line})
target.write_text("".join(value + "\n" for value in assemblies), encoding="utf-8")
PY

"$datasets_bin" download genome accession \
  --inputfile "$output_dir/assembly_accessions.txt" \
  --include genome,gbff,seq-report \
  --dehydrated \
  --no-progressbar \
  --filename "$output_dir/package/ncbi_dataset_dehydrated.zip"

unzip -q "$output_dir/package/ncbi_dataset_dehydrated.zip" -d "$output_dir/package/rehydrated"
fi

estimate_within="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("within_policy")' "$estimate_receipt")"
estimate_bytes="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("estimated_uncompressed_bytes")' "$estimate_receipt")"
selected_assemblies="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("selected_assemblies")' "$estimate_receipt")"
selected_replicons="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("selected_replicons")' "$estimate_receipt")"
[[ "$estimate_within" == "true" ]] || {
  echo "BLOCKED: selected download estimate exceeds 200 GiB policy: $estimate_bytes" >&2
  exit 2
}
echo "DOSA_U0_SELECTED_DOWNLOAD_ESTIMATE freeze_mode=$freeze_mode assemblies=$selected_assemblies replicons=$selected_replicons uncompressed_bytes=$estimate_bytes scientific_metrics_computed=false"

"$datasets_bin" rehydrate \
  --directory "$output_dir/package/rehydrated" \
  --max-workers "$DATASETS_WORKERS" \
  --no-progressbar
python3 "$rehydrate_completeness" \
  --package-root "$output_dir/package/rehydrated" \
  --receipt "$output_dir/reports/rehydrate_complete_receipt.json"

if [[ -n "$resume_package" ]]; then
  rm -f \
    "$output_dir/control_ledger.tsv" \
    "$output_dir/control_binding_receipt.json" \
    "$output_dir/control_ledger_receipt.json" \
    "$output_dir/SHA256SUMS" \
    "$output_dir/source_manifest.json" \
    "$output_dir/source_integrity_receipt.json" \
    "$output_dir/source_index.json" \
    "$output_dir/u0_work_units.tsv"
fi

# Bind the pre-download inclusion declarations to exact files only after the
# selected package exists. The binding receipt remains explicitly unvalidated
# until the independent semantic validator below proves every claim.
control_ledger="$output_dir/control_ledger.tsv"
control_binding_receipt="$output_dir/control_binding_receipt.json"
python3 "$control_ledger_binder" \
  --control-candidates "$control_candidates" \
  --package-root "$output_dir/package/rehydrated" \
  --output-ledger "$control_ledger" \
  --output-receipt "$control_binding_receipt"

# The generated ledger cannot be satisfied by an unrelated duplicate hash:
# validate exact accession/assembly/path/hash binding and each semantic claim
# before any source manifest is built.
control_ledger_receipt="$output_dir/control_ledger_receipt.json"
python3 "$control_ledger_validator" \
  --controls "$control_ledger" \
  --package-root "$output_dir/package/rehydrated" \
  --output "$control_ledger_receipt"

find "$output_dir/package/rehydrated" -type f -print0 | sort -z | while IFS= read -r -d '' file; do
  printf '%s  %s\n' "$(sha256_file "$file")" "${file#"$output_dir/"}"
done > "$output_dir/SHA256SUMS"

commit="$(git -C "$atlas_root" rev-parse HEAD)"
query_sha="$(sha256_file "$query_file")"
selection_sha="$(sha256_file "$selection")"
manifest_sha="$(sha256_file "$output_dir/SHA256SUMS")"
control_candidates_sha="$(sha256_file "$control_candidates")"
control_ledger_sha="$(sha256_file "$control_ledger")"
control_binding_receipt_sha="$(sha256_file "$control_binding_receipt")"
control_ledger_receipt_sha="$(sha256_file "$control_ledger_receipt")"
merge_receipt_sha="$(sha256_file "$merge_receipt")"
estimate_receipt_sha="$(sha256_file "$estimate_receipt")"

catalog_count="$(find "$output_dir/package/rehydrated" -type f -name dataset_catalog.json | wc -l | tr -d '[:space:]')"
[[ "$catalog_count" == "1" ]] || {
  echo "BLOCKED: expected exactly one dataset_catalog.json in rehydrated package, found $catalog_count" >&2
  exit 2
}
catalog_file="$(find "$output_dir/package/rehydrated" -type f -name dataset_catalog.json -print -quit)"
python3 "$source_manifest_builder" \
  --snapshot-root "$output_dir" \
  --selection "$selection" \
  --query-source "$query_file" \
  --tool-lock-source "$lock_file" \
  --package-root "$output_dir/package/rehydrated" \
  --dehydrated-archive "$output_dir/package/ncbi_dataset_dehydrated.zip" \
  --catalog "$catalog_file" \
  --checksums "$output_dir/SHA256SUMS" \
  --manifest-output "$output_dir/source_manifest.json" \
  --integrity-output "$output_dir/source_integrity_receipt.json" \
  --source-index-output "$output_dir/source_index.json" \
  --retrieved-utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --package-id "u0-$(basename "$output_dir")" \
  --manifest-id "u0-source-$(basename "$output_dir")"

source_manifest_sha="$(sha256_file "$output_dir/source_manifest.json")"
source_integrity_sha="$(sha256_file "$output_dir/source_integrity_receipt.json")"
source_index_sha="$(sha256_file "$output_dir/source_index.json")"
full_replicon_inventory_sha="$(sha256_file "$full_replicon_inventory")"
work_unit_manifest="$output_dir/u0_work_units.tsv"
python3 - "$output_dir" "$selection" "$output_dir/source_index.json" "$atlas_root/data/v3/u0_parameters.json" "$work_unit_manifest" <<'PY'
import hashlib, json, pathlib, re, sys
snapshot, selection_path, index_path, parameters_path, output_path = map(pathlib.Path, sys.argv[1:])
ACCESSION_RE = re.compile(r"^[A-Z][A-Z0-9_]*[0-9]\.[0-9]+$")
FASTA_ALPHABET = frozenset("ACGTURYSWKMBDHVN")

def fasta_header_accession(text: str):
    parts = text.split()
    if not parts or ACCESSION_RE.fullmatch(parts[0]) is None:
        return None
    return parts[0]

def extract_selected_record(path: pathlib.Path, accession: str) -> str:
    current = None
    chunks = []
    with path.open(encoding="ascii") as handle:
        for line_no, raw in enumerate(handle, start=1):
            line = raw.rstrip("\r\n")
            if line.startswith(">"):
                if current == accession:
                    break
                header = fasta_header_accession(line[1:])
                if header is None:
                    raise SystemExit(f"BLOCKED: invalid FASTA header for {accession} at {path}:{line_no}")
                current = header
                chunks = []
                continue
            if current != accession:
                continue
            sequence = "".join(line.split()).upper()
            if not sequence or any(base not in FASTA_ALPHABET for base in sequence):
                raise SystemExit(f"BLOCKED: invalid FASTA sequence for {accession} at {path}:{line_no}")
            chunks.append(sequence)
    sequence = "".join(chunks)
    if current != accession or not sequence:
        raise SystemExit(f"BLOCKED: selected accession missing from FASTA: {accession}")
    return sequence

selection = {}
for line in selection_path.read_text(encoding="utf-8").splitlines():
    if not line:
        continue
    row = json.loads(line)
    accession = row["sequence_accession_version"]
    if accession in selection:
        raise SystemExit(f"BLOCKED: duplicate work-unit accession: {accession}")
    selection[accession] = row
index = json.loads(index_path.read_text(encoding="utf-8"))
records = index.get("records")
if index.get("source_index_version") != "dosa-v3-source-index-1" or set(records or {}) != set(selection):
    raise SystemExit("BLOCKED: source index and selection differ before work-unit construction")
parameters_sha = hashlib.sha256(parameters_path.read_bytes()).hexdigest()
header = (
    "u0_manifest_version", "work_unit_id", "assembly_accession_version",
    "sequence_accession_version", "replicon_class", "source_locator",
    "source_file_sha256", "sequence_sha256", "sequence_length", "declared_alphabet",
    "parameters_sha256", "scale", "stride", "k_min", "k_max", "null_model",
    "null_replicates",
)
rows = []
for accession in sorted(selection):
    selected = selection[accession]
    record = records[accession]
    locator = record["locator"]
    relative = pathlib.PurePosixPath(locator)
    if relative.is_absolute() or relative.as_posix() != locator or any(part in ("", ".", "..") for part in relative.parts):
        raise SystemExit(f"BLOCKED: unsafe source-index locator for {accession}")
    source = snapshot.joinpath(*relative.parts)
    if source.is_symlink() or not source.is_file():
        raise SystemExit(f"BLOCKED: unavailable canonical FASTA for {accession}")
    try:
        source.resolve(strict=True).relative_to(snapshot.resolve(strict=True))
    except ValueError as exc:
        raise SystemExit(f"BLOCKED: canonical FASTA escapes snapshot for {accession}") from exc
    sequence = extract_selected_record(source, accession)
    canonical_sha = hashlib.sha256(f">{accession}\n{sequence}\n".encode("ascii")).hexdigest()
    sequence_sha = hashlib.sha256(sequence.encode("ascii")).hexdigest()
    if canonical_sha != record["canonical_sequence_input_sha256"]:
        raise SystemExit(f"BLOCKED: canonical FASTA hash mismatch for {accession}")
    if sequence_sha != record["normalized_sequence_sha256"] or len(sequence) != selected["length_bp"]:
        raise SystemExit(f"BLOCKED: canonical sequence identity mismatch for {accession}")
    alphabet = "acgt" if all(base in "ACGT" for base in sequence) else "non_acgt"
    for scale in (16, 100, 500, 1000):
        rows.append((
            "1.0.0", f"{accession}@{scale}", selected["assembly_accession_version"],
            accession, selected["replicon_class"], locator,
            record["canonical_sequence_input_sha256"], sequence_sha, str(len(sequence)), alphabet,
            parameters_sha, str(scale), str(scale), "1", "8",
            "euler_wilson_fixed_endpoints_v1", "1000",
        ))
with output_path.open("x", encoding="utf-8", newline="\n") as handle:
    handle.write("\t".join(header) + "\n")
    for row in rows:
        handle.write("\t".join(row) + "\n")
PY
work_unit_manifest_sha="$(sha256_file "$work_unit_manifest")"
pending_bytes="$(du -sk "$output_dir" | awk '{print $1 * 1024}')"
max_pending_bytes=$((200 * 1024 * 1024 * 1024))
if (( pending_bytes > max_pending_bytes )); then
  echo "BLOCKED: local pending snapshot exceeds 200 GiB policy: $pending_bytes" >&2
  exit 2
fi

python3 - "$output_dir/freeze_receipt.json" "$commit" "$actual_version" "$actual_datasets_sha" "$actual_dataformat_sha" "$query_sha" "$selection_sha" "$manifest_sha" "$control_candidates_sha" "$control_ledger_sha" "$control_binding_receipt_sha" "$control_ledger_receipt_sha" "$source_manifest_sha" "$source_integrity_sha" "$source_index_sha" "$full_replicon_inventory_sha" "$work_unit_manifest_sha" "$pending_bytes" "$freeze_mode" "$discovery_archive_sha" "$merge_receipt_sha" "$estimate_receipt_sha" "$estimate_bytes" "$selected_assemblies" "$selected_replicons" <<'PY'
import datetime, json, pathlib, sys
target = pathlib.Path(sys.argv[1])
receipt = {
    "schema_version": "dosa-u0-source-freeze-1",
    "status": "frozen_unprocessed",
    "finished_utc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "atlas_commit": sys.argv[2],
    "datasets_version": sys.argv[3],
    "datasets_sha256": sys.argv[4],
    "dataformat_sha256": sys.argv[5],
    "query_sha256": sys.argv[6],
    "selection_sha256": sys.argv[7],
    "package_manifest_sha256": sys.argv[8],
    "control_candidates_sha256": sys.argv[9],
    "control_ledger_sha256": sys.argv[10],
    "control_binding_receipt_sha256": sys.argv[11],
    "control_ledger_receipt_sha256": sys.argv[12],
    "source_manifest_sha256": sys.argv[13],
    "source_integrity_receipt_sha256": sys.argv[14],
    "source_index_sha256": sys.argv[15],
    "full_replicon_inventory_sha256": sys.argv[16],
    "work_unit_manifest_sha256": sys.argv[17],
    "pending_bytes": int(sys.argv[18]),
    "freeze_mode": sys.argv[19],
    "discovery_archive_sha256": sys.argv[20],
    "sequence_report_merge_receipt_sha256": sys.argv[21],
    "selected_download_estimate_sha256": sys.argv[22],
    "selected_download_estimate_bytes": int(sys.argv[23]),
    "selected_assemblies": int(sys.argv[24]),
    "selected_replicons": int(sys.argv[25]),
    "scientific_metrics_computed": False,
}
target.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY

echo "DOSA_U0_SOURCE_FREEZE_OK output=$output_dir freeze_mode=$freeze_mode receipt_sha256=$(sha256_file "$output_dir/freeze_receipt.json") scientific_metrics_computed=false"
