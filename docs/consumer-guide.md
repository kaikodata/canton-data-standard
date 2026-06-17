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

## Reading at scale

For querying many feeds across providers, prefer the
[Participant Query Store (PQS)](https://docs.canton.network/sdks-tools/development-tools/pqs)
over repeated active-contract queries. PQS projects and filters by interface
views, so one query covers every `PublishedData` implementation regardless of
producer. On Canton 3.4, use PQS 3.4.3 or later (earlier versions had an
interface-view projection bug). If you consume streams directly instead:
interface views are served on the Transaction Stream and the ACS, not the
Transaction Tree Stream.
