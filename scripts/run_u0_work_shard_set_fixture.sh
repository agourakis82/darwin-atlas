#!/usr/bin/env bash
# Compile the bounded work-shard executor from the pinned official Sounio tree,
# execute a nine-shard resumable fixture, package its canonical stream as typed
# Parquet/Zstandard, and independently recompute every reopened row in Julia.
# This is fixture evidence, not Gate U0 or a release receipt.
set -euo pipefail

readonly atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_file="${atlas_root}/sounio/src/u0_work_shard_executor.sio"
readonly executor_script="${atlas_root}/scripts/execute_u0_work_shard_plan.py"
readonly planner="${atlas_root}/scripts/plan_u0_eligible_work_shards.py"
readonly validator="${atlas_root}/julia/scripts/validate_u0_work_shard_set.jl"
readonly packager="${atlas_root}/scripts/package_u0_work_shard_set.py"
readonly parquet_validator="${atlas_root}/julia/scripts/validate_u0_work_parquet_set.jl"
readonly parameters="${atlas_root}/data/v3/u0_parameters.json"
readonly common_schema="${atlas_root}/schemas/dosa_v3_common.schema.json"
readonly window_schema="${atlas_root}/schemas/dosa_v3_window_profile.schema.json"
readonly fixture="${atlas_root}/data/fixtures/u0_work_unit"
readonly manifest="${fixture}/u0_work_units.tsv"
readonly lock_file="${atlas_root}/toolchains/sounio.lock.json"
readonly run_id="u0-work-shard-set-fixture"
readonly julia_bin="${JULIA_BIN:-julia}"
readonly instance="${SOUNIO_LIMA_INSTANCE:-}"
readonly physical_temp_root="$(python3 -c 'import os,tempfile; print(os.path.realpath(tempfile.gettempdir()))')"
readonly temporary="$(mktemp -d "${physical_temp_root}/dosa-u0-work-set.XXXXXX")"
guest_root=""

cleanup() {
  if [[ -n "${guest_root}" ]] && command -v limactl >/dev/null 2>&1; then
    limactl shell "${instance}" -- rm -r "${guest_root}" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${temporary}"
}
trap cleanup EXIT

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

blocked() { echo "BLOCKED: $*" >&2; exit 2; }

[[ -n "${SOUNIO_REPO:-}" ]] || blocked "set SOUNIO_REPO to the pinned official Sounio checkout"
for required in python3 ruby; do command -v "${required}" >/dev/null 2>&1 || blocked "missing ${required}"; done
python3 -c 'import duckdb; assert duckdb.__version__ == "1.5.5", duckdb.__version__' \
  >/dev/null 2>&1 || blocked "duckdb==1.5.5 is required for the Parquet differential"
command -v "${julia_bin}" >/dev/null 2>&1 || blocked "missing Julia validator: ${julia_bin}"
[[ -x "${SOUNIO_REPO}/bin/souc" ]] || blocked "invalid Sounio checkout"
expected_commit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("commit")' "${lock_file}")"
expected_repo="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("repository")' "${lock_file}")"
actual_commit="$(git -C "${SOUNIO_REPO}" rev-parse HEAD)"
actual_remote="$(git -C "${SOUNIO_REPO}" remote get-url origin)"
[[ "${actual_commit}" == "${expected_commit}" ]] || blocked "Sounio pin mismatch"
case "${actual_remote}" in
  "${expected_repo}"|https://github.com/sounio-lang/sounio|git@github.com:sounio-lang/sounio.git) ;;
  *) blocked "unofficial Sounio remote" ;;
esac
[[ -z "$(git -C "${SOUNIO_REPO}" status --porcelain)" ]] || blocked "pinned Sounio checkout is dirty"

python3 "${planner}" --parameters "${parameters}" --manifest "${manifest}" \
  --source-root "${fixture}" --output-directory "${temporary}/plan" --shard-size 2 --run-id "${run_id}"

