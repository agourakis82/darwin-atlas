"""
    Storage.jl

Parquet-based storage with partition support for scale.

Partition strategy:
- source_db: refseq | genbank
- replicon_type: chromosome | plasmid | other
- length_bin: 0-50kb | 50-200kb | 200-1000kb | gt1Mb
"""

using DataFrames
using Parquet2
using Arrow
using Dates
using SHA

export write_partitioned_parquet, read_partitioned_parquet
export write_csv_view, get_length_bin
export AtlasDataset, write_atlas_dataset, read_atlas_dataset

# Length bin boundaries (bp)
const LENGTH_BINS = [
    (0, 50_000, "0-50kb"),
    (50_000, 200_000, "50-200kb"),
    (200_000, 1_000_000, "200-1000kb"),
    (1_000_000, typemax(Int64), "gt1Mb")
]

"""
    get_length_bin(length_bp::Integer) -> String

Assign a length bin based on sequence length.
"""
function get_length_bin(length_bp::Integer)::String
    for (lo, hi, label) in LENGTH_BINS
        if lo <= length_bp < hi
            return label
        end
    end
    return "gt1Mb"
end

"""
    AtlasDataset

Container for all Atlas tables in a versioned dataset.
"""
struct AtlasDataset
    version::String
    base_path::String
    timestamp::DateTime
    git_sha::String
    params::Dict{String, Any}
end

"""
    write_partitioned_parquet(df::DataFrame, base_path::String;
        partition_cols::Vector{Symbol}=Symbol[],
        table_name::String="data"
    )

Write DataFrame to partitioned Parquet files.

Partition columns are used to create directory structure:
  base_path/partition_col1=value1/partition_col2=value2/data.parquet
"""
function write_partitioned_parquet(
    df::DataFrame,
    base_path::String;
    partition_cols::Vector{Symbol}=Symbol[],
    table_name::String="data"
)
    if isempty(partition_cols)
        # No partitioning - write single file
        mkpath(base_path)
        path = joinpath(base_path, "$table_name.parquet")
        Parquet2.writefile(path, df)
        return [path]
    end

    # Group by partition columns
    grouped = groupby(df, partition_cols)
    paths = String[]

    for group in grouped
        # Build partition path
        partition_path = base_path
        for col in partition_cols
            val = string(first(group[!, col]))
            # Sanitize value for filesystem
            val = replace(val, r"[^a-zA-Z0-9_-]" => "_")
            partition_path = joinpath(partition_path, "$(col)=$(val)")
        end
        mkpath(partition_path)

        # Remove partition columns from data (they're in the path)
        data = select(group, Not(partition_cols))

        # Write parquet
        path = joinpath(partition_path, "$table_name.parquet")
        Parquet2.writefile(path, DataFrame(data))
        push!(paths, path)
    end

    return paths
end

"""
    read_partitioned_parquet(base_path::String) -> DataFrame

Read all Parquet files from a partitioned directory structure.
Reconstructs partition column values from directory names.
"""
function read_partitioned_parquet(base_path::String)::DataFrame
    parquet_files = String[]

    # Find all .parquet files
    for (root, dirs, files) in walkdir(base_path)
        for f in files
            if endswith(f, ".parquet")
                push!(parquet_files, joinpath(root, f))
            end
        end
    end

    if isempty(parquet_files)
        return DataFrame()
    end

    dfs = DataFrame[]
    for path in parquet_files
        df = DataFrame(Parquet2.readfile(path))

        # Extract partition columns from path
        rel_path = relpath(dirname(path), base_path)
        for part in split(rel_path, Base.Filesystem.path_separator)
            if contains(part, "=")
                col, val = split(part, "=", limit=2)
                df[!, Symbol(col)] .= val
            end
        end

        push!(dfs, df)
    end

    return vcat(dfs...; cols=:union)
end

"""
    write_csv_view(df::DataFrame, path::String)

Write DataFrame as CSV for compatibility with tools that don't support Parquet.
"""
function write_csv_view(df::DataFrame, path::String)
    mkpath(dirname(path))
    CSV.write(path, df)
    return path
end

