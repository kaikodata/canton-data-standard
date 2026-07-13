# Consumer guide

How to read published data through the standard while staying independent of
every producer's package.

## Depend only on the interface

Your `daml.yaml` takes `data-dependencies` on the standard's DARs and nothing
else from any provider:

```yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.1.1.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.1.1.dar
```

To get the DARs, clone this repository and run `dpm build --all`; they land
in `interfaces/*/.daml/dist/`. CI also attaches them to each run as build
artifacts.

Reference publications as `ContractId PublishedData` (the interface, never a
template), so your code never names a producer's package. That removes one of
the two things that tie a consumer to a provider. The other is the payload
schema: the generic interface does not fix the keys inside `values`. You read
the keys you agreed on with the provider, `assetPair` and `price` below, and
`schemaVersion` identifies that agreement. Switching to another provider that
publishes the same schema is then a decision about which `distributor` party
you trust. A typed interface such as `PublishedQuote` carries named fields in
the view itself, which drops the schema agreement for the feeds it covers (see
below).

## Reading inside your workflow

Read through the interface's `PublishedData_Fetch` choice and extract typed
fields with `lookupField`:

```daml
import DataStandard.DataPointV1
import DataStandard.Utils

choice AcceptTrade : ContractId TradeSettlement
  controller buyer
  do
    v <- exercise priceDataCid PublishedData_Fetch with actor = buyer
    publishedPair <- case (lookupField "assetPair" v.values : Optional Text) of
      Some p -> pure p
      None   -> abort "published data missing field: assetPair"
    assertMsg "asset pair mismatch" (publishedPair == assetPair)
    ...
```

The full version lives in
[`examples/datapoint-consumer`](../examples/datapoint-consumer).

Use the choice, not a plain `fetch`. Daml authorizes a `fetch` only when one
of the fetched contract's stakeholders is in the authorizing set. If you hold
a publication via disclosure (the normal case), you are not a stakeholder,
and a plain `fetch` fails. Exercising `PublishedData_Fetch` is authorized by
you, the `actor`. If your party is a stakeholder, say because the producer
made you an observer, both paths work.

## Getting the contract: explicit disclosure

