# canton-data-standard

Versioned Daml interfaces for publishing and consuming market data on
[Canton](https://docs.canton.network/), without coupling consumers to any
distributor's Daml package.

A distributor publishes market data by implementing a shared interface on its
own contracts. A consumer reads that data through the same interface. Neither
side depends on the other's code, only on the interface packages in this
repository.

The standard is three interfaces plus a utility library. The push interfaces
(`PublishedDataPoint`, `PublishedQuote`) distribute data as on-ledger contracts
the distributor signs as a Daml party. The `DistributorKey` interface publishes
a distributor's off-ledger signing key, so data signed off-ledger (an ECDSA
signature over a structural hash of the payload) can be pulled and
authenticated on demand by anyone. The verification itself is library code in
`canton-data-standard-codecs`, called from the consumer's own choice. An
interface package holds views and one-line fetch choices; all executable code
(hashing, codecs, signature checks) lives in the utility library, which can be
upgraded at any time.

The generic `PublishedDataPoint` interface fixes the shape a consumer reads: a
distributor, a publication time, a schema version, and a key/value payload. It
does not fix the keys inside that payload. A consumer and the distributors it
reads agree on those out of band, and `schemaVersion` identifies the agreement;
switching to another distributor of the same schema is a configuration change:
which distributor party to trust. A typed interface such as `PublishedQuote`
has named fields in the view itself and drops the schema agreement for the
feeds it covers. The interfaces are versioned, so the shape a consumer builds
against stays fixed for the life of a version.

## Packages

| Path | Package | What it is |
|---|---|---|
| `interfaces/canton-data-standard-utils-v1` | `canton-data-standard-utils-v1` | The shared value model: `AnyValue`/`Values`, the `Quote` record, `Metadata`, typed accessors, and the serializable signed/verified payload records (`SignedQuote`, `SignedDataPoint`, `VerifiedQuote`, `VerifiedDataPoint`). Data-only, so it can evolve through smart-contract upgrades, which interface-defining packages cannot. Its `Metadata` and `AnyValue` mirror the Canton Token Standard's types instead of importing them, which is what keeps the standard free of a token-standard dependency. |
| `interfaces/canton-data-standard-datapoint-v1` | `canton-data-standard-datapoint-v1` | The generic `PublishedDataPoint` interface: a key/value payload (`Values`), publication time, schema version, and extensibility metadata. It holds a view and a fetch choice, nothing else. |
| `interfaces/canton-data-standard-quote-v1` | `canton-data-standard-quote-v1` | The typed `PublishedQuote` interface: a `Quote` (feed, price, and observation time) plus a publication time and extensibility metadata. Independent of `PublishedDataPoint`, and again a view and a fetch choice only. |
| `interfaces/canton-data-standard-distributor-key-v1` | `canton-data-standard-distributor-key-v1` | The `DistributorKey` interface: a long-lived contract publishing a distributor's secp256k1 public key, hash and signature method, and the payload codec its signatures cover. A view and a fetch choice; verification happens in the consumer's own choice through the codecs library. |
| `interfaces/canton-data-standard-codecs` | `canton-data-standard-codecs` | The utility library, and the only package with executable code: the structural hash (combinators and the type-tagged `AnyValue` instance), the `Quote` ⇄ `Values` codecs, the signed-payload envelope hashes (`v2-quote-hash`, `v2-datapoint-hash`), and the `verifyQuote`/`verifyDataPoint` signature checks. Built as a utility package, so any two versions are SCU-compatible and bug fixes ship without an ecosystem migration. Only the verify functions touch the alpha crypto surface; hashing uses the stable `DA.Text.sha256`. |
| `examples/datapoint-producer` | `datapoint-producer-example` | A reference producer: a price-publication template implementing `PublishedDataPoint`. |
| `examples/datapoint-consumer` | `datapoint-consumer-example` | A reference consumer: a trade workflow that reads any `PublishedDataPoint` implementation. Depends only on the interface packages. |
| `examples/quote-producer` | `quote-producer-example` | A reference producer: a quote-publication template implementing `PublishedQuote`. |
| `examples/quote-consumer` | `quote-consumer-example` | A reference consumer: a trade workflow that reads any `PublishedQuote` implementation. Depends only on the interface packages. |
| `examples/switching-distributor-direct` | `switching-distributor-direct-example` | A reference distributor for the distributor-switching demonstration: stores a price directly and implements both `PublishedQuote` and `PublishedDataPoint` on one template. |
| `examples/switching-distributor-marketmaker` | `switching-distributor-marketmaker-example` | A second, structurally different distributor: stores a bid and an ask and derives the mid, exposing the same views as the direct distributor. |
| `examples/switching-consumer` | `switching-consumer-example` | A reference consumer that reads the same feed from either distributor unchanged, gating on a trusted `(distributor, feedId)` pair, and that cross-checks two distributors for agreement. Depends only on the interface packages. |
| `examples/distributor-key-producer` | `distributor-key-producer-example` | A reference distributor for the pull path: a template implementing `DistributorKey`, holding the public key and advertising its payload codec, with a key-rotation choice. |
| `examples/distributor-key-consumer` | `distributor-key-consumer-example` | A reference consumer for the pull path: a trade workflow that authenticates an off-ledger-signed quote in its own choice through the codecs library, against a disclosed `DistributorKey`. Needs no crypto build flag of its own. |
| `tests` | `canton-data-standard-tests` | Daml Script tests for the push interfaces and the `DistributorKey` view. Token-free and crypto-free, so its DAR runs against a live Canton ledger. |
| `tests-codecs` | `canton-data-standard-tests-codecs` | Daml Script tests for the structural hash and the codecs: the normative golden vectors, the tag-injectivity and ordering properties, and the `Quote` ⇄ `Values` round-trips. It builds without the alpha crypto flag, which is how the hashing surface is held to the stable standard library. |
| `tests-crypto` | `canton-data-standard-tests-crypto` | Daml Script tests for the `verifyQuote`/`verifyDataPoint` signature paths, including signatures produced entirely outside Daml. Kept separate because they use Daml Script's `secp256k1` helpers, whose values the live-ledger script runner cannot load. They run in-memory. |

