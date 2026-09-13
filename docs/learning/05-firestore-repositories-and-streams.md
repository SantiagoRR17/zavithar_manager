# 05 — Firestore repositories and streams

*Written 2026-08-25, alongside the transactions slice of Milestone 1.*

Lessons 02–04 kept circling one idea: **"who is signed in" is not a value you
can read, it is something you observe over time.** This lesson is that same idea
applied to data instead of identity, and it is the reason the app has no refresh
button anywhere.

> **A Firestore collection is not a table you query. It is a stream you
> subscribe to.**

Everything below follows from taking that literally.

---

## 1. `get()` versus `snapshots()`

Firestore offers both:

```dart
// One answer, right now.
final QuerySnapshot snap = await collection.get();

// Every answer, from now on.
final Stream<QuerySnapshot> stream = collection.snapshots();
```

`get()` is the shape you know from SQL or a REST call: ask, receive, done. If
the data changes a second later, you do not find out. To show fresh data you
would have to ask again — on a timer, or on a pull-to-refresh, or when the app
returns to the foreground. All three are things you have to remember to build,
and all three are wrong some of the time.

`snapshots()` opens a **listener**. It emits the current contents immediately,
and then again every single time anything in the query result changes — a
document added, edited or deleted, by this device, by the desktop, or by a
human clicking around in the Firebase console.

Milestone 1's "done when" is *a change on one device appears on the other within
seconds*. Read that again with the two options in mind: with `get()` it is a
feature you would have to engineer. With `snapshots()` it is what happens if you
do nothing else. That is the whole reason the requirement was written the way it
was and why Firestore was chosen (ADR 0001).

`TransactionsRepository.watchAll()` is one call to `snapshots()`. There is no
other machinery.

---

## 2. Why the repository exists at all

`CLAUDE.md`'s rule is that UI never talks to Firestore directly. Concretely,
`transactions_repository.dart` is the only file in the app that names the string
`'transactions'`.

The reasons are the same three as `AuthRepository` (lesson 04):

1. **One place to look.** How a transaction is stored is one file, not a fact
   spread across a form's save button, a list builder and a delete handler.
2. **Errors get translated at the boundary.** Widgets catch `FinanceFailure`
   with a readable `message`. They never see a `FirebaseException` or have to
   know that `'permission-denied'` is a string worth switching on.
3. **It is the test seam.** The constructor takes an optional `FirebaseFirestore`
   for exactly the same reason `AuthRepository` takes an optional
   `FirebaseAuth`.

There is a fourth reason specific to Firestore, and it is the one that bites
hardest without a repository: **the path is a string**. `collection('users')
.doc(uid).collection('transactions')` has no compile-time check on it
whatsoever. Typo `'transaction'` and Firestore does not error — collections are
created on demand, so you silently get an empty list and a write that lands
somewhere nothing reads. Confining that string to one file is not tidiness, it
is the only defence available.

---

## 3. `withConverter` — where the parsing lives

Raw Firestore hands you `Map<String, dynamic>`. Every field access is a cast
that can fail at runtime:

```dart
final amount = doc.data()['amount'] as num;   // throws on a bad document
```

`withConverter` moves that translation into the collection reference itself:

```dart
CollectionReference<FinanceTransaction> get _collection =>
    _raw.withConverter<FinanceTransaction>(
      fromFirestore: (snapshot, _) =>
          FinanceTransaction.fromMap(snapshot.id, snapshot.data() ?? {}),
      toFirestore: (value, _) => value.toMap(),
    );
```

After that line, `snapshots()` yields typed `FinanceTransaction` objects and the
casts exist exactly once.

**Note what `fromMap` does with bad data.** Every read has a fallback: a missing
amount becomes 0, an unknown `type` becomes an expense, a missing category
becomes `'other'`. That looks over-cautious given the security rules validate
every write. It is not, for one specific reason: **rules only validate writes as
they happen.** A document written yesterday, before a rule was tightened, is
never re-checked. Neither is one typed by hand into the console. A model that
throws on an unexpected document takes down the whole list because of one bad
row.

