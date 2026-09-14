// Unit tests for user-editable categories — Milestone 4.
//
// The thing that must not break here is history: a category is referenced by
// key from every transaction and todo ever written, and nothing in this feature
// may make one of those records unreadable.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/categories/domain/category_set.dart';
import 'package:zavithar_manager/features/categories/domain/user_category.dart';
import 'package:zavithar_manager/features/finance/domain/finance_categories.dart';
import 'package:zavithar_manager/features/todos/domain/todo.dart';

void main() {
  UserCategory cat(
    String key, {
    CategoryKind kind = CategoryKind.expense,
    String? label,
    int sortOrder = 100,
  }) {
    return UserCategory(
      kind: kind,
      key: key,
      label: label ?? key,
      sortOrder: sortOrder,
    );
  }

  group('identity', () {
    test('**the kind is part of the id**', () {
      // `home` is a plausible expense category and one of the todo categories.
      // Without the kind in the id one document would have to be both.
      expect(cat('home').id, isNot(cat('home', kind: CategoryKind.todo).id));
      expect(cat('home').id, 'expense:home');
    });

    test('a key with a space survives the id round trip', () {
      final UserCategory c = cat('eating out');
      expect(c.id, 'expense:eating out');
      expect(UserCategory.fromMap(c.id, c.toMap()).key, 'eating out');
    });

    test('a document missing its key falls back to the id', () {
      // Defensive: a hand-edited document in the console should not render a
      // blank chip.
      final UserCategory c = UserCategory.fromMap(
        'todo:work',
        <String, Object?>{UserCategory.fieldKind: 'todo'},
      );
      expect(c.key, 'work');
      expect(c.label, 'work');
    });

    test('an unknown kind on disk reads back as expense', () {
      // An older build must not crash on a document a newer one wrote.
      expect(CategoryKind.fromWire('project'), CategoryKind.expense);
      expect(CategoryKind.fromWire(null), CategoryKind.expense);
    });
  });

  group('keyFor', () {
    test('lowercases and collapses whitespace', () {
      expect(UserCategory.keyFor('  Eating   Out '), 'eating out');
    });

    test('two labels that differ only in case are one category', () {
      expect(
        UserCategory.keyFor('Groceries'),
        UserCategory.keyFor('groceries'),
      );
    });

    test('**keeps accents and the n-tilde**', () {
      // Stripping them is the standard slug trick and it would mangle exactly
      // the labels this feature exists to allow.
      expect(UserCategory.keyFor('Niñez'), 'niñez');
      expect(UserCategory.keyFor('Café'), 'café');
    });
  });

  group('ordering', () {
    test('a new category goes after the highest', () {
      expect(
        UserCategory.nextOrder(<UserCategory>[
          cat('a', sortOrder: 100),
          cat('b', sortOrder: 300),
        ]),
        400,
      );
    });

    test('the first category in an empty list still gets a gap', () {
      expect(UserCategory.nextOrder(const <UserCategory>[]), 100);
    });

    test('a move lands halfway between its neighbours', () {
      expect(
        UserCategory.orderBetween(
          cat('a', sortOrder: 100),
          cat('b', sortOrder: 200),
        ),
        150,
      );
    });

    test('a move to the front goes a full gap before', () {
      expect(UserCategory.orderBetween(null, cat('a', sortOrder: 100)), 0);
    });

    test('a move to the end goes a full gap after', () {
      expect(UserCategory.orderBetween(cat('a', sortOrder: 100), null), 200);
    });

    test('**a closed gap reports failure rather than colliding**', () {
      // Two categories one apart have no integer between them. Returning the
      // neighbour's own order would silently make the list order depend on the
      // tiebreak, and the row would appear not to move.
      expect(
        UserCategory.orderBetween(
          cat('a', sortOrder: 100),
          cat('b', sortOrder: 101),
        ),
        isNull,
      );
    });
  });

  group('CategorySet.resolve', () {
    test('**an empty collection means the defaults, not an empty picker**', () {
      // This is what makes the feature migration-free: an install that has
      // never opened the editor sees exactly the list it saw before.
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        const <UserCategory>[],
      );
      expect(set.keys, FinanceCategories.expense);
    });

    test('the todo defaults match the four fixed categories', () {
      expect(CategorySet.defaults(CategoryKind.todo).keys, TodoCategories.all);
    });

    test('stored categories replace the defaults entirely', () {
      // Not merged. Otherwise deleting a default would be impossible.
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        <UserCategory>[cat('mercado', sortOrder: 100)],
      );
      expect(set.keys, <String>['mercado']);
    });

    test('another kind does not leak in', () {
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        <UserCategory>[
          cat('rent', sortOrder: 100),
          cat('work', kind: CategoryKind.todo, sortOrder: 100),
        ],
      );
      expect(set.keys, <String>['rent']);
    });

    test('sorts by order, then by key so the list never reshuffles', () {
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        <UserCategory>[
          cat('zeta', sortOrder: 100),
          cat('alpha', sortOrder: 100),
          cat('first', sortOrder: 50),
        ],
      );
      expect(set.keys, <String>['first', 'alpha', 'zeta']);
    });

    test('deleting every category yields no default key, not a throw', () {
      // A state the editor lets the user reach. A getter that threw would turn
      // it into a crash the next time a form opened.
      const CategorySet set = CategorySet(
        kind: CategoryKind.expense,
        categories: <UserCategory>[],
      );
      expect(set.defaultKey, isNull);
      expect(set.isEmpty, isTrue);
    });
  });

  group('labels', () {
    test('renaming changes the label and never the key', () {
      final UserCategory renamed = cat('groceries').copyWith(label: 'Mercado');
      expect(renamed.label, 'Mercado');
      expect(renamed.key, 'groceries');
      expect(renamed.id, 'expense:groceries');
    });

    test(
      '**a deleted category still renders on the records that used it**',
      () {
        // The single most important property here. Removing `rent` from the
        // offer list must not turn last year's rent into a blank.
        final CategorySet set = CategorySet.resolve(
          CategoryKind.expense,
          <UserCategory>[cat('mercado', label: 'Mercado')],
        );
        expect(set.contains('rent'), isFalse);
        expect(set.label('rent'), 'Rent');
      },
    );

    test('**a removed category stays in the picker while it is selected**', () {
      // Otherwise opening an old transaction to fix its amount would reset the
      // selection to the first category and silently recategorise it on save.
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        <UserCategory>[cat('mercado', label: 'Mercado')],
      );
      expect(set.keysIncluding('rent'), <String>['mercado', 'rent']);
    });

    test('a category still in the list is not duplicated', () {
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        <UserCategory>[cat('mercado')],
      );
      expect(set.keysIncluding('mercado'), <String>['mercado']);
    });

    test('no selection adds nothing', () {
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        <UserCategory>[cat('mercado')],
      );
      expect(set.keysIncluding(null), <String>['mercado']);
      expect(set.keysIncluding(''), <String>['mercado']);
    });

    test('a stored label wins over capitalising the key', () {
      final CategorySet set = CategorySet.resolve(
        CategoryKind.expense,
        <UserCategory>[cat('groceries', label: 'Mercado')],
      );
      expect(set.label('groceries'), 'Mercado');
    });

    test('an empty label falls back to the key', () {
      final UserCategory c = UserCategory.fromMap(
        'expense:rent',
        <String, Object?>{UserCategory.fieldLabel: '   '},
      );
      expect(c.label, 'rent');
    });
  });

  group('toMap', () {
    test('omits the audit timestamps — the server writes those', () {
      final Map<String, Object?> map = cat('rent').toMap();
      expect(map.containsKey(UserCategory.fieldCreatedAt), isFalse);
      expect(map.containsKey(UserCategory.fieldUpdatedAt), isFalse);
      expect(map[UserCategory.fieldKind], 'expense');
      expect(map[UserCategory.fieldKey], 'rent');
    });
  });
}
