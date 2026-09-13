# Feature Spec & Roadmap

## Phase 0 — Project setup
- Create Firebase project (Firestore, Auth, Cloud Messaging, Functions enabled).
- Set up Flutter project targeting Android + one desktop OS first (whichever you use daily), add the other desktop platforms later since Flutter makes that mostly free.
- Wire up Firebase Auth (single account, email/password or Google sign-in).
- Set Firestore security rules scoped to the authenticated user.

## Phase 1 — MVP: Financial manager
- Add/edit/delete transactions (amount, category, date, type).
- List/filter transactions by date range and category.
- Savings goals: create a goal, update current amount, see progress.
- Liabilities: create/track a liability, update remaining balance.
- Simple dashboard: total balance, monthly income vs expense, savings progress bars.
- Real-time verification: confirm a transaction added on phone appears instantly on desktop and vice versa.

## Phase 2 — MVP: Todo list
- Add/edit/delete todos with title, category (hobbies/study/work/home), deadline, priority.
- Filter/group todos by category and by status.
- Mark complete / follow-up task creation (linking a new task to a completed one).
- Real-time verification across devices, same as Phase 1.

## Phase 3 — Notifications
- Register device FCM tokens on login (per device).
- Cloud Function: scheduled check for upcoming deadlines/reminders → send push.
- Local notification handling in-app (foreground) and via FCM (background/closed).
- Test on both Android and desktop.

## Phase 4 — Polish & extras
- Recurring transactions (e.g. monthly rent, subscriptions).
- Budgets per category with alerts when close to/over budget.
- Charts: spending by category, net worth over time, savings trend.
- Custom/editable todo categories instead of a fixed list.
- Data export (CSV) for transactions.
- Dark mode / theming, since this will be checked daily on two devices.

## Suggested build order rationale

Finance and todos are independent modules sharing only the app shell, auth, and real-time infrastructure — so Phase 1 and Phase 2 can be built and tested somewhat in parallel, or one fully before the other, without blocking each other. Notifications are deliberately last because they depend on todos already existing and are the most "infrastructure-heavy" piece (Cloud Functions, scheduling, FCM setup on two platforms) — better to validate the core data model and real-time sync first before adding that complexity.

## Definition of "done" for the real-time requirement

At the end of Phase 2, this should hold: with the app open on both an Android device and a desktop machine, logged into the same account, any add/edit/delete to a transaction, savings goal, liability, or todo on one device appears on the other within a few seconds without manually refreshing.
