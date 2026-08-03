#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_hw_context.h>
#include <xrt/xrt_kernel.h>
#include <xrt/experimental/xrt_xclbin.h>

namespace {
constexpr std::uint32_t kElementCount = 4096;
}

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: " << argv[0] << " <vector_add.xclbin>\n";
    return 2;
  }

  try {
    xrt::device device{0};
    const xrt::xclbin xclbin{std::string{argv[1]}};
    const auto uuid = device.register_xclbin(xclbin);
    const xrt::hw_context context{device, uuid};
    xrt::kernel kernel{context, "vector_add"};
    const std::size_t bytes = kElementCount * sizeof(std::int32_t);

    xrt::bo a{device, bytes, static_cast<xrt::memory_group>(kernel.group_id(0))};
    xrt::bo b{device, bytes, static_cast<xrt::memory_group>(kernel.group_id(1))};
    xrt::bo out{device, bytes, static_cast<xrt::memory_group>(kernel.group_id(2))};

    auto* a_map = a.map<std::int32_t*>();
    auto* b_map = b.map<std::int32_t*>();
    auto* out_map = out.map<std::int32_t*>();

    for (std::uint32_t i = 0; i < kElementCount; ++i) {
      a_map[i] = static_cast<std::int32_t>(i);
      b_map[i] = static_cast<std::int32_t>(3 * i + 7);
      out_map[i] = 0;
    }

    a.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    b.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    auto run = kernel(a, b, out, kElementCount);
    run.wait();
    out.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

    for (std::uint32_t i = 0; i < kElementCount; ++i) {
      const std::int32_t expected = a_map[i] + b_map[i];
      if (out_map[i] != expected) {
        std::cerr << "mismatch index=" << i << " expected=" << expected
                  << " actual=" << out_map[i] << "\n";
        return 1;
      }
    }

    std::cout << "U250_VECTOR_ADD_PASS elements=" << kElementCount << "\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "U250_VECTOR_ADD_ERROR " << error.what() << "\n";
    return 1;
  }
}
