#!/usr/bin/env bash
# Exercise exact U0 control-ledger binding on a tiny synthetic package only.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binder="$atlas_root/scripts/bind_u0_control_ledger.py"
validator="$atlas_root/scripts/validate_u0_control_ledger.py"
fixture="$atlas_root/data/fixtures/u0_control_ledger"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-control-ledger.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

stage_fixture() {
  local target="$1"
  mkdir -p "$target"
  cp -R "$fixture/package" "$target/package"
  cp "$fixture/control_candidates.tsv" "$target/control_candidates.tsv"
}

run_binder() {
  local root="$1"
  python3 "$binder" \
    --control-candidates "$root/control_candidates.tsv" \
    --package-root "$root/package" \
    --output-ledger "$root/controls.tsv" \
    --output-receipt "$root/control_binding_receipt.json"
}

prepare() {
  local target="$1"
  stage_fixture "$target"
  run_binder "$target" > "$target/binding-summary.json"
}

run_validator() {
  local root="$1"
  python3 "$validator" --controls "$root/controls.tsv" --package-root "$root/package" --output "$root/control_ledger_receipt.json"
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

good="$tmp/good"; prepare "$good"
run_validator "$good" > "$tmp/good.json"
python3 - "$good" "$tmp/good.json" <<'PY'
import hashlib, json, pathlib, sys
root, output = map(pathlib.Path, sys.argv[1:])
summary = json.loads(output.read_text())
binding = json.loads((root / "control_binding_receipt.json").read_text())
receipt = json.loads((root / "control_ledger_receipt.json").read_text())
assert summary["status"] == "validated" and summary["controls"] == 6
assert binding["status"] == "bound_unvalidated"
assert binding["semantic_validation_complete"] is False
assert binding["control_candidates_sha256"] == hashlib.sha256((root / "control_candidates.tsv").read_bytes()).hexdigest()
assert binding["control_ledger_sha256"] == hashlib.sha256((root / "controls.tsv").read_bytes()).hexdigest()
assert receipt["status"] == "validated" and len(receipt["controls"]) == 6
assert receipt["control_ledger_sha256"] == hashlib.sha256((root / "controls.tsv").read_bytes()).hexdigest()
assert {row["control_category"] for row in receipt["controls"]} == set(receipt["required_categories"])
print("U0_CONTROL_BINDING_AND_LEDGER_FIXTURE_PASS controls=6")
PY

reordered="$tmp/reordered"; stage_fixture "$reordered"
python3 - "$reordered/control_candidates.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); lines = p.read_text().splitlines()
p.write_text("\n".join([lines[0], *reversed(lines[1:])]) + "\n", encoding="utf-8")
PY
run_binder "$reordered" > "$tmp/reordered.json"
cmp "$good/controls.tsv" "$reordered/controls.tsv"

missing_asset="$tmp/missing-asset"; stage_fixture "$missing_asset"
rm "$missing_asset/package/ncbi_dataset/data/GCF_000000101.1/GCF_000000101.1_genomic.gbff"
expect_fail MISSING_EXPECTED_ASSET run_binder "$missing_asset"

incomplete_candidates="$tmp/incomplete-candidates"; stage_fixture "$incomplete_candidates"
python3 - "$incomplete_candidates/control_candidates.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); lines = p.read_text().splitlines(); p.write_text("\n".join(lines[:-1]) + "\n")
PY
expect_fail CONTROL_CANDIDATES_INCOMPLETE run_binder "$incomplete_candidates"

duplicate_candidate="$tmp/duplicate-candidate"; stage_fixture "$duplicate_candidate"
python3 - "$duplicate_candidate/control_candidates.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); lines = p.read_text().splitlines(); p.write_text("\n".join([*lines, lines[1]]) + "\n")
PY
expect_fail DUPLICATE_CONTROL_CANDIDATE run_binder "$duplicate_candidate"

bad_version="$tmp/bad-version"; stage_fixture "$bad_version"
python3 - "$bad_version/control_candidates.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("NC_000101.1", "NC_000101", 1))
PY
expect_fail INVALID_VERSIONED_BINDING run_binder "$bad_version"

symlinked_candidates="$tmp/symlinked-candidates"; stage_fixture "$symlinked_candidates"
mv "$symlinked_candidates/control_candidates.tsv" "$symlinked_candidates/real-candidates.tsv"
ln -s "$symlinked_candidates/real-candidates.tsv" "$symlinked_candidates/control_candidates.tsv"
expect_fail SYMLINK_FORBIDDEN run_binder "$symlinked_candidates"

overwrite="$tmp/overwrite"; stage_fixture "$overwrite"
touch "$overwrite/controls.tsv"
expect_fail REFUSE_OVERWRITE run_binder "$overwrite"

echo "U0_CONTROL_BINDING_FAIL_CLOSED_PASS cases=6 deterministic_reorder=1"

tampered="$tmp/tampered"; prepare "$tampered"
printf 'N\n' >> "$tampered/package/ncbi_dataset/data/GCF_000000101.1/GCF_000000101.1_genomic.fna"
expect_fail EVIDENCE_SHA256_MISMATCH run_validator "$tampered"

cross_bound="$tmp/cross-bound"; prepare "$cross_bound"
python3 - "$cross_bound/controls.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("GCF_000000101.1\ttopology_circular", "GCF_000000102.1\ttopology_circular", 1))
PY
expect_fail ASSEMBLY_PATH_MISMATCH run_validator "$cross_bound"

false_claim="$tmp/false-claim"; prepare "$false_claim"
python3 - "$false_claim/controls.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("topology_circular", "topology_linear", 1))
PY
expect_fail GBFF_TOPOLOGY_CLAIM_FALSE run_validator "$false_claim"

escaped="$tmp/escaped"; prepare "$escaped"
python3 - "$escaped/controls.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("ncbi_dataset/data/GCF_000000101.1/GCF_000000101.1_genomic.gbff", "../outside.gbff", 1))
PY
expect_fail INVALID_PACKAGE_PATH run_validator "$escaped"

symlinked="$tmp/symlinked"; prepare "$symlinked"
asset="$symlinked/package/ncbi_dataset/data/GCF_000000101.1/GCF_000000101.1_genomic.gbff"
mv "$asset" "$symlinked/real.gbff"
ln -s "$symlinked/real.gbff" "$asset"
expect_fail SYMLINK_FORBIDDEN run_validator "$symlinked"

incomplete="$tmp/incomplete"; prepare "$incomplete"
python3 - "$incomplete/controls.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); lines = p.read_text().splitlines(); p.write_text("\n".join(lines[:-1]) + "\n")
PY
expect_fail CONTROL_LEDGER_INCOMPLETE run_validator "$incomplete"

echo "U0_CONTROL_LEDGER_FAIL_CLOSED_PASS cases=6"
