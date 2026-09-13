# ADR 0010 — Hardening for a public repository

**Status:** Accepted · 2026-09-13
**Supersedes nothing. Extends [ADR 0008](0008-committing-firebase-config.md).**

## Context

The project went under version control and onto a **public** GitHub remote on
2026-09-13. ADR 0008 anticipated exactly this and ended with an instruction:

> If the repository ever becomes public, this decision stands — but the security
> rules become the *only* thing standing between the internet and the data, which
> raises the bar for reviewing every rules change. Worth re-reading this ADR at
> that point.

This is that point. A full audit of the pushed history was run rather than a
targeted grep, because a commit is not a save: history keeps what you put in it,
and deleting a leaked value afterwards does not remove it.

## What the audit found

**Nothing confidential was leaked.** Checked across the full commit history, not
the working tree:

| Checked | Result |
|---|---|
| Email addresses, in content and in commit author/committer metadata | none — authors are the GitHub noreply address |
| Private keys (`BEGIN RSA`/`OPENSSH`), service-account JSON | none |
| Tokens (`ghp_`, `xox*`, `AKIA`, `sk-`, Bearer, refresh/access) | none |
| Passwords, SMTP/IMAP or any mail-account configuration | none — `password` only ever appears as a parameter name |
| URLs carrying credentials (`user:pass@`) | none |
| Keystores, `key.properties`, `local.properties` | not tracked |
| High-entropy strings | one, a pub package integrity hash in `pubspec.lock` |

The two deliberately committed Firebase files contain only public identifiers:
project number and id, storage bucket, app id, OAuth **client IDs** (not client
secrets), the debug certificate SHA-1 **fingerprint** (a hash, not a key), and
the Firebase API key. ADR 0008's reasoning holds for every one of them.

## The finding that mattered

ADR 0008 lists three things that protect the data: Firestore rules, Firebase
Auth, and SHA-1 registration. All three hold. But the list is incomplete, and the
gap only becomes obvious once the key is trivially discoverable:

**The Firebase API key was unrestricted, and account creation was open.**

Confirmed empirically rather than assumed — a REST call to
`identitytoolkit.googleapis.com/v1/accounts:signInWithPassword` carrying the
project's key, sent from a plain terminal with no app and no signed package,
returned `400 INVALID_LOGIN_CREDENTIALS`. A *400, not a 403*: the key was
accepted. Anything the key can reach, the internet can reach.

With email/password sign-in enabled (it is — it is the documented fallback to
Google sign-in), that meant anyone could call `accounts:signUp` and create an
account in the project. Such an account cannot read the owner's data — the rules
scope every path to `request.auth.uid` and that part is sound. But it *can* write
under its own `users/{uid}` subtree, because the Milestone 0 baseline rule allows
any authenticated user to do so in the known collections.

The consequence is not disclosure, it is **denial of service and cost**:
unlimited accounts using the project as free storage, exhausting the Spark plan's
daily write quota — which breaks the owner's own app — and becoming a bill once
Milestone 3 forces the upgrade to Blaze for Cloud Functions.

### The framing that matters

**Going public did not create this.** The API key ships inside the APK, where
anyone can read it with `unzip`; that is precisely why ADR 0008 says it is not a
secret. Publishing the repository lowered the cost of discovery from
"decompile an APK" to "open GitHub" — nothing more. **The gap was equally present
while the repository was private**, which is why the fix is required regardless
of visibility, and why making the repo private again would not have addressed it.

## Decision

1. **Account creation is disabled** in the Firebase console
   (Authentication → Settings → User actions → *Prevent account creation*).
   This is a single-user app whose only account already exists, so nothing is
   lost. Done 2026-09-13.
2. **The fix was verified by observing it reject**, not by trusting the checkbox.
   The same `accounts:signUp` call now returns `ADMIN_ONLY_OPERATION` and creates
   nothing. This project's own rule — a control that has never rejected anything
   is untested — applies to its own mitigations.
3. **Outstanding, in priority order:**
   - Restrict the API key in Google Cloud Console → Credentials (Android app
     restriction: package name + SHA-1, plus API restrictions).
   - **Firebase App Check** with Play Integrity — the defence Google designed for
     this. Natural fit alongside Milestone 3.
   - Verify the Firestore rules with the emulator and
     `@firebase/rules-unit-testing`. They are now the only access control there
     is, and they have still never been observed to reject anything. The Rules
     Playground cannot do this — see `docs/devlog/2026-09-13.md`.

## Consequences

- Adding a second user later means re-enabling sign-up, or creating the account
  from the console. Acceptable: v1 is explicitly single-user.
- Every future rules change is now a change to the only access control the
  project has. Review accordingly.
- The audit method is worth repeating before any future history rewrite or
  visibility change: scan the **pushed history**, not the working tree.
