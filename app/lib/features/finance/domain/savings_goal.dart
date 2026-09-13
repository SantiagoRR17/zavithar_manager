import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A thing being saved up for.
///
/// Mirrors `users/{uid}/savings/{id}` in `claude/data-model.md`. Same shape and
/// same conventions as [FinanceTransaction] — read that file first if this one
/// looks bare; the reasoning behind nullable timestamps, explicit field-name
/// constants and defensive parsing is written out there and not repeated here.
@immutable
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.deadline,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// 1–80 characters, per the data model.
  final String name;

  /// What is being saved towards. Always > 0 — a goal of zero is not a goal.
  final num targetAmount;

  /// How much is in it. May exceed [targetAmount]: over-saving is a real thing
  /// that happens and refusing to record it would be silly.
  final num currentAmount;

  /// Optional target date. Nothing enforces it — it is a note to self, not a
  /// deadline the app polices. Todo reminders (Milestone 3) are the feature
  /// that actually chases dates.
  final DateTime? deadline;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String fieldName = 'name';
  static const String fieldTargetAmount = 'targetAmount';
  static const String fieldCurrentAmount = 'currentAmount';
  static const String fieldDeadline = 'deadline';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';

  /// Fraction saved, clamped to 0–1 for the progress bar.
  ///
  /// Clamped rather than raw because a `LinearProgressIndicator` given 1.4
  /// draws past its own track. [isComplete] is what tells you the goal is
  /// met, and [currentAmount] is what tells you by how much it was beaten —
  /// this getter is only for drawing the bar.
  double get progress {
    if (targetAmount <= 0) return 0;
    return (currentAmount / targetAmount).clamp(0.0, 1.0).toDouble();
  }

  bool get isComplete => currentAmount >= targetAmount;

  /// What is still to be found. Never negative.
  num get remaining {
    final num gap = targetAmount - currentAmount;
    return gap < 0 ? 0 : gap;
  }

  factory SavingsGoal.fromMap(String id, Map<String, Object?> data) {
    return SavingsGoal(
      id: id,
      name: (data[fieldName] as String?) ?? 'Untitled goal',
      targetAmount: (data[fieldTargetAmount] as num?) ?? 0,
      currentAmount: (data[fieldCurrentAmount] as num?) ?? 0,
      deadline: _toDate(data[fieldDeadline]),
      createdAt: _toDate(data[fieldCreatedAt]),
      updatedAt: _toDate(data[fieldUpdatedAt]),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      fieldName: name.trim(),
      fieldTargetAmount: targetAmount,
      fieldCurrentAmount: currentAmount,
      if (deadline != null) fieldDeadline: Timestamp.fromDate(deadline!),
    };
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Note the two sentinels.
  ///
  /// `copyWith` uses null to mean "unchanged", which leaves no way to say
  /// "clear the deadline" — so [clearDeadline] is a separate flag. The
  /// alternative, a wrapper type around every nullable field, costs more than
  /// it saves for one field.
  SavingsGoal copyWith({
    String? name,
    num? targetAmount,
    num? currentAmount,
    DateTime? deadline,
    bool clearDeadline = false,
  }) {
    return SavingsGoal(
      id: id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SavingsGoal &&
            other.id == id &&
            other.name == name &&
            other.targetAmount == targetAmount &&
            other.currentAmount == currentAmount &&
            other.deadline == deadline &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    targetAmount,
    currentAmount,
    deadline,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'SavingsGoal($id, $name, $currentAmount/$targetAmount)';
}
