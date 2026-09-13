# Product Requirements Document (PRD)

**Project:** Zavithar Manager — personal finance & productivity app
**Owner/single user:** Zavithar
**Status:** Draft v1 — living document, updated as decisions are made
**Last updated:** 2026-08-20

## 1. Purpose

A single, real-time-synced personal app to track finances (transactions, savings, liabilities) and manage a categorized todo list with deadlines and push reminders, usable interchangeably on an Android phone and a Windows desktop with the same data reflected live on both.

## 2. Goals

- One source of truth for personal finances and tasks, accessible from phone or desktop.
- Changes made on one device appear on the other within seconds, without manual refresh.
- Deadline-driven todos trigger real push notifications, even when the app is closed.
- Built and maintained by a single developer (the user), so simplicity and low maintenance overhead matter as much as functionality.

## 3. Non-goals (out of scope for v1)

- Multi-user accounts, sharing, or permissions (single-user only for now).
- Bank account linking / automatic transaction import (all entries are manual in v1).
- iOS support (Android + Windows desktop only for v1; other desktop OSes and iOS are future options, not required now).
- Advanced budgeting/forecasting features (covered only at a basic level; deeper budgeting is a Phase 4/"later" feature).

## 4. Users & context

Single user, using the app daily on both a phone (Android) and a Windows desktop, expecting the two to always show consistent, up-to-date data.

## 5. Functional requirements

### 5.1 Authentication
- FR-1: User can sign in with Google (via Firebase Auth), at no cost.
- FR-2: User can alternatively sign in with email/password if preferred.
- FR-3: Session persists across app restarts on each device.
- FR-4: Only the authenticated user's data is ever readable/writable (enforced via Firestore security rules).

### 5.2 Financial manager
- FR-5: User can create, edit, and delete transactions (amount, type income/expense, category, date, optional description/account).
- FR-6: User can view a list of transactions, filterable by date range and category.
- FR-7: User can create, edit, and delete savings goals (name, target amount, current amount, optional deadline) and see progress toward each.
- FR-8: User can create, edit, and delete liabilities (name, type, original amount, remaining amount, optional interest rate and due date).
- FR-9: User can view a summary/dashboard: current balance, income vs. expense for a period, savings progress, total liabilities.

### 5.3 Todo list
- FR-10: User can create, edit, delete, and complete todos (title, notes, category, deadline, priority).
- FR-11: Todos are organized into categories: hobbies, study, work, home (extensible list).
- FR-12: User can view/filter todos by category and by status (pending/in progress/completed).
- FR-13: User can create a follow-up task linked to a completed/existing task.
- FR-14: User can set a reminder time for a todo, separate from its deadline (e.g. "1 day before").

### 5.4 Notifications
- FR-15: User receives a push notification on both registered devices when a todo's reminder time is reached, even if the app is closed.
- FR-16: Notifications are delivered via Firebase Cloud Messaging, triggered by a scheduled server-side check (Cloud Function).

### 5.5 Cross-device real-time sync
- FR-17: Any create/edit/delete on transactions, savings, liabilities, or todos on one device is reflected on all other logged-in devices within a few seconds.
- FR-18: The app remains usable offline; changes made offline sync automatically once connectivity returns.

## 6. Non-functional requirements

- NFR-1 (Platforms): Android (phone) and Windows (desktop) as the v1 supported platforms, built from a single Flutter codebase.
- NFR-2 (Performance): Real-time updates should be reflected across devices within ~2-3 seconds under normal connectivity.
- NFR-3 (Availability/offline): Core read/write functionality (excluding push notifications) works offline via Firestore's local cache.
- NFR-4 (Security): Data is private to the single authenticated user; no data is publicly readable. No plaintext secrets committed to source control.
- NFR-5 (Cost): The app should run within Firebase's free tier (Spark plan) for a single user's usage volume.
- NFR-6 (Maintainability): Solo-developer-friendly — minimal custom backend code, relying on managed Firebase services wherever possible.
- NFR-7 (Usability): Usable one-handed on mobile for quick entry (e.g. logging a transaction or adding a todo in under 10 seconds).

## 7. Success criteria

- Both devices, logged into the same account, show identical data at all times (validated per the "definition of done" in the roadmap doc).
- A todo with a reminder produces a push notification on both devices without the app being open.
- The user can fully replace any spreadsheet/notes app they were previously using for finances and todos.

## 8. Assumptions & dependencies

- User has a Google/Firebase account and is comfortable with a free-tier Firebase project.
- Windows is the primary desktop target for v1; macOS/Linux are future additions enabled by Flutter's multi-desktop support.
- No dedicated design tool (e.g. Figma) is used — mockups are produced as interactive HTML/CSS prototypes instead.

## 9. Related documents

- `architecture.md` — technical architecture and stack.
- `data-model.md` — Firestore data structures.
- `feature-roadmap.md` — original phased feature roadmap.
- `work-plan.md` — master project plan across all 7 delivery phases.
- `development-plan.md`, `testing-plan.md`, `deployment-plan.md`, `maintenance-plan.md` — detailed plans per phase.
