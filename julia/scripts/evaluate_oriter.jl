#!/usr/bin/env julia
"""
Evaluate ori/ter predictions against DoriC labels.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using ArgParse
using CSV
using DataFrames
using JSON3
using Statistics

function parse_args()
    s = ArgParseSettings(
        description = "Evaluate ori/ter predictions vs DoriC",
        prog = "evaluate_oriter.jl"
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
        "--window", "-w"
            help = "GC-skew window size"
            arg_type = Int
            default = 1000
        "--step", "-s"
            help = "GC-skew step size"
            arg_type = Int
            default = 100
        "--output"
            help = "Output CSV path"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "metadata", "oriter_eval.csv")
    end

    return ArgParse.parse_args(s)
end

function main()
    args = parse_args()
    df = evaluate_oriter_gc_skew(
        data_dir=args["data-dir"],
        metadata_dir=args["metadata-dir"],
        window_size=args["window"],
        step=args["step"]
    )

    CSV.write(args["output"], df)

    if nrow(df) == 0
        summary = Dict(
            "n" => 0,
            "window_size" => args["window"],
            "step" => args["step"]
        )
    else
        summary = Dict(
            "n" => nrow(df),
            "ori_error_mean" => mean(df.ori_error),
            "ori_error_median" => median(df.ori_error),
            "ter_error_mean" => mean(df.ter_error),
            "ter_error_median" => median(df.ter_error),
            "window_size" => args["window"],
            "step" => args["step"]
        )
    end

    summary_path = replace(args["output"], r"\.csv$" => "_summary.json")
    open(summary_path, "w") do io
        JSON3.write(io, summary; allow_inf=true)
    end

    println("Wrote evaluation: $(args["output"])")
    println("Summary: $summary_path")
end

main()
