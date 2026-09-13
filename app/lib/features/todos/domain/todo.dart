import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Where a task is in its life.
///
/// Stored strings are pinned in [wireName] rather than taken from Dart's
/// `.name`, for the reason spelled out in `finance_transaction.dart`: renaming
/// or reordering a Dart constant must not silently change the database format.
/// Here it matters more than there — `inProgress` in Dart is `in_progress` on
/// the wire, so `.name` would have been wrong from the first write.
enum TodoStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed');

  const TodoStatus(this.wireName);

  final String wireName;

  /// Parses the stored string, falling back to [pending].
  ///
  /// Falling back rather than throwing is the same call made for
  /// `TransactionType`: one malformed document must not take down the list.
  /// [pending] is the conservative reading — treating an unrecognised task as
  /// *done* would hide it, and hiding a task is the one failure this app
  /// exists to prevent.
  static TodoStatus fromWire(Object? value) {
    for (final TodoStatus status in TodoStatus.values) {
      if (value == status.wireName) return status;
    }
    return TodoStatus.pending;
  }

  bool get isCompleted => this == TodoStatus.completed;

  String get label => switch (this) {
    TodoStatus.pending => 'Pending',
    TodoStatus.inProgress => 'In progress',
    TodoStatus.completed => 'Completed',
  };
}

/// How much a task matters. Optional in the data model, with a default.
enum TodoPriority {
  low('low'),
  medium('medium'),
  high('high');

  const TodoPriority(this.wireName);

  final String wireName;

  /// The default for anything unspecified — including a document written
  /// before this field existed, which is why the fallback lives here rather
  /// than at each call site.
  static const TodoPriority fallback = TodoPriority.medium;

  static TodoPriority fromWire(Object? value) {
    for (final TodoPriority priority in TodoPriority.values) {
      if (value == priority.wireName) return priority;
    }
    return fallback;
  }

  String get label => switch (this) {
    TodoPriority.low => 'Low',
    TodoPriority.medium => 'Medium',
    TodoPriority.high => 'High',
  };
}

/// The four task categories, in their fixed order.
///
/// **The order is load-bearing.** `CLAUDE.md` → Brand & UI tokens: category
/// colours are never reassigned or cycled, because "work is orange" has to stay
/// true on every screen or the colour stops carrying information. This list and
/// `AppColors.categoryOrder` must therefore agree exactly.
///
/// They are deliberately *not* the same constant. The domain layer owns the
/// data contract and must not import the theme — that would make a model depend
/// on presentation. Duplication is the lesser evil, and the drift it risks is
/// caught by a test asserting the two lists match, rather than by someone
/// noticing a wrong colour months later.
///
/// Stored as a lowercase string, not a Dart enum, for the same reason
/// transaction categories are: `claude/data-model.md` keeps the door open to
/// user-editable categories in Milestone 4, and that must not become a
/// migration.
abstract final class TodoCategories {
  static const List<String> all = <String>['work', 'hobbies', 'study', 'home'];

  static const String fallback = 'work';

  static bool isKnown(String category) => all.contains(category);

  /// `hobbies` → `Hobbies`. Keys are lowercase so they sort and group
  /// predictably; capitalisation is display only.
  static String label(String category) {
    if (category.isEmpty) return category;
    return category[0].toUpperCase() + category.substring(1);
  }
}

