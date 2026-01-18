"""
    WindowAnalysis.jl

Sliding window analysis for genome-wide symmetry computation.

Handles circular genome extraction and batch processing of windows.
"""

using BioSequences: LongDNA
using CSV
using DataFrames
using CodecZlib: GzipDecompressorStream
using FASTX: FASTA

"""
    extract_window(seq::LongDNA, start::Int, window_size::Int) -> LongDNA

Extract a window from a circular genome.

Handles wraparound for positions near the end of circular replicons.

# Arguments
- `seq`: Full replicon sequence
- `start`: 0-indexed start position
- `window_size`: Length of window to extract

# Returns
Window sequence of exactly `window_size` bases, wrapping if necessary.
"""
function extract_window(seq::LongDNA, start::Int, window_size::Int)::LongDNA
    n = length(seq)
    @assert window_size <= n "Window size ($window_size) exceeds sequence length ($n)"
    @assert start >= 0 "Start position must be non-negative"

    # Normalize start position
    start_mod = mod(start, n)
    end_pos = start_mod + window_size

    if end_pos <= n
        # No wraparound needed
        return seq[start_mod+1:end_pos]
    else
        # Wraparound: concatenate end and beginning
        first_part = seq[start_mod+1:n]
        second_part = seq[1:end_pos-n]
        return first_part * second_part
    end
end

"""
    window_positions(replicon_length::Int, window_size::Int; step::Int=0) -> Vector{Int}

Generate window start positions for a replicon.

# Arguments
- `replicon_length`: Total length of the replicon
- `window_size`: Size of each window
- `step`: Step between windows (default: window_size for non-overlapping)

# Returns
Vector of 0-indexed start positions.
"""
function window_positions(replicon_length::Int, window_size::Int; step::Int=0)::Vector{Int}
    step = step == 0 ? window_size : step

    if replicon_length < window_size
        return Int[]
    end

    # For circular genomes, we can start anywhere
    # But for efficiency, we only need non-overlapping coverage
    positions = collect(0:step:replicon_length-1)

    return positions
end

"""
    analyze_window(seq::LongDNA, replicon_id::String, window_size::Int, start::Int) -> WindowResult

Analyze a single window and return results.

# Arguments
- `seq`: Full replicon sequence
- `replicon_id`: Identifier for the replicon
- `window_size`: Size of window to analyze
- `start`: 0-indexed start position

# Returns
`WindowResult` with all symmetry metrics.
"""
function analyze_window(seq::LongDNA, replicon_id::String, window_size::Int, start::Int)::WindowResult
    window = extract_window(seq, start, window_size)

    return WindowResult(
        replicon_id,
        window_size,
        start,
        orbit_ratio(window),
        is_palindrome(window),
        is_rc_fixed(window),
        orbit_size(window),
        dmin(window),
        dmin_normalized(window)
    )
end

"""
    analyze_replicon_windows(seq::LongDNA, replicon_id::String, window_size::Int;
                             step::Int=0, max_windows::Int=0) -> Vector{WindowResult}

Analyze all windows of a given size for a replicon.

# Arguments
- `seq`: Full replicon sequence
- `replicon_id`: Identifier for the replicon
- `window_size`: Size of windows to analyze
- `step`: Step between windows (default: window_size)
- `max_windows`: Maximum windows to analyze (0 = all)

# Returns
Vector of `WindowResult` for each analyzed window.
"""
function analyze_replicon_windows(
    seq::LongDNA,
    replicon_id::String,
    window_size::Int;
    step::Int=0,
    max_windows::Int=0
)::Vector{WindowResult}

    n = length(seq)

    if n < window_size
        return WindowResult[]
    end

    positions = window_positions(n, window_size; step=step)

    if max_windows > 0 && length(positions) > max_windows
        positions = positions[1:max_windows]
    end

    results = Vector{WindowResult}(undef, length(positions))

    for (i, start) in enumerate(positions)
        results[i] = analyze_window(seq, replicon_id, window_size, start)
    end

    return results
end

