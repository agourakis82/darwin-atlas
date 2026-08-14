"""Fail-closed operational boundary for DOSA v3 U0 development.

Python performs transport, hashing, routing and envelope validation only.
Scientific calibration remains exclusively in the configured canonical Sounio
runner.  The runner's build provenance is accepted only through a separate,
immutable attestation artifact; a hash-bound artifact does not attest the
scientific semantics of a calibration result.
"""
from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import urllib.parse
from dataclasses import dataclass
from typing import Any


PACKAGE_VERSION = "U0-dev"
MANIFEST_NAME = "dosa-payload-manifest.json"
MANIFEST_VERSION = "dosa-v3-u0-dev-payload-manifest-3"
SOURCE_INDEX_VERSION = "dosa-v3-source-index-1"
CALIBRATION_ENVELOPE_VERSION = "dosa-v3-u0-dev-calibration-result-1"
RUNNER_ATTESTATION_VERSION = "dosa-v3-sounio-runner-attestation-1"
SOUNIO_OFFICIAL_REPOSITORY = "https://github.com/sounio-lang/sounio.git"
MAX_ROWS_PER_SHARD = 5_000_000
MAX_BYTES_PER_SHARD = 5 * 1024 * 1024 * 1024
EXIT_OK = 0
EXIT_USAGE_OR_DEPENDENCY = 2
EXIT_VERIFICATION_FAILED = 3
EXIT_NOT_FOUND = 4
EXIT_REFUSED = 5
EXIT_CALIBRATION_FAILED = 6


class DosaError(Exception):
    exit_code = EXIT_USAGE_OR_DEPENDENCY
    code = "DOSA_ERROR"


class DependencyError(DosaError):
    code = "DOSA_DEPENDENCY_MISSING"


class RefusalError(DosaError):
    exit_code = EXIT_REFUSED
    code = "DOSA_REFUSE"


class VerificationError(DosaError):
    exit_code = EXIT_VERIFICATION_FAILED
    code = "DOSA_VERIFICATION_FAILED"


class NotFoundError(DosaError):
    exit_code = EXIT_NOT_FOUND
    code = "DOSA_NOT_FOUND"


class CalibrationError(DosaError):
    exit_code = EXIT_CALIBRATION_FAILED
    code = "DOSA_CALIBRATION_FAILED"


def require_duckdb():
    try:
        import duckdb  # type: ignore
    except ModuleNotFoundError as exc:
        raise DependencyError(
            "DuckDB is required for DOSA Parquet packaging/query; install the "
            "Python 'duckdb' package. No fallback reader is used."
        ) from exc
    return duckdb


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def accession_bucket(accession_version: str) -> str:
    """Return the first byte of SHA256(accession.version), as two hex digits."""
    return hashlib.sha256(accession_version.encode("utf-8")).hexdigest()[:2]


def file_record(path: pathlib.Path, root: pathlib.Path) -> dict[str, Any]:
    return {
        "name": path.relative_to(root).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def json_dumps(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def safe_partition(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9._-]+", value):
        raise DosaError("partition values must match [A-Za-z0-9._-]+")
    return value


def qident(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        raise DosaError(f"unsafe SQL identifier: {value!r}")
    return '"' + value + '"'


def sql_string(value: pathlib.Path | str) -> str:
    return str(value).replace("'", "''")


def _safe_manifest_name(name: Any) -> str:
    if not isinstance(name, str) or not name or "\\" in name:
        raise DosaError("manifest file names must be non-empty POSIX relative paths")
    path = pathlib.PurePosixPath(name)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise DosaError(f"unsafe manifest file name: {name!r}")
    if path.as_posix() != name:
        raise DosaError(f"manifest file name is not normalized: {name!r}")
    return path.as_posix()


def _package_path(package: pathlib.Path, name: Any) -> pathlib.Path:
    safe_name = _safe_manifest_name(name)
    root = package.resolve()
    path = package / pathlib.PurePosixPath(safe_name)
    try:
        path.resolve(strict=False).relative_to(root)
    except ValueError as exc:
        raise DosaError(f"manifest path escapes package: {safe_name}") from exc
    return path


def load_manifest(package: pathlib.Path) -> dict[str, Any]:
    path = package / MANIFEST_NAME
    try:
        result = _strict_json_file_object(path)
    except FileNotFoundError as exc:
        raise DosaError(f"payload manifest is missing: {path}") from exc
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError) as exc:
        raise DosaError(f"payload manifest is not JSON: {path}") from exc
    if not isinstance(result, dict):
        raise DosaError("payload manifest root must be an object")
    if result.get("manifest_version") != MANIFEST_VERSION or result.get("package_version") != PACKAGE_VERSION:
        raise DosaError("unsupported payload manifest or package version")
    return result


def _source_format(source: pathlib.Path, fmt: str) -> str:
    if fmt != "auto":
        return fmt
    return "tsv" if source.suffix.lower() == ".tsv" else "jsonl"


def _validate_binding_document(path: pathlib.Path, kind: str) -> None:
    try:
        value = _strict_json_file_object(path)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise DosaError(f"{kind} binding must be a valid UTF-8 JSON document: {path}") from exc
    if not isinstance(value, dict):
        raise DosaError(f"{kind} binding root must be an object: {path}")
    if kind == "schema" and not (isinstance(value.get("$schema"), str) and value.get("type") == "object"):
        raise DosaError(f"schema binding lacks JSON Schema object markers: {path}")
    if kind == "receipt" and not any(key in value for key in ("receipt_id", "receipt_kind", "run_id")):
        raise DosaError(f"receipt binding lacks a receipt identifier: {path}")


def _is_sha256(value: Any) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _is_accession_version(value: Any) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_]+\.[0-9]+", value) is not None


def _is_public_source_locator(value: Any) -> bool:
    """Accept a public HTTPS locator or a normalized portable relative path."""
    if not isinstance(value, str) or not value:
        return False
    if value.startswith("https://"):
        parsed = urllib.parse.urlsplit(value)
        host = (parsed.hostname or "").lower()
        if (
            parsed.scheme != "https" or not host or parsed.username or parsed.password
            or parsed.fragment or any(marker in value.lower() for marker in ("localhost", ".local", "/users/", "/home/", "/private/", "proxmox", "cluster"))
        ):
            return False
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            address = None
        return address is None or address.is_global
    if "://" in value or "\\" in value or value.startswith("/"):
        return False
    path = pathlib.PurePosixPath(value)
    return path.as_posix() == value and all(part not in ("", ".", "..") for part in path.parts)


def _strict_json_file_object(path: pathlib.Path) -> dict[str, Any]:
    def no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, item in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON object key: {key}")
            result[key] = item
        return result

    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_duplicate_keys)
    if not isinstance(value, dict):
        raise ValueError("JSON root must be an object")
    return value


