# Architecture — as built

What actually exists in the repository. `claude/architecture.md` is the *intended* design; this file is the record of what was built, and it is updated as each milestone lands.

**Current state:** Milestone 0 (scaffolding). Auth, theme, routing and the app shell exist. No feature data yet.

---

## Repository

```
zavithar_manager/
├─ app/                     Flutter application (Android + Windows targets)
├─ functions/               Cloud Functions — empty until Milestone 3
├─ firebase.json            Firebase CLI config
├─ firestore.rules          Security rules — the real access-control layer
├─ firestore.indexes.json   Composite indexes (empty; added as queries need them)
├─ claude/                  What we decided to build (PRD, plans, data model)
└─ docs/                    What we built and why (this file, ADRs, lessons, devlog)
```

Firebase config sits at the root because it describes the backend that both `app/` and `functions/` talk to. See [ADR 0004](adr/0004-monorepo-layout.md).

## `app/lib/`

```
main.dart                              entry point: Firebase init, offline cache, ProviderScope
core/
  theme/app_colors.dart                every brand colour — the only file with hex literals
  theme/app_theme.dart                 ThemeData built from those tokens
  router/app_router.dart               go_router: routes, auth gate, tab shell
  widgets/milestone_placeholder.dart   "not built yet, arrives in Milestone N"
features/
  auth/
    data/auth_repository.dart          the only code that touches FirebaseAuth
    application/auth_providers.dart    Riverpod providers over it
    presentation/login_screen.dart     Google + email/password
  shell/presentation/app_shell.dart    bottom tabs (narrow) / sidebar (wide)
  startup/presentation/startup_screen.dart   shown while the session is restored
  dashboard/ finance/ todos/           placeholders — Milestones 1 and 2
  settings/presentation/settings_screen.dart account + sign out (real, not a placeholder)
```

### Why features, not layers

The alternative — `screens/`, `models/`, `repositories/` as top-level folders — spreads one feature across the tree, so building "transactions" means editing four distant directories. Grouping by feature keeps everything a milestone touches in one place, and makes it obvious what is finished.

Inside a feature, three layers, always in this order:

```
presentation/   widgets. Never imports Firebase.
application/    Riverpod providers. Wires data to presentation.
data/           repositories. The only code that talks to Firebase.
```

`core/` holds what genuinely crosses features: theme, routing, shared widgets.

## The data flow

```
Firestore ──stream──> Repository ──> StreamProvider ──> ConsumerWidget
                        (data/)      (application/)      (presentation/)
```

One direction, one rule: **UI never talks to Firestore directly** (`CLAUDE.md`). The repository boundary is what makes Firebase's error types and query syntax stay out of widgets, and what makes widget tests possible without a network — override one provider and everything downstream uses the fake.

## Auth and navigation

`FirebaseAuth.authStateChanges()` is the single source of truth for who is signed in. It flows through `AuthRepository` → `authStateChangesProvider` → a `ValueNotifier` inside `routerProvider` → go_router's `redirect`.

Consequence: **no screen navigates after signing in or out.** State changes; the router reacts. See [ADR 0003](adr/0003-go-router-and-the-auth-gate.md) and [lesson 03](learning/03-routing-and-the-auth-gate.md).

Route table:

| Path | Screen | Gate |
|---|---|---|
| `/startup` | `StartupScreen` | while auth state is loading |
| `/sign-in` | `LoginScreen` | signed out |
| `/` | `DashboardScreen` | signed in — tab 1 |
| `/finance` | `FinanceScreen` | signed in — tab 2 |
| `/todos` | `TodosScreen` | signed in — tab 3 |
| `/settings` | `SettingsScreen` | signed in — tab 4 |

The four tabs are branches of a `StatefulShellRoute.indexedStack`, so each keeps its own navigation stack and scroll position.

## Theming

`AppColors` holds every hex value in the project; `AppTheme.dark` turns them into a `ThemeData` with an explicitly pinned `ColorScheme`. Because the theme is configured properly once, individual widgets almost never name a colour — which is what keeps the "one file for colours" rule practical.

Dark only. A light theme is Milestone 4.

## Platform differences

| | Android | Windows |
|---|---|---|
| Firestore, Auth | yes | yes (FlutterFire on Windows is beta) |
| Google sign-in | yes | **no plugin** → email/password |
| FCM push | yes | **no plugin** → unresolved, see below |
| Build status | working | not built yet — needs the MSVC C++ workload |

`AuthRepository.supportsGoogleSignIn` is the single place that check lives; the login screen hides the Google button when it is false.

## Known gaps

- **Windows is unverified.** Declared as a build target, never compiled. [ADR 0005](adr/0005-android-first.md).
- **FR-15 vs Windows.** Push on both devices with the app closed is required; `firebase_messaging` has no Windows implementation. Needs a decision before Milestone 3.
- **NFR-5 vs FR-16.** "Runs on the Spark free tier" versus Cloud Functions, which have required Blaze since Feb 2026. Blaze is $0 within the free quota but needs a card. Also a Milestone 3 decision.
- **Security rules are ownership-only.** No field type or range validation yet — deliberate, tightened per module (`claude/data-model.md`).
- **Deep-link continuation is not implemented.** The router can express "sign in, then continue to where you asked for", but nothing does it yet — there is nothing to link to until Milestone 2.
