# Master Work Plan — Zavithar Manager

Formal project plan across all delivery phases. Milestone-based (no fixed calendar dates), single developer. This doc is the index — each phase links to its detailed doc.

## Phase 1 — Documentation & Requirements ✅
- `requirements.md` — PRD: goals, scope, functional & non-functional requirements, success criteria.
- `architecture.md` — tech stack and system architecture.
- **Status:** Complete (v1 draft).

## Phase 2 — Mockups ✅
- Interactive HTML/CSS prototype covering: Dashboard, Transactions, Savings & Liabilities, Todos, Add Todo, Notification preview — in both phone and desktop frames.
- Delivered as a file and persisted as a revisitable artifact.
- **Status:** Complete (v1 — will evolve as real screens are built).

## Phase 3 — Data structure & models ✅
- `data-model.md` — Firestore collections, field types/validation, baseline security rules, indexing notes.
- **Status:** Complete (v1 draft).

## Phase 4 — Development
- `development-plan.md` — 5 milestones: scaffolding → financial manager → todo list → notifications → polish.
- **Status:** Not started — ready to begin whenever you give the go-ahead.

## Phase 5 — Testing
- `testing-plan.md` — unit, widget/integration, manual real-time sync verification, notification testing, security rules testing, device matrix.
- **Status:** Plan complete; execution happens alongside each development milestone.

## Phase 6 — Deployment
- `deployment-plan.md` — dev/prod environments, Android APK + Windows build process, Firebase deploy steps, release checklist, cost monitoring.
- **Status:** Plan complete; execution starts after Milestone 0/1 of development.

## Phase 7 — Maintenance & updates
- `maintenance-plan.md` — versioning, dependency updates, bug-fix workflow, backups, feature intake process, review cadence.
- **Status:** Plan complete; ongoing once the app is in daily use.

## Key decisions on record
- **Client:** Flutter (single codebase) — Android + Windows desktop for v1.
- **Backend:** Firebase — Firestore (real-time sync), Auth (Google sign-in + email/password, both free), Cloud Messaging (push), Cloud Functions (scheduled reminder checks).
- **Users:** single-user app, no sharing/multi-account in v1.
- **Docs:** kept as living markdown docs in this project (not separate formal Word/PDF deliverables).
- **Mockups:** interactive HTML/CSS prototypes (no external design tool).
- **Timeline:** milestone-based, no fixed dates.

## Next decision point
Development (Phase 4) hasn't started yet. When you're ready, next step is Milestone 0 (project scaffolding: Firebase project + Flutter project setup) from `development-plan.md`.
