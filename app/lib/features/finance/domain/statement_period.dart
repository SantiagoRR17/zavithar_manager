import 'package:flutter/foundation.dart';

/// One calendar month, identified the way a bank identifies a statement.
///
/// The whole statements feature turns on getting month arithmetic right, so it
/// lives here on its own, free of Firebase and of everything else, and is
/// tested exhaustively. Off-by-one errors in period boundaries do not crash —
/// they quietly misplace money, which is worse.
@immutable
class StatementPeriod implements Comparable<StatementPeriod> {
  const StatementPeriod(this.year, this.month)
    : assert(month >= 1 && month <= 12, 'month is 1-12');

  final int year;

  /// 1–12, the way humans and `DateTime` both count months.
  final int month;

  /// The month containing [date].
  factory StatementPeriod.of(DateTime date) =>
      StatementPeriod(date.year, date.month);

  /// The Firestore document ID: `2026-09`.
  ///
  /// Zero-padded so that lexicographic order *is* chronological order — which
  /// is what lets Firestore sort statements by document name with no index and
  /// no separate sort field. `2026-9` would sort after `2026-10`.
  String get id => '$year-${month.toString().padLeft(2, '0')}';

  /// Midnight on the first of the month.
  DateTime get start => DateTime(year, month, 1);

  /// Midnight on the first of the *next* month — the exclusive upper bound.
  ///
  /// December needs no special case: Dart normalises `DateTime(2026, 13, 1)`
  /// to 1 January 2027. Writing the conditional by hand would be one more
  /// branch to get wrong.
  DateTime get endExclusive => DateTime(year, month + 1, 1);

  /// The last instant that still belongs to this month, for a `<=` bound or for
  /// display. A microsecond before the next month starts, because that is the
  /// resolution Dart's `DateTime` actually has.
  DateTime get endInclusive =>
      endExclusive.subtract(const Duration(microseconds: 1));

  StatementPeriod get next => StatementPeriod.of(endExclusive);

  StatementPeriod get previous =>
      StatementPeriod.of(start.subtract(const Duration(days: 1)));

  /// Whether [date] falls inside this month.
  bool contains(DateTime date) =>
      !date.isBefore(start) && date.isBefore(endExclusive);

  /// Whether the month is over, and therefore closable.
  ///
  /// A month cannot be closed while it is still running — half a month's totals
  /// written as if they were the whole month's is exactly the silent wrongness
  /// this feature exists to avoid.
  bool hasEnded({DateTime? now}) =>
      !(now ?? DateTime.now()).isBefore(endExclusive);

  /// `September 2026`.
  String get label => '${_monthNames[month - 1]} $year';

  /// `Sep 2026`.
  String get shortLabel => '${_monthNames[month - 1].substring(0, 3)} $year';

  /// Parses `2026-09`, returning null for anything that is not one.
  ///
  /// Lenient about what it rejects rather than throwing: the input is a
  /// document ID from a database, and one malformed document must not take
  /// down the statements list.
  static StatementPeriod? tryParse(String id) {
    final List<String> parts = id.split('-');
    if (parts.length != 2) return null;
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    if (month < 1 || month > 12) return null;
    if (year < 1970 || year > 9999) return null;
    return StatementPeriod(year, month);
  }

  /// English month names, matching `AppDates`' `en_US` locale — the UI copy is
  /// English throughout, so a Spanish month here would read as a bug.
  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  int compareTo(StatementPeriod other) {
    final int byYear = year.compareTo(other.year);
    return byYear != 0 ? byYear : month.compareTo(other.month);
  }

  bool operator <(StatementPeriod other) => compareTo(other) < 0;
  bool operator <=(StatementPeriod other) => compareTo(other) <= 0;
  bool operator >(StatementPeriod other) => compareTo(other) > 0;
  bool operator >=(StatementPeriod other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatementPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => id;
}