A publication with no observers is invisible to you until the producer
discloses it: they hand you the contract's `template_id`, `contract_id` and
`created_event_blob` off-ledger, and you attach them to your command
submission (`disclosed_contracts` on the Ledger API;
`submit (actAs you <> disclose d)` in Daml Script). See
[explicit contract disclosure](https://docs.canton.network/appdev/deep-dives/explicit-contract-disclosure).

Disclosure is tamper-evident: a contract id is a hash of the contract's
contents, so a manipulated disclosure fails authentication and you always
read what the distributor signed. It gives no freshness guarantee, though.
Disclosure proves authenticity, not recency, so check `publishedAt` against
your own staleness policy. Producers archive stale publications
(archive-and-replace), which means a stale contract id also fails outright
once refreshed.

## Checks that are yours, not the standard's

The standard authenticates who published: `distributor` is the party that
signed the contract, and it cannot be forged. Whether that party is one you
trust for this feed is still your decision, as is everything else about how you
use the data.

- Distributor identity: confirm `distributor` is a party you trust
  (`distributor == expectedDistributor`). The standard guarantees the field is
  authentic, not that you want data from whoever signed it, and the price
  source is often chosen by your counterparty rather than by you.
- Feed identity: verify the payload describes the feed you expect (the
  `assetPair` check above).
- Staleness: bound the age of `publishedAt` for your use case. The reference
  consumers enforce this with a `maxQuoteAge` gate rather than leaving it to
  prose.
- Schema: handle `None` from `lookupField`, since a field may be absent or
  typed differently than you expect. Gate on `schemaVersion` if you support
  multiple producer schemas.

Unknown `values` fields and unknown `metadata` keys are normal; producers add
them over time. Ignore what you do not understand. That is what keeps old
consumers working.

## Reading a typed quote

When a feed publishes through the `PublishedQuote` interface, the price and feed
id are typed fields on the view, so the payload-schema step disappears. Depend
on the quote interface DAR, reference publications as `ContractId PublishedQuote`,
and read through the `PublishedQuote_Fetch` choice:

```daml
import DataStandard.QuoteV1

choice AcceptQuoteTrade : ContractId QuoteTradeSettlement
  controller buyer
  do
    v <- exercise quoteCid PublishedQuote_Fetch with actor = buyer
    assertMsg "feed mismatch" (v.quote.feedId == feedId)
    ...  -- settle at v.quote.price
```

The full version lives in
[`examples/quote-consumer`](../examples/quote-consumer).

`quote.price` is a typed `Decimal` you read directly, with no `lookupField` and
no `schemaVersion` to gate on. The checks that remain yours are the same as for
a data point: confirm `quote.feedId` is the feed you expect, confirm
`distributor` is a party you trust, and bound the age of `publishedAt` for your
staleness policy. The standard makes `distributor` authentic; it does not decide
whether you trust that party or whether the feed is the one you want.

## Switching providers, and reading several at once

Reading through an interface means your code never names a producer's package.
What ties you to a particular provider is the data you trust: a
`(distributor, feedId)` pair. Gate on both inside your workflow, and switching to
another provider is supplying a different `distributor`. The compiled code does
not change.

```daml
v <- exercise quoteCid PublishedQuote_Fetch with actor = buyer
assertMsg "untrusted distributor" (v.distributor == expectedDistributor)
assertMsg "feed mismatch" (v.quote.feedId == feedId)
...  -- settle at v.quote.price
```

The worked example is
[`examples/switching-consumer`](../examples/switching-consumer), which reads the
same feed from two deliberately different providers:
[`switching-provider-direct`](../examples/switching-provider-direct) stores a
price, and
[`switching-provider-marketmaker`](../examples/switching-provider-marketmaker)
stores a bid and an ask and derives the mid. Both expose the same views, so the
consumer settles against either with no change. On the generic data point path
the two providers must also publish the same payload schema; the consumer reads
the keys it needs and ignores the rest, so the market maker's extra `bid`/`ask`
fields are harmless.

Because every provider exposes the same view, a consumer can read more than one
and require them to agree before acting. The `CrossCheckOffer` in that example
reads two providers in a single transaction and settles only when their prices
fall within a tolerance, pricing the trade at the average. That is N-of-M
agreement across distributors, built from the same interface read.

## Reading a pulled, signed quote

The interfaces above read a quote the producer pushed onto the ledger as a
contract. The verifier interfaces read a quote the producer signed off-ledger
and you pulled in: you obtain the signed bytes through the producer's own channel
and authenticate them on demand. There is no contract per quote. The producer
publishes one long-lived verifier contract holding its public key, and you
verify any number of pulled quotes against it.

Depend on the verifier interface DAR, and reference the verifier as
`ContractId QuoteVerifier`, the interface, never a producer's template:

```yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.1.1.dar
  - <path-to>/canton-data-standard-quote-verifier-v1-0.1.1.dar
```

You obtain the verifier contract through explicit disclosure, the same as any
contract you are not a stakeholder of, and you reconstruct the signed quote into
a `SignedPayload`: the `publishedAt`, the `expiresAt` the producer signed, and
the `quote` itself. The signature travels beside it, not inside it. You hand both
to the `QuoteVerifier_Verify` choice:

```daml
import DataStandard.QuoteVerifierV1

choice AcceptVerifiedQuoteTrade : ContractId VerifiedQuoteTradeSettlement
  with
    payload   : SignedPayload
    signature : Text
  controller buyer
  do
    v <- exercise verifierCid QuoteVerifier_Verify with actor = buyer, payload, signature
    assertMsg "feed mismatch" (v.quote.feedId == feedId)
    ...  -- settle at v.quote.price
```

The full version lives in
[`examples/verifier-consumer`](../examples/verifier-consumer).

`QuoteVerifier_Verify` checks the payload has not expired and that the signature
is valid under the verifier's resident public key, then returns a
`VerifiedPayload` you use in the same transaction. A bad signature or an expired
payload aborts the whole transaction, so nothing settles against an
unauthenticated price. On success the choice also writes one producer-signed
`AuditRecord` (see [the audit record](#the-audit-record-every-verify-writes)).
It never archives or mutates the verifier itself, so one verifier serves every
consumer and every quote at once, with no contention.

The `VerifiedPayload` you get back is field-aligned with `PublishedQuoteView`:
its `distributor`, `publishedAt`, and `quote` carry the same meaning, so the code
that reads a verified price is identical to the code that reads a pushed one. The
`distributor` is taken from the verifier, never from the payload, so a quote
cannot claim a producer it was not signed by. It also carries the
`canonicalHash`, `signature`, and `publicKey` as evidence, so the verification
can be reproduced off-ledger later.

The checks that remain yours are the same as before. The standard authenticates
the signer, not the feed, so confirm `quote.feedId` is the feed you expect (the
feed-mismatch check above) and confirm `distributor` is a party you trust before
settling against its price. The `expiresAt` window is the only replay defence the
standard provides, so for a tighter staleness policy bound the age of
`publishedAt` yourself.

## The audit record every verify writes

Every successful verification, on all four verifier interfaces, creates one
`AuditRecord` contract in the same transaction: the standard's durable receipt
that the verification happened. The producer signs it and you, the verifying
party, observe it, so it appears in your active contracts and in your PQS with
no extra step. It carries the full evidence the verify returned (the validity
window, `canonicalHash`, `signature`, `publicKey`, and the verified quote or
data point; the paid variants add the settled fee, instrument, and payee), so an
auditor can re-check the signature off-ledger from the record alone. A party
that is not a stakeholder reads a disclosed record through its
`AuditRecord_Fetch` choice.

Two things follow from the signatory model. The producer controls the record's
lifetime: it can archive its audit records at any time, to prune old history for
instance, and needs no consent from you. So treat the record as the producer's
receipt, not as your evidence store, and keep the fields you may need later on
your own contracts, as the reference consumers do. And never link to an audit
record by contract id, since archival invalidates ids; when one of your records
must reference a verification, bind on `canonicalHash`, which pins the exact
signed payload.

## Reading a pulled quote and paying for it

`PaidQuoteVerifier` is the same flow with a fee attached. You reconstruct a
`PaidSignedPayload`, which is the free payload plus the `Cost` and the `payee` the
producer signed, and you supply `PaymentArgs`: the Canton Token Standard transfer
factory for the fee instrument, the holdings to pay from, and the registry-supplied
context. You hand all of it to `PaidQuoteVerifier_VerifyAndPay`:

```daml
import DataStandard.PaidQuoteVerifierV1

choice AcceptPaidVerifiedQuoteTrade : ContractId VerifiedQuoteTradeSettlement
  with
    payload   : PaidSignedPayload
    signature : Text
    payment   : PaymentArgs
  controller buyer
  do
    v <- exercise verifierCid PaidQuoteVerifier_VerifyAndPay with
      actor = buyer, payload, signature, payment
    assertMsg "feed mismatch" (v.quote.feedId == feedId)
    ...  -- settle at v.quote.price
```

The full version lives in
[`examples/paid-verifier-consumer`](../examples/paid-verifier-consumer); it
settles into its own `PaidVerifiedQuoteTradeSettlement` record, which extends
the free settlement with the fee, instrument, and payee that settled. The
`AuditRecord` this path writes carries the settled payment too.

`PaidQuoteVerifier_VerifyAndPay` authenticates the payload and settles the fee atomically. The fee
amount and the asset come from the `Cost` the producer signed, not from your
arguments, and the recipient is the `payee` pinned on the verifier. The producer
also signs that payee into the payload, and the call settles only when the two
match, so you cannot be charged more than quoted and the fee cannot be redirected,
not even through a substitute verifier that holds the producer's public key. The
transfer is a single direct Canton Token Standard transfer you authorize as the
sender, and the verification and the payment abort together, so you never pay for
a quote that does not verify.

Two things you supply are worth calling out. The `inputHoldingCids` are your own
holdings of the fee instrument; naming specific ones lets you use deliberate
contention to avoid paying twice for the same call. The `context` carries the
receive-side consent the registry needs to settle directly, typically the payee's
standing transfer preapproval, which the payee or its registry sets up out of
band. You obtain the transfer factory contract, and the verifier itself, through
explicit disclosure when you are not a stakeholder of them. The paid path needs
the Canton Token Standard interface DARs from [`dependencies/`](../dependencies)
on your `daml.yaml` alongside the verifier DAR.

## Reading a pulled, signed data point

The verifier pair for the generic data point reads exactly like the quote pair,
with one difference in the checks. Depend on the datapoint-verifier interface
DAR, and reference the verifier as `ContractId DataPointVerifier`, the interface,
never a producer's template:

```yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.1.1.dar
  - <path-to>/canton-data-standard-datapoint-verifier-v1-0.1.1.dar
```

You obtain the verifier contract through explicit disclosure, reconstruct the
signed data point into a `SignedDataPoint` (the `publishedAt`, the `expiresAt` the
producer signed, the `schemaVersion`, and the `values` payload), and hand it with
the signature to the `DataPointVerifier_Verify` choice:

```daml
import DataStandard.DataPointVerifierV1
import DataStandard.Utils (lookupField)

choice AcceptVerifiedDataPoint : ContractId RecordedRate
  with
    payload   : SignedDataPoint
    signature : Text
  controller subscriber
  do
    v <- exercise verifierCid DataPointVerifier_Verify with
      actor = subscriber, payload, signature
    assertMsg "untrusted distributor" (v.distributor == expectedDistributor)
    assertMsg "unexpected schema version" (v.schemaVersion == expectedSchemaVersion)
    feedId <- case lookupField "feedId" v.values of
      Some f -> pure (f : Text)
      None   -> abort "payload missing feedId field"
    assertMsg "feed mismatch" (feedId == expectedFeedId)
    ...  -- record the rate read from v.values
```

The full version lives in
[`examples/datapoint-verifier-consumer`](../examples/datapoint-verifier-consumer),
a `RateSubscription` that records a verified rate as a `RecordedRate`.

`DataPointVerifier_Verify` checks the payload has not expired and that the
signature is valid under the verifier's resident public key, then returns a
`VerifiedDataPoint` you use in the same transaction. A bad signature or an
expired payload aborts the whole transaction, so nothing settles against an
unauthenticated data point. On success the choice also writes one
producer-signed `AuditRecord`, exactly as on the quote path. It never archives
or mutates the verifier itself, so one verifier serves every consumer and every
data point at once.

The `VerifiedDataPoint` is field-aligned with `PublishedDataView` on
`distributor`, `publishedAt`, `schemaVersion`, and `values`, so the code that
reads a verified data point is the code that reads a pushed one. The `distributor`
is taken from the verifier, never from the payload, so a data point cannot claim a
producer it was not signed by. It also carries the `canonicalHash`, `signature`,
and `publicKey` as evidence, so the verification can be reproduced off-ledger
later.

The checks that remain yours differ from the quote case in one way: a data point
has no top-level feed id. A quote carries `quote.feedId` on the view; a data
point's feed identity lives inside `values`. So your identity gate is
schema-aware. Confirm `distributor == expectedDistributor` (the field is
authenticated, but you still choose whom to trust). Confirm `schemaVersion`
matches what you expect, since it tells you how to read `values`. Then read a
known identifier field out of `values` with `lookupField`, a `"feedId"` key for
example, and check it. As with a quote, bound the age of `publishedAt` for
staleness, and reject a future-dated `publishedAt`. The `expiresAt` window is the
only replay defence the standard provides.

### Reading a pulled data point and paying for it

`PaidDataPointVerifier` is the same flow with a fee attached. You reconstruct a
`PaidSignedDataPoint`, which is the free payload plus the `Cost` and the `payee`
the producer signed, and you supply `PaymentArgs`: the Canton Token Standard
transfer factory for the fee instrument, the holdings to pay from, and the
registry-supplied context. You hand all of it to
`PaidDataPointVerifier_VerifyAndPay`:

```daml
import DataStandard.PaidDataPointVerifierV1
import DataStandard.Utils (lookupField)

choice AcceptPaidVerifiedDataPoint : ContractId RecordedRate
  with
    payload   : PaidSignedDataPoint
    signature : Text
    payment   : PaymentArgs
  controller subscriber
  do
    v <- exercise verifierCid PaidDataPointVerifier_VerifyAndPay with
      actor = subscriber, payload, signature, payment
    assertMsg "untrusted distributor" (v.distributor == expectedDistributor)
    assertMsg "unexpected schema version" (v.schemaVersion == expectedSchemaVersion)
    feedId <- case lookupField "feedId" v.values of
      Some f -> pure (f : Text)
      None   -> abort "payload missing feedId field"
    assertMsg "feed mismatch" (feedId == expectedFeedId)
    ...  -- record the rate read from v.values
```

The full version lives in
[`examples/paid-datapoint-verifier-consumer`](../examples/paid-datapoint-verifier-consumer),
a `PaidRateSubscription` that records into its own `PaidRecordedRate` record,
which extends the free `RecordedRate` with the fee, instrument, and payee that
settled. The `AuditRecord` this path writes carries the settled payment too.

`PaidDataPointVerifier_VerifyAndPay` authenticates the payload and settles the fee
atomically. The fee amount and the asset come from the `Cost` the producer signed,
not from your arguments, and the recipient is the `payee` pinned on the verifier.
The producer also signs that payee into the payload, and the call settles only
when the two match, so you cannot be charged more than quoted and the fee cannot
be redirected, not even through a substitute verifier that holds the producer's
public key. The transfer is a single direct Canton Token Standard transfer you
authorize as the sender, and the verification and the payment abort together, so
you never pay for a data point that does not verify. The same two arguments are
worth calling out as on the paid quote: `inputHoldingCids` are your own holdings
of the fee instrument, and naming specific ones lets you use deliberate contention
to avoid paying twice for the same call; `context` carries the receive-side
consent the registry needs to settle directly, typically the payee's standing
transfer preapproval. You obtain the transfer factory and the verifier through
explicit disclosure when you are not a stakeholder of them, and the paid path
needs the Canton Token Standard interface DARs from
[`dependencies/`](../dependencies) on your `daml.yaml` alongside the verifier DAR.

## Reading at scale

For querying many feeds across providers, prefer the
[Participant Query Store (PQS)](https://docs.canton.network/sdks-tools/development-tools/pqs)
over repeated active-contract queries. PQS projects and filters by interface
views, so one query covers every `PublishedData` implementation regardless of
producer. On Canton 3.4, use PQS 3.4.3 or later (earlier versions had an
interface-view projection bug). If you consume streams directly instead:
interface views are served on the Transaction Stream and the ACS, not the
Transaction Tree Stream.
