"""
    DemetriosFFI.jl

FFI wrappers for calling Demetrios kernels from Julia.

This module provides ccall bindings to the compiled Demetrios library.
Only loaded when the library is available.
"""

using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T

# Library path
const LIBPATH = joinpath(@__DIR__, "..", "..", "demetrios", "target", "release", "libdarwin_kernels.so")

"""
    demetrios_available() -> Bool

Check if the Demetrios library is available.
"""
function demetrios_available()::Bool
    return isfile(LIBPATH)
end

"""
    base_to_u8(base::DNA) -> UInt8

Convert BioSequences DNA base to 2-bit encoding.
A=0, C=1, G=2, T=3
"""
function base_to_u8(base)::UInt8
    if base == DNA_A
        return 0x00
    elseif base == DNA_C
        return 0x01
    elseif base == DNA_G
        return 0x02
    elseif base == DNA_T
        return 0x03
    else
        error("Invalid DNA base: $base")
    end
end

"""
    seq_to_bytes(seq::LongDNA) -> Vector{UInt8}

Convert a LongDNA sequence to byte array for FFI.
"""
function seq_to_bytes(seq::LongDNA)::Vector{UInt8}
    return [base_to_u8(seq[i]) for i in 1:length(seq)]
end

# ============================================================================
# Exact Symmetry FFI
# ============================================================================

"""
    demetrios_orbit_size(seq::LongDNA) -> Int

Compute orbit size using Demetrios implementation.
"""
function demetrios_orbit_size(seq::LongDNA)::Int
    bytes = seq_to_bytes(seq)
    result = ccall(
        (:darwin_orbit_size, LIBPATH),
        Csize_t,
        (Ptr{UInt8}, Csize_t),
        bytes, length(bytes)
    )
    return Int(result)
end

"""
    demetrios_orbit_ratio(seq::LongDNA) -> Float64

Compute orbit ratio using Demetrios implementation.
"""
function demetrios_orbit_ratio(seq::LongDNA)::Float64
    bytes = seq_to_bytes(seq)
    result = ccall(
        (:darwin_orbit_ratio, LIBPATH),
        Cdouble,
        (Ptr{UInt8}, Csize_t),
        bytes, length(bytes)
    )
    return result
end

"""
    demetrios_is_palindrome(seq::LongDNA) -> Bool

Check if sequence is palindrome using Demetrios implementation.
"""
function demetrios_is_palindrome(seq::LongDNA)::Bool
    bytes = seq_to_bytes(seq)
    result = ccall(
        (:darwin_is_palindrome, LIBPATH),
        Bool,
        (Ptr{UInt8}, Csize_t),
        bytes, length(bytes)
    )
    return result
end

"""
    demetrios_is_rc_fixed(seq::LongDNA) -> Bool

Check if sequence is RC-fixed using Demetrios implementation.
"""
function demetrios_is_rc_fixed(seq::LongDNA)::Bool
    bytes = seq_to_bytes(seq)
    result = ccall(
        (:darwin_is_rc_fixed, LIBPATH),
        Bool,
        (Ptr{UInt8}, Csize_t),
        bytes, length(bytes)
    )
    return result
end

# ============================================================================
# Approximate Metric FFI
# ============================================================================

"""
    demetrios_dmin(seq::LongDNA; include_rc::Bool=true) -> Int

Compute d_min using Demetrios implementation.
"""
function demetrios_dmin(seq::LongDNA; include_rc::Bool=true)::Int
    bytes = seq_to_bytes(seq)
    result = ccall(
        (:darwin_dmin, LIBPATH),
        Csize_t,
        (Ptr{UInt8}, Csize_t, Bool),
        bytes, length(bytes), include_rc
    )
    return Int(result)
end

"""
    demetrios_dmin_normalized(seq::LongDNA; include_rc::Bool=true) -> Float64

Compute normalized d_min using Demetrios implementation.
"""
function demetrios_dmin_normalized(seq::LongDNA; include_rc::Bool=true)::Float64
    bytes = seq_to_bytes(seq)
    result = ccall(
        (:darwin_dmin_normalized, LIBPATH),
        Cdouble,
        (Ptr{UInt8}, Csize_t, Bool),
        bytes, length(bytes), include_rc
    )
    return result
end

"""
    demetrios_hamming_distance(a::LongDNA, b::LongDNA) -> Int

Compute Hamming distance using Demetrios implementation.
"""
function demetrios_hamming_distance(a::LongDNA, b::LongDNA)::Int
    @assert length(a) == length(b) "Sequences must have equal length"

    bytes_a = seq_to_bytes(a)
    bytes_b = seq_to_bytes(b)

    result = ccall(
        (:darwin_hamming_distance, LIBPATH),
        Csize_t,
        (Ptr{UInt8}, Ptr{UInt8}, Csize_t),
        bytes_a, bytes_b, length(bytes_a)
    )
    return Int(result)
end

# ============================================================================
# Quaternion FFI
# ============================================================================

"""
    demetrios_verify_double_cover(n::Int) -> Bool

Verify dicyclic double cover property using Demetrios implementation.
"""
function demetrios_verify_double_cover(n::Int)::Bool
    result = ccall(
        (:darwin_verify_double_cover, LIBPATH),
        Bool,
        (Csize_t,),
        n
    )
    return result
end

# ============================================================================
# Version Info
# ============================================================================

"""
    demetrios_version() -> String

Get Demetrios library version.
"""
function demetrios_version()::String
    ptr = ccall((:darwin_version, LIBPATH), Ptr{UInt8}, ())
    return unsafe_string(ptr)
end

