# Producer guide

How to publish data that any consumer of the standard can read.

## What you implement

An `interface instance` of `DataStandard.DataPointV1.PublishedDataPoint` on
your own template, and nothing beyond that. Your package takes
`data-dependencies` on the standard's DARs; consumers never import your
package.

```yaml
# daml.yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.2.0.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.2.0.dar
```

The built DARs are committed under [`dars/`](../dars) so you can take them
directly from the repository (or from a tagged GitHub Release); building from
source with `dpm build --all` produces identical packages, which CI proves on
every run.

```daml
import qualified DA.TextMap as TM
import DataStandard.DataPointV1
import DataStandard.Utils

template PublishedPrice
  with
    oracle    : Party
    assetPair : Text
    price     : Decimal
    at        : Time
  where
    signatory oracle

    interface instance PublishedDataPoint for PublishedPrice where
      view = PublishedDataPointView with
        distributor   = oracle
        publishedAt   = at
        schemaVersion = "1.0.0"
        values        = insertField "assetPair" assetPair
                      $ insertField "price"     price
                        TM.empty
        metadata      = emptyMetadata
```

The full version of this producer lives in
[`examples/datapoint-producer`](../examples/datapoint-producer).

## The view, field by field

| Field | Meaning |
|---|---|
| `distributor` | You, the party consumers decide to trust. |
| `publishedAt` | When the data was produced. Consumers use it for staleness checks, so if the data's timestamp differs from the contract-creation time, use the data's timestamp. |
| `schemaVersion` | Semantic version of your `values` schema (see below). |
| `values` | The payload: field names to typed values, scalar or structured. |
| `metadata` | Additive annotations under DNS-prefixed keys (see below). |

## The `values` payload

`Values` maps field names to `AnyValue`, a closed set the standard governs:
the scalars `Int`, `Decimal`, `Text`, `Time`, `Bool`, plus an ordered list and
a string-keyed map. The list and map nest, so you can express a structured
payload such as an index's constituents.

The set is closed because signature-based delivery reconstructs payload bytes
canonically on-ledger, which needs one encoding per value. It lives in its own
package (`canton-data-standard-utils-v1`), so a later version can widen it.
Adding a constructor is a coordinated rollout, not a drop-in change: a reader
built against an older version aborts on a constructor it does not know.

Build payloads with `insertField`, which converts native values to their
tagged representation:

```daml
values = insertField "assetPair" assetPair
       $ insertField "price"     price
       $ insertField "confidence" (0.99 : Decimal)
         TM.empty
```

For a structured field, insert a list or a map directly. An index's
constituents, for example, is a list of maps:

```daml
let constituent symbol weight =
      insertField "symbol" (symbol : Text)
        $ insertField "weight" (weight : Decimal) TM.empty
values = insertField "constituents"
           ([constituent "eurc-usd" 0.6, constituent "usdc-usd" 0.4] : [TextMap AnyValue])
           TM.empty
```

