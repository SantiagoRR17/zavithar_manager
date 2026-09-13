import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'finance_transaction.dart';
import 'statement_period.dart';

/// A closed month, summarised — the app's equivalent of a bank statement.
///
/// Written once when the month is closed and never edited. See
/// [ADR 0012](../../../../docs/adr/0012-monthly-statements.md) for why this
/// stored derived value is allowed where a stored `balance` field is not: this
/// one cannot drift, because it is immutable and because the transactions it
/// summarises are still there to check it against.
@immutable
class MonthlyStatement {
  const MonthlyStatement({
    required this.period,
    required this.totalIncome,
    required this.totalExpense,
    required this.openingBalance,
    required this.transactionCount,
    required this.incomeByCategory,
    required this.expenseByCategory,
    this.closedAt,
  });

  final StatementPeriod period;

  final num totalIncome;
  final num totalExpense;

  /// The running balance carried in from the previous statement — zero for the
  /// very first one. This is what makes statements chain the way a bank's do,
  /// and what makes a missing month visible: the openings and closings stop
  /// lining up.
  final num openingBalance;

  final int transactionCount;

  /// Per-category totals, kept as two maps rather than one signed map.
  ///
  /// A single map would have to encode direction in the sign, and a category
  /// that saw both income and expense — `other`, routinely — would collapse to
  /// their difference and lose both real figures.
  final Map<String, num> incomeByCategory;
  final Map<String, num> expenseByCategory;

  /// Server timestamp of the close. Null for the moments between the local
  /// write and the server stamping it, like every other audit field here.
  final DateTime? closedAt;

  String get id => period.id;

  num get net => totalIncome - totalExpense;

  num get closingBalance => openingBalance + net;

  static const String fieldPeriodStart = 'periodStart';
  static const String fieldPeriodEnd = 'periodEnd';
  static const String fieldTotalIncome = 'totalIncome';
  static const String fieldTotalExpense = 'totalExpense';
  static const String fieldOpeningBalance = 'openingBalance';
  static const String fieldClosingBalance = 'closingBalance';
  static const String fieldTransactionCount = 'transactionCount';
  static const String fieldIncomeByCategory = 'incomeByCategory';
  static const String fieldExpenseByCategory = 'expenseByCategory';
  static const String fieldClosedAt = 'closedAt';

  /// Summarises [transactions] for [period], carrying [openingBalance] in.
  ///
  /// Transactions outside the period are ignored rather than trusted — the
  /// caller filters, but a statement that silently absorbed a neighbouring
  /// month's rows would be wrong in a way nothing downstream could detect.
  factory MonthlyStatement.from({
    required StatementPeriod period,
    required List<FinanceTransaction> transactions,
    required num openingBalance,
  }) {
    num income = 0;
    num expense = 0;
    int count = 0;
    final Map<String, num> byIncome = <String, num>{};
    final Map<String, num> byExpense = <String, num>{};

    for (final FinanceTransaction tx in transactions) {
      if (!period.contains(tx.date)) continue;
      count++;
      if (tx.type.isIncome) {
        income += tx.amount;
        byIncome[tx.category] = (byIncome[tx.category] ?? 0) + tx.amount;
      } else {
        expense += tx.amount;
        byExpense[tx.category] = (byExpense[tx.category] ?? 0) + tx.amount;
      }
    }

    return MonthlyStatement(
      period: period,
      totalIncome: income,
      totalExpense: expense,
      openingBalance: openingBalance,
      transactionCount: count,
      incomeByCategory: Map<String, num>.unmodifiable(byIncome),
      expenseByCategory: Map<String, num>.unmodifiable(byExpense),
    );
  }

  factory MonthlyStatement.fromMap(String id, Map<String, Object?> data) {
    // The document ID *is* the period. A `period` field would be a second copy
    // of the same fact, to be kept in sync for no benefit.
    final StatementPeriod period =
        StatementPeriod.tryParse(id) ??
        StatementPeriod.of(_toDate(data[fieldPeriodStart]) ?? DateTime(1970));

    return MonthlyStatement(
      period: period,
      totalIncome: (data[fieldTotalIncome] as num?) ?? 0,
      totalExpense: (data[fieldTotalExpense] as num?) ?? 0,
      openingBalance: (data[fieldOpeningBalance] as num?) ?? 0,
      transactionCount: (data[fieldTransactionCount] as num?)?.toInt() ?? 0,
      incomeByCategory: _toAmountMap(data[fieldIncomeByCategory]),
      expenseByCategory: _toAmountMap(data[fieldExpenseByCategory]),
      closedAt: _toDate(data[fieldClosedAt]),
    );
  }

  /// The document body. [closedAt] is absent — the repository stamps it with
  /// `FieldValue.serverTimestamp()`.
  ///
  /// [fieldClosingBalance] is written even though it is derivable from
  /// opening + net. It is the number a person reads off the statement, and
  /// storing it means a future reader — a CSV export, a spreadsheet, a human in
  /// the console — does not have to re-derive the app's arithmetic to trust it.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      fieldPeriodStart: Timestamp.fromDate(period.start),
      fieldPeriodEnd: Timestamp.fromDate(period.endInclusive),
      fieldTotalIncome: totalIncome,
      fieldTotalExpense: totalExpense,
      fieldOpeningBalance: openingBalance,
      fieldClosingBalance: closingBalance,
      fieldTransactionCount: transactionCount,
      fieldIncomeByCategory: incomeByCategory,
      fieldExpenseByCategory: expenseByCategory,
    };
  }

  static Map<String, num> _toAmountMap(Object? value) {
    if (value is! Map) return const <String, num>{};
    final Map<String, num> out = <String, num>{};
    value.forEach((Object? k, Object? v) {
      if (k is String && v is num) out[k] = v;
    });
    return Map<String, num>.unmodifiable(out);
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  String toString() =>
      'MonthlyStatement(${period.id}, net $net, closing $closingBalance)';
}

/// The result of checking a stored statement against the transactions it
/// claims to summarise.
///
/// This is the thing that makes a stored derived value acceptable at all
/// (ADR 0012). A statement nobody can check is a number you have to believe;
/// one that can be re-derived from data you still hold is a number you can
/// *prove*, and the difference only exists if something actually offers to do
/// the proving.
@immutable
class StatementVerification {
  const StatementVerification({
    required this.stored,
    required this.recomputed,
    required this.strayTransactions,
  });

  final MonthlyStatement stored;
  final MonthlyStatement recomputed;

  /// Transactions dated inside the closed month that the stored statement does
  /// not account for — the backdating hazard ADR 0012 names. The security rules
  /// reject these, so any that turn up came from the console, from a client
  /// older than the rules, or from a genuine bug.
  final int strayTransactions;

  bool get matches =>
      stored.totalIncome == recomputed.totalIncome &&
      stored.totalExpense == recomputed.totalExpense &&
      stored.transactionCount == recomputed.transactionCount;

  num get incomeDrift => recomputed.totalIncome - stored.totalIncome;
  num get expenseDrift => recomputed.totalExpense - stored.totalExpense;
  num get netDrift => recomputed.net - stored.net;

  int get countDrift => recomputed.transactionCount - stored.transactionCount;
}
