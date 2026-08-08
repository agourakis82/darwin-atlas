// Fase P2 hardware probe for the dinucleotide_summaries kernel (U250).
//
// Mirrors the P1 probe structure against the v2 kernel interface:
//   1. Correctness anchor — frozen Fase L 8x8 fixture; every one of the 720
//      expected summary fields (generated_summaries_fixture.hpp, reference:
//      scripts/null_summaries_reference.py, min_effective=1) must match with
//      tolerance 0. Exits before any throughput measurement on failure.
//   2. Throughput sweep — the same 1024 synthetic windows / splitmix64 seed
//      stream as the P1 probe; reports per-case and per-draw rates for the
//      full pipeline (draw + 18 metrics + summaries).
//   3. Integrity — on the R=8 batch every summary block is validated:
//      0 < count <= R, fields in [0, 1e6] (or -1 for unavailable metrics
//      only when count == 0), q025 <= mean-range check, q025 <= q975.
//
// Markers:
//   U250_SUMMARIES_ANCHOR cases=8 metrics=18 fields=720 tolerance=0
//   U250_SUMMARIES_THROUGHPUT cases=N replicates=R wall_ms=W cases_per_second=C draws_per_second=D
//   U250_SUMMARIES_INTEGRITY cases=N replicates=8 blocks_ok=B
//   U250_SUMMARIES_PASS anchor=ok cases=N max_replicates=1024
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>

#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_hw_context.h>
#include <xrt/xrt_kernel.h>
#include <xrt/experimental/xrt_xclbin.h>

#include "../generated_fixture.hpp"
#include "../generated_summaries_fixture.hpp"

