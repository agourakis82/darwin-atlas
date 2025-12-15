using Test
using DarwinAtlas
using BioSequences

@testset "DarwinAtlas" begin
    include("test_operators.jl")
    include("test_symmetry.jl")
end
