"""
    DoriC.jl

DoriC (oriC database) ingestion and label generation.

Pipeline:
1) Download DoriC archive (RAR)
2) Extract CSV tables (bacteria/archaea/plasmid)
3) Parse origin locations
4) Join with local replicon manifest
5) Emit labels table + provenance metadata
"""

using CSV
using CodecZlib: GzipDecompressorStream
using DataFrames
using Dates
using FASTX: FASTA
using HTTP
using JSON3
using Parquet2
using SHA

export fetch_doric, build_doric_labels

const DORIC_VERSION = "10"
const DORIC_ARCHIVE_NAME = "doric10.rar"
const DORIC_DEFAULT_URL = "https://tubic.org/doric10/public/static/download/doric10.rar"

const DORIC_TABLES = Dict(
    "bacteria" => "tubic_bacteria.csv",
    "archaea" => "tubic_archaea.csv",
    "plasmid" => "tubic_plasmid.csv"
)

struct DoriCDownload
    archive_path::String
    extract_dir::String
    url::String
    version::String
    sha256::String
end

function sha256_file(path::String)::String
    open(path, "r") do io
        return bytes2hex(SHA.sha256(io))
    end
end

function ensure_7z()
    if Sys.which("7z") === nothing
        error("7z not found. Install 7zip/7zip-rar to extract DoriC archive.")
    end
end

function download_file(url::String, dest::String)
    resp = HTTP.get(url; headers=Dict("User-Agent" => "Mozilla/5.0"))
    if resp.status != 200
        error("Failed to download DoriC: HTTP $(resp.status)")
    end
    open(dest, "w") do io
        write(io, resp.body)
    end
end

"""
    fetch_doric(; data_dir="data", url=DORIC_DEFAULT_URL, version=DORIC_VERSION, force=false) -> DoriCDownload

Download DoriC archive (RAR) into `data/doric/`.
"""
function fetch_doric(; data_dir::String="data", url::String=DORIC_DEFAULT_URL,
    version::String=DORIC_VERSION, force::Bool=false)::DoriCDownload

    doric_dir = joinpath(data_dir, "doric")
    mkpath(doric_dir)

    archive_path = joinpath(doric_dir, DORIC_ARCHIVE_NAME)
    extract_dir = joinpath(doric_dir, "doric$(version)")

    if force || !isfile(archive_path)
        println("Downloading DoriC archive...")
        download_file(url, archive_path)
    end

    sha = sha256_file(archive_path)
    return DoriCDownload(archive_path, extract_dir, url, version, sha)
end

function extract_doric(archive::DoriCDownload; force::Bool=false)
    if isdir(archive.extract_dir) && !force
        return
    end
    ensure_7z()
    mkpath(dirname(archive.extract_dir))
    run(`7z x -y -o$(dirname(archive.extract_dir)) $(archive.archive_path)`)
end

function parse_origin_range(loc::AbstractString)
    nums = [parse(Int, m.match) for m in eachmatch(r"\d+", loc)]
    if length(nums) < 2
        return nothing
    end
    return (nums[1], nums[2])
end

function load_doric_tables(extract_dir::String)
    dfs = DataFrame[]
    for (source, file) in DORIC_TABLES
        path = joinpath(extract_dir, file)
        isfile(path) || error("Missing DoriC file: $path")
        df = DataFrame(CSV.File(path))
        rename!(df, Dict(
            "doricAC" => :doric_accession,
            "Refseq" => :refseq_accession,
            "Organism" => :organism,
            "Lineage" => :lineage,
            "Location of replication origin" => :ori_location,
            "OriC AT content" => :ori_at_content,
            "Location of replication genes" => :replication_genes,
            "OriC sequence" => :ori_sequence
        ))
        df[!, :doric_source] .= source
        push!(dfs, df)
    end
    return vcat(dfs...; cols=:union)
end

function load_replicon_manifest(data_dir::String)::DataFrame
    manifest_path = joinpath(data_dir, "manifest", "manifest.jsonl")
    isfile(manifest_path) || error("Missing manifest: $manifest_path")

    rows = Dict{Symbol, Any}[]
    open(manifest_path, "r") do io
        for line in eachline(io)
            isempty(strip(line)) && continue
            obj = JSON3.read(line)
            row = Dict{Symbol, Any}(Symbol(k) => v for (k, v) in pairs(obj))
            push!(rows, row)
        end
    end
    df = DataFrame(rows)
    return df
