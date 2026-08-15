#!/usr/bin/env python3
"""Create deterministic hash-closed Sounio case shards for eligible U0 work units.

This is a pre-execution planner. It computes no scientific metric and emits no
execution receipt. Non-ACGT and zero-complete-window units are refused until a
separate reason-coded exclusion planner is implemented.
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
    build,
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
         output_directory: pathlib.Path, shard_size: int) -> dict[str, object]:
    if shard_size < 1 or shard_size > 32:
        raise PlanError("shard size must be in 1:32")
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
    for index, row in enumerate(rows, start=1):
        if row["declared_alphabet"] != "acgt":
            raise PlanError(f"work unit {index} requires reason-coded non-ACGT exclusion planning")
        if int(row["sequence_length"]) // int(row["scale"]) < 1:
            raise PlanError(f"work unit {index} requires reason-coded partial-window exclusion planning")

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
            total_windows = int(row["sequence_length"]) // scale
            unit_shards: list[int] = []
            for start_window in range(0, total_windows, shard_size):
                shard_index = len(shards)
                name = f"{accession.replace('.', '_')}-s{scale}-w{start_window:012d}.tsv"
                relative = pathlib.PurePosixPath("cases", name)
                target = temporary.joinpath(*relative.parts)
                metadata = build(
                    parameters, manifest, source_root, target, start_window,
                    shard_size, work_unit_id,
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
                    "path": relative.as_posix(),
                    "sha256": metadata["sha256"],
                    "size_bytes": metadata["size_bytes"],
                })
                unit_shards.append(shard_index)
            work_units.append({
                "work_unit_id": work_unit_id,
                "sequence_accession_version": accession,
                "scale": scale,
                "expected_rows": total_windows,
                "status": "planned",
                "reason_code": None,
                "shard_indices": unit_shards,
            })
        result: dict[str, object] = {
            "schema_version": "dosa-v3-u0-eligible-work-shard-plan-1",
            "evidence_scope": "preexecution_only",
            "parameters_sha256": parameters_sha,
            "work_unit_manifest_sha256": sha256_file(manifest),
            "shard_size": shard_size,
            "work_units_expected": len(work_units),
            "rows_expected": sum(int(unit["expected_rows"]) for unit in work_units),
            "shards_expected": len(shards),
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
    parser.add_argument("--shard-size", type=int, default=32)
    args = parser.parse_args()
    try:
        plan(args.parameters, args.manifest, args.source_root, args.output_directory, args.shard_size)
        return 0
    except (OSError, ValueError, BindingError, PlanError) as exc:
        print(f"U0_ELIGIBLE_WORK_SHARD_PLAN_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
