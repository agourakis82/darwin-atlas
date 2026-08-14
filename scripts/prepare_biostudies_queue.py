#!/usr/bin/env python3
"""Validate and stage a BioStudies upload queue without uploading anything.

The tool intentionally has no network client, credential option, token option,
or submission operation.  It turns a hash-closed list of already validated
files into a small, canonical queue receipt.  Real deposit is a separately
authorized operation after BioStudies accession/coordination and Aspera setup.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from typing import Any


GIB = 1024 ** 3
MAX_PENDING_BYTES = 200 * GIB
HEX64 = __import__("re").compile(r"[0-9a-f]{64}")
INPUT_VERSION = "dosa-v3-biostudies-upload-candidate-1"
OUTPUT_VERSION = "dosa-v3-biostudies-validated-queue-1"
VALIDATION_VERSION = "dosa-v3-biostudies-shard-validation-receipt-1"


class QueueError(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_name(value: Any) -> pathlib.PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value:
        raise QueueError("queue file path must be a non-empty normalized POSIX relative path")
    path = pathlib.PurePosixPath(value)
    if path.is_absolute() or path.as_posix() != value or any(part in ("", ".", "..") for part in path.parts):
        raise QueueError("queue file path must be a non-empty normalized POSIX relative path")
    return path


def load_candidate(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise QueueError("candidate manifest is not a readable JSON object") from exc
    if not isinstance(value, dict) or value.get("schema_version") != INPUT_VERSION:
        raise QueueError("unsupported BioStudies queue candidate manifest")
    if value.get("evidence_scope") != "u0_pilot":
        raise QueueError("fixture or non-pilot evidence cannot enter a BioStudies queue")
    validation = value.get("validation")
    if not isinstance(validation, dict) or set(validation) != {
        "status", "receipt_path", "receipt_bytes", "receipt_sha256"
    } or validation.get("status") != "PASS":
        raise QueueError("candidate requires a hash-bound validated PASS receipt; no unvalidated shard may be queued")
    files = value.get("files")
    if not isinstance(files, list) or not files:
        raise QueueError("candidate manifest must contain a non-empty files list")
    return value


def validate_files(root: pathlib.Path, files: list[Any]) -> tuple[list[dict[str, Any]], int]:
    resolved_root = root.resolve()
    output: list[dict[str, Any]] = []
    seen: set[str] = set()
    total = 0
    for item in files:
        if not isinstance(item, dict):
            raise QueueError("candidate file entry must be an object")
        relative = safe_name(item.get("path"))
        name = relative.as_posix()
        if name in seen:
            raise QueueError("candidate contains duplicate file path")
        seen.add(name)
        expected_bytes = item.get("bytes")
        expected_sha = item.get("sha256")
        if type(expected_bytes) is not int or expected_bytes < 1 or not isinstance(expected_sha, str) or not HEX64.fullmatch(expected_sha):
            raise QueueError("candidate file entry requires positive bytes and lowercase SHA-256")
        path = root / relative
        try:
            path.resolve(strict=True).relative_to(resolved_root)
        except (OSError, ValueError) as exc:
            raise QueueError("candidate path escapes root or is unavailable") from exc
        if not path.is_file() or path.is_symlink():
            raise QueueError("candidate path is not a regular file")
        actual_bytes = path.stat().st_size
        actual_sha = sha256_file(path)
        if actual_bytes != expected_bytes or actual_sha != expected_sha:
            raise QueueError("candidate file bytes/SHA-256 mismatch")
        total += actual_bytes
        if total > MAX_PENDING_BYTES:
            raise QueueError("validated queue exceeds the 200 GiB pending-local limit")
        output.append({"path": name, "bytes": actual_bytes, "sha256": actual_sha})
    return output, total


def validate_receipt(root: pathlib.Path, binding: dict[str, Any], payloads: list[dict[str, Any]]) -> dict[str, Any]:
    relative = safe_name(binding.get("receipt_path"))
    expected_bytes = binding.get("receipt_bytes")
    expected_sha = binding.get("receipt_sha256")
    if type(expected_bytes) is not int or expected_bytes < 1 or not isinstance(expected_sha, str) or not HEX64.fullmatch(expected_sha):
        raise QueueError("validation receipt binding requires positive bytes and lowercase SHA-256")
    resolved_root = root.resolve()
    path = root / relative
    try:
        path.resolve(strict=True).relative_to(resolved_root)
    except (OSError, ValueError) as exc:
        raise QueueError("validation receipt escapes root or is unavailable") from exc
    if not path.is_file() or path.is_symlink() or path.stat().st_size != expected_bytes or sha256_file(path) != expected_sha:
        raise QueueError("validation receipt bytes/SHA-256 mismatch")
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise QueueError("validation receipt is not a UTF-8 JSON object") from exc
    if not isinstance(receipt, dict) or receipt.get("schema_version") != VALIDATION_VERSION:
        raise QueueError("unsupported shard validation receipt")
    if receipt.get("status") != "PASS" or receipt.get("evidence_scope") != "u0_pilot":
        raise QueueError("validation receipt is not a real-pilot PASS")
    if receipt.get("producer") != {"language": "Sounio", "canonical": True}:
        raise QueueError("validation receipt does not bind the canonical Sounio producer")
    if receipt.get("validator") != {"language": "Julia", "disagreements": 0, "absolute_tolerance": 0}:
        raise QueueError("validation receipt does not bind independent zero-disagreement Julia validation")
    declared = receipt.get("validated_payload_sha256")
    observed = sorted(item["sha256"] for item in payloads)
    if not isinstance(declared, list) or declared != observed or len(set(declared)) != len(declared):
        raise QueueError("validation receipt does not close exactly the queued payload SHA-256 set")
    return {"path": relative.as_posix(), "bytes": expected_bytes, "sha256": expected_sha}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, type=pathlib.Path)
    parser.add_argument("--root", required=True, type=pathlib.Path, help="root containing candidate relative paths")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    try:
        if args.output.exists():
            raise QueueError(f"refusing to overwrite queue receipt: {args.output}")
        if not args.root.is_dir() or args.root.is_symlink():
            raise QueueError("--root is not a regular directory")
        candidate = load_candidate(args.candidate)
        files, total = validate_files(args.root, candidate["files"])
        validation_receipt = validate_receipt(args.root, candidate["validation"], files)
        total += int(validation_receipt["bytes"])
        if total > MAX_PENDING_BYTES:
            raise QueueError("validated queue plus its validation receipt exceeds the 200 GiB pending-local limit")
        receipt = {
            "schema_version": OUTPUT_VERSION,
            "status": "READY_FOR_COORDINATION",
            "evidence_scope": "u0_pilot",
            "upload_performed": False,
            "external_accession": None,
            "candidate_manifest_sha256": sha256_file(args.candidate),
            "validation_receipt": validation_receipt,
            "files": files,
            "pending_local_bytes": total,
            "max_pending_local_bytes": MAX_PENDING_BYTES,
            "blocking_requirements": [
                "BioStudies_accession_or_submission_coordination",
                "approved_Aspera_or_official_transfer_configuration",
                "explicit_authority_to_upload",
            ],
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(canonical(receipt) + "\n", encoding="utf-8")
        sys.stdout.write(canonical(receipt) + "\n")
        return 0
    except QueueError as exc:
        sys.stdout.write(canonical({"schema_version": OUTPUT_VERSION, "status": "BLOCKED", "reason_code": "BIOSTUDIES_QUEUE_INVALID", "message": str(exc), "upload_performed": False}) + "\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
