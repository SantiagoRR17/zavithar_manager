# ADR 0008 — `firebase_options.dart` and `google-services.json` are committed

**Status:** Accepted · 2026-08-23

## Context

`flutterfire configure` generates two files that contain a string called `apiKey`:

- `app/lib/firebase_options.dart`
- `app/android/app/google-services.json`

The word "key" invites the reflex to gitignore them. NFR-4 says no plaintext secrets in source control, so the question has to be answered rather than assumed.

## Decision

**Both files are committed.** `.gitignore` says so explicitly, in a section headed "NOT ignored, deliberately", so nobody re-litigates it in six months.

## Rationale

A Firebase Web/Android API key is an **identifier, not a credential**. It says *which project* a request is for. It grants nothing. Every Android app ships it inside the APK, where anyone can read it with `unzip`; treating it as secret would be theatre.

What actually protects the data is:

1. **Firestore security rules** (`firestore.rules`) — no request reads or writes anything unless `request.auth.uid` matches the owning user. Someone holding the API key and no session gets nothing.
2. **Firebase Auth** — a valid session requires signing in as the account.
3. **SHA-1 fingerprint registration** — Google sign-in on Android only works for an APK signed with a registered certificate.

Google documents this directly: *"Firebase API keys are safe to include in code or checked-in config files."*

Not committing them has a real cost: the project stops being clone-and-run, and every new machine needs a manual `flutterfire configure` before it builds.

## What *is* secret, and stays out

- **Service account JSON** (`*-firebase-adminsdk-*.json`) — full admin access, bypasses all security rules. Gitignored.
- **Android signing keystores** (`*.jks`, `*.keystore`, `key.properties`) — leaking them lets someone ship an update as you.
- **`.env` files** with any third-party API keys.

## Consequences

If the repository ever becomes public, this decision stands — but the security rules become the *only* thing standing between the internet and the data, which raises the bar for reviewing every rules change. Worth re-reading this ADR at that point.
