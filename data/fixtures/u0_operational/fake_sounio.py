#!/usr/bin/env python3
"""Fixture-only canonical-envelope stand-in; scope fixture prevents promotion."""
import hashlib
import json
import pathlib
import sys
import time


def sha(path: str) -> str:
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def main() -> int:
    values = dict(zip(sys.argv[1::2], sys.argv[2::2]))
    # Deliberately slow enough to exercise the operational 100x threshold;
    # the enclosing evidence scope is fixture and cannot promote U0.
    time.sleep(15.0)
    sequence = pathlib.Path(values["--sequence"])
    parameters = pathlib.Path(values["--parameters"])
    output = pathlib.Path(values["--output"])
    output.write_bytes(b"fixture-sounio-n1000-output\n")
    envelope = {
        "schema_version": "dosa-v3-u0-sounio-n1000-recompute-1",
        "producer": {"language": "Sounio", "canonical": True, "runner_sha256": sha(sys.argv[0]), "attestation_sha256": values["--sounio-attestation-sha256"]},
        "inputs": {"accession_version": values["--accession-version"], "scale": values["--scale"], "coordinate_start": int(values["--coordinate-start"]), "coordinate_end": int(values["--coordinate-end"]), "sequence_bytes": sequence.stat().st_size, "sequence_sha256": sha(str(sequence)), "parameters_bytes": parameters.stat().st_size, "parameters_sha256": sha(str(parameters))},
        "null_model": "euler_wilson_fixed_endpoints_v1",
        "null_replicates": 1000,
        "output_bytes": output.stat().st_size,
        "output_sha256": sha(str(output)),
    }
    print(json.dumps(envelope, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
