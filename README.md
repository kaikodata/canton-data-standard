# canton-data-standard

Versioned Daml interfaces for publishing and consuming market data on
[Canton](https://docs.canton.network/), without coupling consumers to any
provider's Daml package.

A provider publishes market data by implementing a shared interface on its own
contracts. A consumer reads that data through the same interface. Neither side
depends on the other's code, only on the interface packages in this repository.

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
| `interfaces/canton-data-standard-utils-v1` | `canton-data-standard-utils-v1` | The shared value model: `AnyValue`/`Values`, the `Quote` record, `Metadata`, and typed accessors. Kept separate because it can evolve through smart-contract upgrades, which interface-defining packages cannot. |
| `interfaces/canton-data-standard-datapoint-v1` | `canton-data-standard-datapoint-v1` | The generic `PublishedData` interface: a key/value payload (`Values`), publication time, schema version, and extensibility metadata. |
| `examples/datapoint-producer` | `datapoint-producer-example` | A reference producer: a price-publication template implementing `PublishedData`. |
| `examples/datapoint-consumer` | `datapoint-consumer-example` | A reference consumer: a trade workflow that reads any `PublishedData` implementation. Depends only on the interface packages. |
| `interfaces/canton-data-standard-quote-v1` | `canton-data-standard-quote-v1` | The typed `PublishedQuote` interface: a `Quote` (feed, price, and observation time) plus a publication time and extensibility metadata. Independent of `PublishedData`. |
| `examples/quote-producer` | `quote-producer-example` | A reference producer: a quote-publication template implementing `PublishedQuote`. |
| `examples/quote-consumer` | `quote-consumer-example` | A reference consumer: a trade workflow that reads any `PublishedQuote` implementation. Depends only on the interface packages. |
| `tests` | `canton-data-standard-tests` | Daml Script tests for everything above. |

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

- [Producer guide](docs/producer-guide.md): implement `PublishedData` on your
  own template and publish.
- [Consumer guide](docs/consumer-guide.md): read published data through the
  interface, including contracts you are not a stakeholder of.

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
