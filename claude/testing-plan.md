# Testing Plan

## Strategy overview

For a solo-built, single-user app, testing effort should concentrate where bugs are costly (data integrity, cross-device sync, notifications) and stay light where it isn't (pure UI polish).

## 1. Unit tests
- Repository layer functions (e.g. `TransactionsRepository.add`, `SavingsRepository.updateProgress`) — validate data shaping and calculations (e.g. savings percentage, monthly totals) with mocked Firestore.
- Pure calculation logic: balance calculation, budget vs actual, reminder-time computation (deadline minus offset).

## 2. Widget/integration tests (Flutter)
- Form validation: required fields, numeric ranges, on the Add Transaction and Add Todo forms.
- List rendering: transactions/todos list renders correctly given a fixed data set, filters apply correctly.
- Navigation: bottom-tab (mobile) and sidebar (desktop) navigation reach the right screens.

## 3. Manual real-time sync verification (critical, every milestone)
- Two devices (or one physical + one emulator/desktop build) logged into the same account.
- For each entity type (transaction, savings goal, liability, todo): create/edit/delete on Device A, confirm it appears on Device B within a few seconds without refresh.
- Test with one device offline: make a change offline, bring it back online, confirm it syncs.
- Record results against the "definition of done" in `feature-roadmap.md`.

## 4. Notification testing (Milestone 3)
- Create a todo with a reminder 1-2 minutes out; confirm push arrives on Android with app closed.
- Same test on Windows desktop.
- Confirm foreground in-app banner also works while the app is open.
- Confirm no duplicate notifications are sent (Cloud Function idempotency — mark-as-notified check).

## 5. Security rules testing
- Attempt to read/write another (test) user's data path directly — should be denied.
- Attempt writes missing required fields once field-level validation is added to rules — should be denied.
- Use the Firebase Emulator Suite locally to test rules before deploying.

## 6. Device/platform matrix
| Platform | Priority | Notes |
|---|---|---|
| Android phone | Required | Primary daily-use device |
| Windows desktop | Required | Primary desktop target |
| Android tablet | Nice-to-have | Layout should adapt but isn't a launch blocker |
| macOS / Linux desktop | Future | Only after Windows is stable |

## 7. Pre-release checklist (per milestone)
- All manual real-time sync checks pass.
- No console errors/exceptions during normal use flows.
- Offline mode doesn't crash the app.
- Firestore security rules deployed and verified (not just local).
