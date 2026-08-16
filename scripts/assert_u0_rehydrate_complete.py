#!/usr/bin/env python3
"""Fail closed unless every NCBI fetch.txt payload exists and is non-empty.

`datasets rehydrate` can exit 0 after gateway 'File unavailable' retries. A
source freeze must not treat that as a complete package. This check never
computes DOSA metrics.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


EXIT_INCOMPLETE = 11
FETCH_RELATIVE = Path("ncbi_dataset") / "fetch.txt"


class RehydrateCompleteError(RuntimeError):
    pass


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def parse_fetch_paths(fetch_file: Path) -> list[str]:
    paths: list[str] = []
    seen: set[str] = set()
    for line_number, line in enumerate(fetch_file.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            raise RehydrateCompleteError(f"BLOCKED: malformed fetch.txt line {line_number}")
        relative = parts[-1].strip().replace("\\", "/")
        if not relative or relative.startswith("/") or ".." in Path(relative).parts:
            raise RehydrateCompleteError(f"BLOCKED: unsafe fetch path on line {line_number}: {relative}")
        if relative in seen:
            raise RehydrateCompleteError(f"BLOCKED: duplicate fetch path: {relative}")
        seen.add(relative)
        paths.append(relative)
    if not paths:
        raise RehydrateCompleteError("BLOCKED: fetch.txt lists no payload files")
    return paths


def inspect_package(package_root: Path) -> dict[str, object]:
    if package_root.is_symlink() or not package_root.is_dir():
        raise RehydrateCompleteError(f"BLOCKED: rehydrated package root is missing: {package_root}")
    fetch_file = package_root / FETCH_RELATIVE
    if fetch_file.is_symlink() or not fetch_file.is_file():
        raise RehydrateCompleteError(f"BLOCKED: fetch.txt is missing: {fetch_file}")
    bag = fetch_file.parent
    wanted = parse_fetch_paths(fetch_file)
    missing: list[str] = []
    empty: list[str] = []
    for relative in wanted:
        payload = bag / relative
        if payload.is_symlink():
            raise RehydrateCompleteError(f"BLOCKED: rehydrated payload is a symlink: {relative}")
        if not payload.is_file():
            missing.append(relative)
            continue
        if payload.stat().st_size < 1:
            empty.append(relative)
    receipt = {
        "empty_files": empty,
        "fetch_entries": len(wanted),
        "missing_files": missing,
        "schema_version": "dosa-v3-u0-rehydrate-complete-1",
        "scientific_metrics_computed": False,
        "status": "complete" if not missing and not empty else "incomplete",
    }
    if missing or empty:
        raise RehydrateCompleteError(
            "BLOCKED: rehydrate incomplete "
            + canonical_json({"missing": len(missing), "empty": len(empty), "wanted": len(wanted)})
        )
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", required=True, type=Path)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    try:
        receipt = inspect_package(args.package_root)
    except RehydrateCompleteError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INCOMPLETE
    encoded = canonical_json(receipt) + "\n"
    if args.receipt is not None:
        args.receipt.write_text(encoded, encoding="utf-8", newline="\n")
    sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