The built interface DARs are committed under `dars/` so they can be taken
straight from the repository, and every CI run proves they are identical to a
from-source rebuild (`make dars-check`, a package-id comparison). Tagged
releases attach the same DARs to a GitHub Release.

## Build and test

Requirements: [dpm](https://docs.digitalasset.com/) (the Daml Package
Manager) and a JDK (17+). The packages pin Daml SDK `3.4.11`
(`dpm install 3.4.11`).

A `Makefile` wraps the common tasks, and CI runs `make ci`:

```bash
make build          # dpm build --all
make test           # run the Daml Script test suites
make validate       # validate the built interface DARs
make lint           # dlint over the Daml sources
make headers-check  # check every Daml file carries the license header
make dars           # refresh the committed DARs in dars/ from a local build
make dars-check     # prove the committed DARs match a from-source rebuild
make clean          # remove build artifacts
make ci             # headers-check, build, validate, test and dars-check
```

## Reading and writing data

- [Producer guide](docs/producer-guide.md): implement `PublishedDataPoint`,
  `PublishedQuote`, or `DistributorKey` on your own template and distribute,
  by push or by off-ledger signing.
- [Consumer guide](docs/consumer-guide.md): read published data through the
  interface, including contracts you are not a stakeholder of, whether pushed to
  you or pulled and verified on demand through the codecs library.

## Versioning policy

The standard versions four things independently:

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
   added as metadata entries under DNS-prefixed keys instead of as view-shape
   changes, so existing readers keep working.
4. The codecs utility package has no `-v1` suffix: any two versions of a
   utility package are SCU-compatible, so fixes and additions ship as ordinary
   version bumps. The signed-payload encodings themselves are versioned by
   codec id (`v2-quote-hash`, `v2-datapoint-hash`), advertised on the
   `DistributorKey` view.

## License

[Apache-2.0](LICENSE)
