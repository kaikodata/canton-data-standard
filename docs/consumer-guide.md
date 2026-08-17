# Consumer guide

How to read published data through the standard while staying independent of
every distributor's package.

## Depend only on the interface

Your `daml.yaml` takes `data-dependencies` on the standard's DARs and nothing
from any distributor:

```yaml
data-dependencies:
  - <path-to>/canton-data-standard-utils-v1-0.2.0.dar
  - <path-to>/canton-data-standard-datapoint-v1-0.2.0.dar
```

Take the DARs from [`dars/`](../dars) or from a tagged release, or build them
with `dpm build --all`.

Reference publications as `ContractId PublishedDataPoint` — the interface,
never a template — so your code never names a distributor's package. What
remains is the payload schema: the generic interface does not fix the keys
inside `values`, so you read the keys you agreed on with the distributor and
`schemaVersion` identifies that agreement. Switching to another distributor
publishing the same schema is then a decision about which `distributor` party
you trust. `PublishedQuote` has named fields in the view and drops the schema
agreement for the feeds it covers.

## Reading inside your workflow

Read through the interface's `_Fetch` choice and extract typed fields with
`lookupField`:

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

The full consumer is [`examples/datapoint-consumer`](../examples/datapoint-consumer).

Use the choice, not a plain `fetch`. Daml authorizes a `fetch` only when one of
the fetched contract's stakeholders is in the authorizing set; if you hold a
publication by disclosure you are not a stakeholder, and the `fetch` fails.
`PublishedDataPoint_Fetch` is authorized by you, its `actor`. Both paths work
if you are an observer.

## Getting the contract

A publication is visible to you in one of two ways, and the difference decides
what else you can do with it.

