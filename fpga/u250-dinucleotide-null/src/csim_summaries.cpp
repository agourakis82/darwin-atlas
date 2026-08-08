// Fase P2 csim anchor for the dinucleotide_summaries kernel semantics.
// Validates, on the frozen Fase L fixture (8 cases x 8 replicates):
//   1. derive_state (jump-ahead ROM) reproduces every frozen draw slot with
//      tolerance 0 — the Fase L kernel semantics is unchanged;
//   2. the 18-metric projection + five exact integer summaries match the
//      independent Python reference (scripts/null_summaries_reference.py).
// Prints machine-checkable markers; the summary block is diffed against the
// reference JSON by scripts/check_summaries_csim.py.
#include <cstdint>
#include <cstdio>

#include "../generated_fixture.hpp"
#include "null_core.hpp"

using namespace darwin_null_core;
namespace fixture = u250_dinucleotide_fixture;

int main(int argc, char** argv) {
  const std::uint32_t min_effective =
      argc > 1 ? static_cast<std::uint32_t>(std::atoi(argv[1])) : 1U;

  // 1. Draw anchor: every frozen slot bit-exact.
  std::uint32_t slot_mismatches = 0;
  for (std::uint32_t c = 0; c < fixture::kCaseCount; ++c) {
    std::int32_t input[kCapacity];
    for (std::uint32_t i = 0; i < kCapacity; ++i) {
      input[i] = fixture::kWindows[c * kCapacity + i];
    }
    const std::uint32_t length = static_cast<std::uint32_t>(fixture::kMetadata[c * 3U]);
    const std::uint64_t seed_high = fixture::kMetadata[c * 3U + 1U];
    const std::uint64_t seed_low = fixture::kMetadata[c * 3U + 2U];
    for (std::uint32_t r = 1; r <= fixture::kReplicates; ++r) {
      std::int32_t draw[kCapacity] = {0};
      const bool ok = make_draw(input, length, seed_high, seed_low, r, draw);
      for (std::uint32_t i = 0; i < kCapacity; ++i) {
        const std::int32_t expected = fixture::kExpected[(c * fixture::kReplicates + r - 1U) * kCapacity + i];
        const std::int32_t got = ok && i < length ? draw[i] : -1;
        if (got != expected) {
          ++slot_mismatches;
        }
      }
    }
  }
  std::printf("P2_CSIM_ANCHOR cases=%u replicates=%u slots=%u mismatches=%u %s\n",
              fixture::kCaseCount, fixture::kReplicates, fixture::kCaseCount * fixture::kReplicates * kCapacity,
              slot_mismatches, slot_mismatches == 0 ? "PASS" : "FAIL");
  if (slot_mismatches != 0) {
    return 1;
  }

  // 2. Summaries: same per-case flow as the HLS kernel top.
  std::printf("P2_CSIM_SUMMARIES_BEGIN min_effective=%u\n", min_effective);
  for (std::uint32_t c = 0; c < fixture::kCaseCount; ++c) {
    std::int32_t input[kCapacity];
    for (std::uint32_t i = 0; i < kCapacity; ++i) {
      input[i] = fixture::kWindows[c * kCapacity + i];
    }
    const std::uint32_t length = static_cast<std::uint32_t>(fixture::kMetadata[c * 3U]);
    const std::uint64_t seed_high = fixture::kMetadata[c * 3U + 1U];
    const std::uint64_t seed_low = fixture::kMetadata[c * 3U + 2U];

    std::int32_t values[kMetricCount][kMaxReplicates];
    std::uint32_t counts[kMetricCount] = {0};
    for (std::uint32_t r = 1; r <= fixture::kReplicates; ++r) {
      std::int32_t draw[kCapacity] = {0};
      const bool ok = make_draw(input, length, seed_high, seed_low, r, draw);
      for (std::uint32_t m = 0; m < kMetricCount; ++m) {
        const std::int32_t scaled =
            ok ? metric_scaled(draw, length, m, min_effective) : kUnavailable;
        if (scaled >= 0) {
          values[m][counts[m]++] = scaled;
        }
      }
    }
    for (std::uint32_t m = 0; m < kMetricCount; ++m) {
      std::int32_t scratch[kMaxReplicates];
      std::int32_t out[kSummaryFields];
      summarize(values[m], counts[m], scratch, out);
      std::printf("P2_CSIM_SUMMARY case=%u metric=%u count=%d mean=%d mad=%d q025=%d q975=%d\n",
                  c, m, out[0], out[1], out[2], out[3], out[4]);
    }
  }
  std::printf("P2_CSIM_SUMMARIES_END\n");
  return 0;
}
