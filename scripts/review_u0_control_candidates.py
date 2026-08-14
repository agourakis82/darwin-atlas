#!/usr/bin/env python3
"""Review a bounded, already-downloaded U0 control mini-package.

This offline-only step never calls NCBI.  It binds six declared control claims
to the exact reports used for discovery and to the tiny rehydrated package used
for review.  The resulting receipt is provenance for candidate qualification,
not a source freeze or a scientific-result receipt.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
from typing import Any

import bind_u0_control_ledger as binder
import select_u0_pilot as selector
import validate_u0_control_ledger as ledger_validator


EXIT_INVALID = 11
RECEIPT_VERSION = "dosa-u0-control-review-receipt-1"
HEX64 = re.compile(r"[0-9a-f]{64}")


class ReviewError(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def reject_symlink_components(root: pathlib.Path, path: pathlib.Path, label: str) -> pathlib.Path:
    # Inspect the lexical path before resolving it.  Resolving first would hide
    # an intermediate symlink that happens to point back inside review_root.
    lexical = path if path.is_absolute() else pathlib.Path.cwd() / path
    try:
        relative = lexical.relative_to(root)
    except ValueError as exc:
        raise ReviewError(f"PATH_OUTSIDE_REVIEW_ROOT: {label}: {path}") from exc
    cursor = root
    for part in relative.parts:
        if part in {"", ".", ".."}:
            raise ReviewError(f"INVALID_RELATIVE_PATH: {label}: {path}")
        cursor = cursor / part
        if cursor.is_symlink():
            raise ReviewError(f"SYMLINK_FORBIDDEN: {label}: {path}")
    try:
        resolved = lexical.resolve(strict=True)
        resolved.relative_to(root.resolve(strict=True))
    except (OSError, ValueError) as exc:
        raise ReviewError(f"PATH_OUTSIDE_REVIEW_ROOT: {label}: {path}") from exc
    return relative


def review_root(path: pathlib.Path) -> pathlib.Path:
    if ".." in path.parts:
        raise ReviewError(f"INVALID_REVIEW_ROOT: {path}")
    lexical = path if path.is_absolute() else pathlib.Path.cwd() / path
    cursor = pathlib.Path(lexical.anchor)
    for part in lexical.parts[1:]:
        cursor = cursor / part
        if cursor.is_symlink():
            raise ReviewError(f"SYMLINK_FORBIDDEN: review root: {path}")
    if not lexical.is_dir():
        raise ReviewError(f"INVALID_REVIEW_ROOT: {path}")
    return lexical


def require_file(root: pathlib.Path, path: pathlib.Path, label: str) -> pathlib.Path:
    if path.is_symlink() or not path.is_file():
        raise ReviewError(f"MISSING_OR_SYMLINK_FILE: {label}: {path}")
    reject_symlink_components(root, path, label)
    return path if path.is_absolute() else pathlib.Path.cwd() / path


def require_directory(root: pathlib.Path, path: pathlib.Path, label: str) -> pathlib.Path:
    if path.is_symlink() or not path.is_dir():
        raise ReviewError(f"MISSING_OR_SYMLINK_DIRECTORY: {label}: {path}")
    reject_symlink_components(root, path, label)
    return path if path.is_absolute() else pathlib.Path.cwd() / path


def relative_path(root: pathlib.Path, path: pathlib.Path, label: str) -> str:
    relative = reject_symlink_components(root, path, label)
    value = relative.as_posix()
    if not value or value == "." or value.startswith("/") or ".." in relative.parts:
        raise ReviewError(f"INVALID_RELATIVE_PATH: {label}: {value!r}")
    return value


def identity(root: pathlib.Path, path: pathlib.Path, label: str) -> dict[str, Any]:
    path = require_file(root, path, label)
    return {"path": relative_path(root, path, label), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def strict_json(path: pathlib.Path, label: str) -> dict[str, Any]:
    def pairs(values: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in values:
            if key in result:
                raise ValueError(f"duplicate key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs)
    except (OSError, UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise ReviewError(f"INVALID_JSON: {label}: {path}") from exc
    if not isinstance(value, dict):
        raise ReviewError(f"INVALID_JSON_OBJECT: {label}: {path}")
    return value


def path_from_receipt(root: pathlib.Path, value: Any, label: str) -> pathlib.Path:
    if not isinstance(value, str):
        raise ReviewError(f"INVALID_RECEIPT_PATH: {label}")
    pure = pathlib.PurePosixPath(value)
    if not value or pure.is_absolute() or pure.as_posix() != value or any(part in {"", ".", ".."} for part in pure.parts):
        raise ReviewError(f"INVALID_RECEIPT_PATH: {label}")
    return root.joinpath(*pure.parts)


def verify_identity(root: pathlib.Path, value: Any, label: str) -> pathlib.Path:
    if not isinstance(value, dict) or set(value) != {"path", "bytes", "sha256"}:
        raise ReviewError(f"INVALID_RECEIPT_IDENTITY: {label}")
    if type(value["bytes"]) is not int or value["bytes"] < 1 or not isinstance(value["sha256"], str) or not HEX64.fullmatch(value["sha256"]):
        raise ReviewError(f"INVALID_RECEIPT_IDENTITY: {label}")
    path = path_from_receipt(root, value["path"], label)
    if identity(root, path, label) != value:
        raise ReviewError(f"IDENTITY_MISMATCH: {label}")
    return path


def validate_discovery_inputs(assemblies: pathlib.Path, sequences: pathlib.Path, candidates: pathlib.Path) -> None:
    assembly_rows = selector.load_assemblies(assemblies)
    replicons = selector.load_replicons(sequences, assembly_rows)
    selector.load_control_candidates(candidates, replicons)


def cleanup_partial_outputs(paths: tuple[pathlib.Path, ...]) -> None:
    """Remove only this invocation's known outputs after a failed review."""
    failures: list[str] = []
    for path in paths:
        try:
            if path.exists() and not path.is_symlink():
                path.unlink()
        except OSError:
            failures.append(str(path))
    if failures:
        raise ReviewError("CONTROL_REVIEW_CLEANUP_FAILED: " + ",".join(failures))


