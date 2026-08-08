// Fase P2 kernel: dinucleotide_summaries (U250).
//
// Redesign of dinucleotide_draws per ADR-0002 item P2:
//   - jump-ahead ROM (host-precomputed table, binary lifting) replaces the
//     O(replicate) sequential stream derivation — the draw sequence stays
//     bit-identical to Fase L (csim anchor, tolerance 0);
//   - one shuffle feeds all 18 metrics (shared shuffle), metrics computed
//     in-kernel without consuming the RNG stream;
//   - in-kernel exact integer summaries (count, mean, mad, q025, q975) —
//     the kernel returns 18x5 int32 per case instead of R raw draws;
//   - replicates capped at kMaxReplicates=1024 on-chip (P3 target n=1000).
// Semantics live in null_core.hpp (shared with the HIP benchmark and csim).
#include "null_core.hpp"

using namespace darwin_null_core;

extern "C" void dinucleotide_summaries(const std::int32_t* windows,
                                        const std::uint64_t* metadata,
                                        std::int32_t* summaries,
                                        std::uint32_t case_count,
                                        std::uint32_t replicates,
                                        std::uint32_t min_effective) {
#pragma HLS INTERFACE m_axi port=windows offset=slave bundle=gmem0
#pragma HLS INTERFACE m_axi port=metadata offset=slave bundle=gmem1
#pragma HLS INTERFACE m_axi port=summaries offset=slave bundle=gmem2
#pragma HLS INTERFACE s_axilite port=windows bundle=control
#pragma HLS INTERFACE s_axilite port=metadata bundle=control
#pragma HLS INTERFACE s_axilite port=summaries bundle=control
#pragma HLS INTERFACE s_axilite port=case_count bundle=control
#pragma HLS INTERFACE s_axilite port=replicates bundle=control
#pragma HLS INTERFACE s_axilite port=min_effective bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

  static std::int32_t values[kMetricCount][kMaxReplicates];
#pragma HLS BIND_STORAGE variable=values type=ram_2p impl=uram
#pragma HLS ARRAY_PARTITION variable=values dim=1 complete

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

    std::uint32_t counts[kMetricCount];
#pragma HLS ARRAY_PARTITION variable=counts complete
    for (std::uint32_t m = 0; m < kMetricCount; ++m) {
#pragma HLS UNROLL
      counts[m] = 0;
    }

    for (std::uint32_t replicate = 1; replicate <= replicates; ++replicate) {
      std::int32_t draw[kCapacity];
#pragma HLS ARRAY_PARTITION variable=draw complete
      const bool ok = make_draw(input, length, seed_high, seed_low, replicate, draw);
      for (std::uint32_t m = 0; m < kMetricCount; ++m) {
        // Fail-closed: a rejected draw is unavailable for every metric,
        // never summarized as data (ADR-0003 boundary).
        const std::int32_t scaled =
            ok ? metric_scaled(draw, length, m, min_effective) : kUnavailable;
        if (scaled >= 0 && counts[m] < kMaxReplicates) {
          values[m][counts[m]] = scaled;
          ++counts[m];
        }
      }
    }

    for (std::uint32_t m = 0; m < kMetricCount; ++m) {
      std::int32_t scratch[kMaxReplicates];
      std::int32_t out[kSummaryFields];
      summarize(values[m], counts[m], scratch, out);
      for (std::uint32_t f = 0; f < kSummaryFields; ++f) {
#pragma HLS UNROLL
        summaries[(item * kMetricCount + m) * kSummaryFields + f] = out[f];
      }
    }
  }
}
