#!/usr/bin/env bash
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/sounio.lock.json"
fixture="$atlas_root/sounio/src/operator_fixture.sio"

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

if [[ -z "${SOUNIO_REPO:-}" ]]; then
  echo "BLOCKED: set SOUNIO_REPO to a checkout of the official sounio-lang/sounio repository" >&2
  exit 2
fi

if [[ ! -d "$SOUNIO_REPO/.git" || ! -x "$SOUNIO_REPO/bin/souc" ]]; then
  echo "BLOCKED: SOUNIO_REPO is not a usable Sounio checkout: $SOUNIO_REPO" >&2
  exit 2
fi

expected_repo="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("repository")' "$lock_file")"
expected_commit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("commit")' "$lock_file")"
actual_remote="$(git -C "$SOUNIO_REPO" remote get-url origin)"
actual_commit="$(git -C "$SOUNIO_REPO" rev-parse HEAD)"
fixture_sha256="$(sha256_file "$fixture")"

case "$actual_remote" in
  "$expected_repo"|https://github.com/sounio-lang/sounio|git@github.com:sounio-lang/sounio.git) ;;
  *)
    echo "BLOCKED: Sounio remote is not the official repository: $actual_remote" >&2
    exit 2
    ;;
esac

if [[ "$actual_commit" != "$expected_commit" ]]; then
  echo "BLOCKED: Sounio checkout does not match the pinned commit" >&2
  echo "expected=$expected_commit" >&2
  echo "actual=$actual_commit" >&2
  exit 2
fi

if [[ -n "$(git -C "$SOUNIO_REPO" status --porcelain)" ]]; then
  echo "BLOCKED: pinned Sounio checkout is dirty" >&2
  exit 2
fi

echo "sounio_repository=$expected_repo"
echo "sounio_commit=$actual_commit"
echo "sounio_launcher_sha256=$(sha256_file "$SOUNIO_REPO/bin/souc")"
echo "sounio_fixture_source_sha256=$fixture_sha256"

run_fixture() {
  local repo="$1"
  local root="$2"
  local output="/tmp/dosa-operator-fixture-${expected_commit:0:12}-${fixture_sha256:0:12}.elf"

  cd "$repo"
  "$repo/bin/souc" --version
  echo "science_boundary=off (executable specification fixture; not a release receipt)"
  "$repo/bin/souc" check "$root/sounio/src/operator_fixture.sio" --science-boundary off
  "$repo/bin/souc" compile "$root/sounio/src/operator_fixture.sio" -o "$output" --science-boundary off
  echo "fixture_executable_sha256=$(sha256_file "$output")"
  "$output"
}

if [[ -n "${SOUNIO_LIMA_INSTANCE:-}" ]]; then
  if ! command -v limactl >/dev/null 2>&1; then
    echo "BLOCKED: limactl is unavailable for SOUNIO_LIMA_INSTANCE=$SOUNIO_LIMA_INSTANCE" >&2
    exit 2
  fi
  guest_fixture="/tmp/dosa-operator-fixture-source-${fixture_sha256:0:12}.sio"
  limactl copy -y --backend=scp "$fixture" "$SOUNIO_LIMA_INSTANCE:$guest_fixture"
  limactl shell "$SOUNIO_LIMA_INSTANCE" -- bash -s -- \
    "$SOUNIO_REPO" "$guest_fixture" "${expected_commit:0:12}" "${fixture_sha256:0:12}" <<'SOUNIO_LINUX_RUNNER'
set -euo pipefail
repo="$1"
fixture="$2"
commit_short="$3"
fixture_short="$4"
output="/tmp/dosa-operator-fixture-${commit_short}-${fixture_short}.elf"

cd "$repo"
"$repo/bin/souc" --version
echo "science_boundary=off (executable specification fixture; not a release receipt)"
"$repo/bin/souc" check "$fixture" --science-boundary off
"$repo/bin/souc" compile "$fixture" -o "$output" --science-boundary off
echo "fixture_executable_sha256=$(sha256sum "$output" | awk '{print $1}')"
"$output"
SOUNIO_LINUX_RUNNER
else
  run_fixture "$SOUNIO_REPO" "$atlas_root"
fi
