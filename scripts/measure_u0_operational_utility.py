#!/usr/bin/env python3
"""Measure DOSA U0 lookup utility against a hash-closed Sounio recomputation.

Transport and provenance live here; scientific computation does not.  The
source is selected from the DOSA v3 source manifest, its public bytes are
checked against the local immutable manifest/integrity receipt, and one exact
FASTA record is canonicalized before it is handed to the configured Sounio
runner.  A separate, immutable build attestation binds the official Sounio
repository, source, compiler, executable, and build receipt.

``fixture`` scope may resolve HTTPS paths through ``--source-root`` as a local
cache.  Such evidence is explicitly non-promotable.  ``u0_pilot`` always
downloads the public HTTPS documents and asset; a local cache cannot substitute
for public recoverability.
"""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from typing import Any


GIB = 1024 ** 3
MAX_SHARD_BYTES = 5 * GIB
MAX_QUERY_SECONDS = 60.0
MIN_SPEEDUP = 100.0
EXIT_BLOCKED = 2
HEX64 = re.compile(r"[0-9a-f]{64}")
HEX40 = re.compile(r"[0-9a-f]{40}")
ACCESSION_RE = re.compile(r"[A-Za-z]+_[0-9]+\.[0-9]+")
PRIVATE_MARKERS = ("/users/", "/home/", "/private/", "localhost", ".local", "proxmox", "kubernetes", "cluster")
SOURCE_MANIFEST_VERSION = "3.0.0"
SOURCE_INTEGRITY_VERSION = "dosa-u0-source-integrity-receipt-1"
PAYLOAD_MANIFEST_VERSION = "dosa-v3-u0-dev-payload-manifest-3"
PUBLIC_PAYLOAD_MANIFEST_VERSION = "3.0.0"
SOURCE_INDEX_VERSION = "dosa-v3-source-index-1"
SOUNIO_ENVELOPE_VERSION = "dosa-v3-u0-sounio-n1000-recompute-1"
SOUNIO_ATTESTATION_VERSION = "dosa-v3-sounio-runner-attestation-1"
SOUNIO_OFFICIAL_REPOSITORY = "https://github.com/sounio-lang/sounio.git"
FASTA_ALPHABET = frozenset("ACGTURYSWKMBDHVN")


