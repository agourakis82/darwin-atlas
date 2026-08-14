#!/usr/bin/env python3
"""Validate every U0 control claim against a rehydrated NCBI package.

The ledger is intentionally an exact binding, not a bag of evidence hashes:
each row names one versioned accession, its versioned assembly, one claim, one
asset kind, a normalized package-relative path, and the hash of those bytes.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import pathlib
import re
import stat
import sys
from typing import Any


EXIT_INVALID = 11
ACCESSION_RE = re.compile(r"^[A-Za-z]+_[0-9]+\.[0-9]+$")
ASSEMBLY_RE = re.compile(r"^GCF_[0-9]+\.[0-9]+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
FASTA_ALPHABET = frozenset("ACGTURYSWKMBDHVN")
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
EXPECTED_HEADER = (
    "sequence_accession_version",
    "assembly_accession_version",
    "control_category",
    "asset_kind",
    "package_path",
    "evidence_sha256",
)


class LedgerError(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalized_package_path(value: str, label: str) -> pathlib.PurePosixPath:
    candidate = pathlib.PurePosixPath(value)
    if (
        not value
        or "\\" in value
        or candidate.is_absolute()
        or candidate.as_posix() != value
        or any(part in {"", ".", ".."} for part in candidate.parts)
    ):
        raise LedgerError(f"INVALID_PACKAGE_PATH: {label}")
    return candidate


def require_directory(path: pathlib.Path, label: str) -> pathlib.Path:
    if path.is_symlink():
        raise LedgerError(f"SYMLINK_FORBIDDEN: {label}: {path}")
    if not path.is_dir():
        raise LedgerError(f"MISSING_DIRECTORY: {label}: {path}")
    return path.resolve(strict=True)


def package_asset(root: pathlib.Path, package_path: pathlib.PurePosixPath, label: str) -> pathlib.Path:
    candidate = root.joinpath(*package_path.parts)
    cursor = root
    for part in package_path.parts:
        cursor = cursor / part
        try:
            mode = cursor.lstat().st_mode
        except OSError as exc:
            raise LedgerError(f"MISSING_ASSET: {label}: {package_path.as_posix()}") from exc
        if stat.S_ISLNK(mode):
            raise LedgerError(f"SYMLINK_FORBIDDEN: {label}: {package_path.as_posix()}")
    if not candidate.is_file() or not stat.S_ISREG(candidate.stat().st_mode):
        raise LedgerError(f"MISSING_ASSET: {label}: {package_path.as_posix()}")
    try:
        candidate.resolve(strict=True).relative_to(root)
    except (OSError, ValueError) as exc:
        raise LedgerError(f"PATH_OUTSIDE_PACKAGE: {label}: {package_path.as_posix()}") from exc
    return candidate


def check_path_binding(package_path: pathlib.PurePosixPath, assembly: str, kind: str, label: str) -> None:
    parts = package_path.parts
    required_prefix = ("ncbi_dataset", "data", assembly)
    if parts[:3] != required_prefix:
        raise LedgerError(f"ASSEMBLY_PATH_MISMATCH: {label}: expected ncbi_dataset/data/{assembly}/...")
    name = parts[-1]
    valid_name = (
        kind == "fasta" and name.endswith(".fna")
        or kind == "gbff" and name.endswith(".gbff")
        or kind == "sequence_report" and name == "sequence_report.jsonl"
    )
    if not valid_name:
        raise LedgerError(f"ASSET_KIND_PATH_MISMATCH: {label}: {kind}: {name}")


def accession_tokens(text: str) -> set[str]:
    return {token for token in re.findall(r"[A-Za-z]+_[0-9]+\.[0-9]+", text) if ACCESSION_RE.fullmatch(token)}


def prove_fasta(path: pathlib.Path, accession: str, category: str) -> dict[str, Any]:
    matches: list[bool] = []
    current_matches = False
    current_has_ambiguity = False
    with path.open(encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, start=1):
            line = raw.rstrip("\r\n")
            if line.startswith(">"):
                if current_matches:
                    matches.append(current_has_ambiguity)
                tokens = accession_tokens(line[1:])
                if len(tokens) != 1:
                    raise LedgerError(f"INVALID_FASTA_HEADER: {path}:{line_no}")
                current_matches = next(iter(tokens)) == accession
                current_has_ambiguity = False
                continue
            if not current_matches:
                continue
            sequence = "".join(line.split()).upper()
            if not sequence or any(base not in FASTA_ALPHABET for base in sequence):
                raise LedgerError(f"INVALID_FASTA_SEQUENCE: {path}:{line_no}")
            current_has_ambiguity = current_has_ambiguity or any(base not in {"A", "C", "G", "T"} for base in sequence)
    if current_matches:
        matches.append(current_has_ambiguity)
    if len(matches) != 1:
        raise LedgerError(f"FASTA_ACCESSION_NOT_EXACTLY_ONCE: {accession}: {path}")
    observed = matches[0]
    expected = category == "ambiguity_present"
    if observed != expected:
        raise LedgerError(f"FASTA_AMBIGUITY_CLAIM_FALSE: {accession}: expected {category}")
    return {"semantic_proof": "fasta_ambiguity", "ambiguity_present": observed}


def prove_gbff(path: pathlib.Path, accession: str, category: str) -> dict[str, Any]:
    records: list[list[str]] = []
    current: list[str] = []
    with path.open(encoding="utf-8") as handle:
        for raw in handle:
            current.append(raw.rstrip("\r\n"))
            if raw.rstrip("\r\n") == "//":
                records.append(current)
                current = []
    if current:
        raise LedgerError(f"INVALID_GBFF_RECORD_TERMINATOR: {path}")
    topology: list[str] = []
    for record in records:
        version = [line.split()[1] for line in record if line.startswith("VERSION") and len(line.split()) >= 2]
        if accession not in version:
            continue
        loci = [line for line in record if line.startswith("LOCUS")]
        if len(loci) != 1:
            raise LedgerError(f"GBFF_LOCUS_MISSING: {accession}: {path}")
        words = set(loci[0].lower().split())
        observed = "circular" if "circular" in words else "linear" if "linear" in words else "unknown"
        topology.append(observed)
    if len(topology) != 1:
        raise LedgerError(f"GBFF_ACCESSION_NOT_EXACTLY_ONCE: {accession}: {path}")
    expected = category.removeprefix("topology_")
    if topology[0] != expected:
        raise LedgerError(f"GBFF_TOPOLOGY_CLAIM_FALSE: {accession}: expected {expected}, observed {topology[0]}")
    return {"semantic_proof": "gbff_topology", "declared_topology": topology[0]}


def classify_sequence(row: dict[str, Any]) -> str:
    fields = ("assigned_molecule_location_type", "chr_name", "sequence_name")
    values = [str(row.get(field, "")).strip().lower() for field in fields]
    if any("plasmid" in value for value in values):
        return "plasmid"
    if "chromosome" in values[0] or "chromosome" in values[1]:
        return "chromosome"
    return "other"


def prove_sequence_report(path: pathlib.Path, accession: str, assembly: str, category: str) -> dict[str, Any]:
    matches: list[str] = []
    with path.open(encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise LedgerError(f"INVALID_SEQUENCE_REPORT_JSON: {path}:{line_no}") from exc
            if not isinstance(row, dict):
                raise LedgerError(f"INVALID_SEQUENCE_REPORT_ROW: {path}:{line_no}")
            if row.get("refseq_accession") == accession:
                if row.get("assembly_accession") != assembly:
                    raise LedgerError(f"SEQUENCE_REPORT_ASSEMBLY_MISMATCH: {accession}: {path}:{line_no}")
                matches.append(classify_sequence(row))
    if len(matches) != 1:
        raise LedgerError(f"SEQUENCE_REPORT_ACCESSION_NOT_EXACTLY_ONCE: {accession}: {path}")
    expected = category.removeprefix("replicon_")
    if matches[0] != expected:
        raise LedgerError(f"SEQUENCE_REPORT_CLASS_CLAIM_FALSE: {accession}: expected {expected}, observed {matches[0]}")
    return {"semantic_proof": "sequence_report_replicon_class", "replicon_class": matches[0]}


def load_and_validate(controls: pathlib.Path, package_root: pathlib.Path) -> list[dict[str, Any]]:
    if controls.is_symlink():
        raise LedgerError(f"SYMLINK_FORBIDDEN: control ledger: {controls}")
    if not controls.is_file():
        raise LedgerError(f"MISSING_CONTROL_LEDGER: {controls}")
    rows: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    with controls.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != EXPECTED_HEADER:
            raise LedgerError("INVALID_CONTROL_LEDGER_HEADER: exact six-column order required")
        for line_no, raw in enumerate(reader, start=2):
            if set(raw) != set(EXPECTED_HEADER) or any(raw[key] is None for key in EXPECTED_HEADER):
                raise LedgerError(f"INVALID_CONTROL_LEDGER_ROW: {controls}:{line_no}")
            accession, assembly, category, kind, path_text, expected_hash = (raw[key] for key in EXPECTED_HEADER)
            label = f"{controls}:{line_no}"
            if not ACCESSION_RE.fullmatch(accession) or not ASSEMBLY_RE.fullmatch(assembly):
                raise LedgerError(f"INVALID_VERSIONED_BINDING: {label}")
            if category not in REQUIRED_CONTROLS or kind != EXPECTED_KIND.get(category):
                raise LedgerError(f"INVALID_CATEGORY_ASSET_BINDING: {label}")
            if not SHA256_RE.fullmatch(expected_hash):
                raise LedgerError(f"INVALID_EVIDENCE_SHA256: {label}")
            identity = (accession, category)
            if identity in seen:
                raise LedgerError(f"DUPLICATE_CONTROL_CLAIM: {accession}:{category}")
            seen.add(identity)
            package_path = normalized_package_path(path_text, label)
            check_path_binding(package_path, assembly, kind, label)
            asset = package_asset(package_root, package_path, label)
            actual_hash = sha256_file(asset)
            if actual_hash != expected_hash:
                raise LedgerError(f"EVIDENCE_SHA256_MISMATCH: {label}: {path_text}")
            proof = (
                prove_gbff(asset, accession, category) if kind == "gbff"
                else prove_fasta(asset, accession, category) if kind == "fasta"
                else prove_sequence_report(asset, accession, assembly, category)
            )
            rows.append({
                "sequence_accession_version": accession,
                "assembly_accession_version": assembly,
                "control_category": category,
                "asset_kind": kind,
                "package_path": path_text,
                "evidence_sha256": expected_hash,
                **proof,
            })
    observed = {row["control_category"] for row in rows}
    missing = sorted(REQUIRED_CONTROLS - observed)
    if missing:
        raise LedgerError("CONTROL_LEDGER_INCOMPLETE: " + ",".join(missing))
    return sorted(rows, key=lambda row: (row["control_category"], row["sequence_accession_version"]))


def validate(args: argparse.Namespace) -> dict[str, Any]:
    package_root = require_directory(args.package_root, "package root")
    if args.output.exists():
        raise LedgerError(f"REFUSE_OVERWRITE: receipt output: {args.output}")
    receipt_root = args.output.parent.resolve(strict=True)
    try:
        controls_path = args.controls.resolve(strict=True).relative_to(receipt_root).as_posix()
        package_path = package_root.relative_to(receipt_root).as_posix()
    except (OSError, ValueError) as exc:
        raise LedgerError("RECEIPT_INPUT_OUTSIDE_ROOT: controls and package must be below receipt output directory") from exc
    rows = load_and_validate(args.controls, package_root)
    receipt = {
        "schema_version": "dosa-u0-control-ledger-receipt-1",
        "status": "validated",
        "control_ledger_path": controls_path,
        "control_ledger_sha256": sha256_file(args.controls),
        "package_root": package_path,
        "required_categories": sorted(REQUIRED_CONTROLS),
        "controls": rows,
        "scientific_metrics_computed": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(canonical_json(receipt) + "\n", encoding="utf-8", newline="\n")
    return {
        "status": "validated",
        "controls": len(rows),
        "receipt": str(args.output),
        "receipt_sha256": sha256_file(args.output),
        "control_ledger_sha256": receipt["control_ledger_sha256"],
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--controls", required=True, type=pathlib.Path)
    result.add_argument("--package-root", required=True, type=pathlib.Path)
    result.add_argument("--output", required=True, type=pathlib.Path)
    return result


def main() -> int:
    try:
        print(canonical_json(validate(parser().parse_args())))
        return 0
    except (OSError, LedgerError) as exc:
        print(canonical_json({"status": "error", "code": "U0_CONTROL_LEDGER_INVALID", "message": str(exc)}), file=sys.stderr)
        return EXIT_INVALID


if __name__ == "__main__":
    raise SystemExit(main())
