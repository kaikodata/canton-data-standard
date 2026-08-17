# Changelog

Notable changes to the Canton Data Standard packages, newest first. All packages
share one version line while the standard is pre-release.

## [0.2.0]

The first tagged release. It ships three interfaces plus one upgradable utility
library, with no executable code in any interface package.

### Interfaces

- `canton-data-standard-datapoint-v1` — the generic `PublishedDataPoint`
  interface: a key/value payload (`values`), `publishedAt`, `schemaVersion` and
  `metadata`, read through the `PublishedDataPoint_Fetch` choice.
- `canton-data-standard-quote-v1` — the typed `PublishedQuote` interface: a
  `Quote` (feed, price, observation time) plus `publishedAt` and `metadata`.
  Independent of `PublishedDataPoint`.
- `canton-data-standard-distributor-key-v1` — the `DistributorKey` interface: a
  long-lived contract publishing a distributor's secp256k1 public key, its hash
  and signature methods, and the payload codec its signatures cover.
- `canton-data-standard-utils-v1` — the shared data types: `AnyValue`/`Values`,
  `Quote`, `Metadata`, and the signed and verified payload records
  (`SignedQuote`, `SignedDataPoint`, `VerifiedQuote`, `VerifiedDataPoint`).
- `canton-data-standard-codecs` — the utility library, and the only executable
  code in the standard: the structural hash, the `Quote` ⇄ `Values` codecs, the
  `v2-quote-hash` and `v2-datapoint-hash` envelopes, and the
  `verifyQuote`/`verifyDataPoint` signature checks. No `-v1` suffix, because any
  two versions of a utility package are upgrade-compatible.

### Examples

- `datapoint-producer` / `datapoint-consumer` — publishing and reading a generic
  key/value payload through the interface.
- `quote-producer` / `quote-consumer` — the same for the typed quote.
- `distributor-key-producer` / `distributor-key-consumer` — the pull path: the
  distributor publishes a key and signs off-ledger; the consumer verifies inside
  its own choice through the codecs library.
- `switching-distributor-direct`, `switching-distributor-marketmaker` and
  `switching-consumer` — one consumer reading the same feed from two
  structurally different distributors unchanged, and cross-checking the two.
