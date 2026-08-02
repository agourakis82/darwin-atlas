#!/usr/bin/env bash
# Fail-closed engineering release bundle builder (Fase J, G6 evidence).
#
# Builds an immutable engineering-scope release bundle from a CLEAN tree:
#   - a git-archive tarball of the current commit;
#   - the full-battery evidence log (must end with BATTERY_ALL_GREEN);
#   - a SHA256SUMS manifest over the bundle files;
#   - release_receipt.json binding the archived commit, the validated
#     two-stage products receipt, the chromosome benchmark receipt, the
#     battery evidence hash, and the tarball hash. The DOI field is an
#     explicit placeholder: no deposit has been made.
# The bundle directory release/<bundle_id>/ is committed to the repository;
# the large ephemeral products remain hash-bound in their receipts, never
# committed. This is an engineering release, NOT the pilot release: ADR-0002
# remains proposed and no pilot parameters are fixed.
set -euo pipefail

atlas_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$atlas_root/toolchains/sounio.lock.json"

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

if [[ $# -ne 2 ]]; then
  echo "usage: build_release_bundle.sh <battery_evidence_log> <products_receipt_run_id>" >&2
  exit 2
fi
battery_log="$1"
products_run_id="$2"

if [[ ! -f "$battery_log" ]]; then
  echo "BLOCKED: battery evidence log not found: $battery_log" >&2
  exit 2
fi
if [[ "$(tail -1 "$battery_log")" != "BATTERY_ALL_GREEN" ]]; then
  echo "BLOCKED: battery evidence log does not end with BATTERY_ALL_GREEN" >&2
  exit 2
fi

if [[ -n "$(git -C "$atlas_root" status --porcelain)" ]]; then
  echo "BLOCKED: release requires a clean tree" >&2
  exit 2
fi

products_receipt="$atlas_root/receipts/$products_run_id/run_receipt.json"
if [[ ! -f "$products_receipt" ]]; then
  echo "BLOCKED: products receipt not found: $products_receipt" >&2
  exit 2
fi

benchmark_dir="$(dirname "$(find "$atlas_root/receipts" -name benchmark_receipt.json | head -1)")"
if [[ ! -f "$benchmark_dir/benchmark_receipt.json" ]]; then
  echo "BLOCKED: no chromosome benchmark receipt found under receipts/" >&2
  exit 2
fi

commit="$(git -C "$atlas_root" rev-parse HEAD)"
version="0.1.0-engineering"
created_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
bundle_id="darwin-atlas-${version}-${commit:0:8}"
out_dir="$atlas_root/release/$bundle_id"
mkdir -p "$out_dir"

tarball="$out_dir/$bundle_id.tar.gz"
git -C "$atlas_root" archive --format=tar.gz -o "$tarball" HEAD

cp "$battery_log" "$out_dir/battery_evidence.txt"

(
  cd "$out_dir"
  sha256_file "$(basename "$tarball")" > SHA256SUMS
  sha256_file "battery_evidence.txt" >> SHA256SUMS
)

sounio_commit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("commit")' "$lock_file")"
sounio_repo="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("repository")' "$lock_file")"

ruby -rjson -rdigest -e '
  out_dir = ARGV[0]
  bundle_id = ARGV[1]
  receipt = {
    "receipt_kind" => "engineering_release",
    "receipt_version" => "0.1.0",
    "specification_version" => "0.1.0",
    "engineering_scope" => true,
    "release_eligible" => false,
    "doi" => "pending",
    "doi_note" => "explicit placeholder: no deposit has been made; DOI assignment is pending",
    "bundle_id" => bundle_id,
    "created_utc" => ARGV[2],
    "source_commit" => ARGV[3],
    "source_dirty" => false,
    "archive_note" => "the tarball is a git archive of source_commit; the release metadata commit (this bundle directory) follows it and is not inside the tarball",
    "sounio" => { "repository" => ARGV[4], "commit" => ARGV[5] },
    "products_receipt" => {
      "run_id" => ARGV[6],
      "receipt_sha256" => Digest::SHA256.file(ARGV[7]).hexdigest,
    },
    "benchmark_receipt" => {
      "run_id" => File.basename(ARGV[8]),
      "receipt_sha256" => Digest::SHA256.file("#{ARGV[8]}/benchmark_receipt.json").hexdigest,
    },
    "battery" => {
      "evidence_file" => "battery_evidence.txt",
      "evidence_sha256" => Digest::SHA256.file("#{out_dir}/battery_evidence.txt").hexdigest,
      "final_marker" => "BATTERY_ALL_GREEN",
    },
    "bundle_files" => {
      "tarball" => "#{bundle_id}.tar.gz",
      "tarball_sha256" => Digest::SHA256.file("#{out_dir}/#{bundle_id}.tar.gz").hexdigest,
      "tarball_size_bytes" => File.size("#{out_dir}/#{bundle_id}.tar.gz"),
      "manifest" => "SHA256SUMS",
    },
  }
  File.binwrite("#{out_dir}/release_receipt.json", JSON.pretty_generate(receipt) + "\n")
  puts "release_receipt=#{out_dir}/release_receipt.json"
' "$out_dir" "$bundle_id" "$created_utc" "$commit" "$sounio_repo" "$sounio_commit" \
  "$products_run_id" "$products_receipt" "$benchmark_dir"

echo "DOSA_RELEASE_BUNDLE_OK bundle_id=$bundle_id out_dir=$out_dir"
