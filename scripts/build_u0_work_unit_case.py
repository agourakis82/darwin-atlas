#!/usr/bin/env python3
"""Bind one selected U0 manifest row and FASTA to a strict Sounio case shard."""

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
    "case_id", "run_id", "parameters_sha256", "accession_version", "window_start",
    "scale", "seed64", "bases", "replicates", "reason_code",
)
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
ACCESSION_RE = re.compile(r"^[A-Z]{1,8}_[0-9]+\.[0-9]+$")
ASSEMBLY_RE = re.compile(r"^GC[AF]_[0-9]+\.[0-9]+$")
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SCALES = (16, 100, 500, 1000)


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


def fasta_header_accession(text: str) -> str | None:
    parts = text.split()
    if not parts or ACCESSION_RE.fullmatch(parts[0]) is None:
        return None
    return parts[0]


def parse_fasta(path: pathlib.Path, accession: str) -> tuple[bytes, str]:
    raw = path.read_bytes()
    if not raw.endswith(b"\n") or b"\r" in raw or b"\x00" in raw:
        raise BindingError("FASTA must be LF-only ASCII with terminal LF")
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as exc:
        raise BindingError("FASTA must be ASCII") from exc
    current = None
    chunks: list[str] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        if line.startswith(">"):
            if current == accession:
                break
            header = fasta_header_accession(line[1:])
            if header is None:
                raise BindingError(f"FASTA header is not a versioned accession at line {line_no}")
            current = header
            chunks = []
            continue
        if current != accession:
            continue
        sequence = "".join(line.split()).upper()
        if not sequence or re.fullmatch(r"[ACGTRYSWKMBDHVN]+", sequence) is None:
            raise BindingError("fixture FASTA must contain only uppercase-normalizable IUPAC DNA")
        chunks.append(sequence)
    sequence = "".join(chunks)
    if current != accession or not sequence:
        raise BindingError("FASTA must contain exactly the declared accession")
    canonical = f">{accession}\n{sequence}\n".encode("ascii")
    return canonical, sequence


