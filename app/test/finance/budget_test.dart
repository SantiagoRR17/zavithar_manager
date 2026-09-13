// Unit tests for budgets — Milestone 4.
//
// The pace arithmetic gets the attention. A budget that only reports "60% of
// your limit is gone" is decoration: the same number is excellent on the 25th
// and alarming on the 3rd, and the whole value of the feature is in telling
// those apart before the bar fills.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/finance/domain/budget.dart';
import 'package:zavithar_manager/features/finance/domain/finance_transaction.dart';

void main() {
  FinanceTransaction tx({
    required num amount,
    required DateTime date,
    String category = 'groceries',
    TransactionType type = TransactionType.expense,
    String id = 't',
  }) {
    return FinanceTransaction(
      id: id,
      amount: amount,
      type: type,
      category: category,
      date: date,
    );
  }

  Budget budget({String category = 'groceries', num limit = 400000}) =>
      Budget(category: category, monthlyLimit: limit);

  group('spending is counted', () {
    test('only for expenses, never income', () {
      // A refund landing in `groceries` must not buy back room to spend.
      final List<BudgetStatus> statuses = BudgetReport.from(
        budgets: <Budget>[budget()],
        transactions: <FinanceTransaction>[
          tx(amount: 100000, date: DateTime(2026, 9, 5), id: 'a'),
          tx(
            amount: 50000,
            date: DateTime(2026, 9, 6),
            type: TransactionType.income,
            id: 'b',
          ),
        ],
        now: DateTime(2026, 9, 15),
      );

      expect(statuses.single.spent, 100000);
    });

    test('only for the current calendar month', () {
      final List<BudgetStatus> statuses = BudgetReport.from(
        budgets: <Budget>[budget()],
        transactions: <FinanceTransaction>[
          tx(amount: 90000, date: DateTime(2026, 8, 31), id: 'last'),
          tx(amount: 10000, date: DateTime(2026, 9, 1), id: 'this'),
          tx(amount: 70000, date: DateTime(2026, 10, 1), id: 'next'),
        ],
        now: DateTime(2026, 9, 15),
      );

      expect(statuses.single.spent, 10000);
    });

    test('only in the budget\'s own category', () {
      final List<BudgetStatus> statuses = BudgetReport.from(
        budgets: <Budget>[budget(category: 'rent')],
        transactions: <FinanceTransaction>[
          tx(
            amount: 900000,
            date: DateTime(2026, 9, 2),
            category: 'rent',
            id: 'a',
          ),
          tx(
            amount: 20000,
            date: DateTime(2026, 9, 3),
            category: 'transport',
            id: 'b',
          ),
        ],
        now: DateTime(2026, 9, 15),
      );

      expect(statuses.single.spent, 900000);
    });

    test('a category with no spending reports zero, not absence', () {
      final List<BudgetStatus> statuses = BudgetReport.from(
        budgets: <Budget>[budget()],
        transactions: const <FinanceTransaction>[],
        now: DateTime(2026, 9, 15),
      );

      expect(statuses.single.spent, 0);
      expect(statuses.single.remaining, 400000);
    });
  });

  group('remaining and overspend', () {
    BudgetStatus status(num spent) =>
        BudgetStatus(budget: budget(limit: 400000), spent: spent);

    test('remaining never goes negative', () {
      expect(status(500000).remaining, 0);
      expect(status(400000).remaining, 0);
      expect(status(150000).remaining, 250000);
    });

    test('overspend reports the excess and is zero below the limit', () {
      expect(status(500000).overspend, 100000);
      expect(status(150000).overspend, 0);
    });

    test('exactly at the limit is not over', () {
      // Spending your whole budget is the plan working, not a failure.
      expect(status(400000).isOver, isFalse);
      expect(status(400001).isOver, isTrue);
    });

    test('progress clamps so an overspent bar cannot overdraw its track', () {
      expect(status(800000).progress, 1);
    });

    test('a zero limit yields zero progress rather than NaN', () {
      // Not reachable through the form or the rules, but reachable from the
      // console — and a bar handed NaN throws in debug and paints nothing in
      // release.
      final BudgetStatus s = BudgetStatus(budget: budget(limit: 0), spent: 100);
      expect(s.progress, 0);
      expect(s.progress.isNaN, isFalse);
    });
  });

  group('pace', () {
    // September has 30 days, so the 15th is very nearly half way.
    final DateTime midMonth = DateTime(2026, 9, 16);

    test('half the budget spent at half the month is exactly on pace', () {
      final BudgetStatus s = BudgetStatus(
        budget: budget(limit: 400000),
        spent: 200000,
      );
      expect(s.pace(now: midMonth), closeTo(1.0, 0.05));
    });

    test('the same percentage is fine late and alarming early', () {
      // This is the entire argument for the feature. 60% spent is the same
      // number on both days and means opposite things.
      final BudgetStatus s = BudgetStatus(
        budget: budget(limit: 400000),
        spent: 240000,
      );

      expect(s.pace(now: DateTime(2026, 9, 4)), greaterThan(2));
      expect(s.pace(now: DateTime(2026, 9, 26)), lessThan(1));
    });

    test(
      'spending on the first instant of the month is infinite, not a crash',
      () {
        final BudgetStatus s = BudgetStatus(
          budget: budget(limit: 400000),
          spent: 1000,
        );
        expect(s.pace(now: DateTime(2026, 9, 1)), double.infinity);
      },
    );

    test('nothing spent on the first instant is zero, not infinite', () {
      final BudgetStatus s = BudgetStatus(budget: budget(), spent: 0);
      expect(s.pace(now: DateTime(2026, 9, 1)), 0);
    });

    test('monthElapsed spans zero to one and respects month length', () {
      expect(BudgetStatus.monthElapsed(now: DateTime(2026, 9, 1)), 0);
      expect(
        BudgetStatus.monthElapsed(now: DateTime(2026, 9, 30, 23)),
        closeTo(0.97, 0.03),
      );
      // February is shorter, so the same day-of-month is further through it.
      expect(
        BudgetStatus.monthElapsed(now: DateTime(2026, 2, 15)),
        greaterThan(BudgetStatus.monthElapsed(now: DateTime(2026, 9, 15))),
      );
    });
  });

  group('ordering', () {
    test('puts the overspent first, then the fastest-burning', () {
      // A list sorted by category name would bury the one thing worth acting
      // on behind five that are fine.
      final DateTime now = DateTime(2026, 9, 16);
      final List<BudgetStatus> statuses = BudgetReport.from(
        budgets: <Budget>[
          budget(category: 'transport', limit: 100000),
          budget(category: 'groceries', limit: 100000),
          budget(category: 'health', limit: 100000),
        ],
        transactions: <FinanceTransaction>[
          // health: over.
          tx(
            amount: 130000,
            date: DateTime(2026, 9, 5),
            category: 'health',
            id: 'a',
          ),
          // groceries: within, but burning fast.
          tx(
            amount: 80000,
            date: DateTime(2026, 9, 5),
            category: 'groceries',
            id: 'b',
          ),
          // transport: barely touched.
          tx(
            amount: 5000,
            date: DateTime(2026, 9, 5),
            category: 'transport',
            id: 'c',
          ),
        ],
        now: now,
      );

      expect(statuses.map((BudgetStatus s) => s.category), <String>[
        'health',
        'groceries',
        'transport',
      ]);
    });

    test('the result cannot be mutated by the caller', () {
      final List<BudgetStatus> statuses = BudgetReport.from(
        budgets: <Budget>[budget()],
        transactions: const <FinanceTransaction>[],
        now: DateTime(2026, 9, 15),
      );
      expect(() => statuses.clear(), throwsUnsupportedError);
    });
  });

  group('summary figures', () {
    final List<BudgetStatus> statuses = <BudgetStatus>[
      BudgetStatus(budget: budget(category: 'a', limit: 100000), spent: 120000),
      BudgetStatus(budget: budget(category: 'b', limit: 200000), spent: 50000),
    ];

    test('counts the exceeded ones', () {
      expect(BudgetReport.overCount(statuses), 1);
    });

    test('totals both sides', () {
      final (num budgeted, num spent) = BudgetReport.totals(statuses);
      expect(budgeted, 300000);
      expect(spent, 170000);
    });
  });

  group('the document id is the category', () {
    test('toMap keeps the category as a readable copy of the id', () {
      // The rules insist the two agree, so a document cannot claim to budget
      // `rent` while living under `groceries`.
      expect(budget(category: 'rent').id, 'rent');
      expect(budget(category: 'rent').toMap()[Budget.fieldCategory], 'rent');
    });

    test('a document missing the field falls back to its id', () {
      expect(
        Budget.fromMap('transport', const <String, Object?>{
          'monthlyLimit': 50000,
        }).category,
        'transport',
      );
    });

    test('toMap never writes the audit timestamps', () {
      final Map<String, Object?> map = budget().toMap();
      expect(map.containsKey(Budget.fieldCreatedAt), isFalse);
      expect(map.containsKey(Budget.fieldUpdatedAt), isFalse);
    });
  });
}
