# 04 — Firebase Auth, and why security rules are the real app

*Follows [03 — Routing and the auth gate](03-routing-and-the-auth-gate.md).*

---

## There is no backend

That is the thing to internalise first. The Flutter app talks **straight to Firestore** over the network. There is no server of yours in between validating anything.

```
Android app  ─┐
              ├─→  Firestore  ←── security rules decide every read and write
Windows app  ─┘
```

So every check you write in Dart is a *convenience*. Anyone can take the API key out of the APK and talk to your database with `curl`. The only thing that actually stops them is `firestore.rules`.

Two consequences worth holding onto:

1. **Client-side validation is for the user, not for safety.** It tells them the password is too short before a network round trip. It stops nobody.
2. **A bug in `firestore.rules` is a data breach**, not a display glitch. It deserves the care you would give backend code, because it *is* the backend.

## Two identity systems, not one

Google sign-in involves two systems that are easy to conflate.

**`google_sign_in`** proves who the Google user is. It opens the account picker, talks to Google, and hands back an **ID token** — a signed statement from Google saying "this is the holder of that Google account".

**Firebase Auth** takes that token, verifies the signature, and mints **its own session** with its own user ID (`uid`).

That `uid` is what matters. It is what `request.auth.uid` refers to in the rules, and it is what `users/{uid}/...` is keyed on. The Google identity is just the front door.

```dart
final account = await _googleSignIn.authenticate();   // Google says who you are
final idToken = account.authentication.idToken;
await _firebaseAuth.signInWithCredential(              // Firebase issues a session
  GoogleAuthProvider.credential(idToken: idToken),
);
```

Email/password skips the first step — Firebase is both the identity provider and the session issuer. Same `uid` shape at the end, and the rest of the app cannot tell which was used. That is why FR-2's fallback works on Windows, where `google_sign_in` has no implementation at all.

### The SHA-1 thing

Google sign-in on Android only works if the certificate that signed the APK is registered in the Firebase console. Debug builds are signed with a per-machine debug keystore, so **its** SHA-1 must be registered too, or sign-in fails on a developer machine while working in release.

The failure mode is genuinely nasty: Android's Credential Manager reports a configuration error as **"cancelled"**, indistinguishable from the user backing out of the picker. The plugin's own README warns about this. If Google sign-in silently does nothing, suspect the fingerprint before anything else.

## Auth state is a stream, and it is never instant

`FirebaseAuth.authStateChanges()` emits the current user on subscribe, then on every sign-in, sign-out, and token refresh.

The word to underline is *stream*. At cold start, Firebase reads the persisted session from disk asynchronously. `FirebaseAuth.instance.currentUser` is `null` for a moment on launch **even when someone is signed in** — that is not a bug, it is the restore not having finished.

This is the same point lesson 02 made about `AsyncLoading` vs `AsyncData(null)` and lesson 03 made about `StartupScreen`. Three layers, one underlying fact: *you cannot read "who is signed in" as a value; you have to observe it over time.*

Session persistence is automatic — it is what satisfies FR-3 ("session persists across restarts"). No code required, but also no way to skip the async restore.

## Errors, and the one that is deliberately vague

`_messageFor` in `AuthRepository` maps Firebase error codes to sentences. Most are mechanical. One is a security decision:

```dart
'user-not-found' || 'wrong-password' || 'invalid-credential'
    => 'Incorrect email or password.',
```

Firebase deliberately collapses these into `invalid-credential` so that an attacker cannot use the login form to discover which email addresses have accounts. The message keeps that ambiguity. Splitting it into "no such user" / "wrong password" would be friendlier and would leak exactly what Firebase went out of its way to hide.

## Reading `firestore.rules`

```
match /users/{userId} {
  function isOwner() {
    return request.auth != null && request.auth.uid == userId;
  }

  allow read, write: if isOwner();

  match /{collection}/{docId} {
    allow read, write: if isOwner() && isKnownCollection(collection);
  }
}
```

- `{userId}` is a **wildcard that binds**: it captures the path segment, so `isOwner()` can compare it to the caller's `uid`.
- `request.auth` is `null` for unauthenticated callers — checking it first is what denies the anonymous internet.
- Everything is scoped under `users/{uid}/...` precisely so this one comparison is sufficient. That was a data-model decision made to keep the rules trivial; simple rules are ones you can actually verify.

**Why the collection allowlist?** Without it, an authenticated user could create any collection under their own document and use your Firebase project as free storage. There is exactly one legitimate user here, but the rule costs one line and closes the hole permanently.

**Rules are default-deny.** Anything not explicitly allowed is refused. The trailing `match /{document=**} { allow read, write: if false; }` is therefore redundant — it is there to state the intent out loud.

**Rules are not filters.** A query that *could* return a document the rules forbid fails entirely; it does not silently return fewer results. Queries have to be written so their results are provably within what the rules allow.

### Starting loose, tightening later

Milestone 0 ships ownership checks only — no field-type or range validation. That is deliberate (`claude/data-model.md`): rules are only evaluated on **new** reads and writes, never retroactively against stored data, so tightening them later is safe. Locking down fields before the data model has been exercised means fighting your own rules while building.

## Offline

`main.dart` turns on Firestore's local cache:

```dart
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

Reads are served from disk instantly, writes are queued while offline and replayed on reconnect. That is FR-18 and NFR-3 satisfied in four lines, and it is a large part of why Firebase was chosen at all ([ADR 0001](../adr/0001-flutter-and-firebase.md)).

The trade-off: a write that "succeeded" locally may still be rejected by the rules when it reaches the server. The optimistic local result appears first and is then rolled back. Worth remembering when Milestone 1 starts writing real data.

---

## What to notice in the code

- **`app/lib/features/auth/data/auth_repository.dart`** — the entire Firebase Auth surface. Follow `signInWithGoogle` and name the two systems at each line. Read `_messageFor` and find the deliberately vague branch. Notice `signOut` signs out of *both* Google and Firebase, and why.
- **`firestore.rules`** — short, and the most security-critical file in the repository. Read it as the actual backend.
- **`app/lib/main.dart`** — the offline cache settings, and the fact that `Firebase.initializeApp` is awaited before `runApp`.
- **`app/lib/features/auth/data/auth_repository.dart` → `supportsGoogleSignIn`** — the platform check that keeps the Google button off Windows, where the plugin does not exist ([ADR 0005](../adr/0005-android-first.md)).
- **`app/lib/firebase_options.dart`** — generated, and committed on purpose. [ADR 0008](../adr/0008-committing-firebase-config.md) explains why an "API key" here is not a secret.
