#!/usr/bin/env julia
"""
Download E. coli genomes from NCBI for validation and analysis.

This script downloads complete E. coli genomes (taxid:562) from NCBI RefSeq,
including diverse strains (K-12, O157:H7, UPEC, etc.) for biological validation.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using DarwinAtlas: RepliconRecord, RepliconType, CHROMOSOME, PLASMID, OTHER, REFSEQ, GENBANK, gc_content
using ArgParse
using Dates
using HTTP
using JSON3
using SHA
using CodecZlib: GzipDecompressorStream
using ProgressMeter
using Random
using FASTX: FASTA
using BioSequences: LongDNA, DNA_N, DNA_A, DNA_C, DNA_G, DNA_T

const NCBI_ASSEMBLY_SUMMARY = "https://ftp.ncbi.nlm.nih.gov/genomes/refseq/bacteria/assembly_summary.txt"
const ECOLI_TAXID = 562

function parse_args()
    s = ArgParseSettings(
        description = "Download E. coli genomes from NCBI",
        prog = "download_ecoli.jl"
    )

    @add_arg_table! s begin
        "--output-dir", "-o"
            help = "Output directory for downloaded genomes"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "data", "ecoli")
        "--max", "-m"
            help = "Maximum number of genomes to download"
            arg_type = Int
            default = 150
        "--seed", "-s"
            help = "Random seed for reproducible sampling"
            arg_type = Int
            default = 42
        "--force"
            help = "Force re-download even if files exist"
            action = :store_true
    end

    return ArgParse.parse_args(s)
end

"""
    query_ecoli_assemblies(max_genomes::Int, seed::Int) -> Vector{Dict}

Query NCBI RefSeq for complete E. coli genomes.
"""
function query_ecoli_assemblies(max_genomes::Int, seed::Int)
    println("  Downloading assembly summary from NCBI RefSeq...")

    try
        # Download assembly summary
        response = HTTP.get(NCBI_ASSEMBLY_SUMMARY; 
            retry=true, retries=3, 
            connect_timeout=30, 
            readtimeout=120)

        lines = split(String(response.body), '\n')

        # Parse header
        header_idx = findfirst(l -> startswith(l, "#assembly_accession"), lines)
        if header_idx === nothing
            error("Could not find header in assembly summary")
        end

        header_line = replace(lines[header_idx], r"^#" => "")
        columns = split(header_line, '\t')

        # Find column indices
        acc_idx = findfirst(==("assembly_accession"), columns)
        level_idx = findfirst(==("assembly_level"), columns)
        ftp_idx = findfirst(==("ftp_path"), columns)
        taxid_idx = findfirst(==("taxid"), columns)
        org_idx = findfirst(==("organism_name"), columns)
        strain_idx = findfirst(==("infraspecific_name"), columns)

        if any(isnothing, [acc_idx, level_idx, ftp_idx, taxid_idx])
            error("Missing required columns in assembly summary")
        end

        # Filter for E. coli complete genomes
        assemblies = Dict{String, Any}[]
        for line in lines[header_idx+1:end]
            isempty(strip(line)) && continue
            startswith(line, '#') && continue

            fields = split(line, '\t')
            length(fields) < max(acc_idx, level_idx, ftp_idx, taxid_idx) && continue

            # Check taxid and assembly level
            taxid = tryparse(Int, fields[taxid_idx])
            if taxid == ECOLI_TAXID && lowercase(fields[level_idx]) == "complete genome"
                ftp_path = fields[ftp_idx]
                ftp_path == "na" && continue

                # Extract strain information
                strain_info = strain_idx !== nothing && length(fields) >= strain_idx ? 
                    fields[strain_idx] : ""
                
                # Parse strain name from infraspecific_name (format: "strain=K-12")
                strain_name = ""
                if !isempty(strain_info)
                    m = match(r"strain=([^;]+)", strain_info)
                    strain_name = m !== nothing ? strip(m.captures[1]) : ""
                end

                # Classify pathotype based on strain name
                pathotype = classify_pathotype(strain_name, org_idx !== nothing ? fields[org_idx] : "")

                push!(assemblies, Dict(
                    "accession" => fields[acc_idx],
                    "ftp_path" => ftp_path,
                    "taxid" => taxid,
                    "organism_name" => org_idx !== nothing ? fields[org_idx] : "Escherichia coli",
                    "strain" => strain_name,
                    "pathotype" => pathotype
                ))
            end
        end

        println("  Found $(length(assemblies)) complete E. coli genomes")

        # Sample if needed
        if length(assemblies) > max_genomes
            rng = Random.MersenneTwister(seed)
            assemblies = Random.shuffle(rng, assemblies)[1:max_genomes]
            println("  Sampled $max_genomes genomes (seed=$seed)")
        end

        return assemblies
    catch e
        error("NCBI assembly summary fetch failed: $e")
    end
end

"""
    classify_pathotype(strain_name::String, organism_name::String) -> String

