# ADR 0006 — Defer `firebase_messaging` to Milestone 3

**Status:** Accepted · 2026-08-23

## Context

`CLAUDE.md`'s Milestone 0 task list includes adding `firebase_messaging` alongside the other core packages. But:

- Nothing calls it until Milestone 3. Notification handling, token registration and the scheduled Cloud Function are all M3 work.
- It has **no Windows implementation** ([ADR 0005](0005-android-first.md)), and Windows is a declared build target. Carrying an unused plugin that cannot build on one of the two targets adds risk to a milestone whose entire point is "the project builds and runs".
- Adding it later is one `flutter pub add` plus a `google-services.json` that already has the right entries.

## Decision

Milestone 0 adds `firebase_core`, `cloud_firestore`, `firebase_auth`, `google_sign_in`, `flutter_riverpod` and `go_router`. **`firebase_messaging` is added at the start of Milestone 3**, not now.

This is a deliberate, recorded departure from `CLAUDE.md`'s M0 task list — the milestone's *"done when"* (sign in on both platforms, land on an empty shell) is unaffected, since it says nothing about notifications.

## Consequences

**Good** — one less moving part in the first build; no dead dependency; the Windows build has one less reason to fail.

**Bad / accepted** — `CLAUDE.md` and the code disagree until M3. That is what this ADR is for.

**Still open, and bigger:** FR-15 requires push on *both* devices with the app closed, and FCM cannot deliver to Windows at all. Deferring the package does not create that problem and does not solve it. It needs a decision before M3 starts.
