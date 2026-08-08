// Darwin ATLAS — dinucleotide-null shared semantics core (Fase P2).
//
// Single source of truth for the euler_wilson_fixed_endpoints_v1 draw
// (ADR-0003), the 18-metric projection (spec 0.1.0 section 7), and the
// five exact integer null summaries (ADR-0003 / window schema 0.3.0).
// Portable C++17: compiles under Vitis HLS (kernel), HIP (ROCm benchmark),
// and plain host g++ (csim / reference anchors). No dynamic allocation, no
// floating point, no RNG consumption outside make_draw.
#pragma once

#include <cstdint>

// Portable host/device annotation: HIP kernels call the core from device
// code; HLS and plain g++ see plain functions.
#if defined(__HIPCC__)
#include <hip/hip_runtime.h>
#define DNC_HD __host__ __device__
#else
#define DNC_HD
#endif

namespace darwin_null_core {

constexpr std::uint32_t kCapacity = 16;
constexpr std::uint32_t kEdges = 15;
constexpr std::uint32_t kMetricCount = 18;   // 2 positional + 8 k x 2 transforms
constexpr std::uint32_t kMaxReplicates = 1024;
constexpr std::uint32_t kSummaryFields = 5;  // count, mean, mad, q025, q975
constexpr std::int32_t kUnavailable = -1;

// ---------------------------------------------------------------------------
// L'Ecuyer combined generator (ADR-0003 item 6). Replicate streams separated
// by 2^20 steps; jump multipliers verified as a{1,2}^(2^20) mod m{1,2}.
// ---------------------------------------------------------------------------
constexpr std::uint64_t kM1 = 2147483563ULL;
constexpr std::uint64_t kM2 = 2147483399ULL;
constexpr std::uint64_t kA1 = 40014ULL;
constexpr std::uint64_t kA2 = 40692ULL;
constexpr std::uint64_t kJump1 = 993186111ULL;    // kA1^(2^20) mod kM1
constexpr std::uint64_t kJump2 = 1744472178ULL;   // kA2^(2^20) mod kM2

// Fase P2 jump-ahead ROM: kJumpRom{1,2}[i] = kJump{1,2}^(2^i) mod m{1,2}.
// Independently derived (pow table) and proven equivalent to sequential
// jumping for every replicate 1..1024 during csim.
constexpr std::uint64_t kJumpRom1[11] = {
    993186111ULL, 148024010ULL, 2030722398ULL, 1248949068ULL,
    1293735570ULL, 1686750381ULL, 2022572795ULL, 1369073225ULL,
    817637002ULL, 162771853ULL, 1033780774ULL};
constexpr std::uint64_t kJumpRom2[11] = {
    1744472178ULL, 725489045ULL, 965718186ULL, 960416771ULL,
    819929636ULL, 629552648ULL, 518680307ULL, 1000222375ULL,
    450561292ULL, 228670867ULL, 1494757890ULL};

struct RngState {
  std::uint64_t first;
  std::uint64_t second;
};

DNC_HD inline std::uint64_t rng_step(RngState& state) {
  state.first = (kA1 * state.first) % kM1;
  state.second = (kA2 * state.second) % kM2;
  std::int64_t value = static_cast<std::int64_t>(state.first) -
                       static_cast<std::int64_t>(state.second);
  if (value < 1) {
    value += static_cast<std::int64_t>(kM1 - 1ULL);
  }
  return static_cast<std::uint64_t>(value - 1);
}

DNC_HD inline std::uint32_t bounded(RngState& state, std::uint32_t bound) {
  if (bound <= 1U) {
    return 0U;
  }
  const std::uint64_t range = kM1 - 1ULL;
  const std::uint64_t limit = range - (range % bound);
  for (;;) {
    const std::uint64_t value = rng_step(state);
    if (value < limit) {
      return static_cast<std::uint32_t>(value % bound);
    }
  }
}

// Direct replicate-stream derivation: state_r = seed * kJump^(r-1) mod m via
// binary lifting over the ROM. Exactly the residue of the Fase L sequential
// loop, at O(log r) instead of O(r).
DNC_HD inline RngState derive_state(std::uint64_t seed_high, std::uint64_t seed_low,
                             std::uint32_t replicate) {
  RngState state{1ULL + seed_high % (kM1 - 1ULL),
                 1ULL + seed_low % (kM2 - 1ULL)};
  std::uint32_t exponent = replicate - 1U;
  for (std::uint32_t bit = 0; bit < 11U; ++bit) {
    if ((exponent >> bit) & 1U) {
      state.first = (state.first * kJumpRom1[bit]) % kM1;
      state.second = (state.second * kJumpRom2[bit]) % kM2;
    }
  }
  return state;
}

// ---------------------------------------------------------------------------
// euler_wilson_fixed_endpoints_v1 draw — byte-identical semantics to the
// Fase L kernel (fpga/u250-dinucleotide-null/src/dinucleotide_draws.cpp).
// ---------------------------------------------------------------------------
DNC_HD inline bool make_draw(const std::int32_t input[kCapacity], std::uint32_t length,
                      std::uint64_t seed_high, std::uint64_t seed_low,
                      std::uint32_t replicate, std::int32_t output[kCapacity]) {
  std::int32_t edge_source[kEdges];
  std::int32_t edge_target[kEdges];
  std::uint32_t out_degree[4] = {0, 0, 0, 0};
  bool active[4] = {false, false, false, false};
  bool in_tree[4] = {false, false, false, false};
  std::int32_t next_edge[4] = {-1, -1, -1, -1};
  std::int32_t tree_edge[4] = {-1, -1, -1, -1};
  std::int32_t order[4][kCapacity];
  std::uint32_t cursor[4] = {0, 0, 0, 0};

  for (std::uint32_t edge = 0; edge < kEdges; ++edge) {
    edge_source[edge] = -1;
    edge_target[edge] = -1;
  }
  const std::uint32_t edge_count = length - 1U;
  for (std::uint32_t edge = 0; edge < kEdges; ++edge) {
    if (edge < edge_count) {
      const std::int32_t source = input[edge];
      const std::int32_t target = input[edge + 1U];
      edge_source[edge] = source;
      edge_target[edge] = target;
      ++out_degree[source];
      active[source] = true;
      active[target] = true;
    }
  }

  RngState state = derive_state(seed_high, seed_low, replicate);
  const std::int32_t root = input[length - 1U];
  for (std::uint32_t vertex = 0; vertex < 4U; ++vertex) {
    in_tree[vertex] = !active[vertex];
  }
  in_tree[root] = true;

  for (std::uint32_t start = 0; start < 4U; ++start) {
    std::int32_t current = static_cast<std::int32_t>(start);
    bool failed = false;
    for (std::uint32_t safety = 0; safety < 4096U; ++safety) {
      if (in_tree[current]) {
        break;
      }
      if (out_degree[current] == 0U) {
        failed = true;
        break;
      }
      const std::uint32_t rank = bounded(state, out_degree[current]);
      std::uint32_t seen = 0;
      std::int32_t chosen = -1;
      for (std::uint32_t edge = 0; edge < kEdges; ++edge) {
        if (edge_source[edge] == current) {
          if (seen == rank) {
            chosen = static_cast<std::int32_t>(edge);
          }
          ++seen;
        }
      }
      if (chosen < 0) {
        failed = true;
        break;
      }
      next_edge[current] = chosen;
      current = edge_target[chosen];
    }
    if (failed || !in_tree[current]) {
      return false;
    }
    current = static_cast<std::int32_t>(start);
    for (std::uint32_t safety = 0; safety < 4U; ++safety) {
      if (in_tree[current]) {
        break;
      }
      const std::int32_t chosen = next_edge[current];
      if (chosen < 0) {
        return false;
      }
      in_tree[current] = true;
      tree_edge[current] = chosen;
      current = edge_target[chosen];
    }
    if (!in_tree[current]) {
      return false;
    }
  }

  for (std::uint32_t vertex = 0; vertex < 4U; ++vertex) {
    std::uint32_t count = 0;
    for (std::uint32_t edge = 0; edge < kEdges; ++edge) {
      if (edge < edge_count && edge_source[edge] == static_cast<std::int32_t>(vertex)) {
        order[vertex][count++] = static_cast<std::int32_t>(edge);
      }
    }
    for (std::uint32_t remaining = kCapacity; remaining > 1U; --remaining) {
      const std::uint32_t i = remaining - 1U;
      if (i < count) {
        const std::uint32_t j = bounded(state, i + 1U);
        const std::int32_t temporary = order[vertex][i];
        order[vertex][i] = order[vertex][j];
        order[vertex][j] = temporary;
      }
    }
    if (static_cast<std::int32_t>(vertex) != root && active[vertex]) {
      std::int32_t position = -1;
      for (std::uint32_t i = 0; i < kCapacity; ++i) {
        if (i < count && order[vertex][i] == tree_edge[vertex]) {
          position = static_cast<std::int32_t>(i);
        }
      }
      if (position < 0) {
        return false;
      }
      const std::int32_t temporary = order[vertex][position];
      order[vertex][position] = order[vertex][count - 1U];
      order[vertex][count - 1U] = temporary;
    }
  }

  std::int32_t current = input[0];
  output[0] = current;
  for (std::uint32_t step = 0; step < kEdges; ++step) {
    if (step < edge_count) {
      const std::uint32_t at = cursor[current]++;
      if (at >= out_degree[current]) {
        return false;
      }
      const std::int32_t chosen = order[current][at];
      if (edge_source[chosen] != current) {
        return false;
      }
      current = edge_target[chosen];
      output[step + 1U] = current;
    }
  }
  return current == root;
}

// ---------------------------------------------------------------------------
// 18-metric projection (spec 0.1.0 section 7; window_pipeline_core.jl exact
// mirror). metric 0 = delta_R, 1 = delta_RC; for k in 1..8 metric 2k =
// reverse_kmer_imbalance_k, 2k+1 = rc_kmer_imbalance_k. Scaled floor(x*1e6/d)
// integer ratios; kUnavailable when below min_effective or empty denominator.
// Metrics never consume the RNG stream.
// ---------------------------------------------------------------------------
DNC_HD inline std::int32_t positional_scaled(const std::int32_t* seq, std::uint32_t length,
                                      std::uint32_t metric_index) {
  std::uint32_t mismatches = 0;
  for (std::uint32_t i = 0; i < length; ++i) {
    const std::int32_t opposite = seq[length - 1U - i];
    const std::int32_t expected =
        metric_index == 0U ? opposite : (3 - opposite);
    if (seq[i] != expected) {
      ++mismatches;
    }
  }
  return static_cast<std::int32_t>(
      (static_cast<std::uint64_t>(mismatches) * 1000000ULL) / length);
}

// Base-4 k-mer encode (first base most significant: numeric order equals the
// Julia lexicographic string order), reverse and reverse-complement
// transforms as digit operations.
DNC_HD inline std::uint32_t kmer_encode(const std::int32_t* seq, std::uint32_t start,
                                 std::uint32_t k) {
  std::uint32_t value = 0;
  for (std::uint32_t i = 0; i < k; ++i) {
    value = (value << 2) | static_cast<std::uint32_t>(seq[start + i]);
  }
  return value;
}

DNC_HD inline std::uint32_t kmer_reverse(std::uint32_t value, std::uint32_t k) {
  std::uint32_t result = 0;
  for (std::uint32_t i = 0; i < k; ++i) {
    result = (result << 2) | (value & 3U);
    value >>= 2;
  }
  return result;
}

DNC_HD inline std::uint32_t kmer_rc(std::uint32_t value, std::uint32_t k) {
  std::uint32_t result = 0;
  for (std::uint32_t i = 0; i < k; ++i) {
    result = (result << 2) | (3U - (value & 3U));
    value >>= 2;
  }
  return result;
}

DNC_HD inline std::int32_t kmer_imbalance_scaled(const std::int32_t* seq, std::uint32_t length,
                                          std::uint32_t metric_index,
                                          std::uint32_t min_effective) {
  const std::uint32_t k = metric_index / 2U;
  const bool use_rc = (metric_index & 1U) != 0U;
  if (length < k) {
    return kUnavailable;
  }
  const std::uint32_t effective = length - k + 1U;
  if (effective < min_effective) {
    return kUnavailable;
  }

  // Observed k-mers with counts (at most kCapacity distinct slots).
  std::uint32_t obs_kmer[kCapacity];
  std::uint32_t obs_count[kCapacity];
  std::uint32_t n_obs = 0;
  for (std::uint32_t start = 0; start < effective; ++start) {
    const std::uint32_t u = kmer_encode(seq, start, k);
    std::uint32_t slot = n_obs;
    for (std::uint32_t s = 0; s < n_obs; ++s) {
      if (obs_kmer[s] == u) {
        slot = s;
        break;
      }
    }
    if (slot == n_obs) {
      obs_kmer[n_obs] = u;
      obs_count[n_obs] = 0;
      ++n_obs;
    }
    ++obs_count[slot];
  }

  // Orbit accumulation, representative min(u, T(u)) — matches the Julia
  // candidate-set semantics exactly (zero-count partners counted once).
  std::uint64_t numerator = 0;
  std::uint64_t denominator = 0;
  for (std::uint32_t s = 0; s < n_obs; ++s) {
    const std::uint32_t u = obs_kmer[s];
    const std::uint32_t v = use_rc ? kmer_rc(u, k) : kmer_reverse(u, k);
    if (u == v) {
      denominator += obs_count[s];
    } else if (u < v) {
      std::uint32_t right = 0;
      for (std::uint32_t t = 0; t < n_obs; ++t) {
        if (obs_kmer[t] == v) {
          right = obs_count[t];
          break;
        }
      }
      const std::uint32_t left = obs_count[s];
      numerator += left > right ? left - right : right - left;
      denominator += static_cast<std::uint64_t>(left) + right;
    }
  }
  if (denominator == 0) {
    return kUnavailable;
  }
  return static_cast<std::int32_t>((numerator * 1000000ULL) / denominator);
}

DNC_HD inline std::int32_t metric_scaled(const std::int32_t* seq, std::uint32_t length,
                                  std::uint32_t metric_index,
                                  std::uint32_t min_effective) {
  if (metric_index < 2U) {
    return positional_scaled(seq, length, metric_index);
  }
  return kmer_imbalance_scaled(seq, length, metric_index, min_effective);
}

// ---------------------------------------------------------------------------
// Five exact integer summaries over available scaled draws (window schema
// 0.3.0): count, floored mean, exact MAD from the rational mean, nearest-rank
// q025/q975. Sorting: sequential bitonic over the on-chip value array, padded
// with INT32_MAX (sorts to the tail, excluded by count).
// ---------------------------------------------------------------------------
DNC_HD inline void bitonic_sort(std::int32_t* values, std::uint32_t n_padded) {
  for (std::uint32_t size = 2; size <= n_padded; size <<= 1) {
    for (std::uint32_t stride = size >> 1; stride > 0; stride >>= 1) {
      for (std::uint32_t i = 0; i < n_padded; ++i) {
        const std::uint32_t j = i ^ stride;
        if (j > i) {
          const bool ascending = ((i & size) == 0U);
          const std::int32_t a = values[i];
          const std::int32_t b = values[j];
          if ((a > b) == ascending) {
            values[i] = b;
            values[j] = a;
          }
        }
      }
    }
  }
}

// values: n available scaled draws (n <= kMaxReplicates). out: 5 fields.
DNC_HD inline void summarize(const std::int32_t* values, std::uint32_t n,
                      std::int32_t* scratch, std::int32_t out[kSummaryFields]) {
  if (n == 0) {
    out[0] = 0;
    out[1] = kUnavailable;
    out[2] = kUnavailable;
    out[3] = kUnavailable;
    out[4] = kUnavailable;
    return;
  }
  std::int64_t total = 0;
  for (std::uint32_t i = 0; i < n; ++i) {
    total += values[i];
    scratch[i] = values[i];
  }
  for (std::uint32_t i = n; i < kMaxReplicates; ++i) {
    scratch[i] = 0x7FFFFFFF;
  }
  const std::int64_t count = static_cast<std::int64_t>(n);
  const std::int32_t mean = static_cast<std::int32_t>(total / count);
  std::int64_t mad_sum = 0;
  for (std::uint32_t i = 0; i < n; ++i) {
    const std::int64_t delta = count * static_cast<std::int64_t>(values[i]) - total;
    mad_sum += delta < 0 ? -delta : delta;
  }
  const std::int32_t mad = static_cast<std::int32_t>(mad_sum / (count * count));
  bitonic_sort(scratch, kMaxReplicates);
  const std::int32_t q025 = scratch[(25U * (n - 1U)) / 100U];
  const std::int32_t q975 = scratch[(975U * (n - 1U)) / 1000U];
  out[0] = static_cast<std::int32_t>(n);
  out[1] = mean;
  out[2] = mad;
  out[3] = q025;
  out[4] = q975;
}

}  // namespace darwin_null_core
