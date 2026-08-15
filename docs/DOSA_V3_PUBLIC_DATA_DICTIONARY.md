# DOSA v3 public data dictionary

**Current state: U0 NOT YET PASSED; full atlas and HDD BLOCKED_UNTIL_U0;
data release BLOCKED.** This document defines a candidate public contract, not
an atlas release, HDD justification, or biological result.

## Tables and joins

| Public filename | Schema | Row identity | Demonstrated use | Removal/replacement criterion |
| --- | --- | --- | --- | --- |
| `runs.parquet` | `dosa_v3_run.schema.json` | `run_id` | Bind all tables to parameters, immutable source closure, and the Sounio producer. | Supersede with a new immutable run; do not edit a completed run. |
| `replicons.parquet` | `dosa_v3_replicon.schema.json` | `replicon_id` | Join accession, topology, class, length, and source hash without repeating metadata per window. | Replace only when a versioned source record changes. |
| `window_operator_profiles.parquet` | `dosa_v3_window_profile.schema.json` | `(run_id, replicon_id, window_size, window_index)` | Independently recompute every positional/k-mer observation and null block at an exact interval. | Remove a row only through an explicit exclusion in a new run. |
| `replicon_operator_summary.parquet` | `dosa_v3_summary.schema.json` | `(run_id, replicon_id, window_size, metric_id, k)` | Reconstruct replicon-level roll-ups from eligible windows. | Regenerate whenever any source profile changes. |
| `excluded_records.parquet` | `dosa_v3_exclusion.schema.json` | `(run_id, replicon_id, exclusion_level, window coordinates, metric_id, k)` | Audit replicon-, window-, and metric-level non-eligibility by reason code. | Supersede only with a corrected run; never silently delete. |

`dosa_v3_source_manifest.schema.json` records immutable inputs;
`dosa_v3_source_index.schema.json` is the portable accession.version-to-source
closure bundled with queryable payloads; it uses only public relative locators;
`dosa_v3_payload_manifest.schema.json` requires and hash-closes the five named
tables; `dosa_v3_receipt.schema.json` records U0 and release decisions.

## Canonical parameters

| Field | Meaning and demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `schema_version` | Selects the exact v3 contract used by validators and readers. | Never remove; any incompatible change increments it. |
| `contract_id` | Prevents a different parameter family from being treated as U0. | Replace only with a separately versioned contract. |
| `window_profiles` | Fixes 16/16, 100/100, 500/500, and 1000/1000 bp profiles. | New resolution or overlap requires a new parameter/schema version and receipts. |
| `k_min`, `k_max` | Bounds the declared panel at k=1 through k=8. | Any range change creates a new analytic family. |
| `operator_panel.positional` | Requires exact positional R and RC. | Remove only under a new utility decision and validation. |
| `operator_panel.kmer_r` | Requires k-mer R at k=2..8. | k=1 remains omitted while identically zero. |
| `operator_panel.kmer_rc` | Requires k-mer RC at k=1..8. | Range change requires a new contract. |
| `operator_panel.omitted_identically_zero` | Makes the deliberate reverse-k1 omission machine-visible. | Remove only if the operator is redefined and no longer identically zero. |
| `null_model` | Fixes `euler_wilson_fixed_endpoints_v1`. | Replacement requires generator-quality and independent-recomputation receipts. |
| `null_replicates` | Fixes n=1000 for every available null block. | A partial n is unavailable data, not an implicit alternative run. |
| `coordinate_system` | Fixes every public interval as zero-based, half-open. | Coordinate changes require a new schema version and migration. |

Gate state and policy are deliberately absent from the immutable scientific
parameter object: changing `NOT_YET_PASSED` to `PASSED` must not change the
parameter hash that the evidence was computed under. The U0 pass rule,
requirement list, execution/HDD decisions and release policy live in ADR-0004
and the versioned gate receipt schema instead.

