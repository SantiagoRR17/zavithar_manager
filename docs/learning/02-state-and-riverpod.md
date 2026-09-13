# 02 — State, and why Riverpod

*Follows [01 — How Flutter works](01-how-flutter-works.md).*

---

## The problem `setState` cannot solve

Lesson 01 covered state that belongs to one widget. But most state in this app does not:

- **who is signed in** — the router needs it, the settings screen needs it, and it outlives every screen;
- **the list of transactions** — a Firestore stream that several screens read;
- **the repositories themselves** — one instance, shared.

You could hoist it into a `StatefulWidget` near the root and pass it down through constructors. That is "prop drilling": widgets in the middle take parameters they do not use, only to hand them to a child. Add a field and five files change.

Flutter's built-in answer is `InheritedWidget` — put a value in the tree, let descendants find it with `.of(context)`. It works, and it is what `Theme.of(context)` uses. But writing one by hand is verbose, you need a `BuildContext` to read anything, and there is no help with the thing this app does constantly: **subscribing to a stream**.

## What a provider is

A provider is **a declaration of where a value comes from**. Not the value — the recipe for it.

```dart
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);
```

Three properties fall out of that:

1. **Lazy** — nothing runs until something reads it.
2. **Cached** — created once, then reused. Every reader gets the same instance.
3. **Disposed** — when nothing is watching any more, it is cleaned up (streams cancelled, controllers closed).

Providers are declared as top-level `final` variables. Global-looking, but not globals: the actual state lives in a `ProviderScope` widget, which is why `main.dart` wraps the app in one. That indirection is what makes them overridable in tests.

## read vs watch

Inside a widget you get a `ref`:

- **`ref.watch(p)`** — read the value *and subscribe*. When it changes, this widget rebuilds. Use in `build`.
- **`ref.read(p)`** — read once, no subscription. Use in callbacks (`onPressed`) and other one-shot code.
- **`ref.listen(p, cb)`** — do not rebuild; run a side effect when it changes. For things that are not UI: showing a snackbar, or waking up the router.

The rule of thumb: **`watch` in `build`, `read` in callbacks.** Watching in a callback subscribes at a strange moment; reading in `build` means the UI silently stops updating.

Providers use the same `ref` to depend on each other, and the dependency graph updates automatically:

```dart
final authStateChangesProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);
```

## `AsyncValue` — the reason Riverpod was chosen

Async data is always in one of three states. `AsyncValue<T>` makes that a *type*:

- `AsyncLoading()` — no answer yet
- `AsyncError(error, stackTrace)` — it failed
- `AsyncData(value)` — here it is

`StreamProvider<User?>` gives you `AsyncValue<User?>`, and you unpack it with `.when`:

```dart
authState.when(
  loading: () => const CircularProgressIndicator(),
  error:   (e, st) => Text('Could not load: $e'),
  data:    (user) => Text(user?.email ?? 'signed out'),
)
```

All three callbacks are required. **That is the point.** `CLAUDE.md` says every stream-backed screen must have explicit loading and error states — with `.when`, forgetting is a compile error rather than a code-review catch. The convention enforces itself.

### The distinction that actually bit us

`AsyncLoading()` and `AsyncData(null)` are *different*, and conflating them causes a real, visible bug.

At cold start, Firebase reads the saved session from disk. Until that finishes, auth state is `AsyncLoading()` — **"we don't know yet."** Once it finishes with nobody signed in, it becomes `AsyncData(null)` — **"we know, and nobody is."**

Treat "don't know yet" as "signed out" and every launch flashes the login screen at a signed-in user before snapping to the dashboard. That is exactly why `StartupScreen` exists. A plain `User?` cannot express the difference; `AsyncValue<User?>` can.

### Riverpod 3 note

The nullable accessor is **`.value`**. `valueOrNull` existed in Riverpod 2 and is **gone** — most tutorials online still use it and will not compile. `requireValue` is the one that throws if there is no data.

## The layers

```
Widget            ConsumerWidget, watches a provider, renders AsyncValue
   │
Provider          caches, wires dependencies, disposes
   │
Repository        the ONLY code that talks to Firebase
   │
Firebase
```

The repository boundary is a project rule (`CLAUDE.md`). It exists so Firebase's types and error codes never leak into widgets — `AuthRepository` catches `FirebaseAuthException` and rethrows `AuthFailure` with a human-readable message, so no screen has to know what `invalid-credential` means.

It also makes tests possible without a network:

```dart
ProviderScope(
  overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
  child: const ZavitharManagerApp(),
)
```

Everything downstream picks up the fake, because everything downstream depends on that one provider.

## Consumer widgets

Three flavours, and the difference is only how you get `ref`:

| Instead of | Use | `ref` arrives as |
|---|---|---|
| `StatelessWidget` | `ConsumerWidget` | second argument to `build` |
| `StatefulWidget` | `ConsumerStatefulWidget` + `ConsumerState` | a field, available everywhere including `initState` |
| a subtree of an existing widget | `Consumer(builder: (context, ref, child) => …)` | builder argument |

`Consumer` is the surgical option: wrapping just the part that depends on a provider means only that part rebuilds.

---

## What to notice in the code

- **`app/lib/features/auth/application/auth_providers.dart`** — the reference example, three providers in twenty lines: a plain `Provider` for the repository, a `StreamProvider` over its stream, and a derived `Provider` on top. Note `currentUserProvider` uses `.value`, not `valueOrNull`.
- **`app/lib/features/auth/data/auth_repository.dart`** — the whole Firebase surface, in one class. `_messageFor` is the translation layer: Firebase error codes in, sentences in, and nothing above ever sees a `FirebaseAuthException`. Note it holds **no state** — the state is the stream.
- **`app/lib/features/settings/presentation/settings_screen.dart`** — `ConsumerWidget` with the extra `ref` argument, `.when` handling all three states, and `ref.read` (not `watch`) inside the sign-out callback.
- **`app/lib/features/auth/presentation/login_screen.dart`** — the mix in one file: local `setState` state for the form, `ref.read` for actions. Both kinds of state, each in the right place.
- **`app/lib/main.dart`** — `ProviderScope` wrapping everything. Without it, the first `ref.watch` throws.

**Next:** [03 — Routing and the auth gate](03-routing-and-the-auth-gate.md).
