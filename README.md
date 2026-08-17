# canton-data-standard

Versioned Daml interfaces for publishing and consuming market data on
[Canton](https://docs.canton.network/). A distributor publishes by implementing
a standard interface on its own template; a consumer reads through that
interface. Neither side depends on the other's package.

The standard covers two delivery models.

**Push.** The distributor creates a contract per publication, implementing
`PublishedDataPoint` (a generic key/value payload) or `PublishedQuote` (a typed
price for a named feed). The Daml party that signs the contract is the
authenticated source.

**Pull.** The distributor signs payloads off-ledger with an ECDSA key and
delivers them over its own channel. On-ledger it publishes one long-lived
contract implementing `DistributorKey`; a consumer authenticates any number of
payloads against it by calling `canton-data-standard-codecs` from its own
choice. There is no verifier interface and nothing on-ledger per payload.

Interface packages hold a view and one `_Fetch` choice, and no executable code.
A package that defines an interface can never be smart-contract-upgraded, so a
bug in code placed there would be unfixable. Hashing, codecs and signature
checks all live in `canton-data-standard-codecs`, a utility package whose
versions are mutually upgrade-compatible.

`PublishedDataPoint` fixes the shape a consumer reads — distributor,
publication time, schema version, key/value payload — but not the keys inside
the payload. A consumer and its distributors agree on those out of band, and
`schemaVersion` identifies the agreement. `PublishedQuote` has named fields in
the view instead, so the feeds it covers need no such agreement.

## Packages

| Path | Package | What it is |
|---|---|---|
| `interfaces/canton-data-standard-utils-v1` | `canton-data-standard-utils-v1` | Shared data types: `AnyValue`/`Values`, `Quote`, `Metadata`, and the signed and verified payload records (`SignedQuote`, `SignedDataPoint`, `VerifiedQuote`, `VerifiedDataPoint`). Data-only, so it evolves through smart-contract upgrades. Its `Metadata` and `AnyValue` mirror the Canton Token Standard's types instead of importing them, which keeps the standard free of that dependency. |
| `interfaces/canton-data-standard-datapoint-v1` | `canton-data-standard-datapoint-v1` | The generic `PublishedDataPoint` interface: `values`, `publishedAt`, `schemaVersion`, `metadata`. |
| `interfaces/canton-data-standard-quote-v1` | `canton-data-standard-quote-v1` | The typed `PublishedQuote` interface: a `Quote` (feed, price, observation time) plus `publishedAt` and `metadata`. Independent of `PublishedDataPoint`. |
| `interfaces/canton-data-standard-distributor-key-v1` | `canton-data-standard-distributor-key-v1` | The `DistributorKey` interface: a distributor's secp256k1 public key, its hash and signature methods, and the payload codec its signatures cover. |
| `interfaces/canton-data-standard-codecs` | `canton-data-standard-codecs` | The utility library, and the only executable code in the standard: the structural hash, the `Quote` ⇄ `Values` codecs, the signed envelopes (`v2-quote-hash`, `v2-datapoint-hash`) and `verifyQuote`/`verifyDataPoint`. Only the verify functions touch the alpha crypto builtins; hashing uses the stable `DA.Text.sha256`. |

`examples/` holds a reference producer and consumer for each path
(`datapoint-*`, `quote-*`, `distributor-key-*`), plus a distributor-switching
demonstration (`switching-*`) in which one consumer reads two structurally
different distributors unchanged. The consumers there depend only on this
repository's packages, never on a distributor's.

`tests/` covers the push interfaces and is token-free and crypto-free, so its
DAR also runs against a live Canton ledger. `tests-codecs/` holds the normative
golden vectors for the structural hash and builds without the alpha crypto
flag. `tests-crypto/` covers the signature paths, including signatures produced
entirely outside Daml, and runs in-memory only.

The built interface DARs are committed under `dars/` so they can be taken
straight from the repository; CI proves on every run that they match a
from-source rebuild (`make dars-check`, a package-id comparison). Tagged
releases attach the same files to a GitHub Release.

## Build and test

Requirements: [dpm](https://docs.digitalasset.com/) (the Daml Package Manager)
and a JDK (17+). The packages pin Daml SDK `3.4.11` (`dpm install 3.4.11`).

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

## Guides

- [Producer guide](docs/producer-guide.md): implement `PublishedDataPoint`,
  `PublishedQuote` or `DistributorKey` on your own template, and distribute by
  push or by off-ledger signing.
- [Consumer guide](docs/consumer-guide.md): read published data through the
  interfaces, whether pushed to you or pulled and verified on demand.

## Versioning policy

1. The interface version is in the package and module name (`...-datapoint-v1`,
   `DataStandard.DataPointV1`). A breaking change is a new `-v2` package, and
   that is the only ecosystem-wide migration point: `v1` stays available.
2. The payload schema version is a field on the generic view (`schemaVersion`,
   semantic versioning). It describes one feed's `values` content and evolves
   per distributor. A typed interface has no separate payload schema.
3. `metadata` on every view carries additive evolution: new annotations go in
   as DNS-prefixed entries instead of view-shape changes.
4. The codecs package has no `-v1` suffix, because any two versions of a
   utility package are upgrade-compatible; fixes ship as ordinary version
   bumps. The signed encodings are versioned separately by codec id
   (`v2-quote-hash`, `v2-datapoint-hash`), advertised on the `DistributorKey`
   view.

## License

[Apache-2.0](LICENSE)
