#!/usr/bin/env python3
"""Project full DOSA Parquet capacity from measured U0 pilot shards."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import re
import sys
from collections import defaultdict
from typing import Any


SCALES = (16, 100, 500, 1000)
REQUIRED_DUCKDB_VERSION = "1.5.5"
PACKAGE_MANIFEST_VERSION = "dosa-v3-u0-dev-payload-manifest-3"
PUBLIC_PAYLOAD_MANIFEST_VERSION = "3.0.0"


class ProjectionError(RuntimeError):
    pass


def require_duckdb() -> Any:
    try:
        import duckdb  # type: ignore
    except ModuleNotFoundError as exc:
        raise ProjectionError(
            f"duckdb=={REQUIRED_DUCKDB_VERSION} is required; no Parquet metadata fallback is permitted"
        ) from exc
    version = getattr(duckdb, "__version__", None)
    if version != REQUIRED_DUCKDB_VERSION:
        raise ProjectionError(
            f"duckdb=={REQUIRED_DUCKDB_VERSION} is required, found {version!r}"
        )
    return duckdb


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ProjectionError(f"JSON root must be object: {path}")
    return value


def safe_payload_path(package: pathlib.Path, value: Any) -> pathlib.Path:
    if not isinstance(value, str) or not value or "\\" in value:
        raise ProjectionError("payload name must be a normalized relative POSIX path")
    relative = pathlib.PurePosixPath(value)
    if relative.is_absolute() or relative.as_posix() != value or any(part in ("", ".", "..") for part in relative.parts):
        raise ProjectionError("payload name must be a normalized relative POSIX path")
    root = package.resolve()
    path = package / relative
    try:
        path.resolve(strict=True).relative_to(root)
    except (OSError, ValueError) as exc:
        raise ProjectionError("payload path escapes package or is unavailable") from exc
    if not path.is_file() or path.is_symlink():
        raise ProjectionError("payload path is not a regular file")
    return path


def full_rows(path: pathlib.Path) -> dict[int, int]:
    totals = {scale: 0 for scale in SCALES}
    seen: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            accession = row.get("sequence_accession_version")
            length = row.get("length_bp")
            if not isinstance(accession, str) or not accession:
                raise ProjectionError(f"replicon line {number} lacks accession.version")
            if accession in seen:
                raise ProjectionError(f"duplicate replicon accession: {accession}")
            seen.add(accession)
            if isinstance(length, bool) or not isinstance(length, int) or length < 1:
                raise ProjectionError(f"replicon line {number} has invalid length_bp")
            for scale in SCALES:
                totals[scale] += length // scale
    if not seen:
        raise ProjectionError("full replicon inventory is empty")
    return totals


def inspect_parquet(
    connection: Any,
    payload_path: pathlib.Path,
    declared_scale: int,
    declared_rows: int,
) -> int:
    """Return observed rows only after footer, codec, and row content checks."""
    try:
        metadata = connection.execute(
            "SELECT num_rows FROM parquet_file_metadata(?)",
            [str(payload_path)],
        ).fetchone()
        if metadata is None:
            raise ProjectionError(f"Parquet file metadata is empty: {payload_path}")
        footer_rows = int(metadata[0])
        compressions = {
            str(row[0]).lower()
            for row in connection.execute(
                "SELECT DISTINCT compression FROM parquet_metadata(?)",
                [str(payload_path)],
            ).fetchall()
        }
        description = connection.execute(
            "DESCRIBE SELECT * FROM read_parquet(?, hive_partitioning=false)",
            [str(payload_path)],
        ).fetchall()
        columns = {str(row[0]) for row in description}
        if "scale" not in columns:
            raise ProjectionError(f"Parquet payload lacks required scale column: {payload_path}")
        content_rows, scale_mismatches = connection.execute(
            "SELECT count(*), count(*) FILTER (WHERE "
            "try_cast(scale AS BIGINT) IS NULL OR try_cast(scale AS BIGINT) <> ?) "
            "FROM read_parquet(?, hive_partitioning=false)",
            [declared_scale, str(payload_path)],
        ).fetchone()
    except ProjectionError:
        raise
    except Exception as exc:
        raise ProjectionError(f"payload is not readable Parquet: {payload_path}") from exc
    content_rows = int(content_rows)
    scale_mismatches = int(scale_mismatches)
    if footer_rows != content_rows:
        raise ProjectionError(f"Parquet footer/content row count mismatch: {payload_path}")
    if content_rows != declared_rows:
        raise ProjectionError(
            f"Parquet row count does not match manifest: {payload_path} "
            f"manifest={declared_rows} actual={content_rows}"
        )
    if compressions != {"zstd"}:
        raise ProjectionError(
            f"Parquet payload compression is not exclusively ZSTD: {payload_path} "
            f"actual={sorted(compressions)}"
        )
    if scale_mismatches != 0:
        raise ProjectionError(
            f"Parquet scale column does not match manifest scale {declared_scale}: {payload_path} "
            f"mismatched_rows={scale_mismatches}"
        )
    return content_rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--package",
        required=True,
        action="append",
        type=pathlib.Path,
        help="U0 package directory; repeat for independently packaged scales",
    )
    parser.add_argument("--full-replicons", required=True, type=pathlib.Path)
    parser.add_argument("--public-payload-manifest", required=True, type=pathlib.Path)
    parser.add_argument("--evidence-scope", choices=("fixture", "u0_pilot"), default="fixture")
    args = parser.parse_args()
    try:
        duckdb = require_duckdb()
        measured_rows: dict[int, int] = defaultdict(int)
        measured_bytes: dict[int, int] = defaultdict(int)
        package_bindings = []
        seen_payload_names: set[tuple[str, str]] = set()
        seen_packages: set[str] = set()
        connection = duckdb.connect(":memory:")
        try:
            for package in args.package:
                package_identity = package.resolve().as_posix()
                if package_identity in seen_packages:
                    raise ProjectionError(f"duplicate --package directory: {package}")
                seen_packages.add(package_identity)
                manifest_path = package / "dosa-payload-manifest.json"
                manifest = read_json(manifest_path)
                if (
                    manifest.get("manifest_version") != PACKAGE_MANIFEST_VERSION
                    or manifest.get("package_version") != "U0-dev"
                    or not isinstance(manifest.get("payloads"), list)
                ):
                    raise ProjectionError("unsupported or malformed U0 package manifest")
                package_bindings.append(
                    {
                        "package": package.name,
                        "manifest_sha256": sha256_file(manifest_path),
                        "manifest_bytes": manifest_path.stat().st_size,
                    }
                )
                for payload in manifest.get("payloads", []):
                    try:
                        scale = int(payload["scale"])
                        rows = int(payload["rows"])
                        size = int(payload["bytes"])
                        name = str(payload["name"])
                    except (KeyError, TypeError, ValueError) as exc:
                        raise ProjectionError("payload lacks numeric scale/rows/bytes or name") from exc
                    identity = (package.resolve().as_posix(), name)
                    if identity in seen_payload_names:
                        raise ProjectionError(f"duplicate payload manifest entry: {package}/{name}")
                    seen_payload_names.add(identity)
                    if scale not in SCALES or rows < 1 or size < 1:
                        raise ProjectionError("payload scale/rows/bytes outside U0 contract")
                    if size > 5 * 1024**3 or rows > 5_000_000:
                        raise ProjectionError("pilot package contains an oversized shard")
                    if payload.get("compression") != "zstd":
                        raise ProjectionError("pilot package payload is not declared Zstd")
                    expected_prefix = f"scale={scale}/"
                    if not name.startswith(expected_prefix):
                        raise ProjectionError("payload partition path does not match manifest scale")
                    expected_sha = payload.get("sha256")
                    if not isinstance(expected_sha, str) or re.fullmatch(r"[0-9a-f]{64}", expected_sha) is None:
                        raise ProjectionError("pilot package payload lacks lowercase SHA-256")
                    payload_path = safe_payload_path(package, name)
                    actual_size = payload_path.stat().st_size
                    if actual_size != size or sha256_file(payload_path) != expected_sha:
                        raise ProjectionError("pilot package payload bytes/SHA-256 mismatch")
                    actual_rows = inspect_parquet(connection, payload_path, scale, rows)
                    measured_rows[scale] += actual_rows
                    measured_bytes[scale] += actual_size
        finally:
            connection.close()
        if set(measured_rows) != set(SCALES):
            raise ProjectionError("pilot package must measure every U0 scale")
        if not args.public_payload_manifest.is_file() or args.public_payload_manifest.is_symlink():
            raise ProjectionError("public payload manifest must be a regular non-symlink file")
        public_manifest = read_json(args.public_payload_manifest)
        if public_manifest.get("schema_version") != PUBLIC_PAYLOAD_MANIFEST_VERSION:
            raise ProjectionError("unsupported public payload manifest")
        public_entries = public_manifest.get("package_manifests")
        tables = public_manifest.get("public_tables")
        window_rows = [
            row for row in tables
            if isinstance(row, dict) and row.get("filename") == "window_operator_profiles.parquet"
        ] if isinstance(tables, list) else []
        if len(window_rows) != 1 or not isinstance(window_rows[0].get("storage"), dict):
            raise ProjectionError("public payload manifest lacks partitioned window storage")
        storage = window_rows[0]["storage"]
        if storage.get("layout") != "package_manifest_partitioned" or storage.get("partitioning") != "scale_then_sha256_accession_bucket":
            raise ProjectionError("public window table partitioning contract mismatch")
        by_sha: dict[str, dict[str, Any]] = {}
        ids: set[str] = set()
        if not isinstance(public_entries, list) or not public_entries:
            raise ProjectionError("public payload manifest has no package manifest closure")
        for entry in public_entries:
            if not isinstance(entry, dict):
                raise ProjectionError("public package manifest entry must be an object")
            package_id = entry.get("package_manifest_id")
            digest = entry.get("sha256")
            if not isinstance(package_id, str) or not package_id or package_id in ids:
                raise ProjectionError("public package manifest IDs must be unique")
            if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None or digest in by_sha:
                raise ProjectionError("public package manifest SHA-256 values must be unique")
            if entry.get("manifest_version") != PACKAGE_MANIFEST_VERSION or entry.get("package_version") != "U0-dev" or entry.get("table_filename") != "window_operator_profiles.parquet":
                raise ProjectionError("public package manifest version/table binding mismatch")
            if not isinstance(entry.get("size_bytes"), int) or isinstance(entry.get("size_bytes"), bool) or entry["size_bytes"] < 1:
                raise ProjectionError("public package manifest size is invalid")
            ids.add(package_id)
            by_sha[digest] = entry
        if set(storage.get("package_manifest_ids", [])) != ids:
            raise ProjectionError("public window table does not reference the exact package manifest ID set")
        observed_shas = {item["manifest_sha256"] for item in package_bindings}
        if observed_shas != set(by_sha):
            raise ProjectionError("measured package manifest set does not equal public payload closure")
        for binding in package_bindings:
            entry = by_sha[binding["manifest_sha256"]]
            if entry["size_bytes"] != binding["manifest_bytes"]:
                raise ProjectionError("public package manifest byte size mismatch")
            binding["package_manifest_id"] = entry["package_manifest_id"]
        projected_rows = full_rows(args.full_replicons)
        by_scale = []
        projected_total = 0
        for scale in SCALES:
            bytes_per_row = measured_bytes[scale] / measured_rows[scale]
            projected = math.ceil(projected_rows[scale] * bytes_per_row)
            projected_total += projected
            by_scale.append(
                {
                    "scale": scale,
                    "measured_rows": measured_rows[scale],
                    "measured_parquet_bytes": measured_bytes[scale],
                    "measured_bytes_per_row": bytes_per_row,
                    "projected_full_rows": projected_rows[scale],
                    "projected_full_parquet_bytes": projected,
                }
            )
        report = {
            "schema_version": "dosa-u0-capacity-projection-1",
            "status": "pass",
            "evidence_scope": args.evidence_scope,
            "projection_basis": "measured_u0_pilot_parquet",
            "compression": "zstd",
            "parquet_footer_verified": True,
            "safety_factor": 2,
            "measured_pilot_rows": sum(measured_rows.values()),
            "measured_parquet_bytes": sum(measured_bytes.values()),
            "projected_full_rows": sum(projected_rows.values()),
            "projected_full_parquet_bytes": projected_total,
            "required_capacity_bytes": 2 * projected_total,
            "by_scale": by_scale,
            "package_manifests": sorted(package_bindings, key=lambda item: (item["package"], item["manifest_sha256"])),
            "public_payload_manifest_sha256": sha256_file(args.public_payload_manifest),
            "full_replicon_inventory_sha256": sha256_file(args.full_replicons),
        }
        print(json.dumps(report, sort_keys=True, separators=(",", ":")))
        return 0
    except (OSError, json.JSONDecodeError, ProjectionError) as exc:
        print(json.dumps({"schema_version": "dosa-u0-capacity-projection-1", "status": "fail", "evidence_scope": args.evidence_scope, "message": str(exc)}, sort_keys=True, separators=(",", ":")))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