Classify E. coli pathotype based on strain name and organism name.
"""
function classify_pathotype(strain_name::AbstractString, organism_name::AbstractString)
    combined = lowercase(String(strain_name) * " " * String(organism_name))
    
    # Common pathotypes
    occursin(r"o157:?h7", combined) && return "EHEC_O157H7"
    occursin(r"k-?12", combined) && return "K12_Lab"
    occursin(r"upec|uti89|cft073", combined) && return "UPEC"
    occursin(r"etec", combined) && return "ETEC"
    occursin(r"epec", combined) && return "EPEC"
    occursin(r"eiec", combined) && return "EIEC"
    occursin(r"eaec", combined) && return "EAEC"
    occursin(r"stec", combined) && return "STEC"
    occursin(r"commensal", combined) && return "Commensal"
    
    return "Other"
end

"""
    download_ecoli_genome(assembly, output_dir::String, force::Bool) -> (path, checksum)

Download a single E. coli genome from NCBI FTP.
"""
function download_ecoli_genome(assembly, output_dir::String, force::Bool)
    accession = assembly["accession"]
    ftp_base = assembly["ftp_path"]

    # Convert FTP to HTTPS
    ftp_base = replace(ftp_base, "ftp://" => "https://")
    asm_name = basename(ftp_base)
    fasta_url = "$ftp_base/$(asm_name)_genomic.fna.gz"

    local_path = joinpath(output_dir, "$(accession)_genomic.fna.gz")

    # Skip if already downloaded (unless force)
    if isfile(local_path) && !force
        checksum = bytes2hex(sha256(read(local_path)))
        return (local_path, checksum)
    end

    # Download with retries
    for attempt in 1:3
        try
            HTTP.download(fasta_url, local_path; 
                connect_timeout=30, 
                readtimeout=300)
            break
        catch e
            if attempt == 3
                rethrow(e)
            end
            sleep(2^attempt)  # Exponential backoff
        end
    end

    # Compute checksum
    checksum = bytes2hex(sha256(read(local_path)))

    return (local_path, checksum)
end

"""
    parse_ecoli_fasta(path::String, assembly, checksum::String) -> Vector{RepliconRecord}

