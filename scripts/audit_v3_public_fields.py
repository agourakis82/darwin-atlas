#!/usr/bin/env python3
"""Require a demonstrated public use for every field in the five v3 tables."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
from typing import Any


SCHEMAS = (
    "dosa_v3_run.schema.json",
    "dosa_v3_replicon.schema.json",
    "dosa_v3_window_profile.schema.json",
    "dosa_v3_summary.schema.json",
    "dosa_v3_exclusion.schema.json",
)


class AuditError(RuntimeError):
    pass


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SchemaInventory:
    def __init__(self, schema_dir: pathlib.Path):
        self.schema_dir = schema_dir
        self.cache: dict[pathlib.Path, dict[str, Any]] = {}

    def load(self, path: pathlib.Path) -> dict[str, Any]:
        if path not in self.cache:
            value = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(value, dict):
                raise AuditError(f"schema root is not an object: {path}")
            self.cache[path] = value
        return self.cache[path]

    @staticmethod
    def pointer(value: Any, fragment: str) -> Any:
        if not fragment:
            return value
        if not fragment.startswith("/"):
            raise AuditError(f"unsupported JSON pointer: #{fragment}")
        current = value
        for part in fragment[1:].split("/"):
            key = part.replace("~1", "/").replace("~0", "~")
            current = current[key]
        return current

    def resolve(self, current_path: pathlib.Path, ref: str) -> tuple[pathlib.Path, dict[str, Any]]:
        filename, _, fragment = ref.partition("#")
        target_path = current_path if not filename else self.schema_dir / filename
        target = self.pointer(self.load(target_path), fragment)
        if not isinstance(target, dict):
            raise AuditError(f"reference is not a schema object: {ref}")
        return target_path, target

    def fields(self, schema_name: str) -> set[str]:
        root_path = self.schema_dir / schema_name
        output: set[str] = set()
        visiting: set[tuple[pathlib.Path, int, str]] = set()

        def walk(node: Any, current_path: pathlib.Path, prefix: str) -> None:
            if not isinstance(node, dict):
                return
            marker = (current_path, id(node), prefix)
            if marker in visiting:
                return
            visiting.add(marker)
            ref = node.get("$ref")
            if isinstance(ref, str):
                target_path, target = self.resolve(current_path, ref)
                walk(target, target_path, prefix)
            properties = node.get("properties")
            if isinstance(properties, dict):
                for name, child in properties.items():
                    field = f"{prefix}.{name}" if prefix else name
                    output.add(field)
                    walk(child, current_path, field)
            items = node.get("items")
            if isinstance(items, dict):
                walk(items, current_path, prefix + "[]")
            for keyword in ("allOf", "oneOf", "anyOf"):
                alternatives = node.get(keyword)
                if isinstance(alternatives, list):
                    for child in alternatives:
                        walk(child, current_path, prefix)
            visiting.remove(marker)

        walk(self.load(root_path), root_path, "")
        return output


def read_rules(path: pathlib.Path) -> list[dict[str, Any]]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, list) or not value:
        raise AuditError("field-use rules must be a non-empty JSON array")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, rule in enumerate(value, start=1):
        if not isinstance(rule, dict) or set(rule) != {"rule_id", "field_pattern", "demonstrated_use", "evidence_gate"}:
            raise AuditError(f"invalid field-use rule {index}")
        if rule["rule_id"] in seen:
            raise AuditError(f"duplicate field-use rule id: {rule['rule_id']}")
        seen.add(rule["rule_id"])
        if not all(isinstance(rule[key], str) and rule[key].strip() for key in rule):
            raise AuditError(f"empty field-use rule value at rule {index}")
        try:
            compiled = re.compile(rule["field_pattern"])
        except re.error as exc:
            raise AuditError(f"invalid regex in rule {rule['rule_id']}: {exc}") from exc
        result.append({**rule, "compiled": compiled})
    return result


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema-dir", required=True, type=pathlib.Path)
    parser.add_argument("--rules", type=pathlib.Path)
    parser.add_argument("--evidence-scope", choices=("fixture", "u0_pilot"), default="fixture")
    parser.add_argument("--inventory", action="store_true")
    args = parser.parse_args()
    try:
        inventory = SchemaInventory(args.schema_dir)
        expected = {(schema, field) for schema in SCHEMAS for field in inventory.fields(schema)}
        if args.inventory:
            for schema, field in sorted(expected):
                print(f"{schema}\t{field}")
            return 0
        if args.rules is None:
            raise AuditError("--rules is required unless --inventory is used")
        rules = read_rules(args.rules)
        coverage: dict[tuple[str, str], str] = {}
        ambiguous: list[str] = []
        for schema, field in sorted(expected):
            matches = [rule for rule in rules if rule["compiled"].fullmatch(field)]
            if len(matches) == 1:
                coverage[(schema, field)] = matches[0]["rule_id"]
            elif len(matches) > 1:
                ambiguous.append(f"{schema}:{field}")
        missing = sorted(expected - set(coverage))
        used_rules = set(coverage.values())
        unused_rules = sorted(rule["rule_id"] for rule in rules if rule["rule_id"] not in used_rules)
        report = {
            "schema_version": "dosa-v3-field-utility-audit-1",
            "status": "pass" if not missing and not ambiguous and not unused_rules else "fail",
            "evidence_scope": args.evidence_scope,
            "published_fields": len(expected),
            "fields_with_demonstrated_use_or_removed": len(coverage),
            "unaccounted_fields": [f"{schema}:{field}" for schema, field in missing],
            "ambiguously_accounted_fields": ambiguous,
            "unused_rules": unused_rules,
            "rule_counts": {rule["rule_id"]: sum(value == rule["rule_id"] for value in coverage.values()) for rule in rules},
            "schema_sha256": {schema: sha256_file(args.schema_dir / schema) for schema in SCHEMAS},
            "rules_sha256": sha256_file(args.rules),
        }
        print(canonical(report))
        return 0 if report["status"] == "pass" else 2
    except (OSError, json.JSONDecodeError, AuditError, KeyError) as exc:
        print(canonical({"schema_version": "dosa-v3-field-utility-audit-1", "status": "fail", "evidence_scope": args.evidence_scope, "message": str(exc)}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
