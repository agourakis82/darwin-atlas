"""
    OriTerEval.jl

Evaluate ori/ter predictions against DoriC labels.
"""

using DataFrames
using Dates
using BioSequences: LongDNA
using FASTX: FASTA
using CodecZlib: GzipDecompressorStream
using JSON3
using Parquet2

 

export evaluate_oriter_gc_skew

function circular_distance(a::Int, b::Int, n::Int)::Int
    d = abs(a - b)
    return min(d, n - d)
end

function load_sequence_by_index(path::String, idx::Int)
    open(path, "r") do io
        reader = FASTA.Reader(GzipDecompressorStream(io))
        i = 0
        for record in reader
            i += 1
            if i == idx
                raw_seq = FASTA.sequence(record)
                return LongDNA{4}(raw_seq)
            end
        end
    end
    return nothing
end

"""
    evaluate_oriter_gc_skew(; data_dir="data", metadata_dir="metadata",
        window_size=1000, step=100) -> DataFrame

Compute GC-skew ori/ter predictions and compare to DoriC labels.
Outputs per-replicon errors.
"""
function evaluate_oriter_gc_skew(; data_dir::String="data", metadata_dir::String="metadata",
    window_size::Int=1000, step::Int=100)

    labels_path = joinpath(metadata_dir, "labels_oriter.parquet")
    isfile(labels_path) || error("Missing labels: $labels_path")
    labels = DataFrame(Parquet2.readfile(labels_path))

    # Load manifest (with accession augmentation)
    replicons = load_replicon_manifest(data_dir)
    augment_replicon_accessions!(replicons, data_dir)

    # Build lookup from replicon_id to (assembly, index)
    rep_idx = Dict{String, Int}()
    for row in eachrow(replicons)
        rid = row.replicon_id
        idx = parse_replicon_index(rid)
        if idx !== nothing
            rep_idx[rid] = idx
        end
    end

    rows = DataFrame(
        replicon_id=String[],
        assembly_accession=String[],
        length_bp=Int[],
        ori_label=Int[],
        ter_label=Int[],
        ori_pred=Int[],
        ter_pred=Int[],
        ori_error=Int[],
        ter_error=Int[],
        window_size=Int[],
        step=Int[]
    )

    for row in eachrow(labels)
        rid = row.replicon_id
        idx = get(rep_idx, rid, nothing)
        idx === nothing && continue
        assembly = row.assembly_accession
        fasta_path = joinpath(data_dir, "raw", "$(assembly)_genomic.fna.gz")
        isfile(fasta_path) || continue

        seq = load_sequence_by_index(fasta_path, idx)
        seq === nothing && continue

        estimate = estimate_ori_ter(seq, window_size; step=step)
        ori_pred = estimate.ori_position
        ter_pred = estimate.ter_position
        n = length(seq)

        ori_label = row.ori_center_bp
        ter_label = row.ter_bp
        ori_error = circular_distance(ori_pred, ori_label, n)
        ter_error = circular_distance(ter_pred, ter_label, n)

        push!(rows, (
            replicon_id=rid,
            assembly_accession=assembly,
            length_bp=n,
            ori_label=ori_label,
            ter_label=ter_label,
            ori_pred=ori_pred,
            ter_pred=ter_pred,
            ori_error=ori_error,
            ter_error=ter_error,
            window_size=window_size,
            step=step
        ))
    end

    return rows
end