## Source manifest fields

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `schema_version` | Selects the manifest parser. | Never remove; incompatible changes increment it. |
| `manifest_id` | Identifies the immutable acquisition closure. | A changed source set receives a new ID. |
| `retrieved_utc` | Distinguishes time-sensitive source retrievals. | Never infer from file modification time. |
| `source_provider` | Declares the NCBI Datasets provenance family. | Provider changes create a new manifest contract. |
| `query.path`, `query.sha256`, `query.size_bytes`, `query.object` | Publish the fresh query semantics and bind/size-check the exact query-file bytes. | A query change requires a new manifest; neither object nor hash may be inferred later. |
| `acquisition_tools.datasets.version`, `.source_url`, `.sha256`, `.size_bytes` | Reacquire and verify the exact NCBI datasets binary. | Tool drift creates a new acquisition manifest. |
| `acquisition_tools.dataformat.version`, `.source_url`, `.sha256`, `.size_bytes` | Reacquire and verify the companion dataformat binary. | Tool drift creates a new acquisition manifest. |
| `package.package_id`, `package.source_url`, `package.package_root` | Identify the NCBI package request and its portable package-relative root. | Source URL/root changes require a new manifest; absolute/private paths are prohibited. |
| `package.dehydrated_archive.path`, `.sha256`, `.size_bytes` | Reconstruct and verify the downloaded dehydrated package. | Changed archive bytes create a new manifest. |
| `package.catalog.path`, `.sha256`, `.size_bytes` | Bind the NCBI catalog describing package contents. | Missing/unverified catalog blocks source closure. |
| `package.checksum_manifest.path`, `.sha256`, `.size_bytes` | Bind the checksum ledger used to verify rehydrated bytes. | Missing/unverified checksum ledger blocks source closure. |
| `package.catalog_verified`, `package.package_checksums_verified`, `package.selected_assets_complete` | Fail closed unless the catalog, all checksums, and selected-asset coverage were verified. | All three must remain true for external recovery. |
| `selected_records[].source_record_id`, `.replicon_id` | Join source, replicon, and asset records without copying package metadata into analytic rows. | IDs change only in a versioned manifest. |
| `selected_records[].assembly_accession_version`, `.sequence_accession_version` | Recover exact versioned NCBI assembly and replicon records. | Unversioned accessions are invalid substitutes. |
| `selected_records[].required_asset_kinds` | Requires FASTA, GBFF, and sequence-report coverage for each selected record. | Asset-set changes require a manifest schema version. |
| `package_assets[].asset_id`, `.asset_kind` | Identify the immutable FASTA/GBFF/sequence-report object. | New or removed objects require a new manifest. |
| `package_assets[].assembly_accession_version`, `.sequence_accession_version` | Bind each asset to the exact NCBI version; sequence may be null only for a shared assembly-level asset. | Accession drift creates a new asset record. |
| `package_assets[].selected_record_ids` | Prove which selected replicons each immutable package asset serves. | Validator requires complete three-kind coverage. |
| `package_assets[].source_url`, `.package_path` | Let an external reviewer locate the upstream object and its portable in-package path. | Private absolute paths or parent traversal are invalid. |
| `package_assets[].sha256`, `.size_bytes` | Verify asset identity and detect truncation. | Never remove from immutable source closure. |

## Run fields

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `schema_version` | Selects the run-row parser. | Never remove. |
| `run_id` | Primary join key across all public tables and receipts. | A rerun receives a new ID. |
| `parameters_sha256` | Proves the exact U0 parameter bytes. | Parameter-byte changes create a new run. |
| `source_manifest_sha256` | Proves the exact acquisition closure. | Source changes create a new run. |

### Portable source index

`source_index.json` uses `dosa-v3-source-index-1` and has one duplicate-free
record keyed by each versioned sequence accession. Its `locator` is relative to
the public source manifest/package root, never a workstation or cluster path.
Each record carries `canonical_sequence_input_sha256`,
`normalized_sequence_sha256`, `source_manifest_sha256`, and
`source_integrity_sha256`, so a query result can bind its sequence provenance
without copying the acquisition manifest into every shard.
| `producer.language` | Enforces Sounio as the canonical producer. | Cannot change without superseding ADR-0001. |
| `producer.source_commit` | Rebuilds the exact producer source. | A source change creates a new run. |
| `producer.compiler_sha256`, `producer.executable_sha256` | Bind the toolchain and executed producer bytes. | Missing or changed hashes block validation. |
| `status` | Distinguishes generated, failed, and independently validated runs. | Never infer `validated` from artifact presence. |
| `started_utc`, `finished_utc` | Audit run ordering and duration boundaries. | Never synthesize after the run. |

