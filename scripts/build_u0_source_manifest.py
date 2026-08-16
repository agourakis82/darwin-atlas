#!/usr/bin/env python3
"""Build the immutable, externally recoverable DOSA v3 U0 source closure.

This is deliberately acquisition-only code.  It binds an already rehydrated
NCBI Datasets package to the deterministic U0 selection.  It does not compute
operator profiles or any biological statistic.

The public source manifest has no normalized-sequence field in its schema.
Normalized FASTA lengths and SHA-256 values are therefore written to the
separate integrity receipt. A portable source index maps each selected
accession.version to its public package-relative FASTA locator and hash closure.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import shutil
import sys
from collections import defaultdict
from typing import Any, Iterable


EXIT_INVALID = 11
SOURCE_INDEX_VERSION = "dosa-v3-source-index-1"
ACCESSION_RE = re.compile(r"^[A-Z][A-Z0-9_]*[0-9]\.[0-9]+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ASSEMBLY_DIR_RE = re.compile(r"^GCF_[0-9]+\.[0-9]+$")
FASTA_ALPHABET = frozenset("ACGTURYSWKMBDHVN")


class SourceManifestError(RuntimeError):
    """A fail-closed source closure error."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def reject_symlink(path: pathlib.Path, label: str) -> None:
    if path.is_symlink():
        raise SourceManifestError(f"SYMLINK_FORBIDDEN: {label}: {path}")


