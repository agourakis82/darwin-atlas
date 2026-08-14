# U0 source-manifest fixture

This is an intentionally tiny stand-in for a rehydrated NCBI Datasets package.
The test script materializes its checksum manifest in a temporary copy, then
checks normal success plus tamper, missing-asset, duplicate, unversioned,
accession-coverage, path-escape, symlink, and colliding-output refusal paths.
The successful run emits a `dosa-v3-source-index-1` record with a
package-relative FASTA locator and the source manifest/integrity hash closure.
It contains no scientific metrics and is not an NCBI snapshot.
