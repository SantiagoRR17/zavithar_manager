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
  - **Firebase Cloud Messaging (FCM)** — push notifications for todo reminders.
  - **Cloud Functions** — scheduled job that scans todos for due reminders and sends FCM pushes (this is what requires the app to notify even when closed).
- **Data scoping:** everything lives under `users/{uid}/...` in Firestore; security rules check `request.auth.uid == uid`.

## Current status

| Phase | Status |
|---|---|
| 1. Requirements & docs | Done |
| 2. Mockups | Done (interactive HTML prototype, dark theme, red brand accent) — logo mark still **undecided**, mockups use plain text branding for now |
| 3. Data model | Done |
| 4. Development | **In progress** — Milestone 0 done on Android (2026-08-23); Windows build deferred. Milestone 1 started 2026-08-25: transactions complete; savings, liabilities and dashboard tiles outstanding |
| 5. Testing | Plan written, not yet executed |
| 6. Deployment | Plan written, not yet executed |
| 7. Maintenance | Plan written, ongoing once live |

## Development milestones (execution order)

0. **Scaffolding** — ✅ **Done on Android, 2026-08-23.** Firebase project live (Firestore + Auth, rules deployed), Flutter project targeting Android + Windows, Riverpod/go_router app shell with a redirect-based auth gate. Two recorded departures from the original plan: `firebase_messaging` deferred to Milestone 3 (`docs/adr/0006`), and the Windows build deferred (`docs/adr/0005`) — so the "both platforms" half of the done-when is still outstanding. See `docs/devlog/2026-08-23.md`.
1. **Financial manager** — transactions/savings/liabilities CRUD wired to real-time Firestore streams, dashboard stat tiles. **Done when:** a change on one device appears on the other within seconds.
   - Transactions, savings goals and liabilities ✅ (2026-08-25) — all three collections live, in a three-tab Finance screen. The four-file shape to copy for todos: `domain/` model → `data/` repository → `application/` providers → `presentation/` screen. See `docs/devlog/2026-08-25.md` and `docs/learning/05-firestore-repositories-and-streams.md`. Dashboard stat tiles still outstanding.
   - **Balances are adjusted with `FieldValue.increment`, never read-then-write** — the latter loses a concurrent contribution or payment, and does not queue correctly offline.
   - **An optional field needs three things**, or it is not really optional: `toMap` omits the key (never writes null), `copyWith` gets an explicit `clear*` flag, and `update` sends `FieldValue.delete()`.
   - **Currency is COP**, formatted only via `core/format/money.dart` — never a raw `'$$amount'` ([ADR 0009](docs/adr/0009-money-and-dates.md)).
   - **Rules gotcha:** Firestore OR-s all matching rules, so a collection with its own validated block must be excluded from the `match /{collection}/{docId}` catch-all in `firestore.rules`, or the wildcard waves everything through. The exclusion list already holds `transactions`, `savings`, `liabilities` — **add `todos` to it at Milestone 2.**
   - **The Firebase console bypasses security rules entirely** (admin credentials), as does the Admin SDK and any Cloud Function. Rules can only be tested from a client SDK or the console's **Rules Playground** — a write that the console accepts proves nothing.
2. **Todo list** — todo CRUD, category chips, status filters, follow-up task linking. Same real-time cross-device check as Milestone 1.
3. **Notifications** — FCM token registration per device, scheduled Cloud Function for reminders, foreground + background notification handling.
4. **Polish** — recurring transactions, budgets, charts, editable categories, CSV export, dark mode refinements.

Full task breakdown for each milestone is in `development-plan.md` in the Project.

## Data model (Firestore, summary)

```
users/{uid}/transactions/{id}   — amount, type, category, description?, date, account?, createdAt, updatedAt
users/{uid}/savings/{id}        — name, targetAmount, currentAmount, deadline?, createdAt, updatedAt
users/{uid}/liabilities/{id}    — name, type, originalAmount, remainingAmount, interestRate?, dueDate?, minimumPayment?
users/{uid}/todos/{id}          — title, notes?, category, status, deadline?, reminderAt?, followUpOf?, priority?, timestamps
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

## Engineering conventions

- Thin repository layer per Firestore collection (e.g. `TransactionsRepository`) — UI never talks to Firestore directly.
- Every stream-backed screen has explicit loading/error states from the start.
- Feature branches per milestone, small commits.
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