class OperationalError(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def strict_object_bytes(raw: bytes, label: str) -> dict[str, Any]:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=unique)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise OperationalError(f"{label} must be duplicate-free UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise OperationalError(f"{label} root must be an object")
    return value


def immutable_file(path: pathlib.Path, label: str) -> pathlib.Path:
    if not path.is_file() or path.is_symlink():
        raise OperationalError(f"{label} is unavailable or is a symlink: {path}")
    if path.stat().st_mode & 0o222:
        raise OperationalError(f"{label} must be read-only: {path}")
    return path


def regular_file(path: pathlib.Path, label: str) -> pathlib.Path:
    if not path.is_file() or path.is_symlink():
        raise OperationalError(f"{label} is unavailable or is a symlink: {path}")
    return path


def write_new(path: pathlib.Path, value: dict[str, Any]) -> None:
    if path.exists():
        raise OperationalError(f"refusing to overwrite evidence: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(canonical(value) + "\n", encoding="utf-8")


def require_scope(value: Any) -> str:
    if value not in ("fixture", "u0_pilot"):
        raise OperationalError("evidence_scope must be exactly fixture or u0_pilot")
    return str(value)


def safe_relative(value: Any, label: str) -> pathlib.PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value:
        raise OperationalError(f"{label} must be a normalized relative POSIX path")
    candidate = pathlib.PurePosixPath(value)
    if candidate.is_absolute() or candidate.as_posix() != value or any(part in ("", ".", "..") for part in candidate.parts):
        raise OperationalError(f"{label} must be a normalized relative POSIX path")
    return candidate


def public_https(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise OperationalError(f"{label} must be public HTTPS")
    parsed = urllib.parse.urlsplit(value)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or not host or parsed.username or parsed.password or parsed.fragment:
        raise OperationalError(f"{label} must be public HTTPS")
    if any(marker in value.lower() for marker in PRIVATE_MARKERS):
        raise OperationalError(f"{label} contains a private or cluster marker")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        address = None
    if address is not None and not address.is_global:
        raise OperationalError(f"{label} cannot use a private/non-global IP address")
    return value


def cache_path(root: pathlib.Path, url: str, label: str) -> pathlib.Path:
    path = urllib.parse.urlsplit(url).path.lstrip("/")
    relative = safe_relative(path, f"{label} cache path")
    resolved_root = root.resolve(strict=True)
    candidate = root / pathlib.Path(*relative.parts)
    try:
        candidate.resolve(strict=True).relative_to(resolved_root)
    except (OSError, ValueError) as exc:
        raise OperationalError(f"{label} cache path escapes --source-root or is unavailable") from exc
    return regular_file(candidate, f"cached {label}")


def download_bytes(url: str, scope: str, root: pathlib.Path | None, label: str) -> bytes:
    public_https(url, label)
    if scope == "fixture":
        if root is None:
            raise OperationalError("fixture evidence requires --source-root HTTPS cache")
        return cache_path(root, url, label).read_bytes()
    if root is not None:
        raise OperationalError("u0_pilot must download public sources; --source-root cache is forbidden")
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            return response.read(128 * 1024 * 1024 + 1)
    except Exception as exc:
        raise OperationalError(f"cannot download public {label}: {exc}") from exc


def download_file(url: str, scope: str, root: pathlib.Path | None, target: pathlib.Path, label: str) -> None:
    public_https(url, label)
    if scope == "fixture":
        if root is None:
            raise OperationalError("fixture evidence requires --source-root HTTPS cache")
        source = cache_path(root, url, label)
        with source.open("rb") as incoming, target.open("xb") as output:
            for block in iter(lambda: incoming.read(1024 * 1024), b""):
                output.write(block)
        return
    if root is not None:
        raise OperationalError("u0_pilot must download public sources; --source-root cache is forbidden")
    try:
        with urllib.request.urlopen(url, timeout=60) as response, target.open("xb") as output:
            for block in iter(lambda: response.read(1024 * 1024), b""):
                output.write(block)
    except Exception as exc:
        raise OperationalError(f"cannot download public {label}: {exc}") from exc


def bind_public_document(local: pathlib.Path, public_url: str, scope: str, root: pathlib.Path | None, label: str) -> tuple[dict[str, Any], str]:
    local = immutable_file(local, f"local {label}")
    local_raw = local.read_bytes()
    public_raw = download_bytes(public_url, scope, root, label)
    if public_raw != local_raw:
        raise OperationalError(f"public {label} bytes do not match the supplied immutable local document")
    return strict_object_bytes(local_raw, label), sha256_bytes(local_raw)


def select_source(manifest: dict[str, Any], integrity: dict[str, Any], accession: str, manifest_sha: str) -> dict[str, Any]:
    if manifest.get("schema_version") != SOURCE_MANIFEST_VERSION or manifest.get("source_provider") != "NCBI_Datasets":
        raise OperationalError("unsupported DOSA v3 source manifest")
    if integrity.get("schema_version") != SOURCE_INTEGRITY_VERSION:
        raise OperationalError("unsupported source integrity receipt")
    if integrity.get("source_manifest_sha256") != manifest_sha or integrity.get("scientific_metrics_computed") is not False:
        raise OperationalError("source integrity receipt does not bind the supplied source manifest")
    records = manifest.get("selected_records")
    matches = [row for row in records if isinstance(row, dict) and row.get("sequence_accession_version") == accession] if isinstance(records, list) else []
    if len(matches) != 1:
        raise OperationalError("source manifest must contain exactly one selected accession.version")
    record = matches[0]
    source_id = record.get("source_record_id")
    assembly = record.get("assembly_accession_version")
    if not isinstance(source_id, str) or not isinstance(assembly, str):
        raise OperationalError("selected source record lacks source_record_id or assembly accession")
    assets = manifest.get("package_assets")
    fasta = [
        row for row in assets
        if isinstance(row, dict) and row.get("asset_kind") == "fasta"
        and row.get("assembly_accession_version") == assembly
        and isinstance(row.get("selected_record_ids"), list) and source_id in row["selected_record_ids"]
    ] if isinstance(assets, list) else []
    if len(fasta) != 1:
        raise OperationalError("source manifest must bind exactly one FASTA asset for the selected record")
    asset = fasta[0]
    if not isinstance(asset.get("sha256"), str) or not HEX64.fullmatch(asset["sha256"]):
        raise OperationalError("selected FASTA asset lacks a lowercase SHA-256")
    if type(asset.get("size_bytes")) is not int or asset["size_bytes"] < 1:
        raise OperationalError("selected FASTA asset has invalid size_bytes")
    asset_path = safe_relative(asset.get("package_path"), "selected FASTA package_path").as_posix()
    integrity_records = integrity.get("records")
    matched_integrity = [row for row in integrity_records if isinstance(row, dict) and row.get("sequence_accession_version") == accession] if isinstance(integrity_records, list) else []
    if len(matched_integrity) != 1:
        raise OperationalError("source integrity receipt must contain exactly one matching accession.version")
    normalized = matched_integrity[0]
    if normalized.get("source_record_id") not in (None, source_id) or normalized.get("assembly_accession_version") not in (None, assembly):
        raise OperationalError("source integrity record identity does not match source manifest")
    if not isinstance(normalized.get("normalized_fasta_sha256"), str) or not HEX64.fullmatch(normalized["normalized_fasta_sha256"]):
        raise OperationalError("source integrity record lacks normalized FASTA SHA-256")
    if type(normalized.get("normalized_fasta_length_bp")) is not int or normalized["normalized_fasta_length_bp"] < 1:
        raise OperationalError("source integrity record lacks normalized FASTA length")
    if normalized.get("fasta_asset_sha256") not in (None, asset["sha256"]):
        raise OperationalError("source integrity record FASTA asset SHA-256 mismatch")
    return {"record": record, "asset": asset, "asset_path": asset_path, "integrity": normalized}


def extract_fasta(raw: pathlib.Path, accession: str, canonical_path: pathlib.Path) -> tuple[int, str, str]:
    matches: list[str] = []
    current_matches = False
    bases: list[str] = []
    with raw.open(encoding="utf-8") as handle:
        for line_no, raw_line in enumerate(handle, start=1):
            line = raw_line.rstrip("\r\n")
            if line.startswith(">"):
                if current_matches:
                    matches.append("".join(bases))
                tokens = set(ACCESSION_RE.findall(line[1:]))
                current_matches = accession in tokens
                bases = []
                continue
            if current_matches:
                sequence = "".join(line.split()).upper()
                if not sequence or any(base not in FASTA_ALPHABET for base in sequence):
                    raise OperationalError(f"selected FASTA has invalid sequence bytes at line {line_no}")
                bases.append(sequence)
    if current_matches:
        matches.append("".join(bases))
    if len(matches) != 1 or not matches[0]:
        raise OperationalError("downloaded FASTA must contain exactly one non-empty selected accession record")
    sequence = matches[0]
    normalized_sha = sha256_bytes(sequence.encode("ascii"))
    canonical_bytes = f">{accession}\n{sequence}\n".encode("ascii")
    canonical_path.write_bytes(canonical_bytes)
    return len(sequence), normalized_sha, sha256_bytes(canonical_bytes)


def executable_command(value: str, label: str) -> list[str]:
    command = shlex.split(value)
    if not command:
        raise OperationalError(f"{label} command is empty")
    first = pathlib.Path(command[0]).expanduser()
    if first.is_file():
        command[0] = str(first.resolve())
    elif not os.path.isabs(command[0]):
        for directory in os.environ.get("PATH", "").split(os.pathsep):
            candidate = pathlib.Path(directory) / command[0]
            if candidate.is_file() and os.access(candidate, os.X_OK):
                command[0] = str(candidate.resolve())
                break
    executable = pathlib.Path(command[0])
    if not executable.is_file() or executable.is_symlink() or not os.access(executable, os.X_OK):
        raise OperationalError(f"{label} executable is unavailable or not executable")
    return command


def command_json(command: list[str], label: str, timeout: float) -> tuple[dict[str, Any], float]:
    started = time.monotonic()
    try:
        completed = subprocess.run(command, text=True, capture_output=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise OperationalError(f"{label} exceeded {timeout:.0f} seconds") from exc
    elapsed = time.monotonic() - started
    if completed.returncode != 0:
        raise OperationalError(f"{label} exited {completed.returncode}: {completed.stderr.strip()}")
    try:
        value = json.loads(completed.stdout.strip())
    except json.JSONDecodeError as exc:
        raise OperationalError(f"{label} did not emit exactly one JSON object") from exc
    if not isinstance(value, dict):
        raise OperationalError(f"{label} JSON root must be an object")
    return value, elapsed


def load_payloads(package: pathlib.Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]], pathlib.Path]:
    manifest_path = regular_file(package / "dosa-payload-manifest.json", "payload manifest")
    manifest = strict_object_bytes(manifest_path.read_bytes(), "payload manifest")
    if manifest.get("manifest_version") != PAYLOAD_MANIFEST_VERSION or manifest.get("package_version") != "U0-dev":
        raise OperationalError("unsupported DOSA U0 payload manifest")
    payloads = manifest.get("payloads")
    if not isinstance(payloads, list):
        raise OperationalError("payload manifest payloads must be a list")
    by_name: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        if not isinstance(payload, dict) or not isinstance(payload.get("name"), str) or payload["name"] in by_name:
            raise OperationalError("payload manifest has a missing/duplicate payload name")
        name = safe_relative(payload["name"], "payload name").as_posix()
        if not isinstance(payload.get("sha256"), str) or not HEX64.fullmatch(payload["sha256"]):
            raise OperationalError(f"payload lacks lowercase SHA-256: {name}")
        if type(payload.get("rows")) is not int or not 1 <= payload["rows"] <= 5_000_000:
            raise OperationalError(f"payload rows violate U0 shard constraint: {name}")
        if type(payload.get("bytes")) is not int or not 1 <= payload["bytes"] <= MAX_SHARD_BYTES:
            raise OperationalError(f"payload bytes violate U0 shard constraint: {name}")
        by_name[name] = payload
    if not by_name:
        raise OperationalError("payload manifest has no payloads")
    return manifest, by_name, manifest_path


def bind_package_to_public_manifest(
    public_manifest_path: pathlib.Path,
    package_manifest_path: pathlib.Path,
    parameters_sha: str,
    source_manifest_sha: str,
) -> tuple[str, dict[str, Any]]:
    """Bind one physical shard package to the logical five-table manifest.

    The public manifest owns the source/parameter closure once.  Package
    manifests only close their physical routed shards, so no source hash is
    repeated in a window record or inferred from a shard path.
    """
    public_manifest_path = immutable_file(public_manifest_path, "public payload manifest")
    public = strict_object_bytes(public_manifest_path.read_bytes(), "public payload manifest")
    if public.get("schema_version") != PUBLIC_PAYLOAD_MANIFEST_VERSION:
        raise OperationalError("unsupported public DOSA v3 payload manifest")
    if public.get("parameters_sha256") != parameters_sha:
        raise OperationalError("public payload manifest parameters SHA-256 mismatch")
    if public.get("source_manifest_sha256") != source_manifest_sha:
        raise OperationalError("public payload manifest source manifest SHA-256 mismatch")
    tables = public.get("public_tables")
    if not isinstance(tables, list) or len(tables) != 5:
        raise OperationalError("public payload manifest must contain exactly five public tables")
    expected_tables = {
        "runs.parquet", "replicons.parquet", "window_operator_profiles.parquet",
        "replicon_operator_summary.parquet", "excluded_records.parquet",
    }
    if {row.get("filename") for row in tables if isinstance(row, dict)} != expected_tables:
        raise OperationalError("public payload manifest does not close the required five-table set")
    window_rows = [row for row in tables if isinstance(row, dict) and row.get("filename") == "window_operator_profiles.parquet"]
    if len(window_rows) != 1 or not isinstance(window_rows[0].get("storage"), dict):
        raise OperationalError("public payload manifest lacks a window table storage declaration")
    storage = window_rows[0]["storage"]
    if storage.get("layout") != "package_manifest_partitioned" or storage.get("partitioning") != "scale_then_sha256_accession_bucket":
        raise OperationalError("public window table must use package-manifest scale/bucket partitioning")
    package_entries = public.get("package_manifests")
    if not isinstance(package_entries, list) or not package_entries:
        raise OperationalError("public payload manifest has no package manifests")
    package_sha = sha256_file(package_manifest_path)
    matches = [
        entry for entry in package_entries
        if isinstance(entry, dict) and entry.get("sha256") == package_sha
    ]
    if len(matches) != 1:
        raise OperationalError("package manifest is not referenced exactly once by the public payload manifest")
    entry = matches[0]
    package_id = entry.get("package_manifest_id")
    if not isinstance(package_id, str) or package_id not in storage.get("package_manifest_ids", []):
        raise OperationalError("package manifest is not referenced by the partitioned public window table")
    if entry.get("manifest_version") != PAYLOAD_MANIFEST_VERSION or entry.get("package_version") != "U0-dev":
        raise OperationalError("public package manifest reference has an unsupported CLI manifest version")
    if entry.get("table_filename") != "window_operator_profiles.parquet":
        raise OperationalError("package manifest reference does not target the window table")
    if entry.get("size_bytes") != package_manifest_path.stat().st_size:
        raise OperationalError("public package manifest reference size mismatch")
    return sha256_file(public_manifest_path), entry


def validate_query(
    result: dict[str, Any], payloads: dict[str, dict[str, Any]], accession: str,
    start: int, end: int, scale: str, asset_url: str, source_index_locator: str, sequence_sha: str,
    normalized_sha: str, source_manifest_sha: str, source_integrity_sha: str,
    package: pathlib.Path, payload_manifest: pathlib.Path,
) -> tuple[list[str], int]:
    expected_query = {"accession_version": accession, "accession_sha256_bucket": hashlib.sha256(accession.encode()).hexdigest()[:2], "coordinate_start": start, "coordinate_end": end, "scale": scale}
    if result.get("status") != "ok" or result.get("query") != expected_query:
        raise OperationalError("dosa query result is not bound to the exact requested window")
    read = result.get("shards_read")
    if not isinstance(read, list) or not read or len(set(read)) != len(read) or any(not isinstance(name, str) for name in read):
        raise OperationalError("dosa query must report non-empty unique shards_read")
    for name in read:
        if name not in payloads:
            raise OperationalError(f"dosa query read an unbound shard: {name}")
        shard = package / pathlib.Path(*safe_relative(name, "queried shard").parts)
        if not shard.is_file() or shard.is_symlink() or shard.stat().st_size != payloads[name]["bytes"] or sha256_file(shard) != payloads[name]["sha256"]:
            raise OperationalError(f"queried shard bytes/SHA-256 mismatch: {name}")
    manifest = strict_object_bytes(payload_manifest.read_bytes(), "payload manifest")
    bindings = manifest.get("bindings")
    source_bindings = [item for item in bindings if isinstance(item, dict) and item.get("kind") == "source_index"] if isinstance(bindings, list) else []
    if len(source_bindings) != 1:
        raise OperationalError("payload manifest must bind exactly one portable source index")
    binding = source_bindings[0]
    source_index_path = package / pathlib.Path(*safe_relative(binding.get("name"), "source index binding name").parts)
    if not source_index_path.is_file() or source_index_path.is_symlink():
        raise OperationalError("bound source index is unavailable or is a symlink")
    source_index_sha = sha256_file(source_index_path)
    if source_index_path.stat().st_size != binding.get("bytes") or source_index_sha != binding.get("sha256"):
        raise OperationalError("bound source index bytes/SHA-256 mismatch")
    source_index = strict_object_bytes(source_index_path.read_bytes(), "source index")
    if source_index.get("source_index_version") != SOURCE_INDEX_VERSION or not isinstance(source_index.get("records"), dict):
        raise OperationalError("unsupported portable source index")
    source = source_index["records"].get(accession)
    expected_source = {
        "locator": source_index_locator,
        "canonical_sequence_input_sha256": sequence_sha,
        "normalized_sequence_sha256": normalized_sha,
        "source_manifest_sha256": source_manifest_sha,
        "source_integrity_sha256": source_integrity_sha,
    }
    if not isinstance(source, dict) or any(source.get(key) != value for key, value in expected_source.items()):
        raise OperationalError("bound source index record does not match the recovered public FASTA provenance")
    if result.get("source_index_sha256") != source_index_sha or result.get("source_record") != source:
        raise OperationalError("dosa query did not return the exact bound source index record")
    if result.get("package_manifest_sha256") != sha256_file(payload_manifest):
        raise OperationalError("dosa query did not bind the exact payload manifest")
    query_payloads = result.get("payloads")
    if not isinstance(query_payloads, list) or sorted(item.get("name") for item in query_payloads if isinstance(item, dict)) != sorted(read):
        raise OperationalError("dosa query payload bindings do not match shards_read")
    for item in query_payloads:
        if not isinstance(item, dict) or item.get("sha256") != payloads[item.get("name")]["sha256"]:
            raise OperationalError("dosa query payload SHA-256 is not manifest-bound")
    return read, sum(int(payloads[name]["bytes"]) for name in read)


def load_attestation(attestation_path: pathlib.Path, receipt_path: pathlib.Path, runner: pathlib.Path) -> dict[str, str]:
    attestation_path = immutable_file(attestation_path, "Sounio runner attestation")
    receipt_path = immutable_file(receipt_path, "Sounio build receipt")
    raw = attestation_path.read_bytes()
    document = strict_object_bytes(raw, "Sounio runner attestation")
    required = {"attestation_version", "evidence_scope", "repository_url", "source_commit", "source_sha256", "compiler_sha256", "executable_sha256", "receipt_path", "receipt_sha256"}
    if set(document) != required:
        raise OperationalError("Sounio runner attestation keys mismatch")
    if document.get("attestation_version") != SOUNIO_ATTESTATION_VERSION or document.get("repository_url") != SOUNIO_OFFICIAL_REPOSITORY:
        raise OperationalError("Sounio runner attestation version/repository mismatch")
    if document.get("evidence_scope") not in ("fixture-only-non-semantic", "build-provenance-only-non-semantic"):
        raise OperationalError("Sounio runner attestation evidence_scope is invalid")
    if not isinstance(document.get("source_commit"), str) or not HEX40.fullmatch(document["source_commit"]):
        raise OperationalError("Sounio runner attestation source_commit is invalid")
    for field in ("source_sha256", "compiler_sha256", "executable_sha256", "receipt_sha256"):
        if not isinstance(document.get(field), str) or not HEX64.fullmatch(document[field]):
            raise OperationalError(f"Sounio runner attestation {field} is invalid")
    relative = safe_relative(document.get("receipt_path"), "Sounio build receipt path")
    if (attestation_path.parent / pathlib.Path(*relative.parts)).resolve() != receipt_path.resolve():
        raise OperationalError("Sounio runner attestation receipt_path does not identify the supplied separate build receipt")
    if document["receipt_sha256"] != sha256_file(receipt_path):
        raise OperationalError("Sounio build receipt SHA-256 mismatch")
    if document["executable_sha256"] != sha256_file(runner):
        raise OperationalError("Sounio runner attestation executable SHA-256 mismatch")
    return {"sha256": sha256_bytes(raw), "receipt_sha256": document["receipt_sha256"], "evidence_scope": str(document["evidence_scope"])}


def render_sounio_command(template: str, sequence: pathlib.Path, accession: str, scale: str, parameters: pathlib.Path, start: int, end: int, output: pathlib.Path, attestation_sha: str) -> list[str]:
    required = {"{sequence}", "{accession_version}", "{scale}", "{parameters}", "{coordinate_start}", "{coordinate_end}", "{output}", "{attestation_sha256}"}
    if any(token not in template for token in required):
        raise OperationalError("--sounio-command must bind sequence, accession, scale, parameters, coordinates, output, and attestation_sha256")
    return executable_command(template.format(sequence=sequence, accession_version=accession, scale=scale, parameters=parameters, coordinate_start=start, coordinate_end=end, output=output, attestation_sha256=attestation_sha), "canonical Sounio")


def validate_sounio(envelope: dict[str, Any], sequence: pathlib.Path, accession: str, scale: str, parameters: pathlib.Path, start: int, end: int, runner: pathlib.Path, output: pathlib.Path, attestation_sha: str) -> dict[str, Any]:
    expected_inputs = {"accession_version": accession, "scale": scale, "coordinate_start": start, "coordinate_end": end, "sequence_bytes": sequence.stat().st_size, "sequence_sha256": sha256_file(sequence), "parameters_bytes": parameters.stat().st_size, "parameters_sha256": sha256_file(parameters)}
    expected_keys = {"schema_version", "producer", "inputs", "null_model", "null_replicates", "output_bytes", "output_sha256"}
    expected_producer = {"language": "Sounio", "canonical": True, "runner_sha256": sha256_file(runner), "attestation_sha256": attestation_sha}
    if set(envelope) != expected_keys or envelope.get("schema_version") != SOUNIO_ENVELOPE_VERSION:
        raise OperationalError("canonical Sounio output envelope schema mismatch")
    if envelope.get("producer") != expected_producer or envelope.get("inputs") != expected_inputs:
        raise OperationalError("canonical Sounio envelope producer/input identities mismatch")
    if envelope.get("null_model") != "euler_wilson_fixed_endpoints_v1" or envelope.get("null_replicates") != 1000:
        raise OperationalError("canonical Sounio envelope is not the pinned n=1000 null")
    if not output.is_file() or output.is_symlink() or output.stat().st_size < 1:
        raise OperationalError("canonical Sounio runner did not persist its output")
    actual = {"bytes": output.stat().st_size, "sha256": sha256_file(output)}
    if envelope.get("output_bytes") != actual["bytes"] or envelope.get("output_sha256") != actual["sha256"]:
        raise OperationalError("canonical Sounio output bytes/SHA-256 mismatch")
    return actual


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dosa", required=True)
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--source-manifest", required=True, type=pathlib.Path)
    parser.add_argument("--source-integrity", required=True, type=pathlib.Path)
    parser.add_argument("--public-payload-manifest", required=True, type=pathlib.Path)
    parser.add_argument("--source-manifest-url", required=True)
    parser.add_argument("--source-integrity-url", required=True)
    parser.add_argument("--source-root", type=pathlib.Path)
    parser.add_argument("--accession-version", required=True)
    parser.add_argument("--coordinate", required=True)
    parser.add_argument("--scale", required=True)
    parser.add_argument("--parameters", required=True, type=pathlib.Path)
    parser.add_argument("--sounio-command", required=True)
    parser.add_argument("--sounio-attestation", required=True, type=pathlib.Path)
    parser.add_argument("--sounio-build-receipt", required=True, type=pathlib.Path)
    parser.add_argument("--evidence-scope", required=True, choices=("fixture", "u0_pilot"))
    parser.add_argument("--query-output", required=True, type=pathlib.Path)
    parser.add_argument("--speed-output", required=True, type=pathlib.Path)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        scope = require_scope(args.evidence_scope)
        if args.query_output == args.speed_output or args.query_output.exists() or args.speed_output.exists():
            raise OperationalError("operational evidence outputs must be distinct and new")
        try:
            start_text, end_text = args.coordinate.split(":", 1)
            start, end = int(start_text), int(end_text)
        except ValueError as exc:
            raise OperationalError("--coordinate must be zero-based half-open start:end") from exc
        if start < 0 or end <= start:
            raise OperationalError("--coordinate must be zero-based half-open start:end")
        parameters = regular_file(args.parameters, "parameters")
        package = args.package.resolve(strict=True)
        if not package.is_dir() or package.is_symlink():
            raise OperationalError("package is unavailable or is a symlink")
        manifest, manifest_sha = bind_public_document(args.source_manifest, public_https(args.source_manifest_url, "source manifest URL"), scope, args.source_root, "source manifest")
        integrity, integrity_sha = bind_public_document(args.source_integrity, public_https(args.source_integrity_url, "source integrity URL"), scope, args.source_root, "source integrity receipt")
        selected = select_source(manifest, integrity, args.accession_version, manifest_sha)
        asset_url = urllib.parse.urljoin(args.source_manifest_url, selected["asset_path"])
        public_https(asset_url, "manifest-relative FASTA URL")
        _, payloads, package_manifest_path = load_payloads(package)
        package_manifest_sha = sha256_file(package_manifest_path)
        public_payload_manifest_sha, package_reference = bind_package_to_public_manifest(
            args.public_payload_manifest, package_manifest_path, sha256_file(parameters), manifest_sha,
        )
        dosa = executable_command(args.dosa, "dosa")
        with tempfile.TemporaryDirectory(prefix="dosa-u0-operational-") as temp_name:
            temp = pathlib.Path(temp_name)
            raw_fasta = temp / "source-asset.fna"
            canonical_fasta = temp / "selected-canonical.fa"
            download_file(asset_url, scope, args.source_root, raw_fasta, "selected FASTA asset")
            asset = selected["asset"]
            raw_sha = sha256_file(raw_fasta)
            if raw_fasta.stat().st_size != asset["size_bytes"] or raw_sha != asset["sha256"]:
                raise OperationalError("downloaded FASTA raw bytes/SHA-256 do not match source manifest")
            length, normalized_sha, sequence_input_sha = extract_fasta(raw_fasta, args.accession_version, canonical_fasta)
            integrity_record = selected["integrity"]
            if length != integrity_record["normalized_fasta_length_bp"] or normalized_sha != integrity_record["normalized_fasta_sha256"]:
                raise OperationalError("canonical FASTA record does not match source integrity length/SHA-256")
            if end > length:
                raise OperationalError("requested coordinate exceeds recovered selected sequence")
            query_command = dosa + ["query", "--package", str(package), "--accession-version", args.accession_version, "--coordinate", args.coordinate, "--scale", args.scale]
            query_result, query_seconds = command_json(query_command, "dosa query", MAX_QUERY_SECONDS)
            shards_read, transfer_bytes = validate_query(
                query_result, payloads, args.accession_version, start, end,
                args.scale, asset_url, selected["asset_path"], sequence_input_sha, normalized_sha,
                manifest_sha, integrity_sha, package, package_manifest_path,
            )
            recompute_output = temp / "sounio-n1000.jsonl"
            template_tokens = shlex.split(args.sounio_command)
            if not template_tokens:
                raise OperationalError("canonical Sounio command is empty")
            preliminary = executable_command(template_tokens[0], "canonical Sounio")
            runner = pathlib.Path(preliminary[0])
            attestation = load_attestation(args.sounio_attestation, args.sounio_build_receipt, runner)
            expected_attestation_scope = "fixture-only-non-semantic" if scope == "fixture" else "build-provenance-only-non-semantic"
            if attestation["evidence_scope"] != expected_attestation_scope:
                raise OperationalError(
                    f"Sounio attestation evidence_scope must be {expected_attestation_scope} for {scope} evidence"
                )
            attestation_before = sha256_file(args.sounio_attestation)
            receipt_before = sha256_file(args.sounio_build_receipt)
            sounio_command = render_sounio_command(args.sounio_command, canonical_fasta, args.accession_version, args.scale, parameters, start, end, recompute_output, attestation["sha256"])
            if pathlib.Path(sounio_command[0]).resolve() != runner.resolve():
                raise OperationalError("Sounio command runner changed between attestation and invocation")
            sounio_envelope, recompute_seconds = command_json(sounio_command, "canonical Sounio n=1000 recomputation", 3600.0)
            if sha256_file(args.sounio_attestation) != attestation_before or sha256_file(args.sounio_build_receipt) != receipt_before:
                raise OperationalError("Sounio attestation/build receipt changed during execution")
            recompute_artifact = validate_sounio(sounio_envelope, canonical_fasta, args.accession_version, args.scale, parameters, start, end, runner, recompute_output, attestation["sha256"])
        query_pass = transfer_bytes <= MAX_SHARD_BYTES and query_seconds <= MAX_QUERY_SECONDS
        speedup = recompute_seconds / query_seconds if query_seconds > 0 else float("inf")
        speed_pass = speedup >= MIN_SPEEDUP
        query_report = {
            "schema_version": "dosa-v3-u0-query-utility-evidence-1", "status": "pass" if query_pass else "fail", "evidence_scope": scope,
            "accession_version": args.accession_version, "coordinate": {"start": start, "end": end, "convention": "zero_based_half_open"}, "scale": args.scale,
            "post_download_query_seconds": query_seconds, "shard_download_bytes": transfer_bytes, "shards_read": shards_read,
            "payload_hashes_verified": True, "source_sequence_recovered": True, "source_sequence_sha256_verified": True, "cluster_access_used": False,
            "source_locator": asset_url, "source_manifest_public_url": args.source_manifest_url, "source_integrity_public_url": args.source_integrity_url,
            "source_manifest_sha256": manifest_sha, "source_integrity_receipt_sha256": integrity_sha,
            "public_payload_manifest_sha256": public_payload_manifest_sha,
            "package_manifest_sha256": package_manifest_sha, "package_manifest_id": package_reference["package_manifest_id"],
            "raw_fasta_asset_sha256": raw_sha, "normalized_sequence_sha256": normalized_sha, "sequence_sha256": sequence_input_sha,
            "limits": {"max_shard_download_bytes": MAX_SHARD_BYTES, "max_post_download_query_seconds": MAX_QUERY_SECONDS},
        }
        speed_report = {
            "schema_version": "dosa-v3-u0-speed-utility-evidence-1", "status": "pass" if speed_pass else "fail", "evidence_scope": scope,
            "accession_version": args.accession_version, "scale": args.scale, "coordinate": {"start": start, "end": end, "convention": "zero_based_half_open"},
            "lookup_seconds": query_seconds, "n1000_recompute_seconds": recompute_seconds, "lookup_speedup": speedup, "minimum_lookup_speedup": MIN_SPEEDUP,
            "null_model": "euler_wilson_fixed_endpoints_v1", "null_replicates": 1000, "canonical_producer": "Sounio",
            "sounio_output_sha256": sounio_envelope["output_sha256"], "sounio_output_bytes": recompute_artifact["bytes"],
            "sounio_runner_sha256": sounio_envelope["producer"]["runner_sha256"], "sounio_attestation_sha256": attestation["sha256"],
            "sounio_build_receipt_sha256": attestation["receipt_sha256"], "sounio_attestation_evidence_scope": attestation["evidence_scope"],
            "sequence_sha256": sequence_input_sha, "parameters_sha256": sha256_file(parameters),
            "source_manifest_sha256": manifest_sha, "source_integrity_receipt_sha256": integrity_sha,
            "public_payload_manifest_sha256": public_payload_manifest_sha,
            "package_manifest_sha256": package_manifest_sha, "package_manifest_id": package_reference["package_manifest_id"],
        }
        write_new(args.query_output, query_report)
        write_new(args.speed_output, speed_report)
        return 0 if query_pass and speed_pass else EXIT_BLOCKED
    except (OSError, OperationalError) as exc:
        error = {"schema_version": "dosa-v3-u0-operational-error-1", "status": "BLOCKED", "reason_code": "INVALID_OR_MISSING_OPERATIONAL_EVIDENCE", "message": str(exc)}
        sys.stdout.write(canonical(error) + "\n")
        return EXIT_BLOCKED


if __name__ == "__main__":
    raise SystemExit(main())