namespace {

std::uint64_t splitmix64(std::uint64_t& state) {
  state += 0x9e3779b97f4a7c15ULL;
  std::uint64_t z = state;
  z = (z ^ (z >> 30U)) * 0xbf58476d1ce4e5b9ULL;
  z = (z ^ (z >> 27U)) * 0x94d049bb133111ebULL;
  return z ^ (z >> 31U);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2 || argc > 3) {
    std::cerr << "usage: " << argv[0]
              << " <dinucleotide_summaries.xclbin> [probe_cases]\n";
    return 2;
  }
  try {
    namespace fixture = u250_dinucleotide_fixture;
    namespace expected = u250_dinucleotide_summaries_fixture;
    constexpr std::uint32_t kMetricCount = 18;
    constexpr std::uint32_t kSummaryFields = 5;
    constexpr std::uint32_t kReplicateMax = 1024U;
    const std::uint32_t probe_cases =
        argc == 3 ? std::min<std::uint32_t>(
                        static_cast<std::uint32_t>(std::stoul(argv[2])), 4096U)
                  : 1024U;

    xrt::device device{0};
    const xrt::xclbin xclbin{std::string{argv[1]}};
    const auto uuid = device.register_xclbin(xclbin);
    const xrt::hw_context context{device, uuid};
    xrt::kernel kernel{context, "dinucleotide_summaries"};

    const std::size_t summary_slots = static_cast<std::size_t>(probe_cases) *
                                      kMetricCount * kSummaryFields;

    // Step 1: correctness anchor on the frozen fixture summaries.
    {
      xrt::bo windows{device, fixture::kWindows.size() * sizeof(std::int32_t),
                      static_cast<xrt::memory_group>(kernel.group_id(0))};
      xrt::bo metadata{device, fixture::kMetadata.size() * sizeof(std::uint64_t),
                       static_cast<xrt::memory_group>(kernel.group_id(1))};
      xrt::bo summaries{device,
                        expected::kExpectedSummaries.size() * sizeof(std::int32_t),
                        static_cast<xrt::memory_group>(kernel.group_id(2))};
      auto* windows_map = windows.map<std::int32_t*>();
      auto* metadata_map = metadata.map<std::uint64_t*>();
      auto* summaries_map = summaries.map<std::int32_t*>();
      std::copy(fixture::kWindows.begin(), fixture::kWindows.end(), windows_map);
      std::copy(fixture::kMetadata.begin(), fixture::kMetadata.end(), metadata_map);
      std::fill(summaries_map, summaries_map + expected::kExpectedSummaries.size(), -2);
      windows.sync(XCL_BO_SYNC_BO_TO_DEVICE);
      metadata.sync(XCL_BO_SYNC_BO_TO_DEVICE);
      auto run = kernel(windows, metadata, summaries, fixture::kCaseCount,
                        fixture::kReplicates, expected::kMinEffective);
      run.wait();
      summaries.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
      for (std::size_t i = 0; i < expected::kExpectedSummaries.size(); ++i) {
        if (summaries_map[i] != expected::kExpectedSummaries[i]) {
          std::cerr << "U250_SUMMARIES_ANCHOR_MISMATCH field=" << i
                    << " expected=" << expected::kExpectedSummaries[i]
                    << " actual=" << summaries_map[i] << "\n";
          return 1;
        }
      }
      std::cout << "U250_SUMMARIES_ANCHOR cases=" << fixture::kCaseCount
                << " metrics=" << kMetricCount
                << " fields=" << expected::kExpectedSummaries.size()
                << " tolerance=0\n";
    }

    // Step 2: synthetic throughput batches (identical stream to the P1 probe).
    const std::size_t window_slots =
        static_cast<std::size_t>(probe_cases) * fixture::kCapacity;
    const std::size_t metadata_slots = static_cast<std::size_t>(probe_cases) * 3U;

    xrt::bo windows{device, window_slots * sizeof(std::int32_t),
                    static_cast<xrt::memory_group>(kernel.group_id(0))};
    xrt::bo metadata{device, metadata_slots * sizeof(std::uint64_t),
                     static_cast<xrt::memory_group>(kernel.group_id(1))};
    xrt::bo summaries{device, summary_slots * sizeof(std::int32_t),
                      static_cast<xrt::memory_group>(kernel.group_id(2))};
    auto* windows_map = windows.map<std::int32_t*>();
    auto* metadata_map = metadata.map<std::uint64_t*>();
    auto* summaries_map = summaries.map<std::int32_t*>();

    static const std::int32_t kBranching[fixture::kCapacity] = {
        0, 1, 0, 2, 3, 2, 1, 0, 3, 1, 0, 1, 2, 3, 2, 1};
    std::uint64_t rng = 0x64617277696e2d70ULL;  // "darwin-p" probe stream
    for (std::uint32_t item = 0; item < probe_cases; ++item) {
      const std::uint32_t family = item % 4U;
      for (std::uint32_t i = 0; i < fixture::kCapacity; ++i) {
        std::int32_t base = 0;
        if (family == 1U) {
          base = static_cast<std::int32_t>(i % 2U);
        } else if (family == 2U) {
          base = kBranching[i];
        } else if (family == 3U) {
          base = static_cast<std::int32_t>(splitmix64(rng) % 4U);
        }
        windows_map[static_cast<std::size_t>(item) * fixture::kCapacity + i] = base;
      }
      metadata_map[static_cast<std::size_t>(item) * 3U] = fixture::kCapacity;
      metadata_map[static_cast<std::size_t>(item) * 3U + 1U] = splitmix64(rng);
      metadata_map[static_cast<std::size_t>(item) * 3U + 2U] = splitmix64(rng);
    }
    std::fill(summaries_map, summaries_map + summary_slots, -2);
    windows.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    metadata.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    const std::uint32_t sweep[] = {8U, 64U, 256U, 1024U};
    for (const std::uint32_t replicates : sweep) {
      const auto t0 = std::chrono::steady_clock::now();
      auto run = kernel(windows, metadata, summaries, probe_cases, replicates,
                        expected::kMinEffective);
      run.wait();
      const auto t1 = std::chrono::steady_clock::now();
      const double wall_ms =
          std::chrono::duration<double, std::milli>(t1 - t0).count();
      const double draws =
          static_cast<double>(probe_cases) * static_cast<double>(replicates);
      std::cout << "U250_SUMMARIES_THROUGHPUT cases=" << probe_cases
                << " replicates=" << replicates
                << " wall_ms=" << static_cast<std::uint64_t>(wall_ms)
                << " cases_per_second="
                << static_cast<std::uint64_t>(
                       wall_ms > 0.0 ? probe_cases * 1000.0 / wall_ms : 0.0)
                << " draws_per_second="
                << static_cast<std::uint64_t>(
                       wall_ms > 0.0 ? draws * 1000.0 / wall_ms : 0.0)
                << "\n";

      if (replicates == 8U) {
        summaries.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
        std::uint64_t blocks_ok = 0;
        for (std::size_t block = 0; block < static_cast<std::size_t>(probe_cases) * kMetricCount;
             ++block) {
          const std::int32_t count = summaries_map[block * kSummaryFields];
          const std::int32_t mean = summaries_map[block * kSummaryFields + 1];
          const std::int32_t mad = summaries_map[block * kSummaryFields + 2];
          const std::int32_t q025 = summaries_map[block * kSummaryFields + 3];
          const std::int32_t q975 = summaries_map[block * kSummaryFields + 4];
          bool ok = false;
          if (count == 0) {
            ok = mean == -1 && mad == -1 && q025 == -1 && q975 == -1;
          } else if (count > 0 && count <= static_cast<std::int32_t>(replicates)) {
            ok = mean >= 0 && mean <= 1000000 && mad >= 0 && mad <= 1000000 &&
                 q025 >= 0 && q025 <= 1000000 && q975 >= 0 && q975 <= 1000000 &&
                 q025 <= q975;
          }
          if (!ok) {
            std::cerr << "U250_SUMMARIES_INTEGRITY_MISMATCH block=" << block
                      << " count=" << count << " mean=" << mean
                      << " mad=" << mad << " q025=" << q025 << " q975=" << q975
                      << "\n";
            return 1;
          }
          ++blocks_ok;
        }
        std::cout << "U250_SUMMARIES_INTEGRITY cases=" << probe_cases
                  << " replicates=8 blocks_ok=" << blocks_ok << "\n";
      }
    }

    std::cout << "U250_SUMMARIES_PASS anchor=ok cases=" << probe_cases
              << " max_replicates=" << kReplicateMax << "\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "U250_SUMMARIES_ERROR " << error.what() << "\n";
    return 1;
  }
}
