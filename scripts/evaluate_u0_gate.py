#!/usr/bin/env python3
"""Validate DOSA v3 U0 evidence under an explicit fail-closed promotion lock.

Fixtures exercise structural and threshold checks but can never emit PASS.
Real-scope adjudication is also locked until the canonical producer, integral
validator and held-out derivation closure are implemented; deeper validators
below are development scaffolding, not an enabled scientific admission path.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import pathlib
import re
import runpy
import stat
import subprocess
import sys
import tempfile
from collections import Counter
from fractions import Fraction
from typing import Any
from urllib.parse import urljoin, urlparse


EXIT_BLOCKED = 2
GIB = 1024**3
HEX64 = re.compile(r"[0-9a-f]{64}")
ACCESSION_VERSION = re.compile(r"[A-Za-z]+_[0-9]+\.[0-9]+")
ALLOWED_SCALES = {"16", "100", "500", "1000"}
PUBLIC_TABLES = {
    "runs.parquet", "replicons.parquet", "window_operator_profiles.parquet",
    "replicon_operator_summary.parquet", "excluded_records.parquet",
}
PRIVATE_MARKERS = ("/users/", "/home/", "/private/", "localhost", ".local", "proxmox", "cluster")
ROOT = pathlib.Path(__file__).resolve().parents[1]
ORIC_EVALUATOR = ROOT / "julia" / "scripts" / "evaluate_oric_terminus_gate.jl"
MODEL_EVALUATOR = ROOT / "julia" / "scripts" / "evaluate_rc_equivariance_benchmark.jl"
U0_SOUNIO_EXECUTOR = ROOT / "sounio" / "src" / "u0_pilot_executor.sio"
U0_JULIA_FULL_VALIDATOR = ROOT / "julia" / "scripts" / "validate_u0_pilot.jl"
# These roles are intentionally not part of PILOT_PROVENANCE_ROLES yet.  Their
# absence is an explicit promotion lock: a held-out PASS is not admissible
# until the frozen cohort/split/ground-truth and prediction derivations are
# hash-closed by the real-pilot provenance contract.
U0_SCIENTIFIC_DERIVATION_ROLES = frozenset(
    {
        "scientific_cohort_manifest",
        "scientific_split_manifest",
        "oric_ground_truth",
        "oric_derivation_receipt",
        "model_injection_manifest",
        "model_derivation_receipt",
    }
)
PILOT_PROVENANCE_ROLES = frozenset(
    {
        "agreement",
        "query",
        "speed",
        "capacity",
        "field_audit",
        "oric",
        "model",
        "oric_input",
        "model_input",
        "parameters",
        "source_manifest",
        "source_integrity",
        "source_index",
        "payload_manifest",
        "sounio_attestation",
        "sounio_build_receipt",
        "sounio_execution_receipt",
        "sounio_output_manifest",
        "julia_receipt",
        "selection",
        "control_candidates",
        "control_ledger",
        "control_binding_receipt",
        "control_validation_receipt",
        "source_freeze_receipt",
        "assembly_report",
        "sequence_report",
        "full_replicon_inventory",
        "work_unit_manifest",
    }
)


class GateError(RuntimeError):
    pass


def u0_promotion_blockers() -> tuple[str, ...]:
    """Return every known contract gap that forbids real-U0 promotion."""
    blockers: list[str] = []
    if not U0_SOUNIO_EXECUTOR.is_file():
        blockers.append("CANONICAL_SOUNIO_U0_EXECUTOR_NOT_IMPLEMENTED")
    if not U0_JULIA_FULL_VALIDATOR.is_file():
        blockers.append("INDEPENDENT_JULIA_FULL_VALIDATOR_NOT_IMPLEMENTED")
    missing_derivation_roles = sorted(U0_SCIENTIFIC_DERIVATION_ROLES - PILOT_PROVENANCE_ROLES)
    if missing_derivation_roles:
        blockers.append(
            "HELD_OUT_SCIENTIFIC_DERIVATION_PROVENANCE_NOT_IMPLEMENTED["
            + ",".join(missing_derivation_roles)
            + "]"
        )
    return tuple(blockers)


def enforce_u0_promotion_lock() -> None:
    blockers = u0_promotion_blockers()
    if blockers:
        raise GateError("U0_PROMOTION_LOCKED: " + ";".join(blockers))


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: pathlib.Path) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise GateError(f"cannot read evidence JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise GateError(f"evidence must be a JSON object: {path}")
    return value


def read_json_object_bytes(raw: bytes, name: str) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(raw, object_pairs_hook=reject_duplicates)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise GateError(f"invalid JSON object in {name}: {exc}") from exc
    if not isinstance(value, dict):
        raise GateError(f"{name} must contain a JSON object")
    return value


def window_row_validator() -> Any:
    try:
        from importlib.metadata import version
        from jsonschema import Draft202012Validator, FormatChecker  # type: ignore
        from referencing import Registry, Resource  # type: ignore
    except (ImportError, ModuleNotFoundError) as exc:
        raise GateError("real U0 logical-row validation requires jsonschema==4.26.0") from exc
    if version("jsonschema") != "4.26.0":
        raise GateError(f"real U0 logical-row validation requires jsonschema==4.26.0, found {version('jsonschema')!r}")
    common = read_json(ROOT / "schemas" / "dosa_v3_common.schema.json")
    window = read_json(ROOT / "schemas" / "dosa_v3_window_profile.schema.json")
    registry = Registry()
    for schema in (common, window):
        identifier = schema.get("$id")
        if not isinstance(identifier, str):
            raise GateError("v3 row schema lacks an absolute $id")
        resource = Resource.from_contents(schema)
        registry = registry.with_resource(identifier, resource)
        registry = registry.with_resource(identifier.rsplit("/", 1)[-1], resource)
    Draft202012Validator.check_schema(window)
    return Draft202012Validator(window, registry=registry, format_checker=FormatChecker())


def exact_fraction(value: Any, name: str) -> Fraction:
    if not isinstance(value, dict) or set(value) != {"numerator", "denominator"}:
        raise GateError(f"{name} must be an exact fraction")
    numerator = nonnegative_integer(value.get("numerator"), f"{name}.numerator")
    denominator = positive_integer(value.get("denominator"), f"{name}.denominator")
    return Fraction(numerator, denominator)


def validate_window_row_invariants(row: dict[str, Any], name: str) -> None:
    size = positive_integer(row.get("window_size"), f"{name}.window_size")
    index = nonnegative_integer(row.get("window_index"), f"{name}.window_index")
    start = nonnegative_integer(row.get("window_start"), f"{name}.window_start")
    end = positive_integer(row.get("window_end"), f"{name}.window_end")
    if end - start != size or start != index * size:
        raise GateError(f"{name} violates the fixed non-overlapping window coordinate contract")
    kmer_r = row.get("kmer_r")
    kmer_rc = row.get("kmer_rc")
    if not isinstance(kmer_r, list) or [item.get("k") for item in kmer_r if isinstance(item, dict)] != list(range(2, 9)):
        raise GateError(f"{name}.kmer_r must be ordered k=2..8")
    if not isinstance(kmer_rc, list) or [item.get("k") for item in kmer_rc if isinstance(item, dict)] != list(range(1, 9)):
        raise GateError(f"{name}.kmer_rc must be ordered k=1..8")
    observations = [("positional_r", row.get("positional_r")), ("positional_rc", row.get("positional_rc"))]
    observations.extend((f"kmer_r[{index}]", value) for index, value in enumerate(kmer_r))
    observations.extend((f"kmer_rc[{index}]", value) for index, value in enumerate(kmer_rc))
    for field, observation in observations:
        if not isinstance(observation, dict):
            raise GateError(f"{name}.{field} must be an observation object")
        effective = nonnegative_integer(observation.get("effective_count"), f"{name}.{field}.effective_count")
        null = observation.get("null_summary")
        if not isinstance(null, dict):
            raise GateError(f"{name}.{field}.null_summary must be an object")
        reason = observation.get("reason_code")
        if reason is None:
            observed = observation.get("observed")
            exact_fraction(observed, f"{name}.{field}.observed")
            if observed["denominator"] != effective:
                raise GateError(f"{name}.{field} observed denominator must equal effective_count")
            require_value(null.get("n"), 1000, f"{name}.{field}.null_summary.n")
            tails = sum(
                nonnegative_integer(null.get(key), f"{name}.{field}.null_summary.{key}")
                for key in ("tail_lt", "tail_eq", "tail_gt")
            )
            if tails != 1000:
                raise GateError(f"{name}.{field} null tail counts must sum to 1000")
            q025 = exact_fraction(null.get("q025"), f"{name}.{field}.null_summary.q025")
            q500 = exact_fraction(null.get("q500"), f"{name}.{field}.null_summary.q500")
            q975 = exact_fraction(null.get("q975"), f"{name}.{field}.null_summary.q975")
            if not q025 <= q500 <= q975:
                raise GateError(f"{name}.{field} null quantiles are not ordered")
        else:
            require_value(observation.get("observed"), None, f"{name}.{field}.observed")
            require_value(null.get("n"), 0, f"{name}.{field}.null_summary.n")


def positive_number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
        raise GateError(f"{name} must be a positive number")
    return float(value)


def finite_number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise GateError(f"{name} must be a finite number")
    return float(value)


def nonnegative_integer(value: Any, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise GateError(f"{name} must be a non-negative integer")
    return value


def positive_integer(value: Any, name: str) -> int:
    result = nonnegative_integer(value, name)
    if result < 1:
        raise GateError(f"{name} must be a positive integer")
    return result


def require_value(value: Any, expected: Any, name: str) -> None:
    if value != expected:
        raise GateError(f"{name} must be exactly {expected!r}")


def require_sha(value: Any, name: str) -> str:
    if not isinstance(value, str) or HEX64.fullmatch(value) is None:
        raise GateError(f"{name} must be a lowercase SHA-256")
    return value


def require_scope(report: dict[str, Any], name: str, allowed: set[str]) -> str:
    scope = report.get("evidence_scope")
    if scope not in allowed:
        raise GateError(f"{name}.evidence_scope must be one of {sorted(allowed)}")
    return str(scope)


def require_accession(value: Any, name: str) -> str:
    if not isinstance(value, str) or ACCESSION_VERSION.fullmatch(value) is None:
        raise GateError(f"{name} must be an accession.version")
    return value


def require_coordinate(value: Any, name: str) -> tuple[int, int]:
    if not isinstance(value, dict) or set(value) != {"start", "end", "convention"}:
        raise GateError(f"{name} must be an exact coordinate object")
    start = nonnegative_integer(value.get("start"), f"{name}.start")
    end = positive_integer(value.get("end"), f"{name}.end")
    require_value(value.get("convention"), "zero_based_half_open", f"{name}.convention")
    if end <= start:
        raise GateError(f"{name}.end must be greater than start")
    return start, end


def require_scale(value: Any, name: str) -> str:
    scale = str(value)
    if isinstance(value, bool) or scale not in ALLOWED_SCALES:
        raise GateError(f"{name} must be one of {sorted(ALLOWED_SCALES)}")
    return scale


def require_public_https(value: Any, name: str) -> str:
    if not isinstance(value, str):
        raise GateError(f"{name} must be a public HTTPS URL")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise GateError(f"{name} must be a public HTTPS URL")
    if any(marker in value.lower() for marker in PRIVATE_MARKERS):
        raise GateError(f"{name} contains a private or cluster marker")
    return value


def require_public_locator(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value or any(marker in value.lower() for marker in PRIVATE_MARKERS):
        raise GateError(f"{name} must be a public HTTPS or normalized relative locator")
    if value.startswith("https://"):
        return require_public_https(value, name)
    path = pathlib.PurePosixPath(value)
    if path.is_absolute() or path.as_posix() != value or any(part in ("", ".", "..") for part in path.parts):
        raise GateError(f"{name} must be a normalized relative POSIX locator")
    return value


def check_inputs(paths: dict[str, pathlib.Path]) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    reports: dict[str, dict[str, Any]] = {}
    bindings: list[dict[str, Any]] = []
    for name, path in sorted(paths.items()):
        if path.is_symlink() or not path.is_file():
            raise GateError(f"evidence must be a regular non-symlink file: {name}")
        reports[name] = read_json(path)
        bindings.append({"role": name, "name": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    return reports, bindings


def normalized_relative_path(value: Any, name: str) -> pathlib.PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value:
        raise GateError(f"{name} must be a normalized relative POSIX path")
    candidate = pathlib.PurePosixPath(value)
    if candidate.is_absolute() or candidate.as_posix() != value or any(part in ("", ".", "..") for part in candidate.parts):
        raise GateError(f"{name} must be a normalized relative POSIX path")
    return candidate


def regular_file_below(root: pathlib.Path, relative: pathlib.PurePosixPath, name: str) -> pathlib.Path:
    candidate = root.joinpath(*relative.parts)
    cursor = root
    for part in relative.parts:
        cursor = cursor / part
        try:
            mode = cursor.lstat().st_mode
        except OSError as exc:
            raise GateError(f"{name} is missing below the evidence root") from exc
        if stat.S_ISLNK(mode):
            raise GateError(f"{name} contains a forbidden symlink")
    if not candidate.is_file() or not stat.S_ISREG(candidate.stat().st_mode):
        raise GateError(f"{name} must be a regular file")
    try:
        candidate.resolve(strict=True).relative_to(root)
    except (OSError, ValueError) as exc:
        raise GateError(f"{name} escapes the evidence root") from exc
    return candidate


def regular_directory_below(root: pathlib.Path, relative: pathlib.PurePosixPath, name: str) -> pathlib.Path:
    candidate = root.joinpath(*relative.parts)
    cursor = root
    for part in relative.parts:
        cursor = cursor / part
        try:
            mode = cursor.lstat().st_mode
        except OSError as exc:
            raise GateError(f"{name} is missing below the evidence root") from exc
        if stat.S_ISLNK(mode):
            raise GateError(f"{name} contains a forbidden symlink")
    if not candidate.is_dir():
        raise GateError(f"{name} must be a directory")
    try:
        candidate.resolve(strict=True).relative_to(root)
    except (OSError, ValueError) as exc:
        raise GateError(f"{name} escapes the evidence root") from exc
    return candidate


def validate_pilot_provenance(
    root_path: pathlib.Path,
    provenance_path: pathlib.Path,
    supplied: dict[str, pathlib.Path],
) -> dict[str, Any]:
    if root_path.is_symlink() or not root_path.is_dir():
        raise GateError("u0_pilot evidence root must be a regular non-symlink directory")
    root = root_path.resolve(strict=True)
    if provenance_path.is_symlink() or not provenance_path.is_file():
        raise GateError("u0_pilot provenance manifest must be a regular non-symlink file")
    try:
        provenance_path.resolve(strict=True).relative_to(root)
    except (OSError, ValueError) as exc:
        raise GateError("u0_pilot provenance manifest must be below the evidence root") from exc
    manifest = read_json(provenance_path)
    if set(manifest) != {"schema_version", "evidence_scope", "artifacts", "authenticity_boundary"}:
        raise GateError("u0_pilot provenance manifest keys mismatch")
    require_value(manifest.get("schema_version"), "dosa-v3-u0-pilot-provenance-1", "pilot_provenance.schema_version")
    require_value(manifest.get("evidence_scope"), "u0_pilot", "pilot_provenance.evidence_scope")
    require_value(
        manifest.get("authenticity_boundary"),
        "integrity_closure_not_external_authentication",
        "pilot_provenance.authenticity_boundary",
    )
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise GateError("pilot_provenance.artifacts must be a list")
    by_role: dict[str, pathlib.Path] = {}
    artifact_rows: dict[str, dict[str, Any]] = {}
    seen_paths: set[str] = set()
    for index, row in enumerate(artifacts):
        if not isinstance(row, dict) or set(row) != {"role", "path", "sha256", "size_bytes"}:
            raise GateError(f"pilot_provenance.artifacts[{index}] keys mismatch")
        role = row.get("role")
        if not isinstance(role, str) or role in by_role:
            raise GateError("pilot provenance roles must be unique strings")
        relative = normalized_relative_path(row.get("path"), f"pilot_provenance.artifacts[{role}].path")
        if relative.as_posix() in seen_paths:
            raise GateError("pilot provenance paths must be unique")
        seen_paths.add(relative.as_posix())
        target = regular_file_below(root, relative, f"pilot provenance artifact {role}")
        expected_sha = require_sha(row.get("sha256"), f"pilot_provenance.artifacts[{role}].sha256")
        expected_size = positive_integer(row.get("size_bytes"), f"pilot_provenance.artifacts[{role}].size_bytes")
        if target.stat().st_size != expected_size or sha256_file(target) != expected_sha:
            raise GateError(f"pilot provenance artifact bytes mismatch: {role}")
        by_role[role] = target
        artifact_rows[role] = {
            "path": relative.as_posix(),
            "sha256": expected_sha,
            "size_bytes": expected_size,
        }
    if set(by_role) != PILOT_PROVENANCE_ROLES or set(supplied) != PILOT_PROVENANCE_ROLES:
        raise GateError("pilot provenance must close exactly the required U0 artifact roles")
    for role, supplied_path in supplied.items():
        if supplied_path.resolve(strict=True) != by_role[role].resolve(strict=True):
            raise GateError(f"supplied artifact is not the provenance-bound file: {role}")
    return {
        "path": provenance_path.name,
        "bytes": provenance_path.stat().st_size,
        "sha256": sha256_file(provenance_path),
        "artifact_count": len(by_role),
        "artifacts": artifact_rows,
        "paths": by_role,
    }


def validate_source_freeze_closure(
    evidence_root: pathlib.Path,
    provenance: dict[str, Any],
    core: dict[str, Any],
) -> dict[str, Any]:
    paths = provenance["paths"]
    selection_path = paths["selection"]
    candidates_path = paths["control_candidates"]
    ledger_path = paths["control_ledger"]
    binding_path = paths["control_binding_receipt"]
    validation_path = paths["control_validation_receipt"]
    freeze_path = paths["source_freeze_receipt"]
    assembly_report = paths["assembly_report"]
    sequence_report = paths["sequence_report"]

    with tempfile.TemporaryDirectory(prefix="dosa-u0-selection-check.") as temporary:
        recomputed = pathlib.Path(temporary) / "selection.jsonl"
        command = [
            sys.executable,
            str(ROOT / "scripts" / "select_u0_pilot.py"),
            "--assemblies", str(assembly_report),
            "--sequences", str(sequence_report),
            "--control-candidates", str(candidates_path),
            "--output", str(recomputed),
            "--largest", "100",
        ]
        completed = subprocess.run(command, capture_output=True, text=True, timeout=300, check=False)
        if completed.returncode != 0 or not recomputed.is_file():
            raise GateError(f"real U0 deterministic selection recomputation failed: {completed.stderr or completed.stdout}")
        if recomputed.read_bytes() != selection_path.read_bytes():
            raise GateError("real U0 selection differs from mod-256 + top-100 + frozen-control recomputation")

    selection_records: dict[str, dict[str, Any]] = {}
    with selection_path.open("rb") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.endswith(b"\n") or line == b"\n":
                raise GateError(f"selection has malformed JSONL line {line_number}")
            row = read_json_object_bytes(line[:-1], f"selection line {line_number}")
            accession = require_accession(row.get("sequence_accession_version"), f"selection line {line_number} accession")
            if accession in selection_records:
                raise GateError(f"selection contains duplicate accession.version: {accession}")
            selection_records[accession] = row
    if len(selection_records) < 100:
        raise GateError("real U0 selection cannot contain fewer than the 100-largest component")

    source_records = core["documents"]["source_manifest"].get("selected_records")
    source_accessions = {
        row.get("sequence_accession_version")
        for row in source_records
        if isinstance(row, dict)
    } if isinstance(source_records, list) else set()
    if source_accessions != set(selection_records) or None in source_accessions:
        raise GateError("source manifest selected records do not exactly equal the recomputed U0 pilot selection")

    work_manifest_path = paths["work_unit_manifest"]
    work_header = (
        "u0_manifest_version", "work_unit_id", "assembly_accession_version",
        "sequence_accession_version", "replicon_class", "source_locator",
        "source_file_sha256", "sequence_sha256", "sequence_length", "declared_alphabet",
        "parameters_sha256", "scale", "stride", "k_min", "k_max", "null_model",
        "null_replicates",
    )
    source_index = read_json(paths["source_index"])
    index_records = source_index.get("records")
    if source_index.get("source_index_version") != "dosa-v3-source-index-1" or not isinstance(index_records, dict):
        raise GateError("work-unit closure requires the canonical v3 source index")
    expected_coordinates = {
        (accession, scale)
        for accession in selection_records
        for scale in (16, 100, 500, 1000)
    }
    work_units: dict[tuple[str, int], dict[str, Any]] = {}
    with work_manifest_path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != work_header:
            raise GateError("real U0 work-unit manifest header mismatch")
        for line_number, row in enumerate(reader, start=2):
            if set(row) != set(work_header) or any(row[field] is None for field in work_header):
                raise GateError(f"real U0 work-unit manifest row malformed at line {line_number}")
            accession = require_accession(row["sequence_accession_version"], f"work-unit line {line_number} accession")
            try:
                scale = int(row["scale"])
                stride = int(row["stride"])
                length_bp = int(row["sequence_length"])
                k_min = int(row["k_min"])
                k_max = int(row["k_max"])
                replicates = int(row["null_replicates"])
            except ValueError as exc:
                raise GateError(f"real U0 work-unit manifest numeric field invalid at line {line_number}") from exc
            coordinate = (accession, scale)
            if coordinate not in expected_coordinates or coordinate in work_units:
                raise GateError(f"real U0 work-unit coordinate is absent or duplicated at line {line_number}")
            selected = selection_records[accession]
            indexed = index_records.get(accession)
            if not isinstance(indexed, dict):
                raise GateError(f"real U0 work-unit accession is absent from source index: {accession}")
            require_value(row["u0_manifest_version"], "1.0.0", f"work-unit line {line_number} version")
            require_value(row["work_unit_id"], f"{accession}@{scale}", f"work-unit line {line_number} ID")
            require_value(row["assembly_accession_version"], selected.get("assembly_accession_version"), f"work-unit line {line_number} assembly")
            require_value(row["replicon_class"], selected.get("replicon_class"), f"work-unit line {line_number} class")
            require_value(row["source_locator"], indexed.get("locator"), f"work-unit line {line_number} source locator")
            require_value(row["source_file_sha256"], indexed.get("canonical_sequence_input_sha256"), f"work-unit line {line_number} source SHA-256")
            require_value(row["sequence_sha256"], indexed.get("normalized_sequence_sha256"), f"work-unit line {line_number} sequence SHA-256")
            require_value(length_bp, selected.get("length_bp"), f"work-unit line {line_number} sequence length")
            if row["declared_alphabet"] not in ("acgt", "non_acgt"):
                raise GateError(f"work-unit line {line_number} declared alphabet is invalid")
            require_value(row["parameters_sha256"], core["sha256"]["parameters"], f"work-unit line {line_number} parameters SHA-256")
            if scale not in (16, 100, 500, 1000) or stride != scale or k_min != 1 or k_max != 8:
                raise GateError(f"work-unit line {line_number} violates scale/stride/k contract")
            require_value(row["null_model"], "euler_wilson_fixed_endpoints_v1", f"work-unit line {line_number} null model")
            require_value(replicates, 1000, f"work-unit line {line_number} null replicates")
            work_units[coordinate] = {
                "work_unit_id": row["work_unit_id"],
                "sequence_length": length_bp,
                "expected_rows": length_bp // scale,
            }
    if set(work_units) != expected_coordinates:
        raise GateError("real U0 work-unit manifest does not cover every selected replicon x four scales")

    binding = read_json(binding_path)
    require_value(binding.get("schema_version"), "dosa-u0-control-binding-receipt-1", "control_binding_receipt.schema_version")
    require_value(binding.get("status"), "bound_unvalidated", "control_binding_receipt.status")
    require_value(binding.get("control_candidates_sha256"), sha256_file(candidates_path), "control_binding_receipt.control_candidates_sha256")
    require_value(binding.get("control_ledger_sha256"), sha256_file(ledger_path), "control_binding_receipt.control_ledger_sha256")
    require_value(binding.get("semantic_validation_complete"), False, "control_binding_receipt.semantic_validation_complete")
    require_value(binding.get("scientific_metrics_computed"), False, "control_binding_receipt.scientific_metrics_computed")

    validation = read_json(validation_path)
    require_value(validation.get("schema_version"), "dosa-u0-control-ledger-receipt-1", "control_validation_receipt.schema_version")
    require_value(validation.get("status"), "validated", "control_validation_receipt.status")
    require_value(validation.get("control_ledger_sha256"), sha256_file(ledger_path), "control_validation_receipt.control_ledger_sha256")
    require_value(validation.get("scientific_metrics_computed"), False, "control_validation_receipt.scientific_metrics_computed")
    required_categories = {
        "topology_circular", "topology_linear", "ambiguity_present",
        "ambiguity_absent", "replicon_chromosome", "replicon_plasmid",
    }
    require_value(set(validation.get("required_categories", [])), required_categories, "control_validation_receipt.required_categories")
    package_relative = normalized_relative_path(validation.get("package_root"), "control_validation_receipt.package_root")
    package_root = regular_directory_below(validation_path.parent.resolve(strict=True), package_relative, "control package root")
    try:
        validator_module = runpy.run_path(str(ROOT / "scripts" / "validate_u0_control_ledger.py"))
        recomputed_controls = validator_module["load_and_validate"](ledger_path, package_root)
    except (KeyError, OSError, RuntimeError) as exc:
        raise GateError(f"real U0 control semantic revalidation failed: {exc}") from exc
    require_value(validation.get("controls"), recomputed_controls, "control_validation_receipt.controls")

    freeze = read_json(freeze_path)
    require_value(freeze.get("schema_version"), "dosa-u0-source-freeze-1", "source_freeze_receipt.schema_version")
    require_value(freeze.get("status"), "frozen_unprocessed", "source_freeze_receipt.status")
    require_value(freeze.get("scientific_metrics_computed"), False, "source_freeze_receipt.scientific_metrics_computed")
    expected_hashes = {
        "selection_sha256": sha256_file(selection_path),
        "control_candidates_sha256": sha256_file(candidates_path),
        "control_ledger_sha256": sha256_file(ledger_path),
        "control_binding_receipt_sha256": sha256_file(binding_path),
        "control_ledger_receipt_sha256": sha256_file(validation_path),
        "source_manifest_sha256": core["sha256"]["source_manifest"],
        "source_integrity_receipt_sha256": core["sha256"]["source_integrity"],
        "source_index_sha256": provenance["artifacts"]["source_index"]["sha256"],
        "full_replicon_inventory_sha256": provenance["artifacts"]["full_replicon_inventory"]["sha256"],
        "work_unit_manifest_sha256": provenance["artifacts"]["work_unit_manifest"]["sha256"],
    }
    for field, expected in expected_hashes.items():
        require_value(freeze.get(field), expected, f"source_freeze_receipt.{field}")
    positive_integer(freeze.get("pending_bytes"), "source_freeze_receipt.pending_bytes")
    return {
        "selection_records": selection_records,
        "package_root": package_root,
        "work_units": work_units,
        "work_units_expected": len(expected_coordinates),
        "work_unit_manifest_sha256": sha256_file(work_manifest_path),
    }


def check_core_artifacts(paths: dict[str, pathlib.Path]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    documents: dict[str, dict[str, Any]] = {}
    identities: dict[str, str] = {}
    bindings: list[dict[str, Any]] = []
    for role, path in sorted(paths.items()):
        if path.is_symlink() or not path.is_file():
            raise GateError(f"core artifact must be a regular non-symlink file: {role}")
        documents[role] = read_json(path)
        identities[role] = sha256_file(path)
        bindings.append({"role": role, "name": path.name, "bytes": path.stat().st_size, "sha256": identities[role]})

    parameters = documents["parameters"]
    require_value(parameters.get("schema_version"), "3.0.0", "parameters.schema_version")
    require_value(parameters.get("contract_id"), "dosa-v3-u0", "parameters.contract_id")
    require_value(parameters.get("window_profiles"), [
        {"window_size": 16, "stride": 16}, {"window_size": 100, "stride": 100},
        {"window_size": 500, "stride": 500}, {"window_size": 1000, "stride": 1000},
    ], "parameters.window_profiles")
    require_value(parameters.get("k_min"), 1, "parameters.k_min")
    require_value(parameters.get("k_max"), 8, "parameters.k_max")
    require_value(parameters.get("null_model"), "euler_wilson_fixed_endpoints_v1", "parameters.null_model")
    require_value(parameters.get("null_replicates"), 1000, "parameters.null_replicates")

    source = documents["source_manifest"]
    require_value(source.get("schema_version"), "3.0.0", "source_manifest.schema_version")
    require_value(source.get("source_provider"), "NCBI_Datasets", "source_manifest.source_provider")
    if not isinstance(source.get("selected_records"), list) or not source["selected_records"]:
        raise GateError("source_manifest.selected_records must be non-empty")
    if not isinstance(source.get("package_assets"), list) or not source["package_assets"]:
        raise GateError("source_manifest.package_assets must be non-empty")

    integrity = documents["source_integrity"]
    require_value(integrity.get("schema_version"), "dosa-u0-source-integrity-receipt-1", "source_integrity.schema_version")
    require_value(integrity.get("source_manifest_sha256"), identities["source_manifest"], "source_integrity.source_manifest_sha256")
    require_value(integrity.get("scientific_metrics_computed"), False, "source_integrity.scientific_metrics_computed")
    if not isinstance(integrity.get("records"), list) or not integrity["records"]:
        raise GateError("source_integrity.records must be non-empty")

    payload = documents["payload_manifest"]
    require_value(payload.get("schema_version"), "3.0.0", "payload_manifest.schema_version")
    require_value(payload.get("parameters_sha256"), identities["parameters"], "payload_manifest.parameters_sha256")
    require_value(payload.get("source_manifest_sha256"), identities["source_manifest"], "payload_manifest.source_manifest_sha256")
    tables = payload.get("public_tables")
    if not isinstance(tables, list) or len(tables) != 5 or {row.get("filename") for row in tables if isinstance(row, dict)} != PUBLIC_TABLES:
        raise GateError("payload_manifest must close exactly the five required public tables")
    window = [row for row in tables if isinstance(row, dict) and row.get("filename") == "window_operator_profiles.parquet"]
    if len(window) != 1 or not isinstance(window[0].get("storage"), dict):
        raise GateError("payload_manifest lacks a window table storage declaration")
    window_storage = window[0]["storage"]
    if window_storage.get("layout") != "package_manifest_partitioned" or window_storage.get("partitioning") != "scale_then_sha256_accession_bucket":
        raise GateError("payload_manifest window table must be package-manifest partitioned")
    package_manifests = payload.get("package_manifests")
    if not isinstance(package_manifests, list) or not package_manifests:
        raise GateError("payload_manifest must bind one or more CLI package manifests")
    by_id: dict[str, str] = {}
    package_entries: dict[str, dict[str, Any]] = {}
    for entry in package_manifests:
        if not isinstance(entry, dict):
            raise GateError("payload_manifest package manifest entry must be an object")
        package_id = entry.get("package_manifest_id")
        if not isinstance(package_id, str) or not package_id or package_id in by_id:
            raise GateError("payload_manifest package manifest IDs must be unique non-empty strings")
        require_sha(entry.get("sha256"), f"payload_manifest.package_manifests[{package_id}].sha256")
        require_value(entry.get("manifest_version"), "dosa-v3-u0-dev-payload-manifest-3", f"payload_manifest.package_manifests[{package_id}].manifest_version")
        require_value(entry.get("package_version"), "U0-dev", f"payload_manifest.package_manifests[{package_id}].package_version")
        require_value(entry.get("table_filename"), "window_operator_profiles.parquet", f"payload_manifest.package_manifests[{package_id}].table_filename")
        positive_integer(entry.get("size_bytes"), f"payload_manifest.package_manifests[{package_id}].size_bytes")
        by_id[package_id] = entry["sha256"]
        package_entries[package_id] = entry
    if set(window_storage.get("package_manifest_ids", [])) != set(by_id):
        raise GateError("payload_manifest window-table package references do not close the CLI package set")

    attestation = documents["sounio_attestation"]
    required_attestation = {
        "attestation_version", "evidence_scope", "repository_url", "source_commit",
        "source_sha256", "compiler_sha256", "executable_sha256", "receipt_path", "receipt_sha256",
    }
    if set(attestation) != required_attestation:
        raise GateError("Sounio attestation keys mismatch")
    require_value(attestation.get("attestation_version"), "dosa-v3-sounio-runner-attestation-1", "sounio_attestation.attestation_version")
    require_value(attestation.get("repository_url"), "https://github.com/sounio-lang/sounio.git", "sounio_attestation.repository_url")
    if attestation.get("evidence_scope") not in ("fixture-only-non-semantic", "build-provenance-only-non-semantic"):
        raise GateError("sounio_attestation.evidence_scope is invalid")
    if not isinstance(attestation.get("source_commit"), str) or re.fullmatch(r"[0-9a-f]{40}", attestation["source_commit"]) is None:
        raise GateError("sounio_attestation.source_commit must be lowercase 40-hex")
    for field in ("source_sha256", "compiler_sha256", "executable_sha256", "receipt_sha256"):
        require_sha(attestation.get(field), f"sounio_attestation.{field}")
    receipt_name = attestation.get("receipt_path")
    if not isinstance(receipt_name, str) or pathlib.PurePosixPath(receipt_name).name != receipt_name:
        raise GateError("sounio_attestation.receipt_path must name the supplied separate receipt")
    require_value(receipt_name, paths["sounio_build_receipt"].name, "sounio_attestation.receipt_path")
    require_value(attestation.get("receipt_sha256"), identities["sounio_build_receipt"], "sounio_attestation.receipt_sha256")

    julia = documents["julia_receipt"]
    require_value(julia.get("schema_version"), "dosa-v3-u0-julia-full-validation-receipt-1", "julia_receipt.schema_version")
    require_value(julia.get("status"), "PASS", "julia_receipt.status")
    require_value(julia.get("language"), "Julia", "julia_receipt.language")
    require_value(julia.get("full_pilot_recomputed"), True, "julia_receipt.full_pilot_recomputed")
    require_value(julia.get("disagreements"), 0, "julia_receipt.disagreements")
    require_value(julia.get("absolute_tolerance"), 0, "julia_receipt.absolute_tolerance")
    positive_integer(julia.get("rows_recomputed"), "julia_receipt.rows_recomputed")
    require_value(julia.get("parameters_sha256"), identities["parameters"], "julia_receipt.parameters_sha256")
    require_value(julia.get("source_manifest_sha256"), identities["source_manifest"], "julia_receipt.source_manifest_sha256")
    require_value(julia.get("payload_manifest_sha256"), identities["payload_manifest"], "julia_receipt.payload_manifest_sha256")
    return {
        "sha256": identities,
        "documents": documents,
        "package_manifests": by_id,
        "package_manifest_entries": package_entries,
    }, bindings


def validate_package_closure(
    evidence_root: pathlib.Path,
    core: dict[str, Any],
    pilot: dict[str, Any],
) -> dict[str, Any]:
    try:
        import duckdb  # type: ignore
    except ModuleNotFoundError as exc:
        raise GateError("real U0 package closure requires duckdb==1.5.5") from exc
    if getattr(duckdb, "__version__", None) != "1.5.5":
        raise GateError(f"real U0 package closure requires duckdb==1.5.5, found {getattr(duckdb, '__version__', None)!r}")

    cli_package = ROOT / "cli" / "package"
    if str(cli_package) not in sys.path:
        sys.path.insert(0, str(cli_package))
    try:
        from dosa_v3.core import DosaError, verify_package  # type: ignore
    except (ImportError, OSError) as exc:
        raise GateError("cannot load the repository-bound DOSA package verifier") from exc

    root = evidence_root.resolve(strict=True)
    logical_artifacts = {
        row["sha256"]: row
        for row in pilot["documents"]["sounio_output_manifest"]["artifacts"]
    }
    seen_logical: set[str] = set()
    package_hashes: dict[str, str] = {}
    package_directories: list[pathlib.Path] = []
    package_rows = 0
    connection = duckdb.connect(":memory:")
    try:
        for package_id, entry in sorted(core["package_manifest_entries"].items()):
            relative = normalized_relative_path(entry.get("path"), f"payload package manifest {package_id}.path")
            manifest_path = regular_file_below(root, relative, f"payload package manifest {package_id}")
            if manifest_path.name != "dosa-payload-manifest.json":
                raise GateError(f"payload package manifest {package_id} has a non-canonical filename")
            if manifest_path.stat().st_size != entry["size_bytes"] or sha256_file(manifest_path) != entry["sha256"]:
                raise GateError(f"payload package manifest bytes mismatch: {package_id}")
            try:
                verify_package(manifest_path.parent)
            except DosaError as exc:
                raise GateError(f"DOSA package verification failed for {package_id}: {exc}") from exc
            manifest = read_json(manifest_path)
            source = manifest.get("source")
            if not isinstance(source, dict):
                raise GateError(f"payload package manifest {package_id} lacks logical source binding")
            logical_sha = require_sha(source.get("logical_sha256"), f"payload package manifest {package_id}.source.logical_sha256")
            logical_bytes = positive_integer(source.get("logical_bytes"), f"payload package manifest {package_id}.source.logical_bytes")
            logical = logical_artifacts.get(logical_sha)
            if logical is None or logical.get("size_bytes") != logical_bytes or logical_sha in seen_logical:
                raise GateError(f"payload package {package_id} is not uniquely bound to a Sounio logical artifact")
            seen_logical.add(logical_sha)

            source_bindings = [
                row for row in manifest.get("bindings", [])
                if isinstance(row, dict) and row.get("kind") == "source_index"
            ]
            if len(source_bindings) != 1 or source_bindings[0].get("sha256") != pilot["sha256"]["source_index"]:
                raise GateError(f"payload package {package_id} is not bound to the real U0 source index")

            for index, payload in enumerate(manifest.get("payloads", [])):
                if not isinstance(payload, dict):
                    raise GateError(f"payload package {package_id} has a non-object shard entry")
                scale = int(require_scale(payload.get("scale"), f"payload package {package_id} shard scale"))
                rows = positive_integer(payload.get("rows"), f"payload package {package_id} shard rows")
                shard_relative = normalized_relative_path(payload.get("name"), f"payload package {package_id} shard path")
                shard_path = regular_file_below(manifest_path.parent, shard_relative, f"payload package {package_id} shard {index}")
                try:
                    footer_rows = int(connection.execute("SELECT num_rows FROM parquet_file_metadata(?)", [str(shard_path)]).fetchone()[0])
                    compressions = {
                        str(row[0]).lower()
                        for row in connection.execute("SELECT DISTINCT compression FROM parquet_metadata(?)", [str(shard_path)]).fetchall()
                    }
                    columns = {
                        str(row[0])
                        for row in connection.execute("DESCRIBE SELECT * FROM read_parquet(?, hive_partitioning=false)", [str(shard_path)]).fetchall()
                    }
                    content_rows, mismatches = connection.execute(
                        "SELECT count(*), count(*) FILTER (WHERE try_cast(scale AS BIGINT) IS NULL OR try_cast(scale AS BIGINT) <> ?) "
                        "FROM read_parquet(?, hive_partitioning=false)",
                        [scale, str(shard_path)],
                    ).fetchone()
                except Exception as exc:
                    raise GateError(f"payload package {package_id} has unreadable Parquet shard {index}") from exc
                if "scale" not in columns or footer_rows != rows or int(content_rows) != rows or int(mismatches) != 0 or compressions != {"zstd"}:
                    raise GateError(f"payload package {package_id} Parquet footer/content contract failed at shard {index}")
                package_rows += rows
            package_hashes[package_id] = entry["sha256"]
            package_directories.append(manifest_path.parent)
    finally:
        connection.close()
    if seen_logical != set(logical_artifacts):
        raise GateError("not every Sounio logical output artifact is represented by exactly one DOSA package")
    return {
        "package_manifest_sha256s": package_hashes,
        "parquet_rows": package_rows,
        "package_directories": package_directories,
    }


def command_json_object(command: list[str], name: str, timeout: int = 600) -> dict[str, Any]:
    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        raise GateError(f"{name} could not run: {exc}") from exc
    if completed.returncode != 0:
        raise GateError(f"{name} failed with rc={completed.returncode}: {completed.stderr or completed.stdout}")
    lines = [line for line in completed.stdout.splitlines() if line]
    if len(lines) != 1:
        raise GateError(f"{name} must emit exactly one JSON object")
    return read_json_object_bytes(lines[0].encode("utf-8"), name)


def recompute_capacity_report(
    package_directories: list[pathlib.Path],
    full_replicon_inventory: pathlib.Path,
    payload_manifest: pathlib.Path,
    expected: dict[str, Any],
) -> None:
    command = [sys.executable, str(ROOT / "scripts" / "project_u0_parquet_capacity.py")]
    for package in package_directories:
        command.extend(("--package", str(package)))
    command.extend(
        (
            "--full-replicons", str(full_replicon_inventory),
            "--public-payload-manifest", str(payload_manifest),
            "--evidence-scope", "u0_pilot",
        )
    )
    observed = command_json_object(command, "real U0 Parquet capacity recomputation")
    require_value(observed, expected, "capacity report recomputation")


def recompute_scientific_reports(
    julia_bin: pathlib.Path,
    reports: dict[str, dict[str, Any]],
    inputs: dict[str, pathlib.Path],
    julia_receipt: dict[str, Any],
) -> None:
    executable = julia_bin.resolve(strict=True)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise GateError("real U0 Julia binary must resolve to an executable regular file")
    version_run = subprocess.run([str(executable), "--version"], capture_output=True, text=True, timeout=30, check=False)
    if version_run.returncode != 0 or not version_run.stdout.startswith("julia version "):
        raise GateError("real U0 Julia version probe failed")
    require_value(version_run.stdout.strip().removeprefix("julia version "), julia_receipt.get("version"), "julia_receipt.version")
    for role, evaluator in (("oric", ORIC_EVALUATOR), ("model", MODEL_EVALUATOR)):
        command = [
            str(executable), "--startup-file=no", f"--project={ROOT / 'julia'}",
            str(evaluator), str(inputs[f"{role}_input"]),
        ]
        observed = command_json_object(command, f"Julia {role} scientific evaluator")
        require_value(observed, reports[role], f"{role} report byte-semantic recomputation")


def validate_real_pilot_artifacts(
    paths: dict[str, pathlib.Path],
    evidence_root: pathlib.Path,
    core: dict[str, Any],
    provenance: dict[str, Any],
    source_freeze: dict[str, Any],
) -> dict[str, Any]:
    if not U0_SOUNIO_EXECUTOR.is_file():
        raise GateError("real U0 is blocked: canonical Sounio u0_pilot_executor.sio is not implemented")
    if not U0_JULIA_FULL_VALIDATOR.is_file():
        raise GateError("real U0 is blocked: independent Julia validate_u0_pilot.jl is not implemented")
    documents: dict[str, dict[str, Any]] = {}
    identities: dict[str, str] = {}
    bindings: list[dict[str, Any]] = []
    for role, path in sorted(paths.items()):
        if path.is_symlink() or not path.is_file():
            raise GateError(f"real U0 artifact must be a regular non-symlink file: {role}")
        documents[role] = read_json(path)
        identities[role] = sha256_file(path)
        bindings.append({"role": role, "name": path.name, "bytes": path.stat().st_size, "sha256": identities[role]})

    source_index = documents["source_index"]
    if set(source_index) != {"source_index_version", "records"}:
        raise GateError("real U0 source index keys mismatch")
    require_value(source_index.get("source_index_version"), "dosa-v3-source-index-1", "source_index.source_index_version")
    records = source_index.get("records")
    if not isinstance(records, dict) or not records:
        raise GateError("real U0 source index must contain records")
    for accession, record in records.items():
        require_accession(accession, "source_index accession key")
        expected = {
            "locator", "canonical_sequence_input_sha256", "normalized_sequence_sha256",
            "source_manifest_sha256", "source_integrity_sha256",
        }
        if not isinstance(record, dict) or set(record) != expected:
            raise GateError(f"source index record keys mismatch: {accession}")
        require_public_locator(record.get("locator"), f"source_index.records[{accession}].locator")
        require_sha(record.get("canonical_sequence_input_sha256"), f"source_index.records[{accession}].canonical_sequence_input_sha256")
        require_sha(record.get("normalized_sequence_sha256"), f"source_index.records[{accession}].normalized_sequence_sha256")
        require_value(record.get("source_manifest_sha256"), core["sha256"]["source_manifest"], f"source_index.records[{accession}].source_manifest_sha256")
        require_value(record.get("source_integrity_sha256"), core["sha256"]["source_integrity"], f"source_index.records[{accession}].source_integrity_sha256")

    build = core["documents"]["sounio_build_receipt"]
    sounio_lock = read_json(ROOT / "toolchains" / "sounio.lock.json")
    build_keys = {
        "schema_version", "receipt_id", "evidence_scope", "status", "repository_url",
        "source_commit", "source_path", "source_sha256", "compiler_sha256", "executable_sha256",
        "build_exit_code", "source_dirty", "scientific_semantics_validated",
    }
    if set(build) != build_keys:
        raise GateError("real U0 Sounio build receipt keys mismatch")
    require_value(build.get("schema_version"), "dosa-v3-sounio-build-receipt-1", "sounio_build_receipt.schema_version")
    require_value(build.get("evidence_scope"), "build-provenance-only-non-semantic", "sounio_build_receipt.evidence_scope")
    require_value(build.get("status"), "PASS", "sounio_build_receipt.status")
    require_value(build.get("repository_url"), sounio_lock.get("repository"), "sounio_build_receipt.repository_url")
    require_value(build.get("source_commit"), sounio_lock.get("commit"), "sounio_build_receipt.source_commit")
    require_value(build.get("source_path"), "sounio/src/u0_pilot_executor.sio", "sounio_build_receipt.source_path")
    require_value(build.get("source_sha256"), sha256_file(U0_SOUNIO_EXECUTOR), "sounio_build_receipt.source_sha256")
    require_value(build.get("build_exit_code"), 0, "sounio_build_receipt.build_exit_code")
    require_value(build.get("source_dirty"), False, "sounio_build_receipt.source_dirty")
    require_value(build.get("scientific_semantics_validated"), False, "sounio_build_receipt.scientific_semantics_validated")
    if not isinstance(build.get("source_commit"), str) or re.fullmatch(r"[0-9a-f]{40}", build["source_commit"]) is None:
        raise GateError("sounio_build_receipt.source_commit must be lowercase 40-hex")
    for field in ("source_sha256", "compiler_sha256", "executable_sha256"):
        require_sha(build.get(field), f"sounio_build_receipt.{field}")
    attestation = core["documents"]["sounio_attestation"]
    for attestation_field, build_field in (
        ("repository_url", "repository_url"),
        ("source_commit", "source_commit"),
        ("source_sha256", "source_sha256"),
        ("compiler_sha256", "compiler_sha256"),
        ("executable_sha256", "executable_sha256"),
    ):
        require_value(attestation.get(attestation_field), build.get(build_field), f"Sounio attestation/build {attestation_field}")

    output_manifest = documents["sounio_output_manifest"]
    output_keys = {
        "schema_version", "parameters_sha256", "source_manifest_sha256", "work_unit_manifest_sha256",
        "work_units_expected", "work_units_completed", "rows_emitted",
        "all_work_units_complete", "work_units", "artifacts",
    }
    if set(output_manifest) != output_keys:
        raise GateError("real U0 Sounio output manifest keys mismatch")
    require_value(output_manifest.get("schema_version"), "dosa-v3-u0-sounio-output-manifest-1", "sounio_output_manifest.schema_version")
    require_value(output_manifest.get("parameters_sha256"), core["sha256"]["parameters"], "sounio_output_manifest.parameters_sha256")
    require_value(output_manifest.get("source_manifest_sha256"), core["sha256"]["source_manifest"], "sounio_output_manifest.source_manifest_sha256")
    require_value(output_manifest.get("work_unit_manifest_sha256"), source_freeze["work_unit_manifest_sha256"], "sounio_output_manifest.work_unit_manifest_sha256")
    expected_units = positive_integer(output_manifest.get("work_units_expected"), "sounio_output_manifest.work_units_expected")
    completed_units = positive_integer(output_manifest.get("work_units_completed"), "sounio_output_manifest.work_units_completed")
    rows_emitted = positive_integer(output_manifest.get("rows_emitted"), "sounio_output_manifest.rows_emitted")
    require_value(output_manifest.get("all_work_units_complete"), True, "sounio_output_manifest.all_work_units_complete")
    if completed_units != expected_units:
        raise GateError("Sounio output manifest work units are incomplete")
    require_value(expected_units, source_freeze["work_units_expected"], "sounio_output_manifest.work_units_expected")
    output_work_units = output_manifest.get("work_units")
    if not isinstance(output_work_units, list) or len(output_work_units) != expected_units:
        raise GateError("Sounio output manifest work-unit ledger length mismatch")
    declared_work_rows: dict[tuple[str, int], int] = {}
    for index, work in enumerate(output_work_units):
        required_work_keys = {"work_unit_id", "sequence_accession_version", "scale", "rows_emitted", "status", "reason_code"}
        if not isinstance(work, dict) or set(work) != required_work_keys:
            raise GateError(f"Sounio output work-unit ledger keys mismatch at index {index}")
        accession = require_accession(work.get("sequence_accession_version"), f"Sounio output work unit {index} accession")
        scale = int(require_scale(work.get("scale"), f"Sounio output work unit {index} scale"))
        coordinate = (accession, scale)
        expected_work = source_freeze["work_units"].get(coordinate)
        if expected_work is None or coordinate in declared_work_rows:
            raise GateError(f"Sounio output work-unit ledger coordinate absent or duplicated at index {index}")
        require_value(work.get("work_unit_id"), expected_work["work_unit_id"], f"Sounio output work unit {index} ID")
        rows_for_work = nonnegative_integer(work.get("rows_emitted"), f"Sounio output work unit {index} rows")
        require_value(rows_for_work, expected_work["expected_rows"], f"Sounio output work unit {index} expected rows")
        expected_status = "complete" if rows_for_work > 0 else "excluded"
        require_value(work.get("status"), expected_status, f"Sounio output work unit {index} status")
        if expected_status == "complete":
            require_value(work.get("reason_code"), None, f"Sounio output work unit {index} reason_code")
        elif not isinstance(work.get("reason_code"), str) or not work["reason_code"]:
            raise GateError(f"Sounio output work unit {index} excluded rows require a reason code")
        declared_work_rows[coordinate] = rows_for_work
    if set(declared_work_rows) != set(source_freeze["work_units"]):
        raise GateError("Sounio output work-unit ledger does not close the selected replicon x scale set")
    require_value(sum(declared_work_rows.values()), rows_emitted, "sounio_output_manifest.rows_emitted")
    output_artifacts = output_manifest.get("artifacts")
    if not isinstance(output_artifacts, list) or not output_artifacts:
        raise GateError("Sounio output manifest must bind one or more logical artifacts")
    seen_output_paths: set[str] = set()
    artifact_rows = 0
    observed_work_rows: Counter[tuple[str, int]] = Counter()
    observed_window_indices: dict[tuple[str, int], set[int]] = {}
    root = evidence_root.resolve(strict=True)
    row_validator = window_row_validator()
    for index, artifact in enumerate(output_artifacts):
        expected_artifact_keys = {"path", "media_type", "sha256", "size_bytes", "rows"}
        if not isinstance(artifact, dict) or set(artifact) != expected_artifact_keys:
            raise GateError(f"Sounio output artifact keys mismatch at index {index}")
        relative = normalized_relative_path(artifact.get("path"), f"sounio_output_manifest.artifacts[{index}].path")
        if relative.as_posix() in seen_output_paths:
            raise GateError("Sounio output manifest has duplicate artifact paths")
        seen_output_paths.add(relative.as_posix())
        require_value(artifact.get("media_type"), "application/x-ndjson", f"sounio output artifact {index} media_type")
        expected_sha = require_sha(artifact.get("sha256"), f"sounio output artifact {index} sha256")
        expected_size = positive_integer(artifact.get("size_bytes"), f"sounio output artifact {index} size_bytes")
        expected_rows = positive_integer(artifact.get("rows"), f"sounio output artifact {index} rows")
        target = regular_file_below(root, relative, f"Sounio output artifact {index}")
        if target.stat().st_size != expected_size or sha256_file(target) != expected_sha:
            raise GateError(f"Sounio output artifact bytes mismatch at index {index}")
        observed_rows = 0
        with target.open("rb") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.endswith(b"\n") or line == b"\n":
                    raise GateError(f"Sounio output artifact {index} has a malformed JSONL line {line_number}")
                row = read_json_object_bytes(line[:-1], f"Sounio output artifact {index} line {line_number}")
                errors = sorted(row_validator.iter_errors(row), key=lambda item: list(item.absolute_path))
                if errors:
                    location = ".".join(str(item) for item in errors[0].absolute_path) or "$"
                    raise GateError(
                        f"Sounio output artifact {index} line {line_number} fails the public row schema at {location}: {errors[0].message}"
                    )
                validate_window_row_invariants(row, f"Sounio output artifact {index} line {line_number}")
                coordinate = (str(row["replicon_id"]), int(row["window_size"]))
                if coordinate not in declared_work_rows:
                    raise GateError(f"Sounio output artifact {index} line {line_number} is outside the work-unit manifest")
                window_index = int(row["window_index"])
                indices = observed_window_indices.setdefault(coordinate, set())
                if window_index in indices:
                    raise GateError(f"Sounio output contains duplicate window index for {coordinate}")
                indices.add(window_index)
                observed_work_rows[coordinate] += 1
                observed_rows += 1
        if observed_rows != expected_rows:
            raise GateError(f"Sounio output artifact JSONL row count mismatch at index {index}")
        artifact_rows += expected_rows
    if artifact_rows != rows_emitted:
        raise GateError("Sounio output manifest artifact rows do not reconcile")
    if dict(observed_work_rows) != {key: value for key, value in declared_work_rows.items() if value > 0}:
        raise GateError("Sounio output rows do not reconcile with the work-unit ledger")
    for coordinate, expected_rows_for_work in declared_work_rows.items():
        if expected_rows_for_work > 0 and observed_window_indices.get(coordinate) != set(range(expected_rows_for_work)):
            raise GateError(f"Sounio output window coverage is incomplete for {coordinate}")

    execution = documents["sounio_execution_receipt"]
    execution_keys = {
        "schema_version", "receipt_id", "evidence_scope", "status", "canonical_producer",
        "null_model", "null_replicates", "parameters_sha256", "source_manifest_sha256",
        "work_unit_manifest_sha256",
        "sounio_attestation_sha256", "sounio_executable_sha256", "output_manifest_sha256",
        "work_units_expected", "work_units_completed", "rows_emitted", "all_work_units_complete",
    }
    if set(execution) != execution_keys:
        raise GateError("real U0 Sounio execution receipt keys mismatch")
    require_value(execution.get("schema_version"), "dosa-v3-u0-sounio-execution-receipt-1", "sounio_execution_receipt.schema_version")
    require_value(execution.get("evidence_scope"), "u0_pilot", "sounio_execution_receipt.evidence_scope")
    require_value(execution.get("status"), "PASS", "sounio_execution_receipt.status")
    require_value(execution.get("canonical_producer"), "Sounio", "sounio_execution_receipt.canonical_producer")
    require_value(execution.get("null_model"), "euler_wilson_fixed_endpoints_v1", "sounio_execution_receipt.null_model")
    require_value(execution.get("null_replicates"), 1000, "sounio_execution_receipt.null_replicates")
    require_value(execution.get("parameters_sha256"), core["sha256"]["parameters"], "sounio_execution_receipt.parameters_sha256")
    require_value(execution.get("source_manifest_sha256"), core["sha256"]["source_manifest"], "sounio_execution_receipt.source_manifest_sha256")
    require_value(execution.get("work_unit_manifest_sha256"), source_freeze["work_unit_manifest_sha256"], "sounio_execution_receipt.work_unit_manifest_sha256")
    require_value(execution.get("sounio_attestation_sha256"), core["sha256"]["sounio_attestation"], "sounio_execution_receipt.sounio_attestation_sha256")
    require_value(execution.get("sounio_executable_sha256"), attestation["executable_sha256"], "sounio_execution_receipt.sounio_executable_sha256")
    require_value(execution.get("output_manifest_sha256"), identities["sounio_output_manifest"], "sounio_execution_receipt.output_manifest_sha256")
    require_value(execution.get("work_units_expected"), expected_units, "sounio_execution_receipt.work_units_expected")
    require_value(execution.get("work_units_completed"), completed_units, "sounio_execution_receipt.work_units_completed")
    require_value(execution.get("rows_emitted"), rows_emitted, "sounio_execution_receipt.rows_emitted")
    require_value(execution.get("all_work_units_complete"), True, "sounio_execution_receipt.all_work_units_complete")

    julia = core["documents"]["julia_receipt"]
    required_julia = {
        "schema_version", "receipt_id", "evidence_scope", "status", "language", "version",
        "implementation_path", "implementation_sha256", "project_sha256", "manifest_sha256",
        "parameters_sha256", "source_manifest_sha256", "work_unit_manifest_sha256",
        "source_index_sha256", "payload_manifest_sha256", "sounio_execution_receipt_sha256",
        "sounio_output_manifest_sha256", "full_pilot_recomputed", "rows_recomputed",
        "disagreements", "absolute_tolerance", "package_manifest_sha256s",
        "parquet_rows_recomputed", "parquet_disagreements",
    }
    if set(julia) != required_julia:
        raise GateError("real U0 Julia receipt keys mismatch")
    require_value(julia.get("evidence_scope"), "u0_pilot", "julia_receipt.evidence_scope")
    if not isinstance(julia.get("version"), str) or not julia["version"]:
        raise GateError("julia_receipt.version must be non-empty")
    require_value(julia.get("implementation_path"), "julia/scripts/validate_u0_pilot.jl", "julia_receipt.implementation_path")
    require_value(julia.get("implementation_sha256"), sha256_file(U0_JULIA_FULL_VALIDATOR), "julia_receipt.implementation_sha256")
    require_value(julia.get("project_sha256"), sha256_file(ROOT / "julia" / "Project.toml"), "julia_receipt.project_sha256")
    require_value(julia.get("manifest_sha256"), sha256_file(ROOT / "julia" / "Manifest.toml"), "julia_receipt.manifest_sha256")
    require_value(julia.get("source_index_sha256"), identities["source_index"], "julia_receipt.source_index_sha256")
    require_value(julia.get("work_unit_manifest_sha256"), source_freeze["work_unit_manifest_sha256"], "julia_receipt.work_unit_manifest_sha256")
    require_value(julia.get("sounio_execution_receipt_sha256"), identities["sounio_execution_receipt"], "julia_receipt.sounio_execution_receipt_sha256")
    require_value(julia.get("sounio_output_manifest_sha256"), identities["sounio_output_manifest"], "julia_receipt.sounio_output_manifest_sha256")
    require_value(julia.get("rows_recomputed"), rows_emitted, "julia_receipt.rows_recomputed")
    require_value(julia.get("parquet_disagreements"), 0, "julia_receipt.parquet_disagreements")
    positive_integer(julia.get("parquet_rows_recomputed"), "julia_receipt.parquet_rows_recomputed")
    package_manifest_sha256s = julia.get("package_manifest_sha256s")
    if not isinstance(package_manifest_sha256s, dict) or not package_manifest_sha256s:
        raise GateError("julia_receipt.package_manifest_sha256s must be a non-empty object")
    for package_id, digest in package_manifest_sha256s.items():
        if not isinstance(package_id, str) or not package_id:
            raise GateError("julia_receipt package manifest IDs must be non-empty strings")
        require_sha(digest, f"julia_receipt.package_manifest_sha256s[{package_id}]")

    return {
        "documents": documents,
        "sha256": identities,
        "bindings": bindings,
        "provenance": provenance,
        "source_index_records": records,
        "rows_emitted": rows_emitted,
    }


def validate_agreement(report: dict[str, Any]) -> tuple[bool, dict[str, str], int, int]:
    require_value(report.get("schema_version"), "dosa-v3-u0-agreement-evidence-1", "agreement.schema_version")
    require_value(report.get("status"), "pass", "agreement.status")
    require_scope(report, "agreement", {"fixture", "u0_pilot"})
    require_value(report.get("canonical_producer"), "Sounio", "agreement.canonical_producer")
    require_value(report.get("independent_validator"), "Julia", "agreement.independent_validator")
    require_value(report.get("full_pilot_recomputed"), True, "agreement.full_pilot_recomputed")
    total = positive_integer(report.get("sounio_rows"), "agreement.sounio_rows")
    julia_rows = positive_integer(report.get("julia_rows"), "agreement.julia_rows")
    exact = positive_integer(report.get("byte_exact_rows"), "agreement.byte_exact_rows")
    disagreements = nonnegative_integer(report.get("disagreements"), "agreement.disagreements")
    require_value(report.get("absolute_tolerance"), 0, "agreement.absolute_tolerance")
    bindings = {
        key: require_sha(report.get(key), f"agreement.{key}")
        for key in (
            "parameters_sha256", "source_manifest_sha256", "payload_manifest_sha256",
            "sounio_attestation_sha256", "julia_receipt_sha256",
        )
    }
    return total == julia_rows == exact and disagreements == 0, bindings, total, exact


def validate_query(report: dict[str, Any]) -> tuple[bool, bool, dict[str, Any]]:
    require_value(report.get("schema_version"), "dosa-v3-u0-query-utility-evidence-1", "query.schema_version")
    require_value(report.get("status"), "pass", "query.status")
    require_scope(report, "query", {"fixture", "u0_pilot"})
    accession = require_accession(report.get("accession_version"), "query.accession_version")
    coordinate = require_coordinate(report.get("coordinate"), "query.coordinate")
    scale = require_scale(report.get("scale"), "query.scale")
    scale_value = int(scale)
    if coordinate[0] % scale_value != 0 or coordinate[1] - coordinate[0] > scale_value:
        raise GateError("query coordinate must be one aligned full or terminal-partial U0 window")
    transfer = nonnegative_integer(report.get("shard_download_bytes"), "query.shard_download_bytes")
    seconds = positive_number(report.get("post_download_query_seconds"), "query.post_download_query_seconds")
    shards = report.get("shards_read")
    if not isinstance(shards, list) or not shards or len(shards) != len(set(shards)):
        raise GateError("query.shards_read must be a non-empty unique list")
    for index, locator in enumerate(shards):
        require_public_locator(locator, f"query.shards_read[{index}]")
    source_manifest_url = require_public_https(report.get("source_manifest_public_url"), "query.source_manifest_public_url")
    require_public_https(report.get("source_integrity_public_url"), "query.source_integrity_public_url")
    source_locator = require_public_locator(report.get("source_locator"), "query.source_locator")
    sequence_sha = require_sha(report.get("sequence_sha256"), "query.sequence_sha256")
    normalized_sha = require_sha(report.get("normalized_sequence_sha256"), "query.normalized_sequence_sha256")
    raw_fasta_sha = require_sha(report.get("raw_fasta_asset_sha256"), "query.raw_fasta_asset_sha256")
    source_manifest_sha = require_sha(report.get("source_manifest_sha256"), "query.source_manifest_sha256")
    source_integrity_sha = require_sha(report.get("source_integrity_receipt_sha256"), "query.source_integrity_receipt_sha256")
    public_payload_manifest_sha = require_sha(report.get("public_payload_manifest_sha256"), "query.public_payload_manifest_sha256")
    package_manifest_sha = require_sha(report.get("package_manifest_sha256"), "query.package_manifest_sha256")
    package_manifest_id = report.get("package_manifest_id")
    if not isinstance(package_manifest_id, str) or not package_manifest_id:
        raise GateError("query.package_manifest_id must be a non-empty string")
    external_pass = all(
        report.get(key) is True
        for key in ("source_sequence_recovered", "source_sequence_sha256_verified", "payload_hashes_verified")
    ) and report.get("cluster_access_used") is False
    return transfer <= 5 * GIB and seconds <= 60.0, external_pass, {
        "accession": accession, "coordinate": coordinate, "scale": scale,
        "seconds": seconds, "transfer": transfer, "sequence_sha256": sequence_sha,
        "normalized_sequence_sha256": normalized_sha, "raw_fasta_asset_sha256": raw_fasta_sha,
        "source_manifest_sha256": source_manifest_sha,
        "source_integrity_receipt_sha256": source_integrity_sha,
        "public_payload_manifest_sha256": public_payload_manifest_sha,
        "package_manifest_sha256": package_manifest_sha,
        "package_manifest_id": package_manifest_id,
        "source_manifest_public_url": source_manifest_url,
        "source_locator": source_locator,
    }


def validate_speed(report: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    require_value(report.get("schema_version"), "dosa-v3-u0-speed-utility-evidence-1", "speed.schema_version")
    require_value(report.get("status"), "pass", "speed.status")
    require_scope(report, "speed", {"fixture", "u0_pilot"})
    require_value(report.get("canonical_producer"), "Sounio", "speed.canonical_producer")
    require_value(report.get("null_model"), "euler_wilson_fixed_endpoints_v1", "speed.null_model")
    require_value(report.get("null_replicates"), 1000, "speed.null_replicates")
    require_value(report.get("minimum_lookup_speedup"), 100.0, "speed.minimum_lookup_speedup")
    accession = require_accession(report.get("accession_version"), "speed.accession_version")
    coordinate = require_coordinate(report.get("coordinate"), "speed.coordinate")
    scale = require_scale(report.get("scale"), "speed.scale")
    lookup = positive_number(report.get("lookup_seconds"), "speed.lookup_seconds")
    recompute = positive_number(report.get("n1000_recompute_seconds"), "speed.n1000_recompute_seconds")
    declared_speedup = positive_number(report.get("lookup_speedup"), "speed.lookup_speedup")
    speedup = recompute / lookup
    if abs(declared_speedup - speedup) > max(1e-9, abs(speedup) * 1e-9):
        raise GateError("speed.lookup_speedup does not equal recompute/lookup")
    return speedup >= 100.0, {
        "accession": accession, "coordinate": coordinate, "scale": scale,
        "lookup": lookup, "recompute": recompute, "speedup": speedup,
        "sequence_sha256": require_sha(report.get("sequence_sha256"), "speed.sequence_sha256"),
        "parameters_sha256": require_sha(report.get("parameters_sha256"), "speed.parameters_sha256"),
        "sounio_output_sha256": require_sha(report.get("sounio_output_sha256"), "speed.sounio_output_sha256"),
        "sounio_runner_sha256": require_sha(report.get("sounio_runner_sha256"), "speed.sounio_runner_sha256"),
        "sounio_attestation_sha256": require_sha(report.get("sounio_attestation_sha256"), "speed.sounio_attestation_sha256"),
        "sounio_build_receipt_sha256": require_sha(report.get("sounio_build_receipt_sha256"), "speed.sounio_build_receipt_sha256"),
        "source_manifest_sha256": require_sha(report.get("source_manifest_sha256"), "speed.source_manifest_sha256"),
        "source_integrity_receipt_sha256": require_sha(report.get("source_integrity_receipt_sha256"), "speed.source_integrity_receipt_sha256"),
        "public_payload_manifest_sha256": require_sha(report.get("public_payload_manifest_sha256"), "speed.public_payload_manifest_sha256"),
        "package_manifest_sha256": require_sha(report.get("package_manifest_sha256"), "speed.package_manifest_sha256"),
        "package_manifest_id": report.get("package_manifest_id"),
        "attestation_scope": report.get("sounio_attestation_evidence_scope"),
    }


def validate_capacity(report: dict[str, Any]) -> tuple[bool, int, int, str, dict[str, str]]:
    require_value(report.get("schema_version"), "dosa-u0-capacity-projection-1", "capacity.schema_version")
    require_value(report.get("status"), "pass", "capacity.status")
    require_scope(report, "capacity", {"fixture", "u0_pilot"})
    pilot_rows = positive_integer(report.get("measured_pilot_rows"), "capacity.measured_pilot_rows")
    pilot_bytes = positive_integer(report.get("measured_parquet_bytes"), "capacity.measured_parquet_bytes")
    final_rows = positive_integer(report.get("projected_full_rows"), "capacity.projected_full_rows")
    projected = positive_integer(report.get("projected_full_parquet_bytes"), "capacity.projected_full_parquet_bytes")
    required = positive_integer(report.get("required_capacity_bytes"), "capacity.required_capacity_bytes")
    require_value(report.get("compression"), "zstd", "capacity.compression")
    require_value(report.get("safety_factor"), 2, "capacity.safety_factor")
    require_value(report.get("projection_basis"), "measured_u0_pilot_parquet", "capacity.projection_basis")
    require_value(report.get("parquet_footer_verified"), True, "capacity.parquet_footer_verified")
    by_scale = report.get("by_scale")
    if not isinstance(by_scale, list) or {require_scale(item.get("scale"), "capacity.by_scale.scale") for item in by_scale if isinstance(item, dict)} != ALLOWED_SCALES or len(by_scale) != 4:
        raise GateError("capacity.by_scale must contain exactly the four U0 scales")
    public_sha = require_sha(report.get("public_payload_manifest_sha256"), "capacity.public_payload_manifest_sha256")
    package_rows = report.get("package_manifests")
    package_hashes: dict[str, str] = {}
    if not isinstance(package_rows, list) or not package_rows:
        raise GateError("capacity.package_manifests must be a non-empty list")
    for row in package_rows:
        if not isinstance(row, dict):
            raise GateError("capacity package manifest row must be an object")
        package_id = row.get("package_manifest_id")
        if not isinstance(package_id, str) or not package_id or package_id in package_hashes:
            raise GateError("capacity package manifest IDs must be unique")
        package_hashes[package_id] = require_sha(row.get("manifest_sha256"), f"capacity.package_manifests[{package_id}].manifest_sha256")
        positive_integer(row.get("manifest_bytes"), f"capacity.package_manifests[{package_id}].manifest_bytes")
    return final_rows >= pilot_rows and required >= 2 * projected, projected, required, public_sha, package_hashes


def validate_field_audit(report: dict[str, Any]) -> bool:
    require_value(report.get("schema_version"), "dosa-v3-field-utility-audit-1", "field_audit.schema_version")
    require_value(report.get("status"), "pass", "field_audit.status")
    require_scope(report, "field_audit", {"fixture", "u0_pilot"})
    published = positive_integer(report.get("published_fields"), "field_audit.published_fields")
    accounted = positive_integer(report.get("fields_with_demonstrated_use_or_removed"), "field_audit.fields_with_demonstrated_use_or_removed")
    return accounted == published and report.get("unaccounted_fields") == [] and report.get("ambiguously_accounted_fields") == [] and report.get("unused_rules") == []


def validate_scientific(report: dict[str, Any], role: str) -> tuple[bool, bool]:
    expected_kind = {
        "oric": "dosa_oric_terminus_secondary_gate",
        "model": "dosa_rc_equivariance_secondary_benchmark",
    }[role]
    require_value(report.get("kind"), expected_kind, f"{role}.kind")
    scope = require_scope(report, role, {"fixture", "held_out_grouped_cohort"})
    status = report.get("status")
    metric_status = report.get("metric_status")
    if status not in ("PASS", "FAIL", "REFUSE") or metric_status not in ("PASS", "FAIL"):
        raise GateError(f"{role} has an invalid status")
    if role == "oric":
        require_value(report.get("baseline"), "gc_skew+dinucleotide_skew+dnaa_motifs", "oric.baseline")
        require_value(report.get("dosa_model"), "gc_skew+dinucleotide_skew+dnaa_motifs+dosa", "oric.dosa_model")
        bootstrap = report.get("bootstrap")
        if not isinstance(bootstrap, dict):
            raise GateError("oric.bootstrap must be an object")
        require_value(bootstrap.get("algorithm"), "splitmix64_modulo_split_group_cluster_median_v1", "oric.bootstrap.algorithm")
        require_value(bootstrap.get("seed"), "0xD05A0C1A20260814", "oric.bootstrap.seed")
        require_value(bootstrap.get("replicates"), 1000, "oric.bootstrap.replicates")
        require_value(bootstrap.get("ci_lower_quantile"), 0.025, "oric.bootstrap.ci_lower_quantile")
        positive_integer(report.get("oof_records"), "oric.oof_records")
        positive_integer(report.get("split_groups"), "oric.split_groups")
        median = finite_number(report.get("median_relative_error_reduction"), "oric.median_relative_error_reduction")
        lower = finite_number(report.get("bootstrap_ci_lower"), "oric.bootstrap_ci_lower")
        metric_pass = median >= 0.10 and lower > 0.0
    else:
        require_value(report.get("transformations"), ["R", "RC", "ORIGIN_SHIFT"], "model.transformations")
        require_value(report.get("auroc_contract"), "rank_sum_average_ties_float64_v1", "model.auroc_contract")
        bootstrap = report.get("bootstrap")
        if not isinstance(bootstrap, dict):
            raise GateError("model.bootstrap must be an object")
        require_value(bootstrap.get("algorithm"), "splitmix64_stratified_case_paired_delta_v1", "model.bootstrap.algorithm")
        require_value(bootstrap.get("seed"), "0xD05A0A0C20260814", "model.bootstrap.seed")
        require_value(bootstrap.get("replicates"), 1000, "model.bootstrap.replicates")
        require_value(bootstrap.get("ci_quantiles"), [0.025, 0.975], "model.bootstrap.ci_quantiles")
        positive_integer(report.get("held_out_cases"), "model.held_out_cases")
        auroc = finite_number(report.get("rc_equivariant_auroc"), "model.rc_equivariant_auroc")
        if not 0.0 <= auroc <= 1.0:
            raise GateError("model.rc_equivariant_auroc must be within [0, 1]")
        finite_number(report.get("non_equivariant_auroc"), "model.non_equivariant_auroc")
        finite_number(report.get("paired_delta_ci_lower"), "model.paired_delta_ci_lower")
        finite_number(report.get("paired_delta_ci_upper"), "model.paired_delta_ci_upper")
        metric_pass = auroc >= 0.90
    if metric_status != ("PASS" if metric_pass else "FAIL"):
        raise GateError(f"{role} metric_status does not match its declared metric threshold")
    if scope == "fixture":
        if report.get("scientific_claim_permitted") is not False:
            raise GateError(f"{role} fixture must forbid scientific claims")
        expected_status = "REFUSE" if metric_pass else "FAIL"
        if status != expected_status:
            raise GateError(f"{role} fixture status is not coherent with its recomputed metric")
        return metric_pass, False
    require_value(report.get("evaluator_language"), "Julia", f"{role}.evaluator_language")
    require_sha(report.get("evaluator_sha256"), f"{role}.evaluator_sha256")
    require_sha(report.get("input_predictions_sha256"), f"{role}.input_predictions_sha256")
    expected_status = "PASS" if metric_pass else "FAIL"
    if status != expected_status or report.get("scientific_claim_permitted") is not metric_pass:
        raise GateError(f"{role} held-out status/claim is not coherent with its recomputed metric")
    return metric_pass, metric_pass


def evaluate(
    reports: dict[str, dict[str, Any]],
    bindings: list[dict[str, Any]],
    core: dict[str, Any],
    pilot: dict[str, Any] | None = None,
) -> dict[str, Any]:
    agreement_pass, common, total, exact = validate_agreement(reports["agreement"])
    query_pass, external_pass, query = validate_query(reports["query"])
    speed_pass, speed = validate_speed(reports["speed"])
    capacity_pass, projected_bytes, required_bytes, capacity_public_sha, capacity_packages = validate_capacity(reports["capacity"])
    field_pass = validate_field_audit(reports["field_audit"])
    oric_metric_pass, oric_real_pass = validate_scientific(reports["oric"], "oric")
    model_metric_pass, model_real_pass = validate_scientific(reports["model"], "model")
    scientific_pass = oric_real_pass or model_real_pass

    if query["accession"] != speed["accession"] or query["coordinate"] != speed["coordinate"] or query["scale"] != speed["scale"]:
        raise GateError("query and speed reports are not bound to the same exact window")
    if query["sequence_sha256"] != speed["sequence_sha256"] or query["seconds"] != speed["lookup"]:
        raise GateError("query and speed reports disagree on sequence or lookup measurement")
    if common["parameters_sha256"] != speed["parameters_sha256"]:
        raise GateError("agreement and speed reports disagree on parameters SHA-256")
    if common["source_manifest_sha256"] != query["source_manifest_sha256"]:
        raise GateError("agreement and query reports disagree on source manifest SHA-256")
    if common["payload_manifest_sha256"] != query["public_payload_manifest_sha256"]:
        raise GateError("agreement and query reports disagree on payload manifest SHA-256")
    if common["sounio_attestation_sha256"] != speed["sounio_attestation_sha256"]:
        raise GateError("agreement and speed reports disagree on Sounio attestation SHA-256")
    for key in ("source_manifest_sha256", "source_integrity_receipt_sha256", "public_payload_manifest_sha256", "package_manifest_sha256", "package_manifest_id"):
        if query[key] != speed[key]:
            raise GateError(f"query and speed reports disagree on {key}")
    core_sha = core["sha256"]
    expected_core = {
        "parameters_sha256": core_sha["parameters"],
        "source_manifest_sha256": core_sha["source_manifest"],
        "payload_manifest_sha256": core_sha["payload_manifest"],
        "sounio_attestation_sha256": core_sha["sounio_attestation"],
        "julia_receipt_sha256": core_sha["julia_receipt"],
    }
    if common != expected_core:
        raise GateError("agreement report is not bound to the supplied immutable core artifacts")
    if query["source_integrity_receipt_sha256"] != core_sha["source_integrity"]:
        raise GateError("query report is not bound to the supplied source integrity receipt")
    if core["package_manifests"].get(query["package_manifest_id"]) != query["package_manifest_sha256"]:
        raise GateError("query package manifest is not referenced by the supplied public payload manifest")
    if capacity_public_sha != core_sha["payload_manifest"] or capacity_packages != core["package_manifests"]:
        raise GateError("capacity report is not bound to the complete public package-manifest closure")
    operational_roles = ("agreement", "query", "speed", "capacity", "field_audit")
    real_scope = all(reports[role].get("evidence_scope") == "u0_pilot" for role in operational_roles)
    if real_scope:
        # Defense in depth for library callers: the CLI enforces this before
        # loading real evidence, and the adjudicator repeats it before any
        # status can be derived.
        enforce_u0_promotion_lock()
    if real_scope and pilot is None:
        raise GateError("u0_pilot scope requires a provenance-closed real evidence root")
    if not real_scope and pilot is not None:
        raise GateError("real pilot provenance cannot be mixed with fixture operational evidence")
    attestation = core["documents"]["sounio_attestation"]
    if attestation["executable_sha256"] != speed["sounio_runner_sha256"]:
        raise GateError("speed report runner is not the executable bound by the Sounio attestation")
    if attestation["receipt_sha256"] != speed["sounio_build_receipt_sha256"]:
        raise GateError("speed report is not bound to the Sounio build receipt")
    expected_attestation_scope = "build-provenance-only-non-semantic" if real_scope else "fixture-only-non-semantic"
    if speed["attestation_scope"] != expected_attestation_scope or attestation["evidence_scope"] != expected_attestation_scope:
        raise GateError("Sounio attestation scope does not match evidence scope")
    integrity_records = core["documents"]["source_integrity"]["records"]
    integrity_matches = [
        row for row in integrity_records
        if isinstance(row, dict) and row.get("sequence_accession_version") == query["accession"]
    ]
    if len(integrity_matches) != 1 or integrity_matches[0].get("normalized_fasta_sha256") != query["normalized_sequence_sha256"]:
        raise GateError("query normalized sequence is not bound by source integrity")
    require_value(
        core["documents"]["julia_receipt"].get("rows_recomputed"), total,
        "julia_receipt.rows_recomputed",
    )

    if real_scope:
        assert pilot is not None
        require_value(
            core["documents"]["payload_manifest"].get("release_state"),
            "u0_pilot_evidence",
            "payload_manifest.release_state",
        )
        package_closure = validate_package_closure(pilot["evidence_root"], core, pilot)
        recompute_capacity_report(
            package_closure["package_directories"],
            pilot["provenance"]["paths"]["full_replicon_inventory"],
            pilot["provenance"]["paths"]["payload_manifest"],
            reports["capacity"],
        )
        require_value(package_closure["parquet_rows"], pilot["rows_emitted"], "Parquet/Sounio logical row count")
        require_value(
            core["documents"]["julia_receipt"].get("package_manifest_sha256s"),
            package_closure["package_manifest_sha256s"],
            "julia_receipt.package_manifest_sha256s",
        )
        require_value(
            core["documents"]["julia_receipt"].get("parquet_rows_recomputed"),
            package_closure["parquet_rows"],
            "julia_receipt.parquet_rows_recomputed",
        )
        require_value(total, pilot["rows_emitted"], "agreement/Sounio output rows")
        require_value(
            reports["agreement"].get("source_index_sha256"),
            pilot["sha256"]["source_index"],
            "agreement.source_index_sha256",
        )
        require_value(
            reports["agreement"].get("sounio_execution_receipt_sha256"),
            pilot["sha256"]["sounio_execution_receipt"],
            "agreement.sounio_execution_receipt_sha256",
        )
        require_value(
            reports["agreement"].get("sounio_output_manifest_sha256"),
            pilot["sha256"]["sounio_output_manifest"],
            "agreement.sounio_output_manifest_sha256",
        )

        source = core["documents"]["source_manifest"]
        required_source_keys = {
            "schema_version", "manifest_id", "retrieved_utc", "source_provider",
            "query", "acquisition_tools", "package", "selected_records", "package_assets",
        }
        if set(source) != required_source_keys:
            raise GateError("real U0 source manifest must satisfy the full v3 source contract")
        selected = [
            row for row in source["selected_records"]
            if isinstance(row, dict) and row.get("sequence_accession_version") == query["accession"]
        ]
        if len(selected) != 1:
            raise GateError("real U0 source manifest lacks exactly one queried selected record")
        selected_row = selected[0]
        selected_keys = {
            "source_record_id", "replicon_id", "assembly_accession_version",
            "sequence_accession_version", "required_asset_kinds",
        }
        if set(selected_row) != selected_keys or selected_row["required_asset_kinds"] != ["fasta", "gbff", "sequence_report"]:
            raise GateError("real U0 selected source record keys or asset contract mismatch")
        source_record_id = selected_row["source_record_id"]
        assembly = selected_row["assembly_accession_version"]
        fasta_assets = [
            row for row in source["package_assets"]
            if isinstance(row, dict) and row.get("asset_kind") == "fasta"
            and row.get("assembly_accession_version") == assembly
            and isinstance(row.get("selected_record_ids"), list)
            and source_record_id in row["selected_record_ids"]
        ]
        if len(fasta_assets) != 1:
            raise GateError("real U0 source manifest lacks exactly one queried FASTA asset")
        fasta_asset = fasta_assets[0]
        require_value(fasta_asset.get("sha256"), query["raw_fasta_asset_sha256"], "query/source FASTA asset SHA-256")

        source_index_record = pilot["source_index_records"].get(query["accession"])
        if not isinstance(source_index_record, dict):
            raise GateError("real U0 source index lacks the queried accession.version")
        require_value(
            source_index_record.get("canonical_sequence_input_sha256"),
            query["sequence_sha256"],
            "query/source index canonical sequence SHA-256",
        )
        require_value(
            source_index_record.get("normalized_sequence_sha256"),
            query["normalized_sequence_sha256"],
            "query/source index normalized sequence SHA-256",
        )
        locator = source_index_record.get("locator")
        resolved_locator = locator if isinstance(locator, str) and locator.startswith("https://") else urljoin(
            query["source_manifest_public_url"], str(locator)
        )
        require_value(resolved_locator, query["source_locator"], "query/source index public locator")

        integrity_matches = [
            row for row in integrity_records
            if isinstance(row, dict) and row.get("sequence_accession_version") == query["accession"]
        ]
        if len(integrity_matches) != 1:
            raise GateError("real U0 source integrity lacks exactly one queried record")
        integrity_row = integrity_matches[0]
        integrity_keys = {
            "source_record_id", "sequence_accession_version", "assembly_accession_version",
            "normalized_fasta_length_bp", "normalized_fasta_sha256",
            "canonical_sequence_input_sha256", "fasta_asset_sha256",
        }
        if set(integrity_row) != integrity_keys:
            raise GateError("real U0 source integrity record keys mismatch")
        require_value(integrity_row.get("source_record_id"), source_record_id, "source integrity source_record_id")
        require_value(integrity_row.get("assembly_accession_version"), assembly, "source integrity assembly")
        require_value(integrity_row.get("normalized_fasta_sha256"), query["normalized_sequence_sha256"], "source integrity normalized SHA-256")
        require_value(integrity_row.get("canonical_sequence_input_sha256"), query["sequence_sha256"], "source integrity canonical SHA-256")
        require_value(integrity_row.get("fasta_asset_sha256"), query["raw_fasta_asset_sha256"], "source integrity FASTA asset SHA-256")
        sequence_length = positive_integer(integrity_row.get("normalized_fasta_length_bp"), "source integrity sequence length")
        if sequence_length < query["coordinate"][1]:
            raise GateError("queried window exceeds the source-integrity sequence length")
        query_width = query["coordinate"][1] - query["coordinate"][0]
        if query_width < int(query["scale"]) and query["coordinate"][1] != sequence_length:
            raise GateError("a partial query window is permitted only at the exact sequence terminus")

        for role, evaluator in (("oric", ORIC_EVALUATOR), ("model", MODEL_EVALUATOR)):
            report = reports[role]
            input_role = f"{role}_input"
            require_value(
                report.get("input_predictions_sha256"),
                pilot["sha256"][input_role],
                f"{role}.input_predictions_sha256",
            )
            require_value(
                report.get("evaluator_sha256"),
                sha256_file(evaluator),
                f"{role}.evaluator_sha256",
            )
        recompute_scientific_reports(
            pilot["julia_bin"],
            reports,
            pilot["scientific_inputs"],
            core["documents"]["julia_receipt"],
        )
        bindings.extend(pilot["bindings"])
        bindings.append(
            {
                "role": "pilot_provenance",
                "name": pilot["provenance"]["path"],
                "bytes": pilot["provenance"]["bytes"],
                "sha256": pilot["provenance"]["sha256"],
            }
        )

    checks = {
        "sounio_julia_full_agreement": agreement_pass,
        "query_transfer_le_5_gib_and_time_le_60_seconds": query_pass,
        "lookup_speedup_ge_100": speed_pass,
        "external_source_and_hash_verification": external_pass,
        "parquet_projection_with_2x_margin": capacity_pass,
        "public_field_utility_audit": field_pass,
        "at_least_one_secondary_scientific_test": oric_metric_pass or model_metric_pass,
    }
    mandatory_pass = all(value for key, value in checks.items() if key != "at_least_one_secondary_scientific_test")
    all_metric_pass = mandatory_pass and (oric_metric_pass or model_metric_pass)
    all_pass = mandatory_pass and scientific_pass
    status = "PASS" if all_pass and real_scope else "BLOCKED"
    reason = None
    if all_metric_pass and not real_scope:
        reason = "FIXTURE_EVIDENCE_CANNOT_PASS_U0"
    elif not all_pass:
        reason = "U0_REQUIREMENT_FAILED"
    return {
        "schema_version": "dosa-u0-gate-receipt-1",
        "status": status,
        "reason_code": reason,
        "evidence_scope": "u0_pilot" if real_scope else "mixed_or_fixture",
        "checks": checks,
        "measured": {
            "sounio_rows": total,
            "byte_exact_rows": exact,
            "shard_download_bytes": query["transfer"],
            "post_download_query_seconds": query["seconds"],
            "lookup_seconds": speed["lookup"],
            "n1000_recompute_seconds": speed["recompute"],
            "lookup_speedup": speed["speedup"],
            "projected_full_parquet_bytes": projected_bytes,
            "required_capacity_bytes": required_bytes,
            "oric_metric_pass": oric_metric_pass,
            "oric_scientific_pass": oric_real_pass,
            "model_metric_pass": model_metric_pass,
            "model_scientific_pass": model_real_pass,
        },
        "evidence": bindings,
        "full_atlas_authorized": status == "PASS",
        "hdd_purchase_evaluation_authorized": status == "PASS",
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("agreement", "query", "speed", "capacity", "field-audit", "oric", "model"):
        parser.add_argument(f"--{name}", required=True, type=pathlib.Path)
    for name in (
        "parameters", "source-manifest", "source-integrity", "payload-manifest",
        "sounio-attestation", "sounio-build-receipt", "julia-receipt",
    ):
        parser.add_argument(f"--{name}", required=True, type=pathlib.Path)
    parser.add_argument("--evidence-root", type=pathlib.Path)
    parser.add_argument("--pilot-provenance", type=pathlib.Path)
    parser.add_argument("--source-index", type=pathlib.Path)
    parser.add_argument("--sounio-execution-receipt", type=pathlib.Path)
    parser.add_argument("--sounio-output-manifest", type=pathlib.Path)
    parser.add_argument("--oric-input", type=pathlib.Path)
    parser.add_argument("--model-input", type=pathlib.Path)
    parser.add_argument("--selection", type=pathlib.Path)
    parser.add_argument("--control-candidates", type=pathlib.Path)
    parser.add_argument("--control-ledger", type=pathlib.Path)
    parser.add_argument("--control-binding-receipt", type=pathlib.Path)
    parser.add_argument("--control-validation-receipt", type=pathlib.Path)
    parser.add_argument("--source-freeze-receipt", type=pathlib.Path)
    parser.add_argument("--assembly-report", type=pathlib.Path)
    parser.add_argument("--sequence-report", type=pathlib.Path)
    parser.add_argument("--full-replicon-inventory", type=pathlib.Path)
    parser.add_argument("--work-unit-manifest", type=pathlib.Path)
    parser.add_argument("--julia-bin", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    return parser


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def main() -> int:
    args = build_parser().parse_args()
    paths = {
        "agreement": args.agreement,
        "query": args.query,
        "speed": args.speed,
        "capacity": args.capacity,
        "field_audit": args.field_audit,
        "oric": args.oric,
        "model": args.model,
    }
    core_paths = {
        "parameters": args.parameters,
        "source_manifest": args.source_manifest,
        "source_integrity": args.source_integrity,
        "payload_manifest": args.payload_manifest,
        "sounio_attestation": args.sounio_attestation,
        "sounio_build_receipt": args.sounio_build_receipt,
        "julia_receipt": args.julia_receipt,
    }
    try:
        reports, bindings = check_inputs(paths)
        core, core_bindings = check_core_artifacts(core_paths)
        pilot: dict[str, Any] | None = None
        real_scope = all(
            reports[role].get("evidence_scope") == "u0_pilot"
            for role in ("agreement", "query", "speed", "capacity", "field_audit")
        )
        pilot_arguments = {
            "evidence_root": args.evidence_root,
            "pilot_provenance": args.pilot_provenance,
            "source_index": args.source_index,
            "sounio_execution_receipt": args.sounio_execution_receipt,
            "sounio_output_manifest": args.sounio_output_manifest,
            "oric_input": args.oric_input,
            "model_input": args.model_input,
            "selection": args.selection,
            "control_candidates": args.control_candidates,
            "control_ledger": args.control_ledger,
            "control_binding_receipt": args.control_binding_receipt,
            "control_validation_receipt": args.control_validation_receipt,
            "source_freeze_receipt": args.source_freeze_receipt,
            "assembly_report": args.assembly_report,
            "sequence_report": args.sequence_report,
            "full_replicon_inventory": args.full_replicon_inventory,
            "work_unit_manifest": args.work_unit_manifest,
            "julia_bin": args.julia_bin,
        }
        if real_scope:
            missing = sorted(name for name, value in pilot_arguments.items() if value is None)
            if missing:
                raise GateError("u0_pilot evidence is missing provenance arguments: " + ",".join(missing))
            assert all(value is not None for value in pilot_arguments.values())
            enforce_u0_promotion_lock()
            extra_json_paths = {
                "source_index": args.source_index,
                "sounio_execution_receipt": args.sounio_execution_receipt,
                "sounio_output_manifest": args.sounio_output_manifest,
            }
            supplied = {
                **paths,
                **core_paths,
                **extra_json_paths,
                "oric_input": args.oric_input,
                "model_input": args.model_input,
                "selection": args.selection,
                "control_candidates": args.control_candidates,
                "control_ledger": args.control_ledger,
                "control_binding_receipt": args.control_binding_receipt,
                "control_validation_receipt": args.control_validation_receipt,
                "source_freeze_receipt": args.source_freeze_receipt,
                "assembly_report": args.assembly_report,
                "sequence_report": args.sequence_report,
                "full_replicon_inventory": args.full_replicon_inventory,
                "work_unit_manifest": args.work_unit_manifest,
            }
            provenance = validate_pilot_provenance(args.evidence_root, args.pilot_provenance, supplied)
            source_freeze = validate_source_freeze_closure(args.evidence_root, provenance, core)
            pilot = validate_real_pilot_artifacts(extra_json_paths, args.evidence_root, core, provenance, source_freeze)
            pilot.update(source_freeze)
            pilot["evidence_root"] = args.evidence_root
            pilot["julia_bin"] = args.julia_bin
            pilot["scientific_inputs"] = {"oric_input": args.oric_input, "model_input": args.model_input}
            for role, input_path in (("oric_input", args.oric_input), ("model_input", args.model_input)):
                if input_path.is_symlink() or not input_path.is_file():
                    raise GateError(f"real U0 scientific input must be a regular non-symlink file: {role}")
                pilot["sha256"][role] = sha256_file(input_path)
                pilot["bindings"].append(
                    {"role": role, "name": input_path.name, "bytes": input_path.stat().st_size, "sha256": pilot["sha256"][role]}
                )
        elif any(value is not None for value in pilot_arguments.values()):
            raise GateError("fixture or mixed evidence must not supply real-pilot provenance arguments")
        receipt = evaluate(reports, bindings + core_bindings, core, pilot)
        encoded = canonical(receipt) + "\n"
        if args.output:
            if args.output.exists():
                raise GateError(f"refusing to overwrite output: {args.output}")
            args.output.write_text(encoded, encoding="utf-8")
        sys.stdout.write(encoded)
        return 0 if receipt["status"] == "PASS" else EXIT_BLOCKED
    except (GateError, OSError) as exc:
        sys.stdout.write(canonical({"schema_version": "dosa-u0-gate-receipt-1", "status": "BLOCKED", "reason_code": "INVALID_EVIDENCE", "message": str(exc)}) + "\n")
        return EXIT_BLOCKED


if __name__ == "__main__":
    raise SystemExit(main())
