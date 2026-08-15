from __future__ import annotations

import hashlib
import inspect
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


CLI_ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE_ROOT = CLI_ROOT / "package"
ENTRYPOINT = CLI_ROOT / "bin" / "dosa"
FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures"
WINDOWS = FIXTURES / "windows.jsonl"
SEQUENCE = FIXTURES / "sequence.fasta"
PARAMETERS = FIXTURES / "parameters.json"
SCHEMA = FIXTURES / "logical.schema.json"
RECEIPT = FIXTURES / "receipt.json"
SOURCE_INDEX = FIXTURES / "source-index.json"
sys.path.insert(0, str(PACKAGE_ROOT))

from dosa_v3 import __version__  # noqa: E402
from dosa_v3 import core  # noqa: E402
from dosa_v3.core import (  # noqa: E402
    MANIFEST_NAME,
    MANIFEST_VERSION,
    PACKAGE_VERSION,
    VerificationError,
    accession_bucket,
    verify_package,
)


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(ENTRYPOINT), *args],
        text=True,
        capture_output=True,
        check=False,
    )


def identity(path: pathlib.Path, root: pathlib.Path) -> dict[str, object]:
    return {
        "name": path.relative_to(root).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def make_manual_package(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    payload = root / "scale=window" / f"sha256_bucket={accession_bucket('NC_TEST.1')}" / "part-00000.parquet"
    schema = root / "bindings" / "schema" / "logical.schema.json"
    receipt = root / "bindings" / "receipt" / "receipt.json"
    source_index = root / "bindings" / "source_index" / "source-index.json"
    payload.parent.mkdir(parents=True)
    schema.parent.mkdir(parents=True)
    receipt.parent.mkdir(parents=True)
    source_index.parent.mkdir(parents=True)
    payload.write_bytes(b"parquet-fixture-bytes")
    schema.write_bytes(SCHEMA.read_bytes())
    receipt.write_bytes(RECEIPT.read_bytes())
    source_index.write_bytes(SOURCE_INDEX.read_bytes())
    payload_record = identity(payload, root)
    payload_record.update(
        {
            "scale": "window",
            "sha256_bucket": accession_bucket("NC_TEST.1"),
            "rows": 1,
            "compression": "zstd",
            "route_bounds": {
                "accession_min": "NC_TEST.1",
                "accession_max": "NC_TEST.1",
                "min_accession_coordinate_start": 0,
                "min_accession_coordinate_end": 100,
                "max_accession_coordinate_start": 0,
                "max_accession_coordinate_end": 100,
            },
        }
    )
    schema_record = identity(schema, root)
    schema_record["kind"] = "schema"
    receipt_record = identity(receipt, root)
    receipt_record["kind"] = "receipt"
    source_index_record = identity(source_index, root)
    source_index_record["kind"] = "source_index"
    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "package_version": PACKAGE_VERSION,
        "source": {"logical_bytes": WINDOWS.stat().st_size, "logical_sha256": hashlib.sha256(WINDOWS.read_bytes()).hexdigest()},
        "routing": {
            "accession_field": "sequence_accession_version",
            "coordinate_start_field": "window_start",
            "coordinate_end_field": "window_end",
            "bucket_derivation": "first_byte_sha256_accession_version_utf8",
            "rows_per_shard": 1,
            "max_rows_per_shard": 5_000_000,
            "max_bytes_per_shard": 5 * 1024 * 1024 * 1024,
        },
        "typed_schema": [],
        "bindings": [schema_record, receipt_record, source_index_record],
        "payloads": [payload_record],
        "scale_capacity": [
            {
                "scale": "window",
                "compression": "zstd",
                "rows": 1,
                "bytes": payload.stat().st_size,
                "shards": 1,
            }
        ],
    }
    (root / MANIFEST_NAME).write_text(json.dumps(manifest), encoding="utf-8")
    return payload, schema, receipt


def write_runner(path: pathlib.Path, mode: str = "pass") -> None:
    source = f"""#!/usr/bin/env python3
import hashlib,json,pathlib,sys
def value(flag):
    return sys.argv[sys.argv.index(flag)+1]
def all_values(flag):
    return [sys.argv[i+1] for i,x in enumerate(sys.argv) if x == flag]
sequence=pathlib.Path(value('--sequence'))
parameters=pathlib.Path(value('--parameters'))
atlas=[pathlib.Path(x) for x in all_values('--atlas-payload')]
envelope={{
  'envelope_version':'dosa-v3-u0-dev-calibration-result-1',
  'producer':{{'language':'Sounio','canonical':True,'runner_sha256':hashlib.sha256(pathlib.Path(sys.argv[0]).read_bytes()).hexdigest(),'attestation_sha256':value('--runner-attestation-sha256')}},
  'inputs':{{
    'accession_version':value('--accession-version'),
    'scale':value('--scale'),
    'sequence_bytes':sequence.stat().st_size,
    'sequence_sha256':hashlib.sha256(sequence.read_bytes()).hexdigest(),
    'parameters_bytes':parameters.stat().st_size,
    'parameters_sha256':hashlib.sha256(parameters.read_bytes()).hexdigest(),
  }},
  'atlas_payloads':sorted([{{'name':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}} for p in atlas],key=lambda x:x['name']),
  'comparison':{{'method':'canonical_sounio_atlas_strata_v1','status':'match'}},
}}
mode={mode!r}
if mode == 'wrong_sequence': envelope['inputs']['sequence_sha256']='0'*64
if mode == 'echo': envelope['atlas_strata']=[json.loads(x) for x in atlas[0].read_text().splitlines() if x]
print(json.dumps(envelope,separators=(',',':')))
"""
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)


