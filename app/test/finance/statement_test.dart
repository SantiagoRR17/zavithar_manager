// Unit tests for monthly statements — ADR 0012.
//
// Month arithmetic gets the most attention here, because an off-by-one in a
// period boundary does not crash. It moves money into the wrong statement, or
// into none at all, and the app carries on looking perfectly healthy.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/dashboard/domain/finance_summary.dart';
import 'package:zavithar_manager/features/finance/domain/finance_transaction.dart';
import 'package:zavithar_manager/features/finance/domain/liability.dart';
import 'package:zavithar_manager/features/finance/domain/monthly_statement.dart';
import 'package:zavithar_manager/features/finance/domain/savings_goal.dart';
import 'package:zavithar_manager/features/finance/domain/statement_period.dart';

void main() {
  FinanceTransaction tx({
    required num amount,
    required TransactionType type,
    required DateTime date,
    String category = 'other',
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

  group('StatementPeriod — identity', () {
    test('the id zero-pads the month so it sorts chronologically', () {
      // Lexicographic order has to *be* chronological order: that is what lets
      // Firestore sort statements by document name with no index. `2026-9`
      // would sort after `2026-10`.
      expect(const StatementPeriod(2026, 9).id, '2026-09');
      expect(const StatementPeriod(2026, 12).id, '2026-12');

      final List<String> ids = <String>[
        const StatementPeriod(2026, 10).id,
        const StatementPeriod(2026, 9).id,
        const StatementPeriod(2027, 1).id,
      ]..sort();
      expect(ids, <String>['2026-09', '2026-10', '2027-01']);
    });

    test('tryParse round-trips, and rejects nonsense instead of throwing', () {
      expect(
        StatementPeriod.tryParse('2026-09'),
        const StatementPeriod(2026, 9),
      );
      expect(
        StatementPeriod.tryParse('2026-9'),
        const StatementPeriod(2026, 9),
      );

      // A document ID is data from a database; one malformed row must not take
      // down the statements list.
      expect(StatementPeriod.tryParse('nonsense'), isNull);
      expect(StatementPeriod.tryParse('2026'), isNull);
      expect(StatementPeriod.tryParse('2026-13'), isNull);
      expect(StatementPeriod.tryParse('2026-00'), isNull);
      expect(StatementPeriod.tryParse(''), isNull);
    });
  });

  group('StatementPeriod — boundaries', () {
    test('runs from the first of the month to the first of the next', () {
      const StatementPeriod sep = StatementPeriod(2026, 9);
      expect(sep.start, DateTime(2026, 9, 1));
      expect(sep.endExclusive, DateTime(2026, 10, 1));
    });

    test('December rolls into the next January', () {
      // Dart normalises DateTime(2026, 13, 1); the point of the test is that
      // nobody later "fixes" it with a hand-written conditional that is wrong.
      const StatementPeriod dec = StatementPeriod(2026, 12);
      expect(dec.endExclusive, DateTime(2027, 1, 1));
      expect(dec.next, const StatementPeriod(2027, 1));
    });

    test('January steps back into the previous December', () {
      expect(
        const StatementPeriod(2027, 1).previous,
        const StatementPeriod(2026, 12),
      );
    });

    test('February is 28 or 29 days without anyone counting', () {
      expect(const StatementPeriod(2026, 2).endExclusive, DateTime(2026, 3, 1));
      // 2028 is a leap year.
      expect(const StatementPeriod(2028, 2).endExclusive, DateTime(2028, 3, 1));
      expect(const StatementPeriod(2028, 2).endInclusive.day, 29);
    });

    test(
      'contains is inclusive of the first instant and exclusive of the last',
      () {
        const StatementPeriod sep = StatementPeriod(2026, 9);
        expect(sep.contains(DateTime(2026, 9, 1)), isTrue);
        expect(sep.contains(DateTime(2026, 9, 30, 23, 59, 59)), isTrue);
        expect(sep.contains(DateTime(2026, 10, 1)), isFalse);
        expect(sep.contains(DateTime(2026, 8, 31, 23, 59, 59)), isFalse);
      },
    );
  });

  group('StatementPeriod — hasEnded', () {
    const StatementPeriod sep = StatementPeriod(2026, 9);

    test('a month still running cannot be closed', () {
      // Half a month's totals written as if they were the whole month's is the
      // silent wrongness the whole feature exists to avoid.
      expect(sep.hasEnded(now: DateTime(2026, 9, 30, 23, 59)), isFalse);
    });

    test('it ends the instant the next month begins', () {
      expect(sep.hasEnded(now: DateTime(2026, 10, 1)), isTrue);
    });

    test('a long-past month has ended', () {
      expect(sep.hasEnded(now: DateTime(2027, 5, 1)), isTrue);
    });
  });

  group('StatementPeriod — ordering', () {
    test('compares by year then month, across the year boundary', () {
      expect(
        const StatementPeriod(2026, 12) < const StatementPeriod(2027, 1),
        isTrue,
      );
      expect(
        const StatementPeriod(2027, 1) > const StatementPeriod(2026, 12),
        isTrue,
      );
      expect(
        const StatementPeriod(2026, 3) < const StatementPeriod(2026, 11),
        isTrue,
      );
      expect(
        const StatementPeriod(2026, 3) == const StatementPeriod(2026, 3),
        isTrue,
      );
    });
  });

  group('MonthlyStatement.from', () {
    const StatementPeriod sep = StatementPeriod(2026, 9);

    test('totals income and expense separately', () {
      final MonthlyStatement s = MonthlyStatement.from(
        period: sep,
        openingBalance: 0,
        transactions: <FinanceTransaction>[
          tx(
            amount: 500000,
            type: TransactionType.income,
            date: DateTime(2026, 9, 5),
            id: 'a',
          ),
          tx(
            amount: 120000,
            type: TransactionType.expense,
            date: DateTime(2026, 9, 9),
            id: 'b',
          ),
        ],
      );

      expect(s.totalIncome, 500000);
      expect(s.totalExpense, 120000);
      expect(s.net, 380000);
      expect(s.transactionCount, 2);
    });

    test(
      'ignores transactions outside the period rather than absorbing them',
      () {
        // The caller filters, but a statement that silently swallowed a
        // neighbouring month's rows would be wrong in a way nothing downstream
        // could detect.
        final MonthlyStatement s = MonthlyStatement.from(
          period: sep,
          openingBalance: 0,
          transactions: <FinanceTransaction>[
            tx(
              amount: 100,
              type: TransactionType.income,
              date: DateTime(2026, 8, 31),
              id: 'before',
            ),
            tx(
              amount: 200,
              type: TransactionType.income,
              date: DateTime(2026, 9, 15),
              id: 'inside',
            ),
            tx(
              amount: 400,
              type: TransactionType.income,
              date: DateTime(2026, 10, 1),
              id: 'after',
            ),
          ],
        );

        expect(s.totalIncome, 200);
        expect(s.transactionCount, 1);
      },
    );

    test('keeps income and expense per category in separate maps', () {
      // A single signed map would collapse a category that saw both — `other`,
      // routinely — to their difference and lose both real figures.
      final MonthlyStatement s = MonthlyStatement.from(
        period: sep,
        openingBalance: 0,
        transactions: <FinanceTransaction>[
          tx(
            amount: 300,
            type: TransactionType.income,
            date: DateTime(2026, 9, 2),
            category: 'other',
            id: 'a',
          ),
          tx(
            amount: 100,
            type: TransactionType.expense,
            date: DateTime(2026, 9, 3),
            category: 'other',
            id: 'b',
          ),
          tx(
            amount: 50,
            type: TransactionType.expense,
            date: DateTime(2026, 9, 4),
            category: 'rent',
            id: 'c',
          ),
        ],
      );

      expect(s.incomeByCategory['other'], 300);
      expect(s.expenseByCategory['other'], 100);
      expect(s.expenseByCategory['rent'], 50);
    });

    test('the closing balance carries the opening balance forward', () {
      final MonthlyStatement s = MonthlyStatement.from(
        period: sep,
        openingBalance: 1000,
        transactions: <FinanceTransaction>[
          tx(
            amount: 500,
            type: TransactionType.income,
            date: DateTime(2026, 9, 5),
          ),
        ],
      );

      expect(s.openingBalance, 1000);
      expect(s.closingBalance, 1500);
    });

    test('statements chain, so a closing balance is the next opening one', () {
      final MonthlyStatement august = MonthlyStatement.from(
        period: const StatementPeriod(2026, 8),
        openingBalance: 0,
        transactions: <FinanceTransaction>[
          tx(
            amount: 60000,
            type: TransactionType.income,
            date: DateTime(2026, 8, 25),
            id: 'a',
          ),
          tx(
            amount: 13000,
            type: TransactionType.expense,
            date: DateTime(2026, 8, 25),
            id: 'b',
          ),
        ],
      );
      final MonthlyStatement september = MonthlyStatement.from(
        period: sep,
        openingBalance: august.closingBalance,
        transactions: <FinanceTransaction>[
          tx(
            amount: 7000,
            type: TransactionType.expense,
            date: DateTime(2026, 9, 10),
          ),
        ],
      );

      expect(august.closingBalance, 47000);
      expect(september.openingBalance, 47000);
      expect(september.closingBalance, 40000);
    });

    test('an empty month is a valid statement, not a missing one', () {
      // Contiguity is correctness: a quiet month still has to be closed, or the
      // month after it cannot be.
      final MonthlyStatement s = MonthlyStatement.from(
        period: sep,
        openingBalance: 500,
        transactions: const <FinanceTransaction>[],
      );

      expect(s.transactionCount, 0);
      expect(s.net, 0);
      expect(s.closingBalance, 500);
    });

    test(
      'toMap writes a closing balance that reconciles, as the rules demand',
      () {
        final MonthlyStatement s = MonthlyStatement.from(
          period: sep,
          openingBalance: 200,
          transactions: <FinanceTransaction>[
            tx(
              amount: 90,
              type: TransactionType.expense,
              date: DateTime(2026, 9, 9),
            ),
          ],
        );
        final Map<String, Object?> map = s.toMap();

        expect(
          map[MonthlyStatement.fieldClosingBalance],
          (map[MonthlyStatement.fieldOpeningBalance] as num) +
              (map[MonthlyStatement.fieldTotalIncome] as num) -
              (map[MonthlyStatement.fieldTotalExpense] as num),
        );
        // closedAt is the repository's to stamp — it is a FieldValue.
        expect(map.containsKey(MonthlyStatement.fieldClosedAt), isFalse);
      },
    );
  });

  group('FinanceSummary with closed months', () {
    test('the balance is the closed net plus the open period', () {
      // The transactions stream only carries the open period once a month has
      // been closed. Without the opening balance the headline figure would
      // silently reset to zero on the first close — the most alarming possible
      // way for a cost optimisation to go wrong.
      final FinanceSummary summary = FinanceSummary.from(
        transactions: <FinanceTransaction>[
          tx(
            amount: 5000,
            type: TransactionType.income,
            date: DateTime(2026, 10, 3),
          ),
        ],
        savings: const <SavingsGoal>[],
        liabilities: const <Liability>[],
        openingBalance: 47000,
        now: DateTime(2026, 10, 15),
      );

      expect(summary.balance, 52000);
    });

    test('history in closed statements is not an empty account', () {
      // Otherwise the new-account invitation would appear on the first of every
      // month, right after the previous one was closed.
      final FinanceSummary summary = FinanceSummary.from(
        transactions: const <FinanceTransaction>[],
        savings: const <SavingsGoal>[],
        liabilities: const <Liability>[],
        openingBalance: 47000,
      );

      expect(summary.isEmpty, isFalse);
      expect(summary.balance, 47000);
    });

    test('genuinely empty is still empty', () {
      expect(
        FinanceSummary.from(
          transactions: const <FinanceTransaction>[],
          savings: const <SavingsGoal>[],
          liabilities: const <Liability>[],
        ).isEmpty,
        isTrue,
      );
    });
  });
}
