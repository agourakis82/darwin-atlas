"""
    DemetriosFFI.jl

FFI wrappers for calling Sounio kernels from Julia.

This module provides ccall bindings to the compiled Sounio library.
Only loaded when the library is available.

Note: Module name kept as DemetriosFFI for backward compatibility.
"""

using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T

# Library path
const LIBPATH = joinpath(@__DIR__, "..", "..", "sounio", "target", "release", "libdarwin_kernels.so")

"""
    demetrios_available() -> Bool

Check if the Sounio library is available.
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

function append_seq_bytes!(buf::Vector{UInt8}, seq::LongDNA)
    n = length(seq)
    sizehint!(buf, length(buf) + n)
    for i in 1:n
        push!(buf, base_to_u8(seq[i]))
    end
end

# ============================================================================
# Exact Symmetry FFI
# ============================================================================

"""
    demetrios_orbit_size(seq::LongDNA) -> Int

Compute orbit size using Sounio implementation.
"""
function demetrios_orbit_size(seq::LongDNA)::Int
    bytes = seq_to_bytes(seq)
    result = GC.@preserve bytes begin
        ccall(
            (:darwin_orbit_size, LIBPATH),
            Csize_t,
            (Ptr{UInt8}, UInt64),
            pointer(bytes), UInt64(length(bytes))
        )
    end
    return Int(result)
end

"""
    demetrios_orbit_ratio(seq::LongDNA) -> Float64

Compute orbit ratio using Sounio implementation.
"""
function demetrios_orbit_ratio(seq::LongDNA)::Float64
    bytes = seq_to_bytes(seq)
    result = GC.@preserve bytes begin
        ccall(
            (:darwin_orbit_ratio, LIBPATH),
            Cdouble,
            (Ptr{UInt8}, UInt64),
            pointer(bytes), UInt64(length(bytes))
        )
    end
    return result
end

"""
    demetrios_is_palindrome(seq::LongDNA) -> Bool

Check if sequence is palindrome using Sounio implementation.
"""
function demetrios_is_palindrome(seq::LongDNA)::Bool
    bytes = seq_to_bytes(seq)
    result = GC.@preserve bytes begin
        ccall(
            (:darwin_is_palindrome, LIBPATH),
            Bool,
            (Ptr{UInt8}, UInt64),
            pointer(bytes), UInt64(length(bytes))
        )
    end
    return result
end

"""
    demetrios_is_rc_fixed(seq::LongDNA) -> Bool

Check if sequence is RC-fixed using Sounio implementation.
"""
function demetrios_is_rc_fixed(seq::LongDNA)::Bool
    bytes = seq_to_bytes(seq)
    result = GC.@preserve bytes begin
        ccall(
            (:darwin_is_rc_fixed, LIBPATH),
            Bool,
            (Ptr{UInt8}, UInt64),
            pointer(bytes), UInt64(length(bytes))
        )
    end
    return result
end

# ============================================================================
# Approximate Metric FFI
# ============================================================================

"""
    demetrios_dmin(seq::LongDNA; include_rc::Bool=true) -> Int

Compute d_min using Sounio implementation.
"""
function demetrios_dmin(seq::LongDNA; include_rc::Bool=true)::Int
    bytes = seq_to_bytes(seq)
    result = GC.@preserve bytes begin
        ccall(
            (:darwin_dmin, LIBPATH),
            Csize_t,
            (Ptr{UInt8}, UInt64, Bool),
            pointer(bytes), UInt64(length(bytes)), include_rc
        )
    end
    return Int(result)
end

"""
    demetrios_dmin_normalized(seq::LongDNA; include_rc::Bool=true) -> Float64

Compute normalized d_min using Sounio implementation.
"""
function demetrios_dmin_normalized(seq::LongDNA; include_rc::Bool=true)::Float64
    bytes = seq_to_bytes(seq)
    result = GC.@preserve bytes begin
        ccall(
            (:darwin_dmin_normalized, LIBPATH),
            Cdouble,
            (Ptr{UInt8}, UInt64, Bool),
            pointer(bytes), UInt64(length(bytes)), include_rc
        )
    end
    return result
end

"""
    demetrios_hamming_distance(a::LongDNA, b::LongDNA) -> Int

