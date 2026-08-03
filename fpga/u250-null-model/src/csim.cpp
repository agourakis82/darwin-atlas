#include <algorithm>
#include <cstdint>
#include <iostream>
#include <vector>

#include "../generated_fixture.hpp"

extern "C" void null_draws(const std::int32_t* windows,
                           const std::uint64_t* metadata,
                           std::int32_t* outputs,
                           std::uint32_t window_count,
                           std::uint32_t replicates);

int main() {
  using namespace u250_null_fixture;
  std::vector<std::int32_t> outputs(kExpected.size(), -2147483647);
  null_draws(kWindows.data(), kMetadata.data(), outputs.data(), kCaseCount, kReplicates);
  for (std::size_t i = 0; i < kExpected.size(); ++i) {
    if (outputs[i] != kExpected[i]) {
      const std::uint32_t replicate = static_cast<std::uint32_t>(i % kReplicates) + 1U;
      const std::size_t metric_slot = i / kReplicates;
      const std::uint32_t metric = static_cast<std::uint32_t>(metric_slot % kMetricCount);
      const std::uint32_t item = static_cast<std::uint32_t>(metric_slot / kMetricCount);
      std::cerr << "U250_NULL_CSIM_MISMATCH case=" << item << " metric=" << metric
                << " replicate=" << replicate << " expected=" << kExpected[i]
                << " actual=" << outputs[i] << "\n";
      return 1;
    }
  }
  std::cout << "U250_NULL_CSIM_PASS cases=" << kCaseCount
            << " metrics=" << kMetricCount
            << " replicates=" << kReplicates
            << " draws=" << kExpected.size() << "\n";
  return 0;
}
