# BioStudies deposition runbook — DOSA v3

This runbook is for validated U0 or later shards only. It does not authorize a
deposit, does not create a BioStudies record, and does not contain credentials.
The canonical scientific producer remains Sounio; Julia independently
validates the published logical records before any file can enter this queue.

## Boundary

`scripts/prepare_biostudies_queue.py` is deliberately an offline validator.
It checks regular files, relative names, bytes, SHA-256, validation status and
the 200 GiB maximum local pending queue. Its receipt always states
`upload_performed=false` and has no option that can upload data. A fixture is
rejected before queueing. A failed Julia/Sounio receipt is rejected before
queueing.

The command is:

```bash
python3 scripts/prepare_biostudies_queue.py \
  --candidate validated-upload-candidate.json \
  --root validated-shards \
  --output receipts/biostudies-queue-<utc>.json
```

The candidate is a canonical JSON object with schema version
`dosa-v3-biostudies-upload-candidate-1`, `evidence_scope: "u0_pilot"`, a
hash-bound `dosa-v3-biostudies-shard-validation-receipt-1` path/size/SHA-256,
and `files` entries containing a normalized relative path, byte count and
SHA-256. The validation receipt must bind the canonical Sounio producer,
independent Julia validation with zero disagreements/tolerance, and exactly
the queued payload hashes. A free-standing `"status":"PASS"` string is not
accepted. The output receipt is the object to review; it is not evidence that
a remote system has received anything.

## Preconditions for a real upload

Real submission remains **blocked** until all of the following are recorded:

1. U0 itself is PASS, including the public-query and full Sounio/Julia
   agreement receipts.
2. A BioStudies accession or a documented submission coordinator has accepted
   the planned dataset layout.
3. BioStudies has confirmed the permitted transfer route and credentials. For
   large data, follow its current guidance on Aspera/large submissions rather
   than automating a guessed HTTP endpoint.
4. An explicit upload authorization names the validated queue receipt and the
   target submission.
5. The queue is at most 200 GiB pending locally and has an off-host replica.

BioStudies' current submission guidance is the authoritative source for the
deposit workflow: [BioStudies submission documentation](https://www.ebi.ac.uk/biostudies/submit).
For an ongoing high-volume pipeline, coordinate with BioStudies before any
bulk transfer. Zenodo remains only for the light release, not this shard
stream.

## After explicit authorization

Use the provider-approved client/configuration outside the repository's
offline queue validator. Record, in a new receipt, the remote accession,
server-side file inventory, byte count, SHA-256 values where supported,
timestamp, transfer tool version and a restoration/read-back check. Never
infer success from a local queue receipt or a completed client process alone.

No command in this repository simulates that receipt. Until it exists, the
authoritative state is `READY_FOR_COORDINATION`, not uploaded.
