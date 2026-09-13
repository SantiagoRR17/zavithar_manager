import 'finance_transaction.dart';

/// The starter category list for transactions.
///
/// **Why a Dart constant and not a Firestore enum or a `categories` collection
/// yet:** the stored value is a plain lowercase string (see
/// `FinanceTransaction.category`), so when Milestone 4 makes categories
/// user-editable it becomes a matter of *sourcing this list from Firestore
/// instead of from here* — every existing document keeps working, and no
/// migration runs. Baking the list into a Dart `enum` would have made that a
/// breaking change.
///
/// The security rules deliberately validate `category is string && size <= 40`
/// rather than checking membership of this list. If they enforced the list,
/// adding a category would mean redeploying rules before the app could write
/// one — two deploys that have to land in the right order.
abstract final class FinanceCategories {
  /// Categories offered for an expense, in display order.
  static const List<String> expense = <String>[
    'groceries',
    'rent',
    'transport',
    'eating out',
    'health',
    'entertainment',
    'other',
  ];

  /// Categories offered for income, in display order.
  static const List<String> income = <String>[
    'salary',
    'freelance',
    'gift',
    'other',
  ];

  /// The escape hatch, present in both lists. Something unlisted can always be
  /// recorded now and re-categorised once the list is editable.
  static const String fallback = 'other';

  static List<String> forType(TransactionType type) =>
      type.isIncome ? income : expense;

  /// The default selection when a form opens or the income/expense toggle
  /// flips. First in the list rather than [fallback] — the common case should
  /// be one tap, not two.
  static String defaultFor(TransactionType type) => forType(type).first;

  /// Whether [category] is offered for [type].
  ///
  /// Used when the type toggle flips: `groceries` makes no sense as income, so
  /// the form resets the selection instead of writing a nonsense pairing.
  static bool isValidFor(String category, TransactionType type) =>
      forType(type).contains(category);

  /// `eating out` → `Eating out`. Stored keys are lowercase so they group and
  /// sort predictably; capitalisation is a display concern only.
  static String label(String category) {
    if (category.isEmpty) return category;
    return category[0].toUpperCase() + category.substring(1);
  }
}
