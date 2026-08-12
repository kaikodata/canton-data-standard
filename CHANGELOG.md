# Changelog

Notable changes to the Canton Data Standard packages, newest first. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the interface
packages share one version line while the standard is pre-release.

## [0.2.0]

The v0.2 reduction, in response to Digital Asset's review of the standard
(PR #11): three interfaces plus an upgradable utility library, with no
executable code left in any interface package.

### Added

- The `DistributorKey` interface (`canton-data-standard-distributor-key-v1`):
  a long-lived contract publishing a distributor's secp256k1 public key, hash
  and signature method, and the payload codec its signatures cover.
- The `canton-data-standard-codecs` utility package (no `-v1` suffix: any two
  utility-package versions are SCU-compatible): the structural hash, the
  `Quote` ⇄ `Values` codecs, the signed-envelope hashes under the new
  `v2-quote-hash` and `v2-datapoint-hash` codec ids, and the
  `verifyQuote`/`verifyDataPoint` signature checks. Only the verify functions
  touch the alpha crypto surface; hashing uses stable `DA.Text.sha256`.
- Serializable payload and result records in `utils-v1`: `SignedQuote`,
  `SignedDataPoint`, `VerifiedQuote`, `VerifiedDataPoint`, shared by all
  distributors and consumers of the pull path.
- A `distributor-key-producer`/`distributor-key-consumer` example pair: sign
  off-ledger, verify in the consumer's own choice through the library.
- Committed interface DARs under `dars/`, a `make dars-check` CI gate proving
  they match a from-source rebuild (package-id comparison), and a
  tag-triggered release workflow attaching the same DARs to a GitHub Release.
- The `tests-codecs` suite: normative golden vectors for the structural hash,
  injectivity and ordering properties, and codec round-trips, built without
  the alpha crypto flag.

### Changed

- `PublishedData` is now `PublishedDataPoint` (with `PublishedDataPointView`
  and `PublishedDataPoint_Fetch`), parallel with `PublishedQuote`.
- `distributor` is the single term across code and prose; the
  provider-switching examples are now `switching-distributor-direct` and
  `switching-distributor-marketmaker`.
- The signature input is a structural hash (Splice `CryptoHash` combinators
  with type-tagged `AnyValue` nodes) instead of the two v1 byte encodings.
- All packages move to version `0.2.0`.

### Removed

- The four verifier interfaces (`QuoteVerifier`, `PaidQuoteVerifier`,
  `DataPointVerifier`, `PaidDataPointVerifier`), their four audit packages,
  and their eight examples. Verification is library code in
  `canton-data-standard-codecs`; paid settlement and audit records move to
  the implementation layer (Kaiko's Pull Oracle V2 keeps both as product
  code).
- `VerificationAudit` from `utils-v1` (it leaves with the audit packages).
- The `v1-quote-concat` and `v1-datapoint-tlv` canonical encodings, replaced
  by the structural hash (which needs no delimiter guard).
- The Canton Token Standard dependency and the vendored splice DARs; the
  `test-token-registry` example moves to Pull Oracle V2 as a test fixture.