def create(args: argparse.Namespace) -> dict[str, Any]:
    root = review_root(args.review_root)
    assemblies = require_file(root, args.assemblies, "assembly report")
    sequences = require_file(root, args.sequences, "sequence report")
    candidates = require_file(root, args.control_candidates, "control candidates")
    package = require_directory(root, args.package_root, "mini package root")
    outputs = {
        "control ledger": args.output_ledger,
        "binding receipt": args.output_binding_receipt,
        "semantic receipt": args.output_semantic_receipt,
        "review receipt": args.output_review_receipt,
    }
    resolved_outputs: set[pathlib.Path] = set()
    for label, output in outputs.items():
        if output.exists() or output.is_symlink():
            raise ReviewError(f"REFUSE_OVERWRITE: {label}: {output}")
        parent = require_directory(root, output.parent, f"{label} parent")
        resolved = parent / output.name
        if resolved in resolved_outputs:
            raise ReviewError(f"OUTPUT_COLLISION: {label}: {output}")
        resolved_outputs.add(resolved)
    validate_discovery_inputs(assemblies, sequences, candidates)
    partial_outputs = (args.output_ledger, args.output_binding_receipt, args.output_semantic_receipt, args.output_review_receipt)
    try:
        binding = binder.bind(
            argparse.Namespace(
                control_candidates=candidates,
                package_root=package,
                output_ledger=args.output_ledger,
                output_receipt=args.output_binding_receipt,
            )
        )
        semantic = ledger_validator.validate(
            argparse.Namespace(controls=args.output_ledger, package_root=package, output=args.output_semantic_receipt)
        )
    except (OSError, binder.BindingError, ledger_validator.LedgerError) as exc:
        cleanup_partial_outputs(partial_outputs)
        raise ReviewError(f"CONTROL_REVIEW_INVALID: {exc}") from exc
    receipt = {
        "schema_version": RECEIPT_VERSION,
        "status": "validated",
        "evidence_scope": "bounded_control_candidate_review_non_scientific",
        "assembly_report": identity(root, assemblies, "assembly report"),
        "sequence_report": identity(root, sequences, "sequence report"),
        "control_candidates": identity(root, candidates, "control candidates"),
        "mini_package_root": relative_path(root, package, "mini package root"),
        "control_ledger": identity(root, args.output_ledger, "control ledger"),
        "binding_receipt": identity(root, args.output_binding_receipt, "binding receipt"),
        "semantic_receipt": identity(root, args.output_semantic_receipt, "semantic receipt"),
        "control_claims": 6,
        "control_claims_semantically_validated": True,
        "scientific_metrics_computed": False,
    }
    args.output_review_receipt.write_text(canonical_json(receipt) + "\n", encoding="utf-8", newline="\n")
    return {
        "status": "validated",
        "control_claims": 6,
        "control_claims_semantically_validated": True,
        "review_receipt": relative_path(root, args.output_review_receipt, "review receipt"),
        "review_receipt_sha256": sha256_file(args.output_review_receipt),
        "binding_receipt_sha256": binding["binding_receipt_sha256"],
        "semantic_receipt_sha256": semantic["receipt_sha256"],
    }