def _load_source_index(path: pathlib.Path, error_type: type[DosaError] = DosaError) -> dict[str, Any]:
    """Parse and fail closed on the portable accession-version source index."""
    def no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, item in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON object key: {key}")
            result[key] = item
        return result
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_duplicate_keys)
    except FileNotFoundError as exc:
        raise error_type(f"source index does not exist: {path}") from exc
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise error_type(f"source index must be valid UTF-8 JSON: {path}") from exc
    if not isinstance(value, dict) or value.get("source_index_version") != SOURCE_INDEX_VERSION:
        raise error_type("unsupported or invalid source index version")
    records = value.get("records")
    if not isinstance(records, dict) or not records:
        raise error_type("source index records must be a non-empty object keyed by accession.version")
    for accession, record in records.items():
        if not _is_accession_version(accession) or not isinstance(record, dict):
            raise error_type("source index records must be objects keyed by versioned accession.version")
        if record.get("accession_version", accession) != accession:
            raise error_type(f"source index record accession mismatch: {accession}")
        if not _is_public_source_locator(record.get("locator")):
            raise error_type(f"source index locator is not a public relative/HTTPS locator: {accession}")
        for field in (
            "canonical_sequence_input_sha256",
            "normalized_sequence_sha256",
            "source_manifest_sha256",
            "source_integrity_sha256",
        ):
            if not _is_sha256(record.get(field)):
                raise error_type(f"source index record has invalid {field}: {accession}")
    return value


@dataclass(frozen=True)
class PackageOptions:
    source: pathlib.Path
    output: pathlib.Path
    scale: str
    source_index: pathlib.Path
    input_format: str = "auto"
    accession_field: str = "sequence_accession_version"
    coordinate_start_field: str = "window_start"
    coordinate_end_field: str = "window_end"
    rows_per_shard: int = MAX_ROWS_PER_SHARD
    schemas: tuple[pathlib.Path, ...] = ()
    receipts: tuple[pathlib.Path, ...] = ()


def _deposit_bindings(
    staging: pathlib.Path,
    schemas: tuple[pathlib.Path, ...],
    receipts: tuple[pathlib.Path, ...],
    source_index: pathlib.Path,
) -> list[dict[str, Any]]:
    if not schemas or not receipts:
        raise DosaError("a self-contained package requires at least one --schema and one --receipt")
    bindings: list[dict[str, Any]] = []
    deposited: set[str] = set()
    _load_source_index(source_index)
    for kind, paths in (("schema", schemas), ("receipt", receipts), ("source_index", (source_index,))):
        for source in paths:
            if not source.is_file():
                raise DosaError(f"{kind} does not exist: {source}")
            if kind != "source_index":
                _validate_binding_document(source, kind)
            basename = source.name
            if basename in ("", ".", "..") or "/" in basename or "\\" in basename:
                raise DosaError(f"unsafe {kind} binding filename: {basename!r}")
            relative = pathlib.Path("bindings") / kind / basename
            name = relative.as_posix()
            if name in deposited:
                raise DosaError(f"duplicate deposited binding name: {name}")
            deposited.add(name)
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            record = file_record(target, staging)
            record["kind"] = kind
            bindings.append(record)
    return bindings


def _source_index_binding(manifest: dict[str, Any], error_type: type[DosaError] = VerificationError) -> dict[str, Any]:
    matches = [
        entry
        for entry in manifest.get("bindings", [])
        if isinstance(entry, dict) and entry.get("kind") == "source_index"
    ]
    if len(matches) != 1:
        raise error_type("package must bind exactly one source_index artifact")
    return matches[0]


