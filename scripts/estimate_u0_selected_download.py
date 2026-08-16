#!/usr/bin/env python3
"""Estimate selected U0 genome-package bytes from a dehydrated dataset catalog.

This is a pre-download routing check. It never fetches FASTA/GBFF bytes and
never computes DOSA metrics. Missing FASTA or GBFF sizes fail closed so the
estimate cannot understate the pending snapshot.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
from typing import Any


EXIT_INVALID = 11
ASSEMBLY_RE = re.compile(r"^GCF_[0-9]+\.[0-9]+$")
SCHEMA_VERSION = "dosa-v3-u0-selected-download-estimate-1"
POLICY_LIMIT_BYTES = 200 * 1024 * 1024 * 1024
REQUIRED_TYPES = ("GENOMIC_NUCLEOTIDE_FASTA", "GENBANK_FLAT_FILE")
OPTIONAL_TYPES = ("SEQUENCE_REPORT",)


class EstimateError(RuntimeError):
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
            raise EstimateError(f"{label} path may not contain symlinks")


def regular(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink(path, label)
    if path.is_symlink() or not path.is_file():
        raise EstimateError(f"{label} must be a regular non-symlink file")
    return path.resolve(strict=True)


def require_output(path: pathlib.Path, label: str) -> pathlib.Path:
    if path.exists() or path.is_symlink():
        raise EstimateError(f"refusing to overwrite {label}: {path}")
    reject_symlink(path.parent, f"{label} parent")
    if not path.parent.is_dir():
        raise EstimateError(f"{label} parent must be a real directory")
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
        raise EstimateError(f"{label} is not strict JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise EstimateError(f"{label} must be a JSON object")
    return value


def parse_size(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise EstimateError(f"{label} has invalid uncompressedLengthBytes")
    try:
        size = int(value)
    except (TypeError, ValueError) as exc:
        raise EstimateError(f"{label} has invalid uncompressedLengthBytes") from exc
    if size < 0:
        raise EstimateError(f"{label} has negative uncompressedLengthBytes")
    return size


def load_selection(path: pathlib.Path) -> tuple[set[str], int]:
    raw = regular(path, "selection").read_bytes()
    if not raw or not raw.endswith(b"\n") or b"\r" in raw:
        raise EstimateError("selection must be LF-only with terminal LF")
    assemblies: set[str] = set()
    replicons = 0
    for line_number, line in enumerate(raw.decode("utf-8").splitlines(), start=1):
        row = strict_object(line, f"selection line {line_number}")
        assembly = row.get("assembly_accession_version")
        if not isinstance(assembly, str) or ASSEMBLY_RE.fullmatch(assembly) is None:
            raise EstimateError(f"selection line {line_number} has invalid assembly")
        assemblies.add(assembly)
        replicons += 1
    if not assemblies:
        raise EstimateError("selection is empty")
    return assemblies, replicons


def load_catalog(path: pathlib.Path) -> dict[str, dict[str, dict[str, Any]]]:
    raw = regular(path, "dataset catalog").read_text(encoding="utf-8")
    catalog = strict_object(raw, "dataset catalog")
    rows = catalog.get("assemblies")
    if not isinstance(rows, list) or not rows:
        raise EstimateError("dataset catalog has no assemblies")
    result: dict[str, dict[str, dict[str, Any]]] = {}
    for index, item in enumerate(rows):
        if not isinstance(item, dict):
            raise EstimateError(f"dataset catalog assembly {index} is not an object")
        accession = item.get("accession")
        if accession is None:
            continue
        if not isinstance(accession, str) or ASSEMBLY_RE.fullmatch(accession) is None:
            raise EstimateError(f"dataset catalog has invalid accession: {accession!r}")
        files = item.get("files")
        if not isinstance(files, list):
            raise EstimateError(f"dataset catalog {accession} has invalid files")
        by_type: dict[str, dict[str, Any]] = {}
        for file_index, file_row in enumerate(files):
            if not isinstance(file_row, dict):
                raise EstimateError(f"dataset catalog {accession} file {file_index} is not an object")
            file_type = file_row.get("fileType")
            if not isinstance(file_type, str) or not file_type:
                raise EstimateError(f"dataset catalog {accession} file {file_index} has no fileType")
            if file_type in by_type:
                raise EstimateError(f"dataset catalog {accession} has duplicate fileType {file_type}")
            by_type[file_type] = file_row
        if accession in result:
            raise EstimateError(f"dataset catalog has duplicate accession: {accession}")
        result[accession] = by_type
    if not result:
        raise EstimateError("dataset catalog has no assembly accessions")
    return result


def estimate(args: argparse.Namespace) -> dict[str, Any]:
    output = require_output(args.output, "estimate receipt")
    selected, replicons = load_selection(args.selection)
    catalog = load_catalog(args.catalog)
    missing = sorted(selected - set(catalog))
    if missing:
        raise EstimateError(f"catalog missing selected assemblies; first={missing[:5]}")

    bytes_by_type = {file_type: 0 for file_type in (*REQUIRED_TYPES, *OPTIONAL_TYPES)}
    missing_optional_sizes: list[str] = []
    for assembly in sorted(selected):
        files = catalog[assembly]
        for file_type in REQUIRED_TYPES:
            row = files.get(file_type)
            if row is None:
                raise EstimateError(f"catalog {assembly} is missing {file_type}")
            size = row.get("uncompressedLengthBytes")
            if size is None:
                raise EstimateError(f"catalog {assembly} {file_type} has no uncompressedLengthBytes")
            bytes_by_type[file_type] += parse_size(size, f"{assembly} {file_type}")
        for file_type in OPTIONAL_TYPES:
            row = files.get(file_type)
            if row is None:
                raise EstimateError(f"catalog {assembly} is missing {file_type}")
            size = row.get("uncompressedLengthBytes")
            if size is None:
                missing_optional_sizes.append(f"{assembly}:{file_type}")
                continue
            bytes_by_type[file_type] += parse_size(size, f"{assembly} {file_type}")

    estimated = sum(bytes_by_type.values())
    receipt = {
        "schema_version": SCHEMA_VERSION,
        "status": "estimated",
        "scientific_metrics_computed": False,
        "selection_sha256": sha256_file(args.selection),
        "catalog_sha256": sha256_file(args.catalog),
        "selected_assemblies": len(selected),
        "selected_replicons": replicons,
        "estimated_uncompressed_bytes": estimated,
        "fasta_uncompressed_bytes": bytes_by_type["GENOMIC_NUCLEOTIDE_FASTA"],
        "gbff_uncompressed_bytes": bytes_by_type["GENBANK_FLAT_FILE"],
        "sequence_report_uncompressed_bytes": bytes_by_type["SEQUENCE_REPORT"],
        "sequence_report_sizes_missing": len(missing_optional_sizes),
        "policy_limit_bytes": POLICY_LIMIT_BYTES,
        "within_policy": estimated <= POLICY_LIMIT_BYTES,
    }
    output.write_bytes((canonical_json(receipt) + "\n").encode("ascii"))
    print(canonical_json(receipt))
    return receipt


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--selection", required=True, type=pathlib.Path)
    result.add_argument("--catalog", required=True, type=pathlib.Path)
    result.add_argument("--output", required=True, type=pathlib.Path)
    return result


def main() -> int:
    try:
        estimate(parser().parse_args())
        return 0
    except (OSError, UnicodeError, ValueError, EstimateError) as exc:
        print(canonical_json({"status": "error", "code": "U0_DOWNLOAD_ESTIMATE_INVALID", "message": str(exc)}), file=sys.stderr)
        return EXIT_INVALID


if __name__ == "__main__":
    raise SystemExit(main())
