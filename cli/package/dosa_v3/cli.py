"""JSON-only command line interface for DOSA v3."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

from . import __version__
from .core import DosaError, PackageOptions, calibrate, package_logical_output, query_package, verify_package


class JsonArgumentParser(argparse.ArgumentParser):
    """Keep invalid invocations on the same machine-readable error contract."""

    def error(self, message: str) -> None:
        raise DosaError(message)


def _coordinate(value: str) -> tuple[int, int]:
    try:
        start, end = value.split(":", 1)
        return int(start), int(end)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("coordinate must be start:end") from exc


def build_parser() -> argparse.ArgumentParser:
    parser = JsonArgumentParser(prog="dosa", description="DOSA v3 local Parquet boundary")
    parser.add_argument("--json", action="store_true", help="JSON is always emitted; retained for script compatibility")
    commands = parser.add_subparsers(dest="command", required=True)
    package = commands.add_parser("package", help="package canonical JSONL/TSV into typed Parquet")
    package.add_argument("--input", required=True, type=pathlib.Path)
    package.add_argument("--output", required=True, type=pathlib.Path)
    package.add_argument("--scale", required=True)
    package.add_argument("--source-index", required=True, type=pathlib.Path)
    package.add_argument("--input-format", choices=("auto", "jsonl", "tsv"), default="auto")
    package.add_argument("--accession-field", default="sequence_accession_version")
    package.add_argument("--coordinate-start-field", default="window_start")
    package.add_argument("--coordinate-end-field", default="window_end")
    package.add_argument("--rows-per-shard", type=int, default=5_000_000)
    package.add_argument("--schema", action="append", required=True, type=pathlib.Path)
    package.add_argument("--receipt", action="append", required=True, type=pathlib.Path)
    query = commands.add_parser("query", help="route and query only matching Parquet shard(s)")
    query.add_argument("--package", required=True, type=pathlib.Path)
    query.add_argument("--accession-version", required=True)
    query.add_argument("--coordinate", required=True, type=_coordinate)
    query.add_argument("--scale", required=True)
    verify = commands.add_parser("verify", help="verify payload manifest names, bytes, and SHA-256")
    verify.add_argument("--package", required=True, type=pathlib.Path)
    calibration = commands.add_parser("calibrate", help="delegate calibration to canonical Sounio")
    calibration.add_argument("--runner")
    calibration.add_argument("--runner-attestation", type=pathlib.Path)
    calibration.add_argument("--sequence", required=True, type=pathlib.Path)
    calibration.add_argument("--accession-version", required=True)
    calibration.add_argument("--scale", required=True)
    calibration.add_argument("--parameters", required=True, type=pathlib.Path)
    calibration.add_argument("--atlas-strata", action="append", required=True, type=pathlib.Path)
    commands.add_parser("version", help="report the U0 development package version")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
        if args.command == "package":
            result = package_logical_output(
                PackageOptions(
                    source=args.input,
                    output=args.output,
                    scale=args.scale,
                    source_index=args.source_index,
                    input_format=args.input_format,
                    accession_field=args.accession_field,
                    coordinate_start_field=args.coordinate_start_field,
                    coordinate_end_field=args.coordinate_end_field,
                    rows_per_shard=args.rows_per_shard,
                    schemas=tuple(args.schema),
                    receipts=tuple(args.receipt),
                )
            )
        elif args.command == "query":
            result = query_package(args.package, args.accession_version, args.coordinate[0], args.coordinate[1], args.scale)
        elif args.command == "verify":
            result = verify_package(args.package)
        elif args.command == "calibrate":
            result = calibrate(
                args.runner,
                args.runner_attestation,
                args.sequence,
                args.accession_version,
                args.scale,
                args.parameters,
                tuple(args.atlas_strata),
            )
        else:
            result = {"status": "ok", "package_version": __version__}
        print(json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str))
        return 0
    except DosaError as exc:
        print(json.dumps({"status": "error", "code": exc.code, "message": str(exc)}, sort_keys=True, separators=(",", ":")), file=sys.stdout)
        return exc.exit_code
    except Exception as exc:
        print(
            json.dumps(
                {"status": "error", "code": "DOSA_INTERNAL_ERROR", "message": str(exc)},
                sort_keys=True,
                separators=(",", ":"),
            ),
            file=sys.stdout,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