def package_logical_output(options: PackageOptions) -> dict[str, Any]:
    """Convert canonical JSONL/TSV to Zstd Parquet through bounded DuckDB SQL."""
    duckdb = require_duckdb()
    if not options.source.is_file():
        raise DosaError(f"logical input does not exist: {options.source}")
    input_format = _source_format(options.source, options.input_format)
    if input_format not in ("jsonl", "tsv"):
        raise DosaError("input format must be auto, jsonl, or tsv")
    if not options.source_index.is_file():
        raise DosaError(f"source index does not exist: {options.source_index}")
    source_index = _load_source_index(options.source_index)
    if options.rows_per_shard < 1 or options.rows_per_shard > MAX_ROWS_PER_SHARD:
        raise DosaError(f"rows-per-shard must be between 1 and {MAX_ROWS_PER_SHARD}")
    scale = safe_partition(options.scale)
    required = (
        options.accession_field,
        options.coordinate_start_field,
        options.coordinate_end_field,
    )
    for field in required:
        qident(field)
    if options.output.exists():
        raise DosaError(f"output already exists; refusing to overwrite: {options.output}")
    staging = options.output.with_name(options.output.name + ".staging")
    if staging.exists():
        raise DosaError(f"staging path already exists; remove it explicitly: {staging}")
    staging.mkdir(parents=True)
    con = None
    database = staging / ".package-work.duckdb"
    temp_directory = staging / ".duckdb-tmp"
    temp_directory.mkdir()
    try:
        con = duckdb.connect(str(database))
        con.execute("SET preserve_insertion_order = false")
        con.execute("SET memory_limit = '512MB'")
        con.execute(f"SET temp_directory = '{sql_string(temp_directory)}'")
        source_sql = sql_string(options.source)
        if input_format == "jsonl":
            con.execute(f"CREATE VIEW logical AS SELECT * FROM read_json_auto('{source_sql}', format='newline_delimited')")
        else:
            con.execute(f"CREATE VIEW logical AS SELECT * FROM read_csv_auto('{source_sql}', delim='\\t', header=true)")
        description = con.execute("DESCRIBE logical").fetchall()
        columns = {item[0] for item in description}
        missing_columns = [item for item in required if item not in columns]
        if missing_columns:
            raise DosaError("DuckDB inferred input lacks routing columns: " + ", ".join(missing_columns))

        accession_col = qident(options.accession_field)
        start_col = qident(options.coordinate_start_field)
        end_col = qident(options.coordinate_end_field)
        row_count, invalid_count = con.execute(
            "SELECT count(*), sum(CASE WHEN "
            f"{accession_col} IS NULL OR trim(CAST({accession_col} AS VARCHAR)) = '' OR "
            f"try_cast({start_col} AS BIGINT) IS NULL OR try_cast({end_col} AS BIGINT) IS NULL OR "
            f"try_cast({start_col} AS BIGINT) < 0 OR try_cast({end_col} AS BIGINT) <= try_cast({start_col} AS BIGINT) "
            "THEN 1 ELSE 0 END) FROM logical"
        ).fetchone()
        row_count = int(row_count)
        invalid_count = int(invalid_count or 0)
        if row_count == 0:
            raise DosaError("logical input has no rows; refusing to create an empty package")
        if invalid_count:
            raise DosaError(f"logical input has {invalid_count} row(s) with invalid routing fields")
        input_accessions = {
            str(row[0])
            for row in con.execute(f"SELECT DISTINCT CAST({accession_col} AS VARCHAR) FROM logical").fetchall()
        }
        missing_accessions = sorted(input_accessions - set(source_index["records"]))
        if missing_accessions:
            raise DosaError("source index lacks logical input accession.version record(s): " + ", ".join(missing_accessions))

        science_columns = [item[0] for item in description]
        science_sql = ",".join(qident(name) for name in science_columns)
        bucket_expression = f"substr(sha256(CAST({accession_col} AS VARCHAR)), 1, 2)"
        con.execute(
            "CREATE TABLE routed AS SELECT "
            f"{science_sql}, {bucket_expression} AS _dosa_bucket, "
            f"row_number() OVER (PARTITION BY {bucket_expression} ORDER BY "
            f"CAST({accession_col} AS VARCHAR), CAST({start_col} AS BIGINT), CAST({end_col} AS BIGINT)) AS _dosa_row_number "
            "FROM logical"
        )
        bucket_counts = con.execute(
            "SELECT _dosa_bucket, count(*) FROM routed GROUP BY _dosa_bucket ORDER BY _dosa_bucket"
        ).fetchall()
        payloads: list[dict[str, Any]] = []
        for bucket, total_value in bucket_counts:
            bucket = str(bucket)
            if not re.fullmatch(r"[0-9a-f]{2}", bucket):
                raise DosaError(f"DuckDB produced an invalid accession bucket: {bucket!r}")
            total = int(total_value)
            for shard_index, offset in enumerate(range(0, total, options.rows_per_shard)):
                lower = offset + 1
                upper = min(offset + options.rows_per_shard, total)
                relative = pathlib.Path(f"scale={scale}") / f"sha256_bucket={bucket}" / f"part-{shard_index:05d}.parquet"
                target = staging / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target_sql = sql_string(target)
                con.execute(
                    f"COPY (SELECT {science_sql} FROM routed WHERE _dosa_bucket = ? "
                    "AND _dosa_row_number BETWEEN ? AND ? ORDER BY _dosa_row_number) "
                    f"TO '{target_sql}' (FORMAT PARQUET, COMPRESSION ZSTD)",
                    [bucket, lower, upper],
                )
                if target.stat().st_size > MAX_BYTES_PER_SHARD:
                    raise DosaError(
                        f"written shard exceeds the {MAX_BYTES_PER_SHARD}-byte (5 GiB) limit: {relative.as_posix()}"
                    )
                route = con.execute(
                    "WITH shard AS (SELECT * FROM routed WHERE _dosa_bucket = ? "
                    "AND _dosa_row_number BETWEEN ? AND ?), edges AS ("
                    f"SELECT min(CAST({accession_col} AS VARCHAR)) AS accession_min, "
                    f"max(CAST({accession_col} AS VARCHAR)) AS accession_max FROM shard) "
                    "SELECT edges.accession_min, edges.accession_max, "
                    f"min(CASE WHEN CAST({accession_col} AS VARCHAR) = edges.accession_min THEN CAST({start_col} AS BIGINT) END), "
                    f"max(CASE WHEN CAST({accession_col} AS VARCHAR) = edges.accession_min THEN CAST({end_col} AS BIGINT) END), "
                    f"min(CASE WHEN CAST({accession_col} AS VARCHAR) = edges.accession_max THEN CAST({start_col} AS BIGINT) END), "
                    f"max(CASE WHEN CAST({accession_col} AS VARCHAR) = edges.accession_max THEN CAST({end_col} AS BIGINT) END) "
                    "FROM shard CROSS JOIN edges GROUP BY edges.accession_min, edges.accession_max",
                    [bucket, lower, upper],
                ).fetchone()
                payload = file_record(target, staging)
                payload.update(
                    {
                        "scale": scale,
                        "sha256_bucket": bucket,
                        "rows": upper - lower + 1,
                        "compression": "zstd",
                        "route_bounds": {
                            "accession_min": route[0],
                            "accession_max": route[1],
                            "min_accession_coordinate_start": int(route[2]),
                            "min_accession_coordinate_end": int(route[3]),
                            "max_accession_coordinate_start": int(route[4]),
                            "max_accession_coordinate_end": int(route[5]),
                        },
                    }
                )
                payloads.append(payload)
        typed_schema = [{"name": row[0], "type": row[1]} for row in description]
        bindings = _deposit_bindings(staging, options.schemas, options.receipts, options.source_index)
        con.close()
        con = None
        for work_file in (database, database.with_suffix(database.suffix + ".wal")):
            if work_file.exists():
                work_file.unlink()
        shutil.rmtree(temp_directory, ignore_errors=True)
        manifest = {
            "manifest_version": MANIFEST_VERSION,
            "package_version": PACKAGE_VERSION,
            "source": {"logical_bytes": options.source.stat().st_size, "logical_sha256": sha256_file(options.source)},
            "routing": {
                "accession_field": options.accession_field,
                "coordinate_start_field": options.coordinate_start_field,
                "coordinate_end_field": options.coordinate_end_field,
                "bucket_derivation": "first_byte_sha256_accession_version_utf8",
                "rows_per_shard": options.rows_per_shard,
                "max_rows_per_shard": MAX_ROWS_PER_SHARD,
                "max_bytes_per_shard": MAX_BYTES_PER_SHARD,
            },
            "typed_schema": typed_schema,
            "payloads": payloads,
            "bindings": bindings,
            "scale_capacity": [
                {
                    "scale": scale,
                    "compression": "zstd",
                    "rows": row_count,
                    "bytes": sum(int(payload["bytes"]) for payload in payloads),
                    "shards": len(payloads),
                }
            ],
        }
        (staging / MANIFEST_NAME).write_text(json_dumps(manifest) + "\n", encoding="utf-8")
        os.replace(staging, options.output)
        return {
            "status": "ok",
            "package_version": PACKAGE_VERSION,
            "package": str(options.output),
            "payloads": len(payloads),
            "rows": row_count,
            "manifest": MANIFEST_NAME,
        }
    except DosaError:
        if con is not None:
            con.close()
        shutil.rmtree(staging, ignore_errors=True)
        raise
    except Exception as exc:
        if con is not None:
            con.close()
        shutil.rmtree(staging, ignore_errors=True)
        raise DosaError(f"DuckDB packaging failed: {exc}") from exc


