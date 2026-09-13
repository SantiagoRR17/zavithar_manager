import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Money and date formatting for the whole app.
///
/// This file is the formatting counterpart to `core/theme/app_colors.dart`'s
/// rule that hex literals live in one place. The same reasoning applies here:
/// if `'\$${amount.toStringAsFixed(0)}'` gets written inline in a dozen widgets,
/// then changing currency — or merely deciding that thousands need separators —
/// becomes a find-and-replace across the codebase, and the one place that was
/// missed shows a differently-formatted number forever.
///
/// **Currency: Colombian peso (COP).** Changing currency means changing
/// [_currencyLocale] and [_currencySymbol] here, and nothing else.
/// See `docs/adr/0009-money-and-dates.md`.

/// The locale whose number *symbols* are used: `es_CO` groups thousands with
/// `.` and separates decimals with `,`, so 12500 renders as `$12.500`.
///
/// `NumberFormat` locale data ships inside the `intl` package itself, so unlike
/// `DateFormat` with a non-English locale this needs no `initializeDateFormatting`
/// call at startup.
const String _currencyLocale = 'es_CO';

const String _currencySymbol = r'$';

/// Everyday COP amounts are whole pesos — nobody tracks centavos, and showing
/// `,00` on every row is noise. Values are still *stored* as numbers with
/// whatever precision was entered; this only affects display.
const int _currencyDecimals = 0;

/// Formats amounts as Colombian pesos.
abstract final class Money {
  /// Grouping only — the symbol is added by hand in [format].
  ///
  /// `NumberFormat.currency(locale: 'es_CO')` was the obvious choice and it is
  /// wrong for this app: CLDR's `es_CO` places the symbol *after* the number
  /// (`12.500 $`), which is technically correct for formal Spanish typography
  /// and is not how anyone in Colombia writes a price. Taking the locale's
  /// separators but not its symbol placement is the deliberate compromise.
  static final NumberFormat _grouped = NumberFormat(
    _currencyDecimals == 0 ? '#,##0' : '#,##0.${'0' * _currencyDecimals}',
    _currencyLocale,
  );

  /// `12500` → `$12.500`. Always unsigned — amounts are stored positive and the
  /// sign is a presentation decision belonging to [formatSigned].
  static String format(num amount) =>
      '$_currencySymbol${grouped(amount)}';

  /// `12500` → `12.500`. The separators without the symbol.
  ///
  /// For places that draw the `$` themselves — an input field with a
  /// `prefixText`, for instance, where [format] would render `$ $12.500`.
  static String grouped(num amount) => _grouped.format(amount.abs());

  /// `+$12.500` for income, `−$12.500` for an expense.
  ///
  /// The minus is U+2212 MINUS SIGN, not a hyphen: it is the same width as the
  /// plus, so a column of amounts stays aligned.
  ///
  /// The project rule that a colour is never the only signal is why this exists
  /// at all — the sign carries the meaning even in greyscale.
  static String formatSigned(num amount, {required bool isIncome}) =>
      '${isIncome ? '+' : '−'}${format(amount)}';

  /// Parses what a person typed into an amount field.
  ///
  /// Deliberately lenient: it accepts `12.500`, `12500`, `12,500` and `$12.500`,
  /// because on a phone keyboard people type separators inconsistently and
  /// rejecting their input over a dot is hostile. Returns `null` when nothing
  /// numeric is left, which is what the form's validator reports.
  ///
  /// Note the ambiguity this resolves by fiat: in `es_CO` a `.` is a thousands
  /// separator and `,` is the decimal point, so `12.500` is twelve thousand five
  /// hundred — *not* twelve and a half. Both separators are simply stripped,
  /// since [_currencyDecimals] is 0 and sub-peso amounts are not a real case.
  static num? tryParse(String input) {
    final String digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return num.tryParse(digits);
  }
}

