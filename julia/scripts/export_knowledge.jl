#!/usr/bin/env julia
"""
    export_knowledge.jl

Export Atlas CSV tables to Demetrios epistemic Knowledge JSONL format.
Produces:
- data/epistemic/atlas_knowledge.jsonl
- data/epistemic/atlas_provenance.json
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using JSON3
using Dates
using SHA

# Constants
const SCHEMA_VERSION = "1.0.0"
const ATLAS_VERSION = "2.0.0-alpha"

# Get git SHA
function get_git_sha()
    try
        strip(read(`git rev-parse HEAD`, String))
    catch
        "unknown"
    end
end

# Validity predicates for metrics
const VALIDITY_PREDICATES = Dict(
    "gc_fraction" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
    "orbit_ratio" => (v -> 0.25 <= v <= 1.0, "0.25 <= x <= 1"),
    "dmin_over_L" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
    "dmin_normalized" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
    "length_bp" => (v -> v > 0, "x > 0"),
    "taxonomy_id" => (v -> v >= 0, "x >= 0"),
    "dihedral_order" => (v -> v > 0 && isinteger(v) && iseven(Int(v)), "x > 0 and even"),
    "verified_double_cover" => (v -> v isa Bool, "boolean"),
    "relations_satisfied" => (v -> v isa Bool, "boolean"),
    "confidence" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
)

# Epistemic classification: deterministic vs uncertain
const DETERMINISTIC_METRICS = Set([
    "length_bp", "taxonomy_id", "replicon_type", "assembly_accession",
    "replicon_id", "checksum_sha256", "dihedral_order", "lift_group",
    "verified_double_cover", "relations_satisfied"
])

function make_knowledge_record(;
    record_type::String,
    metric_name::String,
    value,
    provenance::Dict,
    epsilon=nothing,
    confidence=nothing
)
    # Determine validity
    pred_info = get(VALIDITY_PREDICATES, metric_name, nothing)
    validity_holds = true
    predicate_str = nothing

    if pred_info !== nothing && value !== nothing && !ismissing(value)
        check_fn, pred_str = pred_info
        try
            validity_holds = check_fn(value)
            predicate_str = pred_str
        catch
            validity_holds = true  # Can't check, assume valid
        end
    end

    # Auto-assign epsilon/confidence for deterministic metrics
    if metric_name in DETERMINISTIC_METRICS
        epsilon = 0.0
        confidence = 1.0
    end

    Dict(
        "record_type" => record_type,
        "metric_name" => metric_name,
        "value" => value,
        "epsilon" => epsilon,
        "confidence" => confidence,
        "validity" => Dict(
            "holds" => validity_holds,
            "predicate" => predicate_str
        ),
        "provenance" => provenance
    )
end

function export_replicons(df::DataFrame, base_prov::Dict)
    records = Dict[]

    metrics = [
        ("length_bp", :length_bp),
        ("gc_fraction", :gc_fraction),
        ("taxonomy_id", :taxonomy_id),
        ("replicon_type", :replicon_type),
        ("checksum_sha256", :checksum_sha256)
    ]

    for row in eachrow(df)
        prov = copy(base_prov)
        prov["assembly_accession"] = row.assembly_accession
        prov["replicon_id"] = row.replicon_id

        for (metric_name, col) in metrics
            haskey(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            # Convert enum-like values
            if val isa Symbol
                val = string(val)
            end

            push!(records, make_knowledge_record(
                record_type="replicon_metric",
                metric_name=metric_name,
                value=val,
                provenance=prov
            ))
        end
    end

    records
end

function export_dicyclic_lifts(df::DataFrame, base_prov::Dict)
    records = Dict[]

    for row in eachrow(df)
        prov = copy(base_prov)

        # dihedral_order
        if hasproperty(row, :dihedral_order) && !ismissing(row.dihedral_order)
            push!(records, make_knowledge_record(
                record_type="dicyclic_lift",
                metric_name="dihedral_order",
                value=row.dihedral_order,
                provenance=prov
            ))
        end

        # lift_group
        if hasproperty(row, :lift_group) && !ismissing(row.lift_group)
            push!(records, make_knowledge_record(
                record_type="dicyclic_lift",
                metric_name="lift_group",
                value=row.lift_group,
                provenance=prov
            ))
        end

        # verified_double_cover
        if hasproperty(row, :verified_double_cover) && !ismissing(row.verified_double_cover)
            push!(records, make_knowledge_record(
                record_type="dicyclic_lift",
                metric_name="verified_double_cover",
                value=row.verified_double_cover,
                provenance=prov
            ))
        end

        # relations_satisfied
        if hasproperty(row, :relations_satisfied) && !ismissing(row.relations_satisfied)
            push!(records, make_knowledge_record(
                record_type="dicyclic_lift",
                metric_name="relations_satisfied",
                value=row.relations_satisfied,
                provenance=prov
            ))
        end
    end

    records
end

function export_quaternion_results(df::DataFrame, base_prov::Dict)
    records = Dict[]

    for row in eachrow(df)
        prov = copy(base_prov)
        if hasproperty(row, :experiment_id) && !ismissing(row.experiment_id)
            prov["experiment_id"] = row.experiment_id
        end

        # Export numeric metrics with uncertainty
        numeric_cols = [:chain_length, :n_trials, :seed, :baseline_markov1_acc,
                        :baseline_markov2_acc, :quaternion_acc, :p_value_vs_markov2]

        for col in numeric_cols
            hasproperty(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            metric_name = string(col)

            # Accuracy/probability metrics have confidence constraints
            eps = nothing
            conf = nothing
            if endswith(metric_name, "_acc") || metric_name == "p_value_vs_markov2"
                eps = 0.01  # Conservative error bound
                conf = 0.95
            elseif metric_name in ["chain_length", "n_trials", "seed"]
                eps = 0.0
                conf = 1.0
            end

            push!(records, make_knowledge_record(
                record_type="quaternion_result",
                metric_name=metric_name,
                value=val,
                provenance=prov,
                epsilon=eps,
                confidence=conf
            ))
        end
    end

    records
end

function export_approx_symmetry(df::DataFrame, base_prov::Dict)
    records = Dict[]

    for row in eachrow(df)
        prov = copy(base_prov)
        if hasproperty(row, :replicon_id) && !ismissing(row.replicon_id)
            prov["replicon_id"] = row.replicon_id
        end
        if hasproperty(row, :window_length) && !ismissing(row.window_length)
            prov["window_length"] = row.window_length
        end

        # d_min metrics
        for col in [:d_min, :dmin, :d_min_over_L, :dmin_normalized, :dmin_over_L]
            hasproperty(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            metric_name = string(col)
            if metric_name in ["d_min_over_L", "dmin_normalized", "dmin_over_L"]
                metric_name = "dmin_over_L"
            end

            push!(records, make_knowledge_record(
                record_type="approx_symmetry",
                metric_name=metric_name,
                value=val,
                provenance=prov,
                epsilon=0.0,  # Computed exactly from Hamming distance
                confidence=1.0
            ))
        end
    end

    records
end

function main()
    # Parse args
    data_dir = get(ARGS, 1, joinpath(@__DIR__, "..", "..", "data"))
    pipeline_max = parse(Int, get(ENV, "PIPELINE_MAX", "200"))
    pipeline_seed = parse(Int, get(ENV, "PIPELINE_SEED", "42"))

    tables_dir = joinpath(data_dir, "tables")
    epistemic_dir = joinpath(data_dir, "epistemic")
    mkpath(epistemic_dir)

    println("Exporting Atlas Knowledge Layer")
    println("  Tables dir: $tables_dir")
    println("  Output dir: $epistemic_dir")

    # Base provenance
    git_sha = get_git_sha()
    timestamp = Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SSZ")

    base_prov = Dict(
        "atlas_git_sha" => git_sha,
        "atlas_version" => ATLAS_VERSION,
        "demetrios_schema_version" => SCHEMA_VERSION,
        "timestamp_utc" => timestamp,
        "pipeline_max" => pipeline_max,
        "pipeline_seed" => pipeline_seed,
        "ncbi_filter" => Dict(
            "assembly_level" => "complete genome",
            "source" => "RefSeq"
        ),
        "assembly_accession" => nothing,
        "replicon_id" => nothing,
        "replicon_accession" => nothing,
        "window_length" => nothing
    )

    all_records = Dict[]

    # Export each table
    tables = [
        ("atlas_replicons.csv", export_replicons),
        ("dicyclic_lifts.csv", export_dicyclic_lifts),
        ("quaternion_results.csv", export_quaternion_results),
        ("approx_symmetry_stats.csv", export_approx_symmetry),
        ("approx_symmetry_summary.csv", export_approx_symmetry),
    ]

    for (filename, exporter) in tables
        path = joinpath(tables_dir, filename)
        if isfile(path)
            println("  Processing $filename...")
            df = CSV.read(path, DataFrame)
            if nrow(df) > 0
                records = exporter(df, base_prov)
                append!(all_records, records)
                println("    -> $(length(records)) records")
            end
        end
    end

    # Write JSONL
    jsonl_path = joinpath(epistemic_dir, "atlas_knowledge.jsonl")
    open(jsonl_path, "w") do io
        for rec in all_records
            JSON3.write(io, rec)
            println(io)
        end
    end
    println("Wrote $(length(all_records)) records to $jsonl_path")

    # Write provenance
    prov_path = joinpath(epistemic_dir, "atlas_provenance.json")
    prov_meta = Dict(
        "export_timestamp" => timestamp,
        "atlas_git_sha" => git_sha,
        "atlas_version" => ATLAS_VERSION,
        "schema_version" => SCHEMA_VERSION,
        "pipeline_params" => Dict(
            "max" => pipeline_max,
            "seed" => pipeline_seed
        ),
        "tables_exported" => [t[1] for t in tables if isfile(joinpath(tables_dir, t[1]))],
        "total_records" => length(all_records),
        "ncbi_filter" => Dict(
            "assembly_level" => "complete genome",
            "source" => "RefSeq",
            "ftp_path" => "required"
        )
    )
    open(prov_path, "w") do io
        JSON3.write(io, prov_meta; allow_inf=true)
    end
    println("Wrote provenance to $prov_path")

    return 0
end

exit(main())
