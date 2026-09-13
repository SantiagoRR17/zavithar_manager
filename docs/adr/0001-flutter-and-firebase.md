# ADR 0001 — Flutter + Firebase

**Status:** Accepted · 2026-08-20 (recorded 2026-08-23)

## Context

The app has to run on an Android phone and a Windows desktop, used interchangeably, with both showing the same data live (PRD §2, FR-17). It is built and maintained by one person who is also learning mobile development. Three shapes were possible:

1. Two native apps (Kotlin + WinUI) sharing a REST backend.
2. One cross-platform client against a custom backend.
3. One cross-platform client against a managed backend.

Real-time sync is the load-bearing requirement. Doing it by hand means a WebSocket server, a reconnect strategy, an offline queue, and conflict reconciliation — weeks of work that has nothing to do with finances or todos.

## Decision

**Flutter** for the client, **Firebase** for the backend: Cloud Firestore (source of truth + real-time sync + offline cache), Firebase Auth (identity), FCM (push), Cloud Functions (scheduled reminder checks).

## Consequences

**Good**

- Firestore's `snapshots()` listeners *are* the real-time layer. Cross-device sync is the default behaviour, not a feature to build.
- Offline persistence and replay-on-reconnect come free, satisfying FR-18 / NFR-3 with one line of config in `app/lib/main.dart`.
- One Dart codebase for both platforms; a third platform later is a build target, not a rewrite.
- Security rules are declarative and live in version control (`firestore.rules`).

**Bad / accepted**

- Vendor lock-in. Firestore's query model and rules language are not portable. Accepted: this is a personal app, and the data model is simple enough to export.
- Firestore cannot do aggregate queries cheaply, so dashboard totals are computed client-side from the live stream. Fine at single-user volume; would need rethinking at scale.
- Firebase's Flutter support on **Windows is beta**, officially scoped to "local development workflows". See [ADR 0005](0005-android-first.md).
- Cloud Functions have required the **Blaze** plan since Feb 2026, which conflicts with NFR-5 ("runs on the Spark free tier"). Blaze stays at $0 within the free quota but needs a card on file. **Unresolved** — it must be decided before Milestone 3 and does not block Milestones 0–2.
