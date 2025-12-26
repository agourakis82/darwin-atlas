#!/bin/bash
# Prepare dataset snapshot for Zenodo deposit

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist/atlas_dataset_v2"
SNAPSHOT_DIR="$PROJECT_ROOT/dist/zenodo_snapshot"
VERSION="${1:-v2.0.0-alpha}"

echo "📦 Preparing Zenodo snapshot..."
echo "   Version: $VERSION"
echo "   Source: $DIST_DIR"
echo "   Output: $SNAPSHOT_DIR"
echo ""

# Create snapshot directory
mkdir -p "$SNAPSHOT_DIR"

# Copy dataset files
echo "Copying dataset files..."
cp -r "$DIST_DIR"/* "$SNAPSHOT_DIR/" 2>/dev/null || true

# Create README for snapshot
cat > "$SNAPSHOT_DIR/README.md" <<EOF
# Darwin Operator Symmetry Atlas (DOSA) - Dataset Snapshot

**Version**: $VERSION  
**Date**: $(date -u +%Y-%m-%d)  
**DOI**: TBD (will be assigned after Zenodo deposit)

## Dataset Contents

This snapshot contains the complete Darwin Operator Symmetry Atlas dataset:

### CSV Tables
- \`atlas_replicons.csv\`: Replicon metadata
- \`kmer_inversion.csv\`: K-mer inversion symmetry metrics
- \`gc_skew_ori_ter.csv\`: GC skew and ori/ter estimates
- \`replichore_metrics.csv\`: Replichore-level metrics
- \`inverted_repeats_summary.csv\`: Inverted repeats analysis
- \`quaternion_results.csv\`: Quaternion group verification
- \`dicyclic_lifts.csv\`: Dicyclic group lifts

### Parquet Partitions
Parquet format tables are available in \`parquet/\` directory.

### Epistemic Knowledge Layer
- \`epistemic/atlas_knowledge.jsonl\`: Knowledge records with provenance
- \`epistemic/atlas_provenance.json\`: Provenance metadata

## Citation

If you use this dataset, please cite:

> Agourakis, D. C. (2025). *Darwin Operator Symmetry Atlas (DOSA)*. 
> Scientific Data (submitted). DOI: TBD

## License

[To be determined - CC-BY or similar]

## Contact

Principal Investigator: Demetrios Chiuratto Agourakis

## Reproducibility

To reproduce this dataset:

\`\`\`bash
git clone https://github.com/[repo]/darwin-atlas.git
cd darwin-atlas
make atlas MAX=500 SEED=42
\`\`\`

See \`CLAUDE.md\` for full documentation.
EOF

# Create manifest
cat > "$SNAPSHOT_DIR/MANIFEST.txt" <<EOF
Darwin Operator Symmetry Atlas (DOSA) - Dataset Manifest
Version: $VERSION
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Git SHA: $(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")

Files:
EOF

find "$SNAPSHOT_DIR" -type f -not -name "MANIFEST.txt" -not -name "README.md" | sort | while read f; do
    rel_path="${f#$SNAPSHOT_DIR/}"
    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "0")
    sha256=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
    echo "$sha256  $size  $rel_path" >> "$SNAPSHOT_DIR/MANIFEST.txt"
done

# Create archive
ARCHIVE_NAME="darwin-atlas-dataset-$VERSION.tar.gz"
echo ""
echo "Creating archive: $ARCHIVE_NAME"
cd "$PROJECT_ROOT/dist"
tar -czf "$ARCHIVE_NAME" -C "$(basename "$SNAPSHOT_DIR")" .

echo ""
echo "✅ Snapshot prepared:"
echo "   Directory: $SNAPSHOT_DIR"
echo "   Archive: $PROJECT_ROOT/dist/$ARCHIVE_NAME"
echo ""
echo "📊 Snapshot size:"
du -sh "$SNAPSHOT_DIR"
du -sh "$PROJECT_ROOT/dist/$ARCHIVE_NAME"

