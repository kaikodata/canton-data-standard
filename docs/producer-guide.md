# Producer guide

How to publish data that any consumer of the standard can read.

## What you implement

An `interface instance` on a template you sign, and nothing beyond that. Your
package takes `data-dependencies` on the standard's DARs; consumers never
import your package.

```yaml
# daml.yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.2.0.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.2.0.dar
```

The built DARs are committed under [`dars/`](../dars), and are also attached to
each tagged release. Building from source with `dpm build --all` produces
identical packages, which CI proves on every run.

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

The full producer is [`examples/datapoint-producer`](../examples/datapoint-producer).

| View field | Meaning |
|---|---|
| `distributor` | You, the party consumers decide to trust. |
| `publishedAt` | When the data was produced, which is not necessarily when the contract was created. Consumers use it for staleness checks. |
| `schemaVersion` | Semantic version of your `values` schema. |
| `values` | The payload: field names to typed values, scalar or structured. |
| `metadata` | Additive annotations under DNS-prefixed keys. |

## The `values` payload

`Values` maps field names to `AnyValue`: the scalars `Int`, `Decimal`, `Text`,
`Time`, `Bool`, plus an ordered list and a string-keyed map. Lists and maps
nest, so a structured payload such as an index's constituents is expressible.

The set is closed because the pull path reconstructs payloads on-ledger to
check a signature, which needs one encoding per value. It lives in
`canton-data-standard-utils-v1`, so a later version can widen it — a
coordinated rollout, not a drop-in change, since a reader built against an
older version aborts on a constructor it does not know.

Build payloads with `insertField`, which tags native values:

```daml
let constituent symbol weight =
      insertField "symbol" (symbol : Text)
        $ insertField "weight" (weight : Decimal) TM.empty
values = insertField "assetPair" assetPair
       $ insertField "price"     price
       $ insertField "constituents"
           ([constituent "eurc-usd" 0.6, constituent "usdc-usd" 0.4] : [TextMap AnyValue])
           TM.empty
```

Document your field names and types per feed, and version that contract with
`schemaVersion`: patch for documentation or semantics clarifications, minor for
added fields (unknown fields read as `None`, so existing consumers are
unaffected), major for a rename, a removal or a type change.

## Metadata

`metadata` holds machine-readable annotations that are not part of the data:
provenance, methodology notes, links. Prefix keys with the DNS name of the
application defining them (`"exampleoracle.com/source"`), and keep entries
small, since on-ledger data is costly. Publish `emptyMetadata` when you have
nothing to attach. Metadata exists so that an annotation is never a reason to
widen a view.

## Publishing a price quote

A quote is not a separate interface. It is a `PublishedDataPoint` whose payload
carries `feedId`, `price` and `priceTime`, published under the schema
`quote-1`. `DataStandard.Codecs.Quote` gives you the record and the encoder, so
you never spell the three field names out yourself:

```daml
import DataStandard.Codecs.Quote (Quote(..), quoteSchemaVersion, quoteToValues)

interface instance PublishedDataPoint for PriceQuote where
  view = PublishedDataPointView with
    distributor   = oracle
    publishedAt
    schemaVersion = quoteSchemaVersion
    values        = quoteToValues Quote with feedId; price; priceTime
    metadata      = emptyMetadata
```

`priceTime` is the market instant the price is observed for; `publishedAt` is
when you produced the quote, and a quote can be produced after the instant it
prices. A consumer reads the payload back with `valuesToQuote`, which is strict:
exactly the three fields, each at its expected type, so a payload carrying
anything else is not a quote. If your feed has more to say than a quote's three
fields, publish it under a schema of your own rather than extending this one.
The full producer is [`examples/quote-producer`](../examples/quote-producer).

`Quote` lives in the codecs package, not in `utils-v1`, and so is not a
serializable type: it is a value you encode on the way out and decode on the way
in, never a template field. What a template stores is the `Values` payload, or
the fields it builds one from.

## Publication lifecycle

Refresh is archive-and-replace: a consuming choice that creates the replacement
(`UpdatePrice`, `UpdateQuote` in the examples). A consumer holding the old
contract id then fails fast instead of silently reading stale data. Revocation
is the same operation without a replacement.

## Reaching consumers

A consumer can only read a contract it can see, and there are two ways to make
one visible.

**Explicit disclosure.** Hand the consumer the contract's `template_id`,
`contract_id` and `created_event_blob` off-ledger, over your own API or feed,
and it attaches them to its command submission. See
[explicit contract disclosure](https://docs.canton.network/appdev/deep-dives/explicit-contract-disclosure).
Disclosure is tamper-evident, because a contract id is a hash of the contract's
contents, and it costs the same whether one consumer reads a publication or a
thousand do. The consumer reads through the interface's `_Fetch` choice, since
it is not a stakeholder.

**Observers.** Naming consumers as observers makes them stakeholders: they can
`fetch` directly, and the publication reaches their participant's active
contract set, which is what a query store such as PQS indexes. The cost is that
the publication is stored and streamed per observer, so it grows with the
audience. Use it when the audience is small and known, or when consumers need
to discover publications by query rather than be handed contract ids.

## The pull path

Everything above pushes data onto the ledger. The pull path publishes nothing
per payload: you sign the payload off-ledger with an ECDSA key, hand the signed
bytes to consumers over your own channel, and publish a single long-lived
contract implementing `DistributorKey` (from
`canton-data-standard-distributor-key-v1`) that holds your public key, the
`secp256k1`/`SHA-256` method pair, and the codec id your signatures cover.
Reads never archive it, so no number of consumers verifying concurrently can
contend.

What you sign is the structural hash of the payload, computed by
`canton-data-standard-codecs`: `hashSignedDataPoint` over a `SignedDataPoint`
from `utils-v1`, under the codec id `v2-datapoint-hash`. There is one envelope
and one codec id, quotes included — `DataStandard.Codecs.Quote.signedQuote`
builds the `SignedDataPoint` for a quote, and it is signed and verified exactly
as any other payload is. The envelope commits to a validity window
(`publishedAt`, `expiresAt`); `expiresAt` is the only replay bound the standard
defines, so a captured payload and signature stop verifying once it lapses. An
off-ledger signer needs only SHA-256, lowercase hex, string joins and the scalar
rendering rules; the signature itself is ECDSA over the SHA-256 of the root
hash's decoded bytes. The golden vectors in `tests-codecs` are the normative
record of the scheme.

The standard defines no on-ledger verification choice: a consumer calls
`verifyDataPoint` from its own choice against your disclosed
`DistributorKey`. See
[`examples/distributor-key-producer`](../examples/distributor-key-producer) for
the key publication and rotation, and the [consumer guide](consumer-guide.md)
for the verifying side.

Key rotation is archive-and-replace on the key contract (the example ships a
`RotateKey` choice). Payloads signed under the old key stop verifying once it
is archived, because consumers can no longer read it.

Charging for pulled data and recording durable verification receipts are not
part of the standard. They are product concerns layered on top: a product
template can hold the key, publish the `DistributorKey` view, and settle a fee
in its own choice.
