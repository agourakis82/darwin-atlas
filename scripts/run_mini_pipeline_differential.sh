#!/usr/bin/env bash
# Differential mini-pipeline fixture: run the fail-closed Sounio producer,
# persist and hash the JSONL artifact, then require the independent Base-only
# Julia validator to reproduce every line, coordinate, exclusion, metric, and
# error tuple exactly. Absence of either implementation is a failure, never a
# fallback.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact="$(mktemp "${TMPDIR:-/tmp}/dosa-sounio-mini-pipeline.log.XXXXXX")"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "BLOCKED: no SHA-256 utility is available" >&2
    return 2
  fi
}

if ! bash "$atlas_root/scripts/run_sounio_mini_pipeline.sh" >"$artifact" 2>&1; then
  cat "$artifact" >&2
  echo "Sounio mini-pipeline failed; Julia validation was not run" >&2
  exit 1
fi

cat "$artifact"
echo "sounio_pipeline_runner_log=$artifact"
echo "sounio_pipeline_runner_log_sha256=$(sha256_file "$artifact")"

jsonl_artifact="$(grep '^sounio_pipeline_jsonl_artifact=' "$artifact" | tail -1 | cut -d= -f2-)"
jsonl_sha_log="$(grep '^sounio_pipeline_jsonl_sha256=' "$artifact" | tail -1 | cut -d= -f2-)"
jsonl_sha_actual="$(sha256_file "$jsonl_artifact")"
if [[ "$jsonl_sha_log" != "$jsonl_sha_actual" ]]; then
  echo "persisted JSONL artifact hash diverges from the runner log" >&2
  exit 1
fi

if ! command -v julia >/dev/null 2>&1; then
  echo "BLOCKED: julia is unavailable; independent validation cannot run" >&2
  exit 2
fi

julia --startup-file=no "$atlas_root/julia/scripts/validate_mini_pipeline.jl" \
  "$artifact" "$atlas_root/data/fixtures/mini_pipeline"
