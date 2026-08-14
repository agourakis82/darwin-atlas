#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$root/data/fixtures/u0_operational"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-operational.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
chmod +x "$fixture/fake_dosa.py" "$fixture/fake_sounio.py"

cp -R "$fixture/source-root" "$tmp/source-cache"
mkdir -p "$tmp/source-cache/public"
cp "$fixture/source-manifest.json" "$tmp/source-cache/public/source-manifest.json"
cp "$fixture/source-integrity.json" "$tmp/source-cache/public/source-integrity.json"
cp "$fixture/source-manifest.json" "$tmp/source-manifest.json"
cp "$fixture/source-integrity.json" "$tmp/source-integrity.json"
cp "$fixture/public-payload-manifest.json" "$tmp/public-payload-manifest.json"
cp "$fixture/sounio-attestation.json" "$tmp/sounio-attestation.json"
cp "$fixture/sounio-build-receipt.json" "$tmp/sounio-build-receipt.json"
chmod 0444 "$tmp/source-manifest.json" "$tmp/source-integrity.json" \
  "$tmp/public-payload-manifest.json" "$tmp/sounio-attestation.json" "$tmp/sounio-build-receipt.json"

sounio_template="$fixture/fake_sounio.py --sequence {sequence} --accession-version {accession_version} --scale {scale} --parameters {parameters} --coordinate-start {coordinate_start} --coordinate-end {coordinate_end} --sounio-attestation-sha256 {attestation_sha256} --output {output}"

run_measure() {
  local source_cache="$1" manifest="$2" integrity="$3" attestation="$4" build_receipt="$5" query_out="$6" speed_out="$7"
  python3 "$root/scripts/measure_u0_operational_utility.py" \
    --dosa "$fixture/fake_dosa.py" --package "$fixture/package" \
    --source-manifest "$manifest" --source-integrity "$integrity" \
    --public-payload-manifest "$tmp/public-payload-manifest.json" \
    --source-manifest-url https://example.org/public/source-manifest.json \
    --source-integrity-url https://example.org/public/source-integrity.json \
    --source-root "$source_cache" \
    --accession-version NC_000001.1 --coordinate 0:16 --scale 16 \
    --parameters "$fixture/parameters.json" \
    --sounio-command "$sounio_template" \
    --sounio-attestation "$attestation" --sounio-build-receipt "$build_receipt" \
    --evidence-scope fixture --query-output "$query_out" --speed-output "$speed_out"
}

expect_blocked() {
  local marker="$1"; shift
  set +e
  "$@" >"$tmp/blocked.log" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne 2 ]] || ! rg -q "$marker" "$tmp/blocked.log"; then
    cat "$tmp/blocked.log" >&2
    echo "expected fail-closed marker: $marker (rc=$rc)" >&2
    exit 1
  fi
}

run_measure "$tmp/source-cache" "$tmp/source-manifest.json" "$tmp/source-integrity.json" \
  "$tmp/sounio-attestation.json" "$tmp/sounio-build-receipt.json" "$tmp/query.json" "$tmp/speed.json"

python3 - "$tmp/query.json" "$tmp/speed.json" "$tmp/source-manifest.json" "$tmp/source-integrity.json" "$tmp/public-payload-manifest.json" "$tmp/sounio-attestation.json" "$fixture/package/dosa-payload-manifest.json" <<'PY'
import hashlib, json, pathlib, sys
query_path, speed_path, source_path, integrity_path, public_payload_path, attestation_path, package_payload_path = map(pathlib.Path, sys.argv[1:])
query = json.loads(query_path.read_text()); speed = json.loads(speed_path.read_text())
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert query["evidence_scope"] == speed["evidence_scope"] == "fixture"
assert query["status"] == speed["status"] == "pass"
assert query["source_sequence_recovered"] and query["payload_hashes_verified"]
assert query["cluster_access_used"] is False
assert query["source_manifest_public_url"] == "https://example.org/public/source-manifest.json"
assert query["source_integrity_public_url"] == "https://example.org/public/source-integrity.json"
assert query["source_locator"] == "https://example.org/public/assets/GCF_000000001.1_genomic.fna"
assert query["source_manifest_sha256"] == sha(source_path)
assert query["source_integrity_receipt_sha256"] == sha(integrity_path)
assert query["public_payload_manifest_sha256"] == sha(public_payload_path)
assert query["package_manifest_sha256"] == sha(package_payload_path)
assert query["package_manifest_id"] == "u0-operational-window-shards"
assert speed["public_payload_manifest_sha256"] == query["public_payload_manifest_sha256"]
assert speed["package_manifest_sha256"] == query["package_manifest_sha256"]
assert query["raw_fasta_asset_sha256"] == "68fb2551613bd872fdd902705e5e88c8f5192e08aaad2d714701f85dea2d0cb6"
assert query["normalized_sequence_sha256"] == "cf573e65038d08ff910a3345642ffd1e8329844633c2dcb15964b324ebdba4d0"
assert query["sequence_sha256"] == speed["sequence_sha256"] == "49a99e52ef62f02057a94334607197df852a3eea6ce7e16786fbe5c29e50111a"
assert speed["canonical_producer"] == "Sounio" and speed["null_replicates"] == 1000
assert speed["sounio_attestation_sha256"] == sha(attestation_path)
assert speed["lookup_speedup"] >= 100
print("U0_OPERATIONAL_SOURCE_ATTESTATION_PASS speedup=%.3f" % speed["lookup_speedup"])
PY

