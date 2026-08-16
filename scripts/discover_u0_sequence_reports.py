#!/usr/bin/env python3
"""Recover RefSeq sequence reports in deterministic, resumable batches.

The NCBI all-accession stream can take hours or fail mid-response. This helper
freezes the assembly accession universe from an existing assembly report, then
uses the pinned `datasets summary genome accession --report sequence` endpoint
in bounded batches. It computes no DOSA metric and emits no pilot PASS.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
from typing import Any


ASSEMBLY_RE = re.compile(r"GCF_[0-9]+\.[0-9]+")
SEQUENCE_RE = re.compile(r"[A-Z][A-Z0-9_]*\.[0-9]+")


class DiscoveryError(RuntimeError):
    pass


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def strict_object(raw: str, label: str) -> dict[str, Any]:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ValueError(f"duplicate JSON key: {key}")
            value[key] = item
        return value

    try:
        value = json.loads(raw, object_pairs_hook=unique)
    except (ValueError, json.JSONDecodeError) as exc:
        raise DiscoveryError(f"{label} is not strict JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise DiscoveryError(f"{label} must be a JSON object")
    return value


def reject_symlink(path: pathlib.Path, label: str) -> None:
    absolute = path.absolute()
    current = pathlib.Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        if current.is_symlink():
            raise DiscoveryError(f"{label} path may not contain symlinks")


def regular(path: pathlib.Path, label: str) -> pathlib.Path:
    reject_symlink(path, label)
    if path.is_symlink() or not path.is_file():
        raise DiscoveryError(f"{label} must be a regular non-symlink file")
    return path.resolve(strict=True)


def load_assemblies(path: pathlib.Path) -> list[str]:
    raw = regular(path, "assembly report").read_bytes()
    if not raw or not raw.endswith(b"\n") or b"\r" in raw:
        raise DiscoveryError("assembly report must be LF-only with terminal LF")
    accessions: set[str] = set()
    for line_number, line in enumerate(raw.decode("utf-8").splitlines(), start=1):
        row = strict_object(line, f"assembly report line {line_number}")
        accession = row.get("accession")
        if not isinstance(accession, str) or ASSEMBLY_RE.fullmatch(accession) is None:
            raise DiscoveryError(f"invalid RefSeq assembly accession at line {line_number}")
        if accession in accessions:
            raise DiscoveryError(f"duplicate assembly accession: {accession}")
        accessions.add(accession)
    if not accessions:
        raise DiscoveryError("assembly report has no accessions")
    return sorted(accessions)


def validate_sequence_report(path: pathlib.Path, expected: set[str], label: str) -> tuple[int, int]:
    raw = regular(path, label).read_bytes()
    if not raw or not raw.endswith(b"\n") or b"\r" in raw:
        raise DiscoveryError(f"{label} must be LF-only with terminal LF")
    observed_assemblies: set[str] = set()
    observed_sequences: set[tuple[str, str]] = set()
    rows = 0
    for line_number, line in enumerate(raw.decode("utf-8").splitlines(), start=1):
        row = strict_object(line, f"{label} line {line_number}")
        # `datasets summary ... --as-json-lines` uses snake_case.  Keep this
        # byte-compatible with the package-level sequence_report.jsonl that the
        # selector and source freeze already consume.
        assembly = row.get("assembly_accession")
        sequence = row.get("refseq_accession")
        length = row.get("length")
        if assembly not in expected:
            raise DiscoveryError(f"{label} contains an assembly outside its batch: {assembly!r}")
        if not isinstance(sequence, str) or SEQUENCE_RE.fullmatch(sequence) is None:
            raise DiscoveryError(f"{label} has invalid sequence accession at line {line_number}")
        if isinstance(length, bool) or not isinstance(length, int) or length < 1:
            raise DiscoveryError(f"{label} has invalid sequence length at line {line_number}")
        identity = (assembly, sequence)
        if identity in observed_sequences:
            raise DiscoveryError(f"{label} has duplicate sequence identity: {identity}")
        observed_sequences.add(identity)
        observed_assemblies.add(assembly)
        rows += 1
    if observed_assemblies != expected:
        missing = sorted(expected - observed_assemblies)
        raise DiscoveryError(f"{label} does not cover its assembly batch; first missing={missing[:3]}")
    return rows, len(observed_assemblies)


def verify_tool(datasets: pathlib.Path, lock_path: pathlib.Path) -> tuple[str, str]:
    datasets = regular(datasets, "datasets executable")
    lock = strict_object(regular(lock_path, "datasets lock").read_text(encoding="utf-8"), "datasets lock")
    expected = lock.get("datasets")
    if not isinstance(expected, dict):
        raise DiscoveryError("datasets lock is malformed")
    observed_sha = sha256_file(datasets)
    if observed_sha != expected.get("sha256"):
        raise DiscoveryError("datasets executable SHA-256 drift")
    completed = subprocess.run([str(datasets), "version"], capture_output=True, text=True, timeout=30, check=False)
    version = completed.stdout.strip().removeprefix("datasets version: ")
    if completed.returncode != 0 or version != expected.get("version"):
        raise DiscoveryError("datasets executable version drift")
    return observed_sha, version


def discover(args: argparse.Namespace) -> None:
    if not 1 <= args.workers <= 30:
        raise DiscoveryError("workers must be between 1 and 30")
    if not 1 <= args.batch_size <= 5000:
        raise DiscoveryError("batch size must be between 1 and 5000")
    assemblies = load_assemblies(args.assembly_report)
    datasets_sha, datasets_version = verify_tool(args.datasets_bin, args.tool_lock)
    output = args.output_directory
    reject_symlink(output.parent, "output parent")
    if not output.parent.is_dir() or output.parent.is_symlink():
        raise DiscoveryError("output parent must be a real directory")
    output.mkdir(exist_ok=True)
    reject_symlink(output, "output directory")
    batches_dir = output / "batches"
    reports_dir = output / "reports"
    batches_dir.mkdir(exist_ok=True)
    reports_dir.mkdir(exist_ok=True)
    state = {
        "schema_version": "dosa-v3-u0-sequence-report-discovery-state-1",
        "assembly_report_sha256": sha256_file(args.assembly_report),
        "datasets_sha256": datasets_sha,
        "datasets_version": datasets_version,
        "assembly_count": len(assemblies),
        "batch_size": args.batch_size,
    }
    state_path = output / "discovery_state.json"
    state_bytes = (canonical_json(state) + "\n").encode("ascii")
    if state_path.exists():
        if regular(state_path, "discovery state").read_bytes() != state_bytes:
            raise DiscoveryError("existing discovery state differs")
    else:
        state_path.write_bytes(state_bytes)

    batches: list[tuple[pathlib.Path, pathlib.Path, set[str]]] = []
    for index, start in enumerate(range(0, len(assemblies), args.batch_size)):
        selected = assemblies[start:start + args.batch_size]
        batch_path = batches_dir / f"accessions-{index:05d}.txt"
        batch_bytes = "".join(value + "\n" for value in selected).encode("ascii")
        if batch_path.exists():
            if regular(batch_path, f"batch {index}").read_bytes() != batch_bytes:
                raise DiscoveryError(f"existing batch {index} differs")
        else:
            batch_path.write_bytes(batch_bytes)
        batches.append((batch_path, reports_dir / f"sequence-{index:05d}.jsonl", set(selected)))

    def retrieve(item: tuple[pathlib.Path, pathlib.Path, set[str]]) -> tuple[str, int, int]:
        batch_path, report_path, expected = item
        if report_path.exists():
            rows, _ = validate_sequence_report(report_path, expected, report_path.name)
            return report_path.name, rows, 0
        last_failure = "unattempted"
        for attempt in range(1, 4):
            descriptor, temporary_name = tempfile.mkstemp(prefix=f".{report_path.name}.", dir=reports_dir)
            os.close(descriptor)
            temporary = pathlib.Path(temporary_name)
            try:
                environment = dict(os.environ)
                environment.setdefault("GODEBUG", "http2client=0")
                with temporary.open("wb") as handle:
                    completed = subprocess.run(
                        [str(args.datasets_bin), "summary", "genome", "accession",
                         "--inputfile", str(batch_path), "--report", "sequence", "--as-json-lines"],
                        stdout=handle, stderr=subprocess.PIPE, timeout=7200, check=False, env=environment,
                    )
                if completed.returncode != 0:
                    detail = completed.stderr.decode("utf-8", errors="replace").strip()
                    raise DiscoveryError(
                        f"retrieval failed rc={completed.returncode}: {detail}"
                    )
                rows, _ = validate_sequence_report(
                    temporary, expected, f"temporary {report_path.name} attempt {attempt}"
                )
                os.replace(temporary, report_path)
                return report_path.name, rows, attempt
            except (OSError, subprocess.SubprocessError, DiscoveryError) as exc:
                last_failure = str(exc)
            finally:
                if temporary.exists():
                    temporary.unlink()
        raise DiscoveryError(f"{report_path.name} failed after 3 attempts: {last_failure}")

    results: list[tuple[str, int]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(retrieve, item): item[1].name for item in batches}
        for future in concurrent.futures.as_completed(futures):
            name, rows, attempt = future.result()
            results.append((name, rows))
            print(
                f"U0_SEQUENCE_REPORT_BATCH_PASS name={name} rows={rows} attempt={attempt}",
                flush=True,
            )

    merged = output / "sequence_data_report.jsonl"
    descriptor, merged_name = tempfile.mkstemp(prefix=".sequence_data_report.", dir=output)
    os.close(descriptor)
    merged_temporary = pathlib.Path(merged_name)
    try:
        with merged_temporary.open("wb") as target:
            for _, report_path, _ in batches:
                target.write(regular(report_path, report_path.name).read_bytes())
        expected_all = set(assemblies)
        sequence_rows, assembly_count = validate_sequence_report(
            merged_temporary, expected_all, "merged sequence report"
        )
        if merged.exists():
            if regular(merged, "existing merged sequence report").read_bytes() != merged_temporary.read_bytes():
                raise DiscoveryError("existing merged sequence report differs")
        else:
            os.replace(merged_temporary, merged)
    finally:
        if merged_temporary.exists():
            merged_temporary.unlink()
    receipt = {
        "schema_version": "dosa-v3-u0-sequence-report-discovery-receipt-1",
        "status": "PASS",
        "scientific_metrics_computed": False,
        "assembly_report_sha256": sha256_file(args.assembly_report),
        "assembly_accessions_sha256": hashlib.sha256("".join(value + "\n" for value in assemblies).encode("ascii")).hexdigest(),
        "datasets_sha256": datasets_sha,
        "datasets_version": datasets_version,
        "batch_size": args.batch_size,
        "batch_count": len(batches),
        "assembly_count": assembly_count,
        "sequence_count": sequence_rows,
        "sequence_report_path": "sequence_data_report.jsonl",
        "sequence_report_sha256": sha256_file(merged),
    }
    receipt_path = output / "sequence_report_discovery_receipt.json"
    receipt_bytes = (canonical_json(receipt) + "\n").encode("ascii")
    if receipt_path.exists():
        if regular(receipt_path, "discovery receipt").read_bytes() != receipt_bytes:
            raise DiscoveryError("existing discovery receipt differs")
    else:
        receipt_path.write_bytes(receipt_bytes)
    print(
        "U0_SEQUENCE_REPORT_DISCOVERY_PASS "
        f"assemblies={assembly_count} sequences={sequence_rows} batches={len(batches)} "
        f"workers={args.workers} scientific_metrics_computed=false"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembly-report", type=pathlib.Path, required=True)
    parser.add_argument("--datasets-bin", type=pathlib.Path, required=True)
    parser.add_argument("--tool-lock", type=pathlib.Path, required=True)
    parser.add_argument("--output-directory", type=pathlib.Path, required=True)
    parser.add_argument("--batch-size", type=int, default=1000)
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()
    try:
        discover(args)
        return 0
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError, DiscoveryError) as exc:
        print(f"U0_SEQUENCE_REPORT_DISCOVERY_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