## Replicon fields

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `replicon_id` | Stable public join key used instead of repeated metadata. | Reassign only in a versioned migration. |
| `assembly_accession_version`, `sequence_accession_version` | Recover the exact versioned NCBI biological record. | Unversioned accessions are not substitutes. |
| `replicon_class`, `declared_topology` | Support chromosome/plasmid and linear/circular stratification. | Remove only if the associated U0 controls are retired through a new contract. |
| `length_bp` | Check interval bounds and expected window counts. | Must change with sequence bytes, never independently. |
| `sequence_sha256` | Verify the analyzed sequence bytes. | Never replace with accession identity alone. |
| `source_record_id` | Join back to the source manifest without copying paths/checksums per window. | Required while manifest provenance is retained. |

## Window identity and eligibility

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `run_id`, `replicon_id` | Join provenance and the single canonical replicon metadata row. | Never replace with copied accession/topology fields. |
| `window_size`, `window_index`, `window_start`, `window_end` | Locate the zero-based, half-open source interval for recomputation. | Coordinate change requires a schema version. |
| `status`, `reason_code` | Separate eligible observations from declared exclusions. | An excluded row without a reason is invalid. |

## Operator observations

`positional_r` and `positional_rc` are single observation objects. `kmer_r` is
an exact seven-item k=2..8 collection. `kmer_rc` is an exact eight-item k=1..8
collection. Reverse k-mer R at k=1 has no public field because it is identically
zero.

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `k` | Identifies the k-mer scale; absent from positional observations. | Change only with the canonical k range. |
| `effective_count` | Reports how many positions/k-mers were eligible for the observation. | Required while an observation is public. |
| `observed.numerator`, `observed.denominator` | Exact positional mismatch or k-mer imbalance fraction. | Rounded duplicates and extra denominator fields are prohibited. |
| `reason_code` | Explains unavailable observed data. | Must be null only when the exact observation is available. |
| `null_summary` | Binds the generated reference distribution for the same operator/k/window. | Available only after all 1000 draws complete. |

## Null summaries

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `n` | Distinguishes the complete n=1000 reference from unavailable n=0. | No partial effective n is permitted in this contract. |
| `mean`, `mad`, `q025`, `q500`, `q975` | Exact rational summaries for plots and independent recomputation. | Do not add rounded canonical duplicates. |
| `tail_lt`, `tail_eq`, `tail_gt` | Integer partition of the 1000 draws relative to observed; validator checks their sum equals n. | Null unless n=1000. |
| `reason_code` | Explains unavailable nulls such as ambiguity, failed generator, or incomplete draws. | Missing reason blocks an unavailable block. |

The release contract requires the canonical producer and independent Julia
validator to enforce cross-field invariants that JSON Schema cannot compare
directly: an available observation denominator equals its `effective_count`;
`tail_lt + tail_eq + tail_gt = n`; window end minus start equals the declared
full window size; and summary `windows_eligible + windows_excluded =
windows_total`. The current `U0-dev` manifest fixture does not implement that
full-scale row validator or executor, so it cannot issue the required full
agreement receipt. Any absent or mismatching invariant receipt blocks U0 and
release.

## Replicon summary fields

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `run_id`, `replicon_id` | Join the roll-up to its exact run and replicon. | Never replace with copied metadata. |
| `window_size` | Selects the resolution being summarized. | Must match the canonical profile set. |
| `metric_id`, `k` | Identifies positional R/RC or k-mer R/RC; positional k is null and reverse-k1 is impossible. | Metric-family changes require a new schema. |
| `windows_total`, `windows_eligible`, `windows_excluded` | Reconcile coverage and exclusions. | Their producer/validator invariant must remain auditable. |
| `effective_count` | Reports the exact aggregated opportunity count. | Required for denominator audit. |
| `observed` | Exact aggregate numerator/denominator. | Do not replace with a rounded scalar. |
| `null_summary`, `reason_code` | Preserve the aggregate reference distribution or explicit unavailability. | Must be regenerated with the underlying profiles. |

## Exclusion fields

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `run_id`, `replicon_id` | Join every exclusion to provenance and source metadata. | Never replace with repeated accession fields. |
| `exclusion_level` | Distinguishes replicon-, window-, and metric-level decisions. | New level requires a schema version. |
| `window_size`, `window_index`, `window_start`, `window_end` | Locate window/metric exclusions; all are null for a replicon exclusion. | Coordinate changes require a new schema. |
| `metric_id`, `k` | Locate an operator-specific exclusion; both are null above metric level and reverse-k1 is disallowed. | New metric family requires a new contract. |
| `reason_code` | Makes every exclusion auditable and countable. | Never replace with free text or silent omission. |

