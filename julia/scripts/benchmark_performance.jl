#!/usr/bin/env julia
"""
    benchmark_performance.jl

Benchmark performance comparison: Julia pure vs Demetrios FFI.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using BenchmarkTools
using BioSequences
using Dates
using DarwinAtlas

# Test sequences of varying lengths
const TEST_SEQUENCES = [
    ("short", LongDNA{4}("ACGTACGTACGTACGT")),
    ("medium", LongDNA{4}("ACGT"^100)),
    ("long", LongDNA{4}("ACGT"^1000)),
    ("very_long", LongDNA{4}("ACGT"^5000)),
]

function benchmark_orbit_size()
    results = Dict{String, Dict}()
    
    for (name, seq) in TEST_SEQUENCES
        println("Benchmarking orbit_size: $name (length=$(length(seq)))")
        
        # Julia pure
        julia_time = @belapsed begin
            # Temporarily disable Demetrios
            old_val = DarwinAtlas.HAS_DEMETRIOS[]
            DarwinAtlas.HAS_DEMETRIOS[] = false
            try
                orbit_size($seq)
            finally
                DarwinAtlas.HAS_DEMETRIOS[] = old_val
            end
        end
        
        # Demetrios FFI (if available)
        demetrios_time = nothing
        if DarwinAtlas.HAS_DEMETRIOS[] && DarwinAtlas.demetrios_available()
            demetrios_time = @belapsed begin
                DarwinAtlas.demetrios_orbit_size($seq)
            end
        end
        
        results[name] = Dict(
            "length" => length(seq),
            "julia_time" => julia_time,
            "demetrios_time" => demetrios_time,
            "speedup" => demetrios_time !== nothing ? julia_time / demetrios_time : nothing
        )
    end
    
    return results
end

function benchmark_dmin()
    results = Dict{String, Dict}()
    
    for (name, seq) in TEST_SEQUENCES
        println("Benchmarking dmin: $name (length=$(length(seq)))")
        
        # Julia pure
        julia_time = @belapsed begin
            old_val = DarwinAtlas.HAS_DEMETRIOS[]
            DarwinAtlas.HAS_DEMETRIOS[] = false
            try
                dmin($seq)
            finally
                DarwinAtlas.HAS_DEMETRIOS[] = old_val
            end
        end
        
        # Demetrios FFI (if available)
        demetrios_time = nothing
        if DarwinAtlas.HAS_DEMETRIOS[] && DarwinAtlas.demetrios_available()
            demetrios_time = @belapsed begin
                DarwinAtlas.demetrios_dmin($seq)
            end
        end
        
        results[name] = Dict(
            "length" => length(seq),
            "julia_time" => julia_time,
            "demetrios_time" => demetrios_time,
            "speedup" => demetrios_time !== nothing ? julia_time / demetrios_time : nothing
        )
    end
    
    return results
end

function benchmark_hamming_distance()
    results = Dict{String, Dict}()

    for (name, seq) in TEST_SEQUENCES
        println("Benchmarking hamming_distance: $name (length=$(length(seq)))")

        seq_b = shift(seq, 1)

        julia_time = @belapsed begin
            hamming_distance_fast($seq, $seq_b)
        end

        demetrios_time = nothing
        if DarwinAtlas.HAS_DEMETRIOS[] && DarwinAtlas.demetrios_available()
            demetrios_time = @belapsed begin
                DarwinAtlas.demetrios_hamming_distance($seq, $seq_b)
            end
        end

        results[name] = Dict(
            "length" => length(seq),
            "julia_time" => julia_time,
            "demetrios_time" => demetrios_time,
            "speedup" => demetrios_time !== nothing ? julia_time / demetrios_time : nothing
        )
    end

    return results
end

function generate_report(orbit_results, dmin_results, hamming_results)
    report_path = joinpath(@__DIR__, "..", "..", "dist", "atlas_dataset_v2", "performance_report.md")
    
    open(report_path, "w") do io
        println(io, "# Performance Benchmark Report")
        println(io)
        println(io, "Generated: $(now())")
        println(io)
        println(io, "## orbit_size Performance")
        println(io)
        println(io, "| Sequence | Length | Julia (s) | Demetrios (s) | Speedup |")
        println(io, "|----------|--------|-----------|---------------|---------|")
        
        for (name, res) in orbit_results
            julia_t = round(res["julia_time"] * 1e6, digits=2)
            dem_t = res["demetrios_time"] !== nothing ? round(res["demetrios_time"] * 1e6, digits=2) : "N/A"
            speedup = res["speedup"] !== nothing ? round(res["speedup"], digits=2) : "N/A"
            println(io, "| $name | $(res["length"]) | $julia_t μs | $dem_t μs | $speedup× |")
        end
        
        println(io)
        println(io, "## dmin Performance")
        println(io)
        println(io, "| Sequence | Length | Julia (s) | Demetrios (s) | Speedup |")
        println(io, "|----------|--------|-----------|---------------|---------|")
        
        for (name, res) in dmin_results
            julia_t = round(res["julia_time"] * 1e6, digits=2)
            dem_t = res["demetrios_time"] !== nothing ? round(res["demetrios_time"] * 1e6, digits=2) : "N/A"
            speedup = res["speedup"] !== nothing ? round(res["speedup"], digits=2) : "N/A"
            println(io, "| $name | $(res["length"]) | $julia_t μs | $dem_t μs | $speedup× |")
        end

        println(io)
        println(io, "## hamming_distance Performance (fast packed)")
        println(io)
        println(io, "| Sequence | Length | Julia (s) | Demetrios (s) | Speedup |")
        println(io, "|----------|--------|-----------|---------------|---------|")

        for (name, res) in hamming_results
            julia_t = round(res["julia_time"] * 1e6, digits=2)
            dem_t = res["demetrios_time"] !== nothing ? round(res["demetrios_time"] * 1e6, digits=2) : "N/A"
            speedup = res["speedup"] !== nothing ? round(res["speedup"], digits=2) : "N/A"
            println(io, "| $name | $(res["length"]) | $julia_t μs | $dem_t μs | $speedup× |")
        end
    end
    
    println("📊 Performance report written to: $report_path")
end

function main()
    println("="^60)
    println("PERFORMANCE BENCHMARK")
    println("="^60)
    println()
    
    println("Demetrios available: $(DarwinAtlas.HAS_DEMETRIOS[] && DarwinAtlas.demetrios_available())")
    println()
    
    orbit_results = benchmark_orbit_size()
    println()
    dmin_results = benchmark_dmin()
    println()
    hamming_results = benchmark_hamming_distance()

    generate_report(orbit_results, dmin_results, hamming_results)
    
    println()
    println("✅ Benchmark complete")
end

using Dates
main()
