#!/usr/bin/env bash
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly fixture="${root}/data/fixtures/u0_work_unit"
readonly builder="${root}/scripts/build_u0_work_unit_case.py"
readonly parameters="${root}/data/v3/u0_parameters.json"
readonly work_id="NC_000001.1@16"
readonly temporary="$(mktemp -d)"
trap 'rm -rf -- "${temporary}"' EXIT

python3 "${builder}" --parameters "${parameters}" --manifest "${fixture}/u0_work_units.tsv" \
  --source-root "${fixture}" --output "${temporary}/valid.tsv" --work-unit-id "${work_id}" >/dev/null
test "$(wc -l < "${temporary}/valid.tsv")" -eq 4
test "$(shasum -a 256 "${temporary}/valid.tsv" | awk '{print $1}')" = \
  "ebb071824c41015d70027b54716983ead2b12fa94854ede6392e5c7344bd66f8"
python3 "${builder}" --parameters "${parameters}" --manifest "${fixture}/u0_work_units.tsv" \
  --source-root "${fixture}" --output "${temporary}/resume.tsv" --work-unit-id "${work_id}" --start-window 1 >/dev/null
test "$(shasum -a 256 "${temporary}/resume.tsv" | awk '{print $1}')" = \
  "bfc95c21837aafdfae55be1e11828b5505421b8f713b400a4437527258ee31a3"

expect_refusal() {
  local name="$1"
  shift
  set +e
  "$@" >"${temporary}/${name}.stdout" 2>"${temporary}/${name}.stderr"
  local rc=$?
  set -e
  test "${rc}" -eq 11
}

mkdir -p "${temporary}/tampered/fasta"
cp "${fixture}/u0_work_units.tsv" "${temporary}/tampered/manifest.tsv"
printf '>NC_000001.1\nACGTTGCAACGTTGCT\n' > "${temporary}/tampered/fasta/NC_000001.1.fa"
expect_refusal tampered-fasta python3 "${builder}" --parameters "${parameters}" \
  --manifest "${temporary}/tampered/manifest.tsv" --source-root "${temporary}/tampered" \
  --output "${temporary}/tampered.out" --work-unit-id "${work_id}"
test ! -e "${temporary}/tampered.out"

mkdir -p "${temporary}/linked"
ln -s "${fixture}/fasta" "${temporary}/linked/fasta"
cp "${fixture}/u0_work_units.tsv" "${temporary}/linked/manifest.tsv"
expect_refusal source-symlink python3 "${builder}" --parameters "${parameters}" \
  --manifest "${temporary}/linked/manifest.tsv" --source-root "${temporary}/linked" \
  --output "${temporary}/linked.out" --work-unit-id "${work_id}"

mkdir -p "${temporary}/actual"
cp -R "${fixture}/." "${temporary}/actual/"
ln -s "${temporary}/actual" "${temporary}/alias"
expect_refusal parent-symlink python3 "${builder}" --parameters "${parameters}" \
  --manifest "${temporary}/alias/u0_work_units.tsv" --source-root "${temporary}/alias" \
  --output "${temporary}/parent-symlink.out" --work-unit-id "${work_id}"

ruby -e 'bytes=File.binread(ARGV[0]); File.binwrite(ARGV[1],bytes.sub("68343e04","78343e04"))' \
  "${fixture}/u0_work_units.tsv" "${temporary}/parameters.tsv"
expect_refusal parameter-drift python3 "${builder}" --parameters "${parameters}" \
  --manifest "${temporary}/parameters.tsv" --source-root "${fixture}" \
  --output "${temporary}/parameters.out" --work-unit-id "${work_id}"

printf 'occupied\n' > "${temporary}/occupied.tsv"
expect_refusal output-exists python3 "${builder}" --parameters "${parameters}" \
  --manifest "${fixture}/u0_work_units.tsv" --source-root "${fixture}" \
  --output "${temporary}/occupied.tsv" --work-unit-id "${work_id}"

expect_refusal bad-start python3 "${builder}" --parameters "${parameters}" \
  --manifest "${fixture}/u0_work_units.tsv" --source-root "${fixture}" \
  --output "${temporary}/bad-start.tsv" --work-unit-id "${work_id}" --start-window 3

expect_refusal missing-selector python3 "${builder}" --parameters "${parameters}" \
  --manifest "${fixture}/u0_work_units.tsv" --source-root "${fixture}" \
  --output "${temporary}/missing-selector.tsv"

echo "U0_WORK_UNIT_BINDING_FAIL_CLOSED_PASS cases=7 resume_shard=2 multi_unit_selector=required"