## Payload manifest fields

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `schema_version` | Selects the payload-manifest validator. | Never remove. |
| `payload_id`, `run_id` | Identify the immutable package and its generating run. | Any changed byte receives a new payload ID. |
| `parameters_sha256`, `source_manifest_sha256` | Close parameters and inputs without repeating their contents. | Hash mismatch blocks the payload. |
| `public_tables[].filename` | Requires exactly the five logical public Parquet table names. | Filename/table-set changes require a schema version. |
| `public_tables[].schema_id` | Identifies the row contract for each table. | Schema changes require a new ID. |
| `public_tables[].record_count` | Reconciles the logical table row count, including the total across all window shards. | Count drift blocks release closure. |
| `public_tables[].storage` | Declares either one hash-closed Parquet file or the package-manifest partitioning layout. The window table is always `package_manifest_partitioned` by scale then accession SHA-256 bucket. | Storage/layout changes require a schema version. |
| `package_manifests[].package_manifest_id`, `.path`, `.sha256`, `.size_bytes` | Bind each physical v3 CLI shard manifest exactly once from the public manifest. | An unreferenced or mismatching shard package blocks operational lookup. |
| `package_manifests[].table_filename`, `.manifest_version`, `.package_version` | Prevent a package for a different logical table or CLI contract from being substituted. | Version/table changes require a new manifest contract. |
| `supporting_artifacts[].path`, `.media_type`, `.schema_id` | Locate and type provenance/receipt support files. | Remove an artifact only in a new manifest. |
| `supporting_artifacts[].sha256`, `.size_bytes`, `.record_count` | Hash-close and size/count-check supporting artifacts. | Hash/size changes create a new manifest. |
| `release_state` | Distinguishes `blocked_pending_receipts`, the dedicated gate-input state `u0_pilot_evidence`, and `release_candidate`. | `u0_pilot_evidence` is necessary but never sufficient for U0 PASS; final release still requires the separate receipt. |

## U0 evidence-root and provenance fields

A real U0 evaluation supplies one immutable evidence root plus
`u0-pilot-provenance.json`. The provenance document closes exactly 29 roles:
the agreement, query, speed, capacity, field-audit, OriC and model reports;
both scientific prediction inputs; parameters; source manifest, integrity
receipt and portable source index; payload manifest; Sounio build attestation,
build receipt, execution receipt and output manifest; and the full Julia
validation receipt. It also closes deterministic selection, discovery
assembly/sequence reports, the full-replicon inventory, control candidates,
the generated control ledger and its binding/semantic receipts, the source
freeze receipt, and the exact replicon-by-scale work-unit manifest.

That 29-role structure is a development scaffold, not an enabled promotion
contract. The shard-composed Sounio executor and Base-only integral Julia
validator are implemented and produce nonpromotable fixture receipts. Six
additional held-out derivation roles (scientific cohort, split,
OriC ground truth and derivation receipt, injected-model manifest and model
derivation receipt) are deliberately absent. Their absence and the missing
real RefSeq evidence keep
`U0_PROMOTION_LOCKED`; the two Julia evaluators also refuse held-out scope.

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `schema_version` | Selects the exact U0 provenance-root contract. | Incompatible role or validation changes require a new version. |
| `evidence_scope` | Requires the real scope `u0_pilot`; fixture and mixed scopes are not promotable. | Never infer from report labels alone. |
| `artifacts[].role`, `.path` | Requires exactly one normalized relative, non-symlink file below the evidence root for each frozen role. | Added, missing, duplicate, escaping, or substituted paths block U0. |
| `artifacts[].sha256`, `.size_bytes` | Closes the exact supplied bytes and rejects post-binding drift. | Any changed byte creates a new provenance document. |
| `authenticity_boundary` | Must state `integrity_closure_not_external_authentication`. | Local hashes prove integrity of the closed set, not who created it; external-use and remote-inventory evidence cannot be waived. |

The Sounio build attestation is build provenance only and remains explicitly
non-semantic. The real Sounio execution receipt and output manifest must bind
the completed work units and persisted output artifacts; the gate opens those
artifacts, schema-validates every logical row, proves exact window coverage,
and checks totals against the independent full Julia receipt. Every referenced
package manifest and Zstandard Parquet shard is opened, the capacity report is
recomputed from the full inventory, and each logical Sounio output must map to
exactly one verified package. Reports containing the payload hash live in the
top-level provenance/final receipt instead of inside that same payload, so the
hash graph remains acyclic. The source manifest, source index,
source-integrity receipt, and query report must agree on the queried accession
and raw, canonical, and normalized sequence hashes. Before the promotion lock
may be removed, each held-out Julia scientific report must also bind the
evaluator source and exact prediction input hashes, and both Julia evaluators
must be rerun from the frozen derivation closure.

