# Data Model (Firestore)

All collections live under a single user, e.g. `users/{uid}/...`, so security rules can simply check `request.auth.uid == uid`.

## Finance module

### `users/{uid}/transactions/{transactionId}`
- `amount` (number, > 0, always stored positive)
- `type` ("income" | "expense") — required
- `category` (string, e.g. "groceries", "rent", "salary") — required
- `description` (string, optional, max ~200 chars)
- `date` (timestamp) — required
- `account` (string, optional — e.g. "cash", "credit card", "savings" if you track multiple accounts)
- `createdAt` / `updatedAt` (timestamps, server-set)

### `users/{uid}/savings/{savingsGoalId}`
- `name` (string, required, 1-80 chars)
- `targetAmount` (number, > 0) — required
- `currentAmount` (number, >= 0, defaults 0)
- `deadline` (timestamp, optional)
- `createdAt` / `updatedAt`

### `users/{uid}/liabilities/{liabilityId}`
- `name` (string, required)
- `type` (string, e.g. "loan", "credit card", "mortgage") — required
- `originalAmount` (number, > 0) — required
- `remainingAmount` (number, >= 0) — required, should not exceed `originalAmount`
- `interestRate` (number, optional, 0-100)
- `dueDate` / `nextPaymentDate` (timestamp, optional)
- `minimumPayment` (number, optional, >= 0)
- `createdAt` / `updatedAt`

A dashboard/summary view (net worth, monthly spend vs income, savings progress) is computed client-side from these three collections rather than stored — it's derived data, not source of truth.

## Todo module

### `users/{uid}/todos/{todoId}`
- `title` (string, required, 1-120 chars)
- `notes` (string, optional, max ~1000 chars)
- `category` (string, one of: "hobbies" | "study" | "work" | "home" — extensible list) — required
- `status` ("pending" | "in_progress" | "completed") — required, defaults "pending"
- `deadline` (timestamp, optional)
- `reminderAt` (timestamp, optional — when to fire the push notification, may differ from deadline, e.g. "1 day before")
- `followUpOf` (todoId reference, optional — links a follow-up task to its parent task)
- `priority` (string, optional — "low" | "medium" | "high", defaults "medium")
- `createdAt` / `updatedAt` / `completedAt`

### `users/{uid}/categories/{categoryId}` (optional, if categories should be user-editable rather than a fixed enum)
- `name` (string, required)
- `color` (string, for UI)
- `icon` (string, optional)

## Notifications

### `users/{uid}/devices/{deviceId}`
- `fcmToken` (string, required) — registered per device (phone, desktop) so push notifications reach all of them
- `platform` ("android" | "desktop") — required
- `lastSeenAt` (timestamp)

A scheduled Cloud Function periodically scans `todos` for upcoming `reminderAt`/`deadline` values and sends FCM pushes to all tokens under `devices`.

## Validation strategy

Two layers, both needed:
1. **Client-side (Flutter forms):** required fields, numeric ranges, string length limits — for immediate user feedback.
2. **Firestore Security Rules:** the real enforcement layer, since client-side checks can be bypassed. Rules should validate types and required fields on write, not just ownership. Example sketch:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      match /{collection}/{docId} {
        allow read, write: if request.auth != null
                            && request.auth.uid == userId
                            && collection in ['transactions','savings','liabilities','todos','categories','devices'];
      }
    }
  }
}
```

This baseline (ownership check) ships in Phase 1; per-field type/range validation in rules is added incrementally as each module is built, since it's easy to tighten later without breaking existing data.

## Notes on real-time sync

Each device's Flutter app opens Firestore stream listeners (`snapshots()`) on the relevant collections (`transactions`, `savings`, `liabilities`, `todos`) scoped to the user. Any write from either device is pushed to all other listening devices within roughly a second, with no manual refresh needed. Firestore's offline cache means the app also works without connectivity and reconciles automatically once back online.

## Indexing notes

Composite indexes will be needed for combined filters, e.g. `todos` filtered by `category` + ordered by `deadline`, or `transactions` filtered by `type` + ordered by `date`. Firestore will surface a direct console link to create the exact index the first time such a query runs in development — no need to pre-guess every index up front.