Parse E. coli genome FASTA and extract replicon metadata.
"""
function parse_ecoli_fasta(path::String, assembly, checksum::String)::Vector{RepliconRecord}
    records = RepliconRecord[]

    accession = assembly["accession"]
    taxid = assembly["taxid"]
    organism_name = assembly["organism_name"]
    strain = get(assembly, "strain", "")
    pathotype = get(assembly, "pathotype", "Other")

    # Add strain and pathotype to organism name for tracking
    full_name = if !isempty(strain)
        "$organism_name strain $strain [$pathotype]"
    else
        "$organism_name [$pathotype]"
    end

    # Open gzipped FASTA
    open(path, "r") do io
        reader = FASTA.Reader(GzipDecompressorStream(io))

        replicon_idx = 0
        for record in reader
            replicon_idx += 1

            raw_seq = FASTA.sequence(record)
            header = FASTA.description(record)
            
            # Parse sequence and filter ambiguous bases
            seq = try
                seq_raw = LongDNA{4}(raw_seq)
                canonical_bases = [b for b in seq_raw if b in [DNA_A, DNA_C, DNA_G, DNA_T]]
                
                if isempty(canonical_bases)
                    @warn "Skipping replicon $replicon_idx in $accession: empty after filtering"
                    continue
                end
                
                if length(canonical_bases) < length(seq_raw) * 0.95
                    @warn "Replicon $replicon_idx in $accession has >5% ambiguous bases"
                end
                
                LongDNA{4}(canonical_bases)
            catch e
                @warn "Skipping replicon $replicon_idx in $accession: parse error: $e"
                continue
            end

            # Determine replicon type
            rtype = if occursin(r"plasmid"i, header)
                PLASMID
            elseif occursin(r"chromosome"i, header) || replicon_idx == 1
                CHROMOSOME
            else
                OTHER
            end

            # Extract replicon accession
            replicon_accession = extract_replicon_accession(header)

            # Generate stable replicon ID
            replicon_id = "$(accession)_rep$(replicon_idx)"

            push!(records, RepliconRecord(
                accession,
                replicon_id,
                replicon_accession,
                rtype,
                length(seq),
                gc_content(seq),
                Int64(taxid),
                full_name,  # Include strain and pathotype
                REFSEQ,
                today(),
                checksum
            ))
        end

        close(reader)
    end

    return records
end

function extract_replicon_accession(header::AbstractString)
    isempty(header) && return nothing
    tokens = split(header)
    isempty(tokens) && return nothing
    
    token = tokens[1]
    regex = r"([A-Z]{1,4}_[A-Z0-9]+(?:\.\d+)?|[A-Z]{1,4}\d+(?:\.\d+)?)"
    m = match(regex, token)
    if m === nothing
        m = match(regex, header)
    end
    return m === nothing ? nothing : m.match
end

function main()
    args = parse_args()

    println("\n" * "="^60)
    println("E. COLI GENOME DOWNLOADER")
    println("Darwin Atlas - Biological Validation Dataset")
    println("="^60)
    println("Start time: $(now())")
    println()

    output_dir = args["output-dir"]
    max_genomes = args["max"]
    seed = args["seed"]
    force = args["force"]

    # Setup directories
    raw_dir = joinpath(output_dir, "raw")
    manifest_dir = joinpath(output_dir, "manifest")
    mkpath(raw_dir)
    mkpath(manifest_dir)

    manifest_path = joinpath(manifest_dir, "manifest.jsonl")
    checksums_path = joinpath(manifest_dir, "checksums.sha256")
    metadata_path = joinpath(manifest_dir, "download_metadata.json")

    println("Configuration:")
    println("  Output directory: $output_dir")
    println("  Max genomes: $max_genomes")
    println("  Random seed: $seed")
    println("  Force re-download: $force")
    println()

    # Query NCBI for E. coli assemblies
    println("Querying NCBI for E. coli genomes...")
    assemblies = query_ecoli_assemblies(max_genomes, seed)

    if isempty(assemblies)
        error("No E. coli assemblies found!")
    end

    println("\nDownloading $(length(assemblies)) E. coli genomes...")
    
    records = RepliconRecord[]
    checksums = String[]
    failed_downloads = String[]

    p = Progress(length(assemblies); desc="Downloading: ", showspeed=true)

    for assembly in assemblies
        try
            # Download genome
            local_path, checksum = download_ecoli_genome(assembly, raw_dir, force)

            # Parse FASTA
            replicon_records = parse_ecoli_fasta(local_path, assembly, checksum)

            append!(records, replicon_records)
            push!(checksums, "$checksum  $(basename(local_path))")

        catch e
            accession = assembly["accession"]
            @warn "Failed to download $accession: $e"
            push!(failed_downloads, accession)
        end

        next!(p)
    end

    println("\n\nDownload complete!")
    println("  Successfully downloaded: $(length(assemblies) - length(failed_downloads)) genomes")
    println("  Failed downloads: $(length(failed_downloads))")
    println("  Total replicons: $(length(records))")

    # Write manifest (sorted for determinism)
    sort!(records; by=r -> r.replicon_id)
    open(manifest_path, "w") do io
        for rec in records
            JSON3.write(io, rec)
            println(io)
        end
    end
    println("\nManifest written to: $manifest_path")

    # Write checksums
    sort!(checksums)
    open(checksums_path, "w") do io
        for cs in checksums
            println(io, cs)
        end
    end
    println("Checksums written to: $checksums_path")

    # Write download metadata
    metadata = Dict(
        "timestamp_utc" => Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SS") * "Z",
        "taxid" => ECOLI_TAXID,
        "organism" => "Escherichia coli",
        "seed" => seed,
        "max_genomes" => max_genomes,
        "assemblies_queried" => length(assemblies),
        "assemblies_downloaded" => length(assemblies) - length(failed_downloads),
        "replicons_extracted" => length(records),
        "failed_downloads" => failed_downloads,
        "ncbi_source" => NCBI_ASSEMBLY_SUMMARY,
        "download_policy" => Dict(
            "retries" => 3,
            "connect_timeout_s" => 30,
            "readtimeout_s" => 300,
            "backoff" => "exponential (2^attempt seconds)"
        )
    )

    open(metadata_path, "w") do io
        JSON3.write(io, metadata; allow_inf=true)
    end
    println("Metadata written to: $metadata_path")

    # Generate summary statistics
    println("\n" * "="^60)
    println("DATASET SUMMARY")
    println("="^60)
    
    # Count by replicon type
    n_chromosomes = count(r -> r.replicon_type == CHROMOSOME, records)
    n_plasmids = count(r -> r.replicon_type == PLASMID, records)
    n_other = count(r -> r.replicon_type == OTHER, records)
    
    println("Replicon types:")
    println("  Chromosomes: $n_chromosomes")
    println("  Plasmids: $n_plasmids")
    println("  Other: $n_other")
    
    # Count by pathotype (extract from taxonomy_name)
    pathotype_counts = Dict{String, Int}()
    for rec in records
        m = match(r"\[([^\]]+)\]$", rec.taxonomy_name)
        pathotype = m !== nothing ? m.captures[1] : "Unknown"
        pathotype_counts[pathotype] = get(pathotype_counts, pathotype, 0) + 1
    end
    
    println("\nPathotypes represented:")
    for (pathotype, count) in sort(collect(pathotype_counts); by=x->x[2], rev=true)
        println("  $pathotype: $count replicons")
    end
    
    # Length statistics
    lengths = [r.length_bp for r in records]
    println("\nReplicon length statistics:")
    println("  Min: $(minimum(lengths)) bp")
    println("  Max: $(maximum(lengths)) bp")
    println("  Mean: $(round(Int, sum(lengths) / length(lengths))) bp")
    println("  Median: $(round(Int, sort(lengths)[div(length(lengths), 2)])) bp")
    
    # GC content statistics
    gc_values = [r.gc_fraction for r in records]
    println("\nGC content statistics:")
    println("  Min: $(round(minimum(gc_values) * 100, digits=2))%")
    println("  Max: $(round(maximum(gc_values) * 100, digits=2))%")
    println("  Mean: $(round(sum(gc_values) / length(gc_values) * 100, digits=2))%")

    println("\n" * "="^60)
    println("End time: $(now())")
    println("="^60)
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
