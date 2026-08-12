# Consumer guide

How to read published data through the standard while staying independent of
every producer's package.

## Depend only on the interface

Your `daml.yaml` takes `data-dependencies` on the standard's DARs and nothing
else from any distributor:

```yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.2.0.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.2.0.dar
```

To get the DARs, clone this repository and run `dpm build --all`; they land
in `interfaces/*/.daml/dist/`. CI also attaches them to each run as build
artifacts.

Reference publications as `ContractId PublishedDataPoint` (the interface, never a
template), so your code never names a producer's package. That removes one of
the two things that tie a consumer to a distributor. The other is the payload
schema: the generic interface does not fix the keys inside `values`. You read
the keys you agreed on with the distributor, `assetPair` and `price` below, and
`schemaVersion` identifies that agreement. Switching to another distributor that
publishes the same schema is then a decision about which `distributor` party
you trust. A typed interface such as `PublishedQuote` has named fields in the
view itself, which drops the schema agreement for the feeds it covers (see
below).

## Reading inside your workflow

Read through the interface's `PublishedDataPoint_Fetch` choice and extract typed
fields with `lookupField`:

```daml
import DataStandard.DataPointV1
import DataStandard.Utils

choice AcceptTrade : ContractId TradeSettlement
  controller buyer
  do
    v <- exercise priceDataCid PublishedDataPoint_Fetch with actor = buyer
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
and a plain `fetch` fails. Exercising `PublishedDataPoint_Fetch` is authorized by
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
read what the distributor signed. What it does not give you is recency, so
check `publishedAt` against your own staleness policy. Producers archive stale
publications (archive-and-replace), which means a stale contract id also fails
outright once refreshed.

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
  consumers enforce this with a `maxQuoteAge` gate instead of leaving it to
  prose.
- Schema: handle `None` from `lookupField`, since a field may be absent or
  typed differently than you expect. Gate on `schemaVersion` if you support
  multiple producer schemas.

Unknown `values` fields and unknown `metadata` keys are normal; producers add
them over time. Ignoring what you do not understand is what keeps an old
consumer working against a newer producer.

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
staleness policy.

## Switching distributors, and reading several at once

Reading through an interface means your code never names a producer's package.
What ties you to a particular distributor is the data you trust: a
`(distributor, feedId)` pair. Gate on both inside your workflow, and switching to
another distributor is supplying a different `distributor`. The compiled code does
not change.

```daml
v <- exercise quoteCid PublishedQuote_Fetch with actor = buyer
assertMsg "untrusted distributor" (v.distributor == expectedDistributor)
assertMsg "feed mismatch" (v.quote.feedId == feedId)
...  -- settle at v.quote.price
```

The worked example is
[`examples/switching-consumer`](../examples/switching-consumer), which reads the
same feed from two deliberately different distributors:
[`switching-distributor-direct`](../examples/switching-distributor-direct) stores a
price, and
[`switching-distributor-marketmaker`](../examples/switching-distributor-marketmaker)
stores a bid and an ask and derives the mid. Both expose the same views, so the
consumer settles against either with no change. On the generic data point path
the two distributors must also publish the same payload schema; the consumer reads
the keys it needs and ignores the rest, so the market maker's extra `bid`/`ask`
fields are harmless.

Because every distributor exposes the same view, a consumer can read more than one
and require them to agree before acting. The `CrossCheckOffer` in that example
reads two distributors in a single transaction and settles only when their prices
fall within a tolerance, pricing the trade at the average. That gives you N-of-M
agreement across distributors out of the same interface read.

## Reading pulled, signed data

The interfaces above read data the distributor pushed onto the ledger as
contracts. The pull path reads data the distributor signed off-ledger: you
obtain the signed bytes through the distributor's own channel and authenticate
them on demand, in your own choice, through the
`canton-data-standard-codecs` library. There is no contract per payload and no
verifier interface. The distributor publishes one long-lived `DistributorKey`
contract holding its public key and the codec id its signatures cover, and you
verify any number of pulled payloads against it.

The shape you receive is a `SignedQuote` or `SignedDataPoint` record (from
`utils-v1`) plus a signature. In your choice, fetch the disclosed key via
`DistributorKey_Fetch`, check the distributor is one you trust, and call the
library:

```daml
now <- getTime
kv  <- exercise keyCid DistributorKey_Fetch with actor = reader
assertMsg "untrusted distributor" (kv.distributor == expectedDistributor)
case verifyQuote kv now payload signature of
  Left err -> abort err
  Right v  -> -- v : VerifiedQuote, with the typed quote and the evidence
              -- triple (canonicalHash, signature, publicKey)
```

`verifyQuote` checks the publication window (`published after expiry`,
`payload expired`), the advertised codec id, and the secp256k1 signature over
the structural hash of the payload, and returns the typed `VerifiedQuote`.
`verifyDataPoint` is the generic sibling. Your own checks (feed, staleness,
price bounds) stay yours, exactly as on the push path. Calling the library
needs no crypto build flag in your package. See
[`examples/distributor-key-consumer`](../examples/distributor-key-consumer)
for the complete workflow.

Paying for pulled data, and durable verification receipts, are outside the
standard: they are product features of the distributor you buy from, settled
and recorded by choices on the distributor's own template. The evidence triple
in the verify result is what such receipts pin.

## Reading at scale

For querying many feeds across distributors, prefer the
[Participant Query Store (PQS)](https://docs.canton.network/sdks-tools/development-tools/pqs)
over repeated active-contract queries. PQS projects and filters by interface
views, so one query covers every `PublishedDataPoint` implementation regardless of
producer. On Canton 3.4, use PQS 3.4.3 or later (earlier versions had an
interface-view projection bug). If you consume streams directly instead:
interface views are served on the Transaction Stream and the ACS, not the
Transaction Tree Stream.