/// Groups thousands **as the user types**: `100000` becomes `100.000` in the
/// field itself, not only once it is saved.
///
/// Worth it because an amount field is the one place a mis-read number costs
/// something real. Unseparated, `100000` and `1000000` are distinguishable only
/// by counting zeros, which nobody does — people glance, assume, and log an
/// amount ten times too big.
///
/// ## The part that is fiddly: the cursor
///
/// A formatter does not just return text, it returns text *and a selection*.
/// Reformatting shifts every character after an inserted separator one place
/// right, so returning the old cursor offset would drop the caret in the wrong
/// spot — and typing into the middle of a number would scramble it.
///
/// Positions cannot be mapped directly, because the separators are not in the
/// same places before and after. What *is* stable is **how many digits are to
/// the left of the caret**: inserting a `.` does not change that count. So the
/// caret is placed after the same number of digits in the new string.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  /// Refuses edits past this many digits rather than reformatting them.
  ///
  /// `int.parse` overflows silently past 2^63 and would start rendering
  /// nonsense. Fifteen digits is a quadrillion pesos — comfortably past any
  /// real transaction and comfortably short of the overflow.
  static const int _maxDigits = 15;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // An empty field must stay empty and editable — returning a formatted "0"
    // here would make the field impossible to clear.
    if (digits.isEmpty) return newValue.copyWith(text: '');

    // Rejecting an edit means handing back the previous value unchanged, which
    // is what makes the keystroke appear to do nothing.
    if (digits.length > _maxDigits) return oldValue;

    final String formatted = Money.grouped(int.parse(digits));

    // Count the digits to the left of where the caret was *before*
    // reformatting, then find the position after that many digits in the
    // result. Leading zeros collapse (`01` formats as `1`), so this can run
    // past the end — hence the loop bound rather than an index calculation.
    final int caret = newValue.selection.end.clamp(0, newValue.text.length);
    final int digitsBeforeCaret = newValue.text
        .substring(0, caret)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;

    int offset = 0;
    int seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCaret) {
      if (_isDigit(formatted.codeUnitAt(offset))) seen++;
      offset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
}

/// Date formatting for lists and forms.
///
/// English month names on purpose: the UI copy is English throughout, so a
/// Spanish `25 ago 2026` next to an English "Yesterday" would read as a bug.
/// Only the *number* formatting follows Colombian convention.
///
/// **The locale is `en_US`, and it has to be spelled exactly that.** Unlike
/// `NumberFormat`, whose symbol data ships inside `intl`, `DateFormat` knows
/// only one locale until `initializeDateFormatting()` is called — and that one
/// is `en_US`. A bare `'en'` throws `LocaleDataException` at the first format
/// call. Omitting the locale entirely would be worse: it would then follow
/// whatever `Intl.defaultLocale` happens to be, so this would work in tests and
/// throw on a phone set to Spanish.
abstract final class AppDates {
  static const String _locale = 'en_US';

  static final DateFormat _short = DateFormat('d MMM yyyy', _locale);
  static final DateFormat _dayAndMonth = DateFormat('d MMM', _locale);

  /// `25 Aug 2026`.
  static String short(DateTime date) => _short.format(date);

  /// `Today` / `Yesterday` / `25 Aug` / `25 Aug 2026` for another year.
  ///
  /// Used for list rows, where "Today" is far easier to scan than a date that
  /// the reader has to compare against today's mentally.
  static String relativeDay(DateTime date, {DateTime? now}) {
    final DateTime today = _dateOnly(now ?? DateTime.now());
    final DateTime target = _dateOnly(date);
    final int days = today.difference(target).inDays;

    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days == -1) return 'Tomorrow';
    return target.year == today.year ? _dayAndMonth.format(date) : short(date);
  }

  /// Strips the time so two `DateTime`s on the same calendar day compare equal.
  ///
  /// Without this, "yesterday at 23:00" and "today at 01:00" are two hours apart
  /// and `inDays` reports 0 — the difference in *days* is not the difference in
  /// 24-hour blocks.
  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
