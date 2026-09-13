# CLAUDE.md — Zavithar Manager

This file orients any Claude Code session (or developer) working in this repository. Full project documentation (requirements, architecture, data model, testing/deployment/maintenance plans) lives in the **zavithar_manager** Claude Project — this file is the quick-reference summary so work stays consistent across sessions. When in doubt about a decision, check the Project docs before re-deciding something already settled here.

## What this is

A single-user, real-time-synced personal app covering two areas:
- **Financial manager** — transactions, savings goals, liabilities.
- **Todo list** — categorized (hobbies / study / work / home) tasks with deadlines, reminders, push notifications, and follow-up tasks.

Used on Android (phone) and Windows (desktop), interchangeably, with both devices always reflecting the same live data — that real-time cross-device sync is the core requirement everything else is designed around.

Single owner/user: Zavithar. No multi-user/sharing in v1. (The owner's Google account is the one signed into the Firebase project — it is deliberately not written down in this repo.)

## Tech stack (decided, do not re-litigate without discussion)

- **Client:** Flutter — one codebase, Android + Windows desktop builds.
- **Backend:** Firebase
  - **Cloud Firestore** — real-time database, source of truth, offline-cache enabled.
  - **Firebase Auth** — Google sign-in (primary) and email/password (fallback), both free on the Spark plan.
  - ~~**Firebase Cloud Messaging (FCM)**~~ — **dropped with the Cloud Functions** (ADR 0011). With no server sending, there is nothing to receive; `firebase_messaging` is not a dependency.
  - ~~**Cloud Functions**~~ — **removed, [ADR 0011](docs/adr/0011-free-tier-only.md).** They require the Blaze plan, and the app must stay free. Todo reminders are **on-device scheduled notifications** (`flutter_local_notifications` + `zonedSchedule`) instead: one user, and every device already has the `reminderAt` values Firestore synced to it, so there is nothing for a server to re-derive.
- **Data scoping:** everything lives under `users/{uid}/...` in Firestore; security rules check `request.auth.uid == uid`.

## Current status

| Phase | Status |
|---|---|
| 1. Requirements & docs | Done |
| 2. Mockups | Done (interactive HTML prototype, dark theme, red brand accent) — logo mark still **undecided**, mockups use plain text branding for now |
| 3. Data model | Done |
| 4. Development | **In progress** — Milestones 0, 1, 2 done and 3 code-complete (2026-09-13), plus monthly statements (ADR 0012). Windows build still deferred. **Open:** a reminder has not yet been observed firing on a device |
| 5. Testing | Plan written, not yet executed |
| 6. Deployment | Plan written, not yet executed |
| 7. Maintenance | Plan written, ongoing once live |

## Development milestones (execution order)

0. **Scaffolding** — ✅ **Done on Android, 2026-08-23.** Firebase project live (Firestore + Auth, rules deployed), Flutter project targeting Android + Windows, Riverpod/go_router app shell with a redirect-based auth gate. Two recorded departures from the original plan: `firebase_messaging` deferred to Milestone 3 (`docs/adr/0006`), and the Windows build deferred (`docs/adr/0005`) — so the "both platforms" half of the done-when is still outstanding. See `docs/devlog/2026-08-23.md`.
1. **Financial manager** — transactions/savings/liabilities CRUD wired to real-time Firestore streams, dashboard stat tiles. **Done when:** a change on one device appears on the other within seconds.
   - Transactions, savings goals and liabilities ✅ (2026-08-25) — all three collections live, in a three-tab Finance screen. The four-file shape to copy for todos: `domain/` model → `data/` repository → `application/` providers → `presentation/` screen. See `docs/devlog/2026-08-25.md` and `docs/learning/05-firestore-repositories-and-streams.md`.
   - Dashboard stat tiles ✅ (2026-09-13) — balance, this month's income/expense/net, savings and debt progress. **All derived, never stored**, and folded from the *same* three streams the Finance tab watches, so both screens alive still means three Firestore listeners rather than six. See `docs/devlog/2026-09-13.md`.
   - **When folding several `AsyncValue`s, check error before loading.** A stream refused by a rule stays in the error state forever while a slow sibling is still loading, so a loading-first branch wins every frame and spins for ever instead of reporting the real failure. Render on `hasValue`, not `!isLoading` — a refreshing stream is both.
   - **"This month" filters on `date`, not `createdAt`** — when the money moved, not when the row was typed — and compares year *and* month.
   - **Balances are adjusted with `FieldValue.increment`, never read-then-write** — the latter loses a concurrent contribution or payment, and does not queue correctly offline.
   - **An optional field needs three things**, or it is not really optional: `toMap` omits the key (never writes null), `copyWith` gets an explicit `clear*` flag, and `update` sends `FieldValue.delete()`.
   - **Currency is COP**, formatted only via `core/format/money.dart` — never a raw `'$$amount'` ([ADR 0009](docs/adr/0009-money-and-dates.md)).
   - **Transactions are streamed only for the open period** — since the last closed month ([ADR 0012](docs/adr/0012-monthly-statements.md)). The balance is `sum(statement nets) + open period`. Closing a month is manual, reversible, and **deletes nothing**; only the *earliest* unclosed finished month may be closed, because skipping one would drop its transactions out of both the stream and every statement.
   - **A transaction dated inside a closed month is rejected by the rules** (`periodIdOf()` + `exists()`), refused by the date picker, and caught afterwards by `verify()`. Unguarded it would vanish from the balance in silence.
   - **Rules gotcha:** Firestore OR-s all matching rules, so a collection with its own validated block must be excluded from the `match /{collection}/{docId}` catch-all in `firestore.rules`, or the wildcard waves everything through. The exclusion list already holds `transactions`, `savings`, `liabilities` — **add `todos` to it at Milestone 2.**
   - **The Firebase console bypasses security rules entirely** (admin credentials), as does the Admin SDK and any Cloud Function — a write that the console accepts proves nothing.
   - **The Rules Playground cannot test these rules either, and fails misleadingly.** All three collections require `createdAt == request.time`, which only `FieldValue.serverTimestamp()` can satisfy; the Playground's timestamps are typed by hand, so *every* simulated create/update is denied — on the timestamp, whatever else is in the payload. Testing `amount: -5` there returns "denied" and proves nothing. The Playground is only sound for checks not involving timestamps (cross-user reads, the collection allowlist). Real verification needs the **Firestore emulator + `@firebase/rules-unit-testing`**, which runs a real client SDK. See `docs/devlog/2026-09-13.md`.
2. **Todo list** — ✅ **Done 2026-09-13.** CRUD, category + status filter chips with cross-filtered counts, follow-up linking, validated rules. See `docs/devlog/2026-09-13.md`.
   - **`todos` is now in the rules exclusion list**, which reads `transactions`, `savings`, `liabilities`, `todos`. Every future collection with its own validated block must be added, or the catch-all waves its writes through.
   - **`completedAt` is deliberately not pinned to `request.time`**, unlike the audit timestamps: it is written once and carried through later edits, so an equality check would reject every subsequent edit of a finished task.
   - **Filtering and ordering happen in memory** (`TodoQuery`), not in the query — a `where` per chip needs a composite index per combination and re-reads every document on every tap.
   - **Never `orderBy` an optional field.** Firestore omits documents that lack it, so ordering todos by `deadline` would hide every undated task.
   - Shared sheet chrome, list states, `OptionalDateField` and `DataFailure` now live in `core/`, not in `features/finance/`.
3. **Notifications** — code-complete 2026-09-13, **not yet verified firing on a device.** On-device scheduling only (`flutter_local_notifications` + `zonedSchedule`); no FCM, no Cloud Function ([ADR 0011](docs/adr/0011-free-tier-only.md)).
   - **A scheduling bug has no symptom** — nothing crashes, nothing is logged, the reminder just never arrives. Hence the pure `ReminderPlan` with heavy unit tests, and the Settings card that shows what *Android is actually holding* versus what the app intends.
   - Android needs **core library desugaring** (`isCoreLibraryDesugaringEnabled`) or the build fails at `checkDebugAarMetadata`, plus `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED` and `VIBRATE` — see the manifest comments for why each one is load-bearing.
   - **Notification IDs must be stable per todo**, or a reschedule leaves the old alarm beside the new one and the reminder fires twice.
   - **Past reminders are dropped, never scheduled** — firing immediately would dump a week of stale reminders into the shade after a holiday.
   - `users/{uid}/devices/{id}` is dead schema (it only ever held FCM tokens).

4. **Polish** — recurring transactions, budgets, charts, editable categories, CSV export, dark mode refinements.

Full task breakdown for each milestone is in `development-plan.md` in the Project.

## Data model (Firestore, summary)

```
users/{uid}/transactions/{id}   — amount, type, category, description?, date, account?, createdAt, updatedAt
users/{uid}/savings/{id}        — name, targetAmount, currentAmount, deadline?, createdAt, updatedAt
users/{uid}/liabilities/{id}    — name, type, originalAmount, remainingAmount, interestRate?, dueDate?, minimumPayment?
users/{uid}/todos/{id}          — title, notes?, category, status, deadline?, reminderAt?, followUpOf?, priority?, timestamps
users/{uid}/statements/{YYYY-MM} — periodStart/End, totalIncome, totalExpense, openingBalance, closingBalance, transactionCount, incomeByCategory, expenseByCategory, closedAt
users/{uid}/categories/{id}     — optional, if categories become user-editable
users/{uid}/devices/{id}        — fcmToken, platform, lastSeenAt
```

Full field types, validation ranges, and the security-rules sketch are in `data-model.md` in the Project.

## Brand & UI tokens (settled — apply these, don't invent new ones)

Dark theme. CSS custom properties used in the mockups (carry the same values into Flutter theming):

```
page:                #0d0d0d
surface-1:            #1a1a19   (cards, screens, headers)
surface-2:            #161413   (sidebar/secondary panels)
text-primary:         #ffffff
text-secondary:       #c3c2b7
muted:                #898781
gridline:             #2c2c2a
brand-primary:        #b3122b   (buttons, active nav/tabs, links)
brand-primary-light:  #ff3b57   (gradient highlight, hover)
brand-primary-dark:   #6e0d1a   (gradient shadow, pressed)

category — work:      #d95926 (orange)
category — hobbies:   #199e70 (aqua/green)
category — study:     #c98500 (gold, use dark text on it)
category — home:      #9085e9 (violet)

status — good:        #0ca30c
status — warning:     #fab219
status — serious:     #ec835a
status — critical:    #e66767
```

Status colors always pair with an icon or text label, never color alone. Category colors follow a fixed order — don't reassign or cycle them.

**Logo:** not decided yet. Several directions were explored (geometric badge, abstract sync/growth/gem symbols, hand-drawn "meteor crack" and "rune blade" Z letterforms) and none landed. Current mockups use a plain text wordmark. Revisit when there's appetite to iterate again — don't block development on it.

## Hard constraint: the app must never cost money

**No paid tier, under any circumstance** — not "keep it cheap", free. Firestore,
Auth and Hosting are free on Spark, and Spark's failure mode is the right one:
exceeding quota **stops the service for the day, it never bills**.

What this forbids: **Cloud Functions and the Blaze plan** (a payment method on
file is not free, however small the bill would be), and **Cloud Storage**, which
is Blaze-gated for new projects. See [ADR 0011](docs/adr/0011-free-tier-only.md).

The rule to apply when a feature seems to need a server — scheduled work,
webhooks, server-side aggregation, anything that must run while no device is
awake: **it happens on a device, or it does not happen.**

**Reads are the scarce resource, not storage.** 50,000 document reads a day
against 1 GiB of space — roughly a million transactions, or 274 years of them.
So the answer to a collection growing is to stop *reading* it, never to delete
it: see [ADR 0012](docs/adr/0012-monthly-statements.md). Exceeding a quota
returns `resource-exhausted` and stops the service until midnight US Pacific
(2am Colombia); it never bills.

## Engineering conventions

- Thin repository layer per Firestore collection (e.g. `TransactionsRepository`) — UI never talks to Firestore directly.
- Every stream-backed screen has explicit loading/error states from the start.
- **A committed write, a rejected write and one queued forever in the local cache look identical in the UI** — latency compensation renders the row in every case. `main.dart` carries an off-by-default `logFirestoreRpcs` flag; turn it on and look for `commit_time` (accepted) or `permission-denied` (rejected) when data behaves strangely.
- **Under git since 2026-09-13**, on a public GitHub remote (`origin/main`). The repo went three sessions without version control before that — the convention was written here from the start and simply never executed, which is worth remembering as a category of mistake: a rule in a doc is not a thing that exists.
- Commits are authored with the **GitHub noreply address, set repo-locally** (`git config --local user.email`), so the owner's real email never enters a public history. The global git identity on the machine is the real one — do not rely on it here.
- Feature branches per milestone, small commits.
- **Public repo ⇒ the security rules are the only real access control.** The API key is visible by design (ADR 0008) and is not a secret, but anything the rules do not forbid is open to the internet. Account creation is disabled in the Firebase console so the public key cannot be used to mint accounts — see [ADR 0010](docs/adr/0010-public-repo-hardening.md), which also lists the hardening still outstanding (API key restriction, App Check).
- **The API key ships in the APK regardless.** Going public lowered the cost of finding it, not the exposure itself — so "make the repo private" is never the fix for a key-reachable gap.
- Client-side form validation + Firestore security-rules validation (both layers — rules are the real enforcement).
- No fixed release dates; each milestone ships when its "done when" condition (see above) is verified, per `testing-plan.md`.
- **No personal or identifying data in the repo.** Never write the owner's email address, real name, device serial numbers, or machine-specific paths into any tracked file — docs, comments, commit messages included. Refer to "the owner" / "the test phone"; a bare device model (e.g. "Galaxy A26") is fine, its full variant code and serial are not. Use `%USERPROFILE%\...` instead of a real home directory. Firebase *client config* (`firebase_options.dart`, `google-services.json`) is the deliberate exception — it is not secret, see `docs/adr/0008-committing-firebase-config.md`. Delete `firebase-debug.log` after reading it; it embeds the account email.
- **Node package manager: `pnpm` only. Using `npm` is forbidden** — that includes `npm install`, `npm run`, and `npm install -g`. Install global CLIs with `pnpm add -g <pkg>`, install project deps in `functions/` with `pnpm install`, and run scripts with `pnpm <script>`. There must be a `pnpm-lock.yaml` and no `package-lock.json` anywhere in the repo.

## Where to look for more detail

All of these live in the **zavithar_manager** Claude Project (`claude/` docs):
- `requirements.md` — full PRD (functional & non-functional requirements, success criteria).
- `architecture.md` — system architecture and rationale.
- `data-model.md` — full Firestore schema, validation, security rules, indexing notes.
- `development-plan.md` — detailed per-milestone task breakdown.
- `testing-plan.md` — unit/widget/manual testing strategy, device matrix.
- `deployment-plan.md` — build/release process for Android + Windows, Firebase deploy steps.
- `maintenance-plan.md` — versioning, dependency updates, bug-fix workflow, backups.
- `brand-guide.md` — full color palette rationale and logo status.
- `work-plan.md` — master index tying all seven phases together.
