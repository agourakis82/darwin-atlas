#!/usr/bin/env bash
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$atlas_root/data/fixtures/u0_gate"
core="$fixture/core"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-gate.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

python3 "$atlas_root/scripts/audit_v3_public_fields.py" \
  --schema-dir "$atlas_root/schemas" \
  --rules "$atlas_root/data/v3/public_field_use_rules.json" \
  --evidence-scope fixture > "$work_dir/field_audit.json"

common=(
  --agreement "$fixture/agreement.json"
  --query "$fixture/query.json"
  --speed "$fixture/speed.json"
  --capacity "$fixture/capacity.json"
  --field-audit "$work_dir/field_audit.json"
  --parameters "$atlas_root/data/v3/u0_parameters.json"
  --source-manifest "$core/source_manifest.json"
  --source-integrity "$core/source_integrity.json"
  --payload-manifest "$core/payload_manifest.json"
  --sounio-attestation "$core/sounio-attestation.json"
  --sounio-build-receipt "$core/sounio-build-receipt.json"
  --julia-receipt "$core/julia-receipt.json"
)

set +e
python3 "$atlas_root/scripts/evaluate_u0_gate.py" "${common[@]}" \
  --oric "$fixture/oric_pass.json" --model "$fixture/model_fail.json" \
  --output "$work_dir/fixture.json" > "$work_dir/fixture.stdout"
fixture_rc=$?
set -e
[[ "$fixture_rc" -eq 2 ]] || { echo "fixture evidence must block U0, got rc=$fixture_rc" >&2; exit 1; }
python3 - "$work_dir/fixture.json" <<'PY'
import json, pathlib, sys
receipt = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert receipt["status"] == "BLOCKED"
assert receipt["reason_code"] == "FIXTURE_EVIDENCE_CANNOT_PASS_U0"
assert all(receipt["checks"].values())
assert receipt["full_atlas_authorized"] is False
assert receipt["hdd_purchase_evaluation_authorized"] is False
print("U0_GATE_FIXTURE_CANNOT_PROMOTE_PASS")
PY

set +e
python3 "$atlas_root/scripts/evaluate_u0_gate.py" "${common[@]}" \
  --oric "$fixture/oric_fail.json" --model "$fixture/model_fail.json" \
  > "$work_dir/science-fail.stdout"
science_rc=$?
set -e
[[ "$science_rc" -eq 2 ]] || { echo "two failed science tests must block U0" >&2; exit 1; }
grep -q 'U0_REQUIREMENT_FAILED' "$work_dir/science-fail.stdout"

# Regression for the original P0: primitive-only self-declared reports must
# never authorize U0, even when every scope string is changed to u0_pilot.
python3 - "$work_dir" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for name, value in {
    "agreement": {"evidence_scope":"u0_pilot","sounio_rows":1,"julia_rows":1,"byte_exact_rows":1,"absolute_tolerance":0},
    "query": {"evidence_scope":"u0_pilot","shard_download_bytes":1,"post_download_query_seconds":1,"source_sequence_recovered":True,"source_sequence_sha256_verified":True,"payload_hashes_verified":True,"cluster_access_used":False},
    "speed": {"evidence_scope":"u0_pilot","lookup_seconds":1,"n1000_recompute_seconds":100,"null_replicates":1000},
    "capacity": {"evidence_scope":"u0_pilot","measured_pilot_rows":1,"measured_parquet_bytes":1,"projected_full_rows":1,"projected_full_parquet_bytes":1,"required_capacity_bytes":2,"compression":"zstd","safety_factor":2,"projection_basis":"measured_u0_pilot_parquet"},
    "field": {"evidence_scope":"u0_pilot","published_fields":1,"fields_with_demonstrated_use_or_removed":1,"unaccounted_fields":[]},
    "oric": {"evidence_scope":"u0_pilot","status":"PASS"},
    "model": {"evidence_scope":"u0_pilot","status":"FAIL"},
}.items():
    (root / f"forged-{name}.json").write_text(json.dumps(value), encoding="utf-8")
PY
set +e
python3 "$atlas_root/scripts/evaluate_u0_gate.py" \
  --agreement "$work_dir/forged-agreement.json" --query "$work_dir/forged-query.json" \
  --speed "$work_dir/forged-speed.json" --capacity "$work_dir/forged-capacity.json" \
  --field-audit "$work_dir/forged-field.json" --oric "$work_dir/forged-oric.json" \
  --model "$work_dir/forged-model.json" \
  --parameters "$atlas_root/data/v3/u0_parameters.json" \
  --source-manifest "$core/source_manifest.json" --source-integrity "$core/source_integrity.json" \
  --payload-manifest "$core/payload_manifest.json" --sounio-attestation "$core/sounio-attestation.json" \
  --sounio-build-receipt "$core/sounio-build-receipt.json" --julia-receipt "$core/julia-receipt.json" \
  > "$work_dir/forged.stdout"
