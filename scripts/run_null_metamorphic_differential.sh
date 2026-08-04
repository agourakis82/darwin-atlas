#!/usr/bin/env bash
# Null-engine metamorphic differential (Fase M4): run the fail-closed Sounio
# producer on the engineered null-metamorphic fixtures, persist and hash both
# JSONL artifacts, then require the independent Base-only Julia validator to
# reproduce every line byte for byte AND to confirm the explicit metamorphic
# relations MR1-MR4 over the persisted producer output. Absence of either
# implementation is a failure, never a fallback.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact="$(mktemp "${TMPDIR:-/tmp}/dosa-sounio-null-metamorphic.log.XXXXXX")"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    command sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "BLOCKED: no SHA-256 utility is available" >&2
    return 2
  fi
}

if ! bash "$atlas_root/scripts/run_sounio_null_metamorphic.sh" >"$artifact" 2>&1; then
  cat "$artifact" >&2
  echo "Sounio null-metamorphic fixture failed; Julia validation was not run" >&2
  exit 1
fi

cat "$artifact"
echo "sounio_nullmeta_runner_log=$artifact"
echo "sounio_nullmeta_runner_log_sha256=$(sha256_file "$artifact")"

if ! command -v julia >/dev/null 2>&1; then
  echo "BLOCKED: julia is unavailable; independent validation cannot run" >&2
  exit 2
fi

julia --startup-file=no "$atlas_root/julia/scripts/validate_null_metamorphic.jl" \
  "$artifact" "$atlas_root/data/fixtures/null_metamorphic"
