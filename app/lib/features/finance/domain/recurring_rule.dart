import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'finance_transaction.dart';

/// How often a recurring transaction repeats.
enum Cadence {
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const Cadence(this.wireName);

  final String wireName;

  static Cadence fromWire(Object? value) {
    for (final Cadence c in Cadence.values) {
      if (value == c.wireName) return c;
    }
    return Cadence.monthly;
  }

  String get label => switch (this) {
    Cadence.weekly => 'Weekly',
    Cadence.monthly => 'Monthly',
    Cadence.yearly => 'Yearly',
  };
}

/// A transaction that repeats — salary, rent, a subscription.
///
/// Mirrors `users/{uid}/recurring/{id}`. The rule is a **template plus a
/// schedule**: it never moves money itself, it creates ordinary transactions
/// that do. Everything downstream — balances, statements, budgets — therefore
/// needs to know nothing about recurrence at all.
///
/// There is no server (ADR 0011), so occurrences are materialised on the device
/// when the app opens. See `RecurrenceSchedule`.
@immutable
class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.cadence,
    required this.anchorDay,
    required this.nextRunAt,
    this.description,
    this.account,
    this.active = true,
    this.lastRunAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final num amount;
  final TransactionType type;
  final String category;
  final String? description;
  final String? account;

  final Cadence cadence;

  /// The day the rule *means*, which is not always the day it can land on.
  ///
  /// A rule anchored on the 31st has to fire on the 28th in February — but the
  /// following March it must return to the 31st, not stay on the 28th. Storing
  /// the intended day and clamping it per month is what makes that work;
  /// advancing from the clamped date would walk the rule earlier and earlier
  /// until every month fired on the 28th.
  ///
  /// For [Cadence.weekly] this is the weekday, 1 (Monday) to 7 (Sunday), which
  /// is `DateTime`'s own convention.
  final int anchorDay;

  /// When the next occurrence is due. The single piece of state that makes
  /// materialisation idempotent: whatever else happens, an occurrence is only
  /// created for a date at or after this.
  final DateTime nextRunAt;

  final DateTime? lastRunAt;

  /// Paused rules keep their history and their schedule but create nothing.
  /// Deleting would lose the template; a switch is what people actually want
  /// when a subscription is cancelled but might come back.
  final bool active;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String fieldAmount = 'amount';
  static const String fieldType = 'type';
  static const String fieldCategory = 'category';
  static const String fieldDescription = 'description';
  static const String fieldAccount = 'account';
  static const String fieldCadence = 'cadence';
  static const String fieldAnchorDay = 'anchorDay';
  static const String fieldNextRunAt = 'nextRunAt';
  static const String fieldLastRunAt = 'lastRunAt';
  static const String fieldActive = 'active';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';

  factory RecurringRule.fromMap(String id, Map<String, Object?> data) {
    return RecurringRule(
      id: id,
      amount: (data[fieldAmount] as num?) ?? 0,
      type: TransactionType.fromWire(data[fieldType]),
      category: (data[fieldCategory] as String?) ?? 'other',
      description: data[fieldDescription] as String?,
      account: data[fieldAccount] as String?,
      cadence: Cadence.fromWire(data[fieldCadence]),
      anchorDay: (data[fieldAnchorDay] as num?)?.toInt() ?? 1,
      nextRunAt: _toDate(data[fieldNextRunAt]) ?? DateTime.now(),
      lastRunAt: _toDate(data[fieldLastRunAt]),
      active: (data[fieldActive] as bool?) ?? true,
      createdAt: _toDate(data[fieldCreatedAt]),
      updatedAt: _toDate(data[fieldUpdatedAt]),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    fieldAmount: amount,
    fieldType: type.wireName,
    fieldCategory: category,
    fieldCadence: cadence.wireName,
    fieldAnchorDay: anchorDay,
    fieldNextRunAt: Timestamp.fromDate(nextRunAt),
    fieldActive: active,
    if (description != null && description!.trim().isNotEmpty)
      fieldDescription: description!.trim(),
    if (account != null && account!.trim().isNotEmpty) fieldAccount: account,
  };

  /// The transaction this rule would create for [date].
  FinanceTransaction transactionFor(DateTime date) => FinanceTransaction(
    // Assigned by Firestore on write.
    id: '',
    amount: amount,
    type: type,
    category: category,
    description: description,
    account: account,
    date: date,
  );

  RecurringRule copyWith({
    num? amount,
    TransactionType? type,
    String? category,
    String? description,
    String? account,
    Cadence? cadence,
    int? anchorDay,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    bool? active,
    bool clearDescription = false,
    bool clearAccount = false,
  }) {
    return RecurringRule(
      id: id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      description: clearDescription ? null : (description ?? this.description),
      account: clearAccount ? null : (account ?? this.account),
      cadence: cadence ?? this.cadence,
      anchorDay: anchorDay ?? this.anchorDay,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      active: active ?? this.active,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  String toString() =>
      'RecurringRule($id, ${cadence.wireName} $amount $category)';
}

/// What materialising a rule would produce.
@immutable
class RecurrenceRun {
  const RecurrenceRun({
    required this.rule,
    required this.dates,
    required this.nextRunAt,
    required this.skippedClosed,
  });

  final RecurringRule rule;

  /// The dates to create transactions for, oldest first.
  final List<DateTime> dates;

  /// Where the schedule stands afterwards, whether or not anything was created.
  final DateTime nextRunAt;

  /// Occurrences that fell inside a month already closed.
  ///
  /// **Not created, and not silently dropped either.** The security rules would
  /// refuse them (ADR 0012), and inventing a different date to slip them past
  /// that would put money on a day it did not move. The count is surfaced in
  /// the UI so the owner can reopen the month or enter it by hand.
  final int skippedClosed;

  bool get hasWork => dates.isNotEmpty;
}

/// Works out which occurrences of a rule are due.
///
/// Pure, and the reason the whole feature can be trusted without a server:
/// materialisation runs on a device, whenever the app happens to open, possibly
/// after weeks away and possibly on two devices at once. Everything that makes
/// that safe is here.
abstract final class RecurrenceSchedule {
  /// A rule that has not run for this long is assumed abandoned rather than
  /// replayed in full.
  ///
  /// Without a cap, opening the app after a year away on a weekly rule would
  /// create fifty-two transactions in one go. The cap is generous enough that
  /// any real gap is caught up, and small enough that a mistake is reviewable.
  static const int maxCatchUp = 24;

  /// The occurrences due for [rule] as of [now].
  ///
  /// Catches up everything missed, because the app may not have been opened
  /// for weeks and a rent charge does not stop being owed because nobody
  /// looked.
  ///
  /// [openPeriodStart] is the boundary from ADR 0012: anything before it
  /// belongs to a closed month and cannot be written.
  static RecurrenceRun due(
    RecurringRule rule, {
    DateTime? now,
    DateTime? openPeriodStart,
  }) {
    final DateTime reference = now ?? DateTime.now();

    if (!rule.active) {
      return RecurrenceRun(
        rule: rule,
        dates: const <DateTime>[],
        nextRunAt: rule.nextRunAt,
        skippedClosed: 0,
      );
    }

    final List<DateTime> dates = <DateTime>[];
    int skipped = 0;
    DateTime cursor = rule.nextRunAt;

    while (!cursor.isAfter(reference) && dates.length + skipped < maxCatchUp) {
      if (openPeriodStart != null && cursor.isBefore(openPeriodStart)) {
        skipped++;
      } else {
        dates.add(cursor);
      }
      cursor = advance(cursor, rule.cadence, rule.anchorDay);
    }

    return RecurrenceRun(
      rule: rule,
      dates: List<DateTime>.unmodifiable(dates),
      nextRunAt: cursor,
      skippedClosed: skipped,
    );
  }

  /// The occurrence after [from].
  ///
  /// Monthly steps by calendar month and then re-applies [anchorDay], clamped
  /// to the length of the month it lands in. **This is the part that is wrong
  /// in most implementations**: adding 30 days drifts, and advancing from a
  /// clamped date is worse — a rule anchored on the 31st that fires on 28
  /// February would then fire on the 28th every month thereafter, walking
  /// itself permanently earlier.
  static DateTime advance(DateTime from, Cadence cadence, int anchorDay) {
    switch (cadence) {
      case Cadence.weekly:
        return from.add(const Duration(days: 7));

      case Cadence.monthly:
        final DateTime firstOfNext = DateTime(from.year, from.month + 1, 1);
        return _onDay(firstOfNext.year, firstOfNext.month, anchorDay, from);

      case Cadence.yearly:
        return _onDay(from.year + 1, from.month, anchorDay, from);
    }
  }

  /// [anchorDay] in the given month, clamped to that month's length, keeping
  /// the time of day from [template].
  static DateTime _onDay(int year, int month, int day, DateTime template) {
    // Day 0 of the following month is the last day of this one — the standard
    // way to ask Dart how long a month is without a table of lengths or a leap
    // year rule.
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final int clamped = day > daysInMonth ? daysInMonth : (day < 1 ? 1 : day);
    return DateTime(year, month, clamped, template.hour, template.minute);
  }

  /// The first run for a brand-new rule starting on [start].
  ///
  /// The start date itself counts as the first occurrence: a rule created on
  /// payday for today's salary should record today's salary, not wait a month.
  static DateTime firstRun(DateTime start) => start;

  /// The weekday or day-of-month a start date implies.
  static int anchorFor(DateTime start, Cadence cadence) =>
      cadence == Cadence.weekly ? start.weekday : start.day;
}
