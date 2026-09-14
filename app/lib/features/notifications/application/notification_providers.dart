import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/application/category_providers.dart';
import '../../categories/domain/category_set.dart';
import '../../categories/domain/user_category.dart';
import '../../todos/application/todo_providers.dart';
import '../../todos/domain/todo.dart';
import '../data/notification_service.dart';
import '../domain/reminder_plan.dart';

/// The service, created once for the app.
///
/// Not rebuilt on the signed-in user the way the repositories are: alarms
/// belong to the device, not to a Firestore path. Signing out is handled by
/// [reminderSyncProvider] instead, which sees an empty todo list and cancels
/// everything — otherwise the previous user's task titles would keep appearing
/// on the lock screen.
final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((Ref ref) => NotificationService());

/// What the device should currently be holding alarms for.
final Provider<List<ScheduledReminder>> reminderPlanProvider =
    Provider<List<ScheduledReminder>>((Ref ref) {
      final List<Todo> todos =
          ref.watch(todosStreamProvider).asData?.value ?? const <Todo>[];
      // The user's own category names reach the lock screen too: a reminder
      // that says "Work" after the list was renamed to "Trabajo" would be the
      // one place in the app still speaking the old language.
      final CategorySet categories = ref.watch(
        categorySetProvider(CategoryKind.todo),
      );
      return ReminderPlan.from(todos, categoryLabel: categories.label);
    });

/// Keeps Android's registered alarms in step with the plan.
///
/// **Watched at the app root**, not from the todos screen, and that is the
/// deliberate part. Riverpod disposes a stream when nothing is watching it, so
/// if this lived on the Todos tab the todo listener would close the moment the
/// user navigated away — and a task edited on the *other* device would not
/// reach this one's alarms until the tab happened to be opened again. For a
/// two-device app whose entire premise is that both stay current, that is the
/// wrong failure.
///
/// The cost is one always-open listener on a small collection: a personal task
/// list read once per session plus one document per change. Against 50,000
/// reads a day it does not register. The transactions collection is the one
/// where this reasoning would not hold, which is why it is scoped to the open
/// period instead (ADR 0012).
///
/// A [Provider] performing a side effect is unusual. The alternative — a
/// `ref.listen` somewhere in the widget tree — ties the schedule to a widget's
/// lifetime, which is exactly the coupling this is avoiding. The sync is
/// idempotent and fire-and-forget, so a rebuild that races another is harmless.
final Provider<void> reminderSyncProvider = Provider<void>((Ref ref) {
  final List<ScheduledReminder> plan = ref.watch(reminderPlanProvider);
  final NotificationService service = ref.read(notificationServiceProvider);

  // Unawaited on purpose: nothing on screen waits for alarms to be registered,
  // and blocking a provider body on platform channels would stall the frame
  // that triggered it.
  service.sync(plan).catchError((Object error) {
    // A failure here is invisible by nature — the reminder simply never
    // arrives — so it is at least said out loud in debug rather than swallowed.
    debugPrint('Could not sync reminders: $error');
  });
});

/// Whether notifications are permitted and whether alarms can be exact.
@immutable
class NotificationStatus {
  const NotificationStatus({required this.allowed, required this.exact});

  final bool allowed;
  final bool exact;

  /// Reminders will arrive, but possibly late — Doze can defer an inexact
  /// alarm by an unpredictable amount.
  bool get degraded => allowed && !exact;
}

/// The current permission state, read from the platform on every evaluation.
///
/// Asked rather than remembered: either permission can be revoked from system
/// settings while the app is running, and a cached "granted" would then be a
/// lie that explains nothing when reminders stop arriving.
///
/// **This provider only ever queries.** An earlier version called
/// `requestPermission()` here, so merely opening Settings to *see* whether
/// reminders worked popped a system dialog demanding an answer. Asking is a
/// user action; it belongs behind a button, not behind a read.
final FutureProvider<NotificationStatus> notificationStatusProvider =
    FutureProvider<NotificationStatus>((Ref ref) async {
      final NotificationService service = ref.watch(
        notificationServiceProvider,
      );
      return NotificationStatus(
        allowed: await service.isPermitted(),
        exact: await service.canScheduleExact(),
      );
    });