def verify(args: argparse.Namespace) -> dict[str, Any]:
    root = review_root(args.review_root)
    receipt_path = require_file(root, args.receipt, "review receipt")
    receipt = strict_json(receipt_path, "review receipt")
    expected = {
        "schema_version", "status", "evidence_scope", "assembly_report", "sequence_report", "control_candidates",
        "mini_package_root", "control_ledger", "binding_receipt", "semantic_receipt", "control_claims",
        "control_claims_semantically_validated", "scientific_metrics_computed",
    }
    if set(receipt) != expected or receipt.get("schema_version") != RECEIPT_VERSION or receipt.get("status") != "validated":
        raise ReviewError("INVALID_REVIEW_RECEIPT")
    if receipt.get("evidence_scope") != "bounded_control_candidate_review_non_scientific":
        raise ReviewError("INVALID_EVIDENCE_SCOPE")
    if (
        receipt.get("control_claims") != 6
        or receipt.get("control_claims_semantically_validated") is not True
        or receipt.get("scientific_metrics_computed") is not False
    ):
        raise ReviewError("INVALID_REVIEW_SCOPE")
    assemblies = verify_identity(root, receipt["assembly_report"], "assembly report")
    sequences = verify_identity(root, receipt["sequence_report"], "sequence report")
    candidates = verify_identity(root, receipt["control_candidates"], "control candidates")
    package = require_directory(root, path_from_receipt(root, receipt["mini_package_root"], "mini package root"), "mini package root")
    ledger = verify_identity(root, receipt["control_ledger"], "control ledger")
    binding_path = verify_identity(root, receipt["binding_receipt"], "binding receipt")
    semantic_path = verify_identity(root, receipt["semantic_receipt"], "semantic receipt")
    validate_discovery_inputs(assemblies, sequences, candidates)
    binding = strict_json(binding_path, "binding receipt")
    semantic = strict_json(semantic_path, "semantic receipt")
    ledger_sha256 = sha256_file(ledger)
    candidate_sha256 = sha256_file(candidates)
    if (
        binding.get("schema_version") != "dosa-u0-control-binding-receipt-1"
        or binding.get("status") != "bound_unvalidated"
        or binding.get("control_candidates_sha256") != candidate_sha256
        or binding.get("control_ledger_sha256") != ledger_sha256
        or binding.get("semantic_validation_complete") is not False
    ):
        raise ReviewError("BINDING_RECEIPT_MISMATCH")
    if (
        semantic.get("schema_version") != "dosa-u0-control-ledger-receipt-1"
        or semantic.get("status") != "validated"
        or semantic.get("control_ledger_sha256") != ledger_sha256
    ):
        raise ReviewError("SEMANTIC_RECEIPT_MISMATCH")
    try:
        # The shared validator accepts a resolved package root when called
        # directly (its CLI wrapper performs this normalization itself).
        proven = ledger_validator.load_and_validate(ledger, package.resolve(strict=True))
    except (OSError, ledger_validator.LedgerError) as exc:
        raise ReviewError(f"CONTROL_REVIEW_TAMPERED: {exc}") from exc
    if len(proven) != 6 or semantic.get("controls") != proven:
        raise ReviewError("SEMANTIC_PROOF_MISMATCH")
    return {
        "status": "verified",
        "control_claims": 6,
        "control_claims_semantically_validated": True,
        "review_receipt_sha256": sha256_file(receipt_path),
        "scientific_metrics_computed": False,
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    create_parser = commands.add_parser("create", help="bind and validate an offline control mini-package")
    create_parser.add_argument("--review-root", required=True, type=pathlib.Path)
    create_parser.add_argument("--assemblies", required=True, type=pathlib.Path)
    create_parser.add_argument("--sequences", required=True, type=pathlib.Path)
    create_parser.add_argument("--control-candidates", required=True, type=pathlib.Path)
    create_parser.add_argument("--package-root", required=True, type=pathlib.Path)
    create_parser.add_argument("--output-ledger", required=True, type=pathlib.Path)
    create_parser.add_argument("--output-binding-receipt", required=True, type=pathlib.Path)
    create_parser.add_argument("--output-semantic-receipt", required=True, type=pathlib.Path)
    create_parser.add_argument("--output-review-receipt", required=True, type=pathlib.Path)
    verify_parser = commands.add_parser("verify", help="recheck an existing offline review receipt and assets")
    verify_parser.add_argument("--review-root", required=True, type=pathlib.Path)
    verify_parser.add_argument("--receipt", required=True, type=pathlib.Path)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        outcome = create(args) if args.command == "create" else verify(args)
        print(canonical_json(outcome))
        return 0
    except (OSError, ReviewError, selector.SelectionError) as exc:
        print(canonical_json({"status": "error", "code": "U0_CONTROL_REVIEW_INVALID", "message": str(exc)}), file=sys.stderr)
        return EXIT_INVALID


if __name__ == "__main__":
    raise SystemExit(main())
