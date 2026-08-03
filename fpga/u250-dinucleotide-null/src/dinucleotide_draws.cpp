#include <cstdint>

namespace {
constexpr std::uint32_t kCapacity = 16;
constexpr std::uint32_t kEdges = 15;
constexpr std::uint64_t kM1 = 2147483563ULL;
constexpr std::uint64_t kM2 = 2147483399ULL;
constexpr std::uint64_t kA1 = 40014ULL;
constexpr std::uint64_t kA2 = 40692ULL;
constexpr std::uint64_t kJump1 = 993186111ULL;
constexpr std::uint64_t kJump2 = 1744472178ULL;

struct RngState {
  std::uint64_t first;
  std::uint64_t second;
};

std::uint64_t rng_step(RngState& state) {
  state.first = (kA1 * state.first) % kM1;
  state.second = (kA2 * state.second) % kM2;
  std::int64_t value = static_cast<std::int64_t>(state.first) -
                       static_cast<std::int64_t>(state.second);
  if (value < 1) {
    value += static_cast<std::int64_t>(kM1 - 1ULL);
  }
  return static_cast<std::uint64_t>(value - 1);
}

std::uint32_t bounded(RngState& state, std::uint32_t bound) {
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

bool make_draw(const std::int32_t input[kCapacity], std::uint32_t length,
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
#pragma HLS ARRAY_PARTITION variable=edge_source complete
#pragma HLS ARRAY_PARTITION variable=edge_target complete
#pragma HLS ARRAY_PARTITION variable=out_degree complete
#pragma HLS ARRAY_PARTITION variable=active complete
#pragma HLS ARRAY_PARTITION variable=in_tree complete
#pragma HLS ARRAY_PARTITION variable=next_edge complete
#pragma HLS ARRAY_PARTITION variable=tree_edge complete
#pragma HLS ARRAY_PARTITION variable=order complete dim=1
#pragma HLS ARRAY_PARTITION variable=cursor complete

  for (std::uint32_t edge = 0; edge < kEdges; ++edge) {
#pragma HLS UNROLL
    edge_source[edge] = -1;
    edge_target[edge] = -1;
  }
  const std::uint32_t edge_count = length - 1U;
  for (std::uint32_t edge = 0; edge < kEdges; ++edge) {
#pragma HLS UNROLL
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

  RngState state{1ULL + seed_high % (kM1 - 1ULL),
                 1ULL + seed_low % (kM2 - 1ULL)};
  for (std::uint32_t stream = 1; stream < replicate; ++stream) {
    state.first = (state.first * kJump1) % kM1;
    state.second = (state.second * kJump2) % kM2;
  }
  const std::int32_t root = input[length - 1U];
  for (std::uint32_t vertex = 0; vertex < 4U; ++vertex) {
#pragma HLS UNROLL
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
#pragma HLS UNROLL
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
}  // namespace

extern "C" void dinucleotide_draws(const std::int32_t* windows,
                                    const std::uint64_t* metadata,
                                    std::int32_t* outputs,
                                    std::uint32_t case_count,
                                    std::uint32_t replicates) {
#pragma HLS INTERFACE m_axi port=windows offset=slave bundle=gmem0
#pragma HLS INTERFACE m_axi port=metadata offset=slave bundle=gmem1
#pragma HLS INTERFACE m_axi port=outputs offset=slave bundle=gmem2
#pragma HLS INTERFACE s_axilite port=windows bundle=control
#pragma HLS INTERFACE s_axilite port=metadata bundle=control
#pragma HLS INTERFACE s_axilite port=outputs bundle=control
#pragma HLS INTERFACE s_axilite port=case_count bundle=control
#pragma HLS INTERFACE s_axilite port=replicates bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

  for (std::uint32_t item = 0; item < case_count; ++item) {
    std::int32_t input[kCapacity];
#pragma HLS ARRAY_PARTITION variable=input complete
    for (std::uint32_t i = 0; i < kCapacity; ++i) {
#pragma HLS UNROLL
      input[i] = windows[item * kCapacity + i];
    }
    const std::uint32_t length = static_cast<std::uint32_t>(metadata[item * 3U]);
    const std::uint64_t seed_high = metadata[item * 3U + 1U];
    const std::uint64_t seed_low = metadata[item * 3U + 2U];
    for (std::uint32_t replicate = 1; replicate <= replicates; ++replicate) {
      std::int32_t draw[kCapacity];
#pragma HLS ARRAY_PARTITION variable=draw complete
      const bool ok = make_draw(input, length, seed_high, seed_low, replicate, draw);
      for (std::uint32_t i = 0; i < kCapacity; ++i) {
#pragma HLS UNROLL
        const std::uint32_t output_index =
            (item * replicates + replicate - 1U) * kCapacity + i;
        outputs[output_index] = ok && i < length ? draw[i] : -1;
      }
    }
  }
}
