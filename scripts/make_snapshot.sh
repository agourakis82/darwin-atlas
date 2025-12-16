#!/usr/bin/env bash
# make_snapshot.sh — Build deterministic dataset snapshot for Zenodo/DOI
#
# Usage: ./scripts/make_snapshot.sh [MAX] [SEED]
# Example: ./scripts/make_snapshot.sh 50 42
#
# Produces: dist/atlas_snapshot_v2/

set -euo pipefail

MAX="${1:-50}"
SEED="${2:-42}"
VERSION="2.0.0"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_SHA=$(git rev-parse HEAD)
SNAPSHOT_DIR="dist/atlas_snapshot_v2"

echo "=== DSLG Atlas Snapshot Builder v2 ==="
echo "MAX=$MAX, SEED=$SEED, VERSION=$VERSION"
echo "GIT_SHA=$GIT_SHA"
echo ""

# Check for v2 dataset first, fall back to v1 format
V2_DATASET="dist/atlas_dataset_v2"
V1_DATA="data"

if [ -d "$V2_DATASET" ]; then
    echo "Using v2 dataset format (Parquet + CSV)"
    USE_V2=true
else
    echo "v2 dataset not found, checking v1 format..."
    USE_V2=false
fi

# Check required source files exist
if [ "$USE_V2" = true ]; then
    required_files=(
        "$V2_DATASET/csv/atlas_replicons.csv"
        "$V2_DATASET/manifest/dataset_manifest.json"
    )
else
    required_files=(
        "$V1_DATA/manifest/manifest.jsonl"
        "$V1_DATA/manifest/checksums.sha256"
        "$V1_DATA/tables/atlas_replicons.csv"
    )
fi

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
    echo "Run 'make atlas MAX=$MAX SEED=$SEED' first"
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
mkdir -p "$SNAPSHOT_DIR/partitions"

# Copy files based on format
if [ "$USE_V2" = true ]; then
    echo "Copying v2 dataset files..."

    # Copy manifest
    cp "$V2_DATASET/manifest/"* "$SNAPSHOT_DIR/manifest/" 2>/dev/null || true

    # Copy CSV views
    if [ -d "$V2_DATASET/csv" ]; then
        cp "$V2_DATASET/csv/"*.csv "$SNAPSHOT_DIR/tables/" 2>/dev/null || true
    fi

    # Copy Parquet partitions
    if [ -d "$V2_DATASET/partitions" ]; then
        cp -r "$V2_DATASET/partitions/"* "$SNAPSHOT_DIR/partitions/" 2>/dev/null || true
    fi
else
    echo "Copying v1 format files..."

    # Copy manifest files
    cp "$V1_DATA/manifest/manifest.jsonl" "$SNAPSHOT_DIR/manifest/" 2>/dev/null || true
    cp "$V1_DATA/manifest/checksums.sha256" "$SNAPSHOT_DIR/manifest/" 2>/dev/null || true

    # Copy table files
    for f in "$V1_DATA/tables/"*.csv; do
        if [ -f "$f" ]; then
            cp "$f" "$SNAPSHOT_DIR/tables/"
        fi
    done
fi

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
  },
  "format": "$([ "$USE_V2" = true ] && echo 'v2-parquet' || echo 'v1-csv')"
}
EOF

# Copy epistemic files if they exist
echo "Copying epistemic files..."
epistemic_source=""
if [ -d "$V2_DATASET/epistemic" ]; then
    epistemic_source="$V2_DATASET/epistemic"
elif [ -d "$V1_DATA/epistemic" ]; then
    epistemic_source="$V1_DATA/epistemic"
fi

if [ -n "$epistemic_source" ]; then
    # Copy schema
    if [ -f "$epistemic_source/schema_atlas_knowledge.json" ]; then
        cp "$epistemic_source/schema_atlas_knowledge.json" "$SNAPSHOT_DIR/epistemic/"
    fi

    # Copy report
    if [ -f "$epistemic_source/atlas_knowledge_report.md" ]; then
        cp "$epistemic_source/atlas_knowledge_report.md" "$SNAPSHOT_DIR/epistemic/"
    fi

    # Create sample JSONL (first 50 lines)
    if [ -f "$epistemic_source/atlas_knowledge.jsonl" ]; then
        head -50 "$epistemic_source/atlas_knowledge.jsonl" > "$SNAPSHOT_DIR/epistemic/atlas_knowledge_sample_50.jsonl"
    fi
fi

# Generate README from template or create minimal one
echo "Generating README_DATASET.md..."
if [ -f "dist_templates/README_DATASET.md" ]; then
    sed -e "s/{{VERSION}}/$VERSION/g" \
        -e "s/{{TIMESTAMP}}/$TIMESTAMP/g" \
        -e "s/{{GIT_SHA}}/$GIT_SHA/g" \
        -e "s/{{MAX}}/$MAX/g" \
        -e "s/{{SEED}}/$SEED/g" \
        dist_templates/README_DATASET.md > "$SNAPSHOT_DIR/README_DATASET.md"
else
    cat > "$SNAPSHOT_DIR/README_DATASET.md" << EOF
# DSLG Atlas Dataset Snapshot

**Version**: $VERSION
**Generated**: $TIMESTAMP
**Git SHA**: $GIT_SHA
**Pipeline Parameters**: MAX=$MAX, SEED=$SEED

## Contents

- \`manifest/\` - Download manifest and checksums
- \`tables/\` - CSV data tables
- \`partitions/\` - Parquet partitioned data (v2 format)
- \`epistemic/\` - Knowledge layer with validation

## Reproduction

\`\`\`bash
git clone https://github.com/agourakis82/darwin-atlas.git
cd darwin-atlas
git checkout $GIT_SHA
make atlas MAX=$MAX SEED=$SEED
make snapshot MAX=$MAX SEED=$SEED
\`\`\`
EOF
fi

# Generate checksums for snapshot contents
echo "Generating snapshot checksums..."
(cd "$SNAPSHOT_DIR" && find . -type f \( -name "*.csv" -o -name "*.json" -o -name "*.jsonl" -o -name "*.md" -o -name "*.parquet" \) | sort | xargs sha256sum > CHECKSUMS.sha256 2>/dev/null || true)

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
echo "  cd dist && zip -r atlas_snapshot_v2.zip atlas_snapshot_v2/"