end

function strip_version(accession::AbstractString)::String
    return replace(accession, r"\.\d+$" => "")
end

function extract_accession_from_header(header::AbstractString)
    token = split(header)[1]
    regex = r"([A-Z]{1,4}_[A-Z0-9]+(?:\.\d+)?|[A-Z]{1,4}\d+(?:\.\d+)?)"
    m = match(regex, token)
    if m === nothing
        m = match(regex, header)
    end
    return m === nothing ? nothing : m.match
end

function extract_accessions_from_fasta(path::String)
    accessions = String[]
    open(path, "r") do io
        reader = FASTA.Reader(GzipDecompressorStream(io))
        for record in reader
            header = FASTA.description(record)
            acc = extract_accession_from_header(header)
            push!(accessions, acc === nothing ? "" : acc)
        end
    end
    return accessions
end

function parse_replicon_index(replicon_id::AbstractString)
    m = match(r"_rep(\d+)$", replicon_id)
    return m === nothing ? nothing : parse(Int, m.captures[1])
end

function augment_replicon_accessions!(df::DataFrame, data_dir::String)
    raw_dir = joinpath(data_dir, "raw")
    missing_rows = findall(row -> !(row.replicon_accession isa AbstractString) || isempty(row.replicon_accession), eachrow(df))
    if isempty(missing_rows)
        return
    end

    println("Augmenting missing replicon_accession from raw FASTA...")

    grouped = groupby(df, :assembly_accession)
    for group in grouped
        assembly = first(group.assembly_accession)
        if !(assembly isa AbstractString) || isempty(assembly)
            continue
        end
        raw_path = joinpath(raw_dir, "$(assembly)_genomic.fna.gz")
        isfile(raw_path) || continue

        accessions = extract_accessions_from_fasta(raw_path)
        for row in eachrow(group)
            if row.replicon_accession isa AbstractString && !isempty(row.replicon_accession)
                continue
            end
            idx = parse_replicon_index(row.replicon_id)
            if idx === nothing || idx > length(accessions)
                continue
            end
            acc = accessions[idx]
            if !isempty(acc)
                row.replicon_accession = acc
            end
        end
    end
end

function circular_span(start_bp::Int, end_bp::Int, length_bp::Int)::Int
    if start_bp <= end_bp
        return end_bp - start_bp + 1
    end
    return (length_bp - start_bp + 1) + end_bp
end

function circular_midpoint(start_bp::Int, end_bp::Int, length_bp::Int)::Int
    span = circular_span(start_bp, end_bp, length_bp)
    offset = span ÷ 2
    mid = start_bp + offset
    if mid > length_bp
        mid -= length_bp
    end
    return mid
end

