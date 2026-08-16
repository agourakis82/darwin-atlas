#!/usr/bin/env python3
"""Offline regression for pre-download U0 selected-package byte estimates."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
ESTIMATE = ROOT / "scripts" / "estimate_u0_selected_download.py"


def write_jsonl(path: pathlib.Path, values: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n" for value in values),
        encoding="utf-8",
        newline="\n",
    )


def write_json(path: pathlib.Path, value: object) -> None:
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8", newline="\n")


def invoke(selection: pathlib.Path, catalog: pathlib.Path, output: pathlib.Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(ESTIMATE),
            "--selection",
            str(selection),
            "--catalog",
            str(catalog),
            "--output",
            str(output),
        ],
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="dosa-u0-download-estimate-test.", dir="/private/tmp") as temporary_name:
        temporary = pathlib.Path(temporary_name)
        selection = temporary / "u0_pilot_selection.jsonl"
        write_jsonl(
            selection,
            [
                {"assembly_accession_version": "GCF_000000002.1", "sequence_accession_version": "NC_000002.1"},
                {"assembly_accession_version": "GCF_000000001.1", "sequence_accession_version": "NC_000001.1"},
                {"assembly_accession_version": "GCF_000000001.1", "sequence_accession_version": "NC_000003.1"},
            ],
        )
        catalog = temporary / "dataset_catalog.json"
        write_json(
            catalog,
            {
                "apiVersion": "V2",
                "assemblies": [
                    {"files": [{"filePath": "assembly_data_report.jsonl", "fileType": "DATA_REPORT"}]},
                    {
                        "accession": "GCF_000000001.1",
                        "files": [
                            {"filePath": "GCF_000000001.1/genomic.gbff", "fileType": "GENBANK_FLAT_FILE", "uncompressedLengthBytes": "100"},
                            {"filePath": "GCF_000000001.1/GCF_000000001.1_cds_from_genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "99999"},
                            {"filePath": "GCF_000000001.1/genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": 20},
                            {"filePath": "GCF_000000001.1/GCF_000000001.1_rna_from_genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "88888"},
                            {"filePath": "GCF_000000001.1/sequence_report.jsonl", "fileType": "SEQUENCE_REPORT"},
                        ],
                    },
                    {
                        "accession": "GCF_000000002.1",
                        "files": [
                            {"filePath": "GCF_000000002.1/genomic.gbff", "fileType": "GENBANK_FLAT_FILE", "uncompressedLengthBytes": "5"},
                            {"filePath": "GCF_000000002.1/genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "7"},
                            {"filePath": "GCF_000000002.1/sequence_report.jsonl", "fileType": "SEQUENCE_REPORT"},
                        ],
                    },
                    {
                        "accession": "GCF_000000099.1",
                        "files": [
                            {"filePath": "GCF_000000099.1/genomic.gbff", "fileType": "GENBANK_FLAT_FILE", "uncompressedLengthBytes": "1"},
                            {"filePath": "GCF_000000099.1/a_cds_from_genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "9"},
                            {"filePath": "GCF_000000099.1/a_genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "8"},
                            {"filePath": "GCF_000000099.1/a_rna_from_genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "7"},
                            {"filePath": "GCF_000000099.1/sequence_report.jsonl", "fileType": "SEQUENCE_REPORT"},
                        ],
                    },
                ],
            },
        )
        output = temporary / "estimate.json"
        first = invoke(selection, catalog, output)
        if first.returncode != 0:
            raise RuntimeError(first.stderr or first.stdout)
        receipt = json.loads(output.read_text(encoding="ascii"))
        if (
            receipt.get("status") != "estimated"
            or receipt.get("scientific_metrics_computed") is not False
            or receipt.get("selected_assemblies") != 2
            or receipt.get("selected_replicons") != 3
            or receipt.get("fasta_uncompressed_bytes") != 27
            or receipt.get("gbff_uncompressed_bytes") != 105
            or receipt.get("sequence_report_uncompressed_bytes") != 0
            or receipt.get("sequence_report_sizes_missing") != 2
            or receipt.get("estimated_uncompressed_bytes") != 132
            or receipt.get("within_policy") is not True
        ):
            raise RuntimeError(f"estimate receipt drifted: {receipt}")

        overwrite = invoke(selection, catalog, output)
        if overwrite.returncode != 11 or "refusing to overwrite" not in overwrite.stderr:
            raise RuntimeError("overwrite was not refused")

        missing_size = temporary / "missing-size.json"
        write_json(
            missing_size,
            {
                "assemblies": [
                    {
                        "accession": "GCF_000000001.1",
                        "files": [
                            {"filePath": "GCF_000000001.1/genomic.gbff", "fileType": "GENBANK_FLAT_FILE"},
                            {"filePath": "GCF_000000001.1/genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "20"},
                            {"filePath": "GCF_000000001.1/sequence_report.jsonl", "fileType": "SEQUENCE_REPORT"},
                        ],
                    },
                    {
                        "accession": "GCF_000000002.1",
                        "files": [
                            {"filePath": "GCF_000000002.1/genomic.gbff", "fileType": "GENBANK_FLAT_FILE", "uncompressedLengthBytes": "5"},
                            {"filePath": "GCF_000000002.1/genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "7"},
                            {"filePath": "GCF_000000002.1/sequence_report.jsonl", "fileType": "SEQUENCE_REPORT"},
                        ],
                    },
                ]
            },
        )
        no_size = invoke(selection, missing_size, temporary / "no-size.json")
        if no_size.returncode != 11 or "no uncompressedLengthBytes" not in no_size.stderr:
            raise RuntimeError("missing FASTA/GBFF size was not refused")

        absent = temporary / "absent.json"
        write_json(
            absent,
            {
                "assemblies": [
                    {
                        "accession": "GCF_000000001.1",
                        "files": [
                            {"filePath": "GCF_000000001.1/genomic.gbff", "fileType": "GENBANK_FLAT_FILE", "uncompressedLengthBytes": "1"},
                            {"filePath": "GCF_000000001.1/genomic.fna", "fileType": "GENOMIC_NUCLEOTIDE_FASTA", "uncompressedLengthBytes": "1"},
                            {"filePath": "GCF_000000001.1/sequence_report.jsonl", "fileType": "SEQUENCE_REPORT"},
                        ],
                    }
                ]
            },
        )
        missing_assembly = invoke(selection, absent, temporary / "missing-assembly.json")
        if missing_assembly.returncode != 11 or "catalog missing selected assemblies" not in missing_assembly.stderr:
            raise RuntimeError("missing selected assembly was not refused")

    print("U0_SELECTED_DOWNLOAD_ESTIMATE_FIXTURE_PASS assemblies=2 replicons=3 bytes=132 invalid_cases=2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
