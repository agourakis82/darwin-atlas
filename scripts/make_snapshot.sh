#!/usr/bin/env bash
# make_snapshot.sh — Build deterministic dataset snapshot for Zenodo/DOI
#
# Usage: ./scripts/make_snapshot.sh [MAX] [SEED]
# Example: ./scripts/make_snapshot.sh 50 42
#
# Produces: dist/atlas_snapshot_v1/

set -euo pipefail

MAX="${1:-50}"
SEED="${2:-42}"
VERSION="0.1.0-epistemic"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_SHA=$(git rev-parse HEAD)
SNAPSHOT_DIR="dist/atlas_snapshot_v1"

echo "=== DSLG Atlas Snapshot Builder ==="
echo "MAX=$MAX, SEED=$SEED, VERSION=$VERSION"
echo "GIT_SHA=$GIT_SHA"
echo ""

# Check required source files exist
required_files=(
    "data/manifest/manifest.jsonl"
    "data/manifest/checksums.sha256"
    "data/tables/atlas_replicons.csv"
    "data/tables/dicyclic_lifts.csv"
    "data/tables/quaternion_results.csv"
    "data/epistemic/schema_atlas_knowledge.json"
    "data/epistemic/atlas_knowledge_report.md"
    "data/epistemic/atlas_knowledge.jsonl"
)

echo "Checking required source files..."
missing=()
for f in "${required_files[@]}"; do
    if [ ! -f "$f" ]; then
        missing+=("$f")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: Missing required files:"
    for f in "${missing[@]}"; do
        echo "  - $f"
    done
    echo ""
    echo "Run 'make pipeline MAX=$MAX SEED=$SEED' first, then 'make epistemic MAX=$MAX SEED=$SEED'"
    exit 1
fi
echo "All required files present."
echo ""

# Clean and create snapshot directory
echo "Creating snapshot directory: $SNAPSHOT_DIR"
rm -rf "$SNAPSHOT_DIR"
mkdir -p "$SNAPSHOT_DIR/manifest"
mkdir -p "$SNAPSHOT_DIR/tables"
mkdir -p "$SNAPSHOT_DIR/epistemic"
mkdir -p "$SNAPSHOT_DIR/figures"

# Copy manifest files
echo "Copying manifest files..."
cp data/manifest/manifest.jsonl "$SNAPSHOT_DIR/manifest/"
cp data/manifest/checksums.sha256 "$SNAPSHOT_DIR/manifest/"

# Create pipeline_metadata.json
echo "Creating pipeline_metadata.json..."
cat > "$SNAPSHOT_DIR/manifest/pipeline_metadata.json" << EOF
{
  "version": "$VERSION",
  "timestamp_utc": "$TIMESTAMP",
  "git_sha": "$GIT_SHA",
  "parameters": {
    "max_genomes": $MAX,
    "seed": $SEED
  },
  "julia_version": "$(julia --version 2>/dev/null | head -1 || echo 'unknown')",
  "platform": "$(uname -s)-$(uname -m)",
  "source": {
    "ncbi_refseq": "complete bacterial genomes",
    "assembly_level": "complete genome"
  }
}
EOF

# Copy table files
echo "Copying table files..."
for f in data/tables/*.csv; do
    if [ -f "$f" ]; then
        cp "$f" "$SNAPSHOT_DIR/tables/"
    fi
done

# Copy epistemic files
echo "Copying epistemic files..."
cp data/epistemic/schema_atlas_knowledge.json "$SNAPSHOT_DIR/epistemic/"
cp data/epistemic/atlas_knowledge_report.md "$SNAPSHOT_DIR/epistemic/"

# Create sample JSONL (first 50 lines)
echo "Creating atlas_knowledge_sample_50.jsonl..."
head -50 data/epistemic/atlas_knowledge.jsonl > "$SNAPSHOT_DIR/epistemic/atlas_knowledge_sample_50.jsonl"

# Copy figures if they exist
if [ -d "results/figures" ]; then
    echo "Copying figures..."
    cp -r results/figures/* "$SNAPSHOT_DIR/figures/" 2>/dev/null || true
fi

# Generate README from template
echo "Generating README_DATASET.md..."
if [ -f "dist_templates/README_DATASET.md" ]; then
    sed -e "s/{{VERSION}}/$VERSION/g" \
        -e "s/{{TIMESTAMP}}/$TIMESTAMP/g" \
        -e "s/{{GIT_SHA}}/$GIT_SHA/g" \
        -e "s/{{MAX}}/$MAX/g" \
        -e "s/{{SEED}}/$SEED/g" \
        dist_templates/README_DATASET.md > "$SNAPSHOT_DIR/README_DATASET.md"
else
    echo "WARNING: dist_templates/README_DATASET.md not found, skipping README generation"
fi

# Generate checksums for snapshot contents
echo "Generating snapshot checksums..."
(cd "$SNAPSHOT_DIR" && find . -type f -name "*.csv" -o -name "*.json" -o -name "*.jsonl" -o -name "*.md" | sort | xargs sha256sum > CHECKSUMS.sha256)

# Summary
echo ""
echo "=== Snapshot Complete ==="
echo "Location: $SNAPSHOT_DIR"
echo ""
echo "Contents:"
find "$SNAPSHOT_DIR" -type f | sort | while read f; do
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "?")
    echo "  $(echo $f | sed "s|$SNAPSHOT_DIR/||") ($size bytes)"
done
echo ""
echo "To archive for Zenodo:"
echo "  cd dist && zip -r atlas_snapshot_v1.zip atlas_snapshot_v1/"
