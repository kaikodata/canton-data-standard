# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately
through the "Report a vulnerability" button on this repository's Security tab,
which opens a private advisory with the maintainers. We will acknowledge the
report and work with you on a fix and a coordinated disclosure.

## Scope

This repository is the interface standard, its reference implementations, and
its tests. The security-relevant surface is concentrated in the
`canton-data-standard-codecs` utility library, where an off-ledger ECDSA
signature over a structural hash of the payload is checked on-ledger:

- the structural hash in `DataStandard.Codecs.StructuralHash` and the signed
  envelopes in `DataStandard.Codecs.Envelope`, where a mismatch between an
  off-ledger signer and the on-ledger check is a correctness and trust issue.
  Injectivity is the security property the scheme has to hold: a
  non-injective hash would let two distinct payloads collide on the same
  digest, and so let a signature be reused for a payload the distributor never
  signed. The type tags on `AnyValue` nodes and the count prefixes in the
  combinators exist for exactly this reason, and the golden vectors in
  `tests-codecs` are the normative record of the scheme,
- the verify functions in `DataStandard.Codecs.Verify`, including the replay
  window (`expiresAt`), and
- the `DistributorKey` view holding the contract-resident public key and the
  advertised payload codec.

Because the codecs package is an upgradable utility package, a defect here is
fixable in a new version without an ecosystem migration. An interface package
is not, which is why the interface packages contain no executable code.

The reference producers and consumers are illustrative, not production code.

## Supported versions

The standard is pre-release (`0.2.0`). Fixes land on the current version line
until the first tagged release, after which this section will track which
versions receive security updates.
