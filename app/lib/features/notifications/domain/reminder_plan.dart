import 'package:flutter/foundation.dart';

import '../../todos/domain/todo.dart';

/// One notification the device should be holding an alarm for.
@immutable
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.todoId,
    required this.title,
    required this.body,
    required this.at,
  });

  /// The Android notification ID. Stable for a given todo — see
  /// [ReminderPlan.notificationIdFor].
  final int id;

  final String todoId;
  final String title;
  final String body;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledReminder &&
          other.id == id &&
          other.todoId == todoId &&
          other.title == title &&
          other.body == body &&
          other.at == at;

  @override
  int get hashCode => Object.hash(id, todoId, title, body, at);

  @override
  String toString() => 'ScheduledReminder($todoId at $at)';
}

/// Works out which reminders the device should currently hold, from the todos
/// Firestore has synced to it.
///
/// Pure, and free of both Firebase and the notification plugin — which is what
/// lets every rule below be tested in milliseconds. That matters more here than
/// elsewhere: a scheduling bug does not crash, it simply means a reminder never
/// arrives, and there is no screen on which that is visible.
///
/// See [ADR 0011](../../../../docs/adr/0011-free-tier-only.md) for why the
/// schedule lives on the device rather than in a Cloud Function.
abstract final class ReminderPlan {
  /// The most alarms to hold at once.
  ///
  /// Android caps pending alarms per app — in the low hundreds, and silently:
  /// past the limit, registering one simply does nothing. Sixty is far beyond
  /// what a personal task list needs and far below anywhere near the cap, and
  /// keeps the reconcile loop cheap, since it runs on every todo write.
  ///
  /// The cap is applied to the *soonest* reminders, so the ones dropped are the
  /// furthest away — which are also the ones most likely to be rescheduled
  /// before they would have fired anyway.
  static const int maxScheduled = 60;

  /// The reminders that should be registered right now.
  ///
  /// Ordered soonest first, so the cap keeps the right ones.
  static List<ScheduledReminder> from(
    List<Todo> todos, {
    DateTime? now,
    int limit = maxScheduled,
  }) {
    final DateTime reference = now ?? DateTime.now();

    final List<Todo> due = todos.where((Todo t) {
      final DateTime? at = t.reminderAt;
      if (at == null) return false;
      // A completed task has nothing left to remind about, and a reminder that
      // fires for something already ticked off teaches the user to ignore
      // notifications — which costs far more than the one it saved.
      if (t.isCompleted) return false;
      // An alarm in the past cannot fire. Scheduling one either throws or fires
      // immediately depending on the platform, and firing immediately is worse:
      // opening the app after a holiday would dump a week of stale reminders on
      // the notification shade at once.
      return at.isAfter(reference);
    }).toList();

    due.sort((Todo a, Todo b) => a.reminderAt!.compareTo(b.reminderAt!));

    return List<ScheduledReminder>.unmodifiable(
      due
          .take(limit)
          .map(
            (Todo t) => ScheduledReminder(
              id: notificationIdFor(t.id),
              todoId: t.id,
              title: t.title,
              body: bodyFor(t),
              at: t.reminderAt!,
            ),
          ),
    );
  }

  /// The line under the title.
  ///
  /// The deadline if there is one, because "due today" is the part that decides
  /// whether the notification gets acted on or swiped away; otherwise the
  /// category, so the reminder still says what kind of thing it is.
  static String bodyFor(Todo todo) {
    final DateTime? deadline = todo.deadline;
    if (deadline == null) return TodoCategories.label(todo.category);

    final DateTime day = DateTime(deadline.year, deadline.month, deadline.day);
    final DateTime today = DateTime(
      todo.reminderAt!.year,
      todo.reminderAt!.month,
      todo.reminderAt!.day,
    );
    final int days = day.difference(today).inDays;

    return switch (days) {
      0 => 'Due today',
      1 => 'Due tomorrow',
      < 0 => 'Overdue',
      _ => 'Due in $days days',
    };
  }

  /// A stable 31-bit notification ID for a todo.
  ///
  /// Android identifies a notification by an `int`, so the Firestore document
  /// ID has to be folded down to one. **Stability is the requirement**: the
  /// same todo must map to the same ID on every run, or rescheduling would
  /// leave the previous alarm registered and the user would get the same
  /// reminder twice — once with the old text.
  ///
  /// FNV-1a, masked to 31 bits so the result is always positive (Android
  /// accepts negative IDs, but a negative one is a nuisance to recognise in a
  /// log). Two different todos could in principle collide and one would
  /// silently replace the other's alarm; with a personal task list and a 2^31
  /// space that is remote enough to accept rather than to carry a mapping table
  /// for.
  static int notificationIdFor(String todoId) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < todoId.length; i++) {
      hash ^= todoId.codeUnitAt(i);
      // The FNV prime, applied with shifts and masked to 32 bits so the result
      // is identical on the web's 53-bit ints and native's 64-bit ones.
      hash =
          (hash +
              ((hash << 1) +
                  (hash << 4) +
                  (hash << 7) +
                  (hash << 8) +
                  (hash << 24))) &
          0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}