# A cached public manifest with different bytes cannot substitute for the local
# immutable document, even in fixture scope.
cp -R "$tmp/source-cache" "$tmp/tampered-manifest-cache"
chmod u+w "$tmp/tampered-manifest-cache/public/source-manifest.json"
printf '\n' >> "$tmp/tampered-manifest-cache/public/source-manifest.json"
expect_blocked 'public source manifest bytes do not match' run_measure \
  "$tmp/tampered-manifest-cache" "$tmp/source-manifest.json" "$tmp/source-integrity.json" \
  "$tmp/sounio-attestation.json" "$tmp/sounio-build-receipt.json" "$tmp/tampered-manifest-query.json" "$tmp/tampered-manifest-speed.json"

# Raw FASTA tampering is caught before record normalization or Sounio execution.
cp -R "$tmp/source-cache" "$tmp/tampered-asset-cache"
printf 'N\n' >> "$tmp/tampered-asset-cache/public/assets/GCF_000000001.1_genomic.fna"
expect_blocked 'downloaded FASTA raw bytes/SHA-256' run_measure \
  "$tmp/tampered-asset-cache" "$tmp/source-manifest.json" "$tmp/source-integrity.json" \
  "$tmp/sounio-attestation.json" "$tmp/sounio-build-receipt.json" "$tmp/tampered-asset-query.json" "$tmp/tampered-asset-speed.json"

# The physical shard manifest must be explicitly referenced by the logical
# five-table public manifest; a syntactically valid but unrelated top-level
# manifest cannot authorize a query.
cp "$tmp/public-payload-manifest.json" "$tmp/unbound-public-payload-manifest.json"
chmod u+w "$tmp/unbound-public-payload-manifest.json"
python3 - "$tmp/unbound-public-payload-manifest.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); value = json.loads(p.read_text())
value["package_manifests"][0]["sha256"] = "0" * 64
p.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
PY
chmod 0444 "$tmp/unbound-public-payload-manifest.json"
mv "$tmp/public-payload-manifest.json" "$tmp/public-payload-manifest.saved"
cp "$tmp/unbound-public-payload-manifest.json" "$tmp/public-payload-manifest.json"
expect_blocked 'package manifest is not referenced exactly once' run_measure \
  "$tmp/source-cache" "$tmp/source-manifest.json" "$tmp/source-integrity.json" \
  "$tmp/sounio-attestation.json" "$tmp/sounio-build-receipt.json" "$tmp/unbound-query.json" "$tmp/unbound-speed.json"
mv "$tmp/public-payload-manifest.saved" "$tmp/public-payload-manifest.json"

# The attestation is external build provenance: it must bind the exact runner.
cp "$fixture/sounio-attestation.json" "$tmp/wrong-runner-attestation.json"
python3 - "$tmp/wrong-runner-attestation.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); value = json.loads(p.read_text()); value["executable_sha256"] = "0" * 64
p.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
PY
chmod 0444 "$tmp/wrong-runner-attestation.json"
expect_blocked 'attestation executable SHA-256 mismatch' run_measure \
  "$tmp/source-cache" "$tmp/source-manifest.json" "$tmp/source-integrity.json" \
  "$tmp/wrong-runner-attestation.json" "$tmp/sounio-build-receipt.json" "$tmp/wrong-runner-query.json" "$tmp/wrong-runner-speed.json"

mkdir -p "$tmp/tampered-receipt-dir"
cp "$fixture/sounio-attestation.json" "$tmp/tampered-receipt-dir/sounio-attestation.json"
cp "$fixture/sounio-build-receipt.json" "$tmp/tampered-receipt-dir/sounio-build-receipt.json"
printf '\n' >> "$tmp/tampered-receipt-dir/sounio-build-receipt.json"
chmod 0444 "$tmp/tampered-receipt-dir/sounio-attestation.json" "$tmp/tampered-receipt-dir/sounio-build-receipt.json"
expect_blocked 'build receipt SHA-256 mismatch' run_measure \
  "$tmp/source-cache" "$tmp/source-manifest.json" "$tmp/source-integrity.json" \
  "$tmp/tampered-receipt-dir/sounio-attestation.json" "$tmp/tampered-receipt-dir/sounio-build-receipt.json" "$tmp/tampered-receipt-query.json" "$tmp/tampered-receipt-speed.json"

