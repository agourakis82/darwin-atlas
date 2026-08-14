#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-capacity.XXXXXX")"
trap 'rm -rf "$temp"' EXIT

if ! python3 - <<'PY'
import sys
try:
    import duckdb
except ModuleNotFoundError:
    sys.exit(2)
sys.exit(0 if duckdb.__version__ == "1.5.5" else 2)
PY
then
  echo "BLOCKED: duckdb==1.5.5 is required for the U0 capacity test" >&2
  exit 2
fi

python3 - "$temp" <<'PY'
import hashlib
import json
import pathlib
import sys

import duckdb

assert duckdb.__version__ == "1.5.5"
root = pathlib.Path(sys.argv[1])
(root / "replicons.jsonl").write_text(
    json.dumps({"sequence_accession_version":"NC_000001.1","length_bp":10000}, separators=(",",":")) + "\n",
    encoding="utf-8",
)


def sql_string(path: pathlib.Path) -> str:
    return str(path).replace("'", "''")


def write_manifest(package: pathlib.Path, payload: pathlib.Path, scale: int, rows: int) -> None:
    record = {
        "name": payload.relative_to(package).as_posix(),
        "scale": str(scale),
        "rows": rows,
        "bytes": payload.stat().st_size,
        "sha256": hashlib.sha256(payload.read_bytes()).hexdigest(),
        "compression": "zstd",
    }
    manifest = {
        "manifest_version":"dosa-v3-u0-dev-payload-manifest-3",
        "package_version":"U0-dev",
        "payloads":[record],
    }
    (package / "dosa-payload-manifest.json").write_text(
        json.dumps(manifest, separators=(",",":")) + "\n",
        encoding="utf-8",
    )


def write_parquet_package(
    name: str,
    declared_scale: int,
    *,
    actual_scale: int | None = None,
    actual_rows: int = 10,
    declared_rows: int | None = None,
    compression: str = "zstd",
) -> pathlib.Path:
    package = root / name
    payload = package / f"scale={declared_scale}" / "sha256_bucket=00" / "part-00000.parquet"
    payload.parent.mkdir(parents=True)
    row_scale = declared_scale if actual_scale is None else actual_scale
    con = duckdb.connect(":memory:")
    try:
        con.execute(
            f"COPY (SELECT {row_scale}::BIGINT AS scale, range::BIGINT AS row_id "
            f"FROM range({actual_rows})) TO '{sql_string(payload)}' "
            f"(FORMAT PARQUET, COMPRESSION {compression.upper()})"
        )
    finally:
        con.close()
    write_manifest(package, payload, declared_scale, actual_rows if declared_rows is None else declared_rows)
    return package


valid = {scale: write_parquet_package(f"package-{scale}", scale) for scale in (16, 100, 500, 1000)}
package_entries = []
for scale, package in sorted(valid.items()):
    manifest = package / "dosa-payload-manifest.json"
    package_entries.append({
        "package_manifest_id": f"fixture-scale-{scale}",
        "path": f"package-{scale}/dosa-payload-manifest.json",
        "sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
        "size_bytes": manifest.stat().st_size,
        "table_filename": "window_operator_profiles.parquet",
        "manifest_version": "dosa-v3-u0-dev-payload-manifest-3",
        "package_version": "U0-dev",
    })
single = lambda filename, schema, digest: {
    "filename": filename, "schema_id": schema, "record_count": 1,
    "storage": {"layout":"single_file","path":filename,"sha256":digest,"size_bytes":1},
}
public = {
    "schema_version":"3.0.0", "payload_id":"capacity-fixture", "run_id":"capacity-fixture-run",
    "parameters_sha256":"a"*64, "source_manifest_sha256":"b"*64,
    "public_tables":[
        single("runs.parquet","dosa-v3-run-1","c"*64),
        single("replicons.parquet","dosa-v3-replicon-1","d"*64),
        {"filename":"window_operator_profiles.parquet","schema_id":"dosa-v3-window-profile-1","record_count":40,
         "storage":{"layout":"package_manifest_partitioned","partitioning":"scale_then_sha256_accession_bucket","package_manifest_ids":[entry["package_manifest_id"] for entry in package_entries]}},
        single("replicon_operator_summary.parquet","dosa-v3-summary-1","e"*64),
        single("excluded_records.parquet","dosa-v3-exclusion-1","f"*64),
    ],
    "package_manifests":package_entries, "supporting_artifacts":[], "release_state":"blocked_pending_receipts",
}
(root / "public-payload-manifest.json").write_text(json.dumps(public,separators=(",",":"))+"\n",encoding="utf-8")
write_parquet_package("package-row-tamper-100", 100, declared_rows=11)
write_parquet_package("package-compression-tamper-500", 500, compression="snappy")
write_parquet_package("package-scale-tamper-1000", 1000, actual_scale=999)

