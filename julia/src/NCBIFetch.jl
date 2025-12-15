"""
    NCBIFetch.jl

NCBI genome download and manifest management.

Downloads complete bacterial genomes from NCBI RefSeq/GenBank
with full provenance tracking.
"""

using HTTP
using JSON3
using SHA
using Dates
using CodecZlib: GzipDecompressorStream
using ProgressMeter
using Random
using FASTX: FASTA
using BioSequences: LongDNA

const NCBI_DATASETS_API = "https://api.ncbi.nlm.nih.gov/datasets/v2"
const NCBI_FTP_BASE = "https://ftp.ncbi.nlm.nih.gov/genomes/all"
const NCBI_ASSEMBLY_SUMMARY = "https://ftp.ncbi.nlm.nih.gov/genomes/refseq/bacteria/assembly_summary.txt"

"""
    fetch_ncbi(;
        output_dir::String,
        max_genomes::Int=200,
        seed::Int=42,
        taxon::String="bacteria",
        assembly_level::String="complete"
    ) -> Vector{RepliconRecord}

Download complete bacterial genomes from NCBI.

# Arguments
- `output_dir`: Directory to store downloaded genomes
- `max_genomes`: Maximum number of genomes to download
- `seed`: Random seed for reproducible sampling
- `taxon`: Taxonomic group (default: "bacteria")
- `assembly_level`: Assembly completeness (default: "complete")

# Returns
Vector of `RepliconRecord` with metadata for each downloaded replicon.

# Side Effects
- Creates `output_dir` if it doesn't exist
- Downloads genome FASTA files to `output_dir/raw/`
- Creates/updates manifest at `output_dir/manifest/manifest.jsonl`
- Creates checksums file at `output_dir/manifest/checksums.sha256`
"""
function fetch_ncbi(;
    output_dir::String,
    max_genomes::Int=200,
    seed::Int=42,
    taxon::String="bacteria",
    assembly_level::String="complete"
)::Vector{RepliconRecord}

    # Setup directories
    raw_dir = joinpath(output_dir, "raw")
    manifest_dir = joinpath(output_dir, "manifest")
    mkpath(raw_dir)
    mkpath(manifest_dir)

    manifest_path = joinpath(manifest_dir, "manifest.jsonl")
    checksums_path = joinpath(manifest_dir, "checksums.sha256")

    println("Fetching NCBI genome list...")

    # Query NCBI Datasets API for genome list
    assemblies = query_ncbi_assemblies(taxon, assembly_level, max_genomes, seed)

    println("Found $(length(assemblies)) assemblies to download")

    records = RepliconRecord[]
    checksums = String[]

    p = Progress(length(assemblies); desc="Downloading: ", showspeed=true)

    for assembly in assemblies
        try
            # Download genome
            local_path, checksum = download_genome(assembly, raw_dir)

            # Parse FASTA to get replicon info
            replicon_records = parse_genome_fasta(local_path, assembly, checksum)

            append!(records, replicon_records)
            push!(checksums, "$checksum  $(basename(local_path))")

            # Append to manifest
            open(manifest_path, "a") do io
                for rec in replicon_records
                    JSON3.write(io, rec)
                    println(io)
                end
            end

        catch e
            @warn "Failed to download $(assembly["accession"]): $e"
        end

        next!(p)
    end

    # Write checksums
    open(checksums_path, "w") do io
        for cs in checksums
            println(io, cs)
        end
    end

    println("\nDownloaded $(length(records)) replicons from $(length(assemblies)) assemblies")

    return records
end

