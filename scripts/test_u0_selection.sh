#!/usr/bin/env bash
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$atlas_root/data/fixtures/u0_selection"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dosa-u0-selection.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

run_valid() {
  local output="$1"
  python3 "$atlas_root/scripts/select_u0_pilot.py" \
    --assemblies "$fixture/assemblies.jsonl" \
    --sequences "$fixture/sequences.jsonl" \
    --control-candidates "$fixture/control_candidates.tsv" \
    --largest 2 \
    --output "$output"
}

run_valid "$work_dir/one.jsonl" > "$work_dir/one.stdout"
run_valid "$work_dir/two.jsonl" > "$work_dir/two.stdout"
cmp "$work_dir/one.jsonl" "$work_dir/two.jsonl"

python3 - "$work_dir/one.jsonl" "$work_dir/one.stdout" <<'PY'
import json, pathlib, sys
rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
summary = json.loads(pathlib.Path(sys.argv[2]).read_text())
by_id = {row["sequence_accession_version"]: row for row in rows}
assert set(by_id) == {"NC_LARGE00001.1", "NC_LARGE00002.1", "NC_CONTROL001.1", "NC_CONTROL002.1", "NC_TEST00362.1"}
assert "sha256_mod_256_zero" in by_id["NC_TEST00362.1"]["selection_reasons"]
assert "largest_replicon" in by_id["NC_LARGE00001.1"]["selection_reasons"]
assert "largest_replicon" in by_id["NC_LARGE00002.1"]["selection_reasons"]
assert by_id["NC_CONTROL001.1"]["replicon_class"] == "plasmid"
assert by_id["NC_CONTROL002.1"]["replicon_class"] == "chromosome"
assert all(row["sha256_bucket"] == row["accession_sha256"][:2] for row in rows)
assert summary["control_input_kind"] == "unverified_candidates"
assert summary["control_candidates_complete"] is True
assert summary["control_ledger_validated"] is False
print("U0_SELECTION_FIXTURE_PASS records=5")
PY

python3 "$atlas_root/scripts/select_u0_pilot.py" \
  --assemblies "$fixture/assemblies.jsonl" \
  --sequences "$fixture/sequences.jsonl" \
  --controls "$fixture/controls.tsv" \
  --largest 2 \
  --output "$work_dir/ledger-mode.jsonl" > "$work_dir/ledger-mode.stdout"
cmp "$work_dir/one.jsonl" "$work_dir/ledger-mode.jsonl"
grep -q '"control_input_kind":"declared_asset_ledger"' "$work_dir/ledger-mode.stdout"
echo "U0_SELECTION_LEDGER_COMPATIBILITY_PASS"

set +e
python3 "$atlas_root/scripts/select_u0_pilot.py" \
  --assemblies "$fixture/assemblies.jsonl" \
  --sequences "$fixture/sequences.jsonl" \
  --control-candidates "$fixture/control_candidates_missing.tsv" \
  --largest 2 \
  --output "$work_dir/invalid.jsonl" > "$work_dir/invalid.stdout"
invalid_rc=$?
set -e
[[ "$invalid_rc" -eq 11 ]] || { echo "expected invalid control ledger rc=11, got $invalid_rc" >&2; exit 1; }
grep -q 'control candidate file is incomplete' "$work_dir/invalid.stdout"
[[ ! -e "$work_dir/invalid.jsonl" ]]
echo "U0_SELECTION_FAIL_CLOSED_PASS rc=11"

set +e
python3 "$atlas_root/scripts/select_u0_pilot.py" \
  --assemblies "$fixture/assemblies.jsonl" \
  --sequences "$fixture/sequences.jsonl" \
  --controls "$fixture/controls_missing.tsv" \
  --largest 2 \
  --output "$work_dir/missing-ledger.jsonl" > "$work_dir/missing-ledger.stdout"
missing_ledger_rc=$?
set -e
[[ "$missing_ledger_rc" -eq 11 ]] || { echo "expected incomplete ledger rc=11, got $missing_ledger_rc" >&2; exit 1; }
grep -q 'control ledger is incomplete' "$work_dir/missing-ledger.stdout"
[[ ! -e "$work_dir/missing-ledger.jsonl" ]]

cp "$fixture/control_candidates.tsv" "$work_dir/cross-bound-candidates.tsv"
python3 - "$work_dir/cross-bound-candidates.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("GCF_000000002.1", "GCF_000000001.1", 1))
PY
set +e
python3 "$atlas_root/scripts/select_u0_pilot.py" \
  --assemblies "$fixture/assemblies.jsonl" \
  --sequences "$fixture/sequences.jsonl" \
  --control-candidates "$work_dir/cross-bound-candidates.tsv" \
  --largest 2 \
  --output "$work_dir/cross-bound.jsonl" > "$work_dir/cross-bound.stdout"
cross_bound_rc=$?
set -e
[[ "$cross_bound_rc" -eq 11 ]] || { echo "expected cross-bound candidate rc=11, got $cross_bound_rc" >&2; exit 1; }
grep -q 'control assembly does not bind accession' "$work_dir/cross-bound.stdout"
[[ ! -e "$work_dir/cross-bound.jsonl" ]]

printf '%s\n' \
  $'sequence_accession_version\tcontrol_category\tevidence_sha256' \
  $'NC_CONTROL001.1\ttopology_circular\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  > "$work_dir/legacy-controls.tsv"
set +e
python3 "$atlas_root/scripts/select_u0_pilot.py" \
  --assemblies "$fixture/assemblies.jsonl" \
  --sequences "$fixture/sequences.jsonl" \
  --controls "$work_dir/legacy-controls.tsv" \
  --largest 2 \
  --output "$work_dir/legacy.jsonl" > "$work_dir/legacy.stdout"
legacy_rc=$?
set -e
[[ "$legacy_rc" -eq 11 ]] || { echo "expected legacy ledger rc=11, got $legacy_rc" >&2; exit 1; }
grep -q 'control ledger header must be exactly' "$work_dir/legacy.stdout"
[[ ! -e "$work_dir/legacy.jsonl" ]]
echo "U0_SELECTION_LEGACY_LEDGER_REJECTED_PASS rc=11"

set +e
python3 "$atlas_root/scripts/select_u0_pilot.py" \
  --assemblies "$fixture/assemblies.jsonl" \
  --sequences "$fixture/sequences.jsonl" \
  --controls "$fixture/controls.tsv" \
  --control-candidates "$fixture/control_candidates.tsv" \
  --largest 2 \
  --output "$work_dir/both.jsonl" > "$work_dir/both.stdout" 2> "$work_dir/both.stderr"
both_rc=$?
set -e
[[ "$both_rc" -eq 2 ]] || { echo "expected mutually exclusive inputs rc=2, got $both_rc" >&2; exit 1; }
grep -q 'not allowed with argument' "$work_dir/both.stderr"
[[ ! -e "$work_dir/both.jsonl" ]]
echo "U0_SELECTION_INPUT_MODES_FAIL_CLOSED_PASS"