"""
    write_atlas_dataset(
        tables::Dict{String, DataFrame},
        base_path::String;
        version::String="2.0.0",
        git_sha::String="unknown",
        params::Dict{String, Any}=Dict()
    ) -> AtlasDataset

Write complete Atlas dataset with Parquet partitions and CSV views.

Tables expected:
- "atlas_replicons" -> partitioned by source_db, replicon_type, length_bin
- "kmer_inversion" -> partitioned by source_db, k (when available)
- "gc_skew_ori_ter" -> partitioned by source_db
- "inverted_repeats_summary" -> partitioned by source_db
"""
function write_atlas_dataset(
    tables::Dict{String, DataFrame},
    base_path::String;
    version::String="2.0.0",
    git_sha::String="unknown",
    params::Dict{String, Any}=Dict()
)::AtlasDataset
    timestamp = now(UTC)

    # Create directory structure
    partitions_dir = joinpath(base_path, "partitions")
    csv_dir = joinpath(base_path, "csv")
    manifest_dir = joinpath(base_path, "manifest")

    mkpath(partitions_dir)
    mkpath(csv_dir)
    mkpath(manifest_dir)

    written_files = String[]

    # Write each table
    for (name, df) in tables
        if nrow(df) == 0
            continue
        end

        # Determine partition strategy
        partition_cols = get_partition_strategy(name, df)

        # Add derived partition columns if needed
        df_part = prepare_for_partitioning(name, df)

        # Write partitioned Parquet
        parquet_path = joinpath(partitions_dir, name)
        paths = write_partitioned_parquet(df_part, parquet_path;
            partition_cols=partition_cols, table_name="data")
        append!(written_files, paths)

        # Write CSV view (full table, no partitioning)
        csv_path = joinpath(csv_dir, "$name.csv")
        write_csv_view(df, csv_path)
        push!(written_files, csv_path)

        println("  Wrote $name: $(nrow(df)) rows, $(length(paths)) partition(s)")
    end

    # Write manifest
    manifest = Dict{String, Any}(
        "version" => version,
        "timestamp_utc" => Dates.format(timestamp, "yyyy-mm-ddTHH:MM:SSZ"),
        "git_sha" => git_sha,
        "params" => params,
        "tables" => Dict(
            name => Dict(
                "rows" => nrow(df),
                "columns" => names(df),
                "partition_cols" => get_partition_strategy(name, df)
            )
            for (name, df) in tables if nrow(df) > 0
        )
    )

    manifest_path = joinpath(manifest_dir, "dataset_manifest.json")
    open(manifest_path, "w") do io
        JSON3.write(io, manifest; allow_inf=true)
    end

    # Write checksums
    checksums_path = joinpath(manifest_dir, "checksums.sha256")
    open(checksums_path, "w") do io
        for path in written_files
            if isfile(path)
                hash = bytes2hex(sha256(read(path)))
                rel = relpath(path, base_path)
                println(io, "$hash  $rel")
            end
        end
    end

    return AtlasDataset(version, base_path, timestamp, git_sha, params)
end

"""
    get_partition_strategy(table_name::String, df::DataFrame) -> Vector{Symbol}

Determine partition columns for a table.
"""
function get_partition_strategy(table_name::String, df::DataFrame)::Vector{Symbol}
    available = Symbol.(names(df))

    strategy = if table_name == "atlas_replicons"
        [:source_db, :replicon_type, :length_bin]
    elseif table_name == "kmer_inversion"
        [:source_db, :k]
    elseif table_name in ["gc_skew_ori_ter", "replichore_metrics", "inverted_repeats_summary"]
        [:source_db]
    else
        Symbol[]
    end

    # Return only columns that exist
    return filter(c -> c in available, strategy)
end

"""
    prepare_for_partitioning(table_name::String, df::DataFrame) -> DataFrame

Add derived columns needed for partitioning.
"""
function prepare_for_partitioning(table_name::String, df::DataFrame)::DataFrame
    df = copy(df)

    # Add source_db if missing (default to REFSEQ)
    if !hasproperty(df, :source_db)
        if hasproperty(df, :source)
            df.source_db = string.(df.source)
        else
            df.source_db = fill("REFSEQ", nrow(df))
        end
    else
        df.source_db = string.(df.source_db)
    end

    # Add replicon_type as string if enum
    if hasproperty(df, :replicon_type) && eltype(df.replicon_type) != String
        df.replicon_type = string.(df.replicon_type)
    end

    # Add length_bin if length_bp exists
    if hasproperty(df, :length_bp) && !hasproperty(df, :length_bin)
        df.length_bin = get_length_bin.(df.length_bp)
    end

    return df
end

"""
    read_atlas_dataset(base_path::String) -> Dict{String, DataFrame}

Read all tables from an Atlas dataset.
"""
function read_atlas_dataset(base_path::String)::Dict{String, DataFrame}
    partitions_dir = joinpath(base_path, "partitions")
    tables = Dict{String, DataFrame}()

    if !isdir(partitions_dir)
        return tables
    end

    for entry in readdir(partitions_dir)
        table_path = joinpath(partitions_dir, entry)
        if isdir(table_path)
            df = read_partitioned_parquet(table_path)
            if nrow(df) > 0
                tables[entry] = df
            end
        end
    end

    return tables
end