def _route_bounds_overlap(bounds: dict[str, Any], accession: str, start: int, end: int) -> bool:
    accession_min = str(bounds["accession_min"])
    accession_max = str(bounds["accession_max"])
    if accession < accession_min or accession > accession_max:
        return False
    if accession_min == accession_max:
        return int(bounds["min_accession_coordinate_start"]) < end and int(bounds["min_accession_coordinate_end"]) > start
    if accession == accession_min:
        return int(bounds["min_accession_coordinate_start"]) < end and int(bounds["min_accession_coordinate_end"]) > start
    if accession == accession_max:
        return int(bounds["max_accession_coordinate_start"]) < end and int(bounds["max_accession_coordinate_end"]) > start
    return True


def query_package(
    package: pathlib.Path,
    accession: str,
    coordinate_start: int,
    coordinate_end: int,
    scale: str,
) -> dict[str, Any]:
    duckdb = require_duckdb()
    if coordinate_start < 0 or coordinate_end <= coordinate_start:
        raise DosaError("coordinate must be a non-negative half-open interval start:end")
    manifest = load_manifest(package)
    source_index_binding = _source_index_binding(manifest)
    source_index_path = _package_path(package, source_index_binding.get("name"))
    if not source_index_path.is_file() or source_index_path.is_symlink():
        raise VerificationError("bound source index is unavailable")
    if source_index_path.stat().st_size != source_index_binding.get("bytes") or sha256_file(source_index_path) != source_index_binding.get("sha256"):
        raise VerificationError("bound source index bytes/SHA-256 do not match manifest")
    source_index = _load_source_index(source_index_path, VerificationError)
    source_record = source_index["records"].get(accession)
    if not isinstance(source_record, dict):
        raise NotFoundError("source index has no record for the requested accession.version")
    scale = safe_partition(scale)
    routing = manifest["routing"]
    if routing.get("bucket_derivation") != "first_byte_sha256_accession_version_utf8":
        raise VerificationError("package uses an unsupported accession bucket derivation")
    bucket = accession_bucket(accession)
    candidates: list[tuple[pathlib.Path, dict[str, Any]]] = []
    candidate_names: set[str] = set()
    for payload in manifest.get("payloads", []):
        if payload.get("scale") != scale or payload.get("sha256_bucket") != bucket:
            continue
        if _route_bounds_overlap(payload["route_bounds"], accession, coordinate_start, coordinate_end):
            expected_prefix = f"scale={scale}/sha256_bucket={bucket}/"
            if not str(payload.get("name", "")).startswith(expected_prefix):
                raise VerificationError("candidate payload partition path does not match its scale/bucket")
            path = _package_path(package, payload["name"])
            if not path.is_file() or path.is_symlink():
                raise VerificationError(f"payload listed by manifest is unavailable: {payload['name']}")
            if path.stat().st_size != payload.get("bytes") or sha256_file(path) != payload.get("sha256"):
                raise VerificationError(f"candidate payload bytes/SHA-256 do not match manifest: {payload['name']}")
            if payload["name"] in candidate_names:
                raise VerificationError(f"duplicate candidate payload manifest name: {payload['name']}")
            candidate_names.add(payload["name"])
            candidates.append((path, payload))
    if not candidates:
        raise NotFoundError("no payload shard covers the requested accession, coordinate, and scale")
    con = duckdb.connect(":memory:")
    try:
        records: list[dict[str, Any]] = []
        paths_read: list[str] = []
        for path, _ in candidates:
            path_sql = sql_string(path)
            cursor = con.execute(
                f"SELECT * FROM read_parquet('{path_sql}') WHERE "
                f"CAST({qident(routing['accession_field'])} AS VARCHAR) = ? AND "
                f"CAST({qident(routing['coordinate_start_field'])} AS BIGINT) < ? AND "
                f"CAST({qident(routing['coordinate_end_field'])} AS BIGINT) > ?",
                [accession, coordinate_end, coordinate_start],
            )
            names = [column[0] for column in cursor.description]
            records.extend(dict(zip(names, row)) for row in cursor.fetchall())
            paths_read.append(path.relative_to(package).as_posix())
    except Exception as exc:
        raise DosaError(f"DuckDB query failed: {exc}") from exc
    finally:
        con.close()
    if not records:
        raise NotFoundError("the routed shard contains no overlapping records")
    records.sort(
        key=lambda item: (
            str(item.get(routing["accession_field"])),
            int(item.get(routing["coordinate_start_field"])),
            int(item.get(routing["coordinate_end_field"])),
        )
    )
    return {
        "status": "ok",
        "package_version": PACKAGE_VERSION,
        "query": {
            "accession_version": accession,
            "accession_sha256_bucket": bucket,
            "coordinate_start": coordinate_start,
            "coordinate_end": coordinate_end,
            "scale": scale,
        },
        "source_index_sha256": source_index_binding["sha256"],
        "source_record": source_record,
        "package_manifest_sha256": sha256_file(package / MANIFEST_NAME),
        "payloads": [{"name": item["name"], "sha256": item["sha256"]} for _, item in candidates],
        "shards_read": paths_read,
        "records": records,
    }