# Real-pilot scope cannot be promoted through an HTTP URL or local cache.
expect_blocked 'source manifest URL must be public HTTPS' python3 "$root/scripts/measure_u0_operational_utility.py" \
  --dosa "$fixture/fake_dosa.py" --package "$fixture/package" \
  --source-manifest "$tmp/source-manifest.json" --source-integrity "$tmp/source-integrity.json" \
  --public-payload-manifest "$tmp/public-payload-manifest.json" \
  --source-manifest-url http://example.org/public/source-manifest.json \
  --source-integrity-url https://example.org/public/source-integrity.json \
  --source-root "$tmp/source-cache" --accession-version NC_000001.1 --coordinate 0:16 --scale 16 \
  --parameters "$fixture/parameters.json" --sounio-command "$sounio_template" \
  --sounio-attestation "$tmp/sounio-attestation.json" --sounio-build-receipt "$tmp/sounio-build-receipt.json" \
  --evidence-scope u0_pilot --query-output "$tmp/public-query.json" --speed-output "$tmp/public-speed.json"

missing_template="/definitely/missing/sounio --sequence {sequence} --accession-version {accession_version} --scale {scale} --parameters {parameters} --coordinate-start {coordinate_start} --coordinate-end {coordinate_end} --sounio-attestation-sha256 {attestation_sha256} --output {output}"
expect_blocked 'canonical Sounio executable is unavailable' python3 "$root/scripts/measure_u0_operational_utility.py" \
  --dosa "$fixture/fake_dosa.py" --package "$fixture/package" \
  --source-manifest "$tmp/source-manifest.json" --source-integrity "$tmp/source-integrity.json" \
  --public-payload-manifest "$tmp/public-payload-manifest.json" \
  --source-manifest-url https://example.org/public/source-manifest.json \
  --source-integrity-url https://example.org/public/source-integrity.json --source-root "$tmp/source-cache" \
  --accession-version NC_000001.1 --coordinate 0:16 --scale 16 --parameters "$fixture/parameters.json" \
  --sounio-command "$missing_template" --sounio-attestation "$tmp/sounio-attestation.json" \
  --sounio-build-receipt "$tmp/sounio-build-receipt.json" --evidence-scope fixture \
  --query-output "$tmp/missing-query.json" --speed-output "$tmp/missing-speed.json"

# The BioStudies step remains queue preparation only; no external upload occurs.
mkdir -p "$tmp/queue-root"
cp "$fixture/package/scale=16/sha256_bucket=fb/part-00000.parquet" "$tmp/queue-root/shard.parquet"
python3 - "$tmp/queue-root/shard.parquet" "$tmp/candidate.json" <<'PY'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1]); root = p.parent; payload_sha = hashlib.sha256(p.read_bytes()).hexdigest()
receipt = {"schema_version":"dosa-v3-biostudies-shard-validation-receipt-1","status":"PASS","evidence_scope":"u0_pilot","producer":{"language":"Sounio","canonical":True},"validator":{"language":"Julia","disagreements":0,"absolute_tolerance":0},"validated_payload_sha256":[payload_sha]}
receipt_path = root / "validation-receipt.json"; receipt_path.write_text(json.dumps(receipt,sort_keys=True,separators=(",",":"))+"\n")
value = {"schema_version":"dosa-v3-biostudies-upload-candidate-1","evidence_scope":"u0_pilot","validation":{"status":"PASS","receipt_path":"validation-receipt.json","receipt_bytes":receipt_path.stat().st_size,"receipt_sha256":hashlib.sha256(receipt_path.read_bytes()).hexdigest()},"files":[{"path":"shard.parquet","bytes":p.stat().st_size,"sha256":payload_sha}]}
pathlib.Path(sys.argv[2]).write_text(json.dumps(value))
PY
python3 "$root/scripts/prepare_biostudies_queue.py" --candidate "$tmp/candidate.json" --root "$tmp/queue-root" --output "$tmp/queue.json" >"$tmp/queue.log"
python3 - "$tmp/queue.json" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert value["status"] == "READY_FOR_COORDINATION" and value["upload_performed"] is False and value["external_accession"] is None
PY

cp "$tmp/queue-root/validation-receipt.json" "$tmp/queue-root/validation-receipt.saved"
printf 'tamper' >> "$tmp/queue-root/validation-receipt.json"
expect_blocked BIOSTUDIES_QUEUE_INVALID python3 "$root/scripts/prepare_biostudies_queue.py" \
  --candidate "$tmp/candidate.json" --root "$tmp/queue-root" --output "$tmp/tampered-receipt-queue.json"
mv "$tmp/queue-root/validation-receipt.saved" "$tmp/queue-root/validation-receipt.json"
printf 'tamper' >> "$tmp/queue-root/shard.parquet"
expect_blocked BIOSTUDIES_QUEUE_INVALID python3 "$root/scripts/prepare_biostudies_queue.py" \
  --candidate "$tmp/candidate.json" --root "$tmp/queue-root" --output "$tmp/tampered-queue.json"

echo "U0_OPERATIONAL_FIXTURE_PASS fixture_scope_nonpromotable=1 fail_closed_cases=8 queue_uploads=0"
