#!/usr/bin/env python3
"""Close a manifest-directed Sounio execution with deterministic receipts.

This script computes no scientific metric. It verifies the completed shard
ledger and emits a build receipt, runner attestation, logical output manifest,
and execution receipt. Fixture scope remains explicitly non-promotable; a real
pilot still requires the independent Julia receipt and the complete U0 gate.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile
from collections import Counter
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from build_u0_work_unit_case import (  # noqa: E402
    inspect_selected_work_unit,
    reject_symlink_components,
    validated_manifest_rows,
)


LEDGER_HEADER = (
    "run_id", "plan_sha256", "work_unit_id", "sequence_accession_version",
    "scale", "start_window", "rows", "status", "reason_code", "case_path",
    "case_sha256", "artifact_path", "artifact_sha256", "artifact_size_bytes",
)
SHA_RE = re.compile(r"[0-9a-f]{64}")
COMMIT_RE = re.compile(r"[0-9a-f]{40}")
ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
SCOPES = {"fixture-only-nonpromotable", "u0_pilot"}


class FinalizationError(RuntimeError):
    pass


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def regular(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink_components(path, label)
    if path.is_symlink() or not path.is_file():
        raise FinalizationError(f"{label} must be a regular non-symlink file")
    return path.resolve(strict=True)


def directory(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink_components(path, label)
    if path.is_symlink() or not path.is_dir():
        raise FinalizationError(f"{label} must be a real non-symlink directory")
    return path.resolve(strict=True)


def below(root: pathlib.Path, target: pathlib.Path, label: str) -> str:
    resolved = regular(target, label)
    try:
        return resolved.relative_to(root).as_posix()
    except ValueError as exc:
        raise FinalizationError(f"{label} must be below the evidence root") from exc


def strict_json(path: pathlib.Path, label: str) -> dict[str, Any]:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ValueError(f"duplicate key: {key}")
            value[key] = item
        return value

    try:
        value = json.loads(regular(path, label).read_bytes(), object_pairs_hook=unique)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise FinalizationError(f"{label} is not strict JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise FinalizationError(f"{label} must be a JSON object")
    return value


def read_ledger(path: pathlib.Path, execution_root: pathlib.Path, evidence_root: pathlib.Path) -> tuple[str, list[dict[str, Any]], list[dict[str, Any]]]:
    raw = regular(path, "execution ledger").read_bytes()
    if not raw.endswith(b"\n") or b"\r" in raw:
        raise FinalizationError("execution ledger must be LF-only with terminal LF")
    reader = csv.DictReader(raw.decode("ascii").splitlines(), delimiter="\t")
    if tuple(reader.fieldnames or ()) != LEDGER_HEADER:
        raise FinalizationError("execution ledger header drift")
    run_id = ""
    artifacts: list[dict[str, Any]] = []
    ledger_rows: list[dict[str, Any]] = []
    seen_artifacts: set[str] = set()
    for ordinal, row in enumerate(reader, start=2):
        if set(row) != set(LEDGER_HEADER) or any(row[key] is None for key in LEDGER_HEADER):
            raise FinalizationError(f"execution ledger row {ordinal} is incomplete")
        run_id = run_id or row["run_id"]
        if row["run_id"] != run_id or ID_RE.fullmatch(run_id) is None:
            raise FinalizationError("execution ledger run_id drift")
        ledger_rows.append(row)
        if row["status"] == "excluded":
            if row["rows"] != "0" or row["reason_code"] != "PARTIAL_WINDOW":
                raise FinalizationError("excluded work-unit row drift")
            continue
        if row["status"] != "complete" or row["reason_code"]:
            raise FinalizationError("completed work-unit row drift")
        try:
            expected_rows = int(row["rows"])
            expected_size = int(row["artifact_size_bytes"])
        except ValueError as exc:
            raise FinalizationError("execution ledger numeric drift") from exc
        artifact_relative = pathlib.PurePosixPath(row["artifact_path"])
        if artifact_relative.is_absolute() or not artifact_relative.parts or any(part in ("", ".", "..") for part in artifact_relative.parts):
            raise FinalizationError(f"artifact path is unsafe at row {ordinal}")
        artifact = regular(execution_root.joinpath(*artifact_relative.parts), f"artifact row {ordinal}")
        relative = below(evidence_root, artifact, f"artifact row {ordinal}")
        if relative in seen_artifacts:
            raise FinalizationError("duplicate Sounio artifact path")
        seen_artifacts.add(relative)
        raw_artifact = artifact.read_bytes()
        if len(raw_artifact) != expected_size or sha256_bytes(raw_artifact) != row["artifact_sha256"]:
            raise FinalizationError(f"artifact bytes mismatch at row {ordinal}")
        if not raw_artifact.endswith(b"\n") or b"\r" in raw_artifact or len(raw_artifact.splitlines()) != expected_rows:
            raise FinalizationError(f"artifact grammar or rows drift at row {ordinal}")
        artifacts.append({
            "path": relative,
            "media_type": "application/x-ndjson",
            "sha256": row["artifact_sha256"],
            "size_bytes": expected_size,
            "rows": expected_rows,
        })
    if not run_id or not artifacts:
        raise FinalizationError("execution ledger has no completed artifacts")
    return run_id, ledger_rows, sorted(artifacts, key=lambda item: str(item["path"]))


def finalize(args: argparse.Namespace) -> None:
    evidence_root = directory(args.evidence_root, "evidence root")
    parameters = regular(args.parameters, "parameters")
    manifest = regular(args.manifest, "work-unit manifest")
    source_manifest = regular(args.source_manifest, "source manifest")
    source_root = directory(args.source_root, "source root")
    execution_root = directory(args.execution_root, "execution root")
    plan = strict_json(args.plan_directory / "work_shard_plan.json", "work-shard plan")
    executable = regular(args.sounio_executable, "Sounio executable")
    compiler = regular(args.sounio_compiler, "Sounio compiler")
    source = regular(args.sounio_source, "Sounio source")
    if args.evidence_scope not in SCOPES:
        raise FinalizationError("unsupported evidence scope")
    if args.evidence_scope == "u0_pilot":
        if source_manifest == manifest:
            raise FinalizationError("u0_pilot scope requires a distinct frozen source manifest")
        source_document = strict_json(source_manifest, "real-pilot source manifest")
        if source_document.get("schema_version") != "3.0.0" or source_document.get("source_provider") != "NCBI_Datasets":
            raise FinalizationError("u0_pilot source manifest is not a frozen NCBI Datasets manifest")
        selected = source_document.get("selected_records")
        if not isinstance(selected, list) or not selected:
            raise FinalizationError("u0_pilot source manifest has no selected records")
    if COMMIT_RE.fullmatch(args.sounio_commit) is None:
        raise FinalizationError("Sounio commit must be lowercase 40-hex")
    if args.repository_url != "https://github.com/sounio-lang/sounio.git":
        raise FinalizationError("Sounio repository URL is not canonical")
    output = args.output_directory
    reject_symlink_components(output.parent, "output parent")
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise FinalizationError("output directory must be absent below an existing directory")

    parameters_sha = sha256_file(parameters)
    manifest_sha = sha256_file(manifest)
    source_manifest_sha = sha256_file(source_manifest)
    manifest_rows = validated_manifest_rows(manifest, parameters_sha)
    run_id, ledger_rows, artifacts = read_ledger(execution_root / "execution_ledger.tsv", execution_root, evidence_root)
    if plan.get("run_id") != run_id or plan.get("parameters_sha256") != parameters_sha or plan.get("work_unit_manifest_sha256") != manifest_sha:
        raise FinalizationError("plan identity does not match execution inputs")

    completed = Counter()
    exclusions: dict[str, str] = {}
    for row in ledger_rows:
        if row["status"] == "complete":
            completed[row["work_unit_id"]] += int(row["rows"])
        else:
            exclusions[row["work_unit_id"]] = row["reason_code"]
    work_units: list[dict[str, Any]] = []
    rows_emitted = 0
    for row in manifest_rows:
        inspected, sequence, observed_parameters = inspect_selected_work_unit(
            parameters, manifest, source_root, row["work_unit_id"]
        )
        if inspected != row or observed_parameters != parameters_sha:
            raise FinalizationError("manifest/source inspection drift")
        expected_rows = len(sequence) // int(row["scale"])
        observed_rows = completed.get(row["work_unit_id"], 0)
        if expected_rows > 0:
            if observed_rows != expected_rows or row["work_unit_id"] in exclusions:
                raise FinalizationError(f"incomplete work-unit coverage: {row['work_unit_id']}")
            status, reason = "complete", None
        else:
            if observed_rows != 0 or exclusions.get(row["work_unit_id"]) != "PARTIAL_WINDOW":
                raise FinalizationError(f"missing reason-coded exclusion: {row['work_unit_id']}")
            status, reason = "excluded", "PARTIAL_WINDOW"
        work_units.append({
            "work_unit_id": row["work_unit_id"],
            "sequence_accession_version": row["sequence_accession_version"],
            "scale": int(row["scale"]),
            "rows_emitted": observed_rows,
            "status": status,
            "reason_code": reason,
        })
        rows_emitted += observed_rows

    temporary = pathlib.Path(tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=output.parent))
    try:
        source_sha = sha256_file(source)
        compiler_sha = sha256_file(compiler)
        executable_sha = sha256_file(executable)
        build = {
            "schema_version": "dosa-v3-sounio-build-receipt-1",
            "receipt_id": f"{run_id}-sounio-build",
            "evidence_scope": "build-provenance-only-non-semantic",
            "status": "PASS",
            "repository_url": args.repository_url,
            "source_commit": args.sounio_commit,
            "source_path": "sounio/src/u0_work_shard_executor.sio",
            "source_sha256": source_sha,
            "compiler_sha256": compiler_sha,
            "executable_sha256": executable_sha,
            "build_exit_code": 0,
            "source_dirty": False,
            "scientific_semantics_validated": False,
        }
        build_path = temporary / "sounio-build-receipt.json"
        build_path.write_bytes(canonical_json(build))
        attestation = {
            "attestation_version": "dosa-v3-sounio-runner-attestation-1",
            "evidence_scope": "build-provenance-only-non-semantic",
            "repository_url": args.repository_url,
            "source_commit": args.sounio_commit,
            "source_sha256": source_sha,
            "compiler_sha256": compiler_sha,
            "executable_sha256": executable_sha,
            "receipt_path": "sounio-build-receipt.json",
            "receipt_sha256": sha256_file(build_path),
        }
        attestation_path = temporary / "sounio-attestation.json"
        attestation_path.write_bytes(canonical_json(attestation))
        output_manifest = {
            "schema_version": "dosa-v3-u0-sounio-output-manifest-1",
            "parameters_sha256": parameters_sha,
            "source_manifest_sha256": source_manifest_sha,
            "work_unit_manifest_sha256": manifest_sha,
            "work_units_expected": len(work_units),
            "work_units_completed": len(work_units),
            "rows_emitted": rows_emitted,
            "all_work_units_complete": True,
            "work_units": work_units,
            "artifacts": artifacts,
        }
        output_manifest_path = temporary / "sounio-output-manifest.json"
        output_manifest_path.write_bytes(canonical_json(output_manifest))
        execution = {
            "schema_version": "dosa-v3-u0-sounio-execution-receipt-1",
            "receipt_id": f"{run_id}-sounio-execution",
            "evidence_scope": args.evidence_scope,
            "status": "PASS",
            "canonical_producer": "Sounio",
            "null_model": "euler_wilson_fixed_endpoints_v1",
            "null_replicates": 1000,
            "parameters_sha256": parameters_sha,
            "source_manifest_sha256": source_manifest_sha,
            "work_unit_manifest_sha256": manifest_sha,
            "sounio_attestation_sha256": sha256_file(attestation_path),
            "sounio_executable_sha256": executable_sha,
            "output_manifest_sha256": sha256_file(output_manifest_path),
            "work_units_expected": len(work_units),
            "work_units_completed": len(work_units),
            "rows_emitted": rows_emitted,
            "all_work_units_complete": True,
        }
        (temporary / "sounio-execution-receipt.json").write_bytes(canonical_json(execution))
        os.replace(temporary, output)
        print(
            "U0_SOUNIO_EXECUTION_FINALIZED "
            f"run_id={run_id} work_units={len(work_units)} rows={rows_emitted} "
            f"artifacts={len(artifacts)} evidence_scope={args.evidence_scope}"
        )
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parameters", type=pathlib.Path, required=True)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source-manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source-root", type=pathlib.Path, required=True)
    parser.add_argument("--plan-directory", type=pathlib.Path, required=True)
    parser.add_argument("--execution-root", type=pathlib.Path, required=True)
    parser.add_argument("--evidence-root", type=pathlib.Path, required=True)
    parser.add_argument("--sounio-source", type=pathlib.Path, required=True)
    parser.add_argument("--sounio-compiler", type=pathlib.Path, required=True)
    parser.add_argument("--sounio-executable", type=pathlib.Path, required=True)
    parser.add_argument("--sounio-commit", required=True)
    parser.add_argument("--repository-url", required=True)
    parser.add_argument("--evidence-scope", choices=sorted(SCOPES), required=True)
    parser.add_argument("--output-directory", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        finalize(args)
        return 0
    except (OSError, ValueError, FinalizationError) as exc:
        print(f"U0_SOUNIO_EXECUTION_FINALIZATION_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
