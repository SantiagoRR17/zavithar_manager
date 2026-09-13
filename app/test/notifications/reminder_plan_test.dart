// Unit tests for the reminder scheduling policy — Milestone 3, ADR 0011.
//
// Worth testing hard for a reason particular to this feature: **a scheduling
// bug has no symptom.** Nothing crashes, no screen looks wrong, no error is
// logged. A reminder simply never arrives, and the first time anyone notices is
// the day it mattered. These are the only checks that will ever catch it.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/notifications/domain/reminder_plan.dart';
import 'package:zavithar_manager/features/todos/domain/todo.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 13, 10);

  Todo todo({
    String id = 't',
    String title = 'Task',
    DateTime? reminderAt,
    DateTime? deadline,
    TodoStatus status = TodoStatus.pending,
    String category = 'work',
  }) {
    return Todo(
      id: id,
      title: title,
      category: category,
      status: status,
      reminderAt: reminderAt,
      deadline: deadline,
    );
  }

  group('what gets scheduled', () {
    test('a future reminder on an open task', () {
      final List<ScheduledReminder> plan = ReminderPlan.from(<Todo>[
        todo(id: 'a', reminderAt: DateTime(2026, 9, 14, 9)),
      ], now: now);

      expect(plan.length, 1);
      expect(plan.single.todoId, 'a');
      expect(plan.single.at, DateTime(2026, 9, 14, 9));
    });

    test('a task with no reminder is not scheduled', () {
      expect(ReminderPlan.from(<Todo>[todo()], now: now), isEmpty);
    });

    test('a completed task is not scheduled', () {
      // A reminder that fires for something already ticked off teaches the user
      // to ignore notifications, which costs more than the one it saved.
      final List<ScheduledReminder> plan = ReminderPlan.from(<Todo>[
        todo(reminderAt: DateTime(2026, 9, 20), status: TodoStatus.completed),
      ], now: now);

      expect(plan, isEmpty);
    });

    test('an in-progress task is still scheduled', () {
      final List<ScheduledReminder> plan = ReminderPlan.from(<Todo>[
        todo(reminderAt: DateTime(2026, 9, 20), status: TodoStatus.inProgress),
      ], now: now);

      expect(plan.length, 1);
    });

    test('a reminder in the past is dropped, not fired immediately', () {
      // Scheduling a past alarm either throws or fires at once depending on the
      // platform, and firing at once is worse: opening the app after a holiday
      // would dump a week of stale reminders into the shade together.
      final List<ScheduledReminder> plan = ReminderPlan.from(<Todo>[
        todo(id: 'old', reminderAt: DateTime(2026, 9, 12)),
        todo(id: 'new', reminderAt: DateTime(2026, 9, 14)),
      ], now: now);

      expect(plan.map((ScheduledReminder r) => r.todoId), <String>['new']);
    });

    test('a reminder exactly now is not scheduled', () {
      expect(
        ReminderPlan.from(<Todo>[todo(reminderAt: now)], now: now),
        isEmpty,
      );
    });
  });

  group('ordering and the cap', () {
    test('soonest first', () {
      final List<ScheduledReminder> plan = ReminderPlan.from(<Todo>[
        todo(id: 'later', reminderAt: DateTime(2026, 12, 1)),
        todo(id: 'sooner', reminderAt: DateTime(2026, 9, 14)),
        todo(id: 'middle', reminderAt: DateTime(2026, 10, 1)),
      ], now: now);

      expect(plan.map((ScheduledReminder r) => r.todoId), <String>[
        'sooner',
        'middle',
        'later',
      ]);
    });

    test('the cap keeps the soonest and drops the furthest away', () {
      // Android silently stops registering alarms past its per-app limit, so
      // the cap has to drop the ones least likely to be needed before the next
      // reschedule — which is the distant ones.
      final List<Todo> many = <Todo>[
        for (int i = 1; i <= 80; i++)
          todo(
            id: 'day$i',
            reminderAt: DateTime(2026, 9, 13, 10).add(Duration(days: i)),
          ),
      ];

      final List<ScheduledReminder> plan = ReminderPlan.from(
        many,
        now: now,
        limit: 5,
      );

      expect(plan.length, 5);
      expect(plan.map((ScheduledReminder r) => r.todoId), <String>[
        'day1',
        'day2',
        'day3',
        'day4',
        'day5',
      ]);
    });

    test('the default cap is applied without being asked for', () {
      final List<Todo> many = <Todo>[
        for (int i = 1; i <= 200; i++)
          todo(
            id: 'd$i',
            reminderAt: DateTime(2026, 9, 13, 10).add(Duration(days: i)),
          ),
      ];

      expect(
        ReminderPlan.from(many, now: now).length,
        ReminderPlan.maxScheduled,
      );
    });

    test('the plan cannot be mutated by the caller', () {
      final List<ScheduledReminder> plan = ReminderPlan.from(<Todo>[
        todo(reminderAt: DateTime(2026, 9, 14)),
      ], now: now);

      expect(() => plan.clear(), throwsUnsupportedError);
    });
  });

  group('notification IDs', () {
    test('are stable for the same todo', () {
      // Stability is the whole requirement. If an ID changed between runs, the
      // old alarm would survive alongside the new one and the user would get
      // the same reminder twice — once with the stale text.
      final int first = ReminderPlan.notificationIdFor('abc123');
      final int second = ReminderPlan.notificationIdFor('abc123');

      expect(first, second);
    });

    test('are always positive and inside a 31-bit range', () {
      for (final String id in <String>['a', 'abc123', 'X9zQ', '', 'a' * 40]) {
        final int value = ReminderPlan.notificationIdFor(id);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });

    test('differ across a realistic set of Firestore document IDs', () {
      // Collisions are possible in principle; this asserts they are not routine
      // for the 20-character IDs Firestore actually generates.
      //
      // The corpus is built from a *seeded* Random rather than an arithmetic
      // pattern. The first attempt used `alphabet[(i * 31 + j * 7) % 62]`,
      // which looks varied and is not: 31 * 2 == 62, so `i * 31 % 62` only ever
      // takes two values and the loop produced two distinct strings, not five
      // hundred. It failed loudly, but a slightly luckier stride would have
      // produced a handful of inputs, passed, and left this test asserting
      // nothing at all. Hence the assertion on the inputs below.
      const String alphabet =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final Random rng = Random(20260913);

      final Set<String> docIds = <String>{};
      while (docIds.length < 500) {
        docIds.add(
          List<String>.generate(
            20,
            (int _) => alphabet[rng.nextInt(alphabet.length)],
          ).join(),
        );
      }

      final Set<int> ids = docIds.map(ReminderPlan.notificationIdFor).toSet();

      expect(docIds.length, 500, reason: 'the corpus itself must be distinct');
      expect(ids.length, 500, reason: 'no two document IDs may share an alarm');
    });
  });

  group('notification body', () {
    test('says how the deadline relates to the reminder', () {
      expect(
        ReminderPlan.bodyFor(
          todo(
            reminderAt: DateTime(2026, 9, 14, 9),
            deadline: DateTime(2026, 9, 14, 23),
          ),
        ),
        'Due today',
      );
      expect(
        ReminderPlan.bodyFor(
          todo(
            reminderAt: DateTime(2026, 9, 14, 9),
            deadline: DateTime(2026, 9, 15),
          ),
        ),
        'Due tomorrow',
      );
      expect(
        ReminderPlan.bodyFor(
          todo(
            reminderAt: DateTime(2026, 9, 14, 9),
            deadline: DateTime(2026, 9, 20),
          ),
        ),
        'Due in 6 days',
      );
    });

    test('a reminder set after its own deadline says overdue', () {
      // Reachable: set a deadline, then push the reminder past it. The
      // notification should not claim the task is due in -3 days.
      expect(
        ReminderPlan.bodyFor(
          todo(
            reminderAt: DateTime(2026, 9, 20),
            deadline: DateTime(2026, 9, 17),
          ),
        ),
        'Overdue',
      );
    });

    test('with no deadline it falls back to the category', () {
      expect(
        ReminderPlan.bodyFor(
          todo(reminderAt: DateTime(2026, 9, 14), category: 'study'),
        ),
        'Study',
      );
    });
  });
}
