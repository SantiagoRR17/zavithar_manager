# ADR 0012 — Monthly statements, and why nothing is deleted

**Status:** Accepted · 2026-09-13
**Extends [ADR 0011](0011-free-tier-only.md).** Qualifies the "derived data is never stored" rule in `claude/data-model.md`.

## Context

Every query in the app streams its whole collection — no `limit()` anywhere.
That is fine now and does not stay fine, because `transactions` is the one
collection that grows without bound. At roughly ten transactions a day:

| | Documents | Reads per cold start | Share of the 50,000/day free quota |
|---|---|---|---|
| Year 1 | ~3,700 | 3,700 | 7% |
| Year 3 | ~11,000 | 11,000 | 22% |
| Year 5 | ~18,000 | 18,000 | **36%** |

By year five, three cold starts exhaust the day. Under ADR 0011 there is no
paid escape hatch, so this has to be solved rather than outgrown.

The obvious framing — "archive and delete old transactions, like a bank
statement" — is half right, and the half that is wrong is the expensive half.

## Decision

1. **A statement document per calendar month**, at
   `users/{uid}/statements/{YYYY-MM}`: totals, per-category breakdown,
   transaction count, and opening/closing balances that chain month to month.
   Written once, never edited.
2. **The transactions stream is filtered to the open period** —
   `where('date', '>=', openPeriodStart)`. Firestore bills only for documents a
   query returns, so everything before that line stops costing anything to read.
3. **Nothing is deleted.** The raw transactions stay in Firestore forever.
4. **Closing is manual**, triggered by the owner, and only ever closes the
   *earliest* month that has fully ended and is not yet closed.
5. **A statement can be verified** against the raw transactions it summarises,
   and the app offers that as an action rather than assuming it is correct.

## Rationale

### Reads are the constraint; storage is not

The two are separate resources and only one of them is scarce here. A
transaction document costs roughly a kilobyte once index entries are counted, so
the 1 GiB free tier holds on the order of **a million transactions** — 274 years
at ten a day. Storage will never be the binding limit.

So once the balance comes from statements, the old transactions simply stop
being read, and **the entire saving is already banked**. Deleting them frees
only the resource that was never going to run out.

### Deleting costs three things and buys none of them

- **A statement derived from data you still hold can be recomputed; one derived
  from data you deleted has to be taken on faith.** If a bug in the category
  totals surfaces in 2029, the raw ledger is what makes it fixable — and what
  makes it *detectable* in the first place.
- **It answers only the questions that occurred to whoever designed the
  statement.** "How much did I spend on health in 2027", "when did I pay that
  person" — gone.
- **Closing runs on a device** (ADR 0011: no Cloud Functions). Writing a
  statement and deleting N transactions is not atomic, Firestore batches cap at
  500 operations, and two devices could close the same month at once. A partial
  delete double-counts. None of that exists if the delete does not.

Deletion remains available later, once the statements have years of proof behind
them. The reverse is not available at all.

### Why this does not contradict "derived data is never stored"

`claude/data-model.md` says derived data is never stored, and the dashboard tiles
were built that way on 2026-09-13 with the argument that a stored `balance` field
would drift. A statement is stored derived data, so the rule needs a sharper
edge:

**The problem was never storing a derived value — it was storing one that can
drift without anyone noticing.** A `balance` field is updated by every write to
every collection, so the first path that forgets desynchronises it and there is
no way to tell which number is lying. A closed-month statement is written **once**,
is immutable by definition, and — because the raw transactions are still there —
is **checkable against its own source at any time**.

That is the distinction, and it is why `verifyStatement` is part of the feature
rather than a nice-to-have: it is what converts "we trust this number" into "we
checked it".

### Monthly, not six-monthly

A month is the unit people already think about money in, which makes statements
comparable and the close a familiar ritual rather than an event. It also keeps
each statement small and the close cheap. Sixty monthly statements after five
years is still a trivial read.

### The chain, and the gap it prevents

Each statement carries `openingBalance` and `closingBalance`, so they link like
bank statements do. The open period begins the day after the **latest closed
month**, not on the first of the current month — and only the earliest unclosed
finished month can be closed.

Without that rule, skipping a month leaves a hole: its transactions fall before
the open-period boundary and belong to no statement, so **they vanish from the
balance entirely**. Contiguity is not tidiness here, it is correctness.

## Consequences

- **A transaction backdated into a closed month is the hazard.** It would sit
  before the streamed window and outside any statement, and silently disappear
  from the balance. Three defences, in order of reliability: the security rules
  reject a transaction dated inside a closed period; the form will not offer
  such a date; `verifyStatement` finds any that got in anyway (from the console,
  or from a client written before this ADR).
- Editing history means **reopening a month**, which is a deliberate,
  explicit action — exactly as it should be, and exactly as a bank works.
- The all-time balance is `sum(statement nets) + sum(open-period transactions)`.
  Both halves stay live.
- `firestore.indexes.json` stays empty: `where('date', '>=', x)` combined with
  `orderBy('date')` is a single field and uses the automatic index.
- **`statements` must be added to the rules exclusion list** in the
  `match /{collection}/{docId}` catch-all, or the wildcard waves its writes
  through. Same trap as every collection before it.
- Revisit if transactions ever need full-text search or multi-year reporting in
  the app itself — both would want to read outside the open window, and both are
  one-off queries rather than streams.
