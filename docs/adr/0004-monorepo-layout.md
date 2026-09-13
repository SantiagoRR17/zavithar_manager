# ADR 0004 — Monorepo layout

**Status:** Accepted · 2026-08-22

## Context

The project has three kinds of artefact: a Flutter app, Cloud Functions (TypeScript, arriving at Milestone 3), and Firebase configuration that describes the backend the app talks to. Separate repositories would mean a rules change and the client change that depends on it land in two places, with no single commit that represents the working combination.

## Decision

One repository:

```
zavithar_manager/
├─ app/                   Flutter application
├─ functions/             Cloud Functions (empty until Milestone 3)
├─ firebase.json          Firebase CLI config
├─ firestore.rules        Security rules — the real enforcement layer
├─ firestore.indexes.json Composite indexes
├─ claude/                What we decided to build (PRD, architecture, plans)
└─ docs/                  What we actually built and why
```

Firebase config lives at the **root**, not inside `app/`, because it describes the backend both `app/` and `functions/` talk to — it belongs to neither.

## Consequences

**Good**

- A security-rules change and the client change that relies on it are one commit.
- `firebase deploy` runs from the root with no path juggling.
- One place to look.

**Bad / accepted**

- Two package managers in one tree (pub for `app/`, pnpm for `functions/`). Unavoidable given the stack; see [ADR 0007](0007-pnpm-only.md).
- Flutter commands must run from `app/`, not the root. Easy to forget.

## Note on `claude/` vs `docs/`

`claude/` is the intended design, written before building. `docs/` is the as-built record. When the two disagree, that disagreement is itself worth an ADR rather than a silent edit to `claude/`.