### The one place the converter does *not* apply

Writes deliberately use the raw, unconverted reference. Every write has to carry
`FieldValue.serverTimestamp()`, and a `FieldValue` is not a value — it is an
*instruction to the server*, meaning "put your own clock's time here". It cannot
live in a model object, so it cannot come out of `toFirestore`. Rather than have
a converter that is half-honest, writes stay on `_raw` where the instruction is
visible at the call site.

---

## 4. Latency compensation, and the null timestamp

This is the surprise you can actually feel on the device, so it is worth
understanding before it confuses you.

When you write a document, Firestore does **not** wait for the server. It writes
to the local cache, fires every local listener immediately, and reconciles with
the server afterwards. That is why a new transaction appears in the list
instantly, even on a bad connection — and why the app works fully offline
(FR-18).

The consequence: on the writing device, the first snapshot of a new document
contains `createdAt: null`. The server has not stamped it yet. A few hundred
milliseconds later a second snapshot arrives with the real value.

So `FinanceTransaction.createdAt` and `updatedAt` are nullable — not defensive
padding, but the accurate type. A non-nullable field there would crash the list
immediately after every single insert, on the one device that made it, and would
look like a random intermittent bug.

The same mechanism explains why `repository.add()` returns a `Future` that
nothing awaits before showing the row. That future completes on *server*
acknowledgement. The UI is driven by the stream, not by the future — offline,
the future may not complete for hours while the row sits happily on screen.

---

## 5. Rebuilding the repository per user

```dart
final transactionsRepositoryProvider = Provider<TransactionsRepository?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return TransactionsRepository(uid: user.uid);
});
```

Two things are happening in that `watch`, and the second is the important one.

The obvious one: the repository needs a uid to build its paths.

The subtle one: because it *watches* the user, **signing out disposes this
provider and everything derived from it — including the open Firestore
listener.** Without that, the listener opened for the previous user would keep
running, still authorised for a moment because its auth token is still valid,
and the next user's screen could briefly render the previous user's data.

This is a single-user app, so that scenario is hypothetical here. The habit is
not. It is the same principle as lesson 03's redirect: *state changes, and the
things derived from it follow automatically.* You never write "on sign-out, also
close the transaction listener" — that line does not exist anywhere in the
codebase, and it cannot be forgotten because it was never written.

Riverpod's disposal cuts the other way too: leave the Finance tab and nothing
watches the stream, so the listener closes. Firestore bills per document read,
and a listener left open on a collection is a slow leak of the free tier
(NFR-5).

---

## 6. Two layers of validation, and what each is actually for

The form validates. The rules validate. This is not belt-and-braces; they do
genuinely different jobs.

**The form** exists to tell you, before you hit save, that the amount box is
empty. It is a *user experience* feature. It stops nothing — the project's API
key is public (ADR 0008) and anyone can talk to this database directly.

**The rules** are the enforcement. `firestore.rules` now checks, for every
transaction write: exactly the expected set of keys, `amount` a number greater
than zero, `type` one of two strings, `date` a timestamp, `description` at most
200 characters.

Two rules there are worth reading closely:

```
data().createdAt == request.time
```

`request.time` is set by Firestore when the write arrives. `serverTimestamp()`
resolves to exactly it. So an honest client passes and a client that tries to
forge its own history fails — you cannot backdate an audit field.

```
data().createdAt == resource.data.createdAt   // on update
```

`resource.data` is the document *as it exists now*; `request.resource.data` is
what is being written. Comparing them makes `createdAt` immutable after
creation.

### The gotcha that would have silently defeated all of it

Milestone 0 shipped a catch-all rule:

```
match /{collection}/{docId} {
  allow read, write: if isOwner() && isKnownCollection(collection);
}
```

That wildcard also matches `transactions/{id}`. And **Firestore evaluates every
matching rule and allows the write if *any one* of them allows it.** They are
OR-ed, not AND-ed. So adding a strict `match /transactions/{txId}` block above
would have achieved precisely nothing — the loose wildcard would still wave
everything through, and the new rules would look correct while enforcing
nothing.

