"""
    Types.jl

Core type definitions for Darwin Atlas.
"""

using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T
using Dates

# Re-export DNA types
export LongDNA, DNA_A, DNA_C, DNA_G, DNA_T

"""
    RepliconType

Enumeration of replicon types.
"""
@enum RepliconType begin
    CHROMOSOME
    PLASMID
    OTHER
end

"""
    SourceDB

Source database enumeration.
"""
@enum SourceDB begin
    REFSEQ
    GENBANK
end

"""
    RepliconRecord

Metadata for a single replicon (chromosome or plasmid).
"""
struct RepliconRecord
    assembly_accession::String
    replicon_id::String
    replicon_accession::Union{String, Nothing}
    replicon_type::RepliconType
    length_bp::Int64
    gc_fraction::Float64
    taxonomy_id::Int64
    taxonomy_name::String
    source_db::SourceDB
    download_date::Date
    checksum_sha256::String
end

"""
    SymmetryStats

Symmetry statistics for a DNA sequence.
"""
struct SymmetryStats
    length::Int
    orbit_size::Int
    orbit_ratio::Float64
    is_palindrome::Bool
    is_rc_fixed::Bool
    rotational_period::Int
end

"""
    WindowResult

Results from analyzing a single window.
"""
struct WindowResult
    replicon_id::String
    window_length::Int
    window_start::Int  # 0-indexed
    orbit_ratio::Float64
    is_palindrome::Bool
    is_rc_fixed::Bool
    orbit_size::Int
    dmin::Int
    dmin_normalized::Float64
end

"""
    TransformFamily

Classification of dihedral transforms.
"""
@enum TransformFamily begin
    SHIFT           # S^k
    REVERSE_SHIFT   # R ∘ S^k
    RC_SHIFT        # RC ∘ S^k
end

"""
    NearestTransform

Information about the transform achieving d_min.
"""
struct NearestTransform
    family::TransformFamily
    k::Int  # Shift amount
    distance::Int
end

"""
    DicyclicLiftResult

Results from dicyclic group verification.
"""
struct DicyclicLiftResult
    replicon_id::String
    dihedral_order::Int
    verified_double_cover::Bool
    lift_group::String
    verification_method::String
    num_elements_checked::Int
    relations_satisfied::Bool
end

"""
    QuaternionExperimentResult

Results from quaternion encoding experiments.
"""
struct QuaternionExperimentResult
    experiment_id::String
    condition::Symbol  # :group or :semigroup
    chain_length::Int
    n_trials::Int
    seed::Int
    baseline_markov1_acc::Float64
    baseline_markov2_acc::Float64
    quaternion_acc::Float64
    p_value_vs_markov2::Float64
end

"""
    PipelineMetadata

Metadata for a pipeline run.
"""
struct PipelineMetadata
    run_id::String
    start_time::DateTime
    end_time::Union{DateTime, Nothing}
    julia_version::String
    package_versions::Dict{String, String}
    parameters::Dict{String, Any}
    random_seed::Int
    status::Symbol  # :running, :completed, :failed
end