def _record_failure(failures: list[dict[str, str]], name: str, reason: str) -> None:
    failures.append({"name": name, "reason": reason})


def verify_package(package: pathlib.Path) -> dict[str, Any]:
    manifest = load_manifest(package)
    failures: list[dict[str, str]] = []
    payloads = manifest.get("payloads")
    bindings = manifest.get("bindings")
    if not isinstance(payloads, list) or not payloads:
        payloads = []
        _record_failure(failures, "payloads", "missing_or_empty")
    if not isinstance(bindings, list):
        bindings = []
        _record_failure(failures, "bindings", "missing")

    entries: list[tuple[str, dict[str, Any]]] = []
    for kind, values in (("payload", payloads), ("binding", bindings)):
        for value in values:
            if not isinstance(value, dict):
                _record_failure(failures, kind, "manifest_entry_not_object")
                continue
            try:
                name = _safe_manifest_name(value.get("name"))
            except DosaError:
                _record_failure(failures, str(value.get("name")), "unsafe_name")
                continue
            entries.append((kind, value))

    seen_names: set[str] = set()
    duplicate_names: set[str] = set()
    for _, entry in entries:
        name = entry["name"]
        if name in seen_names:
            duplicate_names.add(name)
        seen_names.add(name)
    duplicates = sorted(duplicate_names)
    for name in duplicates:
        _record_failure(failures, name, "duplicate_manifest_name")

    binding_kinds = {binding.get("kind") for binding in bindings if isinstance(binding, dict)}
    for required_kind in ("schema", "receipt", "source_index"):
        if required_kind not in binding_kinds:
            _record_failure(failures, f"bindings/{required_kind}", "required_binding_unavailable")
    try:
        _source_index_binding(manifest)
    except VerificationError:
        _record_failure(failures, "bindings/source_index", "missing_or_ambiguous")

    binding_results: list[dict[str, str]] = []
    payload_names: set[str] = set()
    binding_names: set[str] = set()
    for kind, entry in entries:
        name = entry["name"]
        path = _package_path(package, name)
        if kind == "payload":
            payload_names.add(name)
            expected_prefix = f"scale={entry.get('scale')}/sha256_bucket={entry.get('sha256_bucket')}/"
            if not name.startswith(expected_prefix) or not re.fullmatch(r"[0-9a-f]{2}", str(entry.get("sha256_bucket"))):
                _record_failure(failures, name, "partition_name_mismatch")
            if entry.get("compression") != "zstd":
                _record_failure(failures, name, "compression_mismatch")
            if type(entry.get("rows")) is not int or not 1 <= entry["rows"] <= MAX_ROWS_PER_SHARD:
                _record_failure(failures, name, "row_limit_exceeded_or_invalid")
            if type(entry.get("bytes")) is not int or not 1 <= entry["bytes"] <= MAX_BYTES_PER_SHARD:
                _record_failure(failures, name, "byte_limit_exceeded_or_invalid")
        else:
            binding_names.add(name)
            binding_kind = entry.get("kind")
            if binding_kind not in ("schema", "receipt", "source_index") or not name.startswith(f"bindings/{binding_kind}/"):
                _record_failure(failures, name, "binding_name_mismatch")
        state = "pass"
        if not path.is_file() or path.is_symlink():
            state = "fail"
            _record_failure(failures, name, "unavailable")
        elif path.stat().st_size != entry.get("bytes"):
            state = "fail"
            _record_failure(failures, name, "bytes_mismatch")
        elif sha256_file(path) != entry.get("sha256"):
            state = "fail"
            _record_failure(failures, name, "sha256_mismatch")
        elif kind == "binding":
            try:
                if entry.get("kind") == "source_index":
                    _load_source_index(path, VerificationError)
                else:
                    _validate_binding_document(path, str(entry.get("kind")))
            except DosaError:
                state = "fail"
                _record_failure(failures, name, "binding_content_invalid")
        if kind == "binding":
            binding_results.append({"kind": str(entry.get("kind")), "name": name, "status": state})

    actual_payload_names = {
        path.relative_to(package).as_posix() for path in package.rglob("*.parquet") if path.is_file()
    }
    for name in sorted(actual_payload_names - payload_names):
        _record_failure(failures, name, "unmanifested_payload")
    bindings_root = package / "bindings"
    actual_binding_names = (
        {path.relative_to(package).as_posix() for path in bindings_root.rglob("*") if path.is_file()}
        if bindings_root.exists()
        else set()
    )
    for name in sorted(actual_binding_names - binding_names):
        _record_failure(failures, name, "unmanifested_binding")

    # Row count and the declared compression are properties of the Parquet
    # footer, not of the filesystem.  A successful external verification must
    # inspect them with DuckDB; absence of DuckDB is an explicit dependency
    # refusal rather than a hash-only false pass.
    if not failures:
        duckdb = require_duckdb()
        con = duckdb.connect(":memory:")
        try:
            for payload in payloads:
                name = payload["name"]
                path = _package_path(package, name)
                try:
                    metadata = con.execute(
                        "SELECT num_rows, file_size_bytes FROM parquet_file_metadata(?)",
                        [str(path)],
                    ).fetchone()
                    compressions = {
                        str(row[0]).lower()
                        for row in con.execute(
                            "SELECT DISTINCT compression FROM parquet_metadata(?)",
                            [str(path)],
                        ).fetchall()
                    }
                except Exception:
                    _record_failure(failures, name, "parquet_metadata_unreadable")
                    continue
                if int(metadata[0]) != payload["rows"]:
                    _record_failure(failures, name, "parquet_row_count_mismatch")
                if int(metadata[0]) > MAX_ROWS_PER_SHARD:
                    _record_failure(failures, name, "parquet_row_limit_exceeded")
                if int(metadata[1]) > MAX_BYTES_PER_SHARD:
                    _record_failure(failures, name, "parquet_byte_limit_exceeded")
                if compressions != {"zstd"}:
                    _record_failure(failures, name, "parquet_compression_mismatch")
        finally:
            con.close()

    expected_capacity: list[dict[str, Any]] = []
    for scale in sorted({str(payload.get("scale")) for payload in payloads if isinstance(payload, dict)}):
        scale_payloads = [payload for payload in payloads if isinstance(payload, dict) and payload.get("scale") == scale]
        expected_capacity.append(
            {
                "scale": scale,
                "compression": "zstd",
                "rows": sum(payload.get("rows", 0) if type(payload.get("rows")) is int else 0 for payload in scale_payloads),
                "bytes": sum(payload.get("bytes", 0) if type(payload.get("bytes")) is int else 0 for payload in scale_payloads),
                "shards": len(scale_payloads),
            }
        )
    if manifest.get("scale_capacity") != expected_capacity:
        _record_failure(failures, "scale_capacity", "capacity_totals_mismatch")

    result = {
        "status": "ok" if not failures else "failed",
        "package_version": PACKAGE_VERSION,
        "payloads_checked": len(payloads),
        "bindings": binding_results,
        "failures": failures,
    }
    if failures:
        raise VerificationError(json_dumps(result))
    return result


