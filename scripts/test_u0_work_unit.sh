#!/usr/bin/env bash
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly fixture="${root}/data/fixtures/u0_work_unit"
readonly builder="${root}/scripts/build_u0_work_unit_case.py"
readonly parameters="${root}/data/v3/u0_parameters.json"
readonly temporary="$(mktemp -d)"
trap 'rm -rf -- "${temporary}"' EXIT

python3 "${builder}" --parameters "${parameters}" --manifest "${fixture}/u0_work_units.tsv" \
  --source-root "${fixture}" --output "${temporary}/valid.tsv" >/dev/null
test "$(wc -l < "${temporary}/valid.tsv")" -eq 2
test "$(shasum -a 256 "${temporary}/valid.tsv" | awk '{print $1}')" = \
  "781326e35a9f32b874c8fa49c3b1249c330a05f1e5625bd9bff67b7a567f7457"

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
  --output "${temporary}/tampered.out"
test ! -e "${temporary}/tampered.out"

mkdir -p "${temporary}/linked"
ln -s "${fixture}/fasta" "${temporary}/linked/fasta"
cp "${fixture}/u0_work_units.tsv" "${temporary}/linked/manifest.tsv"
expect_refusal source-symlink python3 "${builder}" --parameters "${parameters}" \
  --manifest "${temporary}/linked/manifest.tsv" --source-root "${temporary}/linked" \
  --output "${temporary}/linked.out"

mkdir -p "${temporary}/actual"
cp -R "${fixture}/." "${temporary}/actual/"
ln -s "${temporary}/actual" "${temporary}/alias"
expect_refusal parent-symlink python3 "${builder}" --parameters "${parameters}" \
  --manifest "${temporary}/alias/u0_work_units.tsv" --source-root "${temporary}/alias" \
  --output "${temporary}/parent-symlink.out"

ruby -e 'bytes=File.binread(ARGV[0]); File.binwrite(ARGV[1],bytes.sub("68343e04","78343e04"))' \
  "${fixture}/u0_work_units.tsv" "${temporary}/parameters.tsv"
expect_refusal parameter-drift python3 "${builder}" --parameters "${parameters}" \
  --manifest "${temporary}/parameters.tsv" --source-root "${fixture}" \
  --output "${temporary}/parameters.out"

printf 'occupied\n' > "${temporary}/occupied.tsv"
expect_refusal output-exists python3 "${builder}" --parameters "${parameters}" \
  --manifest "${fixture}/u0_work_units.tsv" --source-root "${fixture}" \
  --output "${temporary}/occupied.tsv"

echo "U0_WORK_UNIT_BINDING_FAIL_CLOSED_PASS cases=5"
