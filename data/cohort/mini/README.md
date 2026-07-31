# Mini cohort — complete RefSeq replicons (frozen)

Frozen miniature cohort of **complete** RefSeq assemblies, acquired with the
official NCBI Datasets CLI. This is the engineering-scale cohort for gates
G2/G3 at complete-replicon scope; it is NOT the pilot `core` cohort of
specification §8 (that manifest remains pending — see proposed ADR-0002).

## Assemblies

| Assembly | Organism | Level | RefSeq category | Replicons |
|---|---|---|---|---|
| `GCF_000005845.2` | *Escherichia coli* str. K-12 substr. MG1655 | Complete Genome | reference genome | `NC_000913.3` chromosome 4,641,652 bp |
| `GCF_000008865.2` | *Escherichia coli* O157:H7 str. Sakai | Complete Genome | reference genome | `NC_002695.2` chromosome 5,498,578 bp; `NC_002127.1` plasmid pOSAK1 3,306 bp; `NC_002128.1` plasmid pO157 92,721 bp |

All four replicons are declared `circular` by the official GenBank LOCUS
lines (`topology_locus.txt`, extracted from the NCBI GBFF data package).
These are the same accessions whose 16 bp prefixes anchor the mini-pipeline
fixtures, so the fixture and the cohort now share provenance.

## Acquisition (exact commands)

```bash
datasets download genome accession GCF_000005845.2 GCF_000008865.2 \
  --include genome,seq-report --filename cohort.zip   # 2026-07-31T18:04:35Z
datasets download genome accession GCF_000005845.2 GCF_000008865.2 \
  --include gbff --filename gbff.zip                  # topology evidence only
```

- NCBI Datasets CLI: `datasets 18.34.0`, binary SHA-256
  `f1133f8278edc594b9c36082e08140c4cde0acfd2591118e4faf4e5055b3592c`
  (`dataformat` SHA-256
  `625fc7d5760825ae0790280343a1c895069479124982e1648b8241fa47c1f134`).
- Download package SHA-256:
  `f1e34c49e83f9889eb265c8bd71f841ef4bac15ef3196ba59e7d60a907d6c6ad`;
  GBFF (topology) package SHA-256:
  `e1539824ef649046f5222f7babe7fde2eda7c39b04724e502ccf2b96cd38e106`.
- Query filters: explicit accession-version list, no taxon query. The cohort
  is defined by this manifest, per specification §8.

## Integrity

- `ncbi_md5sum.txt` is the official NCBI per-file MD5 manifest from the
  downloaded data package. Every committed file derived from the package
  verifies against it (checked at acquisition and by `make contract`).
- `SHA256SUMS` pins the bytes of every frozen file in this directory (all
  files except `SHA256SUMS` itself and this README);
  `cohort_manifest.jsonl` additionally carries the per-assembly genomic
  FASTA SHA-256 and both download package SHA-256 values.
- FASTA record lengths verify against the official `sequence_report.jsonl`
  lengths for all four replicons (checked at acquisition).
- `cohort_manifest.jsonl` follows specification §11.1 fields
  (`assembly_accession_version`, `taxid`, `organism_name`,
  `refseq_category`, `assembly_level`, `retrieval_utc`, `datasets_version`,
  `package_md5`, `included`) plus provenance extensions. `package_md5` is the
  official NCBI MD5 of the assembly's `genomic.fna` within the data package
  (see `package_md5_scope`).
- `replicons.tsv` is the replicon-level manifest (record order for pipeline
  metadata; class/topology/length from official reports).

Any change to a byte in this directory invalidates every downstream receipt
and differential that binds these hashes.
