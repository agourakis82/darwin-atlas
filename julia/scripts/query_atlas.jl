#!/usr/bin/env julia
"""
    query_atlas.jl

Query Atlas dataset using DuckDB SQL.

Usage:
    julia query_atlas.jl "SELECT * FROM atlas_replicons LIMIT 10"
    julia query_atlas.jl --example count_by_type
    julia query_atlas.jl --list-examples
    julia query_atlas.jl --schema
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using ArgParse
using DataFrames
using CSV

# Include modules
include(joinpath(@__DIR__, "..", "src", "Storage.jl"))
include(joinpath(@__DIR__, "..", "src", "QueryLayer.jl"))

function parse_args()
    s = ArgParseSettings(
        description = "Query Atlas dataset with SQL",
        prog = "query_atlas.jl"
    )

    @add_arg_table! s begin
        "query"
            help = "SQL query to execute"
            arg_type = String
            default = ""
        "--dataset", "-d"
            help = "Path to Atlas dataset"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "dist", "atlas_dataset_v2")
        "--example", "-e"
            help = "Run named example query"
            arg_type = String
            default = ""
        "--list-examples"
            help = "List available example queries"
            action = :store_true
        "--schema"
            help = "Show schema for all tables"
            action = :store_true
        "--output", "-o"
            help = "Output results to CSV file"
            arg_type = String
            default = ""
        "--limit", "-n"
            help = "Limit number of rows to display"
            arg_type = Int
            default = 100
    end

    return ArgParse.parse_args(s)
end

function main()
    args = parse_args()

    # List examples mode
    if args["list-examples"]
        println("Available example queries:")
        println("-" ^ 40)
        for (name, sql) in example_queries()
            println("\n$name:")
            println("  $(replace(sql, "\n" => "\n  "))")
        end
        return 0
    end

    dataset_path = args["dataset"]

    # Check dataset exists
    if !isdir(dataset_path)
        println("Error: Dataset not found at $dataset_path")
        println("Run 'make atlas MAX=50 SEED=42' first to generate the dataset.")
        return 1
    end

    # Create query context
    println("Loading Atlas dataset from: $dataset_path")
    ctx = AtlasQueryContext(dataset_path)
    println("Registered tables: $(join(ctx.tables, ", "))")
    println()

    # Schema mode
    if args["schema"]
        println("Table schemas:")
        println("-" ^ 60)
        schema = schema_info(ctx)
        if nrow(schema) > 0
            for g in groupby(schema, :table_name)
                println("\n$(first(g.table_name)):")
                for row in eachrow(g)
                    println("  $(row.column_name): $(row.column_type)")
                end
            end
        else
            println("No schema information available")
        end
        return 0
    end

    # Determine query
    sql = if !isempty(args["example"])
        examples = example_queries()
        if haskey(examples, args["example"])
            examples[args["example"]]
        else
            println("Error: Unknown example '$(args["example"])'")
            println("Available: $(join(keys(examples), ", "))")
            return 1
        end
    elseif !isempty(args["query"])
        args["query"]
    else
        println("Error: No query specified")
        println("Usage: julia query_atlas.jl \"SELECT * FROM atlas_replicons LIMIT 10\"")
        println("       julia query_atlas.jl --example count_by_type")
        println("       julia query_atlas.jl --list-examples")
        return 1
    end

    # Execute query
    println("Query:")
    println("-" ^ 60)
    println(sql)
    println("-" ^ 60)
    println()

    try
        result = query_atlas(ctx, sql)

        # Output to file if specified
        if !isempty(args["output"])
            CSV.write(args["output"], result)
            println("Results written to: $(args["output"])")
            println("$(nrow(result)) rows")
        else
            # Display results
            n_rows = nrow(result)
            limit = args["limit"]

            if n_rows <= limit
                println(result)
            else
                println("Showing first $limit of $n_rows rows:")
                println(first(result, limit))
            end

            println("\n$(n_rows) row(s) returned")
        end

    catch e
        println("Query error: $e")
        return 1
    end

    return 0
end

exit(main())