"""
    write_window_results(io::IO, results::Vector{WindowResult})

Write window results to CSV format (streaming).

# Arguments
- `io`: Output IO stream
- `results`: Vector of window results to write
"""
function write_window_results(io::IO, results::Vector{WindowResult})
    for result in results
        println(io, join([
            result.replicon_id,
            result.window_length,
            result.window_start,
            result.orbit_ratio,
            result.is_palindrome,
            result.is_rc_fixed,
            result.orbit_size,
            result.dmin,
            result.dmin_normalized
        ], ","))
    end
end

"""
    write_csv_header(io::IO)

Write CSV header for window results.
"""
function write_csv_header(io::IO)
    println(io, "replicon_id,window_length,window_start,orbit_ratio,is_palindrome_R,is_fixed_RC,orbit_size,dmin,dmin_over_L")
end

"""
    analyze_manifest_windows(manifest_path::String, raw_dir::String, output_path::String;
                            window_sizes::Vector{Int}=[100, 500, 1000, 5000, 10000],
                            max_windows_per_replicon::Int=0)

Process all replicons in a manifest and generate window analysis CSV.

# Arguments
- `manifest_path`: Path to manifest.jsonl
- `raw_dir`: Directory containing .fna.gz genome files
- `output_path`: Path for output CSV
- `window_sizes`: List of window sizes to analyze
- `max_windows_per_replicon`: Limit windows per replicon (0 = all)
"""
function analyze_manifest_windows(
    manifest_path::String,
    raw_dir::String,
    output_path::String;
    window_sizes::Vector{Int}=[100, 500, 1000, 5000, 10000],
    max_windows_per_replicon::Int=0
)
    # Read manifest
    manifest_entries = []
    open(manifest_path) do f
        for line in eachline(f)
            push!(manifest_entries, JSON3.read(line))
        end
    end

    println("Processing $(length(manifest_entries)) replicons...")

    # Open output file
    open(output_path, "w") do io
        write_csv_header(io)

        for (i, entry) in enumerate(manifest_entries)
            replicon_id = entry.replicon_id
            assembly = entry.assembly_accession

            # Find genome file (NCBI format: assembly_accession_genomic.fna.gz)
            genome_file = joinpath(raw_dir, "$(assembly)_genomic.fna.gz")

            if !isfile(genome_file)
                @warn "Genome file not found: $genome_file"
                continue
            end

            # Load sequence (streaming decompression)
            seq = load_replicon_sequence(genome_file, replicon_id)

            if isnothing(seq)
                @warn "Replicon $replicon_id not found in $genome_file"
                continue
            end

            # Analyze at each window size
            for ws in window_sizes
                if length(seq) < ws
                    continue
                end

                results = analyze_replicon_windows(
                    seq, replicon_id, ws;
                    max_windows=max_windows_per_replicon
                )

                write_window_results(io, results)
            end

            if i % 50 == 0
                println("  Processed $i/$(length(manifest_entries)) replicons")
            end
        end
    end

    println("Window analysis complete: $output_path")
end

"""
    load_replicon_sequence(genome_file::String, replicon_id::String) -> Union{LongDNA, Nothing}

Load a specific replicon sequence from a gzipped FASTA file.

Replicon IDs follow the pattern "GCF_XXXXXX.Y_repN" where N is the 1-indexed
sequence number in the FASTA file.

# Arguments
- `genome_file`: Path to .fna.gz file
- `replicon_id`: ID of replicon (e.g., "GCF_002847445.1_rep1")

# Returns
The replicon sequence, or nothing if not found.
"""
function load_replicon_sequence(genome_file::String, replicon_id::String)::Union{LongDNA, Nothing}
    # Extract replicon index from replicon_id
    # e.g., "GCF_000005845.2_rep1" -> index 1
    parts = split(replicon_id, "_rep")
    if length(parts) != 2
        @warn "Invalid replicon_id format: $replicon_id"
        return nothing
    end

    target_idx = parse(Int, parts[2])
    result::Union{LongDNA, Nothing} = nothing

    stream = GzipDecompressorStream(open(genome_file))
    try
        reader = FASTA.Reader(stream)
        idx = 0
        for record in reader
            idx += 1
            if idx == target_idx
                result = FASTA.sequence(LongDNA{4}, record)
                break
            end
        end
    finally
        close(stream)
    end

    return result
end
