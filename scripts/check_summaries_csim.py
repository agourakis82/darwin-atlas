#!/usr/bin/env python3
"""Diff the P2 csim summary block against the independent reference JSON."""
import json
import re
import sys

csim_text = open(sys.argv[1]).read()
reference = json.load(open(sys.argv[2]))

rows = {}
for match in re.finditer(
        r"P2_CSIM_SUMMARY case=(\d+) metric=(\d+) count=(-?\d+) mean=(-?\d+) mad=(-?\d+) q025=(-?\d+) q975=(-?\d+)",
        csim_text):
    case, metric = int(match.group(1)), int(match.group(2))
    rows[(case, metric)] = [int(match.group(i)) for i in range(3, 8)]

mismatches = 0
checked = 0
for case_index, case in enumerate(reference["cases"]):
    for metric_index, expected in enumerate(case["summaries"]):
        got = rows.get((case_index, metric_index))
        checked += 1
        if got != expected:
            mismatches += 1
            print("MISMATCH case=%d metric=%d expected=%s got=%s"
                  % (case_index, metric_index, expected, got))

print("P2_CSIM_DIFF checked=%d mismatches=%d %s"
      % (checked, mismatches, "PASS" if mismatches == 0 else "FAIL"))
sys.exit(1 if mismatches else 0)
