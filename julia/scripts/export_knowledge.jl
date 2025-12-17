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
const DEFAULT_DATASET_DIR = joinpath(@__DIR__, "..", "..", "dist", "atlas_dataset_v2")

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
    "x_k" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
    "x_k_6" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
    "ori_confidence" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
    "ter_confidence" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
    "gc_skew_amplitude" => (v -> v >= 0.0, "x >= 0"),
    "window_size" => (v -> v > 0, "x > 0"),
    "ir_count" => (v -> v >= 0, "x >= 0"),
    "ir_density" => (v -> v >= 0.0, "x >= 0"),
    "baseline_count" => (v -> v >= 0.0, "x >= 0"),
    "enrichment_ratio" => (v -> v >= 0.0, "x >= 0"),
    "p_value" => (v -> 0.0 <= v <= 1.0, "0 <= x <= 1"),
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
    "verified_double_cover", "relations_satisfied",
    "x_k", "k_l_tau_05", "k_l_tau_10", "total_kmers", "symmetric_kmers",
    "gc_skew_amplitude", "window_size", "ori_confidence", "ter_confidence",
    "x_k_6",
    "ir_count", "ir_density", "baseline_count", "enrichment_ratio", "p_value",
    "stem_min_length", "stem_max_length", "loop_min_length", "loop_max_length"
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

function safe_int(x)
    x isa Integer && return Int(x)
    x isa AbstractFloat && return Int(round(x))
    return parse(Int, string(x))
end

function load_pipeline_metadata(dataset_dir::String)::Dict{String, Any}
    path = joinpath(dataset_dir, "manifest", "pipeline_metadata.json")
    if !isfile(path)
        return Dict{String, Any}()
    end
    try
        return JSON3.read(read(path, String), Dict{String, Any})
    catch
        return Dict{String, Any}()
    end
end

function load_replicon_index(tables_dir::String)
    path = joinpath(tables_dir, "atlas_replicons.csv")
    if !isfile(path)
        return Dict{String, Dict{String, Any}}()
    end

    df = CSV.read(path, DataFrame)
    idx = Dict{String, Dict{String, Any}}()
    if !hasproperty(df, :replicon_id)
        return idx
    end

    for row in eachrow(df)
        rid = string(row.replicon_id)
        idx[rid] = Dict(
            "assembly_accession" => hasproperty(row, :assembly_accession) ? string(row.assembly_accession) : nothing,
            "length_bp" => hasproperty(row, :length_bp) ? safe_int(row.length_bp) : nothing
        )
    end

    return idx
end

