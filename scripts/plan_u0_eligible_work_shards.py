#!/usr/bin/env python3
"""Create deterministic hash-closed Sounio case shards for U0 work units.

This is a pre-execution planner. It computes no scientific metric and emits no
execution receipt. Ambiguous windows are marked `NULL_INPUT_NOT_ACGT` in their
case ledgers; zero-complete-window units are retained as `PARTIAL_WINDOW`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import tempfile
import sys

from build_u0_work_unit_case import (
    BindingError,
    ID_RE,
    build,
    inspect_selected_work_unit,
    reject_symlink_components,
    validated_manifest_rows,
)


PARAMETERS_SHA256 = "68343e046af24a997195eb2583532d3172234b0b9713f2e4296b9b12300bef94"


class PlanError(RuntimeError):
    pass


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json_bytes(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def plan(parameters: pathlib.Path, manifest: pathlib.Path, source_root: pathlib.Path,
         output_directory: pathlib.Path, shard_size: int, run_id: str) -> dict[str, object]:
    if shard_size < 1 or shard_size > 16:
        raise PlanError("shard size must be in 1:16")
    if ID_RE.fullmatch(run_id) is None or len(run_id) > 128:
        raise PlanError("run_id must be a portable identifier of at most 128 bytes")
    for path, label in ((parameters, "parameters"), (manifest, "manifest")):
        reject_symlink_components(path, label)
        if path.is_symlink() or not path.is_file():
            raise PlanError(f"{label} must be a regular non-symlink file")
    reject_symlink_components(source_root, "source root")
    if source_root.is_symlink() or not source_root.is_dir():
        raise PlanError("source root must be a real directory")
    reject_symlink_components(output_directory.parent, "output parent")
    if output_directory.exists() or output_directory.is_symlink():
        raise PlanError("output directory already exists")
    if output_directory.parent.is_symlink() or not output_directory.parent.is_dir():
        raise PlanError("output parent must already be a real directory")
    parameters_sha = sha256_file(parameters)
    if parameters_sha != PARAMETERS_SHA256:
        raise PlanError("canonical U0 parameter bytes drifted")
    rows = validated_manifest_rows(manifest, parameters_sha)
    temporary = pathlib.Path(tempfile.mkdtemp(prefix=f".{output_directory.name}.tmp-", dir=output_directory.parent))
    try:
        cases_directory = temporary / "cases"
        cases_directory.mkdir()
        work_units: list[dict[str, object]] = []
        shards: list[dict[str, object]] = []
        for row in rows:
            work_unit_id = row["work_unit_id"]
            accession = row["sequence_accession_version"]
            scale = int(row["scale"])
            inspected_row, sequence, inspected_parameters_sha = inspect_selected_work_unit(
                parameters, manifest, source_root, work_unit_id,
            )
            if inspected_row != row or inspected_parameters_sha != parameters_sha:
                raise PlanError("work-unit source inspection drifted from canonical manifest")
            if len(sequence) != int(row["sequence_length"]):
                raise PlanError("work-unit source inspection returned an unexpected sequence length")
            total_windows = int(row["sequence_length"]) // scale
            unit_shards: list[int] = []
            for start_window in range(0, total_windows, shard_size):
                shard_index = len(shards)
                name = f"{accession.replace('.', '_')}-s{scale}-w{start_window:012d}.tsv"
                relative = pathlib.PurePosixPath("cases", name)
                target = temporary.joinpath(*relative.parts)
                metadata = build(
                    parameters, manifest, source_root, target, start_window,
                    shard_size, work_unit_id, run_id,
                )
                if metadata["rows"] != min(shard_size, total_windows - start_window):
                    raise PlanError("builder returned an unexpected shard row count")
                shards.append({
                    "shard_index": shard_index,
                    "work_unit_id": work_unit_id,
                    "sequence_accession_version": accession,
                    "scale": scale,
                    "start_window": start_window,
                    "rows": metadata["rows"],
                    "excluded_rows": metadata["excluded_rows"],
                    "path": relative.as_posix(),
                    "sha256": metadata["sha256"],
                    "size_bytes": metadata["size_bytes"],
                })
                unit_shards.append(shard_index)
            status = "planned" if total_windows > 0 else "excluded"
            reason_code = None if total_windows > 0 else "PARTIAL_WINDOW"
            work_units.append({
                "work_unit_id": work_unit_id,
                "sequence_accession_version": accession,
                "scale": scale,
                "expected_rows": total_windows,
                "status": status,
                "reason_code": reason_code,
                "shard_indices": unit_shards,
            })
        result: dict[str, object] = {
            "schema_version": "dosa-v3-u0-work-shard-plan-3",
            "evidence_scope": "preexecution_only",
            "run_id": run_id,
            "parameters_sha256": parameters_sha,
            "work_unit_manifest_sha256": sha256_file(manifest),
            "shard_size": shard_size,
            "work_units_expected": len(work_units),
            "rows_expected": sum(int(unit["expected_rows"]) for unit in work_units),
            "shards_expected": len(shards),
            "excluded_work_units": sum(unit["status"] == "excluded" for unit in work_units),
            "excluded_windows": sum(int(shard["excluded_rows"]) for shard in shards),
            "scientific_metrics_computed": False,
            "sounio_executed": False,
            "gate_u0_pass": False,
            "work_units": work_units,
            "shards": shards,
        }
        (temporary / "work_shard_plan.json").write_bytes(canonical_json_bytes(result))
        os.replace(temporary, output_directory)
        print(
            "U0_ELIGIBLE_WORK_SHARD_PLAN_PASS "
            f"work_units={len(work_units)} shards={len(shards)} rows={result['rows_expected']} "
            f"shard_size={shard_size} preexecution_only=1"
        )
        return result
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parameters", type=pathlib.Path, required=True)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source-root", type=pathlib.Path, required=True)
    parser.add_argument("--output-directory", type=pathlib.Path, required=True)
    parser.add_argument("--shard-size", type=int, default=16)
    parser.add_argument("--run-id", default="u0-work-unit-fixture")
    args = parser.parse_args()
    try:
        plan(args.parameters, args.manifest, args.source_root, args.output_directory, args.shard_size, args.run_id)
        return 0
    except (OSError, ValueError, BindingError, PlanError) as exc:
        print(f"U0_ELIGIBLE_WORK_SHARD_PLAN_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
