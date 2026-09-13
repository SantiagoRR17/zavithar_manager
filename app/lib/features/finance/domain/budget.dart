import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'finance_transaction.dart';
import 'statement_period.dart';

/// A monthly spending limit for one category.
///
/// Mirrors `users/{uid}/budgets/{category}` — **the document ID is the
/// category**, the same trick `statements` uses with the period. It makes
/// duplicates structurally impossible: there is nowhere to put a second budget
/// for `groceries`. A random ID plus a `category` field would have needed a
/// uniqueness check the database cannot enforce.
@immutable
class Budget {
  const Budget({
    required this.category,
    required this.monthlyLimit,
    this.createdAt,
    this.updatedAt,
  });

  final String category;

  /// Always > 0. A limit of zero is not a budget, it is a ban, and the app has
  /// no way to enforce one.
  final num monthlyLimit;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get id => category;

  static const String fieldCategory = 'category';
  static const String fieldMonthlyLimit = 'monthlyLimit';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';

  factory Budget.fromMap(String id, Map<String, Object?> data) {
    return Budget(
      // The ID is the category; the field is a copy kept only so the document
      // is readable on its own in the console and in an export.
      category: (data[fieldCategory] as String?) ?? id,
      monthlyLimit: (data[fieldMonthlyLimit] as num?) ?? 0,
      createdAt: _toDate(data[fieldCreatedAt]),
      updatedAt: _toDate(data[fieldUpdatedAt]),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    fieldCategory: category,
    fieldMonthlyLimit: monthlyLimit,
  };

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  Budget copyWith({num? monthlyLimit}) => Budget(
    category: category,
    monthlyLimit: monthlyLimit ?? this.monthlyLimit,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Budget &&
          other.category == category &&
          other.monthlyLimit == monthlyLimit &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(category, monthlyLimit, createdAt, updatedAt);

  @override
  String toString() => 'Budget($category, $monthlyLimit)';
}

/// A budget measured against what has actually been spent this month.
@immutable
class BudgetStatus {
  const BudgetStatus({required this.budget, required this.spent});

  final Budget budget;

  /// Expenses in this category, this calendar month. Income is ignored: a
  /// refund landing in `groceries` should not buy back room to spend.
  final num spent;

  String get category => budget.category;
  num get limit => budget.monthlyLimit;

  /// Never negative — once the limit is passed this is zero, and [overspend]
  /// is what says by how much.
  num get remaining {
    final num left = limit - spent;
    return left < 0 ? 0 : left;
  }

  num get overspend {
    final num over = spent - limit;
    return over < 0 ? 0 : over;
  }

  bool get isOver => spent > limit;

  /// Fraction used, clamped to 0–1 for the bar. [isOver] is what reports
  /// having passed the limit; this is only for drawing.
  double get progress {
    if (limit <= 0) return 0;
    return (spent / limit).clamp(0.0, 1.0).toDouble();
  }

  /// How far through the month we are, 0–1.
  ///
  /// This is the number that makes a budget useful rather than decorative.
  /// "You have spent 60% of your food budget" means nothing on its own — it is
  /// excellent on the 25th and alarming on the 3rd. See [pace].
  static double monthElapsed({DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final StatementPeriod period = StatementPeriod.of(reference);
    final int totalDays = period.endExclusive.difference(period.start).inDays;
    final int elapsed = reference.difference(period.start).inDays;
    if (totalDays <= 0) return 0;
    return (elapsed / totalDays).clamp(0.0, 1.0).toDouble();
  }

  /// Spending relative to where the month is.
  ///
  /// 1.0 means exactly on pace. Above 1 means spending faster than the month
  /// is passing, which is the early warning a plain percentage cannot give.
  ///
  /// Infinite would be the honest answer on the first instant of the month
  /// with money already spent; it returns [double.infinity] and callers show
  /// that as "over pace" rather than rendering a number.
  double pace({DateTime? now}) {
    final double elapsed = monthElapsed(now: now);
    if (limit <= 0) return 0;
    if (elapsed <= 0) return spent > 0 ? double.infinity : 0;
    return (spent / limit) / elapsed;
  }

  /// Comfortably within budget for this point in the month.
  bool get isOnTrack => !isOver && pace() <= 1.0;
}

/// Builds the status of every budget from the month's transactions.
abstract final class BudgetReport {
  /// Pairs each budget with what has been spent in its category this month.
  ///
  /// Transactions outside the current calendar month are ignored, and so is
  /// income — a budget is a cap on spending, not a net.
  ///
  /// Ordered by how much trouble each one is in: over first, then by pace.
  /// A list sorted by category name would bury the one thing worth acting on.
  static List<BudgetStatus> from({
    required List<Budget> budgets,
    required List<FinanceTransaction> transactions,
    DateTime? now,
  }) {
    final DateTime reference = now ?? DateTime.now();
    final StatementPeriod month = StatementPeriod.of(reference);

    final Map<String, num> spentByCategory = <String, num>{};
    for (final FinanceTransaction tx in transactions) {
      if (tx.type.isIncome) continue;
      if (!month.contains(tx.date)) continue;
      spentByCategory[tx.category] =
          (spentByCategory[tx.category] ?? 0) + tx.amount;
    }

    final List<BudgetStatus> statuses = <BudgetStatus>[
      for (final Budget b in budgets)
        BudgetStatus(budget: b, spent: spentByCategory[b.category] ?? 0),
    ];

    statuses.sort((BudgetStatus a, BudgetStatus b) {
      if (a.isOver != b.isOver) return a.isOver ? -1 : 1;
      final int byPace = b
          .pace(now: reference)
          .compareTo(a.pace(now: reference));
      if (byPace != 0) return byPace;
      return a.category.compareTo(b.category);
    });

    return List<BudgetStatus>.unmodifiable(statuses);
  }

  /// How many budgets are currently exceeded — the one number worth putting on
  /// the dashboard.
  static int overCount(List<BudgetStatus> statuses) =>
      statuses.where((BudgetStatus s) => s.isOver).length;

  /// Total budgeted and total spent against it, for a summary line.
  static (num budgeted, num spent) totals(List<BudgetStatus> statuses) {
    num budgeted = 0;
    num spent = 0;
    for (final BudgetStatus s in statuses) {
      budgeted += s.limit;
      spent += s.spent;
    }
    return (budgeted, spent);
  }
}
