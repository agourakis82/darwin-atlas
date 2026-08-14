#!/usr/bin/env bash
# Exercise the bounded offline U0 control-review receipt without NCBI access.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
reviewer="$atlas_root/scripts/review_u0_control_candidates.py"
fixture="$atlas_root/data/fixtures/u0_control_review"
package_fixture="$atlas_root/data/fixtures/u0_control_ledger/package"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-control-review.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

stage() {
  local target="$1"
  mkdir -p "$target/review"
  cp "$fixture/assemblies.jsonl" "$target/review/assemblies.jsonl"
  cp "$fixture/sequences.jsonl" "$target/review/sequences.jsonl"
  cp "$fixture/control_candidates.tsv" "$target/review/control_candidates.tsv"
  cp -R "$package_fixture" "$target/review/package"
}

create() {
  local root="$1"
  python3 "$reviewer" create \
    --review-root "$root/review" \
    --assemblies "$root/review/assemblies.jsonl" \
    --sequences "$root/review/sequences.jsonl" \
    --control-candidates "$root/review/control_candidates.tsv" \
    --package-root "$root/review/package" \
    --output-ledger "$root/review/control_ledger.tsv" \
    --output-binding-receipt "$root/review/control_binding_receipt.json" \
    --output-semantic-receipt "$root/review/control_ledger_receipt.json" \
    --output-review-receipt "$root/review/control_review_receipt.json"
}

verify() {
  local root="$1"
  python3 "$reviewer" verify --review-root "$root/review" --receipt "$root/review/control_review_receipt.json"
}

expect_fail() {
  local marker="$1"; shift
  set +e
  "$@" >"$tmp/fail.out" 2>"$tmp/fail.err"
  local rc=$?
  set -e
  [[ "$rc" -eq 11 ]] || { cat "$tmp/fail.out" "$tmp/fail.err" >&2; echo "expected rc=11, got $rc" >&2; exit 1; }
  grep -q "$marker" "$tmp/fail.err" || { cat "$tmp/fail.err" >&2; echo "missing marker $marker" >&2; exit 1; }
}

good="$tmp/good"
stage "$good"
create "$good" > "$tmp/create.json"
verify "$good" > "$tmp/verify.json"
python3 - "$good/review" "$tmp/create.json" "$tmp/verify.json" <<'PY'
import hashlib, json, pathlib, sys
root, create_path, verify_path = map(pathlib.Path, sys.argv[1:])
create = json.loads(create_path.read_text()); verified = json.loads(verify_path.read_text())
receipt_path = root / "control_review_receipt.json"; receipt = json.loads(receipt_path.read_text())
assert create["status"] == "validated" and verified["status"] == "verified"
assert receipt["schema_version"] == "dosa-u0-control-review-receipt-1"
assert receipt["evidence_scope"] == "bounded_control_candidate_review_non_scientific"
assert receipt["control_claims"] == 6 and receipt["control_claims_semantically_validated"] is True
assert receipt["scientific_metrics_computed"] is False
assert receipt["mini_package_root"] == "package"
for key in ("assembly_report", "sequence_report", "control_candidates", "control_ledger", "binding_receipt", "semantic_receipt"):
    value = receipt[key]
    assert not value["path"].startswith("/") and ".." not in pathlib.PurePosixPath(value["path"]).parts
    assert value["bytes"] == (root / value["path"]).stat().st_size
    assert value["sha256"] == hashlib.sha256((root / value["path"]).read_bytes()).hexdigest()
assert verified["review_receipt_sha256"] == hashlib.sha256(receipt_path.read_bytes()).hexdigest()
print("U0_CONTROL_REVIEW_FIXTURE_PASS controls=6 offline_only=1")
PY

ledger_tamper="$tmp/ledger-tamper"
stage "$ledger_tamper"; create "$ledger_tamper" > /dev/null
printf 'tamper\n' >> "$ledger_tamper/review/control_ledger.tsv"
expect_fail IDENTITY_MISMATCH verify "$ledger_tamper"

receipt_tamper="$tmp/receipt-tamper"
stage "$receipt_tamper"; create "$receipt_tamper" > /dev/null
python3 - "$receipt_tamper/review/control_review_receipt.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); value = json.loads(p.read_text()); value["control_claims"] = 7; p.write_text(json.dumps(value), encoding="utf-8")
PY
expect_fail INVALID_REVIEW_SCOPE verify "$receipt_tamper"

package_tamper="$tmp/package-tamper"
stage "$package_tamper"; create "$package_tamper" > /dev/null
printf 'N\n' >> "$package_tamper/review/package/ncbi_dataset/data/GCF_000000101.1/GCF_000000101.1_genomic.fna"
expect_fail CONTROL_REVIEW_TAMPERED verify "$package_tamper"

parent_symlink="$tmp/parent-symlink"
stage "$parent_symlink"
mkdir "$parent_symlink/review/real-reports"
mv "$parent_symlink/review/assemblies.jsonl" "$parent_symlink/review/real-reports/assemblies.jsonl"
ln -s real-reports "$parent_symlink/review/reports-link"
set +e
python3 "$reviewer" create \
  --review-root "$parent_symlink/review" \
  --assemblies "$parent_symlink/review/reports-link/assemblies.jsonl" \
  --sequences "$parent_symlink/review/sequences.jsonl" \
  --control-candidates "$parent_symlink/review/control_candidates.tsv" \
  --package-root "$parent_symlink/review/package" \
  --output-ledger "$parent_symlink/review/control_ledger.tsv" \
  --output-binding-receipt "$parent_symlink/review/control_binding_receipt.json" \
  --output-semantic-receipt "$parent_symlink/review/control_ledger_receipt.json" \
  --output-review-receipt "$parent_symlink/review/control_review_receipt.json" \
  >"$tmp/parent-symlink.out" 2>"$tmp/parent-symlink.err"
parent_symlink_rc=$?
set -e
[[ "$parent_symlink_rc" -eq 11 ]] || { cat "$tmp/parent-symlink.out" "$tmp/parent-symlink.err" >&2; exit 1; }
grep -q SYMLINK_FORBIDDEN "$tmp/parent-symlink.err"

root_parent_symlink="$tmp/root-parent-symlink"
stage "$root_parent_symlink/actual"
ln -s actual "$root_parent_symlink/alias"
expect_fail SYMLINK_FORBIDDEN create "$root_parent_symlink/alias"

semantic_failure="$tmp/semantic-failure"
stage "$semantic_failure"
printf 'N\n' >> "$semantic_failure/review/package/ncbi_dataset/data/GCF_000000101.1/GCF_000000101.1_genomic.fna"
expect_fail CONTROL_REVIEW_INVALID create "$semantic_failure"
for artifact in control_ledger.tsv control_binding_receipt.json control_ledger_receipt.json control_review_receipt.json; do
  [[ ! -e "$semantic_failure/review/$artifact" ]] || { echo "partial artifact remains: $artifact" >&2; exit 1; }
done

echo "U0_CONTROL_REVIEW_TAMPER_FAIL_CLOSED_PASS cases=6 cleanup=1"