forged_rc=$?
set -e
[[ "$forged_rc" -eq 2 ]] || { echo "fabricated primitive reports promoted U0" >&2; exit 1; }
grep -q 'INVALID_EVIDENCE' "$work_dir/forged.stdout"

# Regression for a stronger P0: valid-shaped fixture artifacts cannot be
# promoted by relabeling their scopes and recomputing all mutable local hashes.
cp "$fixture/agreement.json" "$work_dir/relabel-agreement.json"
cp "$fixture/query.json" "$work_dir/relabel-query.json"
cp "$fixture/speed.json" "$work_dir/relabel-speed.json"
cp "$fixture/capacity.json" "$work_dir/relabel-capacity.json"
cp "$work_dir/field_audit.json" "$work_dir/relabel-field.json"
cp "$fixture/oric_pass.json" "$work_dir/relabel-oric.json"
cp "$core/sounio-attestation.json" "$work_dir/relabel-sounio-attestation.json"
python3 - "$work_dir" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for name in ("agreement", "query", "speed", "capacity", "field"):
    path = root / f"relabel-{name}.json"
    value = json.loads(path.read_text())
    value["evidence_scope"] = "u0_pilot"
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
attestation_path = root / "relabel-sounio-attestation.json"
attestation = json.loads(attestation_path.read_text())
attestation["evidence_scope"] = "build-provenance-only-non-semantic"
attestation_path.write_text(json.dumps(attestation, sort_keys=True, separators=(",", ":")) + "\n")
attestation_sha = hashlib.sha256(attestation_path.read_bytes()).hexdigest()
for name in ("agreement", "speed"):
    path = root / f"relabel-{name}.json"
    value = json.loads(path.read_text())
    value["sounio_attestation_sha256"] = attestation_sha
    if name == "speed":
        value["sounio_attestation_evidence_scope"] = "build-provenance-only-non-semantic"
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
oric_path = root / "relabel-oric.json"
oric = json.loads(oric_path.read_text())
oric.update({"evidence_scope":"held_out_grouped_cohort","status":"PASS","scientific_claim_permitted":True})
oric_path.write_text(json.dumps(oric, sort_keys=True, separators=(",", ":")) + "\n")
PY
set +e
python3 "$atlas_root/scripts/evaluate_u0_gate.py" \
  --agreement "$work_dir/relabel-agreement.json" --query "$work_dir/relabel-query.json" \
  --speed "$work_dir/relabel-speed.json" --capacity "$work_dir/relabel-capacity.json" \
  --field-audit "$work_dir/relabel-field.json" --oric "$work_dir/relabel-oric.json" \
  --model "$fixture/model_fail.json" --parameters "$atlas_root/data/v3/u0_parameters.json" \
  --source-manifest "$core/source_manifest.json" --source-integrity "$core/source_integrity.json" \
  --payload-manifest "$core/payload_manifest.json" --sounio-attestation "$work_dir/relabel-sounio-attestation.json" \
  --sounio-build-receipt "$core/sounio-build-receipt.json" --julia-receipt "$core/julia-receipt.json" \
  > "$work_dir/relabel.stdout"
relabel_rc=$?
set -e
[[ "$relabel_rc" -eq 2 ]] || { echo "scope-relabelled fixture promoted U0" >&2; exit 1; }
grep -q 'u0_pilot evidence is missing provenance arguments' "$work_dir/relabel.stdout"
grep -q 'INVALID_EVIDENCE' "$work_dir/relabel.stdout"
echo "U0_GATE_SCOPE_RELABEL_EXPLOIT_REJECTED_PASS"

