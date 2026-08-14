# U0 offline control-review fixture

This fixture holds only discovery reports and six pre-download control claims.
The test combines it with the pre-existing tiny rehydrated control package,
then verifies the review receipt and rejects ledger, receipt, and package-byte
tampering. The review semantically qualifies the six control claims from the
mini-package bytes, but computes no scientific metric and is never an NCBI
source freeze.
