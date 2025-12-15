"""
    DarwinAtlas

Darwin Operator Symmetry Atlas - Julia implementation.

Provides Layer 0 (pure Julia reference) and Layer 1 (orchestration + FFI) for
computing operator-defined symmetries in bacterial genomes.

# Exports

## Types
- `SymmetryStats`: Symmetry statistics for a sequence
- `RepliconRecord`: Metadata for a replicon
- `WindowResult`: Results for a sliding window analysis

## Operators (Layer 0)
- `shift`: Cyclic shift operator S
- `reverse_seq`: Reverse operator R
- `complement_seq`: Complement operator K
- `rev_comp`: Reverse complement RC = R ∘ K

## Exact Symmetry
- `orbit_size`: Size of orbit under dihedral group
- `orbit_ratio`: Normalized orbit size
- `is_palindrome`: Check R-fixed
- `is_rc_fixed`: Check RC-fixed

## Approximate Metric
- `dmin`: Minimum dihedral distance
- `dmin_normalized`: d_min / L

## Quaternion Lift
- `dicyclic_element`: Generate Dic_n element
- `verify_double_cover`: Verify Dic_n → D_n cover

## Pipeline
- `fetch_ncbi`: Download genomes from NCBI
- `run_pipeline`: Execute full analysis pipeline
"""
module DarwinAtlas

# Standard library
using Random
using Statistics
using SHA
using Dates

# External packages
using BioSequences
using DataFrames
using CSV
using JSON3

# Module includes
include("Types.jl")
include("Operators.jl")
include("ExactSymmetry.jl")
include("ApproxMetric.jl")
include("QuaternionLift.jl")
include("NCBIFetch.jl")
include("Validation.jl")

# Optional FFI (requires compiled Demetrios library)
const HAS_DEMETRIOS = Ref(false)
function __init__()
    # Check for Demetrios shared library
    libpath = joinpath(@__DIR__, "..", "..", "demetrios", "target", "release", "libdarwin_kernels.so")
    if isfile(libpath)
        HAS_DEMETRIOS[] = true
        include("DemetriosFFI.jl")
        include("CrossValidation.jl")
    end
end

# Exports - Types
export SymmetryStats, RepliconRecord, WindowResult

# Exports - Operators
export shift, reverse_seq, complement_seq, rev_comp
export hamming_distance

# Exports - Exact Symmetry
export orbit_size, orbit_ratio, is_palindrome, is_rc_fixed
export compute_symmetry_stats

# Exports - Approximate Metric
export dmin, dmin_normalized, nearest_transform

# Exports - Quaternion
export DicyclicGroup, DicyclicElement, order
export dicyclic_element, verify_double_cover
export project_to_dihedral, all_elements

# Exports - Pipeline
export fetch_ncbi, run_pipeline, generate_tables

# Exports - Validation
export validate_operators, validate_symmetry, run_technical_validation
export generate_tables, generate_theoretical_tables

end # module
