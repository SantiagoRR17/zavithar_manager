# Architecture & Tech Stack

## Summary

A personal, single-user, real-time productivity and finance app, usable on Android and desktop simultaneously, with the same data reflected live on both. Built as a single Flutter codebase backed by Firebase.

## Decisions

- **Client framework:** Flutter. One Dart codebase compiles to Android and to Windows/macOS/Linux desktop builds (plus web, if wanted later, for free). This avoids maintaining two separate apps and keeps UI/logic in sync automatically.
- **Backend/database:** Firebase, specifically:
  - **Cloud Firestore** — the real-time database. Every device holding an open listener on a document/collection receives live updates the moment data changes elsewhere, which is exactly the "check the same info in real time on both devices" requirement.
  - **Firebase Authentication** — single-user login (email/password or Google sign-in), used mainly to scope data to your account and secure Firestore rules. Even as a single user, auth is needed so random people/devices can't read or write your data.
  - **Firebase Cloud Messaging (FCM)** — push notifications for todo deadlines and follow-ups, delivered to Android and desktop even when the app isn't open.
  - **Cloud Functions** (small, as needed) — for scheduled/triggered logic, e.g. "check for todos due in the next hour and send a push," which can't run purely on-device since the app may be closed.
- **Users:** single-user app. Data model is scoped under one account; no sharing/permissions system in v1 (can be added later without a full redesign, since Firestore security rules and collections are already user-scoped).
- **Offline support:** Firestore has built-in offline persistence/caching, so the app keeps working without internet and syncs automatically when back online — this comes for free with the chosen stack.

## High-level structure

```
Flutter App (Android + Desktop builds, shared codebase)
  ├── Auth layer (Firebase Auth)
  ├── Finance module
  │     ├── Transactions
  │     ├── Savings
  │     └── Liabilities
  ├── Todo module
  │     ├── Tasks (with category, deadline, status)
  │     └── Reminders/follow-ups
  ├── Notifications (FCM client + local notification handling)
  └── Real-time data layer (Firestore streams/listeners)

Firebase Backend
  ├── Firestore (source of truth, real-time sync)
  ├── Auth (single account)
  ├── Cloud Functions (scheduled deadline checks → push notifications)
  └── Cloud Messaging (delivers push to all registered devices)
```

## Why this combination

- Real-time sync across devices is Firestore's core feature — no custom WebSocket server needed.
- Flutter + Firebase is a well-trodden combination with mature packages (`cloud_firestore`, `firebase_auth`, `firebase_messaging`) for exactly this kind of app.
- Both Firebase and Flutter have generous free tiers, so this is very cheap to run for a single user.
- Everything is prebuilt (auth, sync, offline cache, push) rather than hand-rolled, which matters a lot for a solo-built project.

## Open items to decide later (not blocking)

- Whether to also enable a Flutter Web build for a browser-only fallback.
- Whether desktop builds are distributed as installers or just run from source/dev builds.
- Budgeting-specific logic (recurring transactions, categories/tags for transactions) — to be defined in the feature spec.
