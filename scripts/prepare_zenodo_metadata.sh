#!/bin/bash
# Prepare Zenodo metadata with current dataset information

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZENODO_JSON="$PROJECT_ROOT/.zenodo.json"
SNAPSHOT_DIR="$PROJECT_ROOT/dist/zenodo_snapshot"

echo "📦 Preparing Zenodo metadata..."

# Get current git SHA
GIT_SHA=$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")

# Get dataset statistics
if [ -d "$SNAPSHOT_DIR" ]; then
    REPLICON_COUNT=$(wc -l < "$SNAPSHOT_DIR/csv/atlas_replicons.csv" 2>/dev/null | xargs || echo "unknown")
    EPISTEMIC_COUNT=$(wc -l < "$SNAPSHOT_DIR/epistemic/atlas_knowledge.jsonl" 2>/dev/null | xargs || echo "unknown")
else
    REPLICON_COUNT="unknown"
    EPISTEMIC_COUNT="unknown"
fi

# Update description with current stats
cat > "$ZENODO_JSON" <<EOF
{
  "title": "Darwin Operator Symmetry Atlas (DOSA): A database of dihedral symmetries in complete bacterial replicons",
  "description": "A reproducible, DOI-versioned database of operator-defined symmetries in complete bacterial replicons. DOSA implements a hybrid Julia/Demetrios architecture for computing exact and approximate dihedral symmetry metrics across bacterial genomes. The atlas provides: (1) exact symmetry metrics including orbit sizes and palindrome detection; (2) approximate symmetry via normalized minimum dihedral distance (d_min/L); (3) algebraic verification of dicyclic group structure (Dic_n → D_n double cover); and (4) epistemic knowledge layer with full provenance tracking.\n\n**Current Dataset Statistics (v2.0.0-alpha):**\n- Replicons analyzed: ${REPLICON_COUNT}\n- Epistemic knowledge records: ${EPISTEMIC_COUNT}\n- Git SHA: ${GIT_SHA}\n\n**Reproducibility:** All code and data are fully reproducible via 'git clone' + 'make reproduce'. Cross-validation ensures identical results between Julia and Demetrios implementations.",
  "upload_type": "dataset",
  "publication_date": "$(date -u +%Y-%m-%d)",
  "creators": [
    {
      "name": "Agourakis, Demetrios Chiuratto",
      "affiliation": "Independent Researcher",
      "orcid": "0000-0000-0000-0000"
    }
  ],
  "keywords": [
    "bacterial genomes",
    "dihedral symmetry",
    "reverse complement",
    "genomic operators",
    "palindrome sequences",
    "bioinformatics",
    "reproducible research",
    "scientific data",
    "epistemic computing",
    "demetrios language"
  ],
  "license": {
    "id": "CC-BY-4.0"
  },
  "communities": [
    {
      "identifier": "bioinformatics"
    },
    {
      "identifier": "genomics"
    }
  ],
  "related_identifiers": [
    {
      "identifier": "https://github.com/chiuratto-AI/darwin-atlas",
      "relation": "isSupplementTo",
      "scheme": "url"
    }
  ],
  "grants": [],
  "version": "2.0.0-alpha",
  "language": "eng",
  "access_right": "open",
  "notes": "This dataset accompanies a Data Descriptor manuscript submitted to Scientific Data (Nature Portfolio). All code and data are fully reproducible via 'git clone' + 'make reproduce'. The dataset includes both CSV and Parquet formats, plus an epistemic knowledge layer with full provenance tracking."
}
EOF

echo "✅ Zenodo metadata updated: $ZENODO_JSON"
echo "   - Publication date: $(date -u +%Y-%m-%d)"
echo "   - Git SHA: $GIT_SHA"
echo "   - Replicons: $REPLICON_COUNT"
echo "   - Epistemic records: $EPISTEMIC_COUNT"

