#include <cstdint>

namespace {
constexpr std::uint32_t kWindowCapacity = 16;
constexpr std::uint32_t kMetricCount = 18;
constexpr std::uint64_t kLcgMask = 0x7fffffffULL;

std::uint64_t lcg_step(std::uint64_t state) {
  return (state * 1103515245ULL + 12345ULL) & kLcgMask;
}

std::uint32_t transform_code(std::uint32_t code, std::uint32_t k, bool complement) {
  std::uint32_t result = 0;
  for (std::uint32_t i = 0; i < k; ++i) {
#pragma HLS UNROLL
    std::uint32_t digit = code & 3U;
    if (complement) {
      digit = 3U - digit;
    }
    result = (result << 2U) | digit;
    code >>= 2U;
  }
  return result;
}

std::int32_t positional_draw(const std::int32_t window[kWindowCapacity],
                             std::uint32_t length, bool complement) {
  std::uint32_t mismatches = 0;
  for (std::uint32_t i = 0; i < kWindowCapacity; ++i) {
#pragma HLS UNROLL
    if (i < length) {
      std::int32_t opposite = window[length - 1U - i];
      if (complement) {
        opposite = 3 - opposite;
      }
      if (window[i] != opposite) {
        ++mismatches;
      }
    }
  }
  return static_cast<std::int32_t>((static_cast<std::uint64_t>(mismatches) * 1000000ULL) / length);
}

std::int32_t kmer_draw(const std::int32_t window[kWindowCapacity],
                       std::uint32_t length, std::uint32_t k, bool complement,
                       std::uint32_t min_effective) {
  std::uint32_t codes[kWindowCapacity];
#pragma HLS ARRAY_PARTITION variable=codes complete
  std::uint32_t count = 0;

  for (std::uint32_t start = 0; start < kWindowCapacity; ++start) {
    if (start + k > length) {
      continue;
    }
    bool valid = true;
    std::uint32_t code = 0;
    for (std::uint32_t offset = 0; offset < 8; ++offset) {
#pragma HLS UNROLL
      if (offset < k) {
        const std::int32_t base = window[start + offset];
        if (base < 0 || base > 3) {
          valid = false;
        }
        code = (code << 2U) | (static_cast<std::uint32_t>(base) & 3U);
      }
    }
    if (valid) {
      codes[count++] = code;
    }
  }
  if (count < min_effective) {
    return -1;
  }

  std::uint32_t numerator = 0;
  std::uint32_t denominator = 0;
  for (std::uint32_t i = 0; i < kWindowCapacity; ++i) {
    if (i >= count) {
      continue;
    }
    const std::uint32_t code = codes[i];
    const std::uint32_t partner = transform_code(code, k, complement);
    const std::uint32_t orbit = code < partner ? code : partner;
    bool seen = false;
    for (std::uint32_t earlier = 0; earlier < kWindowCapacity; ++earlier) {
      if (earlier < i) {
        const std::uint32_t previous = codes[earlier];
        const std::uint32_t previous_partner = transform_code(previous, k, complement);
        const std::uint32_t previous_orbit = previous < previous_partner ? previous : previous_partner;
        if (previous_orbit == orbit) {
          seen = true;
        }
      }
    }
    if (seen) {
      continue;
    }

    const std::uint32_t orbit_partner = transform_code(orbit, k, complement);
    std::uint32_t left = 0;
    std::uint32_t right = 0;
    for (std::uint32_t j = 0; j < kWindowCapacity; ++j) {
      if (j < count) {
        if (codes[j] == orbit) {
          ++left;
        } else if (orbit_partner != orbit && codes[j] == orbit_partner) {
          ++right;
        }
      }
    }
    if (orbit_partner == orbit) {
      denominator += left;
    } else {
      numerator += left >= right ? left - right : right - left;
      denominator += left + right;
    }
  }
  if (denominator == 0) {
    return -1;
  }
  return static_cast<std::int32_t>((static_cast<std::uint64_t>(numerator) * 1000000ULL) / denominator);
}

bool observed_available(const std::int32_t window[kWindowCapacity],
                        std::uint32_t length, std::uint32_t configured_length,
                        std::uint32_t metric, std::uint32_t min_effective) {
  if (metric < 2) {
    if (length != configured_length) {
      return false;
    }
    for (std::uint32_t i = 0; i < kWindowCapacity; ++i) {
      if (i < length && (window[i] < 0 || window[i] > 3)) {
        return false;
      }
    }
    return true;
  }
  const std::uint32_t k = metric / 2U;
  return kmer_draw(window, length, k, (metric & 1U) != 0U, min_effective) >= 0;
}
}  // namespace

