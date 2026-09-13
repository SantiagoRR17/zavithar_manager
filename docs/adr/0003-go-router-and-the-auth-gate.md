# ADR 0003 — go_router, and the auth gate as a redirect

**Status:** Accepted · 2026-08-22

## Context

Two navigation problems, and they interact.

1. **The auth gate.** Signed-out users must never reach app screens (FR-4). The obvious implementation is a wrapper widget: `if (user == null) LoginScreen() else AppShell()`.
2. **Tab navigation with persistent state.** The mockups show four sections, each keeping its own scroll position and navigation stack when you switch away and back.

And a third, arriving later: at **Milestone 3**, tapping a reminder notification must open one specific todo. That is a deep link — the app is handed a location and has to navigate to it, possibly from a cold start, possibly while signed out.

The wrapper-widget gate breaks that. A widget that swaps the whole tree cannot express "you asked for `/todos/abc123`, sign in first, then continue" — the requested location is not part of any state, so it is simply lost.

## Decision

**`go_router`**, with:

- the auth gate as a top-level **`redirect`**, not a wrapper widget;
- **`StatefulShellRoute.indexedStack`** for the four tabs.

## Consequences

**Good**

- The location is always real. Routing and permission live in the same system, so a deep link that arrives while signed out can be honoured after sign-in rather than dropped.
- `StatefulShellRoute` gives each branch its own `Navigator`, so per-tab stack and scroll state persist for free.
- Declarative: `redirect` is a pure function of (current auth state, requested location) → location. It is readable in one screenful and testable without a widget tree.

**Bad / accepted**

- `redirect` runs on **every** navigation. It must stay cheap and must never loop — the `location == target ? null : target` shape in `app_router.dart` is what prevents that.
- Auth state is a stream but `GoRouter` wants a `Listenable`, so a small `ValueNotifier` adapter sits in `routerProvider`. Slightly awkward, well contained.
- Carrying the originally-requested location across sign-in is **not yet implemented** — there is nothing to deep-link to until Milestone 2. The structure that makes it possible is what this ADR buys.

## Where it shows up

`app/lib/core/router/app_router.dart` — the whole thing, gate and shell, in one file.