fake_package = root / "package-fake-text-16"
fake_payload = fake_package / "scale=16" / "sha256_bucket=00" / "part-00000.parquet"
fake_payload.parent.mkdir(parents=True)
fake_payload.write_text("not-a-parquet-file\n", encoding="utf-8")
write_manifest(fake_package, fake_payload, 16, 10)

hash_tamper = write_parquet_package("package-hash-tamper-100", 100)
hash_payload = hash_tamper / "scale=100" / "sha256_bucket=00" / "part-00000.parquet"
with hash_payload.open("ab") as handle:
    handle.write(b"tamper")
PY

args=()
for scale in 16 100 500 1000; do args+=(--package "$temp/package-$scale"); done
python3 "$root/scripts/project_u0_parquet_capacity.py" "${args[@]}" \
  --full-replicons "$temp/replicons.jsonl" --public-payload-manifest "$temp/public-payload-manifest.json" \
  --evidence-scope fixture >"$temp/report.json"
python3 - "$temp/report.json" <<'PY'
import json, pathlib, sys
value=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert value["status"] == "pass" and value["evidence_scope"] == "fixture"
assert value["parquet_footer_verified"] is True
assert [item["scale"] for item in value["by_scale"]] == [16,100,500,1000]
assert [item["measured_rows"] for item in value["by_scale"]] == [10,10,10,10]
assert value["measured_pilot_rows"] == 40
assert value["required_capacity_bytes"] == 2 * value["projected_full_parquet_bytes"]
assert len(value["package_manifests"]) == 4
assert all(item["package_manifest_id"].startswith("fixture-scale-") for item in value["package_manifests"])
assert len(value["public_payload_manifest_sha256"]) == 64
PY

expect_failure() {
  local label="$1"
  local pattern="$2"
  shift 2
  local case_args=()
  local package
  for package in "$@"; do case_args+=(--package "$package"); done
  set +e
  python3 "$root/scripts/project_u0_parquet_capacity.py" "${case_args[@]}" \
    --full-replicons "$temp/replicons.jsonl" --public-payload-manifest "$temp/public-payload-manifest.json" \
    --evidence-scope fixture >"$temp/$label.json"
  local rc=$?
  set -e
  if [ "$rc" -ne 2 ] || ! rg -q "$pattern" "$temp/$label.json"; then
    echo "capacity projection failed to reject $label" >&2
    cat "$temp/$label.json" >&2
    exit 1
  fi
}

expect_failure fake_text 'not readable Parquet' \
  "$temp/package-fake-text-16" "$temp/package-100" "$temp/package-500" "$temp/package-1000"
expect_failure row_tamper 'row count does not match manifest' \
  "$temp/package-16" "$temp/package-row-tamper-100" "$temp/package-500" "$temp/package-1000"
expect_failure compression_tamper 'compression is not exclusively ZSTD' \
  "$temp/package-16" "$temp/package-100" "$temp/package-compression-tamper-500" "$temp/package-1000"
expect_failure scale_tamper 'scale column does not match manifest scale' \
  "$temp/package-16" "$temp/package-100" "$temp/package-500" "$temp/package-scale-tamper-1000"
expect_failure hash_tamper 'payload bytes/SHA-256 mismatch' \
  "$temp/package-16" "$temp/package-hash-tamper-100" "$temp/package-500" "$temp/package-1000"

mkdir -p "$temp/wrong-duckdb"
printf '__version__ = "0.0.0"\n' > "$temp/wrong-duckdb/duckdb.py"
set +e
PYTHONPATH="$temp/wrong-duckdb" python3 "$root/scripts/project_u0_parquet_capacity.py" "${args[@]}" \
  --full-replicons "$temp/replicons.jsonl" --public-payload-manifest "$temp/public-payload-manifest.json" \
  --evidence-scope fixture >"$temp/wrong-version.json"
rc=$?
set -e
if [ "$rc" -ne 2 ] || ! rg -q 'duckdb==1.5.5 is required' "$temp/wrong-version.json"; then
  echo "capacity projection accepted an unpinned DuckDB version" >&2
  exit 1
fi

cp "$temp/public-payload-manifest.json" "$temp/unbound-public-payload-manifest.json"
python3 - "$temp/unbound-public-payload-manifest.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); value=json.loads(p.read_text()); value["package_manifests"][0]["sha256"]="0"*64
p.write_text(json.dumps(value,separators=(",",":"))+"\n")
PY
set +e
python3 "$root/scripts/project_u0_parquet_capacity.py" "${args[@]}" \
  --full-replicons "$temp/replicons.jsonl" --public-payload-manifest "$temp/unbound-public-payload-manifest.json" \
  --evidence-scope fixture >"$temp/unbound-public.json"
rc=$?
set -e
if [ "$rc" -ne 2 ] || ! rg -q 'does not equal public payload closure' "$temp/unbound-public.json"; then
  echo "capacity projection accepted a public/package manifest mismatch" >&2
  exit 1
fi

echo "U0_CAPACITY_FIXTURE_PASS scales=4 real_parquet=1 invalid_cases=7 safety_factor=2 fixture_scope_nonpromotable=1"
