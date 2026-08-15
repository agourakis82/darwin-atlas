#!/usr/bin/env python3
"""Package a completed U0 logical shard set and reopen it byte-exactly.

This program is a transport boundary only. It computes no DOSA metric. It
verifies the hash-closed Sounio execution ledger, concatenates canonical JSONL
by scale, writes typed Zstandard Parquet through the DOSA CLI core, reopens the
Parquet bytes through pinned DuckDB, and records a deterministic TSV closure.
The output is fixture/development evidence and cannot authorize Gate U0.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.metadata
import json
import os
import pathlib
import shutil
import sys
import tempfile
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "cli" / "package"))
sys.path.insert(0, str(ROOT / "scripts"))

from dosa_v3.core import DosaError, PackageOptions, package_logical_output, verify_package  # noqa: E402
from build_u0_work_unit_case import (  # noqa: E402
    inspect_selected_work_unit,
    reject_symlink_components,
    validated_manifest_rows,
)


DUCKDB_VERSION = "1.5.5"
LEDGER_HEADER = (
    "run_id", "plan_sha256", "work_unit_id", "sequence_accession_version",
    "scale", "start_window", "rows", "status", "reason_code", "case_path",
    "case_sha256", "artifact_path", "artifact_sha256", "artifact_size_bytes",
)
SET_HEADER = (
    "run_id", "scale", "rows", "package_path", "package_manifest_sha256",
    "logical_path", "logical_sha256", "roundtrip_path", "roundtrip_sha256",
    "payload_count",
)
PAYLOAD_HEADER = (
    "run_id", "scale", "package_path", "payload_path", "payload_sha256",
    "payload_size_bytes", "rows", "compression",
)


class PackagingError(RuntimeError):
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


def strict_object(raw: bytes, label: str) -> dict[str, Any]:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(raw, object_pairs_hook=unique)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise PackagingError(f"{label} is not strict JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise PackagingError(f"{label} must be a JSON object")
    return value


def regular_file(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink_components(path, label)
    if path.is_symlink() or not path.is_file():
        raise PackagingError(f"{label} must be a regular non-symlink file")
    return path.resolve(strict=True)


def safe_below(root: pathlib.Path, raw: str, label: str) -> pathlib.Path:
    relative = pathlib.PurePosixPath(raw)
    if relative.is_absolute() or not relative.parts or any(part in ("", ".", "..") for part in relative.parts):
        raise PackagingError(f"{label} must be a safe relative POSIX path")
    candidate = root.joinpath(*relative.parts)
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise PackagingError(f"{label} path may not contain symlinks")
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root.resolve(strict=True))
    except (OSError, ValueError) as exc:
        raise PackagingError(f"{label} escapes or is absent") from exc
    if resolved.is_symlink() or not resolved.is_file():
        raise PackagingError(f"{label} must be a regular file")
    return resolved


def read_execution_ledger(path: pathlib.Path, execution_root: pathlib.Path) -> tuple[str, dict[int, list[dict[str, Any]]]]:
    raw = regular_file(path, "execution ledger").read_bytes()
    if not raw.endswith(b"\n") or b"\r" in raw:
        raise PackagingError("execution ledger must be LF-only with terminal LF")
    reader = csv.DictReader(raw.decode("ascii").splitlines(), delimiter="\t")
    if tuple(reader.fieldnames or ()) != LEDGER_HEADER:
        raise PackagingError("execution ledger header drift")
    run_id = ""
    by_scale: dict[int, list[dict[str, Any]]] = {}
    seen: set[tuple[str, int, int]] = set()
    declared_artifacts: set[str] = set()
    for ordinal, row in enumerate(reader, start=2):
        if set(row) != set(LEDGER_HEADER) or any(row[field] is None for field in LEDGER_HEADER):
            raise PackagingError(f"execution ledger row {ordinal} is incomplete")
        run_id = run_id or row["run_id"]
        if row["run_id"] != run_id:
            raise PackagingError("execution ledger mixes run IDs")
        if row["status"] == "excluded":
            if row["reason_code"] != "PARTIAL_WINDOW" or row["rows"] != "0":
                raise PackagingError("excluded work-unit ledger row drift")
            continue
        if row["status"] != "complete" or row["reason_code"]:
            raise PackagingError("execution ledger status drift")
        try:
            scale = int(row["scale"])
            start = int(row["start_window"])
            rows = int(row["rows"])
            size = int(row["artifact_size_bytes"])
        except ValueError as exc:
            raise PackagingError(f"execution ledger numeric drift at row {ordinal}") from exc
        if scale not in (16, 100, 500, 1000) or start < 0 or not 1 <= rows <= 16 or size < 1:
            raise PackagingError(f"execution ledger coordinate drift at row {ordinal}")
        coordinate = (row["work_unit_id"], start, rows)
        if coordinate in seen:
            raise PackagingError("execution ledger has duplicate shard coordinates")
        seen.add(coordinate)
        artifact = safe_below(execution_root, row["artifact_path"], f"artifact row {ordinal}")
        if row["artifact_path"] in declared_artifacts:
            raise PackagingError("execution ledger has a duplicate artifact path")
        declared_artifacts.add(row["artifact_path"])
        artifact_raw = artifact.read_bytes()
        if len(artifact_raw) != size or sha256_bytes(artifact_raw) != row["artifact_sha256"]:
            raise PackagingError(f"artifact bytes mismatch at ledger row {ordinal}")
        if not artifact_raw.endswith(b"\n") or b"\r" in artifact_raw or len(artifact_raw.splitlines()) != rows:
            raise PackagingError(f"artifact grammar or row count drift at ledger row {ordinal}")
        for offset, line in enumerate(artifact_raw.splitlines()):
            value = strict_object(line, f"artifact row {ordinal}/{offset + 1}")
            expected_index = start + offset
            expected = {
                "run_id": run_id,
                "replicon_id": row["sequence_accession_version"],
                "window_size": scale,
                "window_index": expected_index,
                "window_start": expected_index * scale,
                "window_end": (expected_index + 1) * scale,
            }
            if any(value.get(key) != expected_value for key, expected_value in expected.items()):
                raise PackagingError(f"artifact identity drift at ledger row {ordinal}/{offset + 1}")
        by_scale.setdefault(scale, []).append({**row, "artifact": artifact, "raw": artifact_raw})
    if not run_id or not by_scale:
        raise PackagingError("execution ledger has no completed logical shards")
    observed_artifacts = {
        candidate.relative_to(execution_root).as_posix()
        for candidate in execution_root.rglob("*.jsonl")
        if candidate.is_file()
    }
    if observed_artifacts != declared_artifacts:
        raise PackagingError("execution root has missing or unmanifested JSONL artifacts")
    for scale_rows in by_scale.values():
        scale_rows.sort(key=lambda row: (row["sequence_accession_version"], int(row["start_window"])))
    return run_id, by_scale


def source_bindings(parameters: pathlib.Path, manifest: pathlib.Path, source_root: pathlib.Path,
                    staging: pathlib.Path, run_id: str) -> tuple[pathlib.Path, tuple[pathlib.Path, pathlib.Path]]:
    parameters_sha = sha256_file(parameters)
    rows = validated_manifest_rows(manifest, parameters_sha)
    accessions: dict[str, dict[str, str]] = {}
    integrity_records: list[dict[str, str | int]] = []
    for row in rows:
        accession = row["sequence_accession_version"]
        inspected, sequence, observed_parameters = inspect_selected_work_unit(
            parameters, manifest, source_root, row["work_unit_id"],
        )
        if inspected != row or observed_parameters != parameters_sha:
            raise PackagingError("source inspection drifted while creating source bindings")
        source_record = {
            "locator": row["source_locator"],
            "canonical_sequence_input_sha256": row["source_file_sha256"],
            "normalized_sequence_sha256": row["sequence_sha256"],
            "source_manifest_sha256": sha256_file(manifest),
            "source_integrity_sha256": "pending",
        }
        if accession in accessions:
            if accessions[accession] != source_record:
                raise PackagingError("one accession has inconsistent cross-scale source bindings")
            continue
        accessions[accession] = source_record
        integrity_records.append({
            "accession_version": accession,
            "locator": row["source_locator"],
            "raw_fasta_sha256": row["source_file_sha256"],
            "normalized_sequence_sha256": row["sequence_sha256"],
            "sequence_length": len(sequence),
        })
    integrity = {
        "schema_version": "dosa-v3-u0-work-source-integrity-1",
        "receipt_id": f"{run_id}-source-integrity",
        "evidence_scope": "fixture-only-nonpromotable",
        "run_id": run_id,
        "work_unit_manifest_sha256": sha256_file(manifest),
        "records": sorted(integrity_records, key=lambda item: str(item["accession_version"])),
    }
    integrity_path = staging / "source-integrity.json"
    integrity_path.write_bytes(canonical_json(integrity))
    integrity_sha = sha256_file(integrity_path)
    for record in accessions.values():
        record["source_integrity_sha256"] = integrity_sha
    source_index = {
        "source_index_version": "dosa-v3-source-index-1",
        "records": dict(sorted(accessions.items())),
    }
    source_index_path = staging / "source-index.json"
    source_index_path.write_bytes(canonical_json(source_index))
    return source_index_path, (integrity_path,)


def export_roundtrip(duckdb: Any, package: pathlib.Path, target: pathlib.Path) -> None:
    manifest = strict_object((package / "dosa-payload-manifest.json").read_bytes(), "package manifest")
    payloads = manifest.get("payloads")
    if not isinstance(payloads, list) or not payloads:
        raise PackagingError("package manifest has no payloads")
    payload_paths = [safe_below(package, str(row.get("name")), "package payload") for row in payloads]
    quoted = ",".join("'" + str(path).replace("'", "''") + "'" for path in payload_paths)
    target_sql = str(target).replace("'", "''")
    connection = duckdb.connect(":memory:")
    try:
        connection.execute(
            "COPY (SELECT * FROM read_parquet([" + quoted + "], hive_partitioning=false) "
            "ORDER BY replicon_id, window_index) TO '" + target_sql + "' (FORMAT JSON, ARRAY false)"
        )
    except Exception as exc:
        raise PackagingError(f"Parquet round-trip export failed: {exc}") from exc
    finally:
        connection.close()


def package_set(parameters: pathlib.Path, manifest: pathlib.Path, source_root: pathlib.Path,
                execution_root: pathlib.Path, output: pathlib.Path,
                window_schema: pathlib.Path, common_schema: pathlib.Path) -> None:
    try:
        observed_version = importlib.metadata.version("duckdb")
    except importlib.metadata.PackageNotFoundError as exc:
        raise PackagingError(f"duckdb=={DUCKDB_VERSION} is required") from exc
    if observed_version != DUCKDB_VERSION:
        raise PackagingError(f"duckdb=={DUCKDB_VERSION} is required, found {observed_version}")
    import duckdb  # type: ignore

    for path, label in (
        (parameters, "parameters"), (manifest, "work-unit manifest"),
        (window_schema, "window schema"), (common_schema, "common schema"),
    ):
        regular_file(path, label)
    reject_symlink_components(source_root, "source root")
    reject_symlink_components(execution_root, "execution root")
    if source_root.is_symlink() or not source_root.is_dir() or execution_root.is_symlink() or not execution_root.is_dir():
        raise PackagingError("source and execution roots must be real directories")
    reject_symlink_components(output.parent, "output parent")
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise PackagingError("output must be absent beneath an existing real parent")
    ledger_path = execution_root / "execution_ledger.tsv"
    run_id, by_scale = read_execution_ledger(ledger_path, execution_root)
    temporary = pathlib.Path(tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=output.parent))
    try:
        logical_root = temporary / "logical"
        roundtrip_root = temporary / "roundtrip"
        packages_root = temporary / "packages"
        for directory in (logical_root, roundtrip_root, packages_root):
            directory.mkdir()
        source_index, source_receipts = source_bindings(parameters, manifest, source_root, temporary, run_id)
        execution_binding = temporary / "execution-binding.json"
        execution_binding.write_bytes(canonical_json({
            "schema_version": "dosa-v3-u0-work-execution-binding-1",
            "receipt_id": f"{run_id}-execution-binding",
            "evidence_scope": "fixture-only-nonpromotable",
            "run_id": run_id,
            "execution_ledger_sha256": sha256_file(ledger_path),
            "work_unit_manifest_sha256": sha256_file(manifest),
        }))
        set_rows: list[tuple[str, ...]] = []
        payload_rows: list[tuple[str, ...]] = []
        total_rows = 0
        for scale, shards in sorted(by_scale.items()):
            logical_relative = pathlib.PurePosixPath("logical", f"scale-{scale}.jsonl")
            logical_path = temporary.joinpath(*logical_relative.parts)
            logical_raw = b"".join(bytes(shard["raw"]) for shard in shards)
            logical_path.write_bytes(logical_raw)
            row_count = len(logical_raw.splitlines())
            package_relative = pathlib.PurePosixPath("packages", f"scale-{scale}")
            package_path = temporary.joinpath(*package_relative.parts)
            package_logical_output(PackageOptions(
                source=logical_path,
                output=package_path,
                scale=str(scale),
                source_index=source_index,
                input_format="jsonl",
                accession_field="replicon_id",
                coordinate_start_field="window_start",
                coordinate_end_field="window_end",
                rows_per_shard=5_000_000,
                schemas=(common_schema, window_schema),
                receipts=(*source_receipts, execution_binding),
            ))
            verification = verify_package(package_path)
            if verification.get("status") != "ok" or verification.get("failures"):
                raise PackagingError(f"DOSA package verification failed for scale {scale}")
            package_manifest = package_path / "dosa-payload-manifest.json"
            package_document = strict_object(package_manifest.read_bytes(), f"scale {scale} package manifest")
            roundtrip_relative = pathlib.PurePosixPath("roundtrip", f"scale-{scale}.jsonl")
            roundtrip_path = temporary.joinpath(*roundtrip_relative.parts)
            export_roundtrip(duckdb, package_path, roundtrip_path)
            roundtrip_raw = roundtrip_path.read_bytes()
            if roundtrip_raw != logical_raw:
                raise PackagingError(f"Parquet round-trip bytes differ from canonical logical JSONL at scale {scale}")
            payloads = package_document["payloads"]
            set_rows.append((
                run_id, str(scale), str(row_count), package_relative.as_posix(),
                sha256_file(package_manifest), logical_relative.as_posix(), sha256_bytes(logical_raw),
                roundtrip_relative.as_posix(), sha256_bytes(roundtrip_raw), str(len(payloads)),
            ))
            for payload in payloads:
                payload_path = safe_below(package_path, payload["name"], "package payload")
                payload_rows.append((
                    run_id, str(scale), package_relative.as_posix(), payload["name"],
                    sha256_file(payload_path), str(payload_path.stat().st_size), str(payload["rows"]),
                    str(payload["compression"]),
                ))
            total_rows += row_count
        set_ledger = temporary / "parquet_set_ledger.tsv"
        set_ledger.write_bytes(("\t".join(SET_HEADER) + "\n" + "\n".join("\t".join(row) for row in set_rows) + "\n").encode("ascii"))
        payload_ledger = temporary / "parquet_payload_ledger.tsv"
        payload_ledger.write_bytes(("\t".join(PAYLOAD_HEADER) + "\n" + "\n".join("\t".join(row) for row in payload_rows) + "\n").encode("ascii"))
        set_manifest = {
            "schema_version": "dosa-v3-u0-work-parquet-set-1",
            "evidence_scope": "fixture-only-nonpromotable",
            "run_id": run_id,
            "parameters_sha256": sha256_file(parameters),
            "work_unit_manifest_sha256": sha256_file(manifest),
            "execution_ledger_sha256": sha256_file(ledger_path),
            "source_index_sha256": sha256_file(source_index),
            "parquet_set_ledger_sha256": sha256_file(set_ledger),
            "parquet_payload_ledger_sha256": sha256_file(payload_ledger),
            "scales_packaged": sorted(by_scale),
            "rows": total_rows,
            "gate_u0_pass": False,
        }
        (temporary / "parquet_set_manifest.json").write_bytes(canonical_json(set_manifest))
        os.replace(temporary, output)
        print(
            "U0_WORK_PARQUET_SET_PASS "
            f"run_id={run_id} scales={len(by_scale)} rows={total_rows} "
            f"payloads={len(payload_rows)} roundtrip_byte_exact=1 fixture_scope_nonpromotable=1"
        )
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parameters", type=pathlib.Path, required=True)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source-root", type=pathlib.Path, required=True)
    parser.add_argument("--execution-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--window-schema", type=pathlib.Path, required=True)
    parser.add_argument("--common-schema", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        package_set(args.parameters, args.manifest, args.source_root, args.execution_root,
                    args.output, args.window_schema, args.common_schema)
        return 0
    except (OSError, TypeError, ValueError, DosaError, PackagingError) as exc:
        print(f"U0_WORK_PARQUET_SET_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
