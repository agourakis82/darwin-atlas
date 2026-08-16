#!/usr/bin/env bash
# Exercise the source closure builder on a tiny synthetic package only.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builder="$atlas_root/scripts/build_u0_source_manifest.py"
fixture="$atlas_root/data/fixtures/u0_source_manifest"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-source-manifest.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

make_checksums() {
  local snapshot="$1"
  (
    cd "$snapshot"
    find package -type f ! -type l -print | LC_ALL=C sort | while IFS= read -r file; do
      if command -v sha256sum >/dev/null 2>&1; then sha256sum "$file"; else shasum -a 256 "$file"; fi
    done
  ) > "$snapshot/SHA256SUMS"
}

prepare() {
  local target="$1"
  cp -R "$fixture/snapshot" "$target"
  make_checksums "$target"
}

run_builder() {
  local snapshot="$1"
  python3 "$builder" \
    --snapshot-root "$snapshot" \
    --selection "$snapshot/u0_pilot_selection.jsonl" \
    --query-source "$fixture/input/query.json" \
    --tool-lock-source "$fixture/input/tool-lock.json" \
    --package-root "$snapshot/package/rehydrated" \
    --dehydrated-archive "$snapshot/package/ncbi_dataset_dehydrated.zip" \
    --catalog "$snapshot/package/dataset_catalog.json" \
    --checksums "$snapshot/SHA256SUMS" \
    --manifest-output "$snapshot/source_manifest.json" \
    --integrity-output "$snapshot/source_integrity_receipt.json" \
    --source-index-output "$snapshot/source_index.json" \
    --retrieved-utc 2026-08-14T12:00:00Z \
    --package-id u0-fixture-package \
    --manifest-id u0-fixture-source
}

expect_fail() {
  local expected="$1"; shift
  set +e
  "$@" >"$tmp/fail.out" 2>"$tmp/fail.err"
  local rc=$?
  set -e
  [[ "$rc" -eq 11 ]] || { cat "$tmp/fail.out" "$tmp/fail.err" >&2; echo "expected rc=11, got $rc" >&2; exit 1; }
  grep -q "$expected" "$tmp/fail.err" || { cat "$tmp/fail.err" >&2; echo "missing failure marker $expected" >&2; exit 1; }
}

good="$tmp/good"
prepare "$good"
run_builder "$good" > "$tmp/good.json"
python3 - "$good" "$tmp/good.json" <<'PY'
import hashlib, json, pathlib, sys
snapshot, output = map(pathlib.Path, sys.argv[1:])
summary = json.loads(output.read_text())
manifest = json.loads((snapshot / "source_manifest.json").read_text())
receipt = json.loads((snapshot / "source_integrity_receipt.json").read_text())
source_index = json.loads((snapshot / "source_index.json").read_text())
assert summary["status"] == "built" and summary["records"] == 1
assert summary["source_index"] == "source_index.json"
assert manifest["schema_version"] == "3.0.0"
assert manifest["query"]["path"] == "provenance/refseq_bacteria_complete_query.json"
assert manifest["package"]["selected_assets_complete"] is True
assert len(manifest["package_assets"]) == 3
assert all(not value.startswith("/") and ".." not in value for value in [manifest["package"]["package_root"], manifest["query"]["path"]])
record = receipt["records"][0]
assert record["normalized_fasta_length_bp"] == 8
assert record["normalized_fasta_sha256"] == hashlib.sha256(b"ACGTACGT").hexdigest()
assert record["canonical_sequence_input_sha256"] == "17e34e9a5e5d4eccffd2c172c3051e2c9dcb6c3da78074b49d25750bc27507cb"
assert record["canonical_sequence_input_sha256"] != record["normalized_fasta_sha256"]
assert receipt["source_manifest_sha256"] == hashlib.sha256((snapshot / "source_manifest.json").read_bytes()).hexdigest()
indexed = source_index["records"]["NC_000001.1"]
assert source_index["source_index_version"] == "dosa-v3-source-index-1"
assert indexed == {
    "locator": "package/rehydrated/ncbi_dataset/data/GCF_000000001.1/GCF_000000001.1_genomic.fna",
    "canonical_sequence_input_sha256": record["canonical_sequence_input_sha256"],
    "normalized_sequence_sha256": record["normalized_fasta_sha256"],
    "source_manifest_sha256": receipt["source_manifest_sha256"],
    "source_integrity_sha256": hashlib.sha256((snapshot / "source_integrity_receipt.json").read_bytes()).hexdigest(),
}
print("U0_SOURCE_MANIFEST_FIXTURE_PASS records=1 assets=3")
PY