def validated_manifest_rows(manifest: pathlib.Path, parameter_sha: str) -> list[dict[str, str]]:
    raw_manifest = manifest.read_bytes()
    if not raw_manifest.endswith(b"\n") or b"\r" in raw_manifest:
        raise BindingError("manifest must be LF-only with terminal LF")
    with manifest.open(encoding="ascii", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != HEADER:
            raise BindingError("manifest header drift")
        rows = list(reader)
    if not rows:
        raise BindingError("manifest must contain at least one work unit")
    coordinates: set[tuple[str, int]] = set()
    work_ids: set[str] = set()
    ordering: list[tuple[str, int]] = []
    for index, row in enumerate(rows, start=1):
        if set(row) != set(HEADER) or any(row[field] is None for field in HEADER):
            raise BindingError(f"manifest row {index} is incomplete")
        accession = row["sequence_accession_version"]
        assembly = row["assembly_accession_version"]
        if ACCESSION_RE.fullmatch(accession) is None or ASSEMBLY_RE.fullmatch(assembly) is None:
            raise BindingError(f"manifest row {index} has invalid accession.version")
        try:
            length = int(row["sequence_length"])
            scale = int(row["scale"])
            stride = int(row["stride"])
        except ValueError as exc:
            raise BindingError(f"manifest row {index} numeric field malformed") from exc
        literals = {
            "u0_manifest_version": "1.0.0", "work_unit_id": f"{accession}@{scale}",
            "parameters_sha256": parameter_sha, "sequence_length": str(length),
            "scale": str(scale), "stride": str(scale), "k_min": "1",
            "k_max": "8", "null_model": "euler_wilson_fixed_endpoints_v1",
            "null_replicates": "1000",
        }
        for field, expected in literals.items():
            if row[field] != expected:
                raise BindingError(f"manifest row {index} {field} drift")
        if row["replicon_class"] not in ("chromosome", "plasmid"):
            raise BindingError(f"manifest row {index} replicon_class drift")
        if row["declared_alphabet"] not in ("acgt", "non_acgt"):
            raise BindingError(f"manifest row {index} alphabet drift")
        if scale not in SCALES or stride != scale or length < 1:
            raise BindingError(f"manifest row {index} scale/stride/length contract drift")
        if SHA_RE.fullmatch(row["source_file_sha256"]) is None or SHA_RE.fullmatch(row["sequence_sha256"]) is None:
            raise BindingError(f"manifest row {index} SHA-256 field malformed")
        relative = pathlib.PurePosixPath(row["source_locator"])
        if relative.is_absolute() or not relative.parts or any(part in ("", ".", "..") for part in relative.parts):
            raise BindingError(f"manifest row {index} source locator is unsafe")
        coordinate = (accession, scale)
        if coordinate in coordinates or row["work_unit_id"] in work_ids:
            raise BindingError("manifest has duplicate work-unit identity")
        coordinates.add(coordinate)
        work_ids.add(row["work_unit_id"])
        ordering.append(coordinate)
    if ordering != sorted(ordering, key=lambda item: (item[0], SCALES.index(item[1]))):
        raise BindingError("manifest work units are not in canonical accession/scale order")
    return rows


def inspect_selected_work_unit(parameters: pathlib.Path, manifest: pathlib.Path,
                               source_root: pathlib.Path,
                               work_unit_id: str | None = None) -> tuple[dict[str, str], str, str]:
    """Validate and bind one manifest row to its exact normalized FASTA."""
    for path, label in ((parameters, "parameters"), (manifest, "manifest")):
        reject_symlink_components(path, label)
        if path.is_symlink() or not path.is_file():
            raise BindingError(f"{label} must be a regular non-symlink file")
    parameter_sha = sha256_bytes(parameters.read_bytes())
    if parameter_sha != "68343e046af24a997195eb2583532d3172234b0b9713f2e4296b9b12300bef94":
        raise BindingError("canonical U0 parameter bytes drifted")
    rows = validated_manifest_rows(manifest, parameter_sha)
    if work_unit_id is None:
        if len(rows) != 1:
            raise BindingError("multi-unit manifest requires --work-unit-id")
        row = rows[0]
    else:
        selected = [candidate for candidate in rows if candidate["work_unit_id"] == work_unit_id]
        if len(selected) != 1:
            raise BindingError("requested work_unit_id is absent or duplicated")
        row = selected[0]
    accession = row["sequence_accession_version"]
    fasta = safe_source(source_root, row["source_locator"])
    raw_fasta, sequence = parse_fasta(fasta, accession)
    if sha256_bytes(raw_fasta) != row["source_file_sha256"]:
        raise BindingError("raw FASTA SHA-256 mismatch")
    if sha256_bytes(sequence.encode("ascii")) != row["sequence_sha256"]:
        raise BindingError("normalized sequence SHA-256 mismatch")
    if int(row["sequence_length"]) != len(sequence):
        raise BindingError("sequence length mismatch")
    actual_alphabet = "acgt" if re.fullmatch(r"[ACGT]+", sequence) is not None else "non_acgt"
    if row["declared_alphabet"] != actual_alphabet:
        raise BindingError("declared alphabet does not match normalized FASTA")
    return row, sequence, parameter_sha


def build(parameters: pathlib.Path, manifest: pathlib.Path, source_root: pathlib.Path,
          output: pathlib.Path, start_window: int, window_count: int,
          work_unit_id: str | None = None,
          run_id: str = "u0-work-unit-fixture") -> dict[str, int | str]:
    if output.exists() or output.is_symlink():
        raise BindingError("output already exists")
    if output.parent.is_symlink() or not output.parent.is_dir():
        raise BindingError("output parent must already be a real directory")
    if ID_RE.fullmatch(run_id) is None or len(run_id) > 128:
        raise BindingError("run_id must be a portable identifier of at most 128 bytes")
    row, sequence, parameter_sha = inspect_selected_work_unit(
        parameters, manifest, source_root, work_unit_id,
    )
    accession = row["sequence_accession_version"]
    length = int(row["sequence_length"])
    scale = int(row["scale"])
    total_windows = length // scale
    if start_window < 0 or start_window >= total_windows or window_count < 1 or window_count > 16:
        raise BindingError("requested window shard is outside the work unit or exceeds 16")
    stop_window = min(total_windows, start_window + window_count)
    cases = []
    excluded_rows = 0
    for window_index in range(start_window, stop_window):
        window_start = window_index * scale
        seed = hashlib.sha256(
            f"{parameter_sha}:{accession}:{window_start}".encode("ascii")
        ).hexdigest()[:16]
        bases = sequence[window_start:window_start + scale]
        reason_code = "" if re.fullmatch(r"[ACGT]+", bases) is not None else "NULL_INPUT_NOT_ACGT"
        if reason_code:
            excluded_rows += 1
        case = (
            accession.replace(".", "_") + f"_{scale}_{window_index}", run_id, parameter_sha,
            accession, str(window_start), str(scale), seed, bases, "1000", reason_code,
        )
        cases.append("\t".join(case))
    output.write_bytes(("\t".join(CASE_HEADER) + "\n" + "\n".join(cases) + "\n").encode("ascii"))
    next_window = stop_window if stop_window < total_windows else -1
    result: dict[str, int | str] = {
        "work_unit_id": row["work_unit_id"], "run_id": run_id, "accession_version": accession,
        "scale": scale, "total_windows": total_windows, "start_window": start_window,
        "stop_window": stop_window, "rows": len(cases), "next_window": next_window,
        "excluded_rows": excluded_rows,
        "sha256": sha256_bytes(output.read_bytes()), "size_bytes": output.stat().st_size,
    }
    print(f"U0_WORK_UNIT_CASE_BINDING_PASS work_unit_id={row['work_unit_id']} windows={len(cases)} scale={scale} start_window={start_window} next_window={next_window}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parameters", type=pathlib.Path, required=True)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--work-unit-id")
    parser.add_argument("--run-id", default="u0-work-unit-fixture")
    parser.add_argument("--start-window", type=int, default=0)
    parser.add_argument("--window-count", type=int, default=16)
    args = parser.parse_args()
    try:
        build(args.parameters, args.manifest, args.source_root, args.output,
              args.start_window, args.window_count, args.work_unit_id, args.run_id)
        return 0
    except (OSError, ValueError, BindingError) as exc:
        print(f"U0_WORK_UNIT_CASE_BINDING_FAIL: {exc}", file=sys.stderr)
        return 11


if __name__ == "__main__":
    raise SystemExit(main())