def _require_file(path: pathlib.Path, label: str) -> pathlib.Path:
    if not path.is_file() or path.is_symlink():
        raise DosaError(f"{label} is unavailable or is a symlink: {path}")
    return path


def _resolve_runner(runner: str | None) -> tuple[list[str], pathlib.Path]:
    configured = runner or os.environ.get("DOSA_SOUNIO_RUNNER")
    if not configured:
        raise RefusalError("canonical Sounio runner is not configured (use --runner or DOSA_SOUNIO_RUNNER)")
    command = shlex.split(configured)
    if not command:
        raise RefusalError("canonical Sounio runner is empty")
    executable_value = shutil.which(command[0])
    if executable_value is None:
        candidate = pathlib.Path(command[0]).expanduser()
        executable_value = str(candidate.resolve()) if candidate.is_file() else None
    if executable_value is None:
        raise RefusalError("configured canonical Sounio runner is not executable")
    executable = pathlib.Path(executable_value)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise RefusalError("configured canonical Sounio runner is not executable")
    command[0] = str(executable)
    return command, executable


def _immutable_regular_file(path: pathlib.Path, label: str) -> pathlib.Path:
    """Require a local, non-symlink, read-only artifact before hashing it.

    This is an operational immutability control: its bytes are rechecked after
    invoking the runner.  It is intentionally not represented as a proof of
    compiler behavior or calibration semantics.
    """
    if not path.is_file() or path.is_symlink():
        raise RefusalError(f"{label} is unavailable or is a symlink: {path}")
    if path.stat().st_mode & 0o222:
        raise RefusalError(f"{label} must be a read-only immutable artifact: {path}")
    return path


