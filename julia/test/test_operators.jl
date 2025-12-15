@testset "Operators" begin
    seq = dna"ACGTACGT"
    n = length(seq)

    @testset "Shift operator S" begin
        @test shift(seq, 0) == seq
        @test shift(seq, n) == seq
        @test shift(seq, 1) == dna"CGTACGTA"
        @test shift(shift(seq, 2), 3) == shift(seq, 5)
    end

    @testset "Reverse operator R" begin
        @test reverse_seq(reverse_seq(seq)) == seq
        @test reverse_seq(dna"ACGT") == dna"TGCA"
    end

    @testset "Complement operator K" begin
        @test complement_seq(complement_seq(seq)) == seq
        @test complement_seq(dna"ACGT") == dna"TGCA"
    end

    @testset "Reverse complement RC" begin
        @test rev_comp(rev_comp(seq)) == seq
        @test rev_comp(seq) == reverse_seq(complement_seq(seq))
        @test rev_comp(seq) == complement_seq(reverse_seq(seq))
        @test rev_comp(dna"ACGT") == dna"ACGT"  # RC-palindrome
    end

    @testset "Hamming distance" begin
        @test hamming_distance(dna"ACGT", dna"ACGT") == 0
        @test hamming_distance(dna"ACGT", dna"TGCA") == 4
        @test hamming_distance(dna"ACGT", dna"ACGA") == 1
    end

    @testset "Dihedral relations" begin
        seq = dna"ACGTACGTAA"
        n = length(seq)
        for k in 1:5
            lhs = reverse_seq(shift(seq, k))
            rhs = shift(reverse_seq(seq), n - k)
            @test lhs == rhs
        end
    end
end
