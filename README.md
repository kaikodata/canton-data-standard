# canton-data-standard

Versioned Daml interfaces for publishing and consuming market data on
[Canton](https://docs.canton.network/), without coupling consumers to any
provider's Daml package.

A provider publishes market data by implementing a shared interface on its own
contracts. A consumer reads that data through the same interface. Neither side
depends on the other's code, only on the interface packages in this repository.

The standard offers two ways to deliver the same data. The push interfaces
(`PublishedData`, `PublishedQuote`) distribute data as on-ledger contracts the
producer signs as a Daml party. The verifier interfaces (`QuoteVerifier`,
`PaidQuoteVerifier`, `DataPointVerifier`, `PaidDataPointVerifier`) distribute
data the producer signs off-ledger with an ECDSA key, so a consumer pulls a
signed quote or data point and authenticates it on demand against a long-lived
verifier contract that holds the producer's public key. A verified quote is
field-aligned with a pushed one, and a verified data point with a pushed data
point, so consumer code that reads a value is the same either way.

The generic `PublishedData` interface fixes the shape a consumer reads: a
distributor, a publication time, a schema version, and a key/value payload. It
does not fix the keys inside that payload. A consumer and the providers it
reads agree on those out of band, and `schemaVersion` identifies the agreement;
switching to another provider of the same schema is a configuration change:
which distributor party to trust. Typed interfaces such as the
`PublishedQuote` interface carry named fields in the view itself and drop the
schema agreement for the feeds they cover. The interfaces are versioned, so the
shape a consumer builds against stays fixed for the life of a version.

## Packages

| Path | Package | What it is |
|---|---|---|
| `interfaces/canton-data-standard-utils-v1` | `canton-data-standard-utils-v1` | The shared value model: `AnyValue`/`Values`, the `Quote` record, `Metadata`, and typed accessors. Kept separate because it can evolve through smart-contract upgrades, which interface-defining packages cannot. Its `Metadata` and `AnyValue` deliberately mirror the Canton Token Standard's types rather than importing them, so the push interfaces carry no token-standard dependency. |
| `interfaces/canton-data-standard-datapoint-v1` | `canton-data-standard-datapoint-v1` | The generic `PublishedData` interface: a key/value payload (`Values`), publication time, schema version, and extensibility metadata. |
| `examples/datapoint-producer` | `datapoint-producer-example` | A reference producer: a price-publication template implementing `PublishedData`. |
| `examples/datapoint-consumer` | `datapoint-consumer-example` | A reference consumer: a trade workflow that reads any `PublishedData` implementation. Depends only on the interface packages. |
| `interfaces/canton-data-standard-quote-v1` | `canton-data-standard-quote-v1` | The typed `PublishedQuote` interface: a `Quote` (feed, price, and observation time) plus a publication time and extensibility metadata. Independent of `PublishedData`. |
| `examples/quote-producer` | `quote-producer-example` | A reference producer: a quote-publication template implementing `PublishedQuote`. |
| `examples/quote-consumer` | `quote-consumer-example` | A reference consumer: a trade workflow that reads any `PublishedQuote` implementation. Depends only on the interface packages. |
| `examples/switching-provider-direct` | `switching-provider-direct-example` | A reference provider for the provider-switching demonstration: stores a price directly and implements both `PublishedQuote` and `PublishedData` on one template. |
| `examples/switching-provider-marketmaker` | `switching-provider-marketmaker-example` | A second, structurally different provider: stores a bid and an ask and derives the mid, exposing the same views as the direct provider. |
| `examples/switching-consumer` | `switching-consumer-example` | A reference consumer that reads the same feed from either provider unchanged, gating on a trusted `(distributor, feedId)` pair, and that cross-checks two providers for agreement. Depends only on the interface packages. |
| `interfaces/canton-data-standard-quote-verifier-v1` | `canton-data-standard-quote-verifier-v1` | The `QuoteVerifier` interface: a long-lived contract that holds a producer's secp256k1 public key and authenticates off-ledger-signed quotes through a pure `QuoteVerifier_Verify` choice that writes nothing to the ledger. |
| `interfaces/canton-data-standard-paid-quote-verifier-v1` | `canton-data-standard-paid-quote-verifier-v1` | The `PaidQuoteVerifier` interface: the pay-as-you-go sibling of `QuoteVerifier`. `PaidQuoteVerifier_VerifyAndPay` authenticates a quote and settles a producer-signed per-call fee, with a single Canton Token Standard transfer, in one transaction. |
| `examples/verifier-producer` | `verifier-producer-example` | A reference producer: a `SignatureVerifier` template implementing the free `QuoteVerifier`, holding the public key. Token-free. |
| `examples/verifier-consumer` | `verifier-consumer-example` | A reference consumer: a trade workflow that authenticates a pulled quote through a disclosed `QuoteVerifier`. Depends only on the interface packages, and is token-free. |
| `examples/paid-verifier-producer` | `paid-verifier-producer-example` | A reference producer for the paid path: a `PaidSignatureVerifier` template implementing `PaidQuoteVerifier`, holding the public key and the fee payee. |
| `examples/paid-verifier-consumer` | `paid-verifier-consumer-example` | A reference consumer for the paid path: a trade workflow that authenticates a pulled quote through a disclosed `PaidQuoteVerifier` and pays the per-call fee. Reuses the settlement record from `verifier-consumer`. |
| `interfaces/canton-data-standard-datapoint-verifier-v1` | `canton-data-standard-datapoint-verifier-v1` | The `DataPointVerifier` interface: the data point sibling of `QuoteVerifier`. A long-lived contract that holds a producer's secp256k1 public key and authenticates off-ledger-signed data points through a pure `DataPointVerifier_Verify` choice that writes nothing to the ledger, under the recursive `v1-datapoint-tlv` canonical encoding. |
| `interfaces/canton-data-standard-paid-datapoint-verifier-v1` | `canton-data-standard-paid-datapoint-verifier-v1` | The `PaidDataPointVerifier` interface: the pay-as-you-go sibling of `DataPointVerifier`. `PaidDataPointVerifier_VerifyAndPay` authenticates a data point and settles a producer-signed per-call fee, with a single Canton Token Standard transfer, in one transaction. |
| `examples/datapoint-verifier-producer` | `datapoint-verifier-producer-example` | A reference producer: a `DataPointSignatureVerifier` template implementing the free `DataPointVerifier`, holding the public key. Token-free. |
| `examples/datapoint-verifier-consumer` | `datapoint-verifier-consumer-example` | A reference consumer: a `RateSubscription` that authenticates a pulled data point through a disclosed `DataPointVerifier` and records it as a `RecordedRate`, gating on `distributor`, `schemaVersion`, and a `values` feed field. Depends only on the interface packages, and is token-free. |
| `examples/paid-datapoint-verifier-producer` | `paid-datapoint-verifier-producer-example` | A reference producer for the paid path: a `PaidDataPointSignatureVerifier` template implementing `PaidDataPointVerifier`, holding the public key and the fee payee. |
| `examples/paid-datapoint-verifier-consumer` | `paid-datapoint-verifier-consumer-example` | A reference consumer for the paid path: a `PaidRateSubscription` that authenticates a pulled data point through a disclosed `PaidDataPointVerifier` and pays the per-call fee. Reuses the `RecordedRate` record from `datapoint-verifier-consumer`. |
| `examples/test-token-registry` | `test-token-registry` | A test-only registry implementing the Canton Token Standard holding and transfer interfaces, so the paid-verifier tests can settle a real one-step transfer. Not part of the standard. |
| `tests` | `canton-data-standard-tests` | Daml Script tests for the push interfaces. Token-free and crypto-free, so its DAR runs against a live Canton ledger. |
| `tests-crypto` | `canton-data-standard-tests-crypto` | Daml Script tests for the `QuoteVerifier` and `DataPointVerifier` signature paths, including golden vectors for both canonical encodings. Kept separate because they use Daml Script's `secp256k1` helpers, whose values the live-ledger script runner cannot load. They run in-memory. |
| `tests-paid` | `canton-data-standard-tests-paid` | Daml Script tests for the paid path, both `PaidQuoteVerifier` and `PaidDataPointVerifier`, which exercise the Canton Token Standard settlement and so depend on the token packages. |

## Build and test

Requirements: [dpm](https://docs.digitalasset.com/) (the Daml Package
Manager) and a JDK (17+). The packages pin Daml SDK `3.4.11`
(`dpm install 3.4.11`).

A `Makefile` wraps the common tasks, and CI runs `make ci`:

```bash
make build          # dpm build --all
make test           # run the Daml Script test suite
make validate       # validate the built interface DARs
make lint           # dlint over the Daml sources
make headers-check  # check every Daml file carries the license header
make clean          # remove build artifacts
make ci             # headers-check, build, validate and test
```

## Reading and writing data

- [Producer guide](docs/producer-guide.md): implement `PublishedData`,
  `PublishedQuote`, or a verifier interface on your own template and distribute,
  by push or by off-ledger signing.
- [Consumer guide](docs/consumer-guide.md): read published data through the
  interface, including contracts you are not a stakeholder of, whether pushed to
  you or pulled and verified on demand.

## Versioning policy

The standard versions three things independently:

1. The interface version lives in the package and module name
   (`...-datapoint-v1`, `DataStandard.DataPointV1`). A breaking change to an
   interface is a new `-v2` package. That is the one ecosystem-wide migration
   point; `v1` stays available and nothing changes under existing consumers.
2. The payload schema version is a field on the generic data point view
   (`schemaVersion`, semantic versioning). It describes the `values` content of
   a given feed and evolves per producer, independently of the interface. A
   typed interface such as the quote has no separate payload schema; its
   interface version is its schema.
3. Metadata on every view handles additive evolution. New annotations are
   added as metadata entries under DNS-prefixed keys rather than as
   view-shape changes, so existing readers keep working.

## License

[Apache-2.0](LICENSE)
