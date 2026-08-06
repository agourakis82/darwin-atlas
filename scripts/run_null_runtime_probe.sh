#!/usr/bin/env bash
# Engineering runtime probe for the null engines (Fase N, ADR-0002 evidence).
#
# Measures wall time of the pinned Sounio pipeline fixture
# (sounio/src/fasta_stream_fixture.sio, --pipeline optimized kernel) on the
# frozen cohort-smoke replicon (NC_002127.1, 3,306 bp, 207 windows at 16/16)
# for null_replicates in {8, 16, 32, 64} under both engines
# (mononucleotide_shuffle, dinucleotide_shuffle). Each config emits one
# NULL_RUNTIME_PROBE line with wall milliseconds; the ADR-0002 evidence
# annex fits the linear regime and projects pilot scale. This is an
# engineering measurement only: no performance claim, no scientific claim.
set -euo pipefail

readonly atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly lock_file="${atlas_root}/toolchains/sounio.lock.json"
readonly source_file="${atlas_root}/sounio/src/fasta_stream_fixture.sio"
readonly smoke_dir="${atlas_root}/data/fixtures/cohort_smoke"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    command sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ -z "${SOUNIO_REPO:-}" ]]; then
  echo "BLOCKED: set SOUNIO_REPO to the pinned official Sounio checkout" >&2
  exit 2
fi
for required in ruby limactl; do
  command -v "${required}" >/dev/null 2>&1 || { echo "BLOCKED: missing ${required}" >&2; exit 2; }
done
[[ -d "${SOUNIO_REPO}/.git" && -x "${SOUNIO_REPO}/bin/souc" ]] || {
  echo "BLOCKED: invalid Sounio checkout" >&2
  exit 2
}

expected_commit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("commit")' "${lock_file}")"
expected_repo="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("repository")' "${lock_file}")"
actual_commit="$(git -C "${SOUNIO_REPO}" rev-parse HEAD)"
actual_remote="$(git -C "${SOUNIO_REPO}" remote get-url origin)"
[[ "${actual_commit}" == "${expected_commit}" ]] || { echo "BLOCKED: Sounio pin mismatch" >&2; exit 2; }
case "${actual_remote}" in
  "${expected_repo}"|https://github.com/sounio-lang/sounio|git@github.com:sounio-lang/sounio.git) ;;
  *) echo "BLOCKED: unofficial Sounio remote" >&2 ;;
esac
[[ -z "$(git -C "${SOUNIO_REPO}" status --porcelain)" ]] || {
  echo "BLOCKED: pinned Sounio checkout is dirty" >&2
  exit 2
}

# Build the eight probe parameter sets on the host: the frozen cohort-smoke
# geometry plus additive null keys, preserving canonical key order.
mkdir -p "${temp_dir}/params"
for engine in mono dinuc; do
  model="mononucleotide_shuffle"
  [[ "${engine}" == "dinuc" ]] && model="dinucleotide_shuffle"
  for reps in 8 16 32 64; do
    ruby -rjson -e '
      base = JSON.parse(File.read(ARGV[0]))
      base["null_model"] = ARGV[1]
      base["null_replicates"] = Integer(ARGV[2])
      File.write(ARGV[3], JSON.pretty_generate(base) + "\n")
    ' "${smoke_dir}/parameters_k8.json" "${model}" "${reps}" \
      "${temp_dir}/params/parameters_${engine}_r${reps}.json"
  done
done

# Dinucleotide seed sidecars (one per replicate count; parameters_sha256
# enters the seed derivation, so they differ across configs).
for reps in 8 16 32 64; do
  ruby "${atlas_root}/scripts/generate_dinucleotide_seed_sidecar.rb" \
    "${temp_dir}/params/parameters_dinuc_r${reps}.json" \
    "${smoke_dir}/nc_002127_1.fa" "${smoke_dir}/nc_002127_1_metadata.tsv" \
    "${temp_dir}/params/sidecar_dinuc_r${reps}.tsv"
done

# Flat parameter rendering happens on the host (the guest has no ruby);
# identical rendering to run_sounio_null_metamorphic.sh.
render_flat() {
  ruby -rjson -rdigest -e '
    raw = File.binread(ARGV[0])
    obj = JSON.parse(raw)
    abort "parameter artifact is not a JSON object" unless obj.is_a?(Hash)
    lines = obj.map do |key, value|
      case value
      when true, false then "#{key}=#{value}"
      when Integer, Float, String then "#{key}=#{value}"
      else abort "non-scalar parameter value for key #{key.inspect}"
      end
    end
    lines << "parameters_sha256=#{Digest::SHA256.hexdigest(raw)}"
    File.binwrite(ARGV[1], lines.join("\n") + "\n")
  ' "$1" "$2"
}
for engine in mono dinuc; do
  for reps in 8 16 32 64; do
    render_flat "${temp_dir}/params/parameters_${engine}_r${reps}.json" \
      "${temp_dir}/params/parameters_${engine}_r${reps}.flat"
  done
done

readonly instance="${SOUNIO_LIMA_INSTANCE:-souc-linux}"
readonly source_sha="$(sha256_file "${source_file}")"
readonly guest_root="/tmp/dosa-null-runtime-${source_sha:0:12}-$$"
limactl shell "${instance}" -- mkdir -p "${guest_root}/params"
limactl copy -y --backend=scp "${source_file}" "${instance}:${guest_root}/fixture.sio"
limactl copy -y --backend=scp "${smoke_dir}/nc_002127_1.fa" "${smoke_dir}/nc_002127_1_metadata.tsv" \
  "${instance}:${guest_root}/"
for f in "${temp_dir}/params/"*; do
  limactl copy -y --backend=scp "$f" "${instance}:${guest_root}/params/"
done

limactl shell "${instance}" -- bash -s -- "${SOUNIO_REPO}" "${guest_root}" <<'PROBE_RUN'
set -euo pipefail
repo="$1"
root="$2"
cd "${repo}"
"${repo}/bin/souc" check "${root}/fixture.sio" --science-boundary off >/dev/null
"${repo}/bin/souc" compile "${root}/fixture.sio" -o "${root}/fixture.elf" --science-boundary off >/dev/null
echo "probe_executable_sha256=$(sha256sum "${root}/fixture.elf" | awk '{print $1}')"

for engine in mono dinuc; do
  for reps in 8 16 32 64; do
    flat="${root}/params/parameters_${engine}_r${reps}.flat"
    seed_args=()
    if [[ "${engine}" == "dinuc" ]]; then
      seed_args=("${root}/params/sidecar_dinuc_r${reps}.tsv")
    fi
    start=$(date +%s%N)
    "${root}/fixture.elf" --pipeline "${root}/nc_002127_1.fa" \
      "${root}/nc_002127_1_metadata.tsv" "${flat}" "${seed_args[@]}" \
      > "${root}/out_${engine}_r${reps}.jsonl"
    end=$(date +%s%N)
    wall_ms=$(( (end - start) / 1000000 ))
    lines=$(wc -l < "${root}/out_${engine}_r${reps}.jsonl" | tr -d ' ')
    test "${lines}" -eq 207
    echo "NULL_RUNTIME_PROBE engine=${engine} replicates=${reps} wall_ms=${wall_ms} lines=${lines}"
  done
done
PROBE_RUN

echo "sounio_repository=${expected_repo}"
echo "sounio_commit=${actual_commit}"
echo "sounio_source_sha256=${source_sha}"
echo "NULL_RUNTIME_PROBE_PASS configs=8 replicon=NC_002127.1 windows=207 metrics=18"
limactl shell "${instance}" -- rm -r "${guest_root}"
