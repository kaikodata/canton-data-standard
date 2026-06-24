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

## Distributing a signed quote: the verifier interfaces

Everything above pushes data onto the ledger: you create a contract per
publication and refresh it by archive-and-replace. The verifier interfaces are
the other delivery model. You sign the quote off-ledger with an ECDSA key, hand
the signed bytes to consumers through your own channel (your API, a feed), and
publish just one on-ledger contract that holds your public key. A consumer
pulls a signed quote whenever it needs one and authenticates it against that
contract. You write nothing per quote, and the verifier contract is reused for
every quote you ever sign, on every feed.

There are two verifier interfaces. `QuoteVerifier` authenticates a signed quote
and returns it. `PaidQuoteVerifier` does the same and settles a per-call fee in
the same transaction. You implement them the same way as any other interface,
with an `interface instance` on a template you sign as a party.

```daml
import DataStandard.QuoteVerifierV1

template SignatureVerifier
  with
    oracle    : Party
    publicKey : Text
  where
    signatory oracle

    interface instance QuoteVerifier for SignatureVerifier where
      view = QuoteVerifierView with
        oracle
        publicKey
        hashMethod   = "SHA-256"
        signMethod   = "secp256k1"
        payloadCodec = quoteCodecId
```

The full version, including a key-rotation choice, lives in
[`examples/verifier-producer`](../examples/verifier-producer). The paid sibling
is a separate, token-coupled package,
[`examples/paid-verifier-producer`](../examples/paid-verifier-producer).

The view, field by field:

| Field | Meaning |
|---|---|
| `oracle` | You, the party that signs the quotes and the verifier contract. Becomes the `distributor` of every quote the verifier authenticates, so a consumer trusts an `(oracle, feedId)` pair exactly as it trusts a `(distributor, feedId)` pair on the push side. |
| `publicKey` | Your secp256k1 public key, hex-encoded in DER form. The signature check reads it from the contract, never from the quote, so a consumer cannot substitute a key of its own. Rotating the key means archiving this contract and publishing a replacement. |
| `hashMethod` | The digest the signature commits to, the constant `"SHA-256"`. Advertised for off-ledger tooling; the on-ledger check is fixed by the interface. |
| `signMethod` | The signature scheme, the constant `"secp256k1"`. Advertised the same way. |
| `payloadCodec` | The identifier of the canonical encoding you signed over: `quoteCodecId` (`"v1-quote-concat"`) for the free verifier, `paidQuoteCodecId` (`"v1-paid-quote-concat"`) for the paid one. A consumer reads it to select the matching off-ledger encoder. |

### Signing a quote

The signature is an ECDSA signature over the SHA-256 of a canonical text. The
canonical text is the one thing your off-ledger signer and the on-ledger check
have to agree on byte for byte. The encoding is fixed and defined in the
interface package as `canonicalQuoteText`: the fields `publishedAt`, `expiresAt`,
`quote.feedId`, `quote.price`, and `quote.priceTime`, in that order, each
followed by a `"|"` delimiter, with times rendered as integer milliseconds since
the Unix epoch and the price via the standard `Decimal` rendering. The arity is
fixed and `quote.feedId` is the only free-text field, so the encoding is injective
and reproducible off-ledger as long as your feed ids carry no `"|"`. A feed id is a
short symbol such as `"BTC/USD"`, so this is a constraint your signer enforces, not
a practical limit; the on-ledger check does not reject a feed id that breaks it.

`quote.price` and the paid `cost.fee` are `Decimal`, which is `Numeric 10`. Daml's
`show` renders them at the full scale of ten fractional digits with trailing zeros,
so `65000.0` becomes `65000.0000000000` and `0.5` becomes `0.5000000000`. Your
signer must produce that exact form, rounded to ten decimal places, not a minimized
one. Pin it with a shared test vector between your signer and this encoding.

Your signer reproduces that exact text, hashes it with SHA-256, and signs the
digest with secp256k1, producing a hex-encoded DER signature. On-ledger, the
`secp256k1` builtin SHA-256s its message argument internally, so the check
passes the hex of the canonical text and verifies against your public key.
Producing the off-ledger signer is outside this repository; what the repository
fixes is the encoding and the on-ledger check, so any signer that follows the
same encoding interoperates.

Each signed quote carries an `expiresAt` alongside the quote. That window is the
only replay defence: a captured `(payload, signature)` pair stops verifying once
it lapses, so sign quotes with a validity window matched to how long the price
should stand. There is no on-ledger record of which quotes you have signed, so
expiry is what bounds a leaked signature.

### Charging per call: the paid verifier

`PaidQuoteVerifier` adds a fee to the same flow. You sign the quote together with
a `Cost` (a `fee` amount and the `InstrumentId` it is denominated in) and the
`payee` the fee is paid to, so the price of the call and its recipient are both
covered by your signature: a client cannot be made to pay more, in a different
asset, or to a different party than you signed for. The paid encoding,
`paidCanonicalText`, reuses the free quote prefix verbatim and appends the cost
and the payee, so it is a distinct codec with its own identifier. It carries the
same delimiter constraint as the free encoding, on `quote.feedId` and now also the
instrument `id`: neither may contain `"|"`.

The paid verifier template carries one extra field, the `payee` that the fee is
credited to:

```daml
import DataStandard.PaidQuoteVerifierV1

template PaidSignatureVerifier
  with
    oracle    : Party
    payee     : Party
    publicKey : Text
  where
    signatory oracle

    interface instance PaidQuoteVerifier for PaidSignatureVerifier where
      view = PaidQuoteVerifierView with
        oracle
        payee
        publicKey
        hashMethod   = "SHA-256"
        signMethod   = "secp256k1"
        payloadCodec = paidQuoteCodecId
```

The fee is settled by a single direct Canton Token Standard transfer that the
calling consumer authorizes alone: the consumer is the sender, and the receiver
is the `payee` pinned on your verifier. You sign that same payee into every
payload, and the verifier settles only when the signed payee matches the one it
pins. That match is what stops a substitute verifier from redirecting your fee:
the public key is not a secret, so anyone can publish a verifier that holds it,
but a payload you signed for your own payee will not settle through a verifier
pinning a different one. Pin and sign the same party, which can be a treasury
distinct from the signing oracle. For the transfer to settle in one step the
payee needs standing consent to receive, typically a transfer preapproval
registered with the instrument's registry; the consumer threads that consent
through the registry-supplied context. If the transfer does not complete in one
step, the whole verification aborts, so a consumer never gets an authenticated
quote it has not paid for.

The paid verifier depends on the Canton Token Standard interface DARs in
[`dependencies/`](../dependencies). Reference them from your `daml.yaml` the same
way you reference the standard's DARs. The reference paid producer that puts this
together is [`examples/paid-verifier-producer`](../examples/paid-verifier-producer).

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
