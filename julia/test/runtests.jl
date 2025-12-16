using Test
using DarwinAtlas
using BioSequences

@testset "DarwinAtlas" begin
include("test_operators.jl")
include("test_symmetry.jl")
include("test_biology_metrics.jl")
end
