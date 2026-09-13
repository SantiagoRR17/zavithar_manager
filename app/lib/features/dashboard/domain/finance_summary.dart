import 'package:flutter/foundation.dart';

import '../../finance/domain/finance_transaction.dart';
import '../../finance/domain/liability.dart';
import '../../finance/domain/savings_goal.dart';

/// Everything the dashboard tiles display, computed from the three finance
/// collections.
///
/// **Derived data, never stored.** `claude/data-model.md` is explicit about
/// this and it is worth restating, because a `balance` field on the user
/// document is the obvious shortcut and it is a trap: it would have to be
/// updated by every write to every collection, and the moment one path forgets
/// — an undo, an offline edit that lands out of order, a document changed from
/// the console — the stored number disagrees with the transactions that are
/// supposed to explain it. A total recomputed from its inputs cannot drift from
/// them. The cost is an O(n) pass per snapshot, which for a personal ledger is
/// nothing.
///
/// Deliberately free of any Firebase import. That is what lets it be tested
/// with plain lists, no emulator, no network and no initialisation — the same
/// argument that caught both real bugs in the transactions slice before the app
/// was ever built.
@immutable
class FinanceSummary {
  const FinanceSummary({
    required this.balance,
    required this.monthIncome,
    required this.monthExpense,
    required this.savedTotal,
    required this.savingsTarget,
    required this.debtRemaining,
    required this.debtOriginal,
    required this.goalCount,
    required this.debtCount,
    required this.transactionCount,
  });

  /// A summary of nothing — what a brand-new account shows, and the value the
  /// tiles fall back to rather than rendering a spinner forever.
  static const FinanceSummary empty = FinanceSummary(
    balance: 0,
    monthIncome: 0,
    monthExpense: 0,
    savedTotal: 0,
    savingsTarget: 0,
    debtRemaining: 0,
    debtOriginal: 0,
    goalCount: 0,
    debtCount: 0,
    transactionCount: 0,
  );

  /// All recorded income minus all recorded expense, for all time.
  ///
  /// **This is not a bank balance**, and the distinction matters enough to name
  /// it here: the app has no concept of an opening balance, so this is the net
  /// of what has been *entered*, not what is in any account. It starts at zero
  /// on the first day of use regardless of what the user actually owns.
  ///
  /// Signed, and legitimately negative — a month of expenses entered before the
  /// salary that covers them is an ordinary state, not an error.
  ///
  /// Since [ADR 0012](../../../../docs/adr/0012-monthly-statements.md) it is
  /// assembled from two halves: the net of every **closed month's statement**,
  /// plus the net of the transactions in the still-open period. Both halves
  /// stay live. The transactions of closed months are never read — which is the
  /// whole point, and why this number is as cheap to compute in year ten as in
  /// year one.
  final num balance;

  /// Income and expense for the current calendar month, kept apart rather than
  /// netted. The net is [monthNet]; the two sides are shown separately because
  /// "you netted +200.000" hides whether that was a quiet month or a big
  /// paycheque against big spending.
  final num monthIncome;
  final num monthExpense;

  /// Summed across every savings goal.
  final num savedTotal;
  final num savingsTarget;

  /// Summed across every liability. [debtOriginal] is what was borrowed;
  /// [debtRemaining] is what is left and is the headline number.
  final num debtRemaining;
  final num debtOriginal;

  final int goalCount;
  final int debtCount;
  final int transactionCount;

  /// True when there is nothing recorded anywhere — the signal for the
  /// dashboard to show an invitation instead of a grid of zeroes.
  ///
  /// A non-zero [balance] counts as "something". Without that clause, a user
  /// whose whole history sits in closed statements would be shown the
  /// new-account invitation on the first of every month, right after closing
  /// the previous one.
  bool get isEmpty =>
      transactionCount == 0 && goalCount == 0 && debtCount == 0 && balance == 0;

  /// This month's income minus this month's expense. Signed.
  num get monthNet => monthIncome - monthExpense;

  /// Fraction of the combined savings target reached, clamped to 0–1 for the
  /// progress bar.
  ///
  /// Clamped for the same reason [SavingsGoal.progress] is: a bar handed 1.4
  /// draws outside its own track. Over-saving is real, so the clamp is a
  /// drawing concern only — [savedTotal] still reports the true figure.
  ///
  /// Zero when nothing has a target, rather than a division by zero.
  double get savingsProgress {
    if (savingsTarget <= 0) return 0;
    return (savedTotal / savingsTarget).clamp(0.0, 1.0).toDouble();
  }

  /// How much of the original borrowing has been repaid, 0–1.
  ///
  /// Counts *down* the debt, matching [Liability.progress]: a nearly-repaid
  /// debt shows a nearly-full bar.
  double get debtProgress {
    if (debtOriginal <= 0) return 0;
    final num paid = debtOriginal - debtRemaining;
    return (paid / debtOriginal).clamp(0.0, 1.0).toDouble();
  }

  /// Builds the summary in a single pass over each collection.
  ///
  /// [now] is injectable so the month boundary can be tested without waiting
  /// for one. Defaulting it to `DateTime.now()` inside the factory rather than
  /// in the parameter list is deliberate — a default parameter value must be a
  /// compile-time constant, and `DateTime.now()` is not.
  factory FinanceSummary.from({
    required List<FinanceTransaction> transactions,
    required List<SavingsGoal> savings,
    required List<Liability> liabilities,
    // The net carried in from every closed month (ADR 0012). Zero before the
    // first close, which is why it defaults rather than being required — a
    // caller with no statements is not a caller with a bug.
    num openingBalance = 0,
    DateTime? now,
  }) {
    final DateTime reference = now ?? DateTime.now();

    num income = 0;
    num expense = 0;
    num monthIncome = 0;
    num monthExpense = 0;

    for (final FinanceTransaction tx in transactions) {
      // `date` is when the money moved, chosen by the user — not `createdAt`,
      // which is when the row happened to be typed in. Entering January's rent
      // in February must count against January.
      final bool thisMonth =
          tx.date.year == reference.year && tx.date.month == reference.month;

      if (tx.type.isIncome) {
        income += tx.amount;
        if (thisMonth) monthIncome += tx.amount;
      } else {
        expense += tx.amount;
        if (thisMonth) monthExpense += tx.amount;
      }
    }

    num savedTotal = 0;
    num savingsTarget = 0;
    for (final SavingsGoal goal in savings) {
      savedTotal += goal.currentAmount;
      savingsTarget += goal.targetAmount;
    }

    num debtRemaining = 0;
    num debtOriginal = 0;
    for (final Liability liability in liabilities) {
      debtRemaining += liability.remainingAmount;
      debtOriginal += liability.originalAmount;
    }

    return FinanceSummary(
      balance: openingBalance + income - expense,
      monthIncome: monthIncome,
      monthExpense: monthExpense,
      savedTotal: savedTotal,
      savingsTarget: savingsTarget,
      debtRemaining: debtRemaining,
      debtOriginal: debtOriginal,
      goalCount: savings.length,
      debtCount: liabilities.length,
      transactionCount: transactions.length,
    );
  }
}
