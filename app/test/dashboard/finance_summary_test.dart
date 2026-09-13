// Unit tests for the dashboard summary.
//
// Same principle as the finance model tests: [FinanceSummary] deliberately
// imports no Firebase, so it can be exercised with plain lists in milliseconds
// — no emulator, no network, no initialisation.
//
// The month boundary gets the most attention, because it is the only part of
// this class that depends on *when* it runs, and a bug there is invisible for
// up to thirty days at a time.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/dashboard/domain/finance_summary.dart';
import 'package:zavithar_manager/features/finance/domain/finance_transaction.dart';
import 'package:zavithar_manager/features/finance/domain/liability.dart';
import 'package:zavithar_manager/features/finance/domain/savings_goal.dart';

void main() {
  // A fixed "now" so the month boundary can be tested without waiting for one.
  final DateTime september = DateTime(2026, 9, 13);

  FinanceTransaction tx({
    required num amount,
    required TransactionType type,
    DateTime? date,
    String id = 't1',
  }) {
    return FinanceTransaction(
      id: id,
      amount: amount,
      type: type,
      category: 'other',
      date: date ?? september,
    );
  }

  SavingsGoal goal({required num target, required num current, String id = 'g'}) {
    return SavingsGoal(
      id: id,
      name: 'Goal',
      targetAmount: target,
      currentAmount: current,
    );
  }

  Liability debt({
    required num original,
    required num remaining,
    String id = 'd',
  }) {
    return Liability(
      id: id,
      name: 'Debt',
      type: 'loan',
      originalAmount: original,
      remainingAmount: remaining,
    );
  }

  FinanceSummary summarise({
    List<FinanceTransaction> transactions = const <FinanceTransaction>[],
    List<SavingsGoal> savings = const <SavingsGoal>[],
    List<Liability> liabilities = const <Liability>[],
    DateTime? now,
  }) {
    return FinanceSummary.from(
      transactions: transactions,
      savings: savings,
      liabilities: liabilities,
      now: now ?? september,
    );
  }

  group('balance', () {
    test('is all recorded income minus all recorded expense', () {
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(amount: 500000, type: TransactionType.income, id: 'a'),
          tx(amount: 120000, type: TransactionType.expense, id: 'b'),
          tx(amount: 30000, type: TransactionType.expense, id: 'c'),
        ],
      );

      expect(summary.balance, 350000);
    });

    test('goes negative rather than flooring at zero', () {
      // Expenses entered before the salary that covers them is an ordinary
      // state, not an error — and a balance clamped to 0 would hide it.
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(amount: 80000, type: TransactionType.expense),
        ],
      );

      expect(summary.balance, -80000);
    });

    test('counts every month, not only the current one', () {
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(
            amount: 100000,
            type: TransactionType.income,
            date: DateTime(2026, 1, 5),
            id: 'a',
          ),
          tx(amount: 40000, type: TransactionType.income, id: 'b'),
        ],
      );

      expect(summary.balance, 140000);
      expect(summary.monthIncome, 40000, reason: 'only September is this month');
    });
  });

  group('this month', () {
    test('splits income and expense instead of only netting them', () {
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(amount: 300000, type: TransactionType.income, id: 'a'),
          tx(amount: 110000, type: TransactionType.expense, id: 'b'),
        ],
      );

      expect(summary.monthIncome, 300000);
      expect(summary.monthExpense, 110000);
      expect(summary.monthNet, 190000);
    });

    test('excludes the same day in a different year', () {
      // Matching on month alone would fold last September into this one — a
      // bug that stays invisible for the first twelve months of use.
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(
            amount: 999000,
            type: TransactionType.income,
            date: DateTime(2025, 9, 13),
          ),
        ],
      );

      expect(summary.monthIncome, 0);
      expect(summary.balance, 999000, reason: 'still counts all-time');
    });

    test('includes the first and last instant of the month', () {
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(
            amount: 1000,
            type: TransactionType.income,
            date: DateTime(2026, 9, 1),
            id: 'first',
          ),
          tx(
            amount: 2000,
            type: TransactionType.income,
            date: DateTime(2026, 9, 30, 23, 59, 59),
            id: 'last',
          ),
          tx(
            amount: 4000,
            type: TransactionType.income,
            date: DateTime(2026, 10, 1),
            id: 'next',
          ),
        ],
      );

      expect(summary.monthIncome, 3000);
    });

    test('uses the date the money moved, not when the row was created', () {
      // January's rent typed in February must count against January.
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          FinanceTransaction(
            id: 'r',
            amount: 90000,
            type: TransactionType.expense,
            category: 'home',
            date: DateTime(2026, 8, 30),
            createdAt: september,
            updatedAt: september,
          ),
        ],
      );

      expect(summary.monthExpense, 0);
    });

    test('net is negative when the month spent more than it earned', () {
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(amount: 50000, type: TransactionType.income, id: 'a'),
          tx(amount: 75000, type: TransactionType.expense, id: 'b'),
        ],
      );

      expect(summary.monthNet, -25000);
    });
  });

  group('savings', () {
    test('sums across every goal', () {
      final FinanceSummary summary = summarise(
        savings: <SavingsGoal>[
          goal(target: 100000, current: 25000, id: 'a'),
          goal(target: 300000, current: 75000, id: 'b'),
        ],
      );

      expect(summary.savedTotal, 100000);
      expect(summary.savingsTarget, 400000);
      expect(summary.savingsProgress, 0.25);
      expect(summary.goalCount, 2);
    });

    test('progress clamps so an over-saved total cannot overdraw the bar', () {
      final FinanceSummary summary = summarise(
        savings: <SavingsGoal>[goal(target: 100000, current: 150000)],
      );

      expect(summary.savingsProgress, 1);
      expect(summary.savedTotal, 150000, reason: 'the real figure is unclamped');
    });

    test('progress is zero with no goals rather than NaN', () {
      // 0/0 is NaN, and a progress bar given NaN throws in debug and paints
      // nothing in release — with no clue as to why.
      expect(summarise().savingsProgress, 0);
      expect(summarise().savingsProgress.isNaN, isFalse);
    });
  });

  group('liabilities', () {
    test('sums remaining and original across every debt', () {
      final FinanceSummary summary = summarise(
        liabilities: <Liability>[
          debt(original: 1000000, remaining: 400000, id: 'a'),
          debt(original: 1000000, remaining: 600000, id: 'b'),
        ],
      );

      expect(summary.debtRemaining, 1000000);
      expect(summary.debtOriginal, 2000000);
      expect(summary.debtProgress, 0.5);
      expect(summary.debtCount, 2);
    });

    test('progress counts down the debt, so nearly repaid is nearly full', () {
      final FinanceSummary summary = summarise(
        liabilities: <Liability>[debt(original: 1000000, remaining: 100000)],
      );

      expect(summary.debtProgress, closeTo(0.9, 1e-9));
    });

    test('a debt grown past what was borrowed clamps at zero progress', () {
      // Interest and late fees make this real — see the liability rules, which
      // deliberately do not cap remainingAmount at originalAmount.
      final FinanceSummary summary = summarise(
        liabilities: <Liability>[debt(original: 500000, remaining: 700000)],
      );

      expect(summary.debtProgress, 0);
      expect(summary.debtRemaining, 700000);
    });

    test('progress is zero with no debts rather than NaN', () {
      expect(summarise().debtProgress, 0);
      expect(summarise().debtProgress.isNaN, isFalse);
    });
  });

  group('isEmpty', () {
    test('is true only when nothing is recorded anywhere', () {
      expect(summarise().isEmpty, isTrue);
      expect(FinanceSummary.empty.isEmpty, isTrue);
    });

    test('is false when a goal exists but no transaction does', () {
      // The dashboard shows tiles, not the invitation, as soon as there is
      // anything at all to total.
      final FinanceSummary summary = summarise(
        savings: <SavingsGoal>[goal(target: 100000, current: 0)],
      );

      expect(summary.isEmpty, isFalse);
    });

    test('is false when a debt exists but no transaction does', () {
      final FinanceSummary summary = summarise(
        liabilities: <Liability>[debt(original: 100000, remaining: 100000)],
      );

      expect(summary.isEmpty, isFalse);
    });

    test('is false for a transaction that nets to zero', () {
      // A balance of 0 is not the same as nothing recorded, and showing the
      // "nothing yet" invitation over real data would look broken.
      final FinanceSummary summary = summarise(
        transactions: <FinanceTransaction>[
          tx(amount: 1000, type: TransactionType.income, id: 'a'),
          tx(amount: 1000, type: TransactionType.expense, id: 'b'),
        ],
      );

      expect(summary.balance, 0);
      expect(summary.isEmpty, isFalse);
    });
  });
}
