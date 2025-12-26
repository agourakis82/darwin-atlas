"""
    BitpackDNA.jl

2-bit DNA packing and fast Hamming distance.
"""

using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T

export pack2bit, hamming_distance_packed, hamming_distance_fast

const PACK_BITS = UInt64(0x5555555555555555)

function encode_base_2bit(b)::UInt64
    if b == DNA_A
        return 0x0
    elseif b == DNA_C
        return 0x1
    elseif b == DNA_G
        return 0x2
    elseif b == DNA_T
        return 0x3
    else
        return 0x0
    end
end

"""
    pack2bit(seq::LongDNA) -> Vector{UInt64}

Pack DNA bases into 2-bit words (32 bases per UInt64).
"""
function pack2bit(seq::LongDNA)::Vector{UInt64}
    n = length(seq)
    n == 0 && return UInt64[]

    nwords = cld(n, 32)
    words = fill(UInt64(0), nwords)

    idx = 1
    for w in 1:nwords
        word = UInt64(0)
        for j in 0:31
            idx > n && break
            word |= encode_base_2bit(seq[idx]) << (2 * j)
            idx += 1
        end
        words[w] = word
    end

    return words
end

"""
    hamming_distance_packed(a::LongDNA, b::LongDNA) -> Int

Compute Hamming distance using 2-bit packing.
"""
function hamming_distance_packed(a::LongDNA, b::LongDNA)::Int
    @assert length(a) == length(b) "Sequences must have equal length"
    n = length(a)
    n == 0 && return 0

    wa = pack2bit(a)
    wb = pack2bit(b)

    nwords = length(wa)
    tail = n % 32
    tail_mask = tail == 0 ? UInt64(0xffffffffffffffff) : (UInt64(1) << (2 * tail)) - 1

    mismatches = 0
    for i in 1:nwords
        x = wa[i] ⊻ wb[i]
        if i == nwords
            x &= tail_mask
        end
        x |= x >> 1
        x &= PACK_BITS
        mismatches += count_ones(x)
    end

    return mismatches
end

"""
    hamming_distance_fast(a::LongDNA, b::LongDNA; threshold=128) -> Int

Use packed Hamming when sequences are long enough.
"""
function hamming_distance_fast(a::LongDNA, b::LongDNA; threshold::Int=128)::Int
    @assert length(a) == length(b) "Sequences must have equal length"
    if length(a) >= threshold
        return hamming_distance_packed(a, b)
    end
    # Fallback to scalar for small sequences
    count = 0
    for i in 1:length(a)
        if a[i] != b[i]
            count += 1
        end
    end
    return count
end
