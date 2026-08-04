#!/usr/bin/env bash
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact="$(mktemp "${TMPDIR:-/tmp}/dosa-sounio-metamorphic.log.XXXXXX")"

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

if ! bash "$atlas_root/scripts/run_sounio_metamorphic_fixture.sh" >"$artifact" 2>&1; then
  cat "$artifact" >&2
  echo "Sounio metamorphic fixture failed; Julia validation was not run" >&2
  exit 1
fi

cat "$artifact"
echo "sounio_metamorphic_artifact=$artifact"
echo "sounio_metamorphic_artifact_sha256=$(sha256_file "$artifact")"
julia --startup-file=no "$atlas_root/julia/scripts/validate_metamorphic_fixture.jl" "$artifact"
