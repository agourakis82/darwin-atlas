#include <algorithm>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_hw_context.h>
#include <xrt/xrt_kernel.h>
#include <xrt/experimental/xrt_xclbin.h>

#include "../generated_fixture.hpp"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: " << argv[0] << " <dinucleotide_draws.xclbin>\n";
    return 2;
  }
  try {
    using namespace u250_dinucleotide_fixture;
    xrt::device device{0};
    const xrt::xclbin xclbin{std::string{argv[1]}};
    const auto uuid = device.register_xclbin(xclbin);
    const xrt::hw_context context{device, uuid};
    xrt::kernel kernel{context, "dinucleotide_draws"};

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
        const std::uint32_t base_slot = static_cast<std::uint32_t>(i % kCapacity);
        const std::size_t draw = i / kCapacity;
        const std::uint32_t replicate = static_cast<std::uint32_t>(draw % kReplicates) + 1U;
        const std::uint32_t item = static_cast<std::uint32_t>(draw / kReplicates);
        std::cerr << "U250_DINUCLEOTIDE_MISMATCH case=" << item
                  << " replicate=" << replicate << " base_slot=" << base_slot
                  << " expected=" << kExpected[i] << " actual=" << outputs_map[i] << "\n";
        return 1;
      }
    }
    std::cout << "U250_DINUCLEOTIDE_DRAW_PASS cases=" << kCaseCount
              << " replicates=" << kReplicates << " slots=" << kExpected.size()
              << " tolerance=0\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "U250_DINUCLEOTIDE_ERROR " << error.what() << "\n";
    return 1;
  }
}
