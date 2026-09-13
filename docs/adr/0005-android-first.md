# ADR 0005 — Android first; Windows declared but not built yet

**Status:** Accepted · 2026-08-22

## Context

`CLAUDE.md` lists Milestone 0 as done when sign-in works **on both Android and Windows**. Two things got in the way.

1. **Toolchain.** Building Flutter for Windows needs MSVC. `flutter doctor` reports Visual Studio Build Tools 2022 17.14 installed but *incomplete* — the "Desktop development with C++" workload is missing. Adding it is a multi-GB download through the Visual Studio Installer GUI, and cannot be scripted from here.

2. **Platform gaps found while researching the stack** (these are facts about the packages, not preferences):
   - FlutterFire on Windows is **beta**, documented as "local development workflows only".
   - `google_sign_in` has **no Windows implementation** → Windows must sign in with email/password.
   - `firebase_messaging` has **no Windows implementation** → FCM cannot reach the desktop at all. This directly contradicts FR-15 ("push on both devices with the app closed"). See [ADR 0006](0006-defer-firebase-messaging.md).

## Decision

Build and verify **Android first**. Keep Windows as a declared Flutter build target from day one (`flutter create --platforms=android,windows`), and write all code platform-agnostically, but do not treat a Windows build as a Milestone 0 blocker.

Milestone 0 closes on Android. Windows is verified as a follow-up once the C++ workload is installed.

## Consequences

**Good**

- No multi-GB toolchain install standing between the project and its first running build.
- Because Windows is a declared target from the start, enabling it later is `flutter build windows`, not a project restructure.
- The platform gaps are handled in code rather than discovered later: `AuthRepository.supportsGoogleSignIn` returns false off Android, and the login screen hides the Google button and falls back to email/password (FR-2).

**Bad / accepted**

- Milestone 0's stated "done when" is only half-met until Windows is verified. Recorded honestly rather than redefined.
- Windows-only bugs will be found late.
- FR-15 remains **unresolved** for the desktop. It needs a decision before Milestone 3 — likely a local scheduled check while the app runs, or accepting phone-only push.

## Also worth knowing

Building Flutter apps with plugins on Windows requires **Developer Mode** enabled (`start ms-settings:developers`), for symlink support. `flutter pub get` warns about this even on an Android-only workflow.
