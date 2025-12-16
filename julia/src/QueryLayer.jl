"""
    QueryLayer.jl

DuckDB-based query interface for Atlas datasets.

Provides SQL access to Parquet files for fast aggregations and filtering.
"""

using DuckDB
using DataFrames

export AtlasQueryContext, query_atlas, register_atlas_tables
export example_queries

"""
    AtlasQueryContext

Holds DuckDB connection with registered Atlas tables.
"""
struct AtlasQueryContext
    db::DuckDB.DB
    base_path::String
    tables::Vector{String}
end

"""
    AtlasQueryContext(base_path::String) -> AtlasQueryContext

Create query context from Atlas dataset path.
"""
function AtlasQueryContext(base_path::String)
    db = DuckDB.DB()
    tables = register_atlas_tables(db, base_path)
    return AtlasQueryContext(db, base_path, tables)
end

"""
    register_atlas_tables(db::DuckDB.DB, base_path::String) -> Vector{String}

Register all Parquet tables as DuckDB views.
"""
function register_atlas_tables(db::DuckDB.DB, base_path::String)::Vector{String}
    partitions_dir = joinpath(base_path, "partitions")
    registered = String[]

    if !isdir(partitions_dir)
        @warn "No partitions directory found at $partitions_dir"
        return registered
    end

    for entry in readdir(partitions_dir)
        table_path = joinpath(partitions_dir, entry)
        if isdir(table_path)
            # Use glob pattern to read all parquet files in partition tree
            pattern = joinpath(table_path, "**", "*.parquet")

            # Create view
            view_sql = """
                CREATE OR REPLACE VIEW $entry AS
                SELECT * FROM read_parquet('$pattern', hive_partitioning=true)
            """

            try
                DuckDB.execute(db, view_sql)
                push!(registered, entry)
            catch e
                @warn "Failed to register table $entry: $e"
            end
        end
    end

    return registered
end

"""
    query_atlas(ctx::AtlasQueryContext, sql::String) -> DataFrame

Execute SQL query against Atlas dataset.
"""
function query_atlas(ctx::AtlasQueryContext, sql::String)::DataFrame
    result = DuckDB.execute(ctx.db, sql)
    return DataFrame(result)
end

"""
    query_atlas(base_path::String, sql::String) -> DataFrame

One-shot query: create context, run query, return result.
"""
function query_atlas(base_path::String, sql::String)::DataFrame
    ctx = AtlasQueryContext(base_path)
    return query_atlas(ctx, sql)
end

"""
    example_queries() -> Dict{String, String}

Return example queries for Atlas dataset.
"""
function example_queries()::Dict{String, String}
    Dict(
        "count_by_type" => """
            SELECT replicon_type, COUNT(*) as count
            FROM atlas_replicons
            GROUP BY replicon_type
            ORDER BY count DESC
        """,

        "gc_distribution" => """
            SELECT
                FLOOR(gc_fraction * 20) / 20 as gc_bin,
                COUNT(*) as count,
                AVG(length_bp) as avg_length
            FROM atlas_replicons
            GROUP BY gc_bin
            ORDER BY gc_bin
        """,

        "length_stats_by_type" => """
            SELECT
                replicon_type,
                COUNT(*) as count,
                MIN(length_bp) as min_length,
                AVG(length_bp) as avg_length,
                MAX(length_bp) as max_length
            FROM atlas_replicons
            GROUP BY replicon_type
        """,

        "top_taxa" => """
            SELECT
                taxonomy_id,
                COUNT(*) as replicon_count,
                SUM(length_bp) as total_bp
            FROM atlas_replicons
            GROUP BY taxonomy_id
            ORDER BY replicon_count DESC
            LIMIT 20
        """,

        "plasmid_size_distribution" => """
            SELECT
                length_bin,
                COUNT(*) as count
            FROM atlas_replicons
            WHERE replicon_type = 'PLASMID'
            GROUP BY length_bin
            ORDER BY length_bin
        """,

        "kmer_inversion_by_k" => """
            SELECT
                k,
                AVG(x_k) as mean_inversion,
                STDDEV(x_k) as std_inversion,
                COUNT(*) as n
            FROM kmer_inversion
            GROUP BY k
            ORDER BY k
        """,

        "gc_skew_confidence" => """
            SELECT
                CASE
                    WHEN ori_confidence < 0.5 THEN 'low'
                    WHEN ori_confidence < 0.8 THEN 'medium'
                    ELSE 'high'
                END as confidence_level,
                COUNT(*) as count
            FROM gc_skew_ori_ter
            GROUP BY confidence_level
        """,

        "ir_enrichment_outliers" => """
            SELECT
                replicon_id,
                ir_count,
                enrichment_ratio,
                p_value
            FROM inverted_repeats_summary
            WHERE enrichment_ratio > 2.0 AND p_value < 0.05
            ORDER BY enrichment_ratio DESC
            LIMIT 50
        """
    )
end

"""
    run_example_queries(ctx::AtlasQueryContext; verbose::Bool=true)

Run all example queries and print results.
"""
function run_example_queries(ctx::AtlasQueryContext; verbose::Bool=true)
    results = Dict{String, DataFrame}()

    for (name, sql) in example_queries()
        try
            df = query_atlas(ctx, sql)
            results[name] = df

            if verbose
                println("\n=== $name ===")
                println(sql)
                println("---")
                println(first(df, 10))
            end
        catch e
            if verbose
                println("\n=== $name === (FAILED)")
                println("Error: $e")
            end
        end
    end

    return results
end

"""
    schema_info(ctx::AtlasQueryContext) -> DataFrame

Get schema information for all registered tables.
"""
function schema_info(ctx::AtlasQueryContext)::DataFrame
    results = DataFrame[]

    for table in ctx.tables
        try
            sql = "DESCRIBE $table"
            df = query_atlas(ctx, sql)
            df.table_name .= table
            push!(results, df)
        catch e
            @warn "Failed to describe $table: $e"
        end
    end

    return isempty(results) ? DataFrame() : vcat(results...)
end