source_sha="$(sha256_file "${source_file}")"
local_elf="${temporary}/u0-work-shard.elf"
if [[ -n "${instance}" ]]; then
  command -v limactl >/dev/null 2>&1 || blocked "limactl is unavailable for ${instance}"
  guest_root="/tmp/dosa-u0-work-set-${source_sha:0:12}-$$"
  limactl shell "${instance}" -- mkdir -p "${guest_root}/plan/cases"
  limactl copy -y --backend=scp "${source_file}" "${instance}:${guest_root}/executor.sio"
  limactl copy -y --backend=scp "${executor_script}" "${instance}:${guest_root}/execute.py"
  limactl copy -y --backend=scp "${temporary}/plan/work_shard_plan.json" "${instance}:${guest_root}/plan/work_shard_plan.json"
  for case_file in "${temporary}"/plan/cases/*.tsv; do
    limactl copy -y --backend=scp "${case_file}" "${instance}:${guest_root}/plan/cases/$(basename "${case_file}")"
  done
  limactl shell "${instance}" -- bash -s -- "${SOUNIO_REPO}" "${guest_root}" <<'SOUNIO_RUN'
set -euo pipefail
repo="$1"; root="$2"; cd "$repo"
"$repo/bin/souc" check "$root/executor.sio" --science-boundary off
"$repo/bin/souc" compile "$root/executor.sio" -o "$root/executor.elf" --science-boundary off
sha256sum "$root/executor.elf" | awk '{print "sounio_executable_sha256=" $1}'
python3 "$root/execute.py" --plan-directory "$root/plan" --executor "$root/executor.elf" --output-directory "$root/execution"
python3 "$root/execute.py" --plan-directory "$root/plan" --executor "$root/executor.elf" --output-directory "$root/execution"
SOUNIO_RUN
  mkdir -p "${temporary}/execution/artifacts"
  limactl copy -y --backend=scp "${instance}:${guest_root}/execution/execution_ledger.tsv" "${temporary}/execution/execution_ledger.tsv"
  while IFS= read -r name; do
    limactl copy -y --backend=scp "${instance}:${guest_root}/execution/artifacts/${name}.jsonl" \
      "${temporary}/execution/artifacts/${name}.jsonl"
  done < <(python3 -c 'import json,pathlib,sys; p=json.load(open(sys.argv[1])); [print(pathlib.Path(s["path"]).stem) for s in p["shards"]]' "${temporary}/plan/work_shard_plan.json")
else
  (
    cd "${SOUNIO_REPO}"
    "${SOUNIO_REPO}/bin/souc" check "${source_file}" --science-boundary off
    "${SOUNIO_REPO}/bin/souc" compile "${source_file}" -o "${local_elf}" --science-boundary off
  )
  echo "sounio_executable_sha256=$(sha256_file "${local_elf}")"
  python3 "${executor_script}" --plan-directory "${temporary}/plan" --executor "${local_elf}" --output-directory "${temporary}/execution"
  python3 "${executor_script}" --plan-directory "${temporary}/plan" --executor "${local_elf}" --output-directory "${temporary}/execution"
fi

"${julia_bin}" --startup-file=no "${validator}" "${parameters}" "${manifest}" \
  "${fixture}" "${temporary}/plan" "${temporary}/execution"

python3 "${packager}" --parameters "${parameters}" --manifest "${manifest}" \
  --source-root "${fixture}" --execution-root "${temporary}/execution" \
  --output "${temporary}/parquet-set" --window-schema "${window_schema}" \
  --common-schema "${common_schema}"
"${julia_bin}" --startup-file=no "${parquet_validator}" "${parameters}" "${manifest}" \
  "${fixture}" "${temporary}/parquet-set"

# A second independently written package must have the same logical, Parquet,
# binding and closure bytes under the pinned transport implementation.
python3 "${packager}" --parameters "${parameters}" --manifest "${manifest}" \
  --source-root "${fixture}" --execution-root "${temporary}/execution" \
  --output "${temporary}/parquet-set-second" --window-schema "${window_schema}" \
  --common-schema "${common_schema}"
diff -qr "${temporary}/parquet-set" "${temporary}/parquet-set-second" >/dev/null

cp -R "${temporary}/parquet-set" "${temporary}/parquet-tampered"
first_parquet="$(find "${temporary}/parquet-tampered" -type f -name '*.parquet' | sort | head -n 1)"
ruby -e 'bytes=File.binread(ARGV[0]); i=bytes.length/2; bytes.setbyte(i,bytes.getbyte(i)^1); File.binwrite(ARGV[0],bytes)' "${first_parquet}"
set +e
"${julia_bin}" --startup-file=no "${parquet_validator}" "${parameters}" "${manifest}" \
  "${fixture}" "${temporary}/parquet-tampered" >"${temporary}/parquet-tamper.log" 2>&1
parquet_tamper_rc=$?
set -e
[[ "${parquet_tamper_rc}" -ne 0 ]] || { echo "FAIL: Julia accepted a perturbed Parquet payload" >&2; exit 1; }
grep -q 'Parquet payload SHA-256 mismatch' "${temporary}/parquet-tamper.log"

cp -R "${temporary}/parquet-set" "${temporary}/roundtrip-tampered"
first_roundtrip="$(find "${temporary}/roundtrip-tampered/roundtrip" -type f -name '*.jsonl' | sort | head -n 1)"
ruby -e 'bytes=File.binread(ARGV[0]); marker="\"numerator\":"; i=bytes.index(marker) or abort "marker missing"; j=i+marker.bytesize; bytes.setbyte(j,bytes.getbyte(j)==57 ? 56 : bytes.getbyte(j)+1); File.binwrite(ARGV[0],bytes)' "${first_roundtrip}"
set +e
"${julia_bin}" --startup-file=no "${parquet_validator}" "${parameters}" "${manifest}" \
  "${fixture}" "${temporary}/roundtrip-tampered" >"${temporary}/roundtrip-tamper.log" 2>&1
roundtrip_tamper_rc=$?
set -e
[[ "${roundtrip_tamper_rc}" -ne 0 ]] || { echo "FAIL: Julia accepted a perturbed Parquet round-trip" >&2; exit 1; }
grep -Eq 'round-trip JSONL SHA-256 mismatch|Parquet round-trip differs' "${temporary}/roundtrip-tamper.log"

first_artifact="$(find "${temporary}/execution/artifacts" -type f -name '*.jsonl' | sort | head -n 1)"
ruby -e 'bytes=File.binread(ARGV[0]); marker="\"numerator\":"; i=bytes.index(marker) or abort "marker missing"; j=i+marker.bytesize; bytes.setbyte(j,bytes.getbyte(j)==57 ? 56 : bytes.getbyte(j)+1); File.binwrite(ARGV[1],bytes)' \
  "${first_artifact}" "${temporary}/perturbed.jsonl"
set +e
"${julia_bin}" --startup-file=no "${validator}" "${parameters}" "${manifest}" \
  "${fixture}" "${temporary}/plan" "${temporary}/execution" >"${temporary}/perturbed-validation.log" 2>&1
baseline_rc=$?
set -e
[[ "${baseline_rc}" -eq 0 ]] || { cat "${temporary}/perturbed-validation.log" >&2; exit 1; }
cp "${temporary}/perturbed.jsonl" "${first_artifact}"
set +e
"${julia_bin}" --startup-file=no "${validator}" "${parameters}" "${manifest}" \
  "${fixture}" "${temporary}/plan" "${temporary}/execution" >"${temporary}/tamper.log" 2>&1
tamper_rc=$?
set -e
[[ "${tamper_rc}" -ne 0 ]] || { echo "FAIL: Julia accepted a perturbed shard" >&2; exit 1; }
grep -Eq 'artifact SHA mismatch|byte mismatch' "${temporary}/tamper.log"

echo "sounio_repository=${expected_repo}"
echo "sounio_commit=${actual_commit}"
echo "sounio_source_sha256=${source_sha}"
echo "plan_sha256=$(sha256_file "${temporary}/plan/work_shard_plan.json")"
echo "execution_ledger_sha256=$(sha256_file "${temporary}/execution/execution_ledger.tsv")"
echo "parquet_set_manifest_sha256=$(sha256_file "${temporary}/parquet-set/parquet_set_manifest.json")"
echo "parquet_set_ledger_sha256=$(sha256_file "${temporary}/parquet-set/parquet_set_ledger.tsv")"
echo "parquet_payload_ledger_sha256=$(sha256_file "${temporary}/parquet-set/parquet_payload_ledger.tsv")"
echo "U0_WORK_SHARD_SET_DIFFERENTIAL_PASS work_units=7 shards=9 rows=12 excluded_work_units=1 resumed_shards=9 parquet_scales=4 roundtrip_byte_exact=1 tolerance=0 fixture_scope_nonpromotable=1"
echo "U0_GATE_PASS=false"
