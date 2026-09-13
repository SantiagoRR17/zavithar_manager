import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Money owed — a loan, a credit card, a mortgage.
///
/// Mirrors `users/{uid}/liabilities/{id}` in `claude/data-model.md`.
///
/// Note that [type] is a plain string with a starter list, exactly like a
/// transaction's category and account. Same reasoning: the list will grow, and
/// growing it should not mean editing an enum, rebuilding, and redeploying
/// rules in the right order.
@immutable
class Liability {
  const Liability({
    required this.id,
    required this.name,
    required this.type,
    required this.originalAmount,
    required this.remainingAmount,
    this.interestRate,
    this.dueDate,
    this.minimumPayment,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// A lowercase key — see [LiabilityTypes].
  final String type;

  /// What was borrowed. Always > 0.
  final num originalAmount;

  /// What is still owed. Never negative.
  ///
  /// The data model says this "should not exceed `originalAmount`". It is
  /// deliberately *not* enforced, in the rules or here: interest and late fees
  /// make a debt genuinely grow past what was borrowed, and an app that refuses
  /// to record that is lying about the situation it exists to track.
  final num remainingAmount;

  /// Annual percentage, 0–100. Optional.
  final num? interestRate;

  /// When the next payment is due. Optional — nothing chases it in v1.
  final DateTime? dueDate;

  /// The minimum the lender expects. Optional.
  final num? minimumPayment;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String fieldName = 'name';
  static const String fieldType = 'type';
  static const String fieldOriginalAmount = 'originalAmount';
  static const String fieldRemainingAmount = 'remainingAmount';
  static const String fieldInterestRate = 'interestRate';
  static const String fieldDueDate = 'dueDate';
  static const String fieldMinimumPayment = 'minimumPayment';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';

  /// How much of the debt is gone, 0–1, for the progress bar.
  ///
  /// Note the direction: this counts *down* the debt, so a nearly-repaid
  /// liability shows a nearly-full bar. The opposite reading — a bar that fills
  /// as you sink further into debt — would be technically defensible and
  /// miserable to look at.
  double get progress {
    if (originalAmount <= 0) return 0;
    final num paid = originalAmount - remainingAmount;
    return (paid / originalAmount).clamp(0.0, 1.0).toDouble();
  }

  bool get isPaidOff => remainingAmount <= 0;

  num get amountPaid {
    final num paid = originalAmount - remainingAmount;
    return paid < 0 ? 0 : paid;
  }

  factory Liability.fromMap(String id, Map<String, Object?> data) {
    return Liability(
      id: id,
      name: (data[fieldName] as String?) ?? 'Untitled',
      type: (data[fieldType] as String?) ?? LiabilityTypes.fallback,
      originalAmount: (data[fieldOriginalAmount] as num?) ?? 0,
      remainingAmount: (data[fieldRemainingAmount] as num?) ?? 0,
      interestRate: data[fieldInterestRate] as num?,
      dueDate: _toDate(data[fieldDueDate]),
      minimumPayment: data[fieldMinimumPayment] as num?,
      createdAt: _toDate(data[fieldCreatedAt]),
      updatedAt: _toDate(data[fieldUpdatedAt]),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      fieldName: name.trim(),
      fieldType: type,
      fieldOriginalAmount: originalAmount,
      fieldRemainingAmount: remainingAmount,
      // Every optional field is omitted rather than written as null — a
      // present-but-null key still counts as present to the rules' allowlist.
      if (interestRate != null) fieldInterestRate: interestRate,
      if (dueDate != null) fieldDueDate: Timestamp.fromDate(dueDate!),
      if (minimumPayment != null) fieldMinimumPayment: minimumPayment,
    };
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// The `clear*` flags exist because `copyWith`'s null-means-unchanged
  /// convention cannot otherwise express "remove this optional value" — without
  /// them, setting an interest rate once would make it permanent.
  Liability copyWith({
    String? name,
    String? type,
    num? originalAmount,
    num? remainingAmount,
    num? interestRate,
    DateTime? dueDate,
    num? minimumPayment,
    bool clearInterestRate = false,
    bool clearDueDate = false,
    bool clearMinimumPayment = false,
  }) {
    return Liability(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      originalAmount: originalAmount ?? this.originalAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      interestRate: clearInterestRate
          ? null
          : (interestRate ?? this.interestRate),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      minimumPayment: clearMinimumPayment
          ? null
          : (minimumPayment ?? this.minimumPayment),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Liability &&
            other.id == id &&
            other.name == name &&
            other.type == type &&
            other.originalAmount == originalAmount &&
            other.remainingAmount == remainingAmount &&
            other.interestRate == interestRate &&
            other.dueDate == dueDate &&
            other.minimumPayment == minimumPayment &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    originalAmount,
    remainingAmount,
    interestRate,
    dueDate,
    minimumPayment,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Liability($id, $name, $remainingAmount owed)';
}

/// The starter list of liability kinds.
///
/// A string key with a display label, for the same reasons as
/// `FinanceCategories` and `FinanceAccounts`. The rules validate
/// `type is string && size <= 40`, not membership of this list, so adding a
/// kind never needs a rules deploy.
abstract final class LiabilityTypes {
  static const List<String> all = <String>[
    'loan',
    'credit card',
    'mortgage',
    'personal debt',
    'other',
  ];

  static const String fallback = 'other';

  /// `credit card` → `Credit card`.
  static String label(String type) {
    if (type.isEmpty) return type;
    return type[0].toUpperCase() + type.substring(1);
  }

  /// Whether a stored value is one this build can offer in a dropdown.
  /// Handing `DropdownButton` a value not among its items throws.
  static bool isKnown(String? type) => type != null && all.contains(type);
}
