# ADR 0002 — Riverpod for state management

**Status:** Accepted · 2026-08-22

## Context

Almost every screen in this app displays a Firestore stream. Something has to subscribe to that stream, hold the latest value, rebuild the UI on change, and cancel the subscription when the screen goes away — and do it identically everywhere, because `CLAUDE.md` requires *every* stream-backed screen to have explicit loading and error states from the start.

Doing this with `StatefulWidget` + `StreamSubscription` by hand means the same twenty lines in every screen, and one forgotten `cancel()` is a leak. `StreamBuilder` removes the boilerplate but gives an `AsyncSnapshot` whose "no data yet" and "data is null" cases are easy to conflate, and it re-subscribes on every rebuild unless the stream is carefully hoisted.

Candidates considered: `provider`, `flutter_bloc`, Riverpod.

## Decision

**`flutter_riverpod`.** Repositories expose a `Stream`, a `StreamProvider` wraps it, and widgets write `.when(data:, loading:, error:)`.

## Consequences

**Good**

- `AsyncValue` makes the project's loading/error rule *structural*: `.when` does not compile unless all three states are handled. The convention enforces itself instead of relying on review.
- It distinguishes `AsyncLoading()` from `AsyncData(null)`. That is not academic — it is the difference between showing a startup spinner and flashing the login screen at an already-signed-in user on every cold start (see `app/lib/features/startup/presentation/startup_screen.dart`).
- Providers are declared outside the widget tree, so they can be read without a `BuildContext` and overridden wholesale in tests: `ProviderScope(overrides: [authRepositoryProvider.overrideWithValue(fake)])`.
- Subscriptions are disposed automatically when nothing watches a provider any more.

**Bad / accepted**

- Another concept to learn on top of Flutter itself — mitigated by `docs/learning/02-state-and-riverpod.md`.
- Riverpod 3 renamed things: the nullable accessor is now `AsyncValue.value`, and `valueOrNull` is gone. Tutorials written for Riverpod 2 will not compile as written.
- Code generation (`riverpod_generator`) is deliberately **not** used yet. It removes boilerplate but adds a build step and hides what a provider actually is; hand-written providers are better for learning. Revisit if the boilerplate becomes a burden.

## Where it shows up

`app/lib/features/auth/application/auth_providers.dart` is the reference example — a `Provider` for the repository, a `StreamProvider` over its stream, and a derived `Provider` on top.