function enrich_replicon_provenance!(prov::Dict, replicon_idx::Dict{String, Dict{String, Any}})
    rid = get(prov, "replicon_id", nothing)
    rid === nothing && return prov
    info = get(replicon_idx, string(rid), nothing)
    info === nothing && return prov

    if get(prov, "assembly_accession", nothing) === nothing
        prov["assembly_accession"] = get(info, "assembly_accession", nothing)
    end
    prov["length_bp"] = get(info, "length_bp", nothing)
    return prov
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

        # Experiment table (optional)
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

        # Theoretical table (always present in v2): export all columns deterministically.
        for col in [:n, :dicyclic_order, :dihedral_order, :double_cover_verified, :group_notation]
            hasproperty(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            metric_name = string(col)
            push!(records, make_knowledge_record(
                record_type="quaternion_result",
                metric_name=metric_name,
                value=val,
                provenance=prov,
                epsilon=0.0,
                confidence=1.0
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

function export_kmer_inversion(df::DataFrame, base_prov::Dict, replicon_idx::Dict{String, Dict{String, Any}})
    records = Dict[]

    sort!(df, [:replicon_id, :replichore, :k]; rev=false)

    metrics = [
        ("x_k", :x_k),
        ("k_l_tau_05", :k_l_tau_05),
        ("k_l_tau_10", :k_l_tau_10),
        ("total_kmers", :total_kmers),
        ("symmetric_kmers", :symmetric_kmers)
    ]

    for row in eachrow(df)
        prov = copy(base_prov)
        prov["replicon_id"] = hasproperty(row, :replicon_id) ? string(row.replicon_id) : nothing
        prov["k"] = hasproperty(row, :k) ? safe_int(row.k) : nothing
        prov["replichore"] = hasproperty(row, :replichore) ? string(row.replichore) : nothing
        prov["source_table"] = "kmer_inversion.csv"
        enrich_replicon_provenance!(prov, replicon_idx)

        for (metric_name, col) in metrics
            hasproperty(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            push!(records, make_knowledge_record(
                record_type="kmer_metric",
                metric_name=metric_name,
                value=val,
                provenance=prov
            ))
        end
    end

    return records
end

function export_gc_skew(df::DataFrame, base_prov::Dict, replicon_idx::Dict{String, Dict{String, Any}})
    records = Dict[]
    sort!(df, [:replicon_id]; rev=false)

    for row in eachrow(df)
        prov = copy(base_prov)
        prov["replicon_id"] = hasproperty(row, :replicon_id) ? string(row.replicon_id) : nothing
        prov["window_size"] = hasproperty(row, :window_size) ? safe_int(row.window_size) : nothing
        prov["source_table"] = "gc_skew_ori_ter.csv"
        enrich_replicon_provenance!(prov, replicon_idx)

        # ori/ter positions: not "exact" (windowed estimate). Store uncertainty and epistemic confidence.
        if hasproperty(row, :ori_position) && !ismissing(row.ori_position)
            win = hasproperty(row, :window_size) && !ismissing(row.window_size) ? safe_int(row.window_size) : 0
            eps = win > 0 ? win / 2 : nothing
            conf = hasproperty(row, :ori_confidence) && !ismissing(row.ori_confidence) ? Float64(row.ori_confidence) : nothing
            push!(records, make_knowledge_record(
                record_type="skew_metric",
                metric_name="ori_position",
                value=row.ori_position,
                provenance=prov,
                epsilon=eps,
                confidence=conf
            ))
        end

        if hasproperty(row, :ter_position) && !ismissing(row.ter_position)
            win = hasproperty(row, :window_size) && !ismissing(row.window_size) ? safe_int(row.window_size) : 0
            eps = win > 0 ? win / 2 : nothing
            conf = hasproperty(row, :ter_confidence) && !ismissing(row.ter_confidence) ? Float64(row.ter_confidence) : nothing
            push!(records, make_knowledge_record(
                record_type="skew_metric",
                metric_name="ter_position",
                value=row.ter_position,
                provenance=prov,
                epsilon=eps,
                confidence=conf
            ))
        end

        # Remaining skew metrics (deterministic algorithm outputs)
        for col in [:ori_confidence, :ter_confidence, :gc_skew_amplitude, :window_size]
            hasproperty(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            push!(records, make_knowledge_record(
                record_type="skew_metric",
                metric_name=string(col),
                value=val,
                provenance=prov
            ))
        end
    end

    return records
end

function export_replichore_metrics(df::DataFrame, base_prov::Dict, replicon_idx::Dict{String, Dict{String, Any}})
    records = Dict[]
    sort!(df, [:replicon_id, :replichore]; rev=false)

    metrics = [
        ("length_bp", :length_bp),
        ("gc_fraction", :gc_fraction),
        ("x_k_6", :x_k_6)
    ]

    for row in eachrow(df)
        prov = copy(base_prov)
        prov["replicon_id"] = hasproperty(row, :replicon_id) ? string(row.replicon_id) : nothing
        prov["replichore"] = hasproperty(row, :replichore) ? string(row.replichore) : nothing
        prov["source_table"] = "replichore_metrics.csv"
        enrich_replicon_provenance!(prov, replicon_idx)

        for (metric_name, col) in metrics
            hasproperty(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            push!(records, make_knowledge_record(
                record_type="replichore_metric",
                metric_name=metric_name,
                value=val,
                provenance=prov
            ))
        end
    end

    return records
end

function export_ir_enrichment(df::DataFrame, base_prov::Dict, replicon_idx::Dict{String, Dict{String, Any}})
    records = Dict[]
    sort!(df, [:replicon_id]; rev=false)

    metrics = [
        ("ir_count", :ir_count),
        ("ir_density", :ir_density),
        ("baseline_count", :baseline_count),
        ("enrichment_ratio", :enrichment_ratio),
        ("p_value", :p_value)
    ]

    for row in eachrow(df)
        prov = copy(base_prov)
        prov["replicon_id"] = hasproperty(row, :replicon_id) ? string(row.replicon_id) : nothing
        prov["baseline_method"] = hasproperty(row, :baseline_method) ? string(row.baseline_method) : nothing
        prov["stem_min_length"] = hasproperty(row, :stem_min_length) ? safe_int(row.stem_min_length) : nothing
        prov["stem_max_length"] = 12
        prov["loop_min_length"] = 3
        prov["loop_max_length"] = hasproperty(row, :loop_max_length) ? safe_int(row.loop_max_length) : nothing
        prov["source_table"] = "inverted_repeats_summary.csv"
        enrich_replicon_provenance!(prov, replicon_idx)

        for (metric_name, col) in metrics
            hasproperty(row, col) || continue
            val = row[col]
            ismissing(val) && continue

            push!(records, make_knowledge_record(
                record_type="ir_metric",
                metric_name=metric_name,
                value=val,
                provenance=prov
            ))
        end
    end

    return records
end

function main()
    # Parse args
    data_dir = get(ARGS, 1, joinpath(@__DIR__, "..", "..", "data"))
    dataset_dir = length(ARGS) >= 2 ? ARGS[2] : DEFAULT_DATASET_DIR

    pipeline_max_env = parse(Int, get(ENV, "PIPELINE_MAX", "200"))
    pipeline_seed_env = parse(Int, get(ENV, "PIPELINE_SEED", "42"))

    dataset_meta = load_pipeline_metadata(dataset_dir)
    pipeline_max = get(get(dataset_meta, "parameters", Dict{String, Any}()), "max_genomes", pipeline_max_env)
    pipeline_seed = get(get(dataset_meta, "parameters", Dict{String, Any}()), "seed", pipeline_seed_env)

    pipeline_max = safe_int(pipeline_max)
    pipeline_seed = safe_int(pipeline_seed)

    dataset_csv_dir = joinpath(dataset_dir, "csv")
    tables_dir = isfile(joinpath(dataset_csv_dir, "atlas_replicons.csv")) ? dataset_csv_dir : joinpath(data_dir, "tables")

    data_epistemic_dir = joinpath(data_dir, "epistemic")
    mkpath(data_epistemic_dir)

    dataset_epistemic_dir = joinpath(dataset_dir, "epistemic")
    if isdir(dataset_dir)
        mkpath(dataset_epistemic_dir)
    end

    println("Exporting Atlas Knowledge Layer")
    println("  Tables dir: $tables_dir")
    println("  Output dirs:")
    println("    - $data_epistemic_dir")
    if isdir(dataset_dir)
        println("    - $dataset_epistemic_dir")
    end

    # Base provenance
    git_sha = get(dataset_meta, "git_sha", get_git_sha())
    timestamp = get(dataset_meta, "timestamp_utc", Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SS") * "Z")

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
        "window_length" => nothing,
        "k" => nothing,
        "replichore" => nothing,
        "window_size" => nothing,
        "baseline_method" => nothing,
        "stem_min_length" => nothing,
        "stem_max_length" => nothing,
        "loop_min_length" => nothing,
        "loop_max_length" => nothing,
        "source_table" => nothing
    )

    all_records = Dict[]

    replicon_idx = load_replicon_index(tables_dir)

    # Export each table
    tables = [
        ("atlas_replicons.csv", export_replicons),
        ("dicyclic_lifts.csv", export_dicyclic_lifts),
        ("quaternion_results.csv", export_quaternion_results),
        ("kmer_inversion.csv", (df, prov) -> export_kmer_inversion(df, prov, replicon_idx)),
        ("gc_skew_ori_ter.csv", (df, prov) -> export_gc_skew(df, prov, replicon_idx)),
        ("replichore_metrics.csv", (df, prov) -> export_replichore_metrics(df, prov, replicon_idx)),
        ("inverted_repeats_summary.csv", (df, prov) -> export_ir_enrichment(df, prov, replicon_idx)),
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

    function write_jsonl(dir::String)
        mkpath(dir)
        jsonl_path = joinpath(dir, "atlas_knowledge.jsonl")
        open(jsonl_path, "w") do io
            for rec in all_records
                JSON3.write(io, rec)
                println(io)
            end
        end
        println("Wrote $(length(all_records)) records to $jsonl_path")
    end

    write_jsonl(data_epistemic_dir)
    isdir(dataset_dir) && write_jsonl(dataset_epistemic_dir)

    # Write provenance
    prov_meta = Dict(
        "export_timestamp" => timestamp,
        "atlas_git_sha" => git_sha,
        "atlas_version" => ATLAS_VERSION,
        "schema_version" => SCHEMA_VERSION,
        "pipeline_params" => Dict(
            "max" => pipeline_max,
            "seed" => pipeline_seed
        ),
        "dataset_dir" => isdir(dataset_dir) ? dataset_dir : nothing,
        "tables_dir" => tables_dir,
        "tables_exported" => [t[1] for t in tables if isfile(joinpath(tables_dir, t[1]))],
        "total_records" => length(all_records),
        "ncbi_filter" => Dict(
            "assembly_level" => "complete genome",
            "source" => "RefSeq",
            "ftp_path" => "required"
        )
    )

    function write_provenance(dir::String)
        prov_path = joinpath(dir, "atlas_provenance.json")
        open(prov_path, "w") do io
            JSON3.write(io, prov_meta; allow_inf=true)
        end
        println("Wrote provenance to $prov_path")
    end

    write_provenance(data_epistemic_dir)
    isdir(dataset_dir) && write_provenance(dataset_epistemic_dir)

    # Copy schema into output dirs (canonical file is committed under data/epistemic/)
    canonical_schema = joinpath(@__DIR__, "..", "..", "data", "epistemic", "schema_atlas_knowledge.json")
    if isfile(canonical_schema)
        schema_text = read(canonical_schema, String)
        for out_dir in filter(isdir, [data_epistemic_dir, dataset_epistemic_dir])
            open(joinpath(out_dir, "schema_atlas_knowledge.json"), "w") do io
                write(io, schema_text)
            end
        end
    end

    return 0
end

exit(main())