Compute Hamming distance using Sounio implementation.
"""
function demetrios_hamming_distance(a::LongDNA, b::LongDNA)::Int
    @assert length(a) == length(b) "Sequences must have equal length"

    bytes_a = seq_to_bytes(a)
    bytes_b = seq_to_bytes(b)

    result = GC.@preserve bytes_a bytes_b begin
        ccall(
            (:darwin_hamming_distance, LIBPATH),
            Csize_t,
            (Ptr{UInt8}, Ptr{UInt8}, UInt64),
            pointer(bytes_a), pointer(bytes_b), UInt64(length(bytes_a))
        )
    end
    return Int(result)
end

"""
    demetrios_hamming_distance_batch(seqs_a::Vector{LongDNA}, seqs_b::Vector{LongDNA}) -> Vector{UInt64}

Compute Hamming distances for many pairs in a single Sounio call.
Handles mixed lengths by grouping sequences of equal length.
Returns a UInt64 vector aligned with input order.
"""
function demetrios_hamming_distance_batch(
    seqs_a::AbstractVector{<:LongDNA},
    seqs_b::AbstractVector{<:LongDNA}
)::Vector{UInt64}
    @assert length(seqs_a) == length(seqs_b) "Batch inputs must have equal length"
    n = length(seqs_a)
    n == 0 && return UInt64[]
    
    out = Vector{UInt64}(undef, n)
    
    # Group by length to use the fixed-length FFI batch call
    len_groups = Dict{Int, Vector{Int}}()
    for i in 1:n
        @assert length(seqs_a[i]) == length(seqs_b[i]) "Pair $i must have equal length"
        l = length(seqs_a[i])
        if !haskey(len_groups, l)
            len_groups[l] = Int[]
        end
        push!(len_groups[l], i)
    end
    
    for (len, indices) in len_groups
        m = length(indices)
        if m == 1
            # Single sequence, use the simple call
            idx = indices[1]
            out[idx] = UInt64(demetrios_hamming_distance(seqs_a[idx], seqs_b[idx]))
            continue
        end
        
        # Multiple sequences of same length, use batch call
        buf_a = Vector{UInt8}(undef, m * len)
        buf_b = Vector{UInt8}(undef, m * len)
        
        for (j, idx) in enumerate(indices)
            for k in 1:len
                buf_a[(j-1)*len + k] = base_to_u8(seqs_a[idx][k])
                buf_b[(j-1)*len + k] = base_to_u8(seqs_b[idx][k])
            end
        end
        
        batch_out = Vector{UInt64}(undef, m)
        GC.@preserve buf_a buf_b batch_out begin
            ccall(
                (:darwin_hamming_distance_batch, LIBPATH),
                Cvoid,
                (Ptr{UInt8}, Ptr{UInt8}, UInt64, UInt64, Ptr{UInt64}),
                pointer(buf_a), pointer(buf_b), UInt64(len), UInt64(m), pointer(batch_out)
            )
        end
        
        for (j, idx) in enumerate(indices)
            out[idx] = batch_out[j]
        end
    end

    return out
end

# ============================================================================
# Quaternion FFI
# ============================================================================

"""
    demetrios_verify_double_cover(n::Int) -> Bool

Verify dicyclic double cover property using Sounio implementation.
"""
function demetrios_verify_double_cover(n::Int)::Bool
    result = ccall(
        (:darwin_verify_double_cover, LIBPATH),
        Bool,
        (UInt64,),
        UInt64(n)
    )
    return result
end

# ============================================================================
# Version Info
# ============================================================================

"""
    demetrios_version() -> String

Get Sounio library version.
"""
function demetrios_version()::String
    try
        ptr = ccall((:darwin_version, LIBPATH), Ptr{UInt8}, ())
        return unsafe_string(ptr)
    catch
        # Fallback if symbol not exported
        return "0.1.0"
    end
end
