#!/usr/bin/env python3
"""Bind one U0 manifest row and FASTA to the strict Sounio case ledger."""

from __future__ import annotations

import argparse
import csv
import hashlib
import pathlib
import re
import sys


HEADER = (
    "u0_manifest_version", "work_unit_id", "assembly_accession_version",
    "sequence_accession_version", "replicon_class", "source_locator",
    "source_file_sha256", "sequence_sha256", "sequence_length",
    "declared_alphabet", "parameters_sha256", "scale", "stride", "k_min",
    "k_max", "null_model", "null_replicates",
)
CASE_HEADER = (
    "case_id", "parameters_sha256", "accession_version", "window_start",
    "scale", "seed64", "bases", "replicates",
)
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
ACCESSION_RE = re.compile(r"^[A-Z]{1,8}_[0-9]+\.[0-9]+$")


class BindingError(RuntimeError):
    pass


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def reject_symlink_components(path: pathlib.Path, label: str) -> None:
    absolute = path.absolute()
    current = pathlib.Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current = current / part
        if current.is_symlink():
            raise BindingError(f"{label} path may not contain symlinks")


def safe_source(root: pathlib.Path, locator: str) -> pathlib.Path:
    relative = pathlib.PurePosixPath(locator)
    if relative.is_absolute() or not relative.parts or any(part in ("", ".", "..") for part in relative.parts):
        raise BindingError("source_locator must be a safe relative POSIX path")
    reject_symlink_components(root, "source root")
    if root.is_symlink() or not root.is_dir():
        raise BindingError("source root must be a real directory")
    root = root.resolve(strict=True)
    candidate = root.joinpath(*relative.parts)
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise BindingError("source path may not contain symlinks")
    resolved = candidate.resolve(strict=True)
    if resolved.parent != root and root not in resolved.parents:
        raise BindingError("source path escapes root")
    if not resolved.is_file() or resolved.is_symlink():
        raise BindingError("source FASTA must be a regular non-symlink file")
    return resolved


def parse_fasta(path: pathlib.Path, accession: str) -> tuple[bytes, str]:
    raw = path.read_bytes()
    if not raw.endswith(b"\n") or b"\r" in raw or b"\x00" in raw:
        raise BindingError("FASTA must be LF-only ASCII with terminal LF")
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeDecodeError as exc:
        raise BindingError("FASTA must be ASCII") from exc
    if len(lines) < 2 or lines[0] != f">{accession}" or any(line.startswith(">") for line in lines[1:]):
        raise BindingError("FASTA must contain exactly the declared accession")
    sequence = "".join(lines[1:]).upper()
    if not sequence or re.fullmatch(r"[ACGT]+", sequence) is None:
        raise BindingError("fixture FASTA must contain only A/C/G/T")
    return raw, sequence


def build(parameters: pathlib.Path, manifest: pathlib.Path, source_root: pathlib.Path,
          output: pathlib.Path) -> None:
    for path, label in ((parameters, "parameters"), (manifest, "manifest")):
        reject_symlink_components(path, label)
        if path.is_symlink() or not path.is_file():
            raise BindingError(f"{label} must be a regular non-symlink file")
    if output.exists() or output.is_symlink():
        raise BindingError("output already exists")
    if output.parent.is_symlink() or not output.parent.is_dir():
        raise BindingError("output parent must already be a real directory")
    parameter_sha = sha256_bytes(parameters.read_bytes())
    if parameter_sha != "68343e046af24a997195eb2583532d3172234b0b9713f2e4296b9b12300bef94":
        raise BindingError("canonical U0 parameter bytes drifted")
    raw_manifest = manifest.read_bytes()
    if not raw_manifest.endswith(b"\n") or b"\r" in raw_manifest:
        raise BindingError("manifest must be LF-only with terminal LF")
    with manifest.open(encoding="ascii", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != HEADER:
            raise BindingError("manifest header drift")
        rows = list(reader)
    if len(rows) != 1 or set(rows[0]) != set(HEADER) or any(rows[0][field] is None for field in HEADER):
        raise BindingError("fixture requires exactly one complete work unit")
    row = rows[0]
    accession = row["sequence_accession_version"]
    if ACCESSION_RE.fullmatch(accession) is None:
        raise BindingError("invalid accession.version")
    expected_literals = {
        "u0_manifest_version": "1.0.0", "work_unit_id": f"{accession}@16",
        "assembly_accession_version": "GCF_000000001.1",
        "sequence_accession_version": "NC_000001.1",
        "replicon_class": "chromosome", "declared_alphabet": "acgt",
        "source_locator": "fasta/NC_000001.1.fa",
        "parameters_sha256": parameter_sha, "scale": "16", "stride": "16",
        "k_min": "1", "k_max": "8", "null_model": "euler_wilson_fixed_endpoints_v1",
        "null_replicates": "1000",
    }
    for field, expected in expected_literals.items():
        if row[field] != expected:
            raise BindingError(f"manifest {field} drift")
    if SHA_RE.fullmatch(row["source_file_sha256"]) is None or SHA_RE.fullmatch(row["sequence_sha256"]) is None:
        raise BindingError("manifest SHA-256 field malformed")
    fasta = safe_source(source_root, row["source_locator"])
    raw_fasta, sequence = parse_fasta(fasta, accession)
    if sha256_bytes(raw_fasta) != row["source_file_sha256"]:
        raise BindingError("raw FASTA SHA-256 mismatch")
    if sha256_bytes(sequence.encode("ascii")) != row["sequence_sha256"]:
        raise BindingError("normalized sequence SHA-256 mismatch")
    if int(row["sequence_length"]) != len(sequence) or len(sequence) != 16:
        raise BindingError("sequence length mismatch")
    seed = hashlib.sha256(f"{parameter_sha}:{accession}:0".encode("ascii")).hexdigest()[:16]
    case = (
        accession.replace(".", "_") + "_16_0", parameter_sha, accession, "0",
        "16", seed, sequence, "1000",
    )
    output.write_bytes(("\t".join(CASE_HEADER) + "\n" + "\t".join(case) + "\n").encode("ascii"))
    print(f"U0_WORK_UNIT_CASE_BINDING_PASS work_units=1 windows=1 scale=16 seed64={seed}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parameters", type=pathlib.Path, required=True)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        build(args.parameters, args.manifest, args.source_root, args.output)
        return 0
    except (OSError, ValueError, BindingError) as exc:
        print(f"U0_WORK_UNIT_CASE_BINDING_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
