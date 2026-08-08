// Fase B3 — Radeon AI PRO R9700 (gfx1201) benchmark for the dinucleotide
// null, sharing null_core.hpp with the U250 P2 kernel (identical semantics,
// ADR-0003). Measures the FULL P2 pipeline per draw: euler_wilson draw +
// 18-metric projection + exact integer summaries — against the U250 Fase L
// draws-only numbers from ADR-0002 section P1.
//
// Kernel 1: one thread per (case, replicate) — draw + 18 metric values.
// Kernel 2: one block per case — 18x five-field summaries (bitonic sort in
// the block, reusing darwin_null_core::summarize).
//
// Markers:
//   R9700_DINUCLEOTIDE_ANCHOR cases=8 replicates=8 slots=1024 mismatches=0
//   R9700_DINUCLEOTIDE_SUMMARY_ANCHOR checked=144 mismatches=0
//   R9700_DINUCLEOTIDE_THROUGHPUT cases=N replicates=R draws=D kernel1_ms=X kernel2_ms=Y total_ms=Z draws_per_second=Q
//   R9700_DINUCLEOTIDE_BENCHMARK_PASS anchor=ok max_replicates=1024
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <vector>

#include <hip/hip_runtime.h>

#include "../generated_fixture.hpp"
#include "../src/null_core.hpp"

using namespace darwin_null_core;

#define HIP_CHECK(x)                                                          \
  do {                                                                        \
    hipError_t e_ = (x);                                                      \
    if (e_ != hipSuccess) {                                                   \
      std::fprintf(stderr, "HIP error %s at %d\n", hipGetErrorString(e_),     \
                   __LINE__);                                                 \
      return 1;                                                               \
    }                                                                         \
  } while (0)

namespace {

std::uint64_t splitmix64(std::uint64_t& state) {
  state += 0x9e3779b97f4a7c15ULL;
  std::uint64_t z = state;
  z = (z ^ (z >> 30U)) * 0xbf58476d1ce4e5b9ULL;
  z = (z ^ (z >> 27U)) * 0x94d049bb133111ebULL;
  return z ^ (z >> 31U);
}

}  // namespace

// values layout: [case][metric][replicate-1]; kUnavailable excluded later.
__global__ void draw_metrics_kernel(const std::int32_t* windows,
                                    const std::uint64_t* metadata,
                                    std::int32_t* values,
                                    std::int32_t* draws_out,
                                    std::uint32_t case_count,
                                    std::uint32_t replicates,
                                    std::uint32_t min_effective) {
  const std::uint64_t tid =
      static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
  const std::uint64_t total =
      static_cast<std::uint64_t>(case_count) * replicates;
  if (tid >= total) {
    return;
  }
  const std::uint32_t item = static_cast<std::uint32_t>(tid / replicates);
  const std::uint32_t replicate = static_cast<std::uint32_t>(tid % replicates) + 1U;

  std::int32_t input[kCapacity];
  for (std::uint32_t i = 0; i < kCapacity; ++i) {
    input[i] = windows[item * kCapacity + i];
  }
  const std::uint32_t length = static_cast<std::uint32_t>(metadata[item * 3U]);
  const std::uint64_t seed_high = metadata[item * 3U + 1U];
  const std::uint64_t seed_low = metadata[item * 3U + 2U];

  std::int32_t draw[kCapacity] = {0};
  const bool ok = make_draw(input, length, seed_high, seed_low, replicate, draw);
  if (draws_out != nullptr) {
    for (std::uint32_t i = 0; i < kCapacity; ++i) {
      draws_out[tid * kCapacity + i] = ok && i < length ? draw[i] : -1;
    }
  }
  for (std::uint32_t m = 0; m < kMetricCount; ++m) {
    const std::int32_t scaled =
        ok ? metric_scaled(draw, length, m, min_effective) : kUnavailable;
    values[(static_cast<std::uint64_t>(item) * kMetricCount + m) * kMaxReplicates +
           (replicate - 1U)] = scaled;
  }
}

// One block per (case, metric); thread 0 compacts + summarizes in shared
// scratch (18432 blocks at probe scale — fills the CUs far better than one
// block per case looping 18 metrics serially).
__global__ void summarize_kernel(const std::int32_t* values,
                                 std::int32_t* summaries,
                                 std::uint32_t replicates) {
  __shared__ std::int32_t scratch[kMaxReplicates];
  const std::uint32_t item = blockIdx.x / kMetricCount;
  const std::uint32_t m = blockIdx.x % kMetricCount;
  const std::int32_t* metric_values =
      values + (static_cast<std::uint64_t>(item) * kMetricCount + m) * kMaxReplicates;
  if (threadIdx.x == 0) {
    std::uint32_t n = 0;
    for (std::uint32_t r = 0; r < replicates; ++r) {
      const std::int32_t v = metric_values[r];
      if (v >= 0) {
        scratch[n++] = v;
      }
    }
    std::int32_t out[kSummaryFields];
    summarize(scratch, n, scratch, out);  // in-place: values already compacted
    for (std::uint32_t f = 0; f < kSummaryFields; ++f) {
      summaries[(static_cast<std::uint64_t>(item) * kMetricCount + m) *
                    kSummaryFields +
                f] = out[f];
    }
  }
}

