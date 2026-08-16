#!/usr/bin/env bash
# Continue a U0 source freeze from an already authenticated RefSeq discovery
# snapshot. This does not rerun the dehydrated-universe download. It still
# downloads only the selected assemblies and computes no DOSA metric.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "usage: $0 DISCOVERY_DIRECTORY OUTPUT_DIRECTORY CONTROL_CANDIDATES.tsv EXPECTED_DEHYDRATED_SHA256 [EXPECTED_ASSEMBLY_COUNT] [--resume-package]" >&2
  exit 2
}

[[ "$#" -eq 4 || "$#" -eq 5 || "$#" -eq 6 ]] || usage
discovery_dir="$1"
output_dir="$2"
control_candidates="$3"
expected_sha="$4"
expected_count="${5:-64971}"
resume_flag=()
if [[ "$#" -eq 6 ]]; then
  [[ "$6" == "--resume-package" ]] || usage
  resume_flag=(--resume-package)
  expected_count="${5}"
elif [[ "$#" -eq 5 && "$5" == "--resume-package" ]]; then
  expected_count=64971
  resume_flag=(--resume-package)
fi

exec "$atlas_root/scripts/freeze_u0_refseq_snapshot.sh" \
  --from-discovery "$discovery_dir" \
  --expected-dehydrated-sha256 "$expected_sha" \
  --expected-assembly-count "$expected_count" \
  "${resume_flag[@]}" \
  "$output_dir" \
  "$control_candidates"
