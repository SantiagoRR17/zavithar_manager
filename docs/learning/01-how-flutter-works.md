# 01 — How Flutter works

*Prerequisite for everything else. Read this before `02-state-and-riverpod.md`.*

---

## The one idea

Most UI toolkits give you *objects you mutate*: you make a button, keep a pointer to it, and later call `button.setText("Saved")`. The screen is a long-lived tree of mutable objects, and your job is to keep it in sync with your data.

Flutter inverts that. You write a **function from state to UI**, and when the state changes Flutter calls it again and works out the difference itself. You never say "change this label" — you say "given this data, the screen looks like *this*", and say it again with new data.

```
data ──build()──> description of the UI ──Flutter──> pixels
```

Everything below follows from that.

## Widgets are descriptions, not the thing on screen

A `Widget` is a lightweight, **immutable** description — a recipe, not a cake. Flutter creates and throws away thousands per second, which is fine because they are just configuration objects.

Behind them sit **Elements**, the long-lived tree Flutter actually maintains, and **RenderObjects**, which do layout and painting. When `build()` returns a new widget tree, Flutter walks it against the existing Element tree and updates only what genuinely differs. That diffing is why rebuilding "the whole screen" is cheap.

You will almost never touch Elements or RenderObjects. But knowing they exist explains the vocabulary: a widget is *created* constantly; an element is *updated*.

**Composition, not inheritance.** There is no `Button` class with forty properties. There is `Padding` wrapping `Center` wrapping `Text`. Deeply nested trees are normal and idiomatic — the nesting *is* the layout. Reading `app/lib/features/auth/presentation/login_screen.dart` will feel like a lot of indentation; that is Flutter working as designed, not a smell.

## `const` matters more than usual

`const Text('Dashboard')` is built once at compile time and reused for the life of the program. When Flutter diffs and sees the identical `const` instance, it skips that subtree entirely.

This is why the codebase is scattered with `const`, and why the linter nags about it. It is a real performance mechanism, not style.

## Stateless vs Stateful

**`StatelessWidget`** — everything it needs comes in through its constructor. Given the same inputs it always builds the same output. Most widgets are this. `DashboardScreen`, `AppShell`, `MilestonePlaceholder`.

**`StatefulWidget`** — owns data that changes over time *and belongs to this widget alone*. It comes in two classes: the widget (immutable, may be recreated constantly) and a `State` object (persists across rebuilds, holds the mutable fields).

Changing a field does nothing on its own. You must wrap it:

```dart
setState(() => _isBusy = true);
```

`setState` marks this element dirty; Flutter schedules a rebuild for the next frame. Assigning `_isBusy = true` without `setState` changes the variable and leaves the screen showing the old value — a classic first bug.

**The State lifecycle** you actually use:

| Method | When | What goes there |
|---|---|---|
| `initState()` | once, before the first build | start subscriptions, kick off one-time setup |
| `build()` | every rebuild | describe the UI, nothing else |
| `dispose()` | once, when removed for good | cancel subscriptions, dispose controllers |

`initState` / `dispose` must be symmetric. Every controller created must be disposed — a `TextEditingController` that outlives its screen is a leak. See the top and bottom of `_LoginScreenState`.

## Which widget owns which state

The rule this project follows:

- **Local, throwaway, nobody else's business** → `StatefulWidget`. What is typed in a text field, whether a spinner is showing, which of two form modes is active.
- **Shared, or outlives the screen, or comes from outside** → a provider (lesson 02). Who is signed in, the list of transactions.

`LoginScreen` is stateful because "what is typed in the password box" should genuinely vanish when the screen does. "Who is signed in" must not — so it lives in a provider.

## `BuildContext`

Every `build` receives a `BuildContext`: a handle to *this widget's position in the tree*. Its job is looking upward — `Theme.of(context)`, `Navigator.of(context)`, `ScaffoldMessenger.of(context)` each walk up until they find the nearest ancestor of that type.

That upward lookup is how the theme reaches every widget without being passed down by hand. It is also why theming properly (`app/lib/core/theme/app_theme.dart`) pays off: configure once at the top, and widgets far below get it for free.

Two traps:

- A context is only valid where it sits. Using a context from *above* a `Scaffold` to find that `Scaffold` fails.
- **After an `await`, a context may be dead** — the widget can have been removed while you waited. Hence `if (!mounted) return;` before touching `context` or calling `setState` in an async method. Every async path in `_LoginScreenState` does this.

## Async, and why the UI never blocks

Dart runs your code on a single thread. A long synchronous operation freezes the UI — there is no other thread to draw the next frame.

So anything slow is asynchronous:

- **`Future<T>`** — one value, later. `await` it.
- **`Stream<T>`** — many values over time. This is the important one here: `FirebaseAuth.authStateChanges()` and Firestore's `snapshots()` are both streams, and they are exactly why the app is real-time. You do not poll for changes; the change arrives.

## Hot reload

Save a file and the running app picks up the new code in under a second, **keeping its current state** — same screen, same text in the fields.

- **Hot reload** (`r`, or save in an IDE) — re-runs `build`, keeps state. Use constantly.
- **Hot restart** (`R`) — restarts the app, loses state. Needed after changing `main()`, a global variable's initialiser, or anything in `initState` you want to re-run.
- **Full restart** — needed after changing native code or adding a plugin (`flutter pub add`).

If an edit "doesn't take", it is nearly always a case that needed a restart rather than a reload.

---

## What to notice in the code

Open these and look for the ideas above:

- **`app/lib/main.dart`** — `runApp` takes a widget and that is the entire app. Note the two `await`s *before* it: Firebase must be initialised before anything asks for auth state.
- **`app/lib/features/dashboard/presentation/dashboard_screen.dart`** — a minimal `StatelessWidget`: inputs in, description out, no state at all.
- **`app/lib/features/auth/presentation/login_screen.dart`** — the stateful counterpart. Find:
  - the three private fields (`_isBusy`, `_isRegistering`, `_errorMessage`) — local state that should die with the screen;
  - `dispose()` releasing both `TextEditingController`s;
  - `if (!mounted) return;` after every `await` in `_run`;
  - `_run` itself, which has **no "navigate on success" step** — that is lesson 03.
- **`app/lib/features/shell/presentation/app_shell.dart`** — `LayoutBuilder` giving the available width, and one widget describing two different layouts from it. Composition doing the work.
- **`app/lib/core/theme/app_theme.dart`** — configure once at the top; `Theme.of(context)` delivers it everywhere below.

**Next:** [02 — State and Riverpod](02-state-and-riverpod.md).