## Gate receipt fields

| Field | Demonstrated use | Removal/change criterion |
| --- | --- | --- |
| `schema_version`, `receipt_id`, `run_id` | Select the contract and bind an immutable decision to its run. | A new decision receives a new receipt ID. |
| `parameters_sha256`, `source_manifest_sha256`, `payload_manifest_sha256` | Prevent gate evidence from being attached to different parameter, source, or payload bytes. | Any mismatch blocks the receipt. |
| `source_identity.git_commit_full`, `.git_tree_full`, `.clean`, `.tag`, `.remote_url`, `.source_archive_path`, `.source_archive_sha256` | Close the exact clean source tree, immutable release tag, resolvable remote, and deposited source archive. | U0 development may use a null tag; release requires exactly `v3.0.0`. |
| `producer.*` | Bind the official Sounio repository commit, producer source, compiler, executable, and producer receipt hashes. | A missing or dirty/unbound producer blocks U0/release. |
| `validator.*` | Bind Julia version, Project/Manifest/implementation hashes, full recomputation count, zero disagreements/tolerance, and validator receipt. | Julia cannot be replaced by a producer echo or sample-only release check. |
| `accelerators[]` | Bind R9700 primary-null and U250 independent-equivalence implementation/artifact/receipt hashes at tolerance zero. | Release requires both roles; hardware does not waive Sounio or Julia. |
| `runtime_environment.*` | Records OS release, architecture, and an explicit container digest or null when no container was used. | Environment changes create a new receipt. |
| `remote_inventories[]` | Closes BioStudies and Zenodo separately with accession, file count, API inventory hash, and receipt. | Release requires exactly one verified inventory for each provider; local staging is never remote closure. |
| `u0_evaluation.state`, `u0_evaluation.reason_code` | Exposes the fail-closed U0 decision and why it has not passed. | `PASSED` requires a null reason; non-passage requires a stable code. |
| `u0_evaluation.evidence_scope` | Prevents fixtures or mixed evidence from being promoted to U0 passage; `PASSED` requires `u0_pilot`, payload `release_state=u0_pilot_evidence`, and the exact provenance-root closure above. | Never infer real-pilot scope from a fixture receipt or a relabelled/rehashed threshold report. |
| `u0_evaluation.mandatory_operational_requirements` | Records exactly the six frozen checks and requires all six to pass with hash-bound receipts. | No item may be waived by a scientific result. |
| `u0_evaluation.scientific_secondary_tests` | Records exactly OriC/terminus and RC-equivariance, requiring at least one pass. | Changing number, identity, or rule requires a gate-version change. |
| `requirement_id`, `state`, `receipt_path`, `receipt_sha256`, `reason_code` | Identify each check, bind passing evidence, and explain non-passage. | A passing item without path/hash or blocked item without reason is invalid. |
| `full_atlas_execution_state` | Keeps full execution blocked before U0. | May become `PERMITTED_AFTER_U0`; not a U0/release receipt. |
| `hdd_purchase_state` | Keeps purchase blocked before U0. | May become `PERMITTED_AFTER_U0`; purchase never counts as science or release evidence. |
| `release_gates.full_producer` | Binds the full-scope Sounio product receipt. | Mandatory for release. |
| `release_gates.full_julia` | Binds independent full-scope Julia recomputation. | Mandatory for release; Julia is not a producer fallback. |
| `release_gates.payload` | Binds table/schema/checksum closure. | Mandatory for release. |
| `release_gates.external_use` | Binds the external-use demonstration. | Mandatory for release. |
| `release_state` | States the final data-release decision. | `PASSED` requires U0 and all four release gates; hardware ownership is not consulted. |

No fixed flags, repeated metadata, redundant denominators, legacy orbit fields,
rounded canonical ratios, p-values, or q-values belong to the v3 public
analytic layer. Historical v2 artifacts remain byte-preserved under their own
engineering boundary and cannot be relabelled as v3 evidence.

The real U0 provenance profile is partially scaffolded and explicitly locked.
The multiscale executor/output and integral Julia closure pass only on synthetic
fixtures; no real-pilot receipt or held-out derivation closure exists. This
dictionary therefore does not imply an enabled PASS path or U0 passage.
