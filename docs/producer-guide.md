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
  - <path-to>/canton-data-standard-utils-v1-0.1.1.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.1.1.dar
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

Both delivery paths carry the full value set, nested lists and maps included.
The contract-based (push) path relies on the ledger to serialize the payload.
The signature-based (pull) path signs the same `AnyValue` tree under the
`v1-datapoint-tlv` canonical encoding that `DataPointVerifier` defines, a
recursive, length-prefixed encoding described in [Distributing a signed data
point](#distributing-a-signed-data-point-the-datapoint-verifier-interfaces)
below.

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
contract. You publish nothing per quote ahead of use; the one per-quote write is
the producer-signed `AuditRecord` each successful verification creates inside
the consumer's transaction (see [Audit records](#audit-records)). The verifier
contract itself is reused for every quote you ever sign, on every feed.

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
short symbol such as `"BTC/USD"`, so this is rarely a practical limit; the verifier
also enforces it on-ledger, rejecting any `feedId` that contains `"|"` (and, on the
paid path, any instrument `id` that does) before it checks the signature, so a
violating payload fails fast rather than verifying ambiguously.

`quote.price` and the paid `cost.fee` are `Decimal`, which is `Numeric 10`. Daml's
`show` renders a `Decimal` in its shortest exact form, with at least one fractional
digit and no trailing zeros, and a leading `"-"` for negatives: `65000.0` renders as
`"65000.0"`, `0.5` as `"0.5"`, and `-12.5` as `"-12.5"`. Your signer must produce
that exact form, not a fixed-scale one padded to ten places. Pin it with a shared
test vector between your signer and this encoding.

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
instrument `id`: neither may contain `"|"`, and `PaidQuoteVerifier_VerifyAndPay`
rejects a payload that breaks either on-ledger.

The paid suffix appends four fields after the free quote prefix, in this fixed
order, each followed by a `"|"` delimiter: `cost.fee` (a `Decimal`, rendered in
the same shortest exact form as `quote.price`), `cost.instrument.admin`,
`cost.instrument.id`, and the `payee`. The two `Party` fields,
`cost.instrument.admin` and `payee`, are rendered with `partyToText`, which emits
the fully-qualified party id (`<hint>::<fingerprint>`), not the bare hint, so your
off-ledger signer must reproduce that exact form. The paid codec id is
`paidQuoteCodecId` (`"v1-paid-quote-concat"`).

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
through the registry-supplied context. If the transfer does not report completion in one
step, the whole verification aborts. The factory that moves the fee is supplied
by the consumer, so the standard cannot prove on-ledger that the fee genuinely
moved: a consumer set on skipping the fee is resisted by the deployment vetting
only honest Token Standard implementations, the trust the Token Standard itself
places in its factory. Redirection, by contrast, is prevented on-ledger by the
payee binding.

The paid verifier depends on the Canton Token Standard interface DARs in
[`dependencies/`](../dependencies). Reference them from your `daml.yaml` the same
way you reference the standard's DARs. The reference paid producer that puts this
together is [`examples/paid-verifier-producer`](../examples/paid-verifier-producer).

## Distributing a signed data point: the DataPoint verifier interfaces

The verifier interfaces above carry a typed quote. For the generic data point
there is a matching pair, `DataPointVerifier` and `PaidDataPointVerifier`. They
work the same way: you sign the data point off-ledger with an ECDSA key, hand the
signed bytes to consumers through your own channel, and publish one on-ledger
contract that holds your public key. A consumer pulls a signed data point and
authenticates it against that contract through a nonconsuming choice that records
each successful verification as a producer-signed `AuditRecord` and never mutates
the verifier, so one verifier serves every data point you ever sign, on every
feed and schema.

You implement them the same way, with an `interface instance` on a template you
sign as a party:

```daml
import DataStandard.DataPointVerifierV1

template DataPointSignatureVerifier
  with
    oracle    : Party
    publicKey : Text
  where
    signatory oracle

    interface instance DataPointVerifier for DataPointSignatureVerifier where
      view = DataPointVerifierView with
        oracle
        publicKey
        hashMethod   = "SHA-256"
        signMethod   = "secp256k1"
        payloadCodec = dataPointCodecId
```

The full version, with a key-rotation choice, lives in
[`examples/datapoint-verifier-producer`](../examples/datapoint-verifier-producer).
The paid sibling is a separate, token-coupled package,
[`examples/paid-datapoint-verifier-producer`](../examples/paid-datapoint-verifier-producer).

The view, field by field:

| Field | Meaning |
|---|---|
| `oracle` | You, the party that signs the data points and the verifier contract. Becomes the `distributor` of every data point the verifier authenticates, taken from this field and never from the payload. |
| `publicKey` | Your secp256k1 public key, hex-encoded in DER form. The signature check reads it from the contract, never from the payload, so a consumer cannot substitute a key of its own. Rotating the key means archiving this contract and publishing a replacement. |
| `hashMethod` | The digest the signature commits to, the constant `"SHA-256"`. Advertised for off-ledger tooling; the on-ledger check is fixed by the interface. |
| `signMethod` | The signature scheme, the constant `"secp256k1"`. Advertised the same way. |
| `payloadCodec` | The identifier of the canonical encoding you signed over: `dataPointCodecId` (`"v1-datapoint-tlv"`) for the free verifier, `paidDataPointCodecId` (`"v1-paid-datapoint-tlv"`) for the paid one. A consumer reads it to select the matching off-ledger encoder. |

The signed field set is `publishedAt`, `expiresAt`, `schemaVersion`, and `values`.
`schemaVersion` is signed, so a consumer can trust it to interpret `values`. The
data point has no `metadata` in the signed bytes or in the result: metadata is an
unsigned envelope annotation, dropped here exactly as it is on the quote side.

### Signing a data point

The signature is an ECDSA signature over the SHA-256 of a canonical encoding of
the signed fields. Unlike the quote codec, which is a flat delimited text, the
data point codec is recursive: a data point's `values` is an open tree of nested
lists and maps, so the encoding is a length-prefixed, type-tagged TLV. It is
defined in the interface package as `canonicalDataPointEncode`, and it is
validated against Canton's own external-signing HashingSchemeV2. Treat the
encoder source as the normative spec, alongside the golden vectors in
[`tests-crypto/daml/Test/DataPointVerifierV1Test.daml`](../tests-crypto/daml/Test/DataPointVerifierV1Test.daml),
which assert byte-exact expected output. An off-ledger signer reproduces the
bytes from those, not from a prose table that would drift from the source.

What an off-ledger signer needs to match, byte for byte:

- The whole encoding is hex. Each value carries a one-byte type tag followed by
  its body. Lengths and collection counts are fixed-width 4-byte big-endian.
- Map keys are emitted in ascending order, sorted by raw UTF-8 byte order, which
  equals Unicode code-point order: shorter prefix first, no locale collation, no
  UTF-16 ordering, no NFC normalization. An off-ledger signer reproduces it by
  sorting the UTF-8 bytes of the keys.
- Times are integer milliseconds since the Unix epoch, never microseconds and
  never sub-millisecond.
- A `Decimal` (`Numeric 10`) is rendered by Daml's `show` in its shortest exact
  form, with at least one fractional digit, no trailing zeros, and a leading
  `"-"` for negatives: `65000.0` renders as `"65000.0"`, `0.5` as `"0.5"`, `-12.5`
  as `"-12.5"`. An off-ledger signer must reproduce that exact form.
- Every variable-length field is length-prefixed, so free text never shifts a
  field boundary. Unlike the quote codec there are no reserved-delimiter guards:
  a `feedId`, an instrument id, or any text value may contain any character.
- There is no version or domain prefix inside the signed bytes.

Your signer reproduces those bytes, hashes them with SHA-256, and signs the
digest with secp256k1, producing a hex-encoded DER signature. On-ledger, the
`secp256k1` builtin SHA-256s its message argument internally, and since the
canonical encoding is already hex, the check passes that hex straight in and
verifies against your public key. Producing the off-ledger signer is outside this
repository; what the repository fixes is the encoding and the on-ledger check, so
any signer that follows the same encoding interoperates.

Each signed data point carries an `expiresAt` alongside the payload. That window
is the only replay defence: a captured `(payload, signature)` pair stops verifying
once it lapses, so sign data points with a validity window matched to how long the
value should stand. There is no on-ledger record of which data points you have
signed, so expiry is what bounds a leaked signature.

### Charging per call: the paid data point verifier

`PaidDataPointVerifier` adds a fee to the same flow. You sign the data point
together with a `Cost` (a `fee` amount and the `InstrumentId` it is denominated
in) and the `payee` the fee is paid to, so the price of the call and its recipient
are both covered by your signature: a client cannot be made to pay more, in a
different asset, or to a different party than you signed for. The paid encoding,
`paidDataPointCanonicalEncode`, reuses the free TLV verbatim and appends the cost
and the payee, each length-prefixed: the fee as the same shortest-form decimal
text, the instrument admin via `partyToText`, the instrument id, then the payee
via `partyToText`. It is a distinct codec with its own identifier,
`paidDataPointCodecId` (`"v1-paid-datapoint-tlv"`). Because every field is
length-prefixed, the paid suffix needs no delimiter guard either.

The paid verifier template carries one extra field, the `payee` the fee is
credited to:

```daml
import DataStandard.PaidDataPointVerifierV1

template PaidDataPointSignatureVerifier
  with
    oracle    : Party
    payee     : Party
    publicKey : Text
  where
    signatory oracle

    interface instance PaidDataPointVerifier for PaidDataPointSignatureVerifier where
      view = PaidDataPointVerifierView with
        oracle
        payee
        publicKey
        hashMethod   = "SHA-256"
        signMethod   = "secp256k1"
        payloadCodec = paidDataPointCodecId
```

The fee settles exactly as it does for the paid quote verifier: one direct Canton
Token Standard transfer the calling consumer authorizes alone, from the consumer
as sender to the `payee` pinned on your verifier. You sign that same payee into
every payload, and `PaidDataPointVerifier_VerifyAndPay` settles only when the
signed payee matches the pinned one. That cross-check is what stops a substitute
verifier from redirecting your fee: the public key is not a secret, so anyone can
publish a verifier that holds it, but a payload you signed for your own payee will
not settle through a verifier pinning a different one. The `cost` is signed too,
so the fee and the instrument cannot be altered. Settlement integrity against a
counterfeit factory rests on package vetting: the choice confirms the transfer
reports completion with a non-empty set of credited holdings, it does not prove
funds moved, the same trust model the Token Standard states for its own transfer.
Pin and sign the same party, which can be a treasury distinct from the signing
oracle.

The paid data point verifier depends on the Canton Token Standard interface DARs
in [`dependencies/`](../dependencies), referenced from your `daml.yaml` the same
way as the standard's DARs. The reference paid producer is
[`examples/paid-datapoint-verifier-producer`](../examples/paid-datapoint-verifier-producer).

## Audit records

Every successful verification through any of the four verifier interfaces
creates one `AuditRecord` contract, signed by you and observed by the verifying
party, inside the consumer's own transaction. Your authority for that create
comes from the verifier contract you signed; you submit nothing per call. The
record carries the verified payload and the evidence needed to re-check the
signature off-ledger; the paid variants add the fee, instrument, and payee that
settled.

Because you sign every record, your participant hosts all of them, and they
accumulate at one per verification. You are the only signatory, so you can
archive them at any time; pruning old records is a routine batch job over your
own contracts. If a data-licensing agreement obliges you to retain usage
history, rely on PQS rather than the active contract set: archived records stay
in PQS history, so you can prune the ledger and keep the trail. For billing
reconciliation, a paid audit record and the fee transfer that paid for it always
share one transaction, so joining them in PQS is a same-transaction lookup, and
`canonicalHash` pins the exact payload a record attests to.

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
