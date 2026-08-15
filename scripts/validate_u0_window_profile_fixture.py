#!/usr/bin/env python3
"""Stdlib structural validator for the four-row U0 profile fixture.

Scientific recomputation belongs to Julia. This companion parser ensures the
byte-exact protocol is also strict JSON with the exact nested v3 field surface
and cross-field invariants before the runner reports PASS.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import pathlib
import sys
from fractions import Fraction
from typing import Any


class ProfileError(RuntimeError):
    pass


TOP_KEYS = {
    "run_id", "replicon_id", "window_size", "window_index", "window_start", "window_end",
    "status", "reason_code", "positional_r", "positional_rc", "kmer_r", "kmer_rc",
}
OBS_KEYS = {"effective_count", "observed", "null_summary", "reason_code"}
NULL_KEYS = {"n", "mean", "mad", "q025", "q500", "q975", "tail_lt", "tail_eq", "tail_gt", "reason_code"}


def strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ProfileError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def nonnegative_integer(value: Any, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ProfileError(f"{name} must be a non-negative integer")
    return value


def positive_integer(value: Any, name: str) -> int:
    result = nonnegative_integer(value, name)
    if result < 1:
        raise ProfileError(f"{name} must be positive")
    return result


def exact_fraction(value: Any, name: str) -> Fraction:
    if not isinstance(value, dict) or set(value) != {"numerator", "denominator"}:
        raise ProfileError(f"{name} must be an exact fraction")
    return Fraction(
        nonnegative_integer(value["numerator"], f"{name}.numerator"),
        positive_integer(value["denominator"], f"{name}.denominator"),
    )


def validate_observation(value: Any, name: str, expected_k: int | None) -> None:
    if not isinstance(value, dict):
        raise ProfileError(f"{name} must be an object")
    expected_keys = OBS_KEYS | ({"k"} if expected_k is not None else set())
    if set(value) != expected_keys:
        raise ProfileError(f"{name} field set drift")
    if expected_k is not None and value.get("k") != expected_k:
        raise ProfileError(f"{name}.k order drift")
    effective = positive_integer(value.get("effective_count"), f"{name}.effective_count")
    observed = value.get("observed")
    exact_fraction(observed, f"{name}.observed")
    if observed["denominator"] != effective:
        raise ProfileError(f"{name} observed denominator/effective mismatch")
    if value.get("reason_code") is not None:
        raise ProfileError(f"{name} available observation has a reason")
    null = value.get("null_summary")
    if not isinstance(null, dict) or set(null) != NULL_KEYS:
        raise ProfileError(f"{name}.null_summary field set drift")
    if null.get("n") != 1000 or null.get("reason_code") is not None:
        raise ProfileError(f"{name}.null_summary is not a complete n=1000 block")
    for field in ("mean", "mad", "q025", "q500", "q975"):
        exact_fraction(null.get(field), f"{name}.null_summary.{field}")
    tails = sum(nonnegative_integer(null.get(field), f"{name}.null_summary.{field}")
                for field in ("tail_lt", "tail_eq", "tail_gt"))
    if tails != 1000:
        raise ProfileError(f"{name}.null_summary tails do not partition 1000")
    q025 = exact_fraction(null["q025"], f"{name}.null_summary.q025")
    q500 = exact_fraction(null["q500"], f"{name}.null_summary.q500")
    q975 = exact_fraction(null["q975"], f"{name}.null_summary.q975")
    if not q025 <= q500 <= q975:
        raise ProfileError(f"{name}.null_summary quantiles are not ordered")


def validate_schema(rows: list[dict[str, Any]], schema_dir: pathlib.Path) -> None:
    try:
        from jsonschema import Draft202012Validator, FormatChecker
        from referencing import Registry, Resource
    except ImportError as exc:
        raise ProfileError("jsonschema==4.26.0 is required for public-schema validation") from exc
    if importlib.metadata.version("jsonschema") != "4.26.0":
        raise ProfileError("public-schema validation requires exact jsonschema==4.26.0")
    if not schema_dir.is_dir() or schema_dir.is_symlink():
        raise ProfileError("schema directory must be a real directory")
    registry = Registry()
    schemas: dict[str, dict[str, Any]] = {}
    for schema_path in sorted(schema_dir.glob("dosa_v3_*.schema.json")):
        try:
            schema = json.loads(schema_path.read_bytes(), object_pairs_hook=strict_object)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ProfileError) as exc:
            raise ProfileError(f"invalid schema {schema_path.name}: {exc}") from exc
        if not isinstance(schema, dict) or not isinstance(schema.get("$id"), str):
            raise ProfileError(f"schema {schema_path.name} has no $id")
        schemas[schema_path.name] = schema
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    try:
        target = schemas["dosa_v3_window_profile.schema.json"]
    except KeyError as exc:
        raise ProfileError("public window-profile schema is missing") from exc
    Draft202012Validator.check_schema(target)
    validator = Draft202012Validator(target, registry=registry, format_checker=FormatChecker())
    for ordinal, row in enumerate(rows, start=1):
        errors = list(validator.iter_errors(row))
        if errors:
            raise ProfileError(f"row {ordinal} public-schema failure: {errors[0].message}")
    print(f"U0_WINDOW_PROFILE_JSON_SCHEMA_PASS rows={len(rows)} schema={target['$id']}")


def validate(path: pathlib.Path, schema_dir: pathlib.Path | None = None) -> None:
    if not path.is_file() or path.is_symlink() or path.stat().st_size < 1:
        raise ProfileError("profile artifact must be a non-empty regular non-symlink file")
    raw = path.read_bytes()
    if not raw.endswith(b"\n") or b"\r" in raw:
        raise ProfileError("profile artifact must be LF-only with terminal LF")
    lines = raw.splitlines()
    if len(lines) != 4:
        raise ProfileError("profile artifact must contain exactly four rows")
    expected_scales = (16, 100, 500, 1000)
    rows: list[dict[str, Any]] = []
    for ordinal, (line, expected_scale) in enumerate(zip(lines, expected_scales, strict=True), start=1):
        try:
            row = json.loads(line, object_pairs_hook=strict_object)
        except (UnicodeDecodeError, json.JSONDecodeError, ProfileError) as exc:
            raise ProfileError(f"row {ordinal} is not strict JSON: {exc}") from exc
        if not isinstance(row, dict) or set(row) != TOP_KEYS:
            raise ProfileError(f"row {ordinal} top-level field set drift")
        rows.append(row)
        if row.get("run_id") != "u0-profile-fixture" or not isinstance(row.get("replicon_id"), str):
            raise ProfileError(f"row {ordinal} identity drift")
        size = positive_integer(row.get("window_size"), f"row {ordinal}.window_size")
        index = nonnegative_integer(row.get("window_index"), f"row {ordinal}.window_index")
        start = nonnegative_integer(row.get("window_start"), f"row {ordinal}.window_start")
        end = positive_integer(row.get("window_end"), f"row {ordinal}.window_end")
        if size != expected_scale or end - start != size or start != index * size:
            raise ProfileError(f"row {ordinal} coordinate contract drift")
        if row.get("status") != "eligible" or row.get("reason_code") is not None:
            raise ProfileError(f"row {ordinal} eligibility drift")
        validate_observation(row.get("positional_r"), f"row {ordinal}.positional_r", None)
        validate_observation(row.get("positional_rc"), f"row {ordinal}.positional_rc", None)
        kmer_r = row.get("kmer_r")
        kmer_rc = row.get("kmer_rc")
        if not isinstance(kmer_r, list) or len(kmer_r) != 7:
            raise ProfileError(f"row {ordinal}.kmer_r cardinality drift")
        if not isinstance(kmer_rc, list) or len(kmer_rc) != 8:
            raise ProfileError(f"row {ordinal}.kmer_rc cardinality drift")
        for value, k in zip(kmer_r, range(2, 9), strict=True):
            validate_observation(value, f"row {ordinal}.kmer_r[{k}]", k)
        for value, k in zip(kmer_rc, range(1, 9), strict=True):
            validate_observation(value, f"row {ordinal}.kmer_rc[{k}]", k)
    if schema_dir is not None:
        validate_schema(rows, schema_dir)
    print("U0_WINDOW_PROFILE_STRUCTURE_PASS rows=4 metrics=17 null_replicates=1000")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=pathlib.Path)
    parser.add_argument("--schema-dir", type=pathlib.Path)
    args = parser.parse_args()
    try:
        validate(args.artifact, args.schema_dir)
        return 0
    except (OSError, ProfileError) as exc:
        print(f"U0_WINDOW_PROFILE_STRUCTURE_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
