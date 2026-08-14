#!/usr/bin/env python3
"""Select the DOSA U0 replicon pilot from frozen NCBI Datasets reports.

This is acquisition/routing code, not a scientific-metric implementation.
The selected set is the deterministic union of the SHA-256 sample, the 100
largest replicons, and explicit control declarations.  A three-column control
candidate file is sufficient only to include the named accessions in the
download.  It does not prove topology, ambiguity, or replicon class.  Those
claims are bound to downloaded FASTA/GBFF/sequence-report bytes in a separate
post-download ledger and semantic-validation receipt.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import re
import sys
from dataclasses import dataclass
from typing import Any, Iterable


EXIT_INVALID = 11
ACCESSION_RE = re.compile(r"^[A-Z][A-Z0-9_]*\.[0-9]+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ASSET_KINDS = frozenset({"fasta", "gbff", "sequence_report"})
CONTROL_CANDIDATE_HEADER = (
    "sequence_accession_version",
    "assembly_accession_version",
    "control_category",
)
CONTROL_LEDGER_HEADER = CONTROL_CANDIDATE_HEADER + (
    "asset_kind",
    "package_path",
    "evidence_sha256",
)
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


class SelectionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Replicon:
    accession: str
    assembly: str
    length_bp: int
    replicon_class: str
    taxid: int | None
    organism_name: str | None


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def json_lines(path: pathlib.Path) -> Iterable[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SelectionError(f"{path}:{number}: invalid JSON: {exc}") from exc
            if not isinstance(value, dict):
                raise SelectionError(f"{path}:{number}: expected a JSON object")
            yield value


def load_assemblies(path: pathlib.Path) -> dict[str, tuple[int | None, str | None]]:
    result: dict[str, tuple[int | None, str | None]] = {}
    for row in json_lines(path):
        accession = row.get("accession") or row.get("current_accession")
        if not isinstance(accession, str) or not ACCESSION_RE.fullmatch(accession):
            raise SelectionError(f"assembly report has invalid accession: {accession!r}")
        organism = row.get("organism") or {}
        taxid = organism.get("tax_id")
        name = organism.get("organism_name")
        value = (int(taxid) if taxid is not None else None, str(name) if name is not None else None)
        if accession in result and result[accession] != value:
            raise SelectionError(f"conflicting duplicate assembly row: {accession}")
        result[accession] = value
    if not result:
        raise SelectionError("assembly report is empty")
    return result


def classify_sequence(row: dict[str, Any]) -> str:
    location = str(row.get("assigned_molecule_location_type", "")).strip().lower()
    name = str(row.get("chr_name", "")).strip().lower()
    sequence_name = str(row.get("sequence_name", "")).strip().lower()
    if "plasmid" in location or "plasmid" in name or "plasmid" in sequence_name:
        return "plasmid"
    if "chromosome" in location or "chromosome" in name:
        return "chromosome"
    return "other"


def load_replicons(path: pathlib.Path, assemblies: dict[str, tuple[int | None, str | None]]) -> dict[str, Replicon]:
    result: dict[str, Replicon] = {}
    for row in json_lines(path):
        accession = row.get("refseq_accession")
        assembly = row.get("assembly_accession")
        if not isinstance(accession, str) or not ACCESSION_RE.fullmatch(accession):
            raise SelectionError(f"sequence report has invalid RefSeq accession: {accession!r}")
        if not isinstance(assembly, str) or assembly not in assemblies:
            raise SelectionError(f"sequence {accession} references absent assembly {assembly!r}")
        try:
            length_bp = int(row["length"])
        except (KeyError, TypeError, ValueError) as exc:
            raise SelectionError(f"sequence {accession} has invalid length") from exc
        if length_bp < 1:
            raise SelectionError(f"sequence {accession} has non-positive length")
        taxid, organism_name = assemblies[assembly]
        value = Replicon(accession, assembly, length_bp, classify_sequence(row), taxid, organism_name)
        if accession in result and result[accession] != value:
            raise SelectionError(f"conflicting duplicate sequence row: {accession}")
        result[accession] = value
    if not result:
        raise SelectionError("sequence report is empty")
    return result


def normalized_package_path(value: str, *, label: str) -> str:
    """Accept only a normalized, portable path relative to a package root."""
    candidate = pathlib.PurePosixPath(value)
    if (
        not value
        or "\\" in value
        or candidate.is_absolute()
        or any(part in {"", ".", ".."} for part in candidate.parts)
        or candidate.as_posix() != value
    ):
        raise SelectionError(f"{label} must be a normalized package-relative path")
    return value


def validate_control_identity(
    *,
    path: pathlib.Path,
    number: int,
    accession: str,
    assembly: str,
    category: str,
    replicons: dict[str, Replicon],
) -> None:
    if accession not in replicons:
        raise SelectionError(f"{path}:{number}: control accession absent from sequence report: {accession}")
    if assembly != replicons[accession].assembly:
        raise SelectionError(f"{path}:{number}: control assembly does not bind accession: {accession}")
    if category not in REQUIRED_CONTROLS:
        raise SelectionError(f"{path}:{number}: unknown control category: {category}")


def require_control_input_file(path: pathlib.Path, label: str) -> None:
    if path.is_symlink():
        raise SelectionError(f"{label} must not be a symlink: {path}")
    if not path.is_file():
        raise SelectionError(f"{label} is missing or not a regular file: {path}")


def require_complete_controls(controls: dict[str, set[str]], label: str) -> None:
    observed = {category for values in controls.values() for category in values}
    missing = sorted(REQUIRED_CONTROLS - observed)
    if missing:
        raise SelectionError(f"{label} is incomplete: " + ",".join(missing))


def load_control_candidates(path: pathlib.Path, replicons: dict[str, Replicon]) -> dict[str, set[str]]:
    require_control_input_file(path, "control candidate file")
    controls: dict[str, set[str]] = {}
    seen: set[tuple[str, str]] = set()
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != CONTROL_CANDIDATE_HEADER:
            raise SelectionError(f"control candidate header must be exactly: {list(CONTROL_CANDIDATE_HEADER)}")
        for number, row in enumerate(reader, start=2):
            if set(row) != set(CONTROL_CANDIDATE_HEADER) or any(row[key] is None for key in CONTROL_CANDIDATE_HEADER):
                raise SelectionError(f"{path}:{number}: invalid control candidate row")
            accession, assembly, category = (row[key] for key in CONTROL_CANDIDATE_HEADER)
            validate_control_identity(
                path=path,
                number=number,
                accession=accession,
                assembly=assembly,
                category=category,
                replicons=replicons,
            )
            identity = (accession, category)
            if identity in seen:
                raise SelectionError(f"{path}:{number}: duplicate control candidate: {accession}:{category}")
            seen.add(identity)
            controls.setdefault(accession, set()).add(category)
    require_complete_controls(controls, "control candidate file")
    return controls


def load_controls(path: pathlib.Path, replicons: dict[str, Replicon]) -> dict[str, set[str]]:
    require_control_input_file(path, "control ledger")
    controls: dict[str, set[str]] = {}
    seen: set[tuple[str, str]] = set()
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != CONTROL_LEDGER_HEADER:
            raise SelectionError(f"control ledger header must be exactly: {list(CONTROL_LEDGER_HEADER)}")
        for number, row in enumerate(reader, start=2):
            if set(row) != set(CONTROL_LEDGER_HEADER) or any(row[key] is None for key in CONTROL_LEDGER_HEADER):
                raise SelectionError(f"{path}:{number}: invalid control ledger row")
            accession = row["sequence_accession_version"]
            assembly = row["assembly_accession_version"]
            category = row["control_category"]
            asset_kind = row["asset_kind"]
            package_path = row["package_path"]
            evidence = row["evidence_sha256"]
            validate_control_identity(
                path=path,
                number=number,
                accession=accession,
                assembly=assembly,
                category=category,
                replicons=replicons,
            )
            identity = (accession, category)
            if identity in seen:
                raise SelectionError(f"{path}:{number}: duplicate control claim: {accession}:{category}")
            seen.add(identity)
            expected_kind = (
                "gbff" if category.startswith("topology_")
                else "fasta" if category.startswith("ambiguity_")
                else "sequence_report"
            )
            if asset_kind not in ASSET_KINDS or asset_kind != expected_kind:
                raise SelectionError(f"{path}:{number}: control category requires asset_kind={expected_kind}")
            normalized_package_path(package_path, label=f"{path}:{number}: package_path")
            if not SHA256_RE.fullmatch(evidence):
                raise SelectionError(f"{path}:{number}: evidence_sha256 must be lowercase SHA-256")
            controls.setdefault(accession, set()).add(category)
    require_complete_controls(controls, "control ledger")
    return controls


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def select(args: argparse.Namespace) -> dict[str, Any]:
    assemblies = load_assemblies(args.assemblies)
    replicons = load_replicons(args.sequences, assemblies)
    if args.control_candidates is not None:
        controls = load_control_candidates(args.control_candidates, replicons)
        control_input_kind = "unverified_candidates"
    else:
        controls = load_controls(args.controls, replicons)
        control_input_kind = "declared_asset_ledger"
    reasons: dict[str, set[str]] = {}
    for accession in replicons:
        digest = hashlib.sha256(accession.encode("ascii")).digest()
        if int.from_bytes(digest, "big") % 256 == 0:
            reasons.setdefault(accession, set()).add("sha256_mod_256_zero")
    largest = sorted(replicons.values(), key=lambda row: (-row.length_bp, row.accession))[: args.largest]
    if len(largest) != args.largest:
        raise SelectionError(f"requested {args.largest} largest replicons but source has only {len(replicons)}")
    for row in largest:
        reasons.setdefault(row.accession, set()).add("largest_replicon")
    for accession, categories in controls.items():
        reasons.setdefault(accession, set()).add("explicit_control")
        for category in categories:
            reasons[accession].add(f"control:{category}")

    assembly_sha = sha256_file(args.assemblies)
    sequence_sha = sha256_file(args.sequences)
    rows: list[dict[str, Any]] = []
    for accession in sorted(reasons):
        replicon = replicons[accession]
        accession_sha = hashlib.sha256(accession.encode("ascii")).hexdigest()
        rows.append(
            {
                "schema_version": "dosa-u0-pilot-selection-1",
                "sequence_accession_version": accession,
                "assembly_accession_version": replicon.assembly,
                "length_bp": replicon.length_bp,
                "replicon_class": replicon.replicon_class,
                "taxid": replicon.taxid,
                "organism_name": replicon.organism_name,
                "accession_sha256": accession_sha,
                "sha256_bucket": accession_sha[:2],
                "selection_reasons": sorted(reasons[accession]),
                "assembly_report_sha256": assembly_sha,
                "sequence_report_sha256": sequence_sha,
            }
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        raise SelectionError(f"refusing to overwrite output: {args.output}")
    with args.output.open("x", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(canonical_json(row) + "\n")
    summary = {
        "status": "selected",
        "records": len(rows),
        "assemblies": len({row["assembly_accession_version"] for row in rows}),
        "sha256_sample_records": sum("sha256_mod_256_zero" in row["selection_reasons"] for row in rows),
        "largest_requested": args.largest,
        "control_candidates_declared_complete": True,
        # Both accepted control-input modes are declarations only at this
        # stage. Semantic proof requires the separate offline review or the
        # final package validator; never infer it from candidate coverage.
        "control_claims_semantically_validated": False,
        "control_ledger_validated": False,
        "control_input_kind": control_input_kind,
        "output": str(args.output),
        "output_sha256": sha256_file(args.output),
        "assembly_report_sha256": assembly_sha,
        "sequence_report_sha256": sequence_sha,
    }
    return summary


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--assemblies", required=True, type=pathlib.Path)
    result.add_argument("--sequences", required=True, type=pathlib.Path)
    controls = result.add_mutually_exclusive_group(required=True)
    controls.add_argument("--controls", type=pathlib.Path, help="six-column post-download asset ledger")
    controls.add_argument(
        "--control-candidates",
        type=pathlib.Path,
        help="three-column pre-download inclusion declarations; never semantic evidence",
    )
    result.add_argument("--output", required=True, type=pathlib.Path)
    result.add_argument("--largest", type=int, default=100)
    return result


def main() -> int:
    args = parser().parse_args()
    if args.largest < 1:
        print(canonical_json({"status": "error", "code": "U0_SELECTION_INVALID", "message": "--largest must be positive"}))
        return EXIT_INVALID
    try:
        print(canonical_json(select(args)))
        return 0
    except (OSError, SelectionError) as exc:
        print(canonical_json({"status": "error", "code": "U0_SELECTION_INVALID", "message": str(exc)}))
        return EXIT_INVALID


if __name__ == "__main__":
    raise SystemExit(main())
