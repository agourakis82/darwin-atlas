#!/usr/bin/env python3
"""Meta-validate the DOSA v3 schemas and their canonical U0 parameter object.

This integration check deliberately depends on the external ``jsonschema``
package.  The lighter ``make u0-contract`` target still performs duplicate-key
and project-specific checks without silently replacing JSON Schema validation.
"""
from __future__ import annotations

import copy
import json
import pathlib
import sys

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCHEMA_DIR = ROOT / "schemas"
SCHEMA_PATHS = sorted(SCHEMA_DIR.glob("dosa_v3_*.schema.json"))


def load(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def fail(message: str) -> None:
    raise SystemExit("DOSA_V3_SCHEMA_VALIDATION_FAIL: " + message)


def registry_for(schemas: list[dict]) -> Registry:
    registry = Registry()
    for schema in schemas:
        identifier = schema.get("$id")
        if not isinstance(identifier, str):
            fail("every schema must declare an absolute $id")
        registry = registry.with_resource(identifier, Resource.from_contents(schema))
        # Relative references in the project resolve against the parent $id,
        # but registering the canonical basename also makes that closure
        # explicit and independently testable.
        registry = registry.with_resource(identifier.rsplit("/", 1)[-1], Resource.from_contents(schema))
    return registry


def source_manifest_fixture() -> dict:
    sha = "0" * 64
    return {
        "schema_version": "3.0.0",
        "manifest_id": "u0-source-fixture",
        "retrieved_utc": "2026-08-14T00:00:00Z",
        "source_provider": "NCBI_Datasets",
        "query": {
            "path": "source/query.json",
            "sha256": sha,
            "size_bytes": 1,
            "object": {"taxon": "bacteria"},
        },
        "acquisition_tools": {
            "datasets": {
                "version": "18.35.0",
                "source_url": "https://ftp.ncbi.nlm.nih.gov/datasets",
                "sha256": sha,
                "size_bytes": 1,
            },
            "dataformat": {
                "version": "undefined-hash-pinned",
                "source_url": "https://ftp.ncbi.nlm.nih.gov/dataformat",
                "sha256": sha,
                "size_bytes": 1,
            },
        },
        "package": {
            "package_id": "fixture-package",
            "source_url": "https://api.ncbi.nlm.nih.gov/datasets/v2alpha/genome/download",
            "package_root": "source/package",
            "dehydrated_archive": {"path": "source/package.zip", "sha256": sha, "size_bytes": 1},
            "catalog": {"path": "source/catalog.json", "sha256": sha, "size_bytes": 1},
            "checksum_manifest": {"path": "source/SHA256SUMS", "sha256": sha, "size_bytes": 1},
            "catalog_verified": True,
            "package_checksums_verified": True,
            "selected_assets_complete": True,
        },
        "selected_records": [
            {
                "source_record_id": "NC_000001.1",
                "replicon_id": "NC_000001.1",
                "assembly_accession_version": "GCF_000000001.1",
                "sequence_accession_version": "NC_000001.1",
                "required_asset_kinds": ["fasta", "gbff", "sequence_report"],
            }
        ],
        "package_assets": [
            {
                "asset_id": "fasta-1",
                "asset_kind": kind,
                "assembly_accession_version": "GCF_000000001.1",
                "sequence_accession_version": "NC_000001.1",
                "selected_record_ids": ["NC_000001.1"],
                "source_url": f"https://api.ncbi.nlm.nih.gov/{kind}",
                "package_path": f"source/{kind}.dat",
                "sha256": sha,
                "size_bytes": 1,
            }
            for kind in ("fasta", "gbff", "sequence_report")
        ],
    }


def source_index_fixture() -> dict:
    sha = "0" * 64
    return {
        "source_index_version": "dosa-v3-source-index-1",
        "records": {
            "NC_000001.1": {
                "locator": "package/rehydrated/ncbi_dataset/data/GCF_000000001.1/GCF_000000001.1_genomic.fna",
                "canonical_sequence_input_sha256": sha,
                "normalized_sequence_sha256": sha,
                "source_manifest_sha256": sha,
                "source_integrity_sha256": sha,
            }
        },
    }


def blocked_receipt_fixture() -> dict:
    sha = "0" * 64
    operational = (
        "sounio_julia_full_agreement",
        "query_transfer_le_5_gib_and_time_le_60_seconds",
        "lookup_speedup_ge_100",
        "external_source_and_hash_verification",
        "parquet_projection_with_2x_margin",
        "public_field_utility_audit",
    )
    scientific = (
        "dosa_oric_terminus_secondary_gate",
        "dosa_rc_equivariance_secondary_benchmark",
    )
    missing = lambda identifier: {
        "requirement_id": identifier,
        "state": "NOT_YET_PASSED",
        "receipt_path": None,
        "receipt_sha256": None,
        "reason_code": "RECEIPT_MISSING",
    }
    gate = {
        "state": "NOT_YET_PASSED",
        "receipt_path": None,
        "receipt_sha256": None,
        "reason_code": "RECEIPT_MISSING",
    }
    return {
        "schema_version": "3.0.0",
        "receipt_id": "u0-blocked-fixture",
        "run_id": "u0-fixture-run",
        "parameters_sha256": sha,
        "source_manifest_sha256": sha,
        "payload_manifest_sha256": sha,
        "source_identity": {
            "git_commit_full": "0" * 40,
            "git_tree_full": "0" * 40,
            "clean": True,
            "tag": None,
            "remote_url": "https://github.com/agourakis82/darwin-atlas",
            "source_archive_path": "source/dosa-u0-fixture.tar.gz",
            "source_archive_sha256": sha,
        },
        "producer": {
            "language": "Sounio",
            "repository": "https://github.com/sounio-lang/sounio.git",
            "repository_commit": "0" * 40,
            "source_sha256": sha,
            "compiler_sha256": sha,
            "executable_sha256": sha,
            "receipt_path": "receipts/sounio.json",
            "receipt_sha256": sha,
        },
        "validator": {
            "language": "Julia",
            "version": "fixture",
            "project_sha256": sha,
            "manifest_sha256": sha,
            "implementation_sha256": sha,
            "rows_recomputed": 1,
            "disagreements": 0,
            "absolute_tolerance": 0,
            "receipt_path": "receipts/julia.json",
            "receipt_sha256": sha,
        },
        "accelerators": [],
        "runtime_environment": {
            "os_release": "fixture",
            "architecture": "fixture",
            "container_digest": None,
        },
        "remote_inventories": [
            {
                "provider": provider,
                "state": "NOT_UPLOADED",
                "accession": None,
                "file_count": 0,
                "api_inventory_sha256": None,
                "receipt_path": None,
                "receipt_sha256": None,
            }
            for provider in ("BioStudies", "Zenodo")
        ],
        "u0_evaluation": {
            "state": "NOT_YET_PASSED",
            "reason_code": "U0_REQUIREMENT_FAILED",
            "evidence_scope": "fixture",
            "mandatory_operational_requirements": [missing(item) for item in operational],
            "scientific_secondary_tests": [missing(item) for item in scientific],
        },
        "full_atlas_execution_state": "BLOCKED_UNTIL_U0",
        "hdd_purchase_state": "BLOCKED_UNTIL_U0",
        "release_gates": {
            "full_producer": dict(gate),
            "full_julia": dict(gate),
            "payload": dict(gate),
            "external_use": dict(gate),
        },
        "release_state": "BLOCKED",
    }


def payload_manifest_fixture() -> dict:
    sha = "0" * 64
    def single(name: str, schema: str) -> dict:
        return {
            "filename": name,
            "schema_id": schema,
            "record_count": 1,
            "storage": {"layout": "single_file", "path": name, "sha256": sha, "size_bytes": 1},
        }
    return {
        "schema_version": "3.0.0",
        "payload_id": "u0-payload-fixture",
        "run_id": "u0-fixture-run",
        "parameters_sha256": sha,
        "source_manifest_sha256": sha,
        "public_tables": [
            single("runs.parquet", "dosa-v3-run-1"),
            single("replicons.parquet", "dosa-v3-replicon-1"),
            {
                "filename": "window_operator_profiles.parquet",
                "schema_id": "dosa-v3-window-profile-1",
                "record_count": 1,
                "storage": {
                    "layout": "package_manifest_partitioned",
                    "partitioning": "scale_then_sha256_accession_bucket",
                    "package_manifest_ids": ["fixture-window-shards"],
                },
            },
            single("replicon_operator_summary.parquet", "dosa-v3-summary-1"),
            single("excluded_records.parquet", "dosa-v3-exclusion-1"),
        ],
        "package_manifests": [{
            "package_manifest_id": "fixture-window-shards",
            "path": "packages/fixture/dosa-payload-manifest.json",
            "sha256": sha,
            "size_bytes": 1,
            "table_filename": "window_operator_profiles.parquet",
            "manifest_version": "dosa-v3-u0-dev-payload-manifest-3",
            "package_version": "U0-dev",
        }],
        "supporting_artifacts": [],
        "release_state": "blocked_pending_receipts",
    }


def main() -> int:
    if len(SCHEMA_PATHS) != 11:
        fail(f"expected exactly 11 v3 schemas, found {len(SCHEMA_PATHS)}")
    schemas = [load(path) for path in SCHEMA_PATHS]
    required_invariants = {
        "dosa_v3_window_profile.schema.json": {
            "window_end - window_start == window_size",
            "window_start == window_index * window_size",
            "available observed.denominator == effective_count",
            "available null_summary.tail_lt + tail_eq + tail_gt == null_summary.n",
            "available null_summary.q025 <= q500 <= q975",
        },
        "dosa_v3_summary.schema.json": {
            "windows_eligible + windows_excluded == windows_total",
            "available observed.denominator == effective_count",
            "available null_summary.tail_lt + tail_eq + tail_gt == null_summary.n",
            "available null_summary.q025 <= q500 <= q975",
        },
    }
    for path, schema in zip(SCHEMA_PATHS, schemas):
        if path.name in required_invariants and set(schema.get("x-dosa-cross-field-invariants", [])) != required_invariants[path.name]:
            fail(f"cross-field invariant registry drift: {path.name}")
    registry = registry_for(schemas)
    validators: dict[str, Draft202012Validator] = {}
    for path, schema in zip(SCHEMA_PATHS, schemas):
        Draft202012Validator.check_schema(schema)
        validators[path.name] = Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        )

    parameters = load(ROOT / "data" / "v3" / "u0_parameters.json")
    parameter_validator = validators["dosa_v3_parameters.schema.json"]
    parameter_validator.validate(parameters)
    invalid_parameters = copy.deepcopy(parameters)
    invalid_parameters["null_replicates"] = 999
    if parameter_validator.is_valid(invalid_parameters):
        fail("parameter schema accepted null_replicates=999")
    invalid_parameters = copy.deepcopy(parameters)
    invalid_parameters["window_profiles"][1]["stride"] = 16
    if parameter_validator.is_valid(invalid_parameters):
        fail("parameter schema accepted stride != window_size")

    source = source_manifest_fixture()
    source_validator = validators["dosa_v3_source_manifest.schema.json"]
    source_validator.validate(source)
    invalid_source = copy.deepcopy(source)
    invalid_source["package_assets"][0]["package_path"] = "/private/cluster/file.fa"
    if source_validator.is_valid(invalid_source):
        fail("source manifest accepted a private absolute path")
    invalid_source = copy.deepcopy(source)
    invalid_source["selected_records"][0]["sequence_accession_version"] = "NC_000001"
    if source_validator.is_valid(invalid_source):
        fail("source manifest accepted an unversioned accession")

    payload = payload_manifest_fixture()
    payload_validator = validators["dosa_v3_payload_manifest.schema.json"]
    payload_validator.validate(payload)
    invalid_payload = copy.deepcopy(payload)
    invalid_payload["public_tables"][2]["storage"] = {
        "layout": "single_file", "path": "window_operator_profiles.parquet", "sha256": "0" * 64, "size_bytes": 1,
    }
    if payload_validator.is_valid(invalid_payload):
        fail("payload manifest accepted an unpartitioned window table")

    source_index = source_index_fixture()
    source_index_validator = validators["dosa_v3_source_index.schema.json"]
    source_index_validator.validate(source_index)
    invalid_source_index = copy.deepcopy(source_index)
    invalid_source_index["records"]["NC_000001.1"]["locator"] = "/private/cluster/file.fa"
    if source_index_validator.is_valid(invalid_source_index):
        fail("source index accepted a private absolute locator")
    invalid_source_index = copy.deepcopy(source_index)
    invalid_source_index["records"]["NC_000001"] = invalid_source_index["records"].pop("NC_000001.1")
    if source_index_validator.is_valid(invalid_source_index):
        fail("source index accepted an unversioned accession key")

    receipt = blocked_receipt_fixture()
    receipt_validator = validators["dosa_v3_receipt.schema.json"]
    receipt_validator.validate(receipt)
    invalid_receipt = copy.deepcopy(receipt)
    invalid_receipt["release_state"] = "PASSED"
    if receipt_validator.is_valid(invalid_receipt):
        fail("receipt schema accepted release passage without U0, v3.0.0, accelerators and remote closure")
    invalid_receipt = copy.deepcopy(receipt)
    invalid_receipt["producer"]["receipt_path"] = "/private/cluster/producer.json"
    if receipt_validator.is_valid(invalid_receipt):
        fail("receipt schema accepted a private absolute evidence path")

    print(
        "DOSA_V3_SCHEMA_INTEGRATION_PASS "
        f"schemas={len(schemas)} parameter_negative_cases=2 source_negative_cases=2 source_index_negative_cases=2 payload_negative_cases=1 receipt_negative_cases=2"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
