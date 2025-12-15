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

const NCBI_DATASETS_API = "https://api.ncbi.nlm.nih.gov/datasets/v2alpha"
const NCBI_FTP_BASE = "https://ftp.ncbi.nlm.nih.gov/genomes/all"

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

Query NCBI Datasets API for genome assemblies.
"""
function query_ncbi_assemblies(taxon::String, assembly_level::String, max_genomes::Int, seed::Int)
    # Simplified implementation - in production would use NCBI Datasets API
    # For now, returns placeholder structure

    url = "$NCBI_DATASETS_API/genome/taxon/$taxon"
    params = Dict(
        "filters.assembly_level" => assembly_level,
        "page_size" => min(max_genomes, 1000)
    )

    try
        response = HTTP.get(url; query=params, retry=true, retries=3)
        data = JSON3.read(response.body)

        assemblies = get(data, :reports, [])

        # Sample if needed
        if length(assemblies) > max_genomes
            rng = Random.MersenneTwister(seed)
            assemblies = Random.shuffle(rng, assemblies)[1:max_genomes]
        end

        return assemblies
    catch e
        @warn "NCBI API query failed: $e"
        return []
    end
end

"""
    download_genome(assembly, output_dir) -> (path, checksum)

Download a single genome assembly.
"""
function download_genome(assembly, output_dir::String)
    accession = assembly["accession"]

    # Construct FTP path
    prefix = accession[1:3]
    part1 = accession[5:7]
    part2 = accession[8:10]
    part3 = accession[11:13]

    ftp_path = "$NCBI_FTP_BASE/$prefix/$part1/$part2/$part3/$(accession)_*/$(accession)_*_genomic.fna.gz"

    local_path = joinpath(output_dir, "$(accession)_genomic.fna.gz")

    # Download
    HTTP.download(ftp_path, local_path; retry=true, retries=3)

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
