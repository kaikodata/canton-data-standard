# Consumer guide

How to read published data through the standard while staying independent of
every producer's package.

## Depend only on the interface

Your `daml.yaml` takes `data-dependencies` on the standard's DARs and nothing
else from any provider:

```yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.1.0.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.1.0.dar
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

The standard authenticates who published: the `distributor` signed the
contract. Everything else is your workflow's policy.

- Feed identity: verify the payload describes the feed you expect (the
  `assetPair` check above).
- Staleness: bound the age of `publishedAt` for your use case.
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
a data point: confirm `quote.feedId` is the feed you expect, and bound the age
of `publishedAt` for your staleness policy. The standard authenticates the
`distributor`, not the feed identity.

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
  - <path-to>/canton-data-standard-utils-v1-0.1.0.dar
  - <path-to>/canton-data-standard-quote-verifier-v1-0.1.0.dar
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

`QuoteVerifier_Verify` writes nothing to the ledger. It checks the payload has not expired and
that the signature is valid under the verifier's resident public key, then
returns a `VerifiedPayload` you use in the same transaction. A bad signature or
an expired payload aborts the whole transaction, so nothing settles against an
unauthenticated price. Because the choice creates and archives nothing, one
verifier serves every consumer and every quote at once, with no contention.

The `VerifiedPayload` you get back is field-aligned with `PublishedQuoteView`:
its `distributor`, `publishedAt`, and `quote` carry the same meaning, so the code
that reads a verified price is identical to the code that reads a pushed one. The
`distributor` is taken from the verifier, never from the payload, so a quote
cannot claim a producer it was not signed by. It also carries the
`canonicalHash`, `signature`, and `publicKey` as evidence, so the verification
can be reproduced off-ledger later.

The checks that remain yours are the same as before. The standard authenticates
the signer, not the feed, so confirm `quote.feedId` is the feed you expect (the
feed-mismatch check above). The `expiresAt` window is the only replay defence the
standard provides, so for a tighter staleness policy bound the age of
`publishedAt` yourself.

## Reading a pulled quote and paying for it

`PaidQuoteVerifier` is the same flow with a fee attached. You reconstruct a
`PaidSignedPayload`, which is the free payload plus the `Cost` the producer
signed, and you supply `PaymentArgs`: the Canton Token Standard transfer factory
for the fee instrument, the holdings to pay from, and the registry-supplied
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
settles into the same `VerifiedQuoteTradeSettlement` record the free
[`examples/verifier-consumer`](../examples/verifier-consumer) produces.

`PaidQuoteVerifier_VerifyAndPay` authenticates the payload and settles the fee atomically. The fee
amount and the asset come from the `Cost` the producer signed, not from your
arguments, and the recipient is the `payee` pinned on the verifier, not a party
in the payload, so you cannot be charged more than quoted and the payment cannot
be redirected. The transfer is a single direct Canton Token Standard transfer
you authorize as the sender; if it does not settle in one step the whole
verification aborts, so you never receive a verified quote you have not paid for,
and never pay for one that does not verify.

Two things you supply are worth calling out. The `inputHoldingCids` are your own
holdings of the fee instrument; naming specific ones lets you use deliberate
contention to avoid paying twice for the same call. The `context` carries the
receive-side consent the registry needs to settle directly, typically the payee's
standing transfer preapproval, which the payee or its registry sets up out of
band. You obtain the transfer factory contract, and the verifier itself, through
explicit disclosure when you are not a stakeholder of them. The paid path needs
the Canton Token Standard interface DARs from [`dependencies/`](../dependencies)
on your `daml.yaml` alongside the verifier DAR.

## Reading at scale

For querying many feeds across providers, prefer the
[Participant Query Store (PQS)](https://docs.canton.network/sdks-tools/development-tools/pqs)
over repeated active-contract queries. PQS projects and filters by interface
views, so one query covers every `PublishedData` implementation regardless of
producer. On Canton 3.4, use PQS 3.4.3 or later (earlier versions had an
interface-view projection bug). If you consume streams directly instead:
interface views are served on the Transaction Stream and the ACS, not the
Transaction Tree Stream.
