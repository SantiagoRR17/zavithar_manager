import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Income or expense.
///
/// The stored value is spelled out in [wireName] rather than taken from Dart's
/// `.name`. That looks redundant — `TransactionType.income.name` is already
/// `'income'` — but it pins the contract: if someone ever renames the enum
/// constant or reorders it, the *database* format stays put and the compiler
/// forces the mapping to be looked at. Data outlives code.
enum TransactionType {
  income('income'),
  expense('expense');

  const TransactionType(this.wireName);

  /// The exact string stored in Firestore's `type` field, and the value the
  /// security rules check against.
  final String wireName;

  /// Parses the stored string. Unknown values fall back to [expense] rather
  /// than throwing: a single malformed document should not take down the whole
  /// list, and an expense is the conservative reading of an unrecognised entry.
  static TransactionType fromWire(Object? value) =>
      value == income.wireName ? income : expense;

  bool get isIncome => this == TransactionType.income;

  String get label => isIncome ? 'Income' : 'Expense';
}

/// One money movement.
///
/// Named `FinanceTransaction` rather than `Transaction` because
/// `cloud_firestore` already exports a `Transaction` — its batched-write handle.
/// A bare `Transaction` would collide in every file importing both, and
/// resolving that with import prefixes everywhere is worse than one clear name.
///
/// Mirrors `users/{uid}/transactions/{id}` in `claude/data-model.md`.
@immutable
class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.description,
    this.account,
    this.createdAt,
    this.updatedAt,
  });

  /// The Firestore document ID. Not stored *inside* the document — it is the
  /// document's name, and duplicating it in a field is a thing to keep in sync
  /// for no benefit.
  final String id;

  /// Always positive. Whether it adds or subtracts is [type]'s job.
  ///
  /// Storing expenses as negative numbers is the obvious alternative and it is
  /// a trap: every sum then depends on the sign being right, and one mis-signed
  /// write corrupts a total silently. With a positive amount and an explicit
  /// type, a wrong type is *visible* on the row.
  final num amount;

  final TransactionType type;

  /// A lowercase key such as `groceries`. See `finance_categories.dart`.
  ///
  /// Deliberately a plain string, not an enum: `claude/data-model.md` keeps the
  /// door open to user-editable categories in Milestone 4, and that change
  /// should not require a data migration.
  final String category;

  final String? description;

  /// When the money actually moved — chosen by the user, not the write time.
  final DateTime date;

  /// Optional account label ("cash", "credit card"). Not surfaced in the
  /// Milestone 1 form; the field exists so the schema is complete from the
  /// start and adding the UI later is not a migration.
  final String? account;

  /// Server-set audit timestamps.
  ///
  /// **Nullable on purpose, and this is not defensive padding.** Writes use
  /// `FieldValue.serverTimestamp()`, and Firestore's latency compensation puts
  /// the document into the local cache — and therefore into the listener's very
  /// next snapshot — *before* the server has stamped it. On the writing device
  /// these read back as `null` for a few hundred milliseconds. A non-nullable
  /// field here would crash the list immediately after every single insert, on
  /// the one device that made it.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Field names, in one place, so a typo is a compile error rather than a
  /// document that silently writes to a new field nothing reads.
  static const String fieldAmount = 'amount';
  static const String fieldType = 'type';
  static const String fieldCategory = 'category';
  static const String fieldDescription = 'description';
  static const String fieldDate = 'date';
  static const String fieldAccount = 'account';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';

  /// Builds a model from a Firestore document.
  ///
  /// Every read is defensive because the document is data from a database, not
  /// a value the compiler checked: security rules validate *new* writes, but a
  /// document written before a rule tightened is never re-validated.
  factory FinanceTransaction.fromMap(String id, Map<String, Object?> data) {
    return FinanceTransaction(
      id: id,
      amount: (data[fieldAmount] as num?) ?? 0,
      type: TransactionType.fromWire(data[fieldType]),
      category: (data[fieldCategory] as String?) ?? 'other',
      description: data[fieldDescription] as String?,
      date: _toDate(data[fieldDate]) ?? DateTime.now(),
      account: data[fieldAccount] as String?,
      createdAt: _toDate(data[fieldCreatedAt]),
      updatedAt: _toDate(data[fieldUpdatedAt]),
    );
  }

  /// The document body for a write.
  ///
  /// [createdAt] and [updatedAt] are absent by design — the repository adds
  /// them as `FieldValue.serverTimestamp()`. A client-supplied timestamp is
  /// whatever that device's clock says, which may be wrong or deliberately
  /// forged; the rules reject anything that is not `request.time`.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      fieldAmount: amount,
      fieldType: type.wireName,
      fieldCategory: category,
      fieldDate: Timestamp.fromDate(date),
      // Firestore stores an explicit null as a real field. For optional text,
      // omitting the key entirely is cleaner — and the rules' key allowlist
      // treats a present-but-null `description` as a present key.
      if (description != null && description!.trim().isNotEmpty)
        fieldDescription: description!.trim(),
      if (account != null && account!.trim().isNotEmpty)
        fieldAccount: account!.trim(),
    };
  }

  /// `Timestamp` is what Firestore hands back; `DateTime` is what the app uses.
  /// Also tolerates the millisecond ints an import or a hand-edited console
  /// document might contain.
  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  FinanceTransaction copyWith({
    num? amount,
    TransactionType? type,
    String? category,
    String? description,
    DateTime? date,
    String? account,
  }) {
    return FinanceTransaction(
      id: id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      description: description ?? this.description,
      date: date ?? this.date,
      account: account ?? this.account,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Value equality so Flutter can skip rebuilding a row whose data is
  /// unchanged. Firestore re-emits the *whole* collection on every snapshot,
  /// including the documents that did not move, so without this every write
  /// rebuilds every visible row.
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FinanceTransaction &&
            other.id == id &&
            other.amount == amount &&
            other.type == type &&
            other.category == category &&
            other.description == description &&
            other.date == date &&
            other.account == account &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    amount,
    type,
    category,
    description,
    date,
    account,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'FinanceTransaction($id, ${type.wireName} $amount, $category)';
}
