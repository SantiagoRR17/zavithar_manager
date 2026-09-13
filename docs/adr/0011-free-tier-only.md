# ADR 0011 — The app stays free, so reminders are local notifications

**Status:** Accepted · 2026-09-13
**Amends [ADR 0001](0001-flutter-and-firebase.md) (Cloud Functions) and [ADR 0006](0006-defer-firebase-messaging.md).**

## Context

The owner set a hard constraint: **this app must never cost money — no paid
tier, under any circumstance.** Not "keep it cheap"; free.

That collides with something already in the stack and already flagged as an
unresolved conflict since 2026-08-23 (*"NFR-5 vs Cloud Functions needing
Blaze"*). `CLAUDE.md` describes Milestone 3 as:

> **Cloud Functions** — scheduled job that scans todos for due reminders and
> sends FCM pushes (this is what requires the app to notify even when closed).

**Cloud Functions require the Blaze plan.** Firebase removed them from the free
Spark plan in 2022 — they cannot be deployed without Blaze, and Blaze requires a
payment method on file. Blaze's free allowance is generous and the real bill
would almost certainly be zero, but "a card is attached and it can bill" is not
what the constraint says. The constraint wins.

Worth stating what the constraint *does not* break: Firestore, Auth and FCM are
all free on Spark. And Spark's failure mode is the one this project wants —
**exceeding quota stops the service for the day, it does not generate a
charge.** A hard ceiling, never an invoice.

## Decision

1. **No Cloud Functions. No Blaze. Ever, unless this ADR is superseded.**
2. **Milestone 3 reminders become on-device scheduled notifications**, via
   `flutter_local_notifications` and `zonedSchedule`. Each device schedules its
   own alarms by reading the todos Firestore has already synced to it.
3. **`firebase_messaging` is dropped rather than merely deferred.** ADR 0006 put
   it off until Milestone 3; with no server to send from, there is nothing for it
   to receive. If it never returns, ADR 0006 is closed rather than pending.
4. **`users/{uid}/devices/{id}` becomes dead schema.** Its only purpose was
   holding `fcmToken` values for a Cloud Function to send to. It stays in the
   rules allowlist for now (harmless, and cheaper than a rules redeploy to prove
   a point) but nothing writes to it, and it should be struck from
   `claude/data-model.md` if Milestone 3 confirms the approach.

## Rationale

The push architecture exists to solve "notify a user whose app is closed, from a
server that knows the schedule". Half of that problem does not exist here:

- **There is one user.** Nothing needs to be delivered *to someone else*, which
  is the case that genuinely requires a server.
- **The schedule is already on every device.** Todos sync through Firestore, so
  each device holds the `reminderAt` values it needs. A server scanning for due
  reminders would be re-deriving, remotely, something each device already knows.

An on-device alarm is therefore not a downgrade from the push design — for this
particular app it is a more direct expression of the same requirement, with a
server removed from the middle of it.

## Consequences, stated plainly

- **A device that has not opened the app since a todo was created has nothing
  scheduled.** Reminders are re-registered on launch and on every todo write, so
  in practice a device that gets opened occasionally stays current — but this is
  a real difference from a server that pushes regardless.
- **Android 13+ needs the `POST_NOTIFICATIONS` runtime permission**, and exact
  timing needs `SCHEDULE_EXACT_ALARM`. Without the latter, Doze can delay a
  reminder by an unpredictable amount. The permission prompt is part of
  Milestone 3, not an afterthought.
- **Dismissing a reminder on one device does not dismiss it on the other.**
  Acceptable for a single user; it would not be for a team app.
- **Windows behaviour is not equivalent** — `flutter_local_notifications`
  supports Windows, but scheduling while the app is closed is not the same
  mechanism. The Windows build is deferred anyway ([ADR 0005](0005-android-first.md));
  this is one more thing to verify when it lands, not a new blocker.
- **Cloud Storage is also Blaze-gated** for new projects. Nothing uses it today.
  If todo attachments are ever wanted, they are out of scope under this ADR.
- Re-check this ADR before adding any feature that wants a server: scheduled
  work, webhooks, server-side aggregation, or anything that must run when no
  device is awake. Under this constraint the answer is "it happens on a device,
  or it does not happen."
