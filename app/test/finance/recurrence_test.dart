// Unit tests for recurring transactions — Milestone 4.
//
// Month arithmetic again, and again it is the part that fails silently: a
// schedule that drifts does not crash, it just starts charging rent on the
// wrong day and keeps doing it.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/finance/domain/finance_transaction.dart';
import 'package:zavithar_manager/features/finance/domain/recurring_rule.dart';

void main() {
  RecurringRule rule({
    Cadence cadence = Cadence.monthly,
    required DateTime nextRunAt,
    int? anchorDay,
    bool active = true,
    num amount = 900000,
  }) {
    return RecurringRule(
      id: 'r1',
      amount: amount,
      type: TransactionType.expense,
      category: 'rent',
      cadence: cadence,
      anchorDay: anchorDay ?? RecurrenceSchedule.anchorFor(nextRunAt, cadence),
      nextRunAt: nextRunAt,
      active: active,
    );
  }

  group('advance — monthly', () {
    test('keeps the same day in an ordinary month', () {
      expect(
        RecurrenceSchedule.advance(DateTime(2026, 9, 5), Cadence.monthly, 5),
        DateTime(2026, 10, 5),
      );
    });

    test('clamps to the last day of a shorter month', () {
      expect(
        RecurrenceSchedule.advance(DateTime(2026, 1, 31), Cadence.monthly, 31),
        DateTime(2026, 2, 28),
      );
    });

    test('**returns to the anchor after a clamp**', () {
      // The bug this design exists to prevent. Advancing from the clamped date
      // would give 28 March and then 28 April and so on, walking the rule
      // permanently earlier — a rent charge that quietly migrates to a
      // different day of the month and never comes back.
      final DateTime february = RecurrenceSchedule.advance(
        DateTime(2026, 1, 31),
        Cadence.monthly,
        31,
      );
      expect(february, DateTime(2026, 2, 28));

      final DateTime march = RecurrenceSchedule.advance(
        february,
        Cadence.monthly,
        31,
      );
      expect(march, DateTime(2026, 3, 31));
    });

    test('handles a leap February', () {
      expect(
        RecurrenceSchedule.advance(DateTime(2028, 1, 31), Cadence.monthly, 31),
        DateTime(2028, 2, 29),
      );
    });

    test('rolls from December into January', () {
      expect(
        RecurrenceSchedule.advance(DateTime(2026, 12, 15), Cadence.monthly, 15),
        DateTime(2027, 1, 15),
      );
    });

    test('a 30th anchor survives February and returns', () {
      final DateTime feb = RecurrenceSchedule.advance(
        DateTime(2026, 1, 30),
        Cadence.monthly,
        30,
      );
      expect(feb, DateTime(2026, 2, 28));
      expect(
        RecurrenceSchedule.advance(feb, Cadence.monthly, 30),
        DateTime(2026, 3, 30),
      );
    });

    test('keeps the time of day', () {
      expect(
        RecurrenceSchedule.advance(
          DateTime(2026, 9, 5, 14, 30),
          Cadence.monthly,
          5,
        ),
        DateTime(2026, 10, 5, 14, 30),
      );
    });
  });

  group('advance — weekly and yearly', () {
    test('weekly steps exactly seven days', () {
      expect(
        RecurrenceSchedule.advance(DateTime(2026, 9, 5), Cadence.weekly, 6),
        DateTime(2026, 9, 12),
      );
    });

    test('weekly keeps the same weekday across a month boundary', () {
      final DateTime start = DateTime(2026, 9, 28);
      final DateTime next = RecurrenceSchedule.advance(
        start,
        Cadence.weekly,
        start.weekday,
      );
      expect(next, DateTime(2026, 10, 5));
      expect(next.weekday, start.weekday);
    });

    test('yearly steps a year and clamps 29 February', () {
      expect(
        RecurrenceSchedule.advance(DateTime(2028, 2, 29), Cadence.yearly, 29),
        DateTime(2029, 2, 28),
      );
    });
  });

  group('what is due', () {
    test('nothing before the next run date', () {
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(nextRunAt: DateTime(2026, 10, 1)),
        now: DateTime(2026, 9, 20),
      );
      expect(run.dates, isEmpty);
      expect(run.nextRunAt, DateTime(2026, 10, 1));
    });

    test('the occurrence due exactly now counts', () {
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(nextRunAt: DateTime(2026, 9, 20)),
        now: DateTime(2026, 9, 20),
      );
      expect(run.dates.length, 1);
    });

    test('catches up everything missed while the app was closed', () {
      // Rent does not stop being owed because nobody opened the app.
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(nextRunAt: DateTime(2026, 6, 1)),
        now: DateTime(2026, 9, 20),
      );

      expect(run.dates, <DateTime>[
        DateTime(2026, 6, 1),
        DateTime(2026, 7, 1),
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      ]);
      expect(run.nextRunAt, DateTime(2026, 10, 1));
    });

    test('a paused rule produces nothing and does not advance', () {
      final RecurringRule paused = rule(
        nextRunAt: DateTime(2026, 6, 1),
        active: false,
      );
      final RecurrenceRun run = RecurrenceSchedule.due(
        paused,
        now: DateTime(2026, 9, 20),
      );

      expect(run.dates, isEmpty);
      expect(run.nextRunAt, DateTime(2026, 6, 1));
    });

    test('a long absence is capped rather than replayed in full', () {
      // Opening the app after two years on a weekly rule would otherwise write
      // a hundred transactions in one batch.
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(cadence: Cadence.weekly, nextRunAt: DateTime(2024, 1, 1)),
        now: DateTime(2026, 9, 20),
      );

      expect(run.dates.length, RecurrenceSchedule.maxCatchUp);
    });
  });

  group('closed months (ADR 0012)', () {
    test('occurrences before the open period are skipped, not created', () {
      // The rules would refuse them, and inventing a different date to slip
      // them past that would put money on a day it did not move.
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(nextRunAt: DateTime(2026, 6, 1)),
        now: DateTime(2026, 9, 20),
        openPeriodStart: DateTime(2026, 8, 1),
      );

      expect(run.skippedClosed, 2); // June and July
      expect(run.dates, <DateTime>[DateTime(2026, 8, 1), DateTime(2026, 9, 1)]);
    });

    test('the schedule still advances past what was skipped', () {
      // Otherwise the rule would offer the same impossible occurrence forever.
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(nextRunAt: DateTime(2026, 6, 1)),
        now: DateTime(2026, 9, 20),
        openPeriodStart: DateTime(2026, 8, 1),
      );

      expect(run.nextRunAt, DateTime(2026, 10, 1));
    });

    test('a skipped occurrence still counts against the catch-up cap', () {
      // Otherwise a rule whose whole history is closed would loop through
      // years of dates on every evaluation.
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(cadence: Cadence.weekly, nextRunAt: DateTime(2024, 1, 1)),
        now: DateTime(2026, 9, 20),
        openPeriodStart: DateTime(2026, 9, 1),
      );

      expect(
        run.dates.length + run.skippedClosed,
        RecurrenceSchedule.maxCatchUp,
      );
    });

    test('no boundary means nothing is skipped', () {
      final RecurrenceRun run = RecurrenceSchedule.due(
        rule(nextRunAt: DateTime(2026, 7, 1)),
        now: DateTime(2026, 9, 20),
      );
      expect(run.skippedClosed, 0);
      expect(run.dates.length, 3);
    });
  });

  group('the template', () {
    test('produces an ordinary transaction, dated to the occurrence', () {
      final RecurringRule r = rule(nextRunAt: DateTime(2026, 9, 1));
      final FinanceTransaction tx = r.transactionFor(DateTime(2026, 10, 1));

      expect(tx.amount, 900000);
      expect(tx.category, 'rent');
      expect(tx.type, TransactionType.expense);
      expect(tx.date, DateTime(2026, 10, 1));
      // Firestore assigns the id on write.
      expect(tx.id, '');
    });

    test('toMap omits empty optionals and the audit timestamps', () {
      final Map<String, Object?> map = rule(nextRunAt: DateTime(2026, 9, 1))
          .toMap();

      expect(map.containsKey(RecurringRule.fieldDescription), isFalse);
      expect(map.containsKey(RecurringRule.fieldAccount), isFalse);
      expect(map.containsKey(RecurringRule.fieldCreatedAt), isFalse);
      expect(map.containsKey(RecurringRule.fieldUpdatedAt), isFalse);
    });

    test('anchorFor reads the day for monthly and the weekday for weekly', () {
      final DateTime d = DateTime(2026, 9, 17); // a Thursday
      expect(RecurrenceSchedule.anchorFor(d, Cadence.monthly), 17);
      expect(RecurrenceSchedule.anchorFor(d, Cadence.weekly), d.weekday);
    });

    test('the first run is the start date itself', () {
      // A rule created on payday for today's salary should record today's
      // salary, not wait a month.
      final DateTime start = DateTime(2026, 9, 20);
      expect(RecurrenceSchedule.firstRun(start), start);
    });

    test('an unknown cadence on disk reads back as monthly', () {
      expect(Cadence.fromWire('fortnightly'), Cadence.monthly);
      expect(Cadence.fromWire(null), Cadence.monthly);
    });
  });
}
