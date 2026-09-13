# 06 — What actually protects your data (and why a private repo does not)

*Follows [05 — Firestore repositories and streams](05-firestore-repositories-and-streams.md).*
*Extends [04](04-firebase-auth-and-firestore-rules.md), which introduced the rules. This one answers the question that came up once the repository went public: **if I just make it private, am I safe?***

---

## The short answer

No. A private repository hides your *source code*. It does not protect your
*data*, and the two are not the same problem.

## The API key was never protected by the repository

`firebase_options.dart` and `google-services.json` contain the project's API
key, and both are committed on purpose ([ADR 0008](../adr/0008-committing-firebase-config.md)).
The instinct is that publishing them is what exposed the key.

It is not, because **the key ships inside the APK**. Anyone who installs the app
has it: unzip the file and read it. That is true of every Firebase Android app
ever built, and Google documents it.

So making the repository private moves the cost of finding the key from
*"open GitHub"* to *"unzip an APK"*. It does not hide it. This is why
[ADR 0010](../adr/0010-public-repo-hardening.md) says going public did not
*create* the security gap it found — the gap was equally present while the
repository was private, which is exactly why making it private again would not
have fixed anything.

The proof was not theoretical. A plain `curl` carrying the public key, sent
from a terminal with no app and no signed package, was accepted by the project's
Identity Toolkit endpoint. Nothing about that depended on the repository.

## Why the rules are the whole defence

Lesson 04 put it this way and it is worth repeating in these terms:

> **Firestore is a database exposed directly to the internet.** There is no
> server of yours in between.

The app, `curl`, and a script written by a stranger all speak to the same Google
API. The only thing that decides what any of them may do is `firestore.rules`.

```
your app   ─┐
curl       ─┼──→  Google's Firestore API  ──→  firestore.rules  ──→  your data
a stranger ─┘                                  ↑
                                               the only gate
```

A useful way to hold it:

> A private repository is not publishing the blueprints of your house.
> The security rules are the lock on the door.
>
> Secret blueprints do not help if the door is unlocked. A locked door works
> fine even when everyone has the blueprints.

## The reason that matters more for a one-person app

Here is the part that is easy to miss, and it is the stronger argument.

**The rules are not mainly protecting you from attackers. They are protecting
you from yourself.**

Look at what the 35 tests in `firestore-tests/` actually check:

- an amount that is negative, or zero, or the string `"100"` instead of a number
- a transaction missing its category
- a `type` of `"refund"`, which the app does not understand
- a statement whose closing balance does not follow from its own totals
- a task whose `followUpOf` points at itself

**None of that is something a hacker does.** All of it is something a *bug*
does.

If a future version of this app writes `amount` as a string — one forgotten
`num.parse`, one field renamed in the model and not in `toMap` — then without
rules that document lands in your ledger and stays there. Nothing breaks
loudly. You find out months later when a total does not add up and you have no
idea how far back the damage goes. With rules, the database refuses it at the
moment it happens, and you get a `permission-denied` while the mistake is one
line old.

This is why `CLAUDE.md` insists on validation in **both** layers: the form is
for the person using the app, the rules are the guarantee. For a single-user
app the main threat was always going to be you, writing code.

## What a private repository does buy

It is not nothing:

- your code, structure and decisions stay yours
- less exposure to opportunistic scanners that crawl public repositories for
  credentials

Both are real. Neither is the thing standing between your transactions and the
internet.

## The rule to carry away

> Ask **"what can someone do with the API key?"**, never **"can someone find
> the API key?"**
>
> Assume they have it, because they do. The answer to the first question is
> written entirely in `firestore.rules`.

## A control you have never seen reject anything is untested

Until 2026-09-13 these rules had been observed *accepting* writes and never once
*refusing* one. That is not the same as working.

It took a while to get there because of a trap worth knowing: **the Firebase
console cannot test rules at all** — its data editor writes with admin
credentials and bypasses them entirely — and **the Rules Playground cannot test
these particular rules either**. Every collection requires
`createdAt == request.time`, which only `FieldValue.serverTimestamp()` can
satisfy, and the Playground's timestamps are typed by hand. So every simulated
write is denied *on the timestamp*, whatever else is in it. Type `amount: -5`,
see **denied**, conclude the amount rule works — and you have tested nothing,
while retiring the question.

The tool that works is the **Firestore emulator** with
`@firebase/rules-unit-testing`, which runs a real client SDK and therefore a
real `serverTimestamp()`. `cd firestore-tests && pnpm test` starts it, runs the
suite and shuts it down. It uses a `demo-` project id, so it is fully offline
and cannot touch real data.

## Where to look next

- `firestore.rules` — the rules themselves, commented per collection
- `firestore-tests/rules.test.js` — what they have actually been seen to refuse
- [ADR 0008](../adr/0008-committing-firebase-config.md) — why the config is committed
- [ADR 0010](../adr/0010-public-repo-hardening.md) — the audit, the gap it found, and the hardening still outstanding

**Next:** lesson 07 will cover forms and validation — `Form`,
`GlobalKey<FormState>`, controllers and why they need disposing, and the custom
`TextInputFormatter` behind the amount field's live thousands grouping.