def regular_file(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink(path, label)
    if not path.is_file():
        raise SourceManifestError(f"MISSING_ASSET: {label}: {path}")
    return path


def resolved_directory(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink(path, label)
    if not path.is_dir():
        raise SourceManifestError(f"MISSING_DIRECTORY: {label}: {path}")
    return path.resolve(strict=True)


def inside(path: pathlib.Path, root: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink(path, label)
    try:
        resolved = path.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, ValueError) as exc:
        raise SourceManifestError(f"PATH_OUTSIDE_SNAPSHOT: {label}: {path}") from exc
    return resolved


def relative(path: pathlib.Path, root: pathlib.Path, label: str) -> str:
    return inside(path, root, label).relative_to(root).as_posix()


def immutable_file(path: pathlib.Path, root: pathlib.Path, label: str) -> dict[str, Any]:
    path = inside(regular_file(path, label), root, label)
    return {"path": relative(path, root, label), "sha256": sha256_file(path), "size_bytes": path.stat().st_size}


def parse_json(path: pathlib.Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SourceManifestError(f"INVALID_JSON: {label}: {exc}") from exc


def parse_selection(path: pathlib.Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    with regular_file(path, "selection").open(encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SourceManifestError(f"INVALID_SELECTION_JSON: line {line_no}: {exc}") from exc
            if not isinstance(row, dict):
                raise SourceManifestError(f"INVALID_SELECTION_ROW: line {line_no}")
            accession = row.get("sequence_accession_version")
            assembly = row.get("assembly_accession_version")
            if not isinstance(accession, str) or not ACCESSION_RE.fullmatch(accession):
                raise SourceManifestError(f"UNVERSIONED_ACCESSION: selection line {line_no}: {accession!r}")
            if not isinstance(assembly, str) or not ASSEMBLY_DIR_RE.fullmatch(assembly):
                raise SourceManifestError(f"INVALID_ASSEMBLY_ACCESSION: selection line {line_no}: {assembly!r}")
            declared_length = row.get("length_bp")
            if declared_length is not None and (not isinstance(declared_length, int) or isinstance(declared_length, bool) or declared_length < 1):
                raise SourceManifestError(f"INVALID_SELECTION_LENGTH: selection line {line_no}: {declared_length!r}")
            if accession in seen:
                raise SourceManifestError(f"DUPLICATE_SELECTION_ACCESSION: {accession}")
            seen.add(accession)
            result.append({"accession": accession, "assembly": assembly, "length_bp": declared_length})
    if not result:
        raise SourceManifestError("EMPTY_SELECTION")
    return sorted(result, key=lambda value: value["accession"])


def parse_sha256sums(path: pathlib.Path, snapshot: pathlib.Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    with regular_file(path, "checksum manifest").open(encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            line = line.rstrip("\n")
            if not line:
                continue
            match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_-][A-Za-z0-9._-]*(?:/[A-Za-z0-9_-][A-Za-z0-9._-]*)*)", line)
            if not match:
                raise SourceManifestError(f"INVALID_CHECKSUM_MANIFEST: line {line_no}")
            digest, path_text = match.groups()
            if path_text in entries:
                raise SourceManifestError(f"DUPLICATE_CHECKSUM_PATH: {path_text}")
            asset = snapshot / path_text
            actual = sha256_file(inside(regular_file(asset, "checksum asset"), snapshot, "checksum asset"))
            if actual != digest:
                raise SourceManifestError(f"CHECKSUM_MISMATCH: {path_text}")
            entries[path_text] = digest
    if not entries:
        raise SourceManifestError("EMPTY_CHECKSUM_MANIFEST")
    return entries


def require_checksum(path: pathlib.Path, snapshot: pathlib.Path, entries: dict[str, str], label: str) -> None:
    path_text = relative(path, snapshot, label)
    if path_text not in entries:
        raise SourceManifestError(f"CHECKSUM_BINDING_MISSING: {label}: {path_text}")


def copy_bound(source: pathlib.Path, destination: pathlib.Path, label: str) -> pathlib.Path:
    regular_file(source, label)
    if destination.exists():
        regular_file(destination, f"existing {label}")
        if sha256_file(source) != sha256_file(destination):
            raise SourceManifestError(f"BOUND_COPY_HASH_MISMATCH: {label}: {destination}")
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    return destination


def discover_assembly_dirs(package_root: pathlib.Path) -> dict[str, pathlib.Path]:
    result: dict[str, pathlib.Path] = {}
    for candidate in package_root.rglob("GCF_*"):
        if not candidate.is_dir() or not ASSEMBLY_DIR_RE.fullmatch(candidate.name):
            continue
        reject_symlink(candidate, "assembly directory")
        if candidate.name in result:
            raise SourceManifestError(f"DUPLICATE_ASSEMBLY_DIRECTORY: {candidate.name}")
        result[candidate.name] = candidate
    return result


def asset_file(assembly_dir: pathlib.Path, suffix: str, label: str) -> pathlib.Path:
    candidates = sorted(path for path in assembly_dir.iterdir() if path.is_file() and path.name.endswith(suffix))
    if len(candidates) != 1:
        raise SourceManifestError(f"MISSING_OR_AMBIGUOUS_ASSET: {label}: expected one *{suffix}, found {len(candidates)}")
    return regular_file(candidates[0], label)


def accession_tokens(text: str) -> set[str]:
    return {token for token in re.findall(r"[A-Z][A-Z0-9_]*[0-9]\.[0-9]+", text) if ACCESSION_RE.fullmatch(token)}


def fasta_header_accession(text: str) -> str | None:
    # NCBI FASTA uses the first whitespace-delimited token as accession.version.
    # Descriptions often contain strain or plasmid labels that look like accessions.
    parts = text.split()
    if not parts or ACCESSION_RE.fullmatch(parts[0]) is None:
        return None
    return parts[0]


def parse_fasta(path: pathlib.Path) -> dict[str, tuple[int, str, str]]:
    records: dict[str, tuple[int, str, str]] = {}
    current: str | None = None
    digest: hashlib._Hash | None = None
    canonical_digest: hashlib._Hash | None = None
    length = 0
    with path.open(encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, start=1):
            line = raw.rstrip("\r\n")
            if line.startswith(">"):
                if current is not None and digest is not None and canonical_digest is not None:
                    canonical_digest.update(b"\n")
                    records[current] = (length, digest.hexdigest(), canonical_digest.hexdigest())
                current = fasta_header_accession(line[1:])
                if current is None:
                    raise SourceManifestError(f"INVALID_FASTA_HEADER: {path}:{line_no}")
                if current in records:
                    raise SourceManifestError(f"DUPLICATE_FASTA_ACCESSION: {current}")
                digest = hashlib.sha256()
                canonical_digest = hashlib.sha256(f">{current}\n".encode("ascii"))
                length = 0
                continue
            if current is None:
                if line.strip():
                    raise SourceManifestError(f"FASTA_SEQUENCE_BEFORE_HEADER: {path}:{line_no}")
                continue
            sequence = "".join(line.split()).upper()
            if not sequence or any(base not in FASTA_ALPHABET for base in sequence):
                raise SourceManifestError(f"INVALID_FASTA_SEQUENCE: {path}:{line_no}")
            assert digest is not None and canonical_digest is not None
            digest.update(sequence.encode("ascii"))
            canonical_digest.update(sequence.encode("ascii"))
            length += len(sequence)
    if current is not None and digest is not None and canonical_digest is not None:
        canonical_digest.update(b"\n")
        records[current] = (length, digest.hexdigest(), canonical_digest.hexdigest())
    if not records:
        raise SourceManifestError(f"EMPTY_FASTA: {path}")
    return records


def gbff_accessions(path: pathlib.Path) -> set[str]:
    values: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("VERSION"):
                values.update(accession_tokens(line))
    return values


def report_accessions(path: pathlib.Path, expected_assembly: str) -> set[str]:
    values: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SourceManifestError(f"INVALID_SEQUENCE_REPORT_JSON: {path}:{line_no}") from exc
            snake_accession = row.get("refseq_accession")
            camel_accession = row.get("refseqAccession")
            snake_assembly = row.get("assembly_accession")
            camel_assembly = row.get("assemblyAccession")
            if snake_accession is not None and camel_accession is not None and snake_accession != camel_accession:
                raise SourceManifestError(f"SEQUENCE_REPORT_ACCESSION_CONFLICT: {path}:{line_no}")
            if snake_assembly is not None and camel_assembly is not None and snake_assembly != camel_assembly:
                raise SourceManifestError(f"SEQUENCE_REPORT_ASSEMBLY_CONFLICT: {path}:{line_no}")
            accession = snake_accession if snake_accession is not None else camel_accession
            assembly = snake_assembly if snake_assembly is not None else camel_assembly
            if not isinstance(accession, str) or not ACCESSION_RE.fullmatch(accession):
                raise SourceManifestError(f"INVALID_SEQUENCE_REPORT_ACCESSION: {path}:{line_no}")
            if assembly is not None and assembly != expected_assembly:
                raise SourceManifestError(f"SEQUENCE_REPORT_ASSEMBLY_MISMATCH: {path}:{line_no}")
            if accession in values:
                raise SourceManifestError(f"DUPLICATE_SEQUENCE_REPORT_ACCESSION: {accession}")
            values.add(accession)
    return values


def asset_entry(kind: str, assembly: str, source_ids: list[str], path: pathlib.Path, snapshot: pathlib.Path) -> dict[str, Any]:
    return {
        "asset_id": f"{kind}-{assembly}",
        "asset_kind": kind,
        "assembly_accession_version": assembly,
        "sequence_accession_version": None,
        "selected_record_ids": source_ids,
        "source_url": f"https://www.ncbi.nlm.nih.gov/datasets/genome/{assembly}/",
        "package_path": relative(path, snapshot, f"{kind} asset"),
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
    }


def validate_utc(value: str) -> str:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SourceManifestError(f"INVALID_RETRIEVED_UTC: {value}") from exc
    if parsed.tzinfo is None:
        raise SourceManifestError("INVALID_RETRIEVED_UTC: timezone required")
    return parsed.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def build(args: argparse.Namespace) -> dict[str, Any]:
    snapshot = resolved_directory(args.snapshot_root, "snapshot root")
    selection_path = inside(args.selection, snapshot, "selection")
    package_root = inside(resolved_directory(args.package_root, "package root"), snapshot, "package root")
    archive = inside(args.dehydrated_archive, snapshot, "dehydrated archive")
    catalog = inside(args.catalog, snapshot, "dataset catalog")
    checksums = inside(args.checksums, snapshot, "checksum manifest")
    manifest_out = args.manifest_output
    integrity_out = args.integrity_output
    source_index_out = args.source_index_output
    outputs = (
        (manifest_out, "manifest output"),
        (integrity_out, "integrity output"),
        (source_index_out, "source index output"),
    )
    resolved_outputs: set[pathlib.Path] = set()
    for output, label in outputs:
        if output.exists():
            raise SourceManifestError(f"REFUSE_OVERWRITE: {label}: {output}")
        try:
            resolved_output = output.resolve(strict=False)
            resolved_output.relative_to(snapshot)
        except (OSError, ValueError) as exc:
            raise SourceManifestError(f"PATH_OUTSIDE_SNAPSHOT: {label}: {output}") from exc
        if resolved_output in resolved_outputs:
            raise SourceManifestError(f"DUPLICATE_OUTPUT_PATH: {label}: {output}")
        resolved_outputs.add(resolved_output)

    selected = parse_selection(selection_path)
    checks = parse_sha256sums(checksums, snapshot)
    # SHA256SUMS is self-authenticating only through the manifest hash below.
    # The dehydrated archive is deliberately outside the rehydrated package in
    # NCBI's documented layout, so it too is bound directly by this manifest
    # rather than requiring an impossible/self-referential checksum entry.
    catalog_object = parse_json(catalog, "dataset catalog")
    if not isinstance(catalog_object, (dict, list)):
        raise SourceManifestError("INVALID_DATASET_CATALOG")
    catalog_text = canonical_json(catalog_object)

    query_source = regular_file(args.query_source, "query source")
    tool_source = regular_file(args.tool_lock_source, "tool lock source")
    query_object = parse_json(query_source, "query source")
    if not isinstance(query_object, dict) or not query_object:
        raise SourceManifestError("INVALID_QUERY_OBJECT")
    lock = parse_json(tool_source, "tool lock source")
    if not isinstance(lock, dict):
        raise SourceManifestError("INVALID_TOOL_LOCK")
    copied_query = copy_bound(query_source, snapshot / "provenance" / "refseq_bacteria_complete_query.json", "query")
    copied_lock = copy_bound(tool_source, snapshot / "provenance" / "ncbi-datasets.lock.json", "tool lock")
    tool_bindings: dict[str, Any] = {}
    for key, version_key in (("datasets", "version"), ("dataformat", "version_reported")):
        value = lock.get(key)
        if not isinstance(value, dict):
            raise SourceManifestError(f"INVALID_TOOL_LOCK_ENTRY: {key}")
        url = value.get("macos_universal_url")
        sha = value.get("sha256")
        size = value.get("size_bytes")
        version = value.get(version_key)
        if not isinstance(url, str) or not re.fullmatch(r"https://(?:[A-Za-z0-9.-]+\.)?ncbi\.nlm\.nih\.gov/.+", url):
            raise SourceManifestError(f"INVALID_NCBI_TOOL_URL: {key}")
        if not isinstance(sha, str) or not SHA256_RE.fullmatch(sha) or not isinstance(size, int) or size < 1 or not isinstance(version, str) or not version:
            raise SourceManifestError(f"INVALID_TOOL_LOCK_ENTRY: {key}")
        tool_bindings[key] = {"version": version, "source_url": url, "sha256": sha, "size_bytes": size}

    by_assembly: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in selected:
        by_assembly[row["assembly"]].append(row)
    assembly_dirs = discover_assembly_dirs(package_root)
    all_assets: list[dict[str, Any]] = []
    normalized: list[dict[str, Any]] = []
    fasta_locator_by_accession: dict[str, str] = {}
    selected_records: list[dict[str, Any]] = []
    for row in selected:
        accession = row["accession"]
        selected_records.append({
            "source_record_id": f"src-{accession}",
            "replicon_id": accession,
            "assembly_accession_version": row["assembly"],
            "sequence_accession_version": accession,
            "required_asset_kinds": ["fasta", "gbff", "sequence_report"],
        })
    for assembly in sorted(by_assembly):
        directory = assembly_dirs.get(assembly)
        if directory is None:
            raise SourceManifestError(f"MISSING_ASSEMBLY_DIRECTORY: {assembly}")
        if assembly not in catalog_text:
            raise SourceManifestError(f"CATALOG_ASSEMBLY_MISSING: {assembly}")
        fasta = asset_file(directory, ".fna", f"fasta {assembly}")
        gbff = asset_file(directory, ".gbff", f"gbff {assembly}")
        report = asset_file(directory, "sequence_report.jsonl", f"sequence report {assembly}")
        for path, label in ((fasta, "fasta"), (gbff, "gbff"), (report, "sequence report")):
            require_checksum(path, snapshot, checks, f"{label} {assembly}")
        fasta_records = parse_fasta(fasta)
        gbff_records = gbff_accessions(gbff)
        report_records = report_accessions(report, assembly)
        records = sorted(by_assembly[assembly], key=lambda value: value["accession"])
        source_ids = [f"src-{row['accession']}" for row in records]
        for row in records:
            accession = row["accession"]
            if accession not in fasta_records:
                raise SourceManifestError(f"FASTA_ACCESSION_MISSING: {assembly}:{accession}")
            if accession not in gbff_records:
                raise SourceManifestError(f"GBFF_ACCESSION_MISSING: {assembly}:{accession}")
            if accession not in report_records:
                raise SourceManifestError(f"SEQUENCE_REPORT_ACCESSION_MISSING: {assembly}:{accession}")
            length, sequence_sha, canonical_sequence_input_sha = fasta_records[accession]
            if row["length_bp"] is not None and row["length_bp"] != length:
                raise SourceManifestError(f"FASTA_LENGTH_MISMATCH: {assembly}:{accession}: expected {row['length_bp']}, observed {length}")
            normalized.append({
                "source_record_id": f"src-{accession}",
                "sequence_accession_version": accession,
                "assembly_accession_version": assembly,
                "normalized_fasta_length_bp": length,
                "normalized_fasta_sha256": sequence_sha,
                "canonical_sequence_input_sha256": canonical_sequence_input_sha,
                "fasta_asset_sha256": sha256_file(fasta),
            })
            if accession in fasta_locator_by_accession:
                raise SourceManifestError(f"DUPLICATE_SOURCE_INDEX_ACCESSION: {accession}")
            fasta_locator_by_accession[accession] = relative(fasta, snapshot, f"fasta locator {assembly}")
        all_assets.extend([
            asset_entry("fasta", assembly, source_ids, fasta, snapshot),
            asset_entry("gbff", assembly, source_ids, gbff, snapshot),
            asset_entry("sequence_report", assembly, source_ids, report, snapshot),
        ])

    retrieved = validate_utc(args.retrieved_utc)
    package_id = args.package_id or f"u0-{snapshot.name}"
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", package_id):
        raise SourceManifestError("INVALID_PACKAGE_ID")
    manifest_id = args.manifest_id or f"u0-source-{snapshot.name}"
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", manifest_id):
        raise SourceManifestError("INVALID_MANIFEST_ID")
    manifest = {
        "schema_version": "3.0.0",
        "manifest_id": manifest_id,
        "retrieved_utc": retrieved,
        "source_provider": "NCBI_Datasets",
        "query": {**immutable_file(copied_query, snapshot, "copied query"), "object": query_object},
        "acquisition_tools": tool_bindings,
        "package": {
            "package_id": package_id,
            "source_url": "https://api.ncbi.nlm.nih.gov/datasets/v2/genome/accession/",
            "package_root": relative(package_root, snapshot, "package root"),
            "dehydrated_archive": immutable_file(archive, snapshot, "dehydrated archive"),
            "catalog": immutable_file(catalog, snapshot, "dataset catalog"),
            "checksum_manifest": immutable_file(checksums, snapshot, "checksum manifest"),
            "catalog_verified": True,
            "package_checksums_verified": True,
            "selected_assets_complete": True,
        },
        "selected_records": selected_records,
        "package_assets": sorted(all_assets, key=lambda item: (item["assembly_accession_version"], item["asset_kind"])),
    }
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(canonical_json(manifest) + "\n", encoding="utf-8", newline="\n")
    integrity = {
        "schema_version": "dosa-u0-source-integrity-receipt-1",
        "source_manifest_path": relative(manifest_out, snapshot, "manifest output"),
        "source_manifest_sha256": sha256_file(manifest_out),
        "normalized_fasta_hashes_are_not_public_manifest_fields": True,
        "scientific_metrics_computed": False,
        "records": sorted(normalized, key=lambda item: item["sequence_accession_version"]),
    }
    integrity_out.parent.mkdir(parents=True, exist_ok=True)
    integrity_out.write_text(canonical_json(integrity) + "\n", encoding="utf-8", newline="\n")
    source_manifest_sha = sha256_file(manifest_out)
    source_integrity_sha = sha256_file(integrity_out)
    source_index_records: dict[str, dict[str, str]] = {}
    for record in integrity["records"]:
        accession = record["sequence_accession_version"]
        locator = fasta_locator_by_accession.get(accession)
        if locator is None:
            raise SourceManifestError(f"SOURCE_INDEX_FASTA_LOCATOR_MISSING: {accession}")
        if accession in source_index_records:
            raise SourceManifestError(f"DUPLICATE_SOURCE_INDEX_ACCESSION: {accession}")
        source_index_records[accession] = {
            "locator": locator,
            "canonical_sequence_input_sha256": record["canonical_sequence_input_sha256"],
            "normalized_sequence_sha256": record["normalized_fasta_sha256"],
            "source_manifest_sha256": source_manifest_sha,
            "source_integrity_sha256": source_integrity_sha,
        }
    if len(source_index_records) != len(selected_records):
        raise SourceManifestError("SOURCE_INDEX_RECORD_COVERAGE_MISMATCH")
    source_index = {
        "source_index_version": SOURCE_INDEX_VERSION,
        "records": dict(sorted(source_index_records.items())),
    }
    source_index_out.parent.mkdir(parents=True, exist_ok=True)
    source_index_out.write_text(canonical_json(source_index) + "\n", encoding="utf-8", newline="\n")
    return {
        "status": "built",
        "schema_version": "3.0.0",
        "records": len(selected_records),
        "manifest": relative(manifest_out, snapshot, "manifest output"),
        "manifest_sha256": source_manifest_sha,
        "integrity_receipt": relative(integrity_out, snapshot, "integrity output"),
        "integrity_receipt_sha256": source_integrity_sha,
        "source_index": relative(source_index_out, snapshot, "source index output"),
        "source_index_sha256": sha256_file(source_index_out),
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--snapshot-root", required=True, type=pathlib.Path)
    result.add_argument("--selection", required=True, type=pathlib.Path)
    result.add_argument("--query-source", required=True, type=pathlib.Path)
    result.add_argument("--tool-lock-source", required=True, type=pathlib.Path)
    result.add_argument("--package-root", required=True, type=pathlib.Path)
    result.add_argument("--dehydrated-archive", required=True, type=pathlib.Path)
    result.add_argument("--catalog", required=True, type=pathlib.Path)
    result.add_argument("--checksums", required=True, type=pathlib.Path)
    result.add_argument("--manifest-output", required=True, type=pathlib.Path)
    result.add_argument("--integrity-output", required=True, type=pathlib.Path)
    result.add_argument("--source-index-output", required=True, type=pathlib.Path)
    result.add_argument("--retrieved-utc", required=True)
    result.add_argument("--package-id")
    result.add_argument("--manifest-id")
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        print(canonical_json(build(args)))
        return 0
    except (OSError, SourceManifestError) as exc:
        print(canonical_json({"status": "error", "code": "U0_SOURCE_MANIFEST_INVALID", "message": str(exc)}), file=sys.stderr)
        return EXIT_INVALID


if __name__ == "__main__":
    raise SystemExit(main())