# Even a real-scope invocation that supplies every current provenance argument
# must stop at the explicit promotion lock while the canonical executor, full
# Julia validator, and held-out scientific derivation closure are incomplete.
promotion_args=(
  --evidence-root "$work_dir"
  --pilot-provenance "$work_dir/not-yet-provenance.json"
  --source-index "$work_dir/not-yet-source-index.json"
  --sounio-execution-receipt "$work_dir/not-yet-sounio-execution.json"
  --sounio-output-manifest "$work_dir/not-yet-sounio-output.json"
  --oric-input "$work_dir/not-yet-oric.tsv"
  --model-input "$work_dir/not-yet-model.tsv"
  --selection "$work_dir/not-yet-selection.tsv"
  --control-candidates "$work_dir/not-yet-control-candidates.tsv"
  --control-ledger "$work_dir/not-yet-control-ledger.tsv"
  --control-binding-receipt "$work_dir/not-yet-control-binding.json"
  --control-validation-receipt "$work_dir/not-yet-control-validation.json"
  --source-freeze-receipt "$work_dir/not-yet-source-freeze.json"
  --assembly-report "$work_dir/not-yet-assembly-report.jsonl"
  --sequence-report "$work_dir/not-yet-sequence-report.jsonl"
  --full-replicon-inventory "$work_dir/not-yet-full-inventory.jsonl"
  --work-unit-manifest "$work_dir/not-yet-work-units.tsv"
  --julia-bin /bin/false
)
set +e
python3 "$atlas_root/scripts/evaluate_u0_gate.py" \
  --agreement "$work_dir/relabel-agreement.json" --query "$work_dir/relabel-query.json" \
  --speed "$work_dir/relabel-speed.json" --capacity "$work_dir/relabel-capacity.json" \
  --field-audit "$work_dir/relabel-field.json" --oric "$work_dir/relabel-oric.json" \
  --model "$fixture/model_fail.json" --parameters "$atlas_root/data/v3/u0_parameters.json" \
  --source-manifest "$core/source_manifest.json" --source-integrity "$core/source_integrity.json" \
  --payload-manifest "$core/payload_manifest.json" --sounio-attestation "$work_dir/relabel-sounio-attestation.json" \
  --sounio-build-receipt "$core/sounio-build-receipt.json" --julia-receipt "$core/julia-receipt.json" \
  "${promotion_args[@]}" > "$work_dir/promotion-lock.stdout"
promotion_rc=$?
set -e
[[ "$promotion_rc" -eq 2 ]] || { echo "incomplete real U0 escaped the promotion lock" >&2; exit 1; }
grep -q 'U0_PROMOTION_LOCKED' "$work_dir/promotion-lock.stdout"
grep -q 'CANONICAL_SOUNIO_U0_EXECUTOR_NOT_IMPLEMENTED' "$work_dir/promotion-lock.stdout"
grep -q 'INDEPENDENT_JULIA_FULL_VALIDATOR_NOT_IMPLEMENTED' "$work_dir/promotion-lock.stdout"
grep -q 'HELD_OUT_SCIENTIFIC_DERIVATION_PROVENANCE_NOT_IMPLEMENTED' "$work_dir/promotion-lock.stdout"
echo "U0_GATE_EXPLICIT_PROMOTION_LOCK_PASS"

# A valid-shaped report with one changed core hash is also rejected.
cp "$fixture/agreement.json" "$work_dir/hash-tampered-agreement.json"
python3 - "$work_dir/hash-tampered-agreement.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); value = json.loads(path.read_text())
value["payload_manifest_sha256"] = "0" * 64
path.write_text(json.dumps(value), encoding="utf-8")
PY
set +e
tampered_common=("${common[@]}")
tampered_common[1]="$work_dir/hash-tampered-agreement.json"
python3 "$atlas_root/scripts/evaluate_u0_gate.py" "${tampered_common[@]}" \
  --oric "$fixture/oric_pass.json" --model "$fixture/model_fail.json" > "$work_dir/hash-tamper.stdout"
hash_rc=$?
set -e
[[ "$hash_rc" -eq 2 ]] || { echo "hash-tampered report promoted U0" >&2; exit 1; }
grep -q 'INVALID_EVIDENCE' "$work_dir/hash-tamper.stdout"

# A self-declared scientific PASS cannot override the frozen OriC threshold.
cp "$fixture/oric_pass.json" "$work_dir/forged-oric-threshold.json"
python3 - "$work_dir/forged-oric-threshold.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); value = json.loads(path.read_text())
value["median_relative_error_reduction"] = 0.09
path.write_text(json.dumps(value), encoding="utf-8")
PY
set +e
python3 "$atlas_root/scripts/evaluate_u0_gate.py" "${common[@]}" \
  --oric "$work_dir/forged-oric-threshold.json" --model "$fixture/model_fail.json" > "$work_dir/forged-oric.stdout"
oric_forged_rc=$?
set -e
[[ "$oric_forged_rc" -eq 2 ]] || { echo "forged OriC metric status promoted U0" >&2; exit 1; }
grep -q 'INVALID_EVIDENCE' "$work_dir/forged-oric.stdout"
echo "U0_GATE_FAIL_CLOSED_PASS"
