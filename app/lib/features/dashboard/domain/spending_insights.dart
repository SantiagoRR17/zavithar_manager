import 'package:flutter/foundation.dart';

import '../../finance/domain/finance_transaction.dart';
import '../../finance/domain/monthly_statement.dart';
import '../../finance/domain/statement_period.dart';

/// One category's share of a month's spending.
@immutable
class CategorySpend {
  const CategorySpend({required this.category, required this.amount});

  final String category;
  final num amount;
}

/// One month's income, expense and net, for the change-over-time chart.
@immutable
class MonthlyTotals {
  const MonthlyTotals({
    required this.period,
    required this.income,
    required this.expense,
    required this.isOpen,
  });

  final StatementPeriod period;
  final num income;
  final num expense;

  /// The current month, still accumulating. Drawn differently, because a bar
  /// that is short only because the month is young would otherwise read as a
  /// quiet month — the single most misleading thing a month-over-month chart
  /// can do.
  final bool isOpen;

  num get net => income - expense;
}

/// The figures behind the dashboard charts.
///
/// Pure, and assembled from what the app already holds: closed months come from
/// their statements, the current month from the open-period transactions. No
/// new reads, and no new Firestore listener.
abstract final class SpendingInsights {
  /// Spending per category for the month containing [now], largest first.
  ///
  /// Income is excluded. A chart of "where the money went" that nets a refund
  /// against a purchase is answering a different question from the one its
  /// title asks.
  ///
  /// The tail beyond [limit] is folded into a single `other` row rather than
  /// drawn — past about seven bars the small ones are noise, and the chart
  /// stops being a comparison and becomes a list.
  static List<CategorySpend> byCategory(
    List<FinanceTransaction> transactions, {
    DateTime? now,
    int limit = 7,
  }) {
    final StatementPeriod month = StatementPeriod.of(now ?? DateTime.now());

    final Map<String, num> totals = <String, num>{};
    for (final FinanceTransaction tx in transactions) {
      if (tx.type.isIncome) continue;
      if (!month.contains(tx.date)) continue;
      totals[tx.category] = (totals[tx.category] ?? 0) + tx.amount;
    }

    final List<CategorySpend> rows = <CategorySpend>[
      for (final MapEntry<String, num> e in totals.entries)
        CategorySpend(category: e.key, amount: e.value),
    ]..sort((CategorySpend a, CategorySpend b) => b.amount.compareTo(a.amount));

    if (rows.length <= limit) return List<CategorySpend>.unmodifiable(rows);

    final num tail = rows
        .skip(limit - 1)
        .fold<num>(0, (num sum, CategorySpend r) => sum + r.amount);

    return List<CategorySpend>.unmodifiable(<CategorySpend>[
      ...rows.take(limit - 1),
      CategorySpend(category: 'other', amount: tail),
    ]);
  }

  /// Income and expense per month, oldest first.
  ///
  /// Closed months are read from their statements — which is the whole payoff
  /// of ADR 0012: a year of history costs a dozen documents rather than
  /// thousands of transactions. The current month is computed from the open
  /// period and marked [MonthlyTotals.isOpen].
  ///
  /// Months with no statement and no transactions are simply absent rather
  /// than drawn as zero. A gap in the record is not a month in which nothing
  /// happened, and a chart that renders it as a flat bar says it was.
  static List<MonthlyTotals> byMonth({
    required List<MonthlyStatement> statements,
    required List<FinanceTransaction> openTransactions,
    DateTime? now,
    int months = 6,
  }) {
    final DateTime reference = now ?? DateTime.now();
    final StatementPeriod current = StatementPeriod.of(reference);

    final List<MonthlyTotals> series = <MonthlyTotals>[
      for (final MonthlyStatement s in statements)
        MonthlyTotals(
          period: s.period,
          income: s.totalIncome,
          expense: s.totalExpense,
          isOpen: false,
        ),
    ];

    num openIncome = 0;
    num openExpense = 0;
    for (final FinanceTransaction tx in openTransactions) {
      if (!current.contains(tx.date)) continue;
      if (tx.type.isIncome) {
        openIncome += tx.amount;
      } else {
        openExpense += tx.amount;
      }
    }

    // The current month is included even when empty: unlike a historical gap,
    // "nothing yet this month" is a fact rather than a hole, and leaving it out
    // would make the chart appear to end last month.
    series.removeWhere((MonthlyTotals m) => m.period == current);
    series.add(
      MonthlyTotals(
        period: current,
        income: openIncome,
        expense: openExpense,
        isOpen: true,
      ),
    );

    series.sort(
      (MonthlyTotals a, MonthlyTotals b) => a.period.compareTo(b.period),
    );

    final int from = series.length > months ? series.length - months : 0;
    return List<MonthlyTotals>.unmodifiable(series.sublist(from));
  }

  /// The largest absolute net in a series, for scaling the bars.
  ///
  /// Returns zero for an empty or all-zero series, which callers treat as
  /// "nothing to draw" rather than dividing by it.
  static num peakNet(List<MonthlyTotals> series) {
    num peak = 0;
    for (final MonthlyTotals m in series) {
      final num magnitude = m.net < 0 ? -m.net : m.net;
      if (magnitude > peak) peak = magnitude;
    }
    return peak;
  }
}
