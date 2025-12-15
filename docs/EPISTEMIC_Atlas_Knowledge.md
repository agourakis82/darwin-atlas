# Atlas Epistemic Knowledge Layer

This document describes the Demetrios L0 epistemic computing integration for the Darwin Operator Symmetry Atlas.

## Why Knowledge Layer Exists

The Knowledge layer wraps Atlas computed metrics with **epistemic metadata**:
- **Provenance**: Full traceability to source data (NCBI accession, git SHA, timestamp)
- **Uncertainty bounds**: Explicit epsilon/error quantification
- **Confidence scores**: Epistemic confidence in [0,1]
- **Validity predicates**: Domain constraints verified at export time

This enables:
1. Reproducibility audits (trace any metric back to its source)
2. Uncertainty propagation in downstream analyses
3. Automatic validation against Demetrios type constraints
4. FDA/EMA-style provenance for regulatory contexts

## How to Reproduce

```bash
# 1. Run pipeline (if tables don't exist)
make pipeline MAX=50 SEED=42

# 2. Export + validate Knowledge layer
make epistemic MAX=50 SEED=42

# Or in one step:
make epistemic-full MAX=50 SEED=42
```

Outputs:
- `data/epistemic/atlas_knowledge.jsonl` — One Knowledge record per metric
- `data/epistemic/atlas_provenance.json` — Pipeline run metadata
- `data/epistemic/atlas_knowledge_report.md` — Validation report

## What Fields Mean

Each JSONL record has:

| Field | Type | Description |
|-------|------|-------------|
| `record_type` | string | `replicon_metric`, `dicyclic_lift`, `quaternion_result`, `approx_symmetry` |
| `metric_name` | string | The specific metric (e.g., `gc_fraction`, `orbit_ratio`) |
| `value` | any | The metric value |
| `epsilon` | number? | Error bound (0 if exact, null if unknown) |
| `confidence` | number? | Epistemic confidence in [0,1] (1.0 if deterministic) |
| `validity.holds` | bool | Whether domain constraint satisfied |
| `validity.predicate` | string? | Human-readable constraint |
| `provenance` | object | Source tracing (see below) |

### Provenance Object

```json
{
  "assembly_accession": "GCF_000001234.1",
  "replicon_id": "GCF_000001234.1_rep1",
  "atlas_git_sha": "abc123...",
  "atlas_version": "2.0.0-alpha",
  "demetrios_schema_version": "1.0.0",
  "timestamp_utc": "2025-01-01T12:00:00Z",
  "pipeline_max": 50,
  "pipeline_seed": 42,
  "ncbi_filter": {
    "assembly_level": "complete genome",
    "source": "RefSeq"
  }
}
```

## How to Extend to New Metrics

1. **Add exporter function** in `julia/scripts/export_knowledge.jl`:
   ```julia
   function export_new_table(df::DataFrame, base_prov::Dict)
       records = Dict[]
       for row in eachrow(df)
           prov = copy(base_prov)
           prov["replicon_id"] = row.replicon_id

           push!(records, make_knowledge_record(
               record_type="new_metric_type",
               metric_name="my_metric",
               value=row.my_metric,
               provenance=prov,
               epsilon=0.0,      # or computed uncertainty
               confidence=1.0    # or computed confidence
           ))
       end
       records
   end
   ```

2. **Add validity predicate** (optional):
   ```julia
   VALIDITY_PREDICATES["my_metric"] = (v -> 0 <= v <= 100, "0 <= x <= 100")
   ```

3. **Register table** in the `tables` array in `main()`.

4. **Add verifier check** (optional) in `julia/scripts/verify_knowledge.jl`.

## Validation Rules

The verifier checks:

1. **provenance_present**: Provenance object must exist
2. **provenance_atlas_git_sha**: Git SHA must be present
3. **provenance_timestamp_utc**: Timestamp must be present
4. **epsilon_nonneg**: Error bounds must be >= 0
5. **confidence_range**: Confidence must be in [0,1]
6. **validity_holds**: Domain predicate must hold
7. **gc_fraction_range**: GC fraction in [0,1]
8. **orbit_ratio_range**: Orbit ratio in [0.25,1]
9. **dmin_range**: d_min/L in [0,1]
10. **length_positive**: Sequence length > 0

## Demetrios Integration

When the Demetrios compiler (`dc`) is available, the verifier runs natively:
```bash
dc run demetrios/src/verify_knowledge.d -- data/epistemic/atlas_knowledge.jsonl
```

Without `dc`, a Julia fallback provides equivalent validation.

## Schema Reference

See `data/epistemic/schema_atlas_knowledge.json` for the JSON Schema definition.