**Explicit disclosure.** The distributor hands you the contract's
`template_id`, `contract_id` and `created_event_blob` off-ledger, and you
attach them to your command submission (`disclosed_contracts` on the Ledger
API, `submit (actAs you <> disclose d)` in Daml Script). See
[explicit contract disclosure](https://docs.canton.network/appdev/deep-dives/explicit-contract-disclosure).
Disclosure is tamper-evident, since a contract id is a hash of the contract's
contents. It does not make you a stakeholder: the contract is not in your
participant's active contract set and you cannot query for it, only use ids the
distributor gives you.

**Observer.** The distributor names your party as an observer. You are then a
stakeholder, the contract lands on your participant, and you can query for it
and `fetch` it directly. This costs the distributor storage and streaming per
observer, so it is offered for small, known audiences rather than by default.

Neither gives you recency, so check `publishedAt` against your own staleness
policy. Distributors archive stale publications on refresh, so a stale contract
id also fails outright.

## Checks that are yours, not the standard's

The standard authenticates who published: `distributor` is the party that
signed the contract and cannot be forged. Everything else is your decision.

- **Distributor identity.** Confirm `distributor` is a party you trust for this
  feed. The field is authentic, but the publication is often chosen by your
  counterparty rather than by you.
- **Feed identity.** Verify the payload describes the feed you expect.
- **Staleness.** Bound the age of `publishedAt`. The reference consumers do
  this with a `maxQuoteAge` gate rather than leaving it to prose.
- **Schema.** Handle `None` from `lookupField`, and gate on `schemaVersion` if
  you support several distributor schemas.

Unknown `values` fields and unknown `metadata` keys are normal; ignoring what
you do not understand is what keeps an old consumer working against a newer
distributor.

## Reading a typed quote

With `PublishedQuote` the price and feed id are typed fields on the view, so
the payload-schema step disappears. Depend on the quote interface DAR,
reference publications as `ContractId PublishedQuote`, and read through
`PublishedQuote_Fetch`:

```daml
v <- exercise quoteCid PublishedQuote_Fetch with actor = buyer
assertMsg "feed mismatch" (v.quote.feedId == feedId)
...  -- settle at v.quote.price
```

`quote.price` is a `Decimal` you read directly, with no `lookupField` and no
`schemaVersion` to gate on. The checks above still apply. The full consumer is
[`examples/quote-consumer`](../examples/quote-consumer).

## Switching distributors, and reading several at once

Reading through an interface means your code never names a distributor's
package. What ties you to a distributor is the data you trust: a
`(distributor, feedId)` pair. Gate on both inside your workflow, and switching
is supplying a different `distributor`. The compiled code does not change.

```daml
v <- exercise quoteCid PublishedQuote_Fetch with actor = buyer
assertMsg "untrusted distributor" (v.distributor == expectedDistributor)
assertMsg "feed mismatch" (v.quote.feedId == feedId)
```

[`examples/switching-consumer`](../examples/switching-consumer) reads the same
feed from two deliberately different distributors — one storing a price, one
storing a bid and an ask and deriving the mid — and settles against either
unchanged, ignoring the extra `bid`/`ask` fields on the generic path. Its
`CrossCheckOffer` goes further and reads two distributors in one transaction,
settling only when their prices agree within a tolerance: N-of-M agreement out
of the same interface read.

## Reading pulled, signed data

The pull path reads data the distributor signed off-ledger: you obtain the
signed payload through its own channel and authenticate it on demand, in your
own choice, through `canton-data-standard-codecs`. There is no contract per
payload and no verifier interface — one long-lived `DistributorKey` contract
authenticates any number of payloads.

Take `data-dependencies` on the `canton-data-standard-distributor-key-v1` and
`canton-data-standard-codecs` DARs alongside `utils-v1`. You receive a
`SignedQuote` or `SignedDataPoint` record plus a signature; read the disclosed
key through `DistributorKey_Fetch`, check the distributor is one you trust, and
call the library:

```daml
now <- getTime
kv  <- exercise keyCid DistributorKey_Fetch with actor = reader
assertMsg "untrusted distributor" (kv.distributor == expectedDistributor)
case verifyQuote kv now payload signature of
  Left err -> abort err
  Right v  -> ...  -- v : VerifiedQuote
```

`verifyQuote` checks the key's advertised codec id, the signed validity window
(`"published after expiry"`, `"payload expired"`) and the secp256k1 signature
over the payload's structural hash, then returns a `VerifiedQuote`: the typed
quote plus the evidence triple `canonicalHash`/`signature`/`publicKey`.
`verifyDataPoint` is the generic sibling. Both take the verified `distributor`
from the key's view rather than from the payload, and both return `Either Text`,
so you decide whether a failure aborts the transaction. Verification runs inside
your transaction and every validating participant re-executes it, exactly as it
would an interface choice — but as library code in an upgradable package, a
defect in it is fixable.

Your own checks — feed, staleness, price bounds — stay yours, as on the push
path; `expiresAt` is the standard's only replay bound, so apply a tighter policy
on top. Calling the library needs no crypto build flag in your package. The full
consumer is
[`examples/distributor-key-consumer`](../examples/distributor-key-consumer).

Paying for pulled data and durable verification receipts are product features of
the distributor you buy from, not part of the standard. The evidence triple is
what such a receipt pins, with `canonicalHash` as the join key — a contract id
will not do, since refreshing a publication changes it.

## Reading at scale

Which reads scale depends on visibility, not on the interfaces.

A query store such as the
[Participant Query Store (PQS)](https://docs.canton.network/sdks-tools/development-tools/pqs)
reads the Ledger API as parties hosted on your participant, and so only ever
projects contracts those parties are stakeholders of. Contracts you hold by
explicit disclosure never enter your active contract set and never appear in
PQS. Pushed publications are therefore queryable only when the distributor
names your party as an observer; if it discloses instead, you learn contract
ids from its channel and use them directly at submission time. Decide this with
your distributor before building a read path around a query store — for a
large audience, disclosure is what the distributor will normally offer.

Where PQS does apply it is the right tool, because it projects and filters by
interface view: one query covers every `PublishedDataPoint` implementation
regardless of distributor. On Canton 3.4 use PQS 3.4.3 or later, which fixes an
interface-view projection bug. If you consume streams directly, interface views
are served on the transaction stream and the ACS, not the transaction tree
stream.

The pull path sidesteps the question: nothing per payload is on the ledger, so
there is nothing to index, and the one `DistributorKey` contract you need is
usable by disclosure alone.
