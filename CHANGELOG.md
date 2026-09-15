# Changelog

Notable changes to the Canton Data Standard packages, newest first. All packages
share one version line while the standard is pre-release.

## [0.2.0]

### Interfaces

- `canton-data-standard-datapoint-v1` — the `PublishedDataPoint` interface: a
  key/value payload (`values`), `publishedAt`, `schemaVersion` and `metadata`,
  read through the `PublishedDataPoint_Fetch` choice.
- `canton-data-standard-distributor-key-v1` — the `DistributorKey` interface: a
  long-lived contract publishing a distributor's secp256k1 public key, its hash
  and signature methods, and the payload codec its signatures cover.
- `canton-data-standard-utils-v1` — the shared data types: `AnyValue`/`Values`,
  `Metadata`, and the signed and verified payload records (`SignedDataPoint`,
  `VerifiedDataPoint`).
- `canton-data-standard-codecs` — the utility library, and the only executable
  code in the standard: the structural hash, the `v2-datapoint-hash` envelope,
  the `verifyDataPoint` signature checks, and the `Quote` record with its
  `Values` codec. No `-v1` suffix, because any two versions of a utility package
  are upgrade-compatible.

### Examples

- `datapoint-producer` / `datapoint-consumer` — publishing and reading a
  key/value payload through the interface, field by field.
- `quote-producer` / `quote-consumer` — the same interface for a price quote,
  encoded and decoded through the codecs library's `Quote`.
- `distributor-key-producer` / `distributor-key-consumer` — the pull path: the
  distributor publishes a key and signs a quote off-ledger; the consumer
  verifies inside its own choice through the codecs library, then decodes.
- `switching-distributor-direct`, `switching-distributor-marketmaker` and
  `switching-consumer` — one consumer reading the same feed from two
  structurally different distributors unchanged, and cross-checking the two.
