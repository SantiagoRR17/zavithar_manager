# 03 — Routing, and the auth gate

*Follows [02 — State and Riverpod](02-state-and-riverpod.md).*

---

## Imperative vs declarative navigation

Flutter's built-in `Navigator` is a stack you push and pop:

```dart
Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen()));
```

Fine for a dialog. It breaks down when navigation must follow *state*:

- signing out has to remove every app screen, from wherever you were;
- a notification tap has to open one specific todo, possibly from a cold start;
- signing in has to leave the login screen behind, not stack the app on top of it.

Each of those is "given the current state, the app should be *here*" — not "push a screen." Expressing it with pushes and pops means callbacks scattered across the codebase all reasoning about the same thing.

**`go_router` is declarative:** you describe locations and the rules for reaching them, and navigation follows.

## Routes

```dart
GoRoute(path: '/sign-in', builder: (context, state) => const LoginScreen())
```

Locations are URL-like strings. Later they carry parameters — `/todos/:id` — which is what makes a notification deep link possible at Milestone 3.

Route paths live in `AppRoutes` as constants rather than being typed inline, so renaming one is a compile error instead of a dead link discovered at runtime.

## `redirect` — the auth gate

The obvious way to gate an app is a wrapper widget:

```dart
// NOT what this project does
user == null ? const LoginScreen() : const AppShell()
```

It works, and it is wrong here. That widget cannot change the URL, so a requested location is simply lost. "You asked for `/todos/abc123`, sign in first, then continue" is inexpressible — there is nowhere for `abc123` to live while the user signs in.

`redirect` is a function `(context, state) → String?`. Return `null` to allow, or a location to send them somewhere else instead. It runs on **every** navigation attempt, including the first.

The logic in `app_router.dart`, in order:

```dart
if (auth.isLoading)  return at(startup) ? null : startup;   // don't know yet
if (!signedIn)       return at(signIn)  ? null : signIn;    // know: signed out
if (at(signIn) || at(startup)) return dashboard;            // signed in, move on
return null;                                                // signed in, carry on
```

Two things to notice.

**The loading branch comes first.** This is lesson 02's `AsyncLoading` vs `AsyncData(null)` distinction, cashed out. Without it, every cold start would show the login screen for a moment before the restored session arrived.

**Every branch is `location == target ? null : target`.** A redirect that returns a location which itself redirects is an infinite loop, and `go_router` throws. Always allowing the target location is what terminates it.

## Making the router react to auth

`redirect` runs on navigation. But signing out is not navigation — nobody tapped a link, a *stream emitted*. Something must tell the router to re-evaluate.

`GoRouter` takes a `refreshListenable`. It re-runs `redirect` whenever that `Listenable` notifies. Auth state is a Riverpod `AsyncValue`, not a `Listenable`, so `routerProvider` bridges the two with a `ValueNotifier`:

```dart
final authState = ValueNotifier<AsyncValue<User?>>(const AsyncValue.loading());

ref.listen(authStateChangesProvider, (prev, next) => authState.value = next,
           fireImmediately: true);
ref.onDispose(authState.dispose);
```

`ref.listen` (not `watch`) because this is a side effect, not a rebuild. `fireImmediately: true` seeds the current value instead of waiting for the next change. `ref.onDispose` because a `ValueNotifier` must be disposed.

**The payoff:** nothing in the app navigates after signing in or out. `SettingsScreen` calls `signOut()` and stops. Firebase emits `null` → the notifier notifies → `redirect` re-runs → the login screen appears. Navigation is a *consequence* of state, in exactly one place.

Look at `_run` in `login_screen.dart` and notice what is missing: no `context.go('/')` on success. It is not an oversight.

## `StatefulShellRoute` — tabs that remember

Four tabs, each keeping its own scroll position and navigation stack when you switch away and back.

A plain `IndexedStack` of screens keeps the widgets alive but gives them no `Navigator` of their own, so pushing a detail screen from inside a tab covers the tab bar. `StatefulShellRoute.indexedStack` gives each **branch** its own `Navigator`:

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
  branches: [ StatefulShellBranch(routes: [...]), ... ],
)
```

The `StatefulNavigationShell` handed to the builder **is** the tab state — it knows the current index and how to switch. `AppShell` stores nothing itself; it renders the shell and calls `goBranch(index)`.

`goBranch(index, initialLocation: index == currentIndex)` gives the standard behaviour where tapping the tab you are already on pops that branch back to its root.

## One shell, two layouts

`AppShell` uses `LayoutBuilder` to read the available width and picks `NavigationBar` (bottom tabs) below 600dp or `NavigationRail` (sidebar) above it — the mobile and desktop presentations from the mockups. Same routes, same branches, same state; only the chrome differs.

`LayoutBuilder` gives the constraints *this widget* received, not the window size, so it stays correct in a split view or a resized desktop window.

---

## What to notice in the code

- **`app/lib/core/router/app_router.dart`** — the whole navigation system in one file. Read `redirect` top to bottom and check each branch against the table above; find the `ValueNotifier` bridge and ask why `ref.listen` rather than `ref.watch`.
- **`app/lib/features/auth/presentation/login_screen.dart`** — `_run` has no navigation. Sit with that until it feels right rather than missing.
- **`app/lib/features/settings/presentation/settings_screen.dart`** — `_confirmSignOut` ends at `signOut()`. The comment above it spells out the chain.
- **`app/lib/features/shell/presentation/app_shell.dart`** — one `_destinations` list, two layouts, no state.
- **`app/lib/features/startup/presentation/startup_screen.dart`** — a whole screen that exists purely to represent "we don't know yet".
- **`app/lib/main.dart`** — `MaterialApp.router` with `routerConfig`, not the plain `MaterialApp` constructor. That is what hands navigation to go_router.

**Next:** [04 — Firebase Auth and Firestore rules](04-firebase-auth-and-firestore-rules.md).