/// One task.
///
/// Mirrors `users/{uid}/todos/{todoId}` in `claude/data-model.md`. The
/// conventions here — nullable audit timestamps, field-name constants,
/// defensive parsing — are explained in `finance_transaction.dart` and not
/// repeated.
@immutable
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    this.notes,
    this.deadline,
    this.reminderAt,
    this.followUpOf,
    this.priority = TodoPriority.medium,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;

  /// 1–120 characters, per the data model.
  final String title;

  final String? notes;

  /// One of [TodoCategories.all].
  final String category;

  final TodoStatus status;

  /// When the task is due. Optional — plenty of tasks have no date.
  final DateTime? deadline;

  /// When to fire the reminder, which may differ from [deadline]
  /// ("a day before"). Optional and independent: a task can have a deadline
  /// with no reminder, or a reminder with no deadline.
  ///
  /// Milestone 2 only *stores* this. Milestone 3 is what schedules an on-device
  /// notification from it — see [ADR 0011](../../../../docs/adr/0011-free-tier-only.md),
  /// which replaced the Cloud Function that would have sent a push.
  final DateTime? reminderAt;

  /// The task this one follows up on, by document ID.
  ///
  /// **Firestore has no referential integrity**, so this can point at a
  /// document that has since been deleted. Nothing prevents it and nothing
  /// repairs it; the UI resolves the parent if it is there and silently omits
  /// the link if it is not. Cascading deletes would need a transaction per
  /// delete to be correct, which is a large cost for a dangling label.
  final String? followUpOf;

  /// Never null in Dart — an unspecified priority reads back as
  /// [TodoPriority.medium] — but optional in the security rules, so documents
  /// written before the field existed stay valid.
  final TodoPriority priority;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// When the task was marked done. Set and cleared by the repository from
  /// [status], never edited directly — two fields that can disagree about
  /// whether something is finished is a bug waiting to happen.
  final DateTime? completedAt;

  static const String fieldTitle = 'title';
  static const String fieldNotes = 'notes';
  static const String fieldCategory = 'category';
  static const String fieldStatus = 'status';
  static const String fieldDeadline = 'deadline';
  static const String fieldReminderAt = 'reminderAt';
  static const String fieldFollowUpOf = 'followUpOf';
  static const String fieldPriority = 'priority';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';
  static const String fieldCompletedAt = 'completedAt';

  bool get isCompleted => status.isCompleted;

  bool get isFollowUp => followUpOf != null;

  /// Past its deadline and not finished.
  ///
  /// Compares whole days, not instants: a task due "today" is not overdue at
  /// 00:01 merely because its stored timestamp was midnight. Anything due
  /// before today counts.
  bool isOverdue({DateTime? now}) {
    final DateTime? due = deadline;
    if (due == null || isCompleted) return false;
    final DateTime today = _dayOnly(now ?? DateTime.now());
    return _dayOnly(due).isBefore(today);
  }

  /// Due today and not finished.
  bool isDueToday({DateTime? now}) {
    final DateTime? due = deadline;
    if (due == null || isCompleted) return false;
    return _dayOnly(due) == _dayOnly(now ?? DateTime.now());
  }

  static DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  factory Todo.fromMap(String id, Map<String, Object?> data) {
    return Todo(
      id: id,
      title: (data[fieldTitle] as String?) ?? 'Untitled task',
      notes: data[fieldNotes] as String?,
      category: (data[fieldCategory] as String?) ?? TodoCategories.fallback,
      status: TodoStatus.fromWire(data[fieldStatus]),
      deadline: _toDate(data[fieldDeadline]),
      reminderAt: _toDate(data[fieldReminderAt]),
      followUpOf: data[fieldFollowUpOf] as String?,
      priority: TodoPriority.fromWire(data[fieldPriority]),
      createdAt: _toDate(data[fieldCreatedAt]),
      updatedAt: _toDate(data[fieldUpdatedAt]),
      completedAt: _toDate(data[fieldCompletedAt]),
    );
  }

  /// The document body for a write.
  ///
  /// Audit timestamps and [completedAt] are absent by design — the repository
  /// supplies them, because they are either `FieldValue.serverTimestamp()`
  /// (which cannot live in a model) or derived from [status].
  ///
  /// Every optional key is *omitted* rather than written as null. Firestore
  /// stores an explicit null as a real field, and the rules' `hasOnly`
  /// allowlist counts a present-but-null key as present.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      fieldTitle: title.trim(),
      fieldCategory: category,
      fieldStatus: status.wireName,
      fieldPriority: priority.wireName,
      if (notes != null && notes!.trim().isNotEmpty) fieldNotes: notes!.trim(),
      if (deadline != null) fieldDeadline: Timestamp.fromDate(deadline!),
      if (reminderAt != null) fieldReminderAt: Timestamp.fromDate(reminderAt!),
      if (followUpOf != null && followUpOf!.isNotEmpty)
        fieldFollowUpOf: followUpOf,
    };
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Dart's null-means-unchanged convention cannot express "remove this", so
  /// every nullable field that a form can clear needs an explicit flag. Without
  /// them a deadline set once could never be unset — the third of the three
  /// things an optional field needs (`CLAUDE.md` → Milestone 1).
  Todo copyWith({
    String? title,
    String? notes,
    String? category,
    TodoStatus? status,
    DateTime? deadline,
    DateTime? reminderAt,
    String? followUpOf,
    TodoPriority? priority,
    DateTime? completedAt,
    bool clearNotes = false,
    bool clearDeadline = false,
    bool clearReminderAt = false,
    bool clearFollowUpOf = false,
    bool clearCompletedAt = false,
  }) {
    return Todo(
      id: id,
      title: title ?? this.title,
      notes: clearNotes ? null : (notes ?? this.notes),
      category: category ?? this.category,
      status: status ?? this.status,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
      followUpOf: clearFollowUpOf ? null : (followUpOf ?? this.followUpOf),
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  /// Value equality so a snapshot that re-emits an unchanged row does not
  /// rebuild it. Firestore re-sends the whole collection on every change.
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Todo &&
            other.id == id &&
            other.title == title &&
            other.notes == notes &&
            other.category == category &&
            other.status == status &&
            other.deadline == deadline &&
            other.reminderAt == reminderAt &&
            other.followUpOf == followUpOf &&
            other.priority == priority &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt &&
            other.completedAt == completedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    category,
    status,
    deadline,
    reminderAt,
    followUpOf,
    priority,
    createdAt,
    updatedAt,
    completedAt,
  );

  @override
  String toString() => 'Todo($id, "$title", $category, ${status.wireName})';
}