extern "C" void null_draws(const std::int32_t* windows,
                           const std::uint64_t* metadata,
                           std::int32_t* outputs,
                           std::uint32_t window_count,
                           std::uint32_t replicates) {
#pragma HLS INTERFACE m_axi port=windows offset=slave bundle=gmem0
#pragma HLS INTERFACE m_axi port=metadata offset=slave bundle=gmem1
#pragma HLS INTERFACE m_axi port=outputs offset=slave bundle=gmem2
#pragma HLS INTERFACE s_axilite port=windows bundle=control
#pragma HLS INTERFACE s_axilite port=metadata bundle=control
#pragma HLS INTERFACE s_axilite port=outputs bundle=control
#pragma HLS INTERFACE s_axilite port=window_count bundle=control
#pragma HLS INTERFACE s_axilite port=replicates bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

  for (std::uint32_t item = 0; item < window_count; ++item) {
    std::int32_t original[kWindowCapacity];
#pragma HLS ARRAY_PARTITION variable=original complete
    for (std::uint32_t i = 0; i < kWindowCapacity; ++i) {
#pragma HLS UNROLL
      original[i] = windows[item * kWindowCapacity + i];
    }
    const std::uint32_t length = static_cast<std::uint32_t>(metadata[item * 6U]);
    const std::uint32_t configured_length = static_cast<std::uint32_t>(metadata[item * 6U + 1U]);
    const std::uint64_t seed_base = metadata[item * 6U + 2U];
    const std::uint64_t window_start = metadata[item * 6U + 3U];
    const std::uint64_t record_index = metadata[item * 6U + 4U];
    const std::uint32_t min_effective = static_cast<std::uint32_t>(metadata[item * 6U + 5U]);

    for (std::uint32_t metric = 0; metric < kMetricCount; ++metric) {
      const bool available = observed_available(original, length, configured_length, metric, min_effective);
      for (std::uint32_t replicate = 1; replicate <= replicates; ++replicate) {
        const std::uint32_t output_index = (item * kMetricCount + metric) * replicates + replicate - 1U;
        if (!available) {
          outputs[output_index] = -1;
          continue;
        }
        std::uint64_t state = (seed_base + window_start * 1000003ULL +
                               record_index * 1000033ULL + metric * 100043ULL +
                               replicate * 1009ULL) & kLcgMask;
        std::int32_t shuffled[kWindowCapacity];
#pragma HLS ARRAY_PARTITION variable=shuffled complete
        for (std::uint32_t i = 0; i < kWindowCapacity; ++i) {
#pragma HLS UNROLL
          shuffled[i] = original[i];
        }
        for (std::uint32_t i = kWindowCapacity - 1U; i > 0; --i) {
          if (i < length) {
            state = lcg_step(state);
            const std::uint32_t j = static_cast<std::uint32_t>(state % (i + 1U));
            const std::int32_t tmp = shuffled[i];
            shuffled[i] = shuffled[j];
            shuffled[j] = tmp;
          }
        }
        if (metric < 2) {
          outputs[output_index] = positional_draw(shuffled, length, metric == 1U);
        } else {
          const std::uint32_t k = metric / 2U;
          outputs[output_index] = kmer_draw(shuffled, length, k, (metric & 1U) != 0U, min_effective);
        }
      }
    }
  }
}
