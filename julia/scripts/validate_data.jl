#!/usr/bin/env julia
"""
    validate_data.jl

Comprehensive data validation for Atlas dataset.
Validates:
1. Schema compliance
2. Value ranges
3. Referential integrity
4. Statistical consistency
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using Statistics
using SHA
using Dates

const DATA_DIR = joinpath(@__DIR__, "..", "..", "data")
const DIST_DIR = joinpath(@__DIR__, "..", "..", "dist", "atlas_dataset_v2")

struct CheckResult
    check::String
    passed::Bool
    message::String
    details::Dict
end

function validate_replicons()
    results = CheckResult[]
    
    csv_path = joinpath(DIST_DIR, "csv", "atlas_replicons.csv")
    if !isfile(csv_path)
        push!(results, CheckResult("replicons_file_exists", false, "File not found: $csv_path", Dict()))
        return results
    end
    
    df = CSV.read(csv_path, DataFrame)
    
    # Schema check
    required_cols = ["assembly_accession", "replicon_id", "replicon_type", "length_bp", "gc_fraction", "taxonomy_id", "checksum_sha256"]
    for col in required_cols
        push!(results, CheckResult(
            "schema_$col",
            col in names(df),
            col in names(df) ? "" : "Missing column: $col",
            Dict("columns" => names(df))
        ))
    end
    
    # Value ranges
    if "length_bp" in names(df)
        lengths = df.length_bp
        push!(results, CheckResult(
            "length_bp_positive",
            all(lengths .> 0),
            "All lengths must be positive",
            Dict("min" => minimum(lengths), "max" => maximum(lengths), "count" => nrow(df))
        ))
    end
    
    if "gc_fraction" in names(df)
        gc = df.gc_fraction
        push!(results, CheckResult(
            "gc_fraction_range",
            all(0.0 .<= gc .<= 1.0),
            "GC fraction must be in [0, 1]",
            Dict("min" => minimum(gc), "max" => maximum(gc), "mean" => mean(gc))
        ))
    end
    
    # Uniqueness
    if "replicon_id" in names(df)
        unique_ids = unique(df.replicon_id)
        push!(results, CheckResult(
            "replicon_id_unique",
            length(unique_ids) == nrow(df),
            "replicon_id must be unique",
            Dict("total" => nrow(df), "unique" => length(unique_ids))
        ))
    end
    
    return results
end

function validate_kmer_inversion()
    results = CheckResult[]
    
    csv_path = joinpath(DIST_DIR, "csv", "kmer_inversion.csv")
    if !isfile(csv_path)
        push!(results, CheckResult("kmer_file_exists", false, "File not found: $csv_path", Dict()))
        return results
    end
    
    df = CSV.read(csv_path, DataFrame)
    
    # Check required columns
    if "k" in names(df) && "replicon_id" in names(df)
        k_values = unique(df.k)
        push!(results, CheckResult(
            "kmer_k_range",
            all(1 .<= k_values .<= 10),
            "k must be in [1, 10]",
            Dict("k_values" => sort(collect(k_values)))
        ))
    end
    
    # Check X_k range (should be in [0, 1] for normalized)
    if "x_k" in names(df)
        x_k = df.x_k
        push!(results, CheckResult(
            "x_k_range",
            all(0.0 .<= x_k .<= 1.0),
            "X_k should be in [0, 1]",
            Dict("min" => minimum(x_k), "max" => maximum(x_k), "mean" => mean(x_k))
        ))
    end
    
    return results
end

function validate_gc_skew()
    results = CheckResult[]
    
    csv_path = joinpath(DIST_DIR, "csv", "gc_skew_ori_ter.csv")
    if !isfile(csv_path)
        push!(results, CheckResult("gc_skew_file_exists", false, "File not found: $csv_path", Dict()))
        return results
    end
    
    df = CSV.read(csv_path, DataFrame)
    
    # Check ori/ter positions are within replicon length
    if "ori_position" in names(df) && "replicon_id" in names(df)
        # Load replicon lengths
        replicons_path = joinpath(DIST_DIR, "csv", "atlas_replicons.csv")
        if isfile(replicons_path)
            replicons_df = CSV.read(replicons_path, DataFrame)
            length_dict = Dict(r.replicon_id => r.length_bp for r in eachrow(replicons_df))
            
            invalid = 0
            for row in eachrow(df)
                len = get(length_dict, row.replicon_id, 0)
                if len > 0 && (row.ori_position < 0 || row.ori_position >= len)
                    invalid += 1
                end
            end
            
            push!(results, CheckResult(
                "ori_position_bounds",
                invalid == 0,
                "ori_position must be in [0, length_bp)",
                Dict("invalid" => invalid, "total" => nrow(df))
            ))
        end
    end
    
    return results
end

function validate_referential_integrity()
    results = CheckResult[]
    
    # Load replicon IDs
    replicons_path = joinpath(DIST_DIR, "csv", "atlas_replicons.csv")
    if !isfile(replicons_path)
        push!(results, CheckResult("replicons_for_fk", false, "Cannot check FK: replicons file missing", Dict()))
        return results
    end
    
    replicons_df = CSV.read(replicons_path, DataFrame)
    valid_ids = Set(replicons_df.replicon_id)
    
    # Check all tables with replicon_id
    tables = ["kmer_inversion", "gc_skew_ori_ter", "replichore_metrics", "inverted_repeats_summary"]
    
    for table in tables
        csv_path = joinpath(DIST_DIR, "csv", "$table.csv")
        if isfile(csv_path)
            df = CSV.read(csv_path, DataFrame)
            if "replicon_id" in names(df)
                table_ids = Set(df.replicon_id)
                invalid_ids = setdiff(table_ids, valid_ids)
                push!(results, CheckResult(
                    "fk_$table",
                    isempty(invalid_ids),
                    isempty(invalid_ids) ? "" : "Invalid replicon_ids: $(length(invalid_ids))",
                    Dict("table" => table, "total_rows" => nrow(df), "invalid" => length(invalid_ids))
                ))
            end
        end
    end
    
    return results
end

function generate_report(all_results::Vector{CheckResult})
    passed = filter(r -> r.passed, all_results)
    failed = filter(r -> !r.passed, all_results)
    
    report_path = joinpath(DIST_DIR, "validation_report.md")
    open(report_path, "w") do io
        println(io, "# Atlas Dataset Validation Report")
        println(io)
        println(io, "Generated: $(now())")
        println(io)
        println(io, "## Summary")
        println(io)
        println(io, "| Metric | Value |")
        println(io, "|--------|-------|")
        println(io, "| Total Checks | $(length(all_results)) |")
        println(io, "| Passed | $(length(passed)) |")
        println(io, "| Failed | $(length(failed)) |")
        println(io, "| Pass Rate | $(round(100 * length(passed) / max(1, length(all_results)), digits=2))% |")
        println(io)
        
        if isempty(failed)
            println(io, "## ✅ Result: ALL CHECKS PASSED")
        else
            println(io, "## ❌ Result: SOME CHECKS FAILED")
            println(io)
            println(io, "### Failed Checks")
            println(io)
            for f in failed
                println(io, "#### $(f.check)")
                println(io)
                println(io, "**Message**: $(f.message)")
                println(io)
                if !isempty(f.details)
                    println(io, "**Details**:")
                    for (k, v) in f.details
                        println(io, "- $k: $v")
                    end
                end
                println(io)
            end
        end
    end
    
    println("📊 Validation report written to: $report_path")
    return length(failed) == 0
end

function main()
    println("="^60)
    println("ATLAS DATA VALIDATION")
    println("="^60)
    println()
    
    all_results = CheckResult[]
    
    println("Validating replicons...")
    append!(all_results, validate_replicons())
    
    println("Validating k-mer inversion...")
    append!(all_results, validate_kmer_inversion())
    
    println("Validating GC skew...")
    append!(all_results, validate_gc_skew())
    
    println("Validating referential integrity...")
    append!(all_results, validate_referential_integrity())
    
    println()
    println("="^60)
    
    all_passed = generate_report(all_results)
    
    if all_passed
        println("✅ ALL VALIDATION CHECKS PASSED")
        exit(0)
    else
        println("❌ SOME VALIDATION CHECKS FAILED")
        exit(1)
    end
end

using Dates
main()

