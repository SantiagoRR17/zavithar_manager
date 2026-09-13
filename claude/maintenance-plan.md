# Maintenance & Updates Plan

## Versioning
- Semantic-ish versioning in `pubspec.yaml` (e.g. `1.2.0`): major for big feature milestones, minor for smaller features, patch for fixes.
- Tag each release in git so any build can be traced back to exact source.

## Ongoing maintenance tasks
- Periodically update Flutter SDK and Firebase package dependencies (`flutter pub outdated`) — Firebase client libraries especially benefit from staying current.
- Watch for Firebase console warnings/deprecations (e.g. security rules syntax changes, SDK deprecations).
- Review Firebase usage dashboard monthly to catch unexpected read/write spikes (could indicate a bug causing excessive Firestore calls, e.g. a listener re-subscribing in a loop).

## Bug fixing workflow
1. Reproduce and note the issue (which device/platform, steps).
2. Fix on a branch, verify against `testing-plan.md`'s relevant checks (especially real-time sync if the fix touches data flow).
3. Release following `deployment-plan.md`'s release process.

## Backups
- Firestore data is the single source of truth — since this is personal financial data, periodically export it (Firestore's built-in export-to-Cloud-Storage, or a simple manual script) so there's a backup independent of the live database.

## Future feature intake
- New feature ideas get added to `feature-roadmap.md` (Phase 4 / "later" section) rather than built ad hoc, to keep the roadmap as the single place tracking what's planned vs. shipped.

## Review cadence
- No fixed schedule required for a personal solo project, but a good habit: after each milestone ships and has been used for a week or two, do a short retro — what worked, what's annoying in daily use, what to prioritize next — and update the roadmap accordingly.
