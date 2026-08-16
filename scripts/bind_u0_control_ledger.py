#!/usr/bin/env python3
"""Bind U0 control candidates to exact post-download NCBI package assets.

This stage does not prove the biological metadata claims. It turns a strict
three-column inclusion request into the existing six-column byte/hash ledger.
The independent control-ledger validator must then parse the bound assets and
prove topology, ambiguity, and replicon class before a source freeze completes.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import re
import stat
import sys
from typing import Any


EXIT_INVALID = 11
ACCESSION_RE = re.compile(r"^[A-Z][A-Z0-9_]*[0-9]\.[0-9]+$")
ASSEMBLY_RE = re.compile(r"^GCF_[0-9]+\.[0-9]+$")
REQUIRED_CONTROLS = frozenset(
    {
        "topology_circular",
        "topology_linear",
        "ambiguity_present",
        "ambiguity_absent",
        "replicon_chromosome",
        "replicon_plasmid",
    }
)
EXPECTED_KIND = {
    "topology_circular": "gbff",
    "topology_linear": "gbff",
    "ambiguity_present": "fasta",
    "ambiguity_absent": "fasta",
    "replicon_chromosome": "sequence_report",
    "replicon_plasmid": "sequence_report",
}
CANDIDATE_HEADER = (
    "sequence_accession_version",
    "assembly_accession_version",
    "control_category",
)
LEDGER_HEADER = CANDIDATE_HEADER + (
    "asset_kind",
    "package_path",
    "evidence_sha256",
)


class BindingError(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_regular_input(path: pathlib.Path, label: str) -> pathlib.Path:
    if path.is_symlink():
        raise BindingError(f"SYMLINK_FORBIDDEN: {label}: {path}")
    if not path.is_file():
        raise BindingError(f"MISSING_FILE: {label}: {path}")
    return path.resolve(strict=True)


def require_directory(path: pathlib.Path, label: str) -> pathlib.Path:
    if path.is_symlink():
        raise BindingError(f"SYMLINK_FORBIDDEN: {label}: {path}")
    if not path.is_dir():
        raise BindingError(f"MISSING_DIRECTORY: {label}: {path}")
    return path.resolve(strict=True)


def load_candidates(path: pathlib.Path) -> list[tuple[str, str, str]]:
    require_regular_input(path, "control candidates")
    rows: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != CANDIDATE_HEADER:
            raise BindingError("INVALID_CONTROL_CANDIDATE_HEADER: exact three-column order required")
        for line_no, raw in enumerate(reader, start=2):
            if set(raw) != set(CANDIDATE_HEADER) or any(raw[key] is None for key in CANDIDATE_HEADER):
                raise BindingError(f"INVALID_CONTROL_CANDIDATE_ROW: {path}:{line_no}")
            accession, assembly, category = (raw[key] for key in CANDIDATE_HEADER)
            if not ACCESSION_RE.fullmatch(accession) or not ASSEMBLY_RE.fullmatch(assembly):
                raise BindingError(f"INVALID_VERSIONED_BINDING: {path}:{line_no}")
            if category not in REQUIRED_CONTROLS:
                raise BindingError(f"INVALID_CONTROL_CATEGORY: {path}:{line_no}: {category}")
            identity = (accession, category)
            if identity in seen:
                raise BindingError(f"DUPLICATE_CONTROL_CANDIDATE: {accession}:{category}")
            seen.add(identity)
            rows.append((accession, assembly, category))
    missing = sorted(REQUIRED_CONTROLS - {row[2] for row in rows})
    if missing:
        raise BindingError("CONTROL_CANDIDATES_INCOMPLETE: " + ",".join(missing))
    return sorted(rows, key=lambda row: (row[2], row[0]))


def package_asset(root: pathlib.Path, assembly: str, kind: str) -> tuple[pathlib.Path, str]:
    directory_parts = ("ncbi_dataset", "data", assembly)
    directory = root.joinpath(*directory_parts)
    cursor = root
    for part in directory_parts:
        cursor = cursor / part
        try:
            mode = cursor.lstat().st_mode
        except OSError as exc:
            raise BindingError(f"MISSING_EXPECTED_ASSET_DIRECTORY: {'/'.join(directory_parts)}") from exc
        if stat.S_ISLNK(mode):
            raise BindingError(f"SYMLINK_FORBIDDEN: package asset directory: {'/'.join(directory_parts)}")
    if not directory.is_dir() or not stat.S_ISDIR(directory.stat().st_mode):
        raise BindingError(f"MISSING_EXPECTED_ASSET_DIRECTORY: {'/'.join(directory_parts)}")

    if kind == "sequence_report":
        matches = [directory / "sequence_report.jsonl"]
    else:
        suffix = "_genomic.fna" if kind == "fasta" else "_genomic.gbff"
        exact = "genomic.fna" if kind == "fasta" else "genomic.gbff"
        matches = sorted(
            (
                entry for entry in directory.iterdir()
                if entry.name == exact or entry.name.endswith(suffix)
            ),
            key=lambda entry: entry.name,
        )
        if len(matches) != 1:
            raise BindingError(
                f"MISSING_EXPECTED_ASSET: EXPECTED_EXACTLY_ONE_{kind.upper()}_ASSET: "
                f"{'/'.join(directory_parts)}: observed={len(matches)}"
            )
    candidate = matches[0]
    parts = (*directory_parts, candidate.name)
    try:
        mode = candidate.lstat().st_mode
    except OSError as exc:
        raise BindingError(f"MISSING_EXPECTED_ASSET: {'/'.join(parts)}") from exc
    if stat.S_ISLNK(mode):
        raise BindingError(f"SYMLINK_FORBIDDEN: package asset: {'/'.join(parts)}")
    if not candidate.is_file() or not stat.S_ISREG(candidate.stat().st_mode):
        raise BindingError(f"MISSING_EXPECTED_ASSET: {'/'.join(parts)}")
    try:
        candidate.resolve(strict=True).relative_to(root)
    except (OSError, ValueError) as exc:
        raise BindingError(f"PATH_OUTSIDE_PACKAGE: {'/'.join(parts)}") from exc
    return candidate, pathlib.PurePosixPath(*parts).as_posix()


def require_output_path(path: pathlib.Path, label: str) -> pathlib.Path:
    if path.exists() or path.is_symlink():
        raise BindingError(f"REFUSE_OVERWRITE: {label}: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.parent.is_symlink():
        raise BindingError(f"SYMLINK_FORBIDDEN: {label} parent: {path.parent}")
    return path.parent.resolve(strict=True) / path.name


def bind(args: argparse.Namespace) -> dict[str, Any]:
    candidates_path = require_regular_input(args.control_candidates, "control candidates")
    package_root = require_directory(args.package_root, "package root")
    output_ledger = require_output_path(args.output_ledger, "ledger output")
    output_receipt = require_output_path(args.output_receipt, "binding receipt output")
    if output_ledger == output_receipt:
        raise BindingError("OUTPUT_COLLISION: ledger and receipt outputs must differ")

    candidates = load_candidates(candidates_path)
    ledger_rows: list[dict[str, Any]] = []
    for accession, assembly, category in candidates:
        kind = EXPECTED_KIND[category]
        asset, package_path = package_asset(package_root, assembly, kind)
        ledger_rows.append(
            {
                "sequence_accession_version": accession,
                "assembly_accession_version": assembly,
                "control_category": category,
                "asset_kind": kind,
                "package_path": package_path,
                "evidence_sha256": sha256_file(asset),
            }
        )

    lines = ["\t".join(LEDGER_HEADER)]
    lines.extend("\t".join(str(row[key]) for key in LEDGER_HEADER) for row in ledger_rows)
    ledger_bytes = ("\n".join(lines) + "\n").encode("utf-8")
    ledger_sha256 = sha256_bytes(ledger_bytes)

    receipt_root = output_receipt.parent
    try:
        candidates_rel = candidates_path.relative_to(receipt_root).as_posix()
        package_rel = package_root.relative_to(receipt_root).as_posix()
        ledger_rel = output_ledger.relative_to(receipt_root).as_posix()
    except ValueError as exc:
        raise BindingError(
            "RECEIPT_INPUT_OUTSIDE_ROOT: candidates, package, and ledger must be below binding receipt directory"
        ) from exc

    receipt = {
        "schema_version": "dosa-u0-control-binding-receipt-1",
        "status": "bound_unvalidated",
        "control_candidates_path": candidates_rel,
        "control_candidates_sha256": sha256_file(candidates_path),
        "package_root": package_rel,
        "control_ledger_path": ledger_rel,
        "control_ledger_sha256": ledger_sha256,
        "required_categories": sorted(REQUIRED_CONTROLS),
        "controls": ledger_rows,
        "semantic_validation_complete": False,
        "scientific_metrics_computed": False,
    }

    with output_ledger.open("xb") as handle:
        handle.write(ledger_bytes)
    output_receipt.write_text(canonical_json(receipt) + "\n", encoding="utf-8", newline="\n")
    return {
        "status": "bound_unvalidated",
        "controls": len(ledger_rows),
        "control_ledger_sha256": ledger_sha256,
        "binding_receipt": str(args.output_receipt),
        "binding_receipt_sha256": sha256_file(output_receipt),
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--control-candidates", required=True, type=pathlib.Path)
    result.add_argument("--package-root", required=True, type=pathlib.Path)
    result.add_argument("--output-ledger", required=True, type=pathlib.Path)
    result.add_argument("--output-receipt", required=True, type=pathlib.Path)
    return result


def main() -> int:
    try:
        print(canonical_json(bind(parser().parse_args())))
        return 0
    except (OSError, BindingError) as exc:
        print(
            canonical_json({"status": "error", "code": "U0_CONTROL_BINDING_INVALID", "message": str(exc)}),
            file=sys.stderr,
        )
        return EXIT_INVALID


if __name__ == "__main__":
    raise SystemExit(main())
