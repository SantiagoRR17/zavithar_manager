# Development Plan

Milestone-based (no fixed dates), built solo. Each milestone should end in something runnable/demoable, not just code committed.

## Milestone 0 — Project scaffolding
- Create Firebase project (Firestore, Auth, Cloud Messaging, Functions).
- Enable Google sign-in and email/password sign-in methods in Firebase Auth (both are free on the Spark plan).
- Create Flutter project; add Android + Windows desktop as build targets.
- Add core packages: `firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_messaging`, `google_sign_in`.
- Baseline Firestore security rules (ownership check per `data-model.md`).
- App shell: navigation (bottom tabs on mobile / sidebar on desktop, per the mockups), auth gate (login screen → main app).
- **Done when:** you can sign in with Google or email/password on both Android and Windows, and land on an empty dashboard shell.

## Milestone 1 — Financial manager
- Transaction model + Firestore CRUD (create/edit/delete/list) wired to real-time stream.
- Transaction list screen with filters (date range, category), matching the mockup.
- Savings goals: CRUD + progress bar UI.
- Liabilities: CRUD + list UI.
- Dashboard stat tiles (balance, monthly income vs expense) computed from live transaction stream.
- **Done when:** adding/editing/deleting a transaction, savings goal, or liability on the phone instantly appears on desktop (and vice versa), matching the "definition of done" in `feature-roadmap.md`.

## Milestone 2 — Todo list
- Todo model + Firestore CRUD wired to real-time stream.
- Todo list screen with category chips and status filter, matching the mockup.
- Add/Edit todo form (title, category, deadline, reminder offset, notes, priority).
- Follow-up task creation (link new todo to a completed/existing one via `followUpOf`).
- **Done when:** same real-time cross-device check as Milestone 1, applied to todos.

## Milestone 3 — Notifications
- Register FCM token per device on login, store under `users/{uid}/devices/{deviceId}`.
- Cloud Function (scheduled, e.g. every 5-15 min): query todos with `reminderAt` in the near past/now and not yet notified, send FCM push to all device tokens, mark as notified.
- Client-side: handle foreground notifications (in-app banner) and background/terminated notifications (system push), matching the mockup's notification preview.
- **Done when:** a todo with a reminder in the next few minutes produces a real push on both Android and Windows without the app open.

## Milestone 4 — Polish
- Recurring transactions.
- Budgets per category with visual alerts.
- Charts: spending by category, net worth trend, savings trend (apply the `dataviz` skill's palette/rules when built).
- Editable todo categories.
- CSV export for transactions.
- Dark mode.

## Engineering practices throughout
- Feature branches per milestone, small commits.
- Keep Firestore reads/writes wrapped in a thin repository layer per collection (e.g. `TransactionsRepository`) so UI code never talks to Firestore directly — makes later testing and refactors easier.
- Add basic error handling/loading states for every stream-backed screen from the start, not as an afterthought.
