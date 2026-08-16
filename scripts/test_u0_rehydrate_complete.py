#!/usr/bin/env python3
"""Offline regression for fail-closed NCBI rehydrate completeness checks."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
ASSERT = ROOT / "scripts" / "assert_u0_rehydrate_complete.py"


def invoke(package_root: pathlib.Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(ASSERT), "--package-root", str(package_root)],
        capture_output=True,
        text=True,
        check=False,
    )


def write_fetch(package_root: pathlib.Path, rows: list[str]) -> None:
    fetch = package_root / "ncbi_dataset" / "fetch.txt"
    fetch.parent.mkdir(parents=True, exist_ok=True)
    fetch.write_text("".join(rows), encoding="utf-8", newline="\n")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="dosa-u0-rehydrate-complete-test.", dir="/private/tmp") as temporary_name:
        temporary = pathlib.Path(temporary_name)
        complete = temporary / "complete"
        payload_dir = complete / "ncbi_dataset" / "data" / "GCF_000000001.1"
        payload_dir.mkdir(parents=True)
        (payload_dir / "genomic.fna").write_text(">NC_000001.1\nACGT\n", encoding="utf-8", newline="\n")
        (payload_dir / "genomic.gbff").write_text("LOCUS\n", encoding="utf-8", newline="\n")
        write_fetch(
            complete,
            [
                "https://example.invalid/a\t0\tdata/GCF_000000001.1/genomic.fna\n",
                "https://example.invalid/b\t0\tdata/GCF_000000001.1/genomic.gbff\n",
            ],
        )
        completed = invoke(complete)
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        receipt = json.loads(completed.stdout)
        if receipt["status"] != "complete" or receipt["fetch_entries"] != 2:
            raise RuntimeError(completed.stdout)

        missing = temporary / "missing"
        write_fetch(missing, ["https://example.invalid/a\t0\tdata/GCF_000000001.1/genomic.fna\n"])
        missed = invoke(missing)
        if missed.returncode != 11 or "rehydrate incomplete" not in missed.stderr:
            raise RuntimeError(missed.stderr or missed.stdout)

        empty = temporary / "empty"
        empty_payload = empty / "ncbi_dataset" / "data" / "GCF_000000001.1"
        empty_payload.mkdir(parents=True)
        (empty_payload / "genomic.fna").write_bytes(b"")
        write_fetch(empty, ["https://example.invalid/a\t0\tdata/GCF_000000001.1/genomic.fna\n"])
        emptied = invoke(empty)
        if emptied.returncode != 11 or "rehydrate incomplete" not in emptied.stderr:
            raise RuntimeError(emptied.stderr or emptied.stdout)

        unsafe = temporary / "unsafe"
        write_fetch(unsafe, ["https://example.invalid/a\t0\t../escape.fna\n"])
        escaped = invoke(unsafe)
        if escaped.returncode != 11 or "unsafe fetch path" not in escaped.stderr:
            raise RuntimeError(escaped.stderr or escaped.stdout)

    print("U0_REHYDRATE_COMPLETE_FIXTURE_PASS cases=4 fail_closed=3")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
