# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately
through the "Report a vulnerability" button on this repository's Security tab,
which opens a private advisory with the maintainers. We will acknowledge the
report and work with you on a fix and a coordinated disclosure.

## Scope

This repository is the interface standard, its reference implementations, and
its tests. The security-relevant surface is concentrated in the verifier
interfaces, where an off-ledger ECDSA signature over a canonical encoding is
checked on-ledger:

- the canonical encoding in `QuoteVerifierV1` and `PaidQuoteVerifierV1`, where a
  mismatch between an off-ledger signer and the on-ledger check is a correctness
  and trust issue,
- the replay window (`expiresAt`) and the contract-resident public key, and
- the paid path's settlement, where the fee must be neither redirectable nor
  skippable.

The reference producers, consumers, and the test token registry are
illustrative, not production code. The registry in particular is a deliberately
minimal stub, as its own module documents, and must not be deployed as-is.

## Supported versions

The standard is pre-release (`0.1.0`). Fixes land on the current version line
until the first tagged release, after which this section will track which
versions receive security updates.
