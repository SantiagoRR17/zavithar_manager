import 'package:flutter/foundation.dart';

import '../../finance/domain/finance_categories.dart';
import '../../finance/domain/finance_transaction.dart';
import '../../todos/domain/todo.dart';
import 'user_category.dart';

/// The categories a form should offer, for one kind.
///
/// **An empty collection means "use the defaults", not "no categories".** That
/// is what keeps this feature free of a migration: every existing install has
/// no `categories` documents, and on the first run after this update it still
/// sees exactly the list it saw before. The collection only becomes the source
/// of truth once the user edits it, at which point [CategoriesRepository.seed]
/// has written the defaults down explicitly so there is something to edit.
@immutable
class CategorySet {
  const CategorySet({required this.kind, required this.categories});

  /// The built-in list for [kind], as [UserCategory] values.
  factory CategorySet.defaults(CategoryKind kind) {
    final List<String> keys = defaultKeysFor(kind);
    return CategorySet(
      kind: kind,
      categories: <UserCategory>[
        for (int i = 0; i < keys.length; i++)
          UserCategory(
            kind: kind,
            key: keys[i],
            label: _capitalise(keys[i]),
            sortOrder: (i + 1) * UserCategory.orderGap,
          ),
      ],
    );
  }

  /// Picks between what is stored and the defaults.
  factory CategorySet.resolve(CategoryKind kind, List<UserCategory> stored) {
    final List<UserCategory> mine =
        stored.where((UserCategory c) => c.kind == kind).toList()
          ..sort(_byOrderThenLabel);
    if (mine.isEmpty) return CategorySet.defaults(kind);
    return CategorySet(
      kind: kind,
      categories: List<UserCategory>.unmodifiable(mine),
    );
  }

  final CategoryKind kind;
  final List<UserCategory> categories;

  bool get isEmpty => categories.isEmpty;

  List<String> get keys =>
      categories.map((UserCategory c) => c.key).toList(growable: false);

  bool contains(String key) => categories.any((UserCategory c) => c.key == key);

  /// The first category, or null when the user has deleted every one.
  ///
  /// Nullable on purpose. An empty list is a state the user can reach — the
  /// editor allows deleting the last category — and a getter that threw here
  /// would turn that into a crash on the next time a form opened.
  String? get defaultKey => categories.isEmpty ? null : categories.first.key;

  /// The keys a picker should offer, with [current] kept even if it has been
  /// removed from the list.
  ///
  /// **Editing a record must never silently recategorise it.** Once categories
  /// are editable, opening an old transaction whose category has since been
  /// deleted is routine — and a picker that simply dropped the missing value
  /// would reset the selection to the first category, so saving an unrelated
  /// change to the amount would quietly move the record to a different
  /// category. Keeping the value in the list makes the change deliberate.
  List<String> keysIncluding(String? current) {
    final List<String> offered = keys;
    if (current == null || current.isEmpty || offered.contains(current)) {
      return offered;
    }
    return List<String>.unmodifiable(<String>[...offered, current]);
  }

  /// What to show for [key].
  ///
  /// Falls back to capitalising the raw key, which is what makes a *deleted*
  /// category still render correctly on the transactions that used it. Those
  /// records keep their key forever; only the offer list shrank.
  String label(String key) {
    for (final UserCategory c in categories) {
      if (c.key == key) return c.label;
    }
    return _capitalise(key);
  }

  static List<String> defaultKeysFor(CategoryKind kind) => switch (kind) {
    CategoryKind.expense => FinanceCategories.expense,
    CategoryKind.income => FinanceCategories.income,
    CategoryKind.todo => TodoCategories.all,
  };

  static int _byOrderThenLabel(UserCategory a, UserCategory b) {
    final int byOrder = a.sortOrder.compareTo(b.sortOrder);
    // Two categories can share a sortOrder if the sparse gap ever closed.
    // Falling back to the label keeps the list from reshuffling between
    // rebuilds, which would make dragging one feel broken.
    return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
  }

  static String _capitalise(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

/// Which category list a transaction type draws from.
extension TransactionCategoryKind on TransactionType {
  CategoryKind get categoryKind =>
      isIncome ? CategoryKind.income : CategoryKind.expense;
}
