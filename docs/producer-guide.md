# Producer guide

How to publish data that any consumer of the standard can read.

## What you implement

One thing: an `interface instance` of
`DataStandard.DataPointV1.PublishedData` on your own template. Your package
takes `data-dependencies` on the standard's DARs; consumers never import your
package.

```yaml
# daml.yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.1.0.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.1.0.dar
```

To get the DARs, clone this repository and run `dpm build --all`; they land
in `interfaces/*/.daml/dist/`. CI also attaches them to each run as build
artifacts.

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

    interface instance PublishedData for PublishedPrice where
      view = PublishedDataView with
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
package (`canton-data-standard-utils-v1`), so a later version can widen it. A
reader built against an older version aborts on a constructor it does not know,
which makes adding one a coordinated rollout, not a drop-in change.

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

One delivery constraint to know up front: in v1 the signature-based (pull)
delivery path carries flat scalar payloads only, because the canonical signing
encoding for nested values is not yet defined. Structured payloads are
published through the contract-based (push) path, where the ledger serializes
them canonically and no off-ledger signing is involved.

Document your field names and types per feed, and version that contract with
`schemaVersion`:

- Patch (`1.0.0` to `1.0.1`): no schema-shape change, documentation or
  semantics clarifications only.
- Minor (`1.0.x` to `1.1.0`): adding fields. Existing consumers are
  unaffected, since unknown fields read as `None`.
- Major (`1.x` to `2.0.0`): renaming or removing fields, or changing a
  field's type. Consumers must opt in.

## Metadata

`metadata` carries machine-readable annotations that are not part of the data
itself: provenance, methodology notes, links. Two conventions, shared with
the Canton token standard's metadata usage:

- Prefix keys with the DNS name of the application defining them:
  `"exampleoracle.com/source"`, `"exampleoracle.com/methodology"`.
- Keep entries small. On-ledger data is costly.

Publish `emptyMetadata` when you have nothing to attach. Never widen the view
shape for an annotation; that is what metadata is for.

## Publishing a typed quote

For the common case of a single price on a feed, the standard offers a typed
interface, `DataStandard.QuoteV1.PublishedQuote`, as an alternative to the
generic data point. Its view carries named fields rather than a `values` map, so
there is no payload schema for a consumer to agree on: the interface itself is
the contract.

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
| `publishedAt` | When you produced the quote. Same meaning as `PublishedData.publishedAt`, and consumers use it for staleness. It is distinct from `quote.priceTime`, since a quote can be produced after the instant it prices. |
| `metadata` | Additive annotations, the same convention as the data point. |

`PublishedQuote` is independent of `PublishedData`. If you want a publication
readable both as a typed quote and as a generic data point, implement both
interfaces on the same template and set the shared fields, `distributor` and
`publishedAt`, identically across the two views.

Refresh, revocation, and distribution work the same as for a data point:
archive-and-replace to publish a fresh quote (see `UpdateQuote` in
[`examples/quote-producer`](../examples/quote-producer)), and explicit
disclosure plus the `PublishedQuote_Fetch` choice to reach consumers who are not
stakeholders.

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
consumer reads via the interface's `PublishedData_Fetch` choice.

Observers remain an option when the audience is small and known:
stakeholders can read directly without disclosure.
