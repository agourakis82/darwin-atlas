#!/usr/bin/env python3
"""Fase P2 reference: exact 18-metric null summaries for the frozen Fase L
dinucleotide fixture (fpga/u250-dinucleotide-null/generated_fixture.hpp).

Parses the frozen 8x8 fixture, recomputes the spec 0.1.0 section 7 metric
projection over every frozen draw (independent reimplementation of
window_pipeline_core.jl semantics), and emits the five exact integer summary
fields per (case, metric): count, mean, mad, q025, q975. Output JSON feeds the
csim anchor of the P2 kernel (dinucleotide_summaries).
"""
import json
import re
import sys

FIXTURE = "fpga/u250-dinucleotide-null/generated_fixture.hpp"
CAPACITY = 16
METRICS = 18
UNAVAILABLE = -1


def parse_array(text, name):
    match = re.search(name + r"\s*=\s*\{\{(.*?)\}\}", text, re.S)
    body = match.group(1)
    return [int(x) for x in re.findall(r"-?\d+", body)]


def positional_scaled(seq, length, metric_index):
    mismatches = 0
    for i in range(length):
        opposite = seq[length - 1 - i]
        expected = opposite if metric_index == 0 else 3 - opposite
        if seq[i] != expected:
            mismatches += 1
    return (mismatches * 1_000_000) // length


def encode(seq, start, k):
    value = 0
    for i in range(k):
        value = (value << 2) | seq[start + i]
    return value


def kreverse(value, k):
    result = 0
    for _ in range(k):
        result = (result << 2) | (value & 3)
        value >>= 2
    return result


def krc(value, k):
    result = 0
    for _ in range(k):
        result = (result << 2) | (3 - (value & 3))
        value >>= 2
    return result


def kmer_imbalance_scaled(seq, length, metric_index, min_effective):
    k = metric_index // 2
    use_rc = (metric_index & 1) != 0
    if length < k:
        return UNAVAILABLE
    effective = length - k + 1
    if effective < min_effective:
        return UNAVAILABLE
    counts = {}
    for start in range(effective):
        u = encode(seq, start, k)
        counts[u] = counts.get(u, 0) + 1
    numerator = 0
    denominator = 0
    for u, c in counts.items():
        v = krc(u, k) if use_rc else kreverse(u, k)
        if u == v:
            denominator += c
        elif u < v:
            right = counts.get(v, 0)
            numerator += abs(c - right)
            denominator += c + right
    if denominator == 0:
        return UNAVAILABLE
    return (numerator * 1_000_000) // denominator


def metric_scaled(seq, length, metric_index, min_effective):
    if metric_index < 2:
        return positional_scaled(seq, length, metric_index)
    return kmer_imbalance_scaled(seq, length, metric_index, min_effective)


def summarize(values):
    n = len(values)
    if n == 0:
        return [0, UNAVAILABLE, UNAVAILABLE, UNAVAILABLE, UNAVAILABLE]
    total = sum(values)
    mean = total // n
    mad = sum(abs(n * x - total) for x in values) // (n * n)
    ordered = sorted(values)
    q025 = ordered[(25 * (n - 1)) // 100]
    q975 = ordered[(975 * (n - 1)) // 1000]
    return [n, mean, mad, q025, q975]


def main():
    min_effective = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    out_path = sys.argv[2] if len(sys.argv) > 2 else "null_summaries_expected.json"
    text = open(FIXTURE).read()
    windows = parse_array(text, "kWindows")
    metadata = parse_array(text, "kMetadata")
    expected = parse_array(text, "kExpected")
    case_count = 8
    replicates = 8

    cases = []
    for case in range(case_count):
        length = metadata[case * 3]
        summaries = []
        for metric in range(METRICS):
            values = []
            for rep in range(replicates):
                base = (case * replicates + rep) * CAPACITY
                draw = expected[base:base + length]
                scaled = metric_scaled(draw, length, metric, min_effective)
                if scaled >= 0:
                    values.append(scaled)
            summaries.append(summarize(values))
        cases.append({"length": length, "summaries": summaries})

    payload = {"min_effective": min_effective, "cases": cases}
    with open(out_path, "w") as fh:
        json.dump(payload, fh)
    flat = [field for case in cases for summary in case["summaries"] for field in summary]
    print("NULL_SUMMARIES_REFERENCE_PASS cases=%d replicates=%d metrics=%d min_effective=%d fields=%d -> %s"
          % (case_count, replicates, METRICS, min_effective, len(flat), out_path))


if __name__ == "__main__":
    main()