function build_labels(doric_df::DataFrame, replicons_df::DataFrame, version::String)
    rep_by_acc = Dict{String, NamedTuple}()
    rep_by_nover = Dict{String, NamedTuple}()

    for row in eachrow(replicons_df)
        acc = row.replicon_accession
        if acc isa AbstractString && !isempty(acc)
            rep_by_acc[acc] = row
            rep_by_nover[strip_version(acc)] = row
        end
    end

    fields = Dict(
        :replicon_id => String[],
        :assembly_accession => String[],
        :replicon_accession => String[],
        :replicon_type => String[],
        :source_db => String[],
        :length_bp => Int[],
        :taxonomy_id => Int[],
        :organism_name => String[],
        :doric_accession => String[],
        :doric_source => String[],
        :ori_start_bp => Int[],
        :ori_end_bp => Int[],
        :ori_center_bp => Int[],
        :ori_span_bp => Int[],
        :ori_wrapped => Bool[],
        :ori_at_content => Union{Missing, Float64}[],
        :label_tier => String[],
        :label_source => String[],
        :label_version => String[],
        :label_confidence => Float64[],
        :ter_bp => Int[],
        :ter_derived => Bool[],
        :match_method => String[],
        :ori_rank => Int[]
    )

    per_rep_count = Dict{String, Int}()
    matched = 0
    unmatched = 0

    for row in eachrow(doric_df)
        ref_raw = row.refseq_accession
        if !(ref_raw isa AbstractString) || isempty(ref_raw)
            unmatched += 1
            continue
        end
        ref = String(ref_raw)

        match = get(rep_by_acc, ref, nothing)
        match_method = "exact"
        if match === nothing
            match = get(rep_by_nover, strip_version(ref), nothing)
            match_method = "nover"
        end

        if match === nothing
            unmatched += 1
            continue
        end

        loc = row.ori_location
        loc isa AbstractString || continue
        range = parse_origin_range(loc)
        range === nothing && continue

        start_bp, end_bp = range
        length_bp = match.length_bp
        wrapped = start_bp > end_bp
        span = circular_span(start_bp, end_bp, length_bp)
        center = circular_midpoint(start_bp, end_bp, length_bp)
        ter = ((center - 1 + length_bp ÷ 2) % length_bp) + 1

        key = match.replicon_id
        rank = get(per_rep_count, key, 0) + 1
        per_rep_count[key] = rank

        push!(fields[:replicon_id], match.replicon_id)
        push!(fields[:assembly_accession], match.assembly_accession)
        push!(fields[:replicon_accession], match.replicon_accession)
        push!(fields[:replicon_type], match.replicon_type)
        push!(fields[:source_db], match.source_db)
        push!(fields[:length_bp], length_bp)
        push!(fields[:taxonomy_id], match.taxonomy_id)
        push!(fields[:organism_name], match.taxonomy_name)
        push!(fields[:doric_accession], String(row.doric_accession))
        push!(fields[:doric_source], String(row.doric_source))
        push!(fields[:ori_start_bp], start_bp)
        push!(fields[:ori_end_bp], end_bp)
        push!(fields[:ori_center_bp], center)
        push!(fields[:ori_span_bp], span)
        push!(fields[:ori_wrapped], wrapped)
        push!(fields[:ori_at_content], parse_optional_float(row.ori_at_content))
        push!(fields[:label_tier], "A")
        push!(fields[:label_source], "DoriC")
        push!(fields[:label_version], version)
        push!(fields[:label_confidence], 1.0)
        push!(fields[:ter_bp], ter)
        push!(fields[:ter_derived], true)
        push!(fields[:match_method], match_method)
        push!(fields[:ori_rank], rank)

        matched += 1
    end

    labels = DataFrame(fields)
    report = Dict(
        "doric_rows" => nrow(doric_df),
        "matched" => matched,
        "unmatched" => unmatched,
        "replicons" => nrow(replicons_df)
    )
    return labels, report
end

function parse_optional_float(val)
    if val isa AbstractString
        return tryparse(Float64, val)
    elseif val isa Number
        return Float64(val)
    else
        return missing
    end
end

"""
    build_doric_labels(; data_dir="data", metadata_dir="metadata", url=DORIC_DEFAULT_URL,
        version=DORIC_VERSION, force_download=false, force_extract=false, force_build=false)

Build ori/ter label table from DoriC and write versioned metadata outputs.
"""
function build_doric_labels(; data_dir::String="data", metadata_dir::String="metadata",
    url::String=DORIC_DEFAULT_URL, version::String=DORIC_VERSION,
    force_download::Bool=false, force_extract::Bool=false, force_build::Bool=false,
    augment_accessions::Bool=true)

    archive = fetch_doric(data_dir=data_dir, url=url, version=version, force=force_download)
    extract_doric(archive; force=force_extract)

    mkpath(metadata_dir)

    labels_path = joinpath(metadata_dir, "labels_oriter.parquet")
    if isfile(labels_path) && !force_build
        println("Labels already exist: $labels_path")
        return labels_path
    end

    doric_df = load_doric_tables(archive.extract_dir)
    replicons_df = load_replicon_manifest(data_dir)
    if augment_accessions
        augment_replicon_accessions!(replicons_df, data_dir)
    end
    labels, report = build_labels(doric_df, replicons_df, version)

    Parquet2.writefile(labels_path, labels)

    version_path = joinpath(metadata_dir, "doric_version.json")
    version_info = Dict(
        "version" => version,
        "url" => archive.url,
        "archive_path" => archive.archive_path,
        "archive_sha256" => archive.sha256,
        "downloaded_at_utc" => Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SS") * "Z",
        "tables" => DORIC_TABLES,
        "n_labels" => nrow(labels)
    )
    open(version_path, "w") do io
        JSON3.write(io, version_info; allow_inf=true)
    end

    report_path = joinpath(metadata_dir, "doric_coverage.json")
    open(report_path, "w") do io
        JSON3.write(io, report; allow_inf=true)
    end

    println("Wrote labels: $labels_path")
    println("Coverage: $(report["matched"])/$(report["doric_rows"]) matched")

    return labels_path
end
