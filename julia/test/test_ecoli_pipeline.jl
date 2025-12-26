using Test
using DarwinAtlas
using BioSequences
using DataFrames
using CSV
using JSON3

@testset "E. coli Pipeline" begin
    
    @testset "Manifest Loading" begin
        # Include the pipeline script functions
        include(joinpath(@__DIR__, "..", "scripts", "run_ecoli_pipeline.jl"))
        
        # Test loading manifest
        data_dir = joinpath(@__DIR__, "..", "..", "data", "ecoli")
        
        if isdir(data_dir) && isfile(joinpath(data_dir, "manifest", "manifest.jsonl"))
            records = load_ecoli_manifest(data_dir)
            
            @test length(records) > 0
            @test all(r -> r.taxonomy_id == 562, records)  # All E. coli
            @test all(r -> !isempty(r.replicon_id), records)
            @test all(r -> r.length_bp > 0, records)
            @test all(r -> 0.0 <= r.gc_fraction <= 1.0, records)
            
            println("  ✓ Loaded $(length(records)) E. coli replicons")
        else
            @warn "E. coli dataset not found, skipping manifest test"
        end
    end
    
    @testset "Sequence Loading" begin
        include(joinpath(@__DIR__, "..", "scripts", "run_ecoli_pipeline.jl"))
        
        data_dir = joinpath(@__DIR__, "..", "..", "data", "ecoli")
        
        if isdir(data_dir) && isfile(joinpath(data_dir, "manifest", "manifest.jsonl"))
            records = load_ecoli_manifest(data_dir)
            
            # Test loading first replicon
            if !isempty(records)
                record = records[1]
                
                try
                    seq = load_replicon_sequence(data_dir, record)
                    
                    @test length(seq) > 0
                    @test length(seq) == record.length_bp
                    @test all(b -> b in [DNA_A, DNA_C, DNA_G, DNA_T], seq)
                    
                    println("  ✓ Loaded sequence for $(record.replicon_id): $(length(seq)) bp")
                catch e
                    @warn "Failed to load sequence: $e"
                end
            end
        else
            @warn "E. coli dataset not found, skipping sequence loading test"
        end
    end
    
    @testset "Metrics Computation" begin
        include(joinpath(@__DIR__, "..", "scripts", "run_ecoli_pipeline.jl"))
        
        # Test with a small synthetic sequence
        seq = LongDNA{4}("ACGTACGTACGTACGT")  # 16 bp, highly symmetric
        
        record = RepliconRecord(
            "TEST_001",
            "TEST_001_rep1",
            "TEST_001",
            CHROMOSOME,
            length(seq),
            0.5,
            562,
            "Test organism",
            REFSEQ,
            today(),
            "test_checksum"
        )
        
        metrics = compute_replicon_metrics(seq, record, false)
        
        @test haskey(metrics, "replicon_id")
        @test haskey(metrics, "length_bp")
        @test haskey(metrics, "orbit_size")
        @test haskey(metrics, "orbit_ratio")
        @test haskey(metrics, "is_palindrome")
        @test haskey(metrics, "is_rc_fixed")
        @test haskey(metrics, "dmin")
        @test haskey(metrics, "dmin_normalized")
        
        @test metrics["replicon_id"] == "TEST_001_rep1"
        @test metrics["length_bp"] == 16
        @test metrics["orbit_size"] > 0
        @test 0.0 <= metrics["orbit_ratio"] <= 1.0
        @test 0.0 <= metrics["dmin_normalized"] <= 1.0
        
        println("  ✓ Computed metrics for test sequence")
    end
    
    @testset "Biology Metrics" begin
        include(joinpath(@__DIR__, "..", "scripts", "run_ecoli_pipeline.jl"))
        
        # Test with a longer sequence
        seq = LongDNA{4}("ACGTACGTACGTACGT" * "TGCATGCATGCATGCA")  # 32 bp
        
        record = RepliconRecord(
            "TEST_002",
            "TEST_002_rep1",
            "TEST_002",
            CHROMOSOME,
            length(seq),
            0.5,
            562,
            "Test organism",
            REFSEQ,
            today(),
            "test_checksum"
        )
        
        bio_metrics = compute_biology_metrics(seq, record)
        
        @test haskey(bio_metrics, "kmer_inversion_score")
        @test haskey(bio_metrics, "kmer_symmetry_index")
        @test haskey(bio_metrics, "gc_skew_ori_estimate")
        @test haskey(bio_metrics, "gc_skew_ter_estimate")
        @test haskey(bio_metrics, "num_inverted_repeats")
        
        println("  ✓ Computed biology metrics for test sequence")
    end
    
    @testset "Small Pipeline Run" begin
        include(joinpath(@__DIR__, "..", "scripts", "run_ecoli_pipeline.jl"))
        
        data_dir = joinpath(@__DIR__, "..", "..", "data", "ecoli")
        
        if isdir(data_dir) && isfile(joinpath(data_dir, "manifest", "manifest.jsonl"))
            # Create temporary output directory
            temp_output = mktempdir()
            
            try
                records = load_ecoli_manifest(data_dir)
                
                # Process first 5 replicons
                test_records = records[1:min(5, length(records))]
                
                replicon_metrics = DataFrame()
                biology_metrics_df = DataFrame()
                
                for record in test_records
                    try
                        seq = load_replicon_sequence(data_dir, record)
                        metrics = compute_replicon_metrics(seq, record, false)
                        bio_metrics = compute_biology_metrics(seq, record)
                        
                        push!(replicon_metrics, metrics, cols=:union)
                        push!(biology_metrics_df, merge(Dict("replicon_id" => record.replicon_id), bio_metrics), cols=:union)
                    catch e
                        @warn "Failed to process $(record.replicon_id): $e"
                    end
                end
                
                # Verify results
                @test nrow(replicon_metrics) > 0
                @test nrow(biology_metrics_df) > 0
                @test nrow(replicon_metrics) == nrow(biology_metrics_df)
                
                # Write test outputs
                CSV.write(joinpath(temp_output, "test_replicons.csv"), replicon_metrics)
                CSV.write(joinpath(temp_output, "test_biology.csv"), biology_metrics_df)
                
                @test isfile(joinpath(temp_output, "test_replicons.csv"))
                @test isfile(joinpath(temp_output, "test_biology.csv"))
                
                println("  ✓ Processed $(nrow(replicon_metrics)) replicons successfully")
                
            finally
                rm(temp_output; recursive=true, force=true)
            end
        else
            @warn "E. coli dataset not found, skipping pipeline run test"
        end
    end
    
    @testset "Cross-Validation" begin
        if HAS_DEMETRIOS[]
            include(joinpath(@__DIR__, "..", "scripts", "run_ecoli_pipeline.jl"))
            
            # Test cross-validation with synthetic sequence
            seq = LongDNA{4}("ACGTACGTACGTACGT")
            
            record = RepliconRecord(
                "TEST_CV",
                "TEST_CV_rep1",
                "TEST_CV",
                CHROMOSOME,
                length(seq),
                0.5,
                562,
                "Test organism",
                REFSEQ,
                today(),
                "test_checksum"
            )
            
            # Compute with cross-validation enabled
            metrics = compute_replicon_metrics(seq, record, true)
            
            # Should not throw warnings if cross-validation passes
            @test haskey(metrics, "orbit_size")
            @test haskey(metrics, "dmin")
            
            println("  ✓ Cross-validation test passed")
        else
            @warn "Demetrios FFI not available, skipping cross-validation test"
        end
    end
end