def write_runner_attestation(runner: pathlib.Path, mode: str = "pass") -> pathlib.Path:
    receipt = runner.with_name("sounio-build-receipt.json")
    receipt.write_text('{"receipt":"fixture-build-only"}\n', encoding="utf-8")
    attestation = runner.with_name("sounio-runner-attestation.json")
    executable_sha256 = hashlib.sha256(runner.read_bytes()).hexdigest()
    if mode == "wrong_executable":
        executable_sha256 = "0" * 64
    document = {
        "attestation_version": "dosa-v3-sounio-runner-attestation-1",
        "evidence_scope": "fixture-only-non-semantic",
        "repository_url": "https://github.com/sounio-lang/sounio.git",
        "source_commit": "0123456789abcdef0123456789abcdef01234567",
        "source_sha256": hashlib.sha256(b"fixture-sounio-source").hexdigest(),
        "compiler_sha256": hashlib.sha256(b"fixture-sounio-compiler").hexdigest(),
        "executable_sha256": executable_sha256,
        "receipt_path": receipt.name,
        "receipt_sha256": hashlib.sha256(receipt.read_bytes()).hexdigest(),
    }
    attestation.write_text(json.dumps(document, sort_keys=True, separators=(",", ":")), encoding="utf-8")
    receipt.chmod(0o444)
    attestation.chmod(0o444)
    return attestation


CALIBRATION_ARGS = (
    "--sequence",
    str(SEQUENCE),
    "--accession-version",
    "NC_NEW.1",
    "--scale",
    "window",
    "--parameters",
    str(PARAMETERS),
    "--atlas-strata",
    str(WINDOWS),
)