"""
    query_ncbi_assemblies(taxon, assembly_level, max_genomes, seed)

Query NCBI RefSeq assembly summary for complete bacterial genomes.
Uses the stable FTP assembly_summary.txt file.
"""
function query_ncbi_assemblies(taxon::String, assembly_level::String, max_genomes::Int, seed::Int)
    println("  Downloading assembly summary from NCBI RefSeq...")

    try
        # Download assembly summary (tab-separated)
        response = HTTP.get(NCBI_ASSEMBLY_SUMMARY; 
            retry=true, retries=3, 
            connect_timeout=30, 
            readtimeout=120)

        lines = split(String(response.body), '\n')

        # Parse header (skip comment lines starting with ##)
        header_idx = findfirst(l -> startswith(l, "#assembly_accession"), lines)
        if header_idx === nothing
            @warn "Could not find header in assembly summary"
            return []
        end

        # Get column names from header (remove leading #)
        header_line = replace(lines[header_idx], r"^#" => "")
        columns = split(header_line, '\t')

        # Find relevant column indices
        acc_idx = findfirst(==("assembly_accession"), columns)
        level_idx = findfirst(==("assembly_level"), columns)
        ftp_idx = findfirst(==("ftp_path"), columns)
        taxid_idx = findfirst(==("taxid"), columns)
        org_idx = findfirst(==("organism_name"), columns)

        if any(isnothing, [acc_idx, level_idx, ftp_idx])
            @warn "Missing required columns in assembly summary"
            return []
        end

        # Filter for complete genomes
        assemblies = Dict{String, Any}[]
        for line in lines[header_idx+1:end]
            isempty(strip(line)) && continue
            startswith(line, '#') && continue

            fields = split(line, '\t')
            length(fields) < max(acc_idx, level_idx, ftp_idx) && continue

            # Filter by assembly level
            if lowercase(fields[level_idx]) == "complete genome"
                ftp_path = fields[ftp_idx]
                ftp_path == "na" && continue

                push!(assemblies, Dict(
                    "accession" => fields[acc_idx],
                    "ftp_path" => ftp_path,
                    "taxid" => taxid_idx !== nothing ? tryparse(Int, fields[taxid_idx]) : 0,
                    "organism_name" => org_idx !== nothing ? fields[org_idx] : "Unknown"
                ))
            end
        end

        println("  Found $(length(assemblies)) complete bacterial genomes")

        # Sample if needed
        if length(assemblies) > max_genomes
            rng = Random.MersenneTwister(seed)
            assemblies = Random.shuffle(rng, assemblies)[1:max_genomes]
            println("  Sampled $max_genomes genomes (seed=$seed)")
        end

        return assemblies
    catch e
        @warn "NCBI assembly summary fetch failed: $e"
        return []
    end
end

"""
    download_genome(assembly, output_dir) -> (path, checksum)

Download a single genome assembly from NCBI FTP.
"""
function download_genome(assembly, output_dir::String)
    accession = assembly["accession"]
    ftp_base = assembly["ftp_path"]

    # Handle "na" or empty paths
    if ftp_base == "na" || isempty(ftp_base)
        error("No FTP path available for $accession")
    end

    # Convert FTP to HTTPS (more reliable)
    ftp_base = replace(ftp_base, "ftp://" => "https://")

    # Get the assembly directory name from the path
    asm_name = basename(ftp_base)

    # Construct full path to genomic FASTA
    fasta_url = "$ftp_base/$(asm_name)_genomic.fna.gz"

    local_path = joinpath(output_dir, "$(accession)_genomic.fna.gz")

    # Skip if already downloaded
    if isfile(local_path)
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
            attempt == 3 && rethrow(e)
            sleep(2^attempt)  # Exponential backoff
        end
    end

    # Compute checksum
    checksum = bytes2hex(sha256(read(local_path)))

    return (local_path, checksum)
end

"""
    parse_genome_fasta(path, assembly, checksum) -> Vector{RepliconRecord}

Parse a genome FASTA file and extract replicon metadata.
"""
function parse_genome_fasta(path::String, assembly, checksum::String)::Vector{RepliconRecord}
    records = RepliconRecord[]

    accession = get(assembly, "accession", "unknown")
    taxid = get(assembly, "taxid", 0)
    organism_name = get(assembly, "organism_name", "Unknown organism")
    source = get(assembly, "source", "REFSEQ")

    # Open gzipped FASTA file
    open(path, "r") do io
        reader = FASTA.Reader(GzipDecompressorStream(io))

        replicon_idx = 0
        for record in reader
            replicon_idx += 1

            # Extract sequence
            seq = LongDNA{4}(FASTA.sequence(record))
            header = FASTA.description(record)

            # Parse replicon type from header
            rtype = if occursin(r"plasmid"i, header)
                PLASMID
            elseif occursin(r"chromosome"i, header) || replicon_idx == 1
                CHROMOSOME
            else
                OTHER
            end

            # Extract replicon accession if present
            replicon_acc = match(r"^([A-Z]{1,2}_?[0-9]+(?:\.[0-9]+)?)", header)
            replicon_accession = replicon_acc !== nothing ? replicon_acc.match : nothing

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
                organism_name,
                source == "REFSEQ" ? REFSEQ : GENBANK,
                today(),
                checksum
            ))
        end

        close(reader)
    end

    return records
end
