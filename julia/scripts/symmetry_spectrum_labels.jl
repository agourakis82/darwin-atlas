#!/usr/bin/env julia
"""
Compute symmetry spectrum summaries (and null p-values) for DoriC-labeled replicons.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using ArgParse
using CSV
using DataFrames
using JSON3
using Parquet2
using Random
using Statistics
using FASTX: FASTA
using CodecZlib: GzipDecompressorStream
using BioSequences: LongDNA

function parse_args()
    s = ArgParseSettings(
        description = "Compute symmetry spectrum summaries for DoriC labels",
        prog = "symmetry_spectrum_labels.jl"
    )

    @add_arg_table! s begin
        "--data-dir", "-d"
            help = "Data directory (raw/ + manifest/)"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "data")
        "--metadata-dir", "-m"
            help = "Metadata directory (labels_oriter.parquet)"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "metadata")
        "--null-model"
            help = "Null model: gc | markov1 | markov2"
            arg_type = String
            default = "gc"
        "--samples"
            help = "Null samples per replicon"
            arg_type = Int
            default = 100
        "--include-rc"
            help = "Include reverse-complement spectrum"
            action = :store_true
        "--seed"
            help = "Random seed"
            arg_type = Int
            default = 42
        "--output"
            help = "Output CSV path"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "metadata", "symmetry_spectrum.csv")
    end

    return ArgParse.parse_args(s)
end

function load_sequence_by_index(path::String, idx::Int)
    open(path, "r") do io
        reader = FASTA.Reader(GzipDecompressorStream(io))
        i = 0
        for record in reader
            i += 1
            if i == idx
                return LongDNA{4}(FASTA.sequence(record))
            end
        end
    end
    return nothing
end

function null_shuffle(seq::LongDNA, model::String; rng=Random.GLOBAL_RNG)
    if model == "markov1"
        return markov1_chain_shuffle(seq; rng=rng)
    elseif model == "markov2"
        return markov2_chain_shuffle(seq; rng=rng)
    else
        return DarwinAtlas.gc_shuffle(seq; rng=rng)
    end
end

function main()
    args = parse_args()
    rng = Random.MersenneTwister(args["seed"])

    labels_path = joinpath(args["metadata-dir"], "labels_oriter.parquet")
    labels = DataFrame(Parquet2.readfile(labels_path))

    replicons = DarwinAtlas.load_replicon_manifest(args["data-dir"])
    DarwinAtlas.augment_replicon_accessions!(replicons, args["data-dir"])

    rep_idx = Dict{String, Int}()
    for row in eachrow(replicons)
        idx = DarwinAtlas.parse_replicon_index(row.replicon_id)
        idx === nothing && continue
        rep_idx[row.replicon_id] = idx
    end

    rows = DataFrame(
        replicon_id=String[],
        assembly_accession=String[],
        length_bp=Int[],
        shift_min=Int[],
        shift_entropy=Float64[],
        shift_peakiness=Float64[],
        rev_min=Int[],
        rev_entropy=Float64[],
        rev_peakiness=Float64[],
        shift_min_p=Float64[],
        rev_min_p=Float64[]
    )

    for row in eachrow(labels)
        rid = row.replicon_id
        idx = get(rep_idx, rid, nothing)
        idx === nothing && continue
        assembly = row.assembly_accession
        fasta_path = joinpath(args["data-dir"], "raw", "$(assembly)_genomic.fna.gz")
        isfile(fasta_path) || continue

        seq = load_sequence_by_index(fasta_path, idx)
        seq === nothing && continue

        summary = symmetry_spectrum_summary(seq; include_rc=args["include-rc"])

        # Null distribution for min distance (shift/rev)
        shift_null = Float64[]
        rev_null = Float64[]
        for _ in 1:args["samples"]
            s = null_shuffle(seq, args["null-model"]; rng=rng)
            ssum = symmetry_spectrum_summary(s; include_rc=false)
            push!(shift_null, ssum.shift_min)
            push!(rev_null, ssum.rev_min)
        end
        shift_p = null_pvalue(summary.shift_min, shift_null; tail=:lower)
        rev_p = null_pvalue(summary.rev_min, rev_null; tail=:lower)

        push!(rows, (
            replicon_id=rid,
            assembly_accession=assembly,
            length_bp=length(seq),
            shift_min=summary.shift_min,
            shift_entropy=summary.shift_entropy,
            shift_peakiness=summary.shift_peakiness,
            rev_min=summary.rev_min,
            rev_entropy=summary.rev_entropy,
            rev_peakiness=summary.rev_peakiness,
            shift_min_p=shift_p,
            rev_min_p=rev_p
        ))
    end

    # FDR correction
    if nrow(rows) > 0
        rows.shift_min_q = fdr_bh(rows.shift_min_p)
        rows.rev_min_q = fdr_bh(rows.rev_min_p)
    end

    CSV.write(args["output"], rows)

    summary_path = replace(args["output"], r"\.csv$" => "_summary.json")
    summary = Dict(
        "n" => nrow(rows),
        "null_model" => args["null-model"],
        "samples" => args["samples"],
        "seed" => args["seed"]
    )
    open(summary_path, "w") do io
        JSON3.write(io, summary; allow_inf=true)
    end

    println("Wrote spectrum: $(args["output"])")
    println("Summary: $summary_path")
end

main()
