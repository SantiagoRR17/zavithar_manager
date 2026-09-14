// Unit tests for the chart data — Milestone 4.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/dashboard/domain/spending_insights.dart';
import 'package:zavithar_manager/features/finance/domain/finance_transaction.dart';
import 'package:zavithar_manager/features/finance/domain/monthly_statement.dart';
import 'package:zavithar_manager/features/finance/domain/statement_period.dart';

void main() {
  final DateTime september = DateTime(2026, 9, 15);

  FinanceTransaction tx({
    required num amount,
    required String category,
    DateTime? date,
    TransactionType type = TransactionType.expense,
    String id = 't',
  }) {
    return FinanceTransaction(
      id: id,
      amount: amount,
      type: type,
      category: category,
      date: date ?? DateTime(2026, 9, 5),
    );
  }

  MonthlyStatement statement(
    StatementPeriod period, {
    num income = 0,
    num expense = 0,
  }) {
    return MonthlyStatement(
      period: period,
      totalIncome: income,
      totalExpense: expense,
      openingBalance: 0,
      transactionCount: 1,
      incomeByCategory: const <String, num>{},
      expenseByCategory: const <String, num>{},
    );
  }

  group('byCategory', () {
    test('sums expenses per category, largest first', () {
      final List<CategorySpend> rows = SpendingInsights.byCategory(
        <FinanceTransaction>[
          tx(amount: 50000, category: 'transport', id: 'a'),
          tx(amount: 200000, category: 'groceries', id: 'b'),
          tx(amount: 100000, category: 'groceries', id: 'c'),
        ],
        now: september,
      );

      expect(rows.map((CategorySpend r) => r.category), <String>[
        'groceries',
        'transport',
      ]);
      expect(rows.first.amount, 300000);
    });

    test('excludes income', () {
      // A chart titled "where it went" that nets a refund against a purchase
      // is answering a different question from the one it asks.
      final List<CategorySpend> rows = SpendingInsights.byCategory(
        <FinanceTransaction>[
          tx(amount: 100000, category: 'groceries', id: 'a'),
          tx(
            amount: 900000,
            category: 'salary',
            type: TransactionType.income,
            id: 'b',
          ),
        ],
        now: september,
      );

      expect(rows.length, 1);
      expect(rows.single.category, 'groceries');
    });

    test('excludes other months', () {
      final List<CategorySpend> rows = SpendingInsights.byCategory(
        <FinanceTransaction>[
          tx(
            amount: 500000,
            category: 'rent',
            date: DateTime(2026, 8, 1),
            id: 'a',
          ),
          tx(
            amount: 10000,
            category: 'rent',
            date: DateTime(2026, 9, 1),
            id: 'b',
          ),
        ],
        now: september,
      );

      expect(rows.single.amount, 10000);
    });

    test('folds the tail into one row past the limit', () {
      // Past about seven bars the small ones are noise and the chart stops
      // being a comparison.
      final List<FinanceTransaction> many = <FinanceTransaction>[
        for (int i = 0; i < 12; i++)
          tx(amount: 100 * (12 - i), category: 'c$i', id: 'x$i'),
      ];

      final List<CategorySpend> rows = SpendingInsights.byCategory(
        many,
        now: september,
        limit: 5,
      );

      expect(rows.length, 5);
      expect(rows.last.category, 'other');
      // The tail keeps its total rather than being dropped.
      expect(
        rows.fold<num>(0, (num s, CategorySpend r) => s + r.amount),
        many.fold<num>(0, (num s, FinanceTransaction t) => s + t.amount),
      );
    });

    test('an exact fit is not folded', () {
      final List<FinanceTransaction> five = <FinanceTransaction>[
        for (int i = 0; i < 5; i++) tx(amount: 100, category: 'c$i', id: 'x$i'),
      ];
      final List<CategorySpend> rows = SpendingInsights.byCategory(
        five,
        now: september,
        limit: 5,
      );
      expect(rows.any((CategorySpend r) => r.category == 'other'), isFalse);
    });

    test('nothing spent yields an empty list, not a zero row', () {
      expect(
        SpendingInsights.byCategory(
          const <FinanceTransaction>[],
          now: september,
        ),
        isEmpty,
      );
    });
  });

  group('byMonth', () {
    test('reads closed months from their statements', () {
      // The payoff of ADR 0012 at its clearest: a year of history is a dozen
      // documents rather than thousands of transactions.
      final List<MonthlyTotals> series = SpendingInsights.byMonth(
        statements: <MonthlyStatement>[
          statement(const StatementPeriod(2026, 7), income: 500, expense: 200),
          statement(const StatementPeriod(2026, 8), income: 600, expense: 700),
        ],
        openTransactions: const <FinanceTransaction>[],
        now: september,
      );

      expect(series.map((MonthlyTotals m) => m.period.id), <String>[
        '2026-07',
        '2026-08',
        '2026-09',
      ]);
      expect(series[0].net, 300);
      expect(series[1].net, -100);
    });

    test('computes the current month from open transactions and marks it', () {
      final List<MonthlyTotals> series = SpendingInsights.byMonth(
        statements: const <MonthlyStatement>[],
        openTransactions: <FinanceTransaction>[
          tx(
            amount: 60000,
            category: 'salary',
            type: TransactionType.income,
            id: 'a',
          ),
          tx(amount: 13000, category: 'groceries', id: 'b'),
        ],
        now: september,
      );

      expect(series.single.isOpen, isTrue);
      expect(series.single.net, 47000);
    });

    test('the current month is present even when empty', () {
      // Unlike a historical gap, "nothing yet this month" is a fact, and
      // omitting it would make the chart appear to end last month.
      final List<MonthlyTotals> series = SpendingInsights.byMonth(
        statements: <MonthlyStatement>[
          statement(const StatementPeriod(2026, 8), income: 100),
        ],
        openTransactions: const <FinanceTransaction>[],
        now: september,
      );

      expect(series.last.period, const StatementPeriod(2026, 9));
      expect(series.last.net, 0);
      expect(series.last.isOpen, isTrue);
    });

    test('months with no record are absent, not drawn as zero', () {
      // A gap in the record is not a month in which nothing happened, and a
      // flat bar would say it was.
      final List<MonthlyTotals> series = SpendingInsights.byMonth(
        statements: <MonthlyStatement>[
          statement(const StatementPeriod(2026, 5), income: 100),
          statement(const StatementPeriod(2026, 8), income: 100),
        ],
        openTransactions: const <FinanceTransaction>[],
        now: september,
      );

      expect(series.map((MonthlyTotals m) => m.period.id), <String>[
        '2026-05',
        '2026-08',
        '2026-09',
      ]);
    });

    test('keeps only the most recent months requested', () {
      final List<MonthlyTotals> series = SpendingInsights.byMonth(
        statements: <MonthlyStatement>[
          for (int m = 1; m <= 8; m++)
            statement(StatementPeriod(2026, m), income: 100),
        ],
        openTransactions: const <FinanceTransaction>[],
        now: september,
        months: 3,
      );

      expect(series.map((MonthlyTotals m) => m.period.id), <String>[
        '2026-07',
        '2026-08',
        '2026-09',
      ]);
    });

    test('a statement for the current month does not duplicate it', () {
      // Closing September and then looking at the chart the same day must not
      // draw two bars for September.
      final List<MonthlyTotals> series = SpendingInsights.byMonth(
        statements: <MonthlyStatement>[
          statement(const StatementPeriod(2026, 9), income: 999),
        ],
        openTransactions: const <FinanceTransaction>[],
        now: september,
      );

      expect(series.length, 1);
      expect(series.single.period, const StatementPeriod(2026, 9));
    });
  });

  group('peakNet', () {
    test('takes the largest magnitude in either direction', () {
      final List<MonthlyTotals> series = <MonthlyTotals>[
        MonthlyTotals(
          period: const StatementPeriod(2026, 7),
          income: 100,
          expense: 900,
          isOpen: false,
        ),
        MonthlyTotals(
          period: const StatementPeriod(2026, 8),
          income: 400,
          expense: 100,
          isOpen: false,
        ),
      ];

      expect(SpendingInsights.peakNet(series), 800);
    });

    test('is zero for an empty series, so callers do not divide by it', () {
      expect(SpendingInsights.peakNet(const <MonthlyTotals>[]), 0);
    });
  });
}
