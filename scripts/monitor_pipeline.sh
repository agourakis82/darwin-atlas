#!/bin/bash
# Monitor pipeline execution progress

LOG_FILE="${1:-/tmp/atlas_500.log}"

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ Log file not found: $LOG_FILE"
    exit 1
fi

echo "📊 Pipeline Monitor"
echo "==================="
echo "Log: $LOG_FILE"
echo ""

# Current step
CURRENT_STEP=$(grep -E "\[Step [0-9]/4\]" "$LOG_FILE" | tail -1)
if [ -n "$CURRENT_STEP" ]; then
    echo "📍 Current: $CURRENT_STEP"
fi

echo ""

# Download progress
if grep -q "Downloading genomes from NCBI" "$LOG_FILE"; then
    echo "📥 Download Progress:"
    grep -E "Downloading:|Downloaded|Found.*assemblies" "$LOG_FILE" | tail -3
    echo ""
fi

# Processing steps
if grep -q "Generating output tables" "$LOG_FILE"; then
    echo "📊 Tables Generated:"
    grep -E "Wrote|Processing.*\.csv" "$LOG_FILE" | tail -5
    echo ""
fi

# Biology metrics
if grep -q "Computing biology metrics" "$LOG_FILE"; then
    echo "🧬 Biology Metrics:"
    grep -E "Computing|kmer|gc_skew|inverted_repeats" "$LOG_FILE" | tail -5
    echo ""
fi

# Epistemic export
if grep -q "Exporting epistemic Knowledge" "$LOG_FILE"; then
    echo "📚 Epistemic Export:"
    grep -E "Wrote.*records|Processing.*\.csv" "$LOG_FILE" | tail -5
    echo ""
fi

# Completion
if grep -q "ATLAS PIPELINE COMPLETE" "$LOG_FILE"; then
    echo "✅ PIPELINE COMPLETE!"
    echo ""
    grep -A 5 "ATLAS PIPELINE COMPLETE" "$LOG_FILE" | tail -6
fi

# Errors
ERRORS=$(grep -i "error\|failed\|Error" "$LOG_FILE" | wc -l)
if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "⚠️  Errors found: $ERRORS"
    grep -i "error\|failed\|Error" "$LOG_FILE" | tail -3
fi

echo ""
echo "📈 File sizes:"
if [ -d "dist/atlas_dataset_v2" ]; then
    du -sh dist/atlas_dataset_v2 2>/dev/null | awk '{print "  Dataset: " $1}'
fi
if [ -d "data/tables" ]; then
    ls -1 data/tables/*.csv 2>/dev/null | wc -l | awk '{print "  CSV tables: " $1}'
fi

