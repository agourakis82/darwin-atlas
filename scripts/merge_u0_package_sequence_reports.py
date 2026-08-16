#!/usr/bin/env python3
"""Merge per-assembly NCBI package sequence_report.jsonl files deterministically.

This is acquisition/routing only. It concatenates the rehydrated package reports
in sorted GCF directory order, accepts NCBI Datasets 18.35 camelCase and the
summary-API snake_case, and emits a hash-closed merge receipt. It computes no
DOSA metric and does not authorize U0 or a full atlas.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import tempfile
from typing import Any


EXIT_INVALID = 11
ASSEMBLY_RE = re.compile(r"^GCF_[0-9]+\.[0-9]+$")
SEQUENCE_RE = re.compile(r"^[A-Z][A-Z0-9_]*[0-9]\.[0-9]+$")
SCHEMA_VERSION = "dosa-v3-u0-package-sequence-report-merge-receipt-1"


class MergeError(RuntimeError):
    pass


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def reject_symlink(path: pathlib.Path, label: str) -> None:
    absolute = path.absolute()
    current = pathlib.Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        if current.is_symlink():
            raise MergeError(f"{label} path may not contain symlinks")


def regular(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink(path, label)
    if path.is_symlink() or not path.is_file():
        raise MergeError(f"{label} must be a regular non-symlink file")
    return path.resolve(strict=True)


def require_directory(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink(path, label)
    if path.is_symlink() or not path.is_dir():
        raise MergeError(f"{label} must be a real directory")
    return path.resolve(strict=True)


def require_output(path: pathlib.Path, label: str) -> pathlib.Path:
    if path.exists() or path.is_symlink():
        raise MergeError(f"refusing to overwrite {label}: {path}")
    reject_symlink(path.parent, f"{label} parent")
    if not path.parent.is_dir():
        raise MergeError(f"{label} parent must be a real directory")
    return path


def strict_object(raw: str, label: str) -> dict[str, Any]:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ValueError(f"duplicate JSON key: {key}")
            value[key] = item
        return value

    try:
        value = json.loads(raw, object_pairs_hook=unique)
    except (ValueError, json.JSONDecodeError) as exc:
        raise MergeError(f"{label} is not strict JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise MergeError(f"{label} must be a JSON object")
    return value


def report_field(row: dict[str, Any], snake: str, camel: str) -> Any:
    snake_value = row.get(snake)
    camel_value = row.get(camel)
    if snake_value is not None and camel_value is not None and snake_value != camel_value:
        raise MergeError(f"conflicting {snake}/{camel} values")
    return snake_value if snake_value is not None else camel_value


def load_assemblies(path: pathlib.Path) -> list[str]:
    raw = regular(path, "assembly report").read_bytes()
    if not raw or not raw.endswith(b"\n") or b"\r" in raw:
        raise MergeError("assembly report must be LF-only with terminal LF")
    accessions: list[str] = []
    seen: set[str] = set()
    for line_number, line in enumerate(raw.decode("utf-8").splitlines(), start=1):
        row = strict_object(line, f"assembly report line {line_number}")
        accession = row.get("accession")
        if accession is None:
            accession = report_field(row, "current_accession", "currentAccession")
        if not isinstance(accession, str) or ASSEMBLY_RE.fullmatch(accession) is None:
            raise MergeError(f"invalid RefSeq assembly accession at line {line_number}")
        if accession in seen:
            raise MergeError(f"duplicate assembly accession: {accession}")
        seen.add(accession)
        accessions.append(accession)
    if not accessions:
        raise MergeError("assembly report has no accessions")
    return accessions


def package_reports(data_root: pathlib.Path) -> list[tuple[str, pathlib.Path]]:
    reports: list[tuple[str, pathlib.Path]] = []
    for entry in sorted(data_root.iterdir(), key=lambda item: item.name):
        if entry.name in {"assembly_data_report.jsonl", "dataset_catalog.json"}:
            continue
        if entry.is_symlink():
            raise MergeError(f"package data may not contain symlinks: {entry.name}")
        if not entry.is_dir():
            continue
        if ASSEMBLY_RE.fullmatch(entry.name) is None:
            raise MergeError(f"unexpected package data entry: {entry.name}")
        reports.append((entry.name, entry / "sequence_report.jsonl"))
    return reports


def validate_report(path: pathlib.Path, assembly: str, identities: set[tuple[str, str]]) -> int:
    raw = regular(path, f"{assembly}/sequence_report.jsonl").read_bytes()
    if not raw or not raw.endswith(b"\n") or b"\r" in raw:
        raise MergeError(f"{assembly}/sequence_report.jsonl must be LF-only with terminal LF")
    rows = 0
    observed_assembly = False
    for line_number, line in enumerate(raw.decode("utf-8").splitlines(), start=1):
        row = strict_object(line, f"{assembly}/sequence_report.jsonl line {line_number}")
        reported_assembly = report_field(row, "assembly_accession", "assemblyAccession")
        sequence = report_field(row, "refseq_accession", "refseqAccession")
        length = row.get("length")
        if reported_assembly != assembly:
            raise MergeError(
                f"{assembly}/sequence_report.jsonl line {line_number} has assembly {reported_assembly!r}"
            )
        if not isinstance(sequence, str) or SEQUENCE_RE.fullmatch(sequence) is None:
            raise MergeError(f"{assembly}/sequence_report.jsonl has invalid sequence at line {line_number}")
        if isinstance(length, bool) or not isinstance(length, int) or length < 1:
            raise MergeError(f"{assembly}/sequence_report.jsonl has invalid length at line {line_number}")
        identity = (assembly, sequence)
        if identity in identities:
            raise MergeError(f"duplicate sequence identity: {identity}")
        identities.add(identity)
        observed_assembly = True
        rows += 1
    if not observed_assembly:
        raise MergeError(f"{assembly}/sequence_report.jsonl has no sequence rows")
    return rows


def merge(args: argparse.Namespace) -> dict[str, Any]:
    data_root = require_directory(args.data_root, "package data root")
    assemblies = load_assemblies(args.assembly_report)
    expected = set(assemblies)
    if args.expected_assembly_count is not None and args.expected_assembly_count != len(assemblies):
        raise MergeError(
            f"assembly report count {len(assemblies)} != expected {args.expected_assembly_count}"
        )
    output = require_output(args.output, "merged sequence report")
    receipt_path = require_output(args.receipt, "merge receipt")
    sources = package_reports(data_root)
    observed = {assembly for assembly, _ in sources}
    missing = sorted(expected - observed)
    extra = sorted(observed - expected)
    if missing or extra:
        detail = []
        if missing:
            detail.append(f"missing={missing[:5]}")
        if extra:
            detail.append(f"extra={extra[:5]}")
        raise MergeError(
            "package sequence reports do not cover the assembly report exactly; " + "; ".join(detail)
        )

    identities: set[tuple[str, str]] = set()
    sequence_rows = 0
    descriptor, temporary_name = tempfile.mkstemp(prefix=".sequence_data_report.", dir=output.parent)
    os.close(descriptor)
    temporary = pathlib.Path(temporary_name)
    digest = hashlib.sha256()
    bytes_written = 0
    try:
        with temporary.open("wb") as target:
            for assembly, source in sources:
                raw = regular(source, f"{assembly}/sequence_report.jsonl").read_bytes()
                sequence_rows += validate_report(source, assembly, identities)
                target.write(raw)
                digest.update(raw)
                bytes_written += len(raw)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()

    receipt = {
        "schema_version": SCHEMA_VERSION,
        "status": "merged",
        "scientific_metrics_computed": False,
        "assembly_report_sha256": sha256_file(args.assembly_report),
        "assembly_count": len(assemblies),
        "source_files": len(sources),
        "sequence_count": sequence_rows,
        "sequence_report_bytes": bytes_written,
        "sequence_report_sha256": digest.hexdigest(),
        "sequence_report_path": output.name,
    }
    receipt_path.write_bytes((canonical_json(receipt) + "\n").encode("ascii"))
    if sha256_file(output) != receipt["sequence_report_sha256"]:
        raise MergeError("merged sequence report SHA-256 drifted during write")
    print(canonical_json(receipt))
    return receipt


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--data-root", required=True, type=pathlib.Path)
    result.add_argument("--assembly-report", required=True, type=pathlib.Path)
    result.add_argument("--output", required=True, type=pathlib.Path)
    result.add_argument("--receipt", required=True, type=pathlib.Path)
    result.add_argument("--expected-assembly-count", type=int)
    return result


def main() -> int:
    try:
        merge(parser().parse_args())
        return 0
    except (OSError, UnicodeError, ValueError, MergeError) as exc:
        print(canonical_json({"status": "error", "code": "U0_SEQUENCE_REPORT_MERGE_INVALID", "message": str(exc)}), file=sys.stderr)
        return EXIT_INVALID


if __name__ == "__main__":
    raise SystemExit(main())