ncbi_header="$tmp/ncbi-header"; prepare "$ncbi_header"
python3 - "$ncbi_header/package/rehydrated/ncbi_dataset/data/GCF_000000001.1/GCF_000000001.1_genomic.fna" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text(
    ">NC_000001.1 Escherichia coli plasmid pPG20180062.1-IncI2, complete sequence\nACGTACGT\n"
)
PY
make_checksums "$ncbi_header"
run_builder "$ncbi_header" > "$tmp/ncbi-header.json"
python3 - "$ncbi_header" "$tmp/ncbi-header.json" <<'PY'
import json, pathlib, sys
snapshot, output = map(pathlib.Path, sys.argv[1:])
summary = json.loads(output.read_text())
assert summary["status"] == "built" and summary["records"] == 1
print("U0_SOURCE_MANIFEST_NCBI_DESCRIPTION_HEADER_PASS")
PY

tampered="$tmp/tampered"; prepare "$tampered"
printf 'N\n' >> "$tampered/package/rehydrated/ncbi_dataset/data/GCF_000000001.1/GCF_000000001.1_genomic.fna"
expect_fail CHECKSUM_MISMATCH run_builder "$tampered"

duplicate="$tmp/duplicate"; prepare "$duplicate"
python3 - "$duplicate/u0_pilot_selection.jsonl" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text() * 2)
PY
expect_fail DUPLICATE_SELECTION_ACCESSION run_builder "$duplicate"

unversioned="$tmp/unversioned"; prepare "$unversioned"
python3 - "$unversioned/u0_pilot_selection.jsonl" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text('{"assembly_accession_version":"GCF_000000001.1","sequence_accession_version":"NC_000001"}\n')
PY
expect_fail UNVERSIONED_ACCESSION run_builder "$unversioned"

missing="$tmp/missing"; prepare "$missing"
mv "$missing/package/rehydrated/ncbi_dataset/data/GCF_000000001.1/GCF_000000001.1_genomic.gbff" "$missing/removed.gbff"
expect_fail MISSING_ASSET run_builder "$missing"

coverage="$tmp/coverage"; prepare "$coverage"
python3 - "$coverage/package/rehydrated/ncbi_dataset/data/GCF_000000001.1/GCF_000000001.1_genomic.fna" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text('>NC_999999.1 synthetic fixture\nACGTACGT\n')
PY
make_checksums "$coverage"
expect_fail FASTA_ACCESSION_MISSING run_builder "$coverage"

escaped="$tmp/escaped"; prepare "$escaped"
expect_fail PATH_OUTSIDE_SNAPSHOT python3 "$builder" \
  --snapshot-root "$escaped" --selection "$escaped/u0_pilot_selection.jsonl" \
  --query-source "$fixture/input/query.json" --tool-lock-source "$fixture/input/tool-lock.json" \
  --package-root "$escaped/package/rehydrated" --dehydrated-archive "$escaped/package/ncbi_dataset_dehydrated.zip" \
  --catalog "$fixture/input/query.json" --checksums "$escaped/SHA256SUMS" \
  --manifest-output "$escaped/source_manifest.json" --integrity-output "$escaped/source_integrity_receipt.json" \
  --source-index-output /tmp/source_index.json \
  --retrieved-utc 2026-08-14T12:00:00Z

symlinked="$tmp/symlinked"; prepare "$symlinked"
target="$symlinked/package/rehydrated/ncbi_dataset/data/GCF_000000001.1/GCF_000000001.1_genomic.fna"
mv "$target" "$symlinked/real.fna"
ln -s "$symlinked/real.fna" "$target"
expect_fail SYMLINK_FORBIDDEN run_builder "$symlinked"

duplicate_output="$tmp/duplicate-output"; prepare "$duplicate_output"
expect_fail DUPLICATE_OUTPUT_PATH python3 "$builder" \
  --snapshot-root "$duplicate_output" --selection "$duplicate_output/u0_pilot_selection.jsonl" \
  --query-source "$fixture/input/query.json" --tool-lock-source "$fixture/input/tool-lock.json" \
  --package-root "$duplicate_output/package/rehydrated" --dehydrated-archive "$duplicate_output/package/ncbi_dataset_dehydrated.zip" \
  --catalog "$duplicate_output/package/dataset_catalog.json" --checksums "$duplicate_output/SHA256SUMS" \
  --manifest-output "$duplicate_output/closure.json" --integrity-output "$duplicate_output/closure.json" \
  --source-index-output "$duplicate_output/source_index.json" --retrieved-utc 2026-08-14T12:00:00Z

echo "U0_SOURCE_MANIFEST_FAIL_CLOSED_PASS cases=8"
