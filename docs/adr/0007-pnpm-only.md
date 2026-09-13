# ADR 0007 — pnpm only; npm is forbidden

**Status:** Accepted · 2026-08-23

## Context

Two parts of this project use the Node ecosystem: the **Firebase CLI**, installed globally, and **Cloud Functions** in `functions/` from Milestone 3 onward. Mixing package managers in one project produces two lockfiles that disagree, and "works on my machine" differences that are tedious to trace.

## Decision

**`pnpm` is the only Node package manager used in this project. `npm` is not to be used at all** — not `npm install`, not `npm run`, not `npm install -g`.

| Instead of | Use |
|---|---|
| `npm install -g firebase-tools` | `pnpm add -g firebase-tools` |
| `npm install` | `pnpm install` |
| `npm run <script>` | `pnpm <script>` |
| `npx <tool>` | `pnpm dlx <tool>` |

`pnpm-lock.yaml` is committed. A `package-lock.json` appearing anywhere in the tree means someone used npm; delete it and reinstall with pnpm rather than adding it to `.gitignore`.

## Consequences

**Good** — one lockfile format, one resolution algorithm, reproducible installs. pnpm's content-addressed store makes installs faster and far smaller on disk, which matters with Firebase Functions' large dependency tree. Strict `node_modules` layout means a package that forgot to declare a dependency fails immediately instead of accidentally working.

**Bad / accepted** — most Firebase and Flutter documentation is written with `npm` commands, so instructions need translating. Firebase's `firebase init functions` generates npm-flavoured scripts; they work under pnpm but the generated README does not mention it. Occasional packages assume npm's flat `node_modules`; `.npmrc` with `node-linker=hoisted` is the escape hatch if one ever does.

## Recorded in

`CLAUDE.md` → Engineering conventions, and a note in `.gitignore` next to the Node section.
