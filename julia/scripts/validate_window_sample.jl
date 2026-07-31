#!/usr/bin/env julia

"""
Deterministic stratified sample validator (specification 0.1.0 section 12.2)
for persisted window_operator_profiles products.

The sample definition is fixed here and printed into the validation report:

- version 0.1.0;
- stratum 1: every window whose persisted status is not "ok";
- stratum 2: the first and last window of every record;
- stratum 3: every "ok" window whose murmur3 fmix64 mix of the seed, the
  1-based record index, and the 0-based window index is divisible by 64
  (~1/64 of ok windows);
- seed: the first 16 hexadecimal digits of the parameters_sha256 bound into
  the rendered flat parameters, parsed as UInt64.

Every sampled line is recomputed independently from the FASTA bytes, the
metadata TSV, and the flat parameters (same emit_window core as the full
mini-pipeline differential) and must match the persisted product byte for
byte. The selected coordinates are also written to a coordinates file whose
SHA-256 (computed by the orchestrator) binds the sample in the validation
report. Base only; never executes Sounio; never produces the product itself.
"""

if length(ARGS) != 5
    println(stderr, "usage: validate_window_sample.jl <windows.jsonl> <fasta> <metadata.tsv> <parameters.flat> <sample-coordinates.out>")
    exit(2)
end

const WINDOWS_PATH = ARGS[1]
const FASTA_PATH = ARGS[2]
const METADATA_PATH = ARGS[3]
const FLAT_PATH = ARGS[4]
const COORDINATES_PATH = ARGS[5]

include(joinpath(@__DIR__, "window_pipeline_core.jl"))

const SAMPLE_VERSION = "0.1.0"
const SAMPLE_MODULUS = UInt64(64)

function fmix64(z::UInt64)
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

function sample_mix(seed::UInt64, record_index::Int, window_index::Int)
    return fmix64(seed ⊻ fmix64(UInt64(record_index) * 0x9e3779b97f4a7c15) ⊻
                  fmix64(UInt64(window_index) * 0x85ebca6b))
end

function read_records(path::String)
    bytes = read(path)
    records = Tuple{String, Vector{Int}}[]
    header = nothing
    seq = Int[]
    function close_record()
        if !isnothing(header)
            isempty(seq) && error("empty sequence for record $header")
            push!(records, (header, copy(seq)))
        end
    end
    at_line_start = true
    in_header = false
    token_done = false
    token = UInt8[]
    for byte in bytes
        byte == 0x0d && continue
        if byte == 0x0a
            if in_header
                isempty(token) && error("empty FASTA header")
                header = String(copy(token))
                in_header = false
            end
            at_line_start = true
            continue
        end
        if at_line_start && byte == UInt8('>')
            close_record()
            header = nothing
            empty!(seq)
            empty!(token)
            in_header = true
            token_done = false
            at_line_start = false
            continue
        end
        at_line_start = false
        if in_header
            if byte == 0x20 || byte == 0x09
                token_done = true
            elseif !token_done
                push!(token, byte)
            end
            continue
        end
        index = get(IUPAC_INDEX, byte, -1)
        index >= 0 || error("invalid symbol in FASTA: $(Char(byte))")
        isnothing(header) && error("sequence before first header")
        push!(seq, index)
    end
    close_record()
    isempty(records) && error("no records in FASTA")
    return records
end

params_or_error = load_parameters(String(read(FLAT_PATH)))
params_or_error isa PipelineParams || error("sample validator rejected the flat parameters")
const PARAMS = params_or_error

metadata_or_error = load_metadata(String(read(METADATA_PATH)))
metadata_or_error isa Vector{MetadataRow} || error("sample validator rejected the metadata")
const ROWS = metadata_or_error

const RECORDS = read_records(FASTA_PATH)
length(RECORDS) == length(ROWS) || error("record/metadata count mismatch")
for (index, (header, _seq)) in enumerate(RECORDS)
    header == ROWS[index].sequence_accession_version ||
        error("record $index header does not match metadata")
end

# Seed from the parameters_sha256 bound into the flat file.
const SEED = let sha = nothing
    for line in eachline(FLAT_PATH)
        if startswith(line, "parameters_sha256=")
            sha = split(line, '='; limit=2)[2]
            break
        end
    end
    isnothing(sha) && error("flat parameters do not bind parameters_sha256")
    parse(UInt64, String(sha[1:16]); base=16)
end

const PRODUCT_LINES = readlines(WINDOWS_PATH)

# Total expected windows per record and cumulative offsets.
const RECORD_WINDOWS = map(RECORDS) do (_header, seq)
    full, rem = divrem(length(seq), PARAMS.window_size)
    full + (rem > 0 ? 1 : 0)
end
sum(RECORD_WINDOWS) == length(PRODUCT_LINES) || error(
    "product line count $(length(PRODUCT_LINES)) does not match the independent " *
    "window count $(sum(RECORD_WINDOWS))",
)

# Select sampled (line, record, window) tuples by the fixed strata.
function select_sample(product_lines, record_windows)
    selected = Tuple{Int, Int, Int}[]  # (line_index, record_index, window_index)
    line_index = 0
    for record_index in 1:length(record_windows)
        n_windows = record_windows[record_index]
        for window_index in 0:(n_windows - 1)
            line_index += 1
            line = product_lines[line_index]
            status = match(r"\"status\":\"(ok|excluded)\"", line)
            isnothing(status) && error("product line $line_index has no status field")
            take = status.captures[1] != "ok" ||
                   window_index == 0 || window_index == n_windows - 1 ||
                   sample_mix(SEED, record_index, window_index) % SAMPLE_MODULUS == 0
            take && push!(selected, (line_index, record_index, window_index))
        end
    end
    return selected
end

selected = select_sample(PRODUCT_LINES, RECORD_WINDOWS)

# Recompute every sampled line byte-exact.
for (line_idx, record_index, window_index) in selected
    (_header, seq) = RECORDS[record_index]
    window_start = window_index * PARAMS.window_size
    window_end = min(window_start + PARAMS.window_size, length(seq))
    window = seq[(window_start + 1):window_end]
    expected = emit_window(ROWS[record_index], record_index, window_index,
                           window_start, window, PARAMS)
    PRODUCT_LINES[line_idx] == expected || error(
        "sampled window mismatch at record $record_index window $window_index: " *
        "persisted product differs from the independent Julia recomputation",
    )
end

# Persist the selected coordinates; the orchestrator hashes this file into
# the validation report.
open(COORDINATES_PATH, "w") do io
    println(io, "sample_version=$SAMPLE_VERSION modulus=$(SAMPLE_MODULUS) seed=$(string(SEED, base=16))")
    for (_line_idx, record_index, window_index) in selected
        println(io, "$record_index,$window_index")
    end
end

println("DOSA_SAMPLE_DEFINITION version=$SAMPLE_VERSION " *
        "strata=excluded_all,record_boundaries,fmix64_mod64 " *
        "seed_source=parameters_sha256 seed=$(string(SEED, base=16))")
println("DOSA_SAMPLE_REPORT total_windows=$(length(PRODUCT_LINES)) " *
        "sampled=$(length(selected)) validated=$(length(selected)) tolerance=0")
println("DOSA_SAMPLE_OK")
