@testset "Symmetry" begin
    @testset "Orbit computation" begin
        seq = dna"ACGT"
        n = length(seq)
        os = orbit_size(seq)

        @test os >= 1
        @test os <= 2 * n
    end

    @testset "Palindrome detection" begin
        @test !is_palindrome(dna"ACGT")
        @test is_palindrome(dna"ACCA")
        @test is_palindrome(dna"AACCAA")
    end

    @testset "RC-fixed detection" begin
        @test is_rc_fixed(dna"ACGT")
        @test !is_rc_fixed(dna"AACC")
    end

    @testset "d_min bounds" begin
        for seq in [dna"ACGT", dna"ACGTACGT", dna"AAAAAAA"]
            n = length(seq)
            dm = dmin(seq)
            @test 0 <= dm <= n
        end
    end

    @testset "d_min periodic sequence" begin
        seq = dna"ACGTACGT"
        @test dmin(seq; include_rc=false) == 0
    end

    @testset "d_min_normalized range" begin
        seq = dna"ACGTACGTACGT"
        dn = dmin_normalized(seq)
        @test 0.0 <= dn <= 1.0
    end
end

@testset "Quaternion Lift" begin
    @testset "Dicyclic group order" begin
        g = DicyclicGroup(4)
        @test order(g) == 16
    end

    @testset "Double cover verification" begin
        for n in 2:6
            g = DicyclicGroup(n)
            @test verify_double_cover(g)
        end
    end
end
