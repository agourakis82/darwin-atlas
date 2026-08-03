#include <algorithm>
#include <cstdint>
#include <iostream>
#include <vector>

#include "../generated_fixture.hpp"

extern "C" void dinucleotide_draws(const std::int32_t*, const std::uint64_t*,
                                    std::int32_t*, std::uint32_t, std::uint32_t);

int main() {
  using namespace u250_dinucleotide_fixture;
  std::vector<std::int32_t> actual(kExpected.size(), -2);
  dinucleotide_draws(kWindows.data(), kMetadata.data(), actual.data(), kCaseCount, kReplicates);
  if (!std::equal(actual.begin(), actual.end(), kExpected.begin())) {
    for (std::size_t i = 0; i < actual.size(); ++i) {
      if (actual[i] != kExpected[i]) {
        std::cerr << "U250_DINUCLEOTIDE_CSIM_MISMATCH slot=" << i
                  << " expected=" << kExpected[i] << " actual=" << actual[i] << "\n";
        return 1;
      }
    }
  }
  std::cout << "U250_DINUCLEOTIDE_CSIM_PASS cases=" << kCaseCount
            << " replicates=" << kReplicates << " slots=" << kExpected.size()
            << " tolerance=0\n";
  return 0;
}