The fix is the `&& collection != 'transactions'` on the baseline block: as each
collection graduates to real validation, it is excluded from the catch-all.
Worth remembering at Milestone 2, when `todos` does the same.

**A rule that has never rejected anything is untested.** The console's Rules
Playground is how you find out — try to write `amount: -5` and watch it be
denied.

---

## 7. Adjusting a number that already exists

Savings goals and liabilities both have a balance that gets *adjusted* rather
than replaced — money added to a goal, a payment made against a debt. The
obvious implementation is wrong, and worth seeing why.

```dart
// Don't. This loses data.
final goal = await ref.get();
await ref.update({'currentAmount': goal['currentAmount'] + 10000});
```

Two devices both read 50.000, both add 10.000, both write 60.000. One
contribution is gone, with no error anywhere.

```dart
// Do.
await ref.update({'currentAmount': FieldValue.increment(10000)});
```

`FieldValue.increment` is applied **on the server**, atomically. The result is
70.000 regardless of ordering, because neither device ever computed the answer —
they each sent an *instruction*.

That framing is also why it works offline. A queued increment composes with
whatever happened elsewhere while the device was away; a queued *value* would
overwrite it.

The cost is real and worth stating: an increment cannot clamp, because the
server applies it without reading anything back. Overpaying a debt therefore
produces a negative balance. Preventing that in the database would need a
`Transaction` (Firestore's read-modify-write kind), and that gives up the
offline behaviour. Here the form validates it instead, and the model displays it
honestly if it ever happens — the trade is written down in
`liabilities_repository.dart` rather than hidden.

## 8. Making a field genuinely optional

A savings deadline is optional. Three separate things have to be right, and each
one fails in a different way:

1. **`toMap` omits the key** rather than writing `null`. A present-but-null key
   still counts as *present* to the rules' `hasOnly`/`hasAll` allowlist, so
   writing null trips the validation you wrote to allow it.
2. **`copyWith` needs an explicit `clearDeadline` flag.** Dart's
   null-means-unchanged convention has no way to say "remove this" — without the
   flag, a deadline set once can never be cleared.
3. **`update` must send `FieldValue.delete()`.** An omitted key in an update
   leaves the old value in the document, so clearing the box in the form would
   silently do nothing.

Miss (1) and writes are rejected. Miss (2) or (3) and the UI appears to work
while the data does not change. The second kind is much harder to notice.

## 9. The shape to copy

Todos are next, and they are the same four files:

```
domain/      finance_transaction.dart     the model: parsing, no Firestore calls
data/        transactions_repository.dart the only file touching the collection
application/ transaction_providers.dart   repository + stream, per user
presentation/finance_screen.dart          watches, handles all three states
```

That layering is not ceremony. Each layer knows only the one below it, which is
why the model can be unit-tested with no emulator, no network and no Firebase
initialisation at all — `test/finance/finance_transaction_test.dart` runs in
milliseconds and it is where both real bugs in this session were caught.

---

**Files written today** — all under `app/lib/features/finance/` unless noted:

- `domain/` — `finance_transaction.dart`, `finance_categories.dart`,
  `finance_accounts.dart`, `savings_goal.dart`, `liability.dart`
- `data/` — `transactions_repository.dart`, `savings_repository.dart`,
  `liabilities_repository.dart`
- `application/transaction_providers.dart` — all three repository/stream pairs
- `presentation/` — `finance_screen.dart` (the three-tab shell), `tabs/`,
  the three form sheets, and `widgets/`
- `app/lib/core/format/money.dart`
- the `transactions`, `savings` and `liabilities` blocks in `firestore.rules`

**Next:** lesson 06 will cover forms and validation properly — `Form`,
`GlobalKey<FormState>`, controllers and why they need disposing, and the custom
`TextInputFormatter` behind the amount field's live thousands grouping.