def _strict_json_object(raw: bytes, label: str) -> dict[str, Any]:
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicate_keys)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise RefusalError(f"{label} must be valid duplicate-free UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise RefusalError(f"{label} root must be an object")
    return value


def _attestation_receipt_path(attestation: pathlib.Path, value: Any) -> pathlib.Path:
    if not isinstance(value, str) or not value:
        raise RefusalError("runner attestation receipt_path must be a non-empty relative path")
    candidate = pathlib.PurePosixPath(value)
    if candidate.is_absolute() or ".." in candidate.parts or value != candidate.as_posix():
        raise RefusalError("runner attestation receipt_path must be a safe relative POSIX path")
    return attestation.parent / pathlib.Path(*candidate.parts)


def _load_runner_attestation(attestation_path: pathlib.Path, executable: pathlib.Path) -> dict[str, str]:
    """Validate external build provenance without inferring semantic validity."""
    attestation = _immutable_regular_file(attestation_path, "runner attestation")
    raw = attestation.read_bytes()
    attestation_sha256 = hashlib.sha256(raw).hexdigest()
    document = _strict_json_object(raw, "runner attestation")
    required = {
        "attestation_version",
        "evidence_scope",
        "repository_url",
        "source_commit",
        "source_sha256",
        "compiler_sha256",
        "executable_sha256",
        "receipt_path",
        "receipt_sha256",
    }
    if set(document) != required:
        raise RefusalError("runner attestation keys mismatch")
    for field in required - {"receipt_path"}:
        if not isinstance(document.get(field), str):
            raise RefusalError(f"runner attestation {field} must be a string")
    if document["attestation_version"] != RUNNER_ATTESTATION_VERSION:
        raise RefusalError("runner attestation version mismatch")
    if document["repository_url"] != SOUNIO_OFFICIAL_REPOSITORY:
        raise RefusalError("runner attestation repository must be the official Sounio repository")
    if document["evidence_scope"] not in {"fixture-only-non-semantic", "build-provenance-only-non-semantic"}:
        raise RefusalError("runner attestation evidence_scope is not an accepted non-semantic scope")
    if not re.fullmatch(r"[0-9a-f]{40}", document["source_commit"]):
        raise RefusalError("runner attestation source_commit must be a lowercase 40-hex commit")
    for field in ("source_sha256", "compiler_sha256", "executable_sha256", "receipt_sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", document[field]):
            raise RefusalError(f"runner attestation {field} must be a lowercase SHA-256")
    if document["executable_sha256"] != sha256_file(executable):
        raise RefusalError("runner attestation executable SHA-256 does not bind the configured runner")
    receipt = _attestation_receipt_path(attestation, document["receipt_path"])
    if receipt.resolve() == attestation.resolve():
        raise RefusalError("runner attestation receipt must be a separate artifact")
    if not receipt.is_file() or receipt.is_symlink():
        raise RefusalError(f"runner attestation receipt is unavailable or is a symlink: {receipt}")
    if sha256_file(receipt) != document["receipt_sha256"]:
        raise RefusalError("runner attestation receipt SHA-256 mismatch")
    return {
        "sha256": attestation_sha256,
        "evidence_scope": document["evidence_scope"],
        "receipt_path": document["receipt_path"],
        "receipt_sha256": document["receipt_sha256"],
    }


def _atlas_identities(paths: tuple[pathlib.Path, ...]) -> list[dict[str, Any]]:
    if not paths:
        raise DosaError("at least one --atlas-strata payload is required")
    identities = []
    names: set[str] = set()
    for path in paths:
        _require_file(path, "atlas strata payload")
        if path.name in names:
            raise DosaError(f"duplicate atlas payload filename: {path.name}")
        names.add(path.name)
        identities.append({"name": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    return sorted(identities, key=lambda item: item["name"])


def calibrate(
    runner: str | None,
    runner_attestation: pathlib.Path | None,
    sequence: pathlib.Path,
    accession_version: str,
    scale: str,
    parameters: pathlib.Path,
    atlas_strata: tuple[pathlib.Path, ...],
) -> dict[str, Any]:
    """Invoke canonical Sounio with build provenance, not semantic attestation."""
    command, executable = _resolve_runner(runner)
    if runner_attestation is None:
        raise RefusalError("canonical Sounio runner attestation is required (use --runner-attestation)")
    attestation = _load_runner_attestation(runner_attestation, executable)
    attestation_before = sha256_file(runner_attestation)
    if attestation_before != attestation["sha256"]:
        raise RefusalError("runner attestation changed while it was being validated")
    _require_file(sequence, "new sequence")
    _require_file(parameters, "canonical parameter file")
    if not accession_version or any(character.isspace() for character in accession_version):
        raise DosaError("accession/version must be non-empty and contain no whitespace")
    scale = safe_partition(scale)
    atlas_identities = _atlas_identities(atlas_strata)
    atlas_by_name = {path.name: path for path in atlas_strata}
    ordered_atlas_paths = [atlas_by_name[item["name"]] for item in atlas_identities]
    expected_inputs = {
        "accession_version": accession_version,
        "scale": scale,
        "sequence_bytes": sequence.stat().st_size,
        "sequence_sha256": sha256_file(sequence),
        "parameters_bytes": parameters.stat().st_size,
        "parameters_sha256": sha256_file(parameters),
    }
    expected_producer = {
        "language": "Sounio",
        "canonical": True,
        "runner_sha256": sha256_file(executable),
        "attestation_sha256": attestation["sha256"],
    }
    invocation = command + [
        "--dosa-calibrate",
        "--runner-attestation-sha256",
        attestation["sha256"],
        "--sequence",
        str(sequence),
        "--accession-version",
        accession_version,
        "--scale",
        scale,
        "--parameters",
        str(parameters),
    ]
    for path in ordered_atlas_paths:
        invocation.extend(("--atlas-payload", str(path)))
    try:
        completed = subprocess.run(
            invocation,
            text=True,
            capture_output=True,
            check=False,
            timeout=300,
        )
    except subprocess.TimeoutExpired as exc:
        raise CalibrationError("canonical Sounio runner exceeded the 300 second timeout") from exc
    if completed.returncode != 0:
        raise CalibrationError(f"canonical Sounio runner exited {completed.returncode}: {completed.stderr.strip()}")
    if sha256_file(runner_attestation) != attestation_before:
        raise RefusalError("runner attestation changed while the runner was executing")
    receipt = _attestation_receipt_path(runner_attestation, attestation["receipt_path"])
    if not receipt.is_file() or receipt.is_symlink() or sha256_file(receipt) != attestation["receipt_sha256"]:
        raise RefusalError("runner attestation receipt changed while the runner was executing")
    try:
        envelope = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise CalibrationError("canonical Sounio runner did not emit exactly one JSON object") from exc
    if not isinstance(envelope, dict):
        raise CalibrationError("canonical Sounio runner envelope root must be an object")
    expected_keys = {"envelope_version", "producer", "inputs", "atlas_payloads", "comparison"}
    if set(envelope) != expected_keys:
        raise CalibrationError("canonical Sounio envelope keys mismatch; raw atlas strata/metrics are not accepted")
    if envelope.get("envelope_version") != CALIBRATION_ENVELOPE_VERSION:
        raise CalibrationError("canonical Sounio envelope version mismatch")
    if envelope.get("producer") != expected_producer:
        raise RefusalError("runner did not prove the configured canonical Sounio producer identity")
    if envelope.get("inputs") != expected_inputs:
        raise CalibrationError("canonical Sounio result is not bound to the requested sequence, accession, scale and parameters")
    if envelope.get("atlas_payloads") != atlas_identities:
        raise CalibrationError("canonical Sounio result is not bound to the exact atlas payload hashes")
    if envelope.get("comparison") != {
        "method": "canonical_sounio_atlas_strata_v1",
        "status": "match",
    }:
        raise CalibrationError("canonical Sounio calibration did not report an exact atlas-strata match")
    return {
        "status": "ok",
        "package_version": PACKAGE_VERSION,
        "canonical_producer": "Sounio",
        "runner_sha256": expected_producer["runner_sha256"],
        "runner_attestation_sha256": attestation["sha256"],
        "runner_attestation_evidence_scope": attestation["evidence_scope"],
        "runner_attestation_receipt": {
            "path": attestation["receipt_path"],
            "sha256": attestation["receipt_sha256"],
        },
        "provenance_boundary": "build_provenance_only_not_calibration_semantics",
        "inputs": expected_inputs,
        "atlas_payloads": atlas_identities,
        "comparison": envelope["comparison"],
    }