int main(int argc, char** argv) {
  const std::uint32_t min_effective =
      argc > 1 ? static_cast<std::uint32_t>(std::atoi(argv[1])) : 1U;
  const std::uint32_t probe_cases =
      argc > 2 ? std::min<std::uint32_t>(
                     static_cast<std::uint32_t>(std::atoi(argv[2])), 4096U)
               : 1024U;
  namespace fixture = u250_dinucleotide_fixture;

  HIP_CHECK(hipSetDevice(0));

  // ---- Anchor: frozen 8x8 fixture, draws bit-exact + summaries vs host ----
  {
    std::int32_t *d_windows, *d_values, *d_draws, *d_summaries;
    std::uint64_t* d_metadata;
    HIP_CHECK(hipMalloc(&d_windows, fixture::kWindows.size() * 4));
    HIP_CHECK(hipMalloc(&d_metadata, fixture::kMetadata.size() * 8));
    HIP_CHECK(hipMalloc(&d_draws, fixture::kExpected.size() * 4));
    HIP_CHECK(hipMalloc(&d_values,
                        sizeof(std::int32_t) * fixture::kCaseCount * kMetricCount *
                            kMaxReplicates));
    HIP_CHECK(hipMalloc(&d_summaries,
                        sizeof(std::int32_t) * fixture::kCaseCount * kMetricCount *
                            kSummaryFields));
    HIP_CHECK(hipMemcpy(d_windows, fixture::kWindows.data(),
                        fixture::kWindows.size() * 4, hipMemcpyHostToDevice));
    HIP_CHECK(hipMemcpy(d_metadata, fixture::kMetadata.data(),
                        fixture::kMetadata.size() * 8, hipMemcpyHostToDevice));
    const std::uint32_t total = fixture::kCaseCount * fixture::kReplicates;
    draw_metrics_kernel<<<(total + 255) / 256, 256>>>(
        d_windows, d_metadata, d_values, d_draws, fixture::kCaseCount,
        fixture::kReplicates, min_effective);
    HIP_CHECK(hipGetLastError());
    summarize_kernel<<<fixture::kCaseCount * kMetricCount, 32>>>(d_values, d_summaries,
                                                  fixture::kReplicates);
    HIP_CHECK(hipGetLastError());
    HIP_CHECK(hipDeviceSynchronize());

    std::vector<std::int32_t> draws(fixture::kExpected.size());
    HIP_CHECK(hipMemcpy(draws.data(), d_draws, draws.size() * 4,
                        hipMemcpyDeviceToHost));
    std::uint32_t mismatches = 0;
    for (std::size_t i = 0; i < draws.size(); ++i) {
      if (draws[i] != fixture::kExpected[i]) {
        ++mismatches;
      }
    }
    std::printf("R9700_DINUCLEOTIDE_ANCHOR cases=%u replicates=%u slots=%zu mismatches=%u %s\n",
                fixture::kCaseCount, fixture::kReplicates, draws.size(),
                mismatches, mismatches == 0 ? "PASS" : "FAIL");
    if (mismatches != 0) {
      return 1;
    }

    // Summary anchor: host recomputes from the frozen draws (independent
    // path through the same core) and diffs every field.
    std::vector<std::int32_t> got(fixture::kCaseCount * kMetricCount * kSummaryFields);
    HIP_CHECK(hipMemcpy(got.data(), d_summaries, got.size() * 4,
                        hipMemcpyDeviceToHost));
    std::uint32_t checked = 0, summary_mismatches = 0;
    for (std::uint32_t c = 0; c < fixture::kCaseCount; ++c) {
      const std::uint32_t length =
          static_cast<std::uint32_t>(fixture::kMetadata[c * 3U]);
      for (std::uint32_t m = 0; m < kMetricCount; ++m) {
        std::int32_t host_values[kMaxReplicates];
        std::uint32_t n = 0;
        for (std::uint32_t r = 0; r < fixture::kReplicates; ++r) {
          const std::int32_t* draw = &fixture::kExpected[(c * fixture::kReplicates + r) * kCapacity];
          const std::int32_t scaled = metric_scaled(draw, length, m, min_effective);
          if (scaled >= 0) {
            host_values[n++] = scaled;
          }
        }
        std::int32_t scratch[kMaxReplicates];
        std::int32_t out[kSummaryFields];
        summarize(host_values, n, scratch, out);
        for (std::uint32_t f = 0; f < kSummaryFields; ++f) {
          ++checked;
          if (got[(c * kMetricCount + m) * kSummaryFields + f] != out[f]) {
            ++summary_mismatches;
          }
        }
      }
    }
    std::printf("R9700_DINUCLEOTIDE_SUMMARY_ANCHOR checked=%u mismatches=%u %s\n",
                checked, summary_mismatches,
                summary_mismatches == 0 ? "PASS" : "FAIL");
    hipFree(d_windows); hipFree(d_metadata); hipFree(d_draws);
    hipFree(d_values); hipFree(d_summaries);
    if (summary_mismatches != 0) {
      return 1;
    }
  }

  // ---- Sweep: same 4 graph families / splitmix64 stream as the U250 P1 ----
  const std::size_t window_slots = static_cast<std::size_t>(probe_cases) * kCapacity;
  const std::size_t metadata_slots = static_cast<std::size_t>(probe_cases) * 3U;
  std::vector<std::int32_t> windows(window_slots);
  std::vector<std::uint64_t> metadata(metadata_slots);
  static const std::int32_t kBranching[kCapacity] = {0, 1, 0, 2, 3, 2, 1, 0,
                                                     3, 1, 0, 1, 2, 3, 2, 1};
  std::uint64_t rng = 0x64617277696e2d70ULL;  // "darwin-p" probe stream
  for (std::uint32_t item = 0; item < probe_cases; ++item) {
    const std::uint32_t family = item % 4U;
    for (std::uint32_t i = 0; i < kCapacity; ++i) {
      std::int32_t base = 0;
      if (family == 1U) {
        base = static_cast<std::int32_t>(i % 2U);
      } else if (family == 2U) {
        base = kBranching[i];
      } else if (family == 3U) {
        base = static_cast<std::int32_t>(splitmix64(rng) % 4U);
      }
      windows[static_cast<std::size_t>(item) * kCapacity + i] = base;
    }
    metadata[static_cast<std::size_t>(item) * 3U] = kCapacity;
    metadata[static_cast<std::size_t>(item) * 3U + 1U] = splitmix64(rng);
    metadata[static_cast<std::size_t>(item) * 3U + 2U] = splitmix64(rng);
  }

  std::int32_t *d_windows, *d_values, *d_summaries;
  std::uint64_t* d_metadata;
  HIP_CHECK(hipMalloc(&d_windows, window_slots * 4));
  HIP_CHECK(hipMalloc(&d_metadata, metadata_slots * 8));
  HIP_CHECK(hipMalloc(&d_values,
                      sizeof(std::int32_t) * probe_cases * kMetricCount * kMaxReplicates));
  HIP_CHECK(hipMalloc(&d_summaries,
                      sizeof(std::int32_t) * probe_cases * kMetricCount * kSummaryFields));
  HIP_CHECK(hipMemcpy(d_windows, windows.data(), window_slots * 4,
                      hipMemcpyHostToDevice));
  HIP_CHECK(hipMemcpy(d_metadata, metadata.data(), metadata_slots * 8,
                      hipMemcpyHostToDevice));

  hipEvent_t ev0, ev1, ev2;
  HIP_CHECK(hipEventCreate(&ev0));
  HIP_CHECK(hipEventCreate(&ev1));
  HIP_CHECK(hipEventCreate(&ev2));

  const std::uint32_t sweep[] = {8U, 64U, 256U, 1024U};
  for (const std::uint32_t replicates : sweep) {
    // warmup
    const std::uint32_t total = probe_cases * replicates;
    draw_metrics_kernel<<<(total + 255) / 256, 256>>>(
        d_windows, d_metadata, d_values, nullptr, probe_cases, replicates,
        min_effective);
    summarize_kernel<<<probe_cases * kMetricCount, 32>>>(d_values, d_summaries, replicates);
    HIP_CHECK(hipDeviceSynchronize());

    HIP_CHECK(hipEventRecord(ev0));
    draw_metrics_kernel<<<(total + 255) / 256, 256>>>(
        d_windows, d_metadata, d_values, nullptr, probe_cases, replicates,
        min_effective);
    HIP_CHECK(hipEventRecord(ev1));
    summarize_kernel<<<probe_cases * kMetricCount, 32>>>(d_values, d_summaries, replicates);
    HIP_CHECK(hipEventRecord(ev2));
    HIP_CHECK(hipDeviceSynchronize());
    float ms1 = 0.0f, ms2 = 0.0f;
    HIP_CHECK(hipEventElapsedTime(&ms1, ev0, ev1));
    HIP_CHECK(hipEventElapsedTime(&ms2, ev1, ev2));
    const double draws = static_cast<double>(total);
    const double total_ms = static_cast<double>(ms1) + ms2;
    std::printf(
        "R9700_DINUCLEOTIDE_THROUGHPUT cases=%u replicates=%u draws=%.0f kernel1_ms=%.1f kernel2_ms=%.1f total_ms=%.1f draws_per_second=%llu summaries_per_second=%llu\n",
        probe_cases, replicates, draws, ms1, ms2, total_ms,
        static_cast<unsigned long long>(draws * 1000.0 / total_ms),
        static_cast<unsigned long long>(
            static_cast<double>(probe_cases) * 1000.0 / total_ms));
  }

  std::printf("R9700_DINUCLEOTIDE_BENCHMARK_PASS anchor=ok cases=%u max_replicates=%u\n",
              probe_cases, kMaxReplicates);
  return 0;
}
