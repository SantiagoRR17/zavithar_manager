// Unit tests for the todo model and the list's filtering and ordering.
//
// No Firebase anywhere — `Todo` and `TodoQuery` are plain Dart, so the parts
// with logic worth testing run in milliseconds.
//
// The ordering gets the most attention. It is the only place in the feature
// where being subtly wrong produces a screen that looks fine and is useless:
// a list that quietly buries the thing you have to do next.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/core/theme/app_colors.dart';
import 'package:zavithar_manager/features/todos/domain/todo.dart';
import 'package:zavithar_manager/features/todos/domain/todo_filters.dart';

void main() {
  final DateTime today = DateTime(2026, 9, 13);

  Todo todo({
    String id = 't',
    String title = 'Task',
    String category = 'work',
    TodoStatus status = TodoStatus.pending,
    TodoPriority priority = TodoPriority.medium,
    DateTime? deadline,
    DateTime? createdAt,
    DateTime? completedAt,
    String? followUpOf,
  }) {
    return Todo(
      id: id,
      title: title,
      category: category,
      status: status,
      priority: priority,
      deadline: deadline,
      createdAt: createdAt ?? today,
      completedAt: completedAt,
      followUpOf: followUpOf,
    );
  }

  group('TodoStatus', () {
    test('wire names are the strings the rules check, not Dart names', () {
      // `TodoStatus.inProgress.name` is "inProgress"; the database says
      // "in_progress". Relying on `.name` would have been wrong from the very
      // first write.
      expect(TodoStatus.inProgress.wireName, 'in_progress');
      expect(TodoStatus.pending.wireName, 'pending');
      expect(TodoStatus.completed.wireName, 'completed');
    });

    test('an unrecognised status reads back as pending, not completed', () {
      // Falling back to completed would *hide* the task, and hiding a task is
      // the one failure this app exists to prevent.
      expect(TodoStatus.fromWire('nonsense'), TodoStatus.pending);
      expect(TodoStatus.fromWire(null), TodoStatus.pending);
      expect(TodoStatus.fromWire(42), TodoStatus.pending);
    });
  });

  group('TodoPriority', () {
    test('missing priority defaults to medium', () {
      expect(TodoPriority.fromWire(null), TodoPriority.medium);
      expect(TodoPriority.fromWire('urgent'), TodoPriority.medium);
    });

    test('index order runs low to high, which the sort depends on', () {
      expect(TodoPriority.low.index, lessThan(TodoPriority.medium.index));
      expect(TodoPriority.medium.index, lessThan(TodoPriority.high.index));
    });
  });

  group('TodoCategories', () {
    test('matches the palette exactly, in the same fixed order', () {
      // The domain must not import the theme, so the two lists are duplicated.
      // This is the test that stops them drifting — without it, adding a
      // category in one place and not the other shows up months later as a
      // grey pill nobody can explain.
      expect(TodoCategories.all, AppColors.categoryOrder);
      for (final String c in TodoCategories.all) {
        expect(
          AppColors.categoryColors[c],
          isNotNull,
          reason: '$c has no colour',
        );
      }
    });

    test('the fallback is a real category', () {
      expect(TodoCategories.all, contains(TodoCategories.fallback));
    });
  });

  group('toMap', () {
    test('omits every empty optional rather than writing null', () {
      // A present-but-null key still counts as *present* to the rules'
      // hasOnly/hasAll allowlist, so writing nulls would fail validation for
      // reasons that read as nonsense in the console.
      final Map<String, Object?> map = todo().toMap();

      expect(map.containsKey(Todo.fieldNotes), isFalse);
      expect(map.containsKey(Todo.fieldDeadline), isFalse);
      expect(map.containsKey(Todo.fieldReminderAt), isFalse);
      expect(map.containsKey(Todo.fieldFollowUpOf), isFalse);
    });

    test('never writes the audit or completion timestamps', () {
      // Those are the repository's job — they are FieldValues, or derived.
      final Map<String, Object?> map = todo(
        status: TodoStatus.completed,
        completedAt: today,
      ).toMap();

      expect(map.containsKey(Todo.fieldCreatedAt), isFalse);
      expect(map.containsKey(Todo.fieldUpdatedAt), isFalse);
      expect(map.containsKey(Todo.fieldCompletedAt), isFalse);
    });

    test('trims the title and drops whitespace-only notes', () {
      final Todo t = Todo(
        id: 'x',
        title: '  Renew the passport  ',
        notes: '   ',
        category: 'home',
        status: TodoStatus.pending,
      );

      expect(t.toMap()[Todo.fieldTitle], 'Renew the passport');
      expect(t.toMap().containsKey(Todo.fieldNotes), isFalse);
    });
  });

  group('copyWith', () {
    test('clear flags remove optional values that null cannot', () {
      final Todo t = todo(deadline: today, followUpOf: 'parent');

      expect(
        t.copyWith(deadline: null).deadline,
        today,
        reason: 'null means unchanged',
      );
      expect(t.copyWith(clearDeadline: true).deadline, isNull);
      expect(t.copyWith(clearFollowUpOf: true).followUpOf, isNull);
    });

    test('audit timestamps are carried, never overwritten', () {
      final Todo t = todo(createdAt: DateTime(2026, 1, 1));
      expect(t.copyWith(title: 'Renamed').createdAt, DateTime(2026, 1, 1));
    });
  });

  group('isOverdue / isDueToday', () {
    test('a task due earlier today is not overdue', () {
      // Comparing instants rather than calendar days would mark everything due
      // "today" as overdue from 00:01 onwards.
      final Todo t = todo(deadline: DateTime(2026, 9, 13, 8));
      expect(t.isOverdue(now: DateTime(2026, 9, 13, 17)), isFalse);
      expect(t.isDueToday(now: DateTime(2026, 9, 13, 17)), isTrue);
    });

    test('yesterday is overdue', () {
      expect(
        todo(deadline: DateTime(2026, 9, 12)).isOverdue(now: today),
        isTrue,
      );
    });

    test('a completed task is never overdue', () {
      final Todo t = todo(
        deadline: DateTime(2026, 1, 1),
        status: TodoStatus.completed,
      );
      expect(t.isOverdue(now: today), isFalse);
    });

    test('no deadline is never overdue', () {
      expect(todo().isOverdue(now: today), isFalse);
      expect(todo().isDueToday(now: today), isFalse);
    });
  });

  group('TodoQuery.apply — filtering', () {
    final List<Todo> all = <Todo>[
      todo(id: 'a', category: 'work', status: TodoStatus.pending),
      todo(id: 'b', category: 'home', status: TodoStatus.completed),
      todo(id: 'c', category: 'work', status: TodoStatus.completed),
    ];

    test('no filter means everything, not nothing', () {
      expect(TodoQuery.apply(all, now: today).length, 3);
    });

    test('filters combine', () {
      final List<Todo> result = TodoQuery.apply(
        all,
        category: 'work',
        status: TodoStatus.completed,
        now: today,
      );
      expect(result.map((Todo t) => t.id), <String>['c']);
    });

    test('the result cannot be mutated by the caller', () {
      // The list is handed straight to a ListView; an accidental sort or add
      // in a widget would desynchronise it from the stream that produced it.
      expect(
        () => TodoQuery.apply(all, now: today).add(todo(id: 'z')),
        throwsUnsupportedError,
      );
    });
  });

  group('TodoQuery.apply — ordering', () {
    List<String> order(List<Todo> todos) =>
        TodoQuery.apply(todos, now: today).map((Todo t) => t.id).toList();

    test('unfinished tasks come before finished ones', () {
      expect(
        order(<Todo>[
          todo(id: 'done', status: TodoStatus.completed, completedAt: today),
          todo(id: 'open'),
        ]),
        <String>['open', 'done'],
      );
    });

    test('soonest deadline first', () {
      expect(
        order(<Todo>[
          todo(id: 'later', deadline: DateTime(2026, 12, 1)),
          todo(id: 'sooner', deadline: DateTime(2026, 9, 20)),
        ]),
        <String>['sooner', 'later'],
      );
    });

    test('undated tasks sort last, not first', () {
      // This is the one that matters. Treating a null deadline as the epoch —
      // the obvious shortcut — sorts every undated task to the top, where it
      // pushes everything actually due off the screen.
      expect(
        order(<Todo>[
          todo(id: 'undated'),
          todo(id: 'dated', deadline: DateTime(2026, 12, 25)),
        ]),
        <String>['dated', 'undated'],
      );
    });

    test('priority breaks a deadline tie, high first', () {
      final DateTime due = DateTime(2026, 9, 20);
      expect(
        order(<Todo>[
          todo(id: 'low', deadline: due, priority: TodoPriority.low),
          todo(id: 'high', deadline: due, priority: TodoPriority.high),
          todo(id: 'mid', deadline: due),
        ]),
        <String>['high', 'mid', 'low'],
      );
    });

    test('an overdue task outranks one due next month', () {
      expect(
        order(<Todo>[
          todo(id: 'future', deadline: DateTime(2026, 10, 1)),
          todo(id: 'overdue', deadline: DateTime(2026, 9, 1)),
        ]),
        <String>['overdue', 'future'],
      );
    });

    test('completed tasks are ordered by most recently completed', () {
      expect(
        order(<Todo>[
          todo(
            id: 'old',
            status: TodoStatus.completed,
            completedAt: DateTime(2026, 1, 1),
          ),
          todo(
            id: 'recent',
            status: TodoStatus.completed,
            completedAt: DateTime(2026, 9, 12),
          ),
        ]),
        <String>['recent', 'old'],
      );
    });

    test('a just-created task with no server timestamp sorts first', () {
      // `createdAt` is null for a few hundred milliseconds after a local write
      // (latency compensation). Sorting it last would drop a task the user
      // just typed to the bottom of the list, where it would then jump.
      final Todo fresh = Todo(
        id: 'fresh',
        title: 'Just typed',
        category: 'work',
        status: TodoStatus.pending,
      );
      expect(
        order(<Todo>[
          todo(id: 'older', createdAt: DateTime(2026, 1, 1)),
          fresh,
        ]),
        <String>['fresh', 'older'],
      );
    });
  });

  group('counts', () {
    final List<Todo> all = <Todo>[
      todo(id: 'a', category: 'work', status: TodoStatus.pending),
      todo(id: 'b', category: 'work', status: TodoStatus.completed),
      todo(id: 'c', category: 'home', status: TodoStatus.pending),
    ];

    test('status counts respect the selected category', () {
      // "Pending 1" under a selected Work has to mean one pending *work* task.
      final Map<TodoStatus, int> counts = TodoQuery.countsByStatus(
        all,
        category: 'work',
      );
      expect(counts[TodoStatus.pending], 1);
      expect(counts[TodoStatus.completed], 1);
      expect(counts[TodoStatus.inProgress], 0);
    });

    test('category counts respect the selected status', () {
      final Map<String, int> counts = TodoQuery.countsByCategory(
        all,
        status: TodoStatus.pending,
      );
      expect(counts['work'], 1);
      expect(counts['home'], 1);
      expect(counts['study'], 0);
    });

    test('every category has an entry, including the empty ones', () {
      // A chip whose count key is missing would crash on lookup; zero is the
      // honest answer and the chip stays put instead of the row reflowing.
      final Map<String, int> counts = TodoQuery.countsByCategory(all);
      for (final String c in TodoCategories.all) {
        expect(counts.containsKey(c), isTrue, reason: '$c missing');
      }
    });

    test(
      'an unknown category from outside the app does not crash the count',
      () {
        final Map<String, int> counts = TodoQuery.countsByCategory(<Todo>[
          todo(id: 'x', category: 'gardening'),
        ]);
        expect(counts.values.every((int v) => v == 0), isTrue);
      },
    );
  });
}
