#!/usr/bin/env python3
"""Offline regression for resumable U0 sequence-report discovery."""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
DISCOVERY = ROOT / "scripts" / "discover_u0_sequence_reports.py"


def write_jsonl(path: pathlib.Path, values: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n" for value in values),
        encoding="utf-8",
        newline="\n",
    )


def invoke(
    assembly_report: pathlib.Path,
    tool: pathlib.Path,
    lock: pathlib.Path,
    output: pathlib.Path,
    batch_size: int,
    environment: dict[str, str],
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(DISCOVERY),
            "--assembly-report",
            str(assembly_report),
            "--datasets-bin",
            str(tool),
            "--tool-lock",
            str(lock),
            "--output-directory",
            str(output),
            "--batch-size",
            str(batch_size),
            "--workers",
            "2",
        ],
        capture_output=True,
        text=True,
        env=environment,
        check=False,
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="dosa-u0-discovery-test.", dir="/private/tmp") as temporary_name:
        temporary = pathlib.Path(temporary_name)
        assembly_report = temporary / "assembly_data_report.jsonl"
        assemblies = ["GCF_000000001.1", "GCF_000000002.1", "GCF_000000003.1"]
        write_jsonl(assembly_report, [{"accession": value} for value in assemblies])

        mock = temporary / "datasets"
        mock.write_text(
            """#!/usr/bin/env python3
import json, os, pathlib, sys
if sys.argv[1:] == ["version"]:
    print("datasets version: 18.35.0")
    raise SystemExit(0)
if sys.argv[1:4] != ["summary", "genome", "accession"]:
    raise SystemExit(9)
source = pathlib.Path(sys.argv[sys.argv.index("--inputfile") + 1])
assemblies = source.read_text(encoding="ascii").splitlines()
marker = pathlib.Path(os.environ["MOCK_DISCOVERY_STATE"]) / (source.stem + ".attempted")
if assemblies[0] == "GCF_000000001.1" and not marker.exists():
    marker.write_text("transient\\n", encoding="ascii")
    print("mock transient transport failure", file=sys.stderr)
    raise SystemExit(7)
for index, assembly in enumerate(assemblies):
    serial = int(assembly.split("_")[1].split(".")[0])
    print(json.dumps({
        "assembly_accession": assembly,
        "assigned_molecule_location_type": "Chromosome",
        "length": 1000 + serial,
        "refseq_accession": f"NC_{serial:06d}.1",
    }, sort_keys=True, separators=(",", ":")))
    if serial == 1:
        print(json.dumps({
            "assembly_accession": assembly,
            "assigned_molecule_location_type": "Plasmid",
            "length": 101,
            "refseq_accession": "NC_900001.1",
        }, sort_keys=True, separators=(",", ":")))
""",
            encoding="utf-8",
            newline="\n",
        )
        mock.chmod(0o755)
        tool_sha = hashlib.sha256(mock.read_bytes()).hexdigest()
        lock = temporary / "lock.json"
        lock.write_text(
            json.dumps(
                {"datasets": {"version": "18.35.0", "sha256": tool_sha}},
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
            newline="\n",
        )
        output = temporary / "output"
        environment = dict(os.environ)
        environment["MOCK_DISCOVERY_STATE"] = str(temporary)

        first = invoke(assembly_report, mock, lock, output, 2, environment)
        if first.returncode != 0:
            raise RuntimeError(first.stderr or first.stdout)
        if "attempt=2" not in first.stdout or "sequences=4" not in first.stdout:
            raise RuntimeError(f"retry/closure marker absent: {first.stdout}")
        receipt = json.loads((output / "sequence_report_discovery_receipt.json").read_text(encoding="ascii"))
        if (
            receipt.get("status") != "PASS"
            or receipt.get("scientific_metrics_computed") is not False
            or receipt.get("assembly_count") != 3
            or receipt.get("sequence_count") != 4
        ):
            raise RuntimeError("discovery receipt drift")

        resumed = invoke(assembly_report, mock, lock, output, 2, environment)
        if resumed.returncode != 0 or resumed.stdout.count("attempt=0") != 2:
            raise RuntimeError("validated resume did not reuse both batches")

        drift = invoke(assembly_report, mock, lock, output, 3, environment)
        if drift.returncode != 11 or "existing discovery state differs" not in drift.stderr:
            raise RuntimeError("state drift was not refused")

        report = output / "reports" / "sequence-00000.jsonl"
        report.write_bytes(report.read_bytes().replace(b"NC_000001.1", b"bad_000001.1", 1))
        tampered = invoke(assembly_report, mock, lock, output, 2, environment)
        if tampered.returncode != 11 or "invalid sequence accession" not in tampered.stderr:
            raise RuntimeError("existing report tamper was not refused")

    print("U0_SEQUENCE_REPORT_DISCOVERY_FIXTURE_PASS batches=2 assemblies=3 sequences=4 retry=1 resume=1 invalid_cases=2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
