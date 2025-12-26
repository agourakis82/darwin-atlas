using Test
using DarwinAtlas
using BioSequences
using Dates
using JSON3

@testset "E. coli Download" begin
    
    @testset "Pathotype Classification" begin
        # Load the classify_pathotype function from download_ecoli.jl
        include(joinpath(@__DIR__, "..", "scripts", "download_ecoli.jl"))
        
        # Test K-12 classification
        @test classify_pathotype("K-12", "Escherichia coli") == "K12_Lab"
        @test classify_pathotype("K12", "Escherichia coli") == "K12_Lab"
        
        # Test O157:H7 classification
        @test classify_pathotype("O157:H7", "Escherichia coli") == "EHEC_O157H7"
        @test classify_pathotype("O157H7", "Escherichia coli") == "EHEC_O157H7"
        
        # Test UPEC classification
        @test classify_pathotype("UTI89", "Escherichia coli") == "UPEC"
        @test classify_pathotype("CFT073", "Escherichia coli") == "UPEC"
        @test classify_pathotype("UPEC", "Escherichia coli") == "UPEC"
        
        # Test other pathotypes
        @test classify_pathotype("ETEC", "Escherichia coli") == "ETEC"
        @test classify_pathotype("EPEC", "Escherichia coli") == "EPEC"
        @test classify_pathotype("EIEC", "Escherichia coli") == "EIEC"
        @test classify_pathotype("EAEC", "Escherichia coli") == "EAEC"
        @test classify_pathotype("STEC", "Escherichia coli") == "STEC"
        
        # Test unknown/other
        @test classify_pathotype("Unknown Strain", "Escherichia coli") == "Other"
        @test classify_pathotype("", "Escherichia coli") == "Other"
    end
    
    @testset "Replicon Accession Extraction" begin
        include(joinpath(@__DIR__, "..", "scripts", "download_ecoli.jl"))
        
        # Test standard RefSeq accessions
        @test extract_replicon_accession("NC_000913.3 Escherichia coli str. K-12") == "NC_000913.3"
        @test extract_replicon_accession("NZ_CP012345.1 plasmid") == "NZ_CP012345.1"
        
        # Test GenBank accessions
        @test extract_replicon_accession("CP000946.1 chromosome") == "CP000946.1"
        
        # Test without version
        @test extract_replicon_accession("NC_000913 chromosome") == "NC_000913"
        
        # Test edge cases
        @test extract_replicon_accession("invalid_header") === nothing
        @test extract_replicon_accession("") === nothing
    end
    
    @testset "Small Download Test" begin
        # Test downloading a small number of genomes
        # This test requires network access and may be slow
        
        # Create temporary directory
        temp_dir = mktempdir()
        
        try
            # Include the download script functions
            include(joinpath(@__DIR__, "..", "scripts", "download_ecoli.jl"))
            
            println("\n  Testing small E. coli download (max=2)...")
            
            # Query for 2 genomes
            assemblies = query_ecoli_assemblies(2, 42)
            
            # Verify we got results
            @test length(assemblies) <= 2
            @test length(assemblies) > 0
            
            # Verify assembly structure
            for asm in assemblies
                @test haskey(asm, "accession")
                @test haskey(asm, "ftp_path")
                @test haskey(asm, "taxid")
                @test haskey(asm, "organism_name")
                @test haskey(asm, "strain")
                @test haskey(asm, "pathotype")
                
                @test asm["taxid"] == 562  # E. coli taxid
                @test !isempty(asm["accession"])
                @test !isempty(asm["ftp_path"])
            end
            
            println("  ✓ Query successful: $(length(assemblies)) assemblies found")
            
            # Test downloading one genome
            if !isempty(assemblies)
                raw_dir = joinpath(temp_dir, "raw")
                mkpath(raw_dir)
                
                assembly = assemblies[1]
                println("  Testing download of $(assembly["accession"])...")
                
                local_path, checksum = download_ecoli_genome(assembly, raw_dir, false)
                
                # Verify download
                @test isfile(local_path)
                @test filesize(local_path) > 0
                @test length(checksum) == 64  # SHA256 hex length
                
                println("  ✓ Download successful: $(basename(local_path))")
                
                # Test parsing
                println("  Testing FASTA parsing...")
                records = parse_ecoli_fasta(local_path, assembly, checksum)
                
                @test length(records) > 0
                
                for rec in records
                    @test rec.taxonomy_id == 562
                    @test rec.length_bp > 0
                    @test 0.0 <= rec.gc_fraction <= 1.0
                    @test rec.source_db == REFSEQ
                    @test !isempty(rec.replicon_id)
                    @test !isempty(rec.checksum_sha256)
                    @test rec.replicon_type in [CHROMOSOME, PLASMID, OTHER]
                end
                
                println("  ✓ Parsing successful: $(length(records)) replicons")
            end
            
        catch e
            if isa(e, HTTP.Exceptions.RequestError) || isa(e, Base.IOError)
                @warn "Network test skipped (no internet connection or NCBI unavailable)"
            else
                rethrow(e)
            end
        finally
            # Cleanup
            rm(temp_dir; recursive=true, force=true)
        end
    end
    
    @testset "Manifest Format" begin
        # Test that manifest can be written and read correctly
        temp_dir = mktempdir()
        
        try
            # Create sample records
            records = [
                RepliconRecord(
                    "GCF_000005845.2",
                    "GCF_000005845.2_rep1",
                    "NC_000913.3",
                    CHROMOSOME,
                    4641652,
                    0.5079,
                    562,
                    "Escherichia coli str. K-12 substr. MG1655 [K12_Lab]",
                    REFSEQ,
                    today(),
                    "abc123"
                ),
                RepliconRecord(
                    "GCF_000008865.2",
                    "GCF_000008865.2_rep1",
                    "NC_002695.2",
                    CHROMOSOME,
                    5498578,
                    0.5051,
                    562,
                    "Escherichia coli O157:H7 str. Sakai [EHEC_O157H7]",
                    REFSEQ,
                    today(),
                    "def456"
                )
            ]
            
            # Write manifest
            manifest_path = joinpath(temp_dir, "manifest.jsonl")
            open(manifest_path, "w") do io
                for rec in records
                    JSON3.write(io, rec)
                    println(io)
                end
            end
            
            # Verify file exists and is not empty
            @test isfile(manifest_path)
            @test filesize(manifest_path) > 0
            
            # Read and verify
            lines = readlines(manifest_path)
            @test length(lines) == length(records)
            
            # Parse first record
            rec1 = JSON3.read(lines[1])
            @test rec1.assembly_accession == "GCF_000005845.2"
            @test rec1.replicon_id == "GCF_000005845.2_rep1"
            @test rec1.taxonomy_id == 562
            
        finally
            rm(temp_dir; recursive=true, force=true)
        end
    end
    
    @testset "Checksum Verification" begin
        # Test checksum computation
        temp_dir = mktempdir()
        
        try
            # Create a test file
            test_file = joinpath(temp_dir, "test.txt")
            write(test_file, "test content")
            
            # Compute checksum
            using SHA
            checksum = bytes2hex(sha256(read(test_file)))
            
            # Verify format
            @test length(checksum) == 64
            @test all(c -> c in "0123456789abcdef", checksum)
            
            # Verify determinism
            checksum2 = bytes2hex(sha256(read(test_file)))
            @test checksum == checksum2
            
        finally
            rm(temp_dir; recursive=true, force=true)
        end
    end
end
