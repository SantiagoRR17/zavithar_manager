import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Which list a category belongs to.
///
/// One collection holds all three rather than three collections, because the
/// editor screen, the repository and the rules are otherwise identical three
/// times over. The kind is part of the document ID, so `expense:other` and
/// `income:other` coexist without colliding.
enum CategoryKind {
  expense('expense'),
  income('income'),
  todo('todo');

  const CategoryKind(this.wire);

  final String wire;

  /// Unknown values read back as [expense] rather than throwing. A document
  /// written by a newer build must not crash an older one — the app is on two
  /// devices that are not always updated together.
  static CategoryKind fromWire(String? value) {
    for (final CategoryKind k in CategoryKind.values) {
      if (k.wire == value) return k;
    }
    return CategoryKind.expense;
  }
}

/// One user-defined category.
///
/// Mirrors `users/{uid}/categories/{kind:key}`.
///
/// **[key] and [label] are deliberately separate.** The key is what gets
/// written into every transaction and todo, so it must never change; the label
/// is display only and can be edited freely. That is what makes renaming
/// `groceries` to `Mercado` a one-document write instead of a migration over
/// the whole history — and it is why a category can be renamed into another
/// language without any past record becoming wrong.
@immutable
class UserCategory {
  const UserCategory({
    required this.kind,
    required this.key,
    required this.label,
    required this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  final CategoryKind kind;

  /// The stored value. Lowercase, trimmed, and immutable once created.
  final String key;

  /// What the user sees. Free text.
  final String label;

  /// Position in the list. Sparse on purpose — see [reorder].
  final int sortOrder;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// `expense:eating out`. The kind has to be in the ID: `home` is a plausible
  /// expense category *and* one of the todo categories, and one document
  /// cannot be both.
  String get id => idFor(kind, key);

  static String idFor(CategoryKind kind, String key) => '${kind.wire}:$key';

  /// The longest a label may be, matched by the security rules.
  static const int maxLabelLength = 40;

  static const String fieldKind = 'kind';
  static const String fieldKey = 'key';
  static const String fieldLabel = 'label';
  static const String fieldSortOrder = 'sortOrder';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';

  factory UserCategory.fromMap(String id, Map<String, Object?> data) {
    return UserCategory(
      kind: CategoryKind.fromWire(data[fieldKind] as String?),
      key: (data[fieldKey] as String?) ?? _keyFromId(id),
      // A category with no label falls back to its key rather than rendering
      // an empty chip the user cannot tap.
      label: (data[fieldLabel] as String?)?.trim().isNotEmpty == true
          ? (data[fieldLabel] as String).trim()
          : _keyFromId(id),
      sortOrder: (data[fieldSortOrder] as num?)?.toInt() ?? 0,
      createdAt: _toDate(data[fieldCreatedAt]),
      updatedAt: _toDate(data[fieldUpdatedAt]),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    fieldKind: kind.wire,
    fieldKey: key,
    fieldLabel: label,
    fieldSortOrder: sortOrder,
  };

  UserCategory copyWith({String? label, int? sortOrder}) => UserCategory(
    kind: kind,
    key: key,
    label: label ?? this.label,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// Turns what the user typed into a storable key.
  ///
  /// Lowercased and whitespace-collapsed so `Eating  Out` and `eating out` are
  /// the same category rather than two that look identical in the list. Kept
  /// deliberately permissive otherwise — accents and `ñ` are ordinary letters
  /// here, and stripping them would mangle the labels this feature exists to
  /// allow.
  static String keyFor(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// The gap left between adjacent [sortOrder] values.
  ///
  /// Sparse numbering means moving one category is a single write: the new
  /// order is the midpoint of its neighbours', and nothing else is touched.
  /// Consecutive integers would make every move renumber the whole list.
  static const int orderGap = 100;

  /// The [sortOrder] for a category appended to [existing].
  static int nextOrder(Iterable<UserCategory> existing) {
    int highest = 0;
    for (final UserCategory c in existing) {
      if (c.sortOrder > highest) highest = c.sortOrder;
    }
    return highest + orderGap;
  }

  /// The [sortOrder] that puts a category between [before] and [after].
  ///
  /// Null means the end of the list. Returns null when the gap has closed and
  /// there is no integer left between them, which the caller answers by
  /// renumbering — rare, and cheaper than renumbering on every move.
  static int? orderBetween(UserCategory? before, UserCategory? after) {
    if (before == null && after == null) return orderGap;
    if (before == null) return after!.sortOrder - orderGap;
    if (after == null) return before.sortOrder + orderGap;
    final int gap = after.sortOrder - before.sortOrder;
    if (gap <= 1) return null;
    return before.sortOrder + gap ~/ 2;
  }

  static String _keyFromId(String id) {
    final int colon = id.indexOf(':');
    return colon < 0 ? id : id.substring(colon + 1);
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserCategory &&
          other.kind == kind &&
          other.key == key &&
          other.label == label &&
          other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(kind, key, label, sortOrder);

  @override
  String toString() => 'UserCategory($id, $label, $sortOrder)';
}
