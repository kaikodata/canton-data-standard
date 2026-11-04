# Changelog

Notable changes to the Canton Data Standard packages, newest first. All packages
share one version line while the standard is pre-release.

## [0.3.0]

### Added

- `canton-data-standard-utils-v1` — `AnyValue` gains `AVParty` and
  `AVInstrumentId`, with `ToAnyValue`/`FromAnyValue` instances, so a payload can
  carry a party and an instrument id through `insertField`/`lookupField`. The
  new `InstrumentId` record mirrors the token standard's
  `Splice.Api.Token.HoldingV2.InstrumentId` (`admin`, `id`) without importing
  it.
- `canton-data-standard-utils-v1` — `AnyValue` gains `AVDate`, with
  `ToAnyValue`/`FromAnyValue` instances, so a calendar date the source gives
  without a time of day (a maturity, ex-dividend or index level date) is carried
  as a Daml `Date` instead of a `Time` at midnight UTC.
- `canton-data-standard-utils-v1` — `AnyValue` gains `AVNull`, a field sent
  with no value, and `ToAnyValue`/`FromAnyValue` instances for `Optional a`
  (`None` as `AVNull`, `Some v` as `v`), so a schema can declare an optional
  field such as `Optional Int` (`AVInt` or `AVNull`) instead of a sentinel. A
  field set to `AVNull` and an absent field are different payloads with
  different hashes: each schema must state which form every optional field
  uses.
- `canton-data-standard-codecs` — structural hash tag `null`, a variant with no
  fields (`sha256("null|0")`), pinned by new golden vectors. Off-ledger signers
  must implement the tag before emitting a null.
- `canton-data-standard-codecs` — `LookupError` gains `NoValue`, returned by
  `lookupFieldEither` for an `AVNull` field read at a type that is not
  `Optional`. `ExpectedType` names `Optional a`, and `anyValueType` names a
  collection mixing one type with nulls after its `Optional`.
- `canton-data-standard-codecs` — structural hash tags `party` (the full party
  id text) and `instrumentId` (the record `admin`, `id`), pinned by new golden
  vectors. Off-ledger signers must implement both tags before emitting either
  value.
- `canton-data-standard-codecs` — structural hash tag `date`, the date as
  integer days since 1970-01-01 (`dateToDays`), pinned by new golden vectors.
  Off-ledger signers must implement the tag before emitting a date.
- `canton-data-standard-codecs` — `DataStandard.Codecs.Lookup.lookupFieldEither`,
  a `lookupField` that says why it found nothing: `Missing` for an absent field,
  `WrongType` (naming the expected and actual types) for one held at another
  type. Same strict read, with no coercion; `lookupField` is unchanged.
- `make upgrade-check`, part of `make ci`: utils-v1 is checked as a
  smart-contract upgrade of its last release, kept in `upgrade-baselines/`.

### Changed

- `canton-data-standard-datapoint-v1` 0.3.0 is rebuilt against utils-v1 0.3.0,
  so `PublishedDataPoint` has a new package id, and an interface's package id is
  its identity. A consumer on 0.2.0 cannot fetch a data point from a producer on
  0.3.0, even one whose payload uses none of the new values: **producers and
  consumers must move to 0.3.0 together.** This is a breaking interface change
  taken as a version bump rather than a `-v2` package because the standard is
  still pre-release.
- `canton-data-standard-distributor-key-v1` moves to 0.3.0 with the rest of the
  version line. Its source is unchanged, but the version is part of the package
  id, so `DistributorKey` gets a new identity: distributors must re-publish and
  re-disclose their key contracts under 0.3.0 for consumers on codecs 0.3.0.
- `quote-1` semantics clarified, with no change to its fields
  ([#18](https://github.com/kaikodata/canton-data-standard/issues/18)): `price`
  is a reference price with no trade size attached, derived by a methodology
  the distributor documents in `metadata` on the push path and out of band on
  the pull path, where a signed payload carries no `metadata`; a price
  executable at a given size belongs under a schema of its own. For a price derived from a pool or an order
  book, `priceTime` is the time of the last trade or book change the price
  reflects, not the time the distributor read it.
- `quote-consumer` and `distributor-key-consumer` bound the age of the quote's
  `priceTime` as well as `publishedAt` (`"price too stale"`), so a fresh
  publication of a market that has stopped trading is rejected. The market age
  has its own bound, `maxPriceAge`, beside `maxQuoteAge`, so a buyer can demand
  a recent publication and still accept a quiet market. A `priceTime` after
  `publishedAt` is rejected (`"price time after publication"`), so a negative
  market age cannot read as fresh.

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
