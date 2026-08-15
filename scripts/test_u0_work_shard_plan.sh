#!/usr/bin/env bash
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly fixture="${root}/data/fixtures/u0_work_unit"
readonly planner="${root}/scripts/plan_u0_eligible_work_shards.py"
readonly parameters="${root}/data/v3/u0_parameters.json"
readonly physical_temp_root="$(python3 -c 'import os,tempfile; print(os.path.realpath(tempfile.gettempdir()))')"
readonly temporary="$(mktemp -d "${physical_temp_root}/dosa-u0-shard-plan.XXXXXX")"
trap 'rm -rf -- "${temporary}"' EXIT

python3 "${planner}" --parameters "${parameters}" \
  --manifest "${fixture}/u0_work_units.tsv" --source-root "${fixture}" \
  --output-directory "${temporary}/valid" --shard-size 2 >/dev/null
test "$(shasum -a 256 "${temporary}/valid/work_shard_plan.json" | awk '{print $1}')" = \
  "aa000b69a865c26b84c5184d24bc040c57ed0e06ff694fd7879987f9ffe052b4"
python3 - "${temporary}/valid" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
plan = json.loads((root / "work_shard_plan.json").read_text(encoding="utf-8"))
assert plan["evidence_scope"] == "preexecution_only"
assert plan["schema_version"] == "dosa-v3-u0-work-shard-plan-3"
assert plan["run_id"] == "u0-work-unit-fixture"
assert plan["scientific_metrics_computed"] is False
assert plan["sounio_executed"] is False and plan["gate_u0_pass"] is False
assert (plan["work_units_expected"], plan["shards_expected"], plan["rows_expected"]) == (7, 9, 12)
assert (plan["excluded_work_units"], plan["excluded_windows"]) == (1, 1)
assert [unit["expected_rows"] for unit in plan["work_units"]] == [3, 3, 3, 0, 1, 1, 1]
assert [unit["status"] for unit in plan["work_units"]] == ["planned", "planned", "planned", "excluded", "planned", "planned", "planned"]
assert [unit["reason_code"] for unit in plan["work_units"]] == [None, None, None, "PARTIAL_WINDOW", None, None, None]
assert [shard["rows"] for shard in plan["shards"]] == [2, 1, 2, 1, 2, 1, 1, 1, 1]
assert [shard["excluded_rows"] for shard in plan["shards"]] == [0, 0, 0, 0, 1, 0, 0, 0, 0]
assert [shard["start_window"] for shard in plan["shards"]] == [0, 2, 0, 2, 0, 2, 0, 0, 0]
for shard in plan["shards"]:
    target = root / shard["path"]
    data = target.read_bytes()
    assert len(data) == shard["size_bytes"]
    assert hashlib.sha256(data).hexdigest() == shard["sha256"]
    assert data.count(b"\n") == shard["rows"] + 1
PY

expect_refusal() {
  local name="$1"
  local marker="$2"
  shift 2
  set +e
  "$@" >"${temporary}/${name}.stdout" 2>"${temporary}/${name}.stderr"
  local rc=$?
  set -e
  test "${rc}" -eq 11
  rg -q "${marker}" "${temporary}/${name}.stderr"
}

cp -R "${fixture}" "${temporary}/tampered-source"
printf 'A\n' >> "${temporary}/tampered-source/fasta/NC_000002.1.fa"
expect_refusal tampered-source 'raw FASTA SHA-256 mismatch' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${temporary}/tampered-source/u0_work_units.tsv" \
  --source-root "${temporary}/tampered-source" --output-directory "${temporary}/tampered-plan" --shard-size 2

ruby -e 'lines=File.binread(ARGV[0]).lines; File.binwrite(ARGV[1],lines.values_at(0,2,1).join)' \
  "${fixture}/u0_work_units.tsv" "${temporary}/reordered.tsv"
expect_refusal reordered 'canonical accession/scale order' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${temporary}/reordered.tsv" \
  --source-root "${fixture}" --output-directory "${temporary}/reordered-plan" --shard-size 2

expect_refusal shard-cap 'shard size must be in 1:16' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${fixture}/u0_work_units.tsv" \
  --source-root "${fixture}" --output-directory "${temporary}/cap-plan" --shard-size 17

mkdir "${temporary}/occupied"
expect_refusal output-exists 'output directory already exists' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${fixture}/u0_work_units.tsv" \
  --source-root "${fixture}" --output-directory "${temporary}/occupied" --shard-size 2

ruby -e 'lines=File.binread(ARGV[0]).lines; fields=lines[3].chomp.split("\t",-1); fields[9]="acgt"; lines[3]=fields.join("\t")+"\n"; File.binwrite(ARGV[1],lines.join)' \
  "${fixture}/u0_work_units.tsv" "${temporary}/non-acgt.tsv"
expect_refusal non-acgt 'declared alphabet does not match normalized FASTA' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${temporary}/non-acgt.tsv" \
  --source-root "${fixture}" --output-directory "${temporary}/non-acgt-plan" --shard-size 2

ruby -e 'lines=File.binread(ARGV[0]).lines; fields=lines[4].chomp.split("\t",-1); fields[8]="7"; lines[4]=fields.join("\t")+"\n"; File.binwrite(ARGV[1],lines.join)' \
  "${fixture}/u0_work_units.tsv" "${temporary}/partial.tsv"
expect_refusal partial 'sequence length mismatch' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${temporary}/partial.tsv" \
  --source-root "${fixture}" --output-directory "${temporary}/partial-plan" --shard-size 2

mkdir "${temporary}/real-parent"
ln -s "${temporary}/real-parent" "${temporary}/linked-parent"
expect_refusal parent-symlink 'output parent path may not contain symlinks' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${fixture}/u0_work_units.tsv" \
  --source-root "${fixture}" --output-directory "${temporary}/linked-parent/plan" --shard-size 2

expect_refusal invalid-run-id 'run_id must be a portable identifier' python3 "${planner}" \
  --parameters "${parameters}" --manifest "${fixture}/u0_work_units.tsv" \
  --source-root "${fixture}" --output-directory "${temporary}/invalid-run-id-plan" \
  --shard-size 2 --run-id 'bad/run'

echo "U0_ELIGIBLE_WORK_SHARD_PLAN_FIXTURE_PASS work_units=7 shards=9 rows=12 excluded_work_units=1 excluded_windows=1 scales=4 fail_closed_cases=8 run_id_bound=1 preexecution_only=1"
