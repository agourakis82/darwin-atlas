# Zenodo DOI Guide for DSLG Atlas

This guide explains how to obtain a DOI for the DSLG Atlas dataset through Zenodo.

## Overview

Zenodo is a general-purpose open-access repository operated by CERN that provides DOIs for research outputs. GitHub releases can be automatically archived to Zenodo, creating citable DOIs.

## Types of DOIs

Zenodo provides two types of DOIs:

### 1. Version DOI (Specific Release)
- Unique identifier for a specific release/version
- Format: `10.5281/zenodo.XXXXXXX`
- Changes with each new release
- Use when citing a specific dataset version

### 2. Concept DOI (All Versions)
- Persistent identifier that resolves to the latest version
- Format: `10.5281/zenodo.YYYYYYY`
- Remains constant across all versions
- Use when citing the project in general

## Setup Instructions

### Step 1: Connect GitHub to Zenodo

1. Go to [zenodo.org](https://zenodo.org) and sign in (or create account)
2. Navigate to **Settings** → **GitHub**
3. Click **Connect** to authorize Zenodo
4. Find `agourakis82/darwin-atlas` in the repository list
5. Toggle the switch to **ON** to enable archiving

### Step 2: Create a Release

When you create a GitHub release, Zenodo automatically:
1. Downloads the release assets
2. Creates a Zenodo record
3. Assigns a DOI
4. Publishes the archive

```bash
# Example: Create a release
git tag v0.1.0-epistemic
git push origin v0.1.0-epistemic
gh release create v0.1.0-epistemic --title "v0.1.0-epistemic" --notes "Initial epistemic release"
```

### Step 3: Verify and Update Metadata

1. Go to your Zenodo uploads
2. Find the new record
3. Update metadata if needed:
   - Title
   - Description
   - Authors/Contributors
   - License
   - Keywords
4. Publish (if not auto-published)

### Step 4: Get Your DOIs

After publishing:
1. Visit the record page on Zenodo
2. Copy the **Version DOI** (specific to this release)
3. Copy the **Concept DOI** (all versions)

## Updating the Repository

Once you have DOIs, update these files:

### CITATION.cff
```yaml
identifiers:
  - type: doi
    value: "10.5281/zenodo.XXXXXXX"  # Replace with actual DOI
    description: "Zenodo archive"
```

### README.md
Update the badge:
```markdown
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
```

### .zenodo.json (Optional)
Create this file to customize Zenodo metadata:
```json
{
  "title": "DSLG Atlas — Demetrios Operator Symmetry Atlas",
  "creators": [
    {
      "name": "Agourakis, Demetrios Chiuratto",
      "affiliation": "Independent Researcher",
      "orcid": "0009-0001-8671-8878"
    }
  ],
  "description": "A reproducible database of operator-defined symmetries in bacterial replicons.",
  "keywords": ["bacterial genomics", "dihedral symmetry", "epistemic computing"],
  "license": {"id": "MIT"},
  "upload_type": "dataset"
}
```

## Workflow for New Releases

1. Complete all code/data changes
2. Update version in CITATION.cff
3. Create git tag: `git tag vX.Y.Z`
4. Push tag: `git push origin vX.Y.Z`
5. Create GitHub release with release notes
6. Wait for Zenodo to process (~minutes)
7. Verify DOI is live on Zenodo
8. Update README badge with new version DOI (optional)

## Best Practices

1. **Use semantic versioning**: v1.0.0, v1.0.1, v1.1.0, etc.
2. **Include release notes**: Describe changes for reproducibility
3. **Archive snapshots**: Use `make snapshot-zip` to create archives
4. **Verify checksums**: Include checksums in release assets
5. **Keep concept DOI stable**: Don't change it between versions

## Current Status

| Item | Value |
|------|-------|
| Repository | agourakis82/darwin-atlas |
| Current Release | v0.1.0-epistemic |
| Zenodo Connected | [To be configured] |
| Version DOI | [To be assigned] |
| Concept DOI | [To be assigned] |

## References

- [Zenodo GitHub Integration](https://docs.zenodo.org/en/latest/github.html)
- [Making Your Code Citable](https://guides.github.com/activities/citable-code/)
- [DOI Handbook](https://www.doi.org/doi_handbook/)

---

*Last updated: 2025-12-16*
