# Zavithar Manager

A single-user, real-time-synced personal app: **financial manager** (transactions, savings goals, liabilities) and **todo list** (categorized tasks with deadlines, reminders, and push notifications).

Used interchangeably on **Android** and **Windows**, with both devices always showing the same live data. That real-time cross-device sync is the core requirement everything else is designed around.

**Stack:** Flutter (Android + Windows) · Cloud Firestore · Firebase Auth · FCM · Cloud Functions
**Owner:** Zavithar — single user, no multi-user/sharing in v1.

---

## Current status

**Milestone 0 — Scaffolding.** Complete on Android; Windows deferred.

Signing in with Google on the phone lands on the app shell, and the session survives a full restart. Firebase project, Firestore and the security rules are live. Windows is a declared build target but has not been compiled yet — it needs Visual Studio's "Desktop development with C++" workload ([ADR 0005](docs/adr/0005-android-first.md)).

| Milestone | Status |
|---|---|
| 0. Scaffolding | ✅ Done (Android) · Windows deferred |
| 1. Financial manager | ⬜ Not started — next up |
| 2. Todo list | ⬜ Not started |
| 3. Notifications | ⬜ Not started |
| 4. Polish | ⬜ Not started |

---

## Repository layout

```
zavithar_manager/
├─ CLAUDE.md      Quick-reference brief for any Claude Code session or developer
├─ app/           The Flutter application (Android + Windows)
├─ functions/     Cloud Functions — scheduled reminder pushes (empty until Milestone 3)
├─ claude/        Project source-of-truth docs: PRD, architecture, data model, plans
└─ docs/          Docs produced while building
   ├─ setup.md       Reproducible from-zero environment setup
   ├─ architecture.md  As-built structure (claude/architecture.md is the intended design)
   ├─ adr/           Architecture Decision Records — why things are the way they are
   ├─ devlog/        Build journal, one entry per working session
   └─ learning/      Numbered lessons on the concepts behind the code
```

`claude/` holds **what we decided to build**. `docs/` holds **what we actually built and why**. When the two disagree, that disagreement is itself worth an ADR.

---

## Getting started

Full, reproducible setup — including installing Flutter from scratch — is in **[docs/setup.md](docs/setup.md)**.

Once the toolchain is in place:

```bash
cd app
flutter pub get
flutter run -d android     # or: flutter run -d windows
```

---

## Learning track

This project doubles as a structured way to learn mobile development. Concepts are written up in `docs/learning/` *before or alongside* the code that uses them, and each lesson ends by pointing at the real files in this repo where the concept appears.

Start at [docs/learning/01-how-flutter-works.md](docs/learning/01-how-flutter-works.md).

---

## Conventions

- **UI never talks to Firestore directly** — a thin repository per collection sits in between.
- **Every stream-backed screen has explicit loading and error states** from the start, not retrofitted.
- **Colors live in exactly one place** (`app/lib/core/theme/app_colors.dart`). No hex literals anywhere else.
- **Status colors always pair with an icon or text label** — never color alone.
- **Category colors have a fixed order** and are never reassigned or cycled.
- Feature branch per milestone, small commits.
