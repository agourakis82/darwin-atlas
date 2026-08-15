#!/usr/bin/env python3
"""Execute or resume a hash-closed U0 work-shard plan with pinned Sounio bytes.

This orchestrator computes no scientific metric. It verifies case-ledger and
artifact bytes, invokes the supplied Sounio executable for missing shards, and
writes a deterministic TSV execution ledger. The ledger is fixture/development
evidence only: it is not the U0 output manifest or an execution receipt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Any


ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
LEDGER_HEADER = (
    "run_id", "plan_sha256", "work_unit_id", "sequence_accession_version",
    "scale", "start_window", "rows", "status", "reason_code", "case_path",
    "case_sha256", "artifact_path", "artifact_sha256", "artifact_size_bytes",
)


class ExecutionError(RuntimeError):
    pass


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def reject_symlink_components(path: pathlib.Path, label: str) -> None:
    absolute = path.absolute()
    current = pathlib.Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current = current / part
        if current.is_symlink():
            raise ExecutionError(f"{label} path may not contain symlinks")


def relative_path(raw: Any, label: str) -> pathlib.PurePosixPath:
    if not isinstance(raw, str):
        raise ExecutionError(f"{label} must be a relative POSIX path")
    value = pathlib.PurePosixPath(raw)
    if value.is_absolute() or not value.parts or any(part in ("", ".", "..") for part in value.parts):
        raise ExecutionError(f"{label} must be a safe relative POSIX path")
    return value


def strict_json(path: pathlib.Path) -> dict[str, Any]:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_bytes(), object_pairs_hook=unique)
    except (OSError, UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise ExecutionError(f"invalid plan JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ExecutionError("plan must be a JSON object")
    return value


def regular_below(root: pathlib.Path, relative: pathlib.PurePosixPath, label: str) -> pathlib.Path:
    candidate = root.joinpath(*relative.parts)
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ExecutionError(f"{label} path may not contain symlinks")
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root.resolve(strict=True))
    except (OSError, ValueError) as exc:
        raise ExecutionError(f"{label} escapes or is absent") from exc
    if not resolved.is_file() or resolved.is_symlink():
        raise ExecutionError(f"{label} must be a regular non-symlink file")
    return resolved


def validate_artifact(raw: bytes, shard: dict[str, Any], run_id: str) -> None:
    if not raw or not raw.endswith(b"\n") or b"\r" in raw:
        raise ExecutionError("Sounio artifact must be LF-only with terminal LF")
    lines = raw.splitlines()
    if len(lines) != shard["rows"]:
        raise ExecutionError("Sounio artifact row count differs from the shard plan")
    expected_indices = range(shard["start_window"], shard["start_window"] + shard["rows"])
    excluded_rows = 0
    for ordinal, (line, window_index) in enumerate(zip(lines, expected_indices, strict=True), start=1):
        def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
            value: dict[str, Any] = {}
            for key, item in pairs:
                if key in value:
                    raise ValueError(f"duplicate JSON key: {key}")
                value[key] = item
            return value
        try:
            row = json.loads(line, object_pairs_hook=unique)
        except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
            raise ExecutionError(f"Sounio artifact row {ordinal} is not JSON") from exc
        if not isinstance(row, dict):
            raise ExecutionError(f"Sounio artifact row {ordinal} is not an object")
        expected = {
            "run_id": run_id,
            "replicon_id": shard["sequence_accession_version"],
            "window_size": shard["scale"],
            "window_index": window_index,
            "window_start": window_index * shard["scale"],
            "window_end": (window_index + 1) * shard["scale"],
        }
        for field, value in expected.items():
            if row.get(field) != value:
                raise ExecutionError(f"Sounio artifact row {ordinal} {field} drift")
        if row.get("status") not in ("eligible", "excluded"):
            raise ExecutionError(f"Sounio artifact row {ordinal} status drift")
        excluded_rows += row.get("status") == "excluded"
    if excluded_rows != shard.get("excluded_rows"):
        raise ExecutionError("Sounio artifact excluded-row count differs from the shard plan")


def execute(plan_directory: pathlib.Path, executable: pathlib.Path,
            output_directory: pathlib.Path) -> dict[str, int | str]:
    for path, label in ((plan_directory, "plan directory"), (executable, "Sounio executable")):
        reject_symlink_components(path, label)
    if plan_directory.is_symlink() or not plan_directory.is_dir():
        raise ExecutionError("plan directory must be a real directory")
    if executable.is_symlink() or not executable.is_file() or not os.access(executable, os.X_OK):
        raise ExecutionError("Sounio executable must be an executable regular file")
    reject_symlink_components(output_directory.parent, "output parent")
    if not output_directory.parent.is_dir() or output_directory.parent.is_symlink():
        raise ExecutionError("output parent must be a real directory")
    if output_directory.exists():
        reject_symlink_components(output_directory, "output directory")
        if output_directory.is_symlink() or not output_directory.is_dir():
            raise ExecutionError("output directory must be a real directory")
    else:
        output_directory.mkdir()
    artifacts_directory = output_directory / "artifacts"
    artifacts_directory.mkdir(exist_ok=True)
    if artifacts_directory.is_symlink() or not artifacts_directory.is_dir():
        raise ExecutionError("artifact directory must be a real directory")

    plan_path = regular_below(plan_directory, pathlib.PurePosixPath("work_shard_plan.json"), "work-shard plan")
    plan = strict_json(plan_path)
    plan_sha = sha256_file(plan_path)
    if plan.get("schema_version") != "dosa-v3-u0-work-shard-plan-3":
        raise ExecutionError("unsupported work-shard plan version")
    if plan.get("evidence_scope") != "preexecution_only" or plan.get("sounio_executed") is not False or plan.get("gate_u0_pass") is not False:
        raise ExecutionError("input plan is not a pre-execution-only plan")
    run_id = plan.get("run_id")
    if not isinstance(run_id, str) or ID_RE.fullmatch(run_id) is None or len(run_id) > 128:
        raise ExecutionError("plan run_id is invalid")
    work_units = plan.get("work_units")
    shards = plan.get("shards")
    if not isinstance(work_units, list) or not isinstance(shards, list):
        raise ExecutionError("plan ledgers are missing")

    rows: list[tuple[str, ...]] = []
    allowed_outputs = {"execution_ledger.tsv"}
    executed = 0
    reused = 0
    for expected_index, shard in enumerate(shards):
        if not isinstance(shard, dict) or shard.get("shard_index") != expected_index:
            raise ExecutionError("shard order/index drift")
        case_relative = relative_path(shard.get("path"), f"shard {expected_index} case path")
        case_path = regular_below(plan_directory, case_relative, f"shard {expected_index} case")
        case_sha = shard.get("sha256")
        if not isinstance(case_sha, str) or SHA_RE.fullmatch(case_sha) is None or sha256_file(case_path) != case_sha:
            raise ExecutionError(f"shard {expected_index} case SHA-256 mismatch")
        if case_path.stat().st_size != shard.get("size_bytes"):
            raise ExecutionError(f"shard {expected_index} case size mismatch")
        artifact_name = case_path.stem + ".jsonl"
        artifact_relative = pathlib.PurePosixPath("artifacts", artifact_name)
        artifact_path = output_directory.joinpath(*artifact_relative.parts)
        allowed_outputs.add(artifact_relative.as_posix())
        if artifact_path.exists():
            if artifact_path.is_symlink() or not artifact_path.is_file():
                raise ExecutionError(f"existing shard {expected_index} artifact is not regular")
            artifact = artifact_path.read_bytes()
            validate_artifact(artifact, shard, run_id)
            reused += 1
        else:
            command = [
                str(executable), str(case_path), "--work-unit-profile", run_id,
                str(shard["start_window"]),
            ]
            completed = subprocess.run(command, capture_output=True, timeout=86400, check=False)
            if completed.returncode != 0:
                raise ExecutionError(f"Sounio shard {expected_index} failed with rc={completed.returncode}")
            if completed.stderr:
                raise ExecutionError(f"Sounio shard {expected_index} emitted unexpected stderr")
            artifact = completed.stdout
            validate_artifact(artifact, shard, run_id)
            with artifact_path.open("xb") as handle:
                handle.write(artifact)
            executed += 1
        rows.append((
            run_id, plan_sha, str(shard["work_unit_id"]), str(shard["sequence_accession_version"]),
            str(shard["scale"]), str(shard["start_window"]), str(shard["rows"]), "complete", "",
            case_relative.as_posix(), case_sha, artifact_relative.as_posix(), sha256_bytes(artifact),
            str(len(artifact)),
        ))

    for unit in work_units:
        if not isinstance(unit, dict):
            raise ExecutionError("work-unit ledger contains a non-object")
        if unit.get("status") == "excluded":
            if unit.get("expected_rows") != 0 or unit.get("reason_code") != "PARTIAL_WINDOW" or unit.get("shard_indices") != []:
                raise ExecutionError("excluded work-unit contract drift")
            rows.append((
                run_id, plan_sha, str(unit["work_unit_id"]), str(unit["sequence_accession_version"]),
                str(unit["scale"]), "-1", "0", "excluded", "PARTIAL_WINDOW", "", "", "", "", "0",
            ))

    ledger = ("\t".join(LEDGER_HEADER) + "\n" + "\n".join("\t".join(row) for row in rows) + "\n").encode("ascii")
    ledger_path = output_directory / "execution_ledger.tsv"
    if ledger_path.exists():
        if ledger_path.is_symlink() or ledger_path.read_bytes() != ledger:
            raise ExecutionError("existing execution ledger differs from the recomputed ledger")
    else:
        with ledger_path.open("xb") as handle:
            handle.write(ledger)

    observed = set()
    for path in output_directory.rglob("*"):
        if path.is_symlink():
            raise ExecutionError("output tree may not contain symlinks")
        if path.is_file():
            observed.add(path.relative_to(output_directory).as_posix())
    if observed != allowed_outputs:
        raise ExecutionError("output directory contains missing or unmanifested files")
    result: dict[str, int | str] = {
        "run_id": run_id,
        "plan_sha256": plan_sha,
        "ledger_sha256": sha256_bytes(ledger),
        "shards": len(shards),
        "rows": sum(int(shard["rows"]) for shard in shards),
        "excluded_work_units": sum(unit.get("status") == "excluded" for unit in work_units if isinstance(unit, dict)),
        "executed_shards": executed,
        "reused_shards": reused,
    }
    print(
        "U0_WORK_SHARD_SET_EXECUTION_PASS "
        f"run_id={run_id} shards={result['shards']} rows={result['rows']} "
        f"executed={executed} reused={reused} excluded_work_units={result['excluded_work_units']} "
        "fixture_scope_nonpromotable=1"
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-directory", type=pathlib.Path, required=True)
    parser.add_argument("--executor", type=pathlib.Path, required=True)
    parser.add_argument("--output-directory", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        execute(args.plan_directory, args.executor, args.output_directory)
        return 0
    except (KeyError, OSError, TypeError, ValueError, subprocess.SubprocessError, ExecutionError) as exc:
        print(f"U0_WORK_SHARD_SET_EXECUTION_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
