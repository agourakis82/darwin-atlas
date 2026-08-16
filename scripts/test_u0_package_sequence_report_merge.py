#!/usr/bin/env python3
"""Offline regression for deterministic U0 package sequence-report merge."""
from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
MERGE = ROOT / "scripts" / "merge_u0_package_sequence_reports.py"


def write_jsonl(path: pathlib.Path, values: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n" for value in values),
        encoding="utf-8",
        newline="\n",
    )


def invoke(data_root: pathlib.Path, assembly_report: pathlib.Path, output: pathlib.Path, receipt: pathlib.Path, extra: list[str] | None = None) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(MERGE),
        "--data-root",
        str(data_root),
        "--assembly-report",
        str(assembly_report),
        "--output",
        str(output),
        "--receipt",
        str(receipt),
    ]
    if extra:
        command.extend(extra)
    return subprocess.run(command, capture_output=True, text=True, check=False)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="dosa-u0-seq-merge-test.", dir="/private/tmp") as temporary_name:
        temporary = pathlib.Path(temporary_name)
        data_root = temporary / "ncbi_dataset" / "data"
        assembly_report = data_root / "assembly_data_report.jsonl"
        write_jsonl(
            assembly_report,
            [
                {"accession": "GCF_000000002.1", "currentAccession": "GCF_000000002.1"},
                {"accession": "GCF_000000001.1"},
            ],
        )
        write_jsonl(
            data_root / "GCF_000000001.1" / "sequence_report.jsonl",
            [
                {
                    "assemblyAccession": "GCF_000000001.1",
                    "assignedMoleculeLocationType": "Chromosome",
                    "chrName": "chromosome",
                    "length": 2314078,
                    "refseqAccession": "NC_000001.1",
                    "sequenceName": "chromosome",
                }
            ],
        )
        write_jsonl(
            data_root / "GCF_000000002.1" / "sequence_report.jsonl",
            [
                {
                    "assembly_accession": "GCF_000000002.1",
                    "assigned_molecule_location_type": "Plasmid",
                    "chr_name": "plasmid",
                    "length": 800,
                    "refseq_accession": "NC_000002.1",
                    "sequence_name": "plasmid pFixture",
                },
                {
                    "assembly_accession": "GCF_000000002.1",
                    "assigned_molecule_location_type": "Chromosome",
                    "chr_name": "chromosome",
                    "length": 1000,
                    "refseq_accession": "NC_000003.1",
                    "sequence_name": "chromosome",
                },
            ],
        )
        (data_root / "dataset_catalog.json").write_text("{}\n", encoding="utf-8", newline="\n")

        output = temporary / "sequence_data_report.jsonl"
        receipt_path = temporary / "merge_receipt.json"
        first = invoke(data_root, assembly_report, output, receipt_path, ["--expected-assembly-count", "2"])
        if first.returncode != 0:
            raise RuntimeError(first.stderr or first.stdout)
        merged = output.read_bytes()
        if b"\r" in merged or not merged.endswith(b"\n"):
            raise RuntimeError("merged report is not LF-only")
        # GCF directories are sorted, so 000000001 precedes 000000002 even though
        # the assembly report listed 000000002 first.
        rows = [json.loads(line) for line in merged.decode("utf-8").splitlines()]
        if [row.get("refseqAccession") or row.get("refseq_accession") for row in rows] != [
            "NC_000001.1",
            "NC_000002.1",
            "NC_000003.1",
        ]:
            raise RuntimeError(f"merge order drifted: {rows}")
        receipt = json.loads(receipt_path.read_text(encoding="ascii"))
        if (
            receipt.get("status") != "merged"
            or receipt.get("scientific_metrics_computed") is not False
            or receipt.get("assembly_count") != 2
            or receipt.get("sequence_count") != 3
            or receipt.get("sequence_report_bytes") != len(merged)
            or receipt.get("sequence_report_sha256") != hashlib.sha256(merged).hexdigest()
        ):
            raise RuntimeError(f"merge receipt drifted: {receipt}")

        overwrite = invoke(data_root, assembly_report, output, temporary / "other.json")
        if overwrite.returncode != 11 or "refusing to overwrite" not in overwrite.stderr:
            raise RuntimeError("overwrite was not refused")

        count_drift = invoke(
            data_root,
            assembly_report,
            temporary / "count.jsonl",
            temporary / "count.json",
            ["--expected-assembly-count", "3"],
        )
        if count_drift.returncode != 11 or "expected 3" not in count_drift.stderr:
            raise RuntimeError("expected assembly count drift was not refused")

        cr_dir = temporary / "cr" / "ncbi_dataset" / "data"
        write_jsonl(cr_dir / "assembly_data_report.jsonl", [{"accession": "GCF_000000001.1"}])
        cr_report = cr_dir / "GCF_000000001.1" / "sequence_report.jsonl"
        cr_report.parent.mkdir(parents=True)
        cr_report.write_bytes(b'{"assemblyAccession":"GCF_000000001.1","length":8,"refseqAccession":"NC_000001.1"}\r\n')
        cr = invoke(cr_dir, cr_dir / "assembly_data_report.jsonl", temporary / "cr.jsonl", temporary / "cr.json")
        if cr.returncode != 11 or "LF-only" not in cr.stderr:
            raise RuntimeError("CR rejection failed")

        dup_dir = temporary / "dup" / "ncbi_dataset" / "data"
        write_jsonl(dup_dir / "assembly_data_report.jsonl", [{"accession": "GCF_000000001.1"}])
        write_jsonl(
            dup_dir / "GCF_000000001.1" / "sequence_report.jsonl",
            [
                {"assemblyAccession": "GCF_000000001.1", "length": 8, "refseqAccession": "NC_000001.1"},
                {"assemblyAccession": "GCF_000000001.1", "length": 8, "refseqAccession": "NC_000001.1"},
            ],
        )
        dup = invoke(dup_dir, dup_dir / "assembly_data_report.jsonl", temporary / "dup.jsonl", temporary / "dup.json")
        if dup.returncode != 11 or "duplicate sequence identity" not in dup.stderr:
            raise RuntimeError("duplicate identity was not refused")

        missing_dir = temporary / "missing" / "ncbi_dataset" / "data"
        write_jsonl(
            missing_dir / "assembly_data_report.jsonl",
            [{"accession": "GCF_000000001.1"}, {"accession": "GCF_000000002.1"}],
        )
        write_jsonl(
            missing_dir / "GCF_000000001.1" / "sequence_report.jsonl",
            [{"assemblyAccession": "GCF_000000001.1", "length": 8, "refseqAccession": "NC_000001.1"}],
        )
        missing = invoke(
            missing_dir,
            missing_dir / "assembly_data_report.jsonl",
            temporary / "missing.jsonl",
            temporary / "missing.json",
        )
        if missing.returncode != 11 or "missing=" not in missing.stderr:
            raise RuntimeError("incomplete coverage was not refused")

        key_dir = temporary / "key" / "ncbi_dataset" / "data"
        write_jsonl(key_dir / "assembly_data_report.jsonl", [{"accession": "GCF_000000001.1"}])
        key_report = key_dir / "GCF_000000001.1" / "sequence_report.jsonl"
        key_report.parent.mkdir(parents=True)
        key_report.write_text(
            '{"assemblyAccession":"GCF_000000001.1","assemblyAccession":"GCF_000000001.1","length":8,"refseqAccession":"NC_000001.1"}\n',
            encoding="utf-8",
            newline="\n",
        )
        keys = invoke(key_dir, key_dir / "assembly_data_report.jsonl", temporary / "key.jsonl", temporary / "key.json")
        if keys.returncode != 11 or "duplicate JSON key" not in keys.stderr:
            raise RuntimeError("duplicate JSON key was not refused")

    print("U0_SEQUENCE_REPORT_MERGE_FIXTURE_PASS assemblies=2 sequences=3 camelcase=1 snakecase=1 invalid_cases=5")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
