// Fase P1 throughput probe for the proven U250 dinucleotide-null kernel.
//
// Reuses the exact Fase L xclbin (no rebuild): the kernel interface takes
// runtime case_count and replicates, so this host binary measures draws/s
// with large batches while anchoring correctness on the frozen 8-case
// fixture (generated_fixture.hpp, tolerance 0). Synthetic windows cycle
// through four graph families (homopolymer, strictly alternating,
// branching, splitmix64 pseudo-random); synthetic seeds are host-drawn
// splitmix64 values because this probe measures throughput only — the
// semantic seed derivation remains gated by the Fase L fixture anchor.
//
// Markers:
//   U250_DINUCLEOTIDE_THROUGHPUT_ANCHOR cases=8 replicates=8 slots=1024 tolerance=0
//   U250_DINUCLEOTIDE_THROUGHPUT cases=N replicates=R draws=D wall_ms=W draws_per_second=Q
//   U250_DINUCLEOTIDE_THROUGHPUT_INTEGRITY cases=N replicates=8 slots_ok=S
//   U250_DINUCLEOTIDE_THROUGHPUT_PASS anchor=ok max_replicates=1024
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
              << " <dinucleotide_draws.xclbin> [probe_cases]\n";
    return 2;
  }
  try {
    using namespace u250_dinucleotide_fixture;
    const std::uint32_t probe_cases =
        argc == 3 ? std::min<std::uint32_t>(
                        static_cast<std::uint32_t>(std::stoul(argv[2])), 4096U)
                  : 1024U;
    constexpr std::uint32_t kReplicateMax = 1024U;

    xrt::device device{0};
    const xrt::xclbin xclbin{std::string{argv[1]}};
    const auto uuid = device.register_xclbin(xclbin);
    const xrt::hw_context context{device, uuid};
    xrt::kernel kernel{context, "dinucleotide_draws"};

    // Step 1: correctness anchor on the frozen Fase L fixture.
    {
      xrt::bo windows{device, kWindows.size() * sizeof(std::int32_t),
                      static_cast<xrt::memory_group>(kernel.group_id(0))};
      xrt::bo metadata{device, kMetadata.size() * sizeof(std::uint64_t),
                       static_cast<xrt::memory_group>(kernel.group_id(1))};
      xrt::bo outputs{device, kExpected.size() * sizeof(std::int32_t),
                      static_cast<xrt::memory_group>(kernel.group_id(2))};
      auto* windows_map = windows.map<std::int32_t*>();
      auto* metadata_map = metadata.map<std::uint64_t*>();
      auto* outputs_map = outputs.map<std::int32_t*>();
      std::copy(kWindows.begin(), kWindows.end(), windows_map);
      std::copy(kMetadata.begin(), kMetadata.end(), metadata_map);
      std::fill(outputs_map, outputs_map + kExpected.size(), -2);
      windows.sync(XCL_BO_SYNC_BO_TO_DEVICE);
      metadata.sync(XCL_BO_SYNC_BO_TO_DEVICE);
      auto run = kernel(windows, metadata, outputs, kCaseCount, kReplicates);
      run.wait();
      outputs.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
      for (std::size_t i = 0; i < kExpected.size(); ++i) {
        if (outputs_map[i] != kExpected[i]) {
          std::cerr << "U250_DINUCLEOTIDE_THROUGHPUT_ANCHOR_MISMATCH slot=" << i
                    << " expected=" << kExpected[i]
                    << " actual=" << outputs_map[i] << "\n";
          return 1;
        }
      }
      std::cout << "U250_DINUCLEOTIDE_THROUGHPUT_ANCHOR cases=" << kCaseCount
                << " replicates=" << kReplicates << " slots=" << kExpected.size()
                << " tolerance=0\n";
    }

    // Step 2: synthetic throughput batches.
    const std::size_t window_slots =
        static_cast<std::size_t>(probe_cases) * kCapacity;
    const std::size_t metadata_slots = static_cast<std::size_t>(probe_cases) * 3U;
    const std::size_t output_slots =
        static_cast<std::size_t>(probe_cases) * kReplicateMax * kCapacity;

    xrt::bo windows{device, window_slots * sizeof(std::int32_t),
                    static_cast<xrt::memory_group>(kernel.group_id(0))};
    xrt::bo metadata{device, metadata_slots * sizeof(std::uint64_t),
                     static_cast<xrt::memory_group>(kernel.group_id(1))};
    xrt::bo outputs{device, output_slots * sizeof(std::int32_t),
                    static_cast<xrt::memory_group>(kernel.group_id(2))};
    auto* windows_map = windows.map<std::int32_t*>();
    auto* metadata_map = metadata.map<std::uint64_t*>();
    auto* outputs_map = outputs.map<std::int32_t*>();

    static const std::int32_t kBranching[kCapacity] = {0, 1, 0, 2, 3, 2, 1, 0,
                                                       3, 1, 0, 1, 2, 3, 2, 1};
    std::uint64_t rng = 0x64617277696e2d70ULL;  // "darwin-p" probe stream
    for (std::uint32_t item = 0; item < probe_cases; ++item) {
      const std::uint32_t family = item % 4U;
      for (std::uint32_t i = 0; i < kCapacity; ++i) {
        std::int32_t base = 0;
        if (family == 1U) {
          base = static_cast<std::int32_t>(i % 2U);  // ACAC...
        } else if (family == 2U) {
          base = kBranching[i];
        } else if (family == 3U) {
          base = static_cast<std::int32_t>(splitmix64(rng) % 4U);
        }
        windows_map[static_cast<std::size_t>(item) * kCapacity + i] = base;
      }
      metadata_map[static_cast<std::size_t>(item) * 3U] = kCapacity;
      metadata_map[static_cast<std::size_t>(item) * 3U + 1U] = splitmix64(rng);
      metadata_map[static_cast<std::size_t>(item) * 3U + 2U] = splitmix64(rng);
    }
    std::fill(outputs_map, outputs_map + output_slots, -2);
    windows.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    metadata.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    const std::uint32_t sweep[] = {8U, 64U, 256U, 1024U};
    for (const std::uint32_t replicates : sweep) {
      const std::size_t used =
          static_cast<std::size_t>(probe_cases) * replicates * kCapacity;
      outputs.sync(XCL_BO_SYNC_BO_TO_DEVICE);  // sentinel region is authoritative
      const auto t0 = std::chrono::steady_clock::now();
      auto run = kernel(windows, metadata, outputs, probe_cases, replicates);
      run.wait();
      const auto t1 = std::chrono::steady_clock::now();
      const double wall_ms =
          std::chrono::duration<double, std::milli>(t1 - t0).count();
      const double draws =
          static_cast<double>(probe_cases) * static_cast<double>(replicates);
      const double rate =
          wall_ms > 0.0 ? draws * 1000.0 / wall_ms : 0.0;
      std::cout << "U250_DINUCLEOTIDE_THROUGHPUT cases=" << probe_cases
                << " replicates=" << replicates
                << " draws=" << static_cast<std::uint64_t>(draws)
                << " wall_ms=" << static_cast<std::uint64_t>(wall_ms)
                << " draws_per_second="
                << static_cast<std::uint64_t>(rate) << "\n";

      if (replicates == 8U) {
        // Integrity sweep on the smallest batch: full sync-back, every slot
        // must be written, in base range, and endpoints must be preserved.
        outputs.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
        std::uint64_t slots_ok = 0;
        for (std::size_t i = 0; i < used; ++i) {
          const std::int32_t value = outputs_map[i];
          if (value < -1 || value > 3) {
            std::cerr << "U250_DINUCLEOTIDE_THROUGHPUT_INTEGRITY_MISMATCH slot="
                      << i << " value=" << value << "\n";
            return 1;
          }
          const std::size_t draw = i / kCapacity;
          const std::size_t slot = i % kCapacity;
          const std::size_t item = draw / replicates;
          const std::int32_t first = windows_map[item * kCapacity];
          const std::int32_t last =
              windows_map[item * kCapacity + kCapacity - 1U];
          if ((slot == 0 && value != first) ||
              (slot == kCapacity - 1U && value != last)) {
            std::cerr << "U250_DINUCLEOTIDE_THROUGHPUT_ENDPOINT_MISMATCH draw="
                      << draw << " slot=" << slot << "\n";
            return 1;
          }
          ++slots_ok;
        }
        std::cout << "U250_DINUCLEOTIDE_THROUGHPUT_INTEGRITY cases="
                  << probe_cases << " replicates=8 slots_ok=" << slots_ok
                  << "\n";
      }
    }

    std::cout << "U250_DINUCLEOTIDE_THROUGHPUT_PASS anchor=ok cases="
              << probe_cases << " max_replicates=" << kReplicateMax << "\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "U250_DINUCLEOTIDE_THROUGHPUT_ERROR " << error.what() << "\n";
    return 1;
  }
}