Both delivery paths handle the full value set, nested lists and maps included.
The contract-based (push) path relies on the ledger to serialize the payload.
The signature-based (pull) path signs a structural hash of the same `AnyValue`
tree, computed by the `canton-data-standard-codecs` library and described in
[Distributing signed data](#distributing-signed-data-the-pull-path) below.

Document your field names and types per feed, and version that contract with
`schemaVersion`:

- Patch (`1.0.0` to `1.0.1`): no schema-shape change, documentation or
  semantics clarifications only.
- Minor (`1.0.x` to `1.1.0`): adding fields. Existing consumers are
  unaffected, since unknown fields read as `None`.
- Major (`1.x` to `2.0.0`): renaming or removing fields, or changing a
  field's type. Consumers must opt in.

## Metadata

`metadata` holds machine-readable annotations that are not part of the data
itself: provenance, methodology notes, links. Two conventions, shared with
the Canton token standard's metadata usage:

- Prefix keys with the DNS name of the application defining them:
  `"exampleoracle.com/source"`, `"exampleoracle.com/methodology"`.
- Keep entries small. On-ledger data is costly.

Publish `emptyMetadata` when you have nothing to attach. An annotation is
never a reason to widen the view shape; metadata exists so you do not have to.

## Publishing a typed quote

For the common case of a single price on a feed, the standard offers a typed
interface, `DataStandard.QuoteV1.PublishedQuote`, as an alternative to the
generic data point. Its view has named fields instead of a `values` map, so
there is no payload schema for a consumer to agree on.

You implement it the same way, an `interface instance` on a template you sign.
The economic content (feed, price, observation time) is a `Quote` record from
`DataStandard.Utils`; the view wraps it with the provenance the quote omits:

```daml
import DataStandard.QuoteV1
import DataStandard.Utils

template PriceQuote
  with
    oracle      : Party
    feedId      : Text
    price       : Decimal
    priceTime   : Time
    publishedAt : Time
  where
    signatory oracle

    interface instance PublishedQuote for PriceQuote where
      view = PublishedQuoteView with
        distributor = oracle
        quote = Quote with feedId; price; priceTime
        publishedAt
        metadata    = emptyMetadata
```

The view, field by field:

| Field | Meaning |
|---|---|
| `distributor` | You, the party consumers decide to trust. |
| `quote` | The economic content: a `Quote` record with `feedId` (the feed, for example `"BTC/USD"`), `price` (an exact base-10 fixed-point `Decimal`), and `priceTime` (the market time the price is observed for). |
| `publishedAt` | When you produced the quote. Same meaning as `PublishedDataPoint.publishedAt`, and consumers use it for staleness. It is distinct from `quote.priceTime`, since a quote can be produced after the instant it prices. |
| `metadata` | Additive annotations, the same convention as the data point. |

`PublishedQuote` is independent of `PublishedDataPoint`. If you want a publication
readable both as a typed quote and as a generic data point, implement both
interfaces on the same template and set the shared fields, `distributor` and
`publishedAt`, identically across the two views.

Refresh, revocation, and distribution work the same as for a data point:
archive-and-replace to publish a fresh quote (see `UpdateQuote` in
[`examples/quote-producer`](../examples/quote-producer)), and explicit
disclosure plus the `PublishedQuote_Fetch` choice to reach consumers who are not
stakeholders.

## Distributing signed data: the pull path

Everything above pushes data onto the ledger: you create a contract per
publication and refresh it by archive-and-replace. The pull path is the other
delivery model. You sign the payload off-ledger with an ECDSA key, hand the
signed bytes to consumers through your own channel (your API, a feed), and
publish a single on-ledger contract: a `DistributorKey` (from
`canton-data-standard-distributor-key-v1`) holding your public key, the
`secp256k1`/`SHA-256` method pair, and the codec id your signatures cover
(`v2-quote-hash` or `v2-datapoint-hash`). Nothing at all is published per
payload.

What you sign is the structural hash of the payload, computed by
`canton-data-standard-codecs` (`hashSignedQuote` over a `SignedQuote`,
`hashSignedDataPoint` over a `SignedDataPoint`, both records from `utils-v1`).
An off-ledger signer needs only SHA-256, lowercase hex, string joins, and the
scalar rendering rules; the golden vectors in `tests-codecs` are the normative
record of the scheme, and the signature is ECDSA over the SHA-256 of the root
hash's decoded bytes. This standard defines no on-ledger verification choice:
a consumer calls the library's `verifyQuote`/`verifyDataPoint` from its own
choice, against your disclosed `DistributorKey`. See
[`examples/distributor-key-producer`](../examples/distributor-key-producer)
for the key publication and rotation, and the
[consumer guide](consumer-guide.md) for the verifying side.

Key rotation is archive-and-replace on the key contract, the same lifecycle as
every other publication (the example ships a `RotateKey` choice). Charging for
pulled data, and leaving durable verification receipts, are not part of the
standard. They are product concerns an implementor layers on top: a product
template can hold the key, publish the `DistributorKey` view, and settle a fee
in its own choice.

## Publication lifecycle

Refresh is archive-and-replace: a consuming choice that creates the
replacement (see `UpdatePrice` in the example). Consumers holding the old
contract id fail fast on stale data instead of silently reading it.
Revocation is the same operation without a replacement: archive the contract
and it is gone, immediately.

## Distribution

You do not need to enumerate your audience as observers. Share the contract
through [explicit disclosure](https://docs.canton.network/appdev/deep-dives/explicit-contract-disclosure):
hand the consumer the contract's `template_id`, `contract_id` and
`created_event_blob` off-ledger (your API, a feed, etc.). Disclosure is
tamper-evident, because a contract id is a hash of its contents, and the
consumer reads via the interface's `PublishedDataPoint_Fetch` choice.

Observers remain an option when the audience is small and known:
stakeholders can read directly without disclosure.
