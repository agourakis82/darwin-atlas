#!/usr/bin/env julia
"""
Fetch DoriC and build ori/ter labels (Tier A).
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using DarwinAtlas
using ArgParse

function parse_args()
    s = ArgParseSettings(
        description = "Build DoriC ori/ter labels",
        prog = "build_doric_labels.jl"
    )

    @add_arg_table! s begin
        "--data-dir", "-d"
            help = "Data directory (contains manifest/)"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "data")
        "--metadata-dir", "-m"
            help = "Metadata output directory"
            arg_type = String
            default = joinpath(@__DIR__, "..", "..", "metadata")
        "--url"
            help = "DoriC download URL"
            arg_type = String
            default = DarwinAtlas.DORIC_DEFAULT_URL
        "--version"
            help = "DoriC version label"
            arg_type = String
            default = DarwinAtlas.DORIC_VERSION
        "--force-download"
            help = "Force download even if archive exists"
            action = :store_true
        "--force-extract"
            help = "Force re-extraction of archive"
            action = :store_true
        "--force-build"
            help = "Rebuild labels even if output exists"
            action = :store_true
        "--no-augment-accessions"
            help = "Skip FASTA-based accession augmentation"
            action = :store_true
    end

    return ArgParse.parse_args(s)
end

function main()
    args = parse_args()
    build_doric_labels(
        data_dir=args["data-dir"],
        metadata_dir=args["metadata-dir"],
        url=args["url"],
        version=args["version"],
        force_download=args["force-download"],
        force_extract=args["force-extract"],
        force_build=args["force-build"],
        augment_accessions=!args["no-augment-accessions"]
    )
end

main()