class DosaV3Tests(unittest.TestCase):
    def test_package_is_explicitly_u0_development(self) -> None:
        self.assertEqual(PACKAGE_VERSION, "U0-dev")
        self.assertEqual(__version__, "U0-dev")
        completed = run_cli("version")
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(json.loads(completed.stdout)["package_version"], "U0-dev")

    def test_packager_has_no_python_source_materialization(self) -> None:
        self.assertFalse(hasattr(core, "_read_source_rows"))
        source = inspect.getsource(core.package_logical_output)
        self.assertNotIn("read_text(", source)
        self.assertNotIn("readlines(", source)
        self.assertNotIn("json.loads(", source)

    def test_schema_binding_accepts_nonempty_common_definitions(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            definitions = root / "common.schema.json"
            definitions.write_text(
                '{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs":{"id":{"type":"string"}}}',
                encoding="utf-8",
            )
            core._validate_binding_document(definitions, "schema")
            definitions.write_text(
                '{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs":{}}',
                encoding="utf-8",
            )
            with self.assertRaises(core.DosaError):
                core._validate_binding_document(definitions, "schema")

    def test_source_index_rejects_duplicate_accession_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            index = pathlib.Path(temp) / "duplicate-source-index.json"
            record = json.loads(SOURCE_INDEX.read_text(encoding="utf-8"))["records"]["NC_TEST.1"]
            index.write_text(
                '{"source_index_version":"dosa-v3-source-index-1","records":'
                + '{"NC_TEST.1":'
                + json.dumps(record)
                + ',"NC_TEST.1":'
                + json.dumps(record)
                + "}}",
                encoding="utf-8",
            )
            with self.assertRaises(core.DosaError) as caught:
                core._load_source_index(index)
            self.assertIn("valid UTF-8 JSON", str(caught.exception))

    def test_verify_detects_payload_hash_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            payload, _, _ = make_manual_package(root)
            payload.write_bytes(b"altered")
            with self.assertRaises(VerificationError):
                verify_package(root)

    def test_verify_fails_closed_without_schema_or_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            _, schema, receipt = make_manual_package(root)
            schema.unlink()
            receipt.unlink()
            with self.assertRaises(VerificationError) as caught:
                verify_package(root)
            self.assertIn("unavailable", str(caught.exception))

    def test_verify_rejects_extra_parquet_and_duplicate_names(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            payload, _, _ = make_manual_package(root)
            extra = payload.with_name("unmanifested.parquet")
            extra.write_bytes(b"extra")
            with self.assertRaises(VerificationError) as caught:
                verify_package(root)
            self.assertIn("unmanifested_payload", str(caught.exception))
            extra.unlink()
            manifest_path = root / MANIFEST_NAME
            manifest = json.loads(manifest_path.read_text())
            manifest["payloads"].append(dict(manifest["payloads"][0]))
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaises(VerificationError) as caught:
                verify_package(root)
            self.assertIn("duplicate_manifest_name", str(caught.exception))

    def test_verify_enforces_declared_row_and_byte_limits(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            make_manual_package(root)
            manifest_path = root / MANIFEST_NAME
            manifest = json.loads(manifest_path.read_text())
            manifest["payloads"][0]["rows"] = 5_000_001
            manifest["payloads"][0]["bytes"] = 5 * 1024 * 1024 * 1024 + 1
            manifest["scale_capacity"][0]["rows"] = 5_000_001
            manifest["scale_capacity"][0]["bytes"] = 5 * 1024 * 1024 * 1024 + 1
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaises(VerificationError) as caught:
                verify_package(root)
            self.assertIn("row_limit_exceeded_or_invalid", str(caught.exception))
            self.assertIn("byte_limit_exceeded_or_invalid", str(caught.exception))

    def test_calibrate_refuses_without_runner(self) -> None:
        completed = run_cli("calibrate", *CALIBRATION_ARGS)
        self.assertEqual(completed.returncode, 5)
        self.assertEqual(json.loads(completed.stdout)["code"], "DOSA_REFUSE")

    def test_calibrate_refuses_generic_python_runner_without_attestation(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            runner = pathlib.Path(temp) / "sounio-runner"
            write_runner(runner)
            completed = run_cli("calibrate", "--runner", str(runner), *CALIBRATION_ARGS)
            self.assertEqual(completed.returncode, 5, completed.stdout + completed.stderr)
            self.assertEqual(json.loads(completed.stdout)["code"], "DOSA_REFUSE")

    def test_calibrate_accepts_fixture_runner_only_with_external_hash_bound_attestation(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            runner = pathlib.Path(temp) / "sounio-runner"
            write_runner(runner)
            attestation = write_runner_attestation(runner)
            completed = run_cli(
                "calibrate", "--runner", str(runner), "--runner-attestation", str(attestation), *CALIBRATION_ARGS
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            body = json.loads(completed.stdout)
            self.assertEqual(body["canonical_producer"], "Sounio")
            self.assertEqual(body["runner_attestation_sha256"], hashlib.sha256(attestation.read_bytes()).hexdigest())
            self.assertEqual(body["runner_attestation_evidence_scope"], "fixture-only-non-semantic")
            self.assertEqual(body["provenance_boundary"], "build_provenance_only_not_calibration_semantics")
            self.assertEqual(body["inputs"]["accession_version"], "NC_NEW.1")
            self.assertEqual(body["inputs"]["sequence_sha256"], hashlib.sha256(SEQUENCE.read_bytes()).hexdigest())
            self.assertNotIn("atlas_strata", body)

    def test_calibrate_rejects_atlas_echo_or_wrong_input_binding(self) -> None:
        for mode in ("echo", "wrong_sequence"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                runner = pathlib.Path(temp) / "sounio-runner"
                write_runner(runner, mode)
                attestation = write_runner_attestation(runner)
                completed = run_cli(
                    "calibrate", "--runner", str(runner), "--runner-attestation", str(attestation), *CALIBRATION_ARGS
                )
                self.assertEqual(completed.returncode, 6, completed.stdout + completed.stderr)
                self.assertEqual(json.loads(completed.stdout)["code"], "DOSA_CALIBRATION_FAILED")

    def test_calibrate_refuses_mismatched_runner_attestation(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            runner = pathlib.Path(temp) / "sounio-runner"
            write_runner(runner)
            attestation = write_runner_attestation(runner, "wrong_executable")
            completed = run_cli(
                "calibrate", "--runner", str(runner), "--runner-attestation", str(attestation), *CALIBRATION_ARGS
            )
            self.assertEqual(completed.returncode, 5, completed.stdout + completed.stderr)
            self.assertEqual(json.loads(completed.stdout)["code"], "DOSA_REFUSE")

    def test_package_dependency_is_explicit_when_duckdb_missing(self) -> None:
        try:
            import duckdb  # type: ignore # noqa: F401
        except ModuleNotFoundError:
            with tempfile.TemporaryDirectory() as temp:
                completed = run_cli(
                    "package",
                    "--input",
                    str(WINDOWS),
                    "--output",
                    str(pathlib.Path(temp) / "out"),
                    "--scale",
                    "window",
                    "--source-index",
                    str(SOURCE_INDEX),
                    "--schema",
                    str(SCHEMA),
                    "--receipt",
                    str(RECEIPT),
                )
            self.assertEqual(completed.returncode, 2)
            self.assertEqual(json.loads(completed.stdout)["code"], "DOSA_DEPENDENCY_MISSING")
        else:
            self.skipTest("DuckDB is available; exercised by integration test")


try:
    import duckdb  # type: ignore # noqa: F401
except ModuleNotFoundError:
    DUCKDB_AVAILABLE = False
else:
    DUCKDB_AVAILABLE = True


@unittest.skipUnless(DUCKDB_AVAILABLE, "DuckDB integration requires the optional duckdb Python package")
class DuckDbIntegrationTests(unittest.TestCase):
    def test_package_rejects_source_index_missing_input_accession(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            index = root / "source-index.json"
            document = json.loads(SOURCE_INDEX.read_text(encoding="utf-8"))
            del document["records"]["NC_OTHER.1"]
            index.write_text(json.dumps(document), encoding="utf-8")
            completed = run_cli(
                "package",
                "--input", str(WINDOWS), "--output", str(root / "package"), "--scale", "window",
                "--source-index", str(index), "--schema", str(SCHEMA), "--receipt", str(RECEIPT),
            )
            self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
            self.assertIn("source index lacks logical input accession.version", completed.stdout)

    def test_multi_shard_package_query_and_external_verify(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            package = pathlib.Path(temp) / "package"
            packaged = run_cli(
                "package",
                "--input",
                str(WINDOWS),
                "--output",
                str(package),
                "--scale",
                "window",
                "--source-index",
                str(SOURCE_INDEX),
                "--rows-per-shard",
                "1",
                "--schema",
                str(SCHEMA),
                "--receipt",
                str(RECEIPT),
            )
            self.assertEqual(packaged.returncode, 0, packaged.stdout + packaged.stderr)
            package_result = json.loads(packaged.stdout)
            self.assertEqual(package_result["payloads"], 3)
            manifest = json.loads((package / MANIFEST_NAME).read_text())
            self.assertEqual(len(manifest["payloads"]), 3)
            self.assertEqual(manifest["scale_capacity"][0]["rows"], 3)
            self.assertEqual(
                manifest["scale_capacity"][0]["bytes"],
                sum(payload["bytes"] for payload in manifest["payloads"]),
            )
            for payload in manifest["payloads"]:
                self.assertIn(f"sha256_bucket={payload['sha256_bucket']}", payload["name"])
                self.assertEqual(payload["compression"], "zstd")
                self.assertLessEqual(payload["rows"], 5_000_000)
                self.assertLessEqual(payload["bytes"], 5 * 1024 * 1024 * 1024)
            for binding in manifest["bindings"]:
                self.assertFalse(pathlib.PurePosixPath(binding["name"]).is_absolute())
                self.assertTrue((package / binding["name"]).is_file())
                self.assertNotIn("path", binding)
            source_index_binding = next(binding for binding in manifest["bindings"] if binding["kind"] == "source_index")
            self.assertEqual(source_index_binding["sha256"], hashlib.sha256(SOURCE_INDEX.read_bytes()).hexdigest())
            verified = run_cli("verify", "--package", str(package))
            self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)
            result = run_cli(
                "query",
                "--package",
                str(package),
                "--accession-version",
                "NC_TEST.1",
                "--coordinate",
                "50:150",
                "--scale",
                "window",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            body = json.loads(result.stdout)
            self.assertEqual(body["query"]["accession_sha256_bucket"], accession_bucket("NC_TEST.1"))
            self.assertEqual(len(body["records"]), 2)
            self.assertEqual(len(body["shards_read"]), 2)
            self.assertTrue(all(f"sha256_bucket={accession_bucket('NC_TEST.1')}" in name for name in body["shards_read"]))
            self.assertNotIn("input_sha256", body["records"][0])
            self.assertEqual(body["source_index_sha256"], source_index_binding["sha256"])
            self.assertEqual(body["source_record"], json.loads(SOURCE_INDEX.read_text())["records"]["NC_TEST.1"])
            (package / source_index_binding["name"]).write_bytes(b" " * source_index_binding["bytes"])
            tampered_index = run_cli("verify", "--package", str(package))
            self.assertEqual(tampered_index.returncode, 3)
            self.assertIn("sha256_mismatch", tampered_index.stdout)
            (package / source_index_binding["name"]).write_bytes(SOURCE_INDEX.read_bytes())
            manifest["payloads"][0]["rows"] += 1
            manifest["scale_capacity"][0]["rows"] += 1
            (package / MANIFEST_NAME).write_text(json.dumps(manifest), encoding="utf-8")
            mismatched = run_cli("verify", "--package", str(package))
            self.assertEqual(mismatched.returncode, 3)
            self.assertIn("parquet_row_count_mismatch", mismatched.stdout)


if __name__ == "__main__":
    unittest.main()
