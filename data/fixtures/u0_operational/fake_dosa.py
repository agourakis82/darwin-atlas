#!/usr/bin/env python3
"""Fixture-only dosa query stand-in; it never represents an external query."""
import hashlib
import json
import pathlib
import sys


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] != "query":
        return 12
    values = dict(zip(sys.argv[2::2], sys.argv[3::2]))
    package = pathlib.Path(values["--package"])
    accession = values["--accession-version"]
    start, end = (int(value) for value in values["--coordinate"].split(":", 1))
    shard = "scale=16/sha256_bucket=fb/part-00000.parquet"
    manifest_hash = hashlib.sha256((package / "dosa-payload-manifest.json").read_bytes()).hexdigest()
    payload_hash = "7dd470767f9ed0887e7b50df542fa162c494b2492ba637983ac57cd4e2fbc89c"
    manifest = json.loads((package / "dosa-payload-manifest.json").read_text())
    source_binding = next(item for item in manifest["bindings"] if item["kind"] == "source_index")
    source_index = json.loads((package / source_binding["name"]).read_text())
    source_record = source_index["records"][accession]
    result = {
        "status": "ok",
        "query": {"accession_version": accession, "accession_sha256_bucket": hashlib.sha256(accession.encode()).hexdigest()[:2], "coordinate_start": start, "coordinate_end": end, "scale": values["--scale"]},
        "shards_read": [shard],
        "records": [{"sequence_accession_version": accession, "window_start": start, "window_end": end}],
        "source_index_sha256": source_binding["sha256"],
        "source_record": source_record,
        "package_manifest_sha256": manifest_hash,
        "payloads": [{"name": shard, "sha256": payload_hash}],
    }
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
