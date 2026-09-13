// Unit tests for the finance domain layer.
//
// No Firebase anywhere in here: `FinanceTransaction` is a plain Dart object and
// `Timestamp` is a plain Dart class, so these run in milliseconds with no
// emulator and no initialisation. That is the payoff of keeping the model
// separate from the repository — the parts with logic worth testing have no
// dependency on the parts that need a network.
//
// What is deliberately *not* tested here: that Firestore accepts these
// documents. That is the security rules' job, and it is checked against the
// real project with the console's Rules Playground (see the devlog).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/core/format/money.dart';
import 'package:zavithar_manager/features/finance/domain/finance_accounts.dart';
import 'package:zavithar_manager/features/finance/domain/finance_categories.dart';
import 'package:zavithar_manager/features/finance/domain/finance_transaction.dart';

void main() {
  group('TransactionType', () {
    test('wire names are the strings the security rules check', () {
      // If either of these changes, `firestore.rules` has to change with it —
      // which is exactly why the test names the literal strings rather than
      // comparing the enum to itself.
      expect(TransactionType.income.wireName, 'income');
      expect(TransactionType.expense.wireName, 'expense');
    });

    test('round-trips through the wire name', () {
      for (final TransactionType type in TransactionType.values) {
        expect(TransactionType.fromWire(type.wireName), type);
      }
    });

    test('an unrecognised stored value falls back to expense', () {
      // A single malformed document must not take down the whole list.
      expect(TransactionType.fromWire('nonsense'), TransactionType.expense);
      expect(TransactionType.fromWire(null), TransactionType.expense);
      expect(TransactionType.fromWire(42), TransactionType.expense);
    });
  });

  group('FinanceTransaction', () {
    final DateTime date = DateTime(2026, 8, 25, 14, 30);

    FinanceTransaction sample({
      String? description,
      String? account = 'nequi',
    }) {
      return FinanceTransaction(
        id: 'abc123',
        amount: 12500,
        type: TransactionType.expense,
        category: 'groceries',
        date: date,
        description: description,
        account: account,
      );
    }

    test('survives a round trip through the Firestore map', () {
      final FinanceTransaction original = sample(description: 'Weekly shop');
      final FinanceTransaction restored = FinanceTransaction.fromMap(
        original.id,
        original.toMap(),
      );

      expect(restored.amount, original.amount);
      expect(restored.type, original.type);
      expect(restored.category, original.category);
      expect(restored.description, original.description);
      expect(restored.account, original.account);
      expect(restored.date, original.date);
    });

    test('omits empty optional fields rather than writing nulls', () {
      // The rules' key allowlist treats a present-but-null key as present, so
      // writing `description: null` is not the same as leaving it out.
      final Map<String, Object?> map = sample(
        description: '   ',
        account: '',
      ).toMap();

      expect(map.containsKey(FinanceTransaction.fieldDescription), isFalse);
      expect(map.containsKey(FinanceTransaction.fieldAccount), isFalse);
    });

    test('never writes its own audit timestamps', () {
      // The repository adds these as `FieldValue.serverTimestamp()`, and the
      // rules reject anything that is not `request.time`.
      final Map<String, Object?> map = sample().toMap();

      expect(map.containsKey(FinanceTransaction.fieldCreatedAt), isFalse);
      expect(map.containsKey(FinanceTransaction.fieldUpdatedAt), isFalse);
    });

    test('tolerates a null createdAt from an unacknowledged write', () {
      // The real case this guards: Firestore's latency compensation surfaces a
      // just-written document to the local listener *before* the server has
      // stamped it, so on the writing device these fields are null for a
      // moment. A non-nullable field here would crash the list after every
      // insert.
      final FinanceTransaction parsed = FinanceTransaction.fromMap('id', {
        FinanceTransaction.fieldAmount: 500,
        FinanceTransaction.fieldType: 'income',
        FinanceTransaction.fieldCategory: 'salary',
        FinanceTransaction.fieldDate: Timestamp.fromDate(date),
        FinanceTransaction.fieldCreatedAt: null,
        FinanceTransaction.fieldUpdatedAt: null,
      });

      expect(parsed.createdAt, isNull);
      expect(parsed.updatedAt, isNull);
      expect(parsed.amount, 500);
    });

    test('survives a document missing every optional field', () {
      final FinanceTransaction parsed = FinanceTransaction.fromMap(
        'id',
        const <String, Object?>{},
      );

      expect(parsed.amount, 0);
      expect(parsed.category, 'other');
      expect(parsed.description, isNull);
      expect(parsed.type, TransactionType.expense);
    });

    test('value equality lets unchanged rows skip a rebuild', () {
      expect(sample(), equals(sample()));
      expect(sample().hashCode, sample().hashCode);
      expect(sample(), isNot(equals(sample(account: 'cash'))));
    });
  });

  group('FinanceCategories', () {
    test('an expense category is not offered as income', () {
      expect(
        FinanceCategories.isValidFor('groceries', TransactionType.income),
        isFalse,
      );
      expect(
        FinanceCategories.isValidFor('salary', TransactionType.income),
        isTrue,
      );
    });

    test('both lists carry the "other" escape hatch', () {
      for (final TransactionType type in TransactionType.values) {
        expect(
          FinanceCategories.forType(type),
          contains(FinanceCategories.fallback),
        );
      }
    });

    test('every category fits the 40-character limit the rules enforce', () {
      for (final TransactionType type in TransactionType.values) {
        for (final String category in FinanceCategories.forType(type)) {
          expect(category.length, lessThanOrEqualTo(40));
          expect(category, category.toLowerCase());
        }
      }
    });
  });

  group('FinanceAccounts', () {
    test('every account has a hand-written label', () {
      for (final String account in FinanceAccounts.all) {
        // The fallback path capitalises the key, which would quietly render
        // "Nubank" instead of "Nu Bank" — so a missing label is a real defect,
        // not a cosmetic one.
        expect(
          FinanceAccounts.label(account),
          isNot(equals(account)),
          reason: '"$account" has no label entry.',
        );
      }
    });

    test('an unknown account is not offered to the dropdown', () {
      // Handing DropdownButton a value that is not among its items throws, so
      // the form asks this before selecting a stored value.
      expect(FinanceAccounts.isKnown('lulo'), isFalse);
      expect(FinanceAccounts.isKnown(null), isFalse);
      expect(FinanceAccounts.isKnown('nequi'), isTrue);
    });

    test('a missing account still renders as something readable', () {
      expect(FinanceAccounts.label(null), 'Cash');
      expect(FinanceAccounts.label('lulo'), 'Lulo');
    });
  });

  group('Money', () {
    test('formats COP with dot thousands separators and no decimals', () {
      expect(Money.format(12500), r'$12.500');
      expect(Money.format(1000000), r'$1.000.000');
    });

    test('the sign carries the meaning, not just the colour', () {
      expect(Money.formatSigned(12500, isIncome: true), r'+$12.500');
      expect(Money.formatSigned(12500, isIncome: false), '−\$12.500');
    });

    test('parses the separators people actually type', () {
      // In es_CO a dot is a thousands separator, so 12.500 is twelve thousand
      // five hundred — not twelve and a half.
      expect(Money.tryParse('12500'), 12500);
      expect(Money.tryParse('12.500'), 12500);
      expect(Money.tryParse(r'$ 12.500'), 12500);
      expect(Money.tryParse('12,500'), 12500);
    });

    test('rejects input with no digits in it', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse(r'$'), isNull);
    });
  });

  group('ThousandsSeparatorInputFormatter', () {
    const ThousandsSeparatorInputFormatter formatter =
        ThousandsSeparatorInputFormatter();

    /// Simulates typing [text] into an empty field, caret at the end.
    TextEditingValue type(String text, {int? caret}) {
      return formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret ?? text.length),
        ),
      );
    }

    test('groups thousands as the number is typed', () {
      expect(type('100000').text, '100.000');
      expect(type('1000').text, '1.000');
      expect(type('999').text, '999');
      expect(type('1234567').text, '1.234.567');
    });

    test('leaves the caret after the digit just typed', () {
      // The caret must land at the end of `100.000`, not at the offset it held
      // in `100000` before the separator pushed everything right.
      expect(type('100000').selection.baseOffset, 7);
      expect(type('1000').selection.baseOffset, 5);
    });

    test('keeps the caret in place when editing mid-number', () {
      // Field holds `1.000`; the user puts the caret after `1` and types `2`,
      // so the raw new value is `12.000` with the caret at offset 2. Two digits
      // sit left of the caret, and it must stay after those two digits — which
      // is still offset 2 here, but would not be if a separator had shifted.
      final TextEditingValue result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '1.000',
          selection: TextSelection.collapsed(offset: 1),
        ),
        const TextEditingValue(
          text: '12.000',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(result.text, '12.000');
      expect(result.selection.baseOffset, 2);
    });

    test('a caret shifted by an inserted separator follows its digits', () {
      // `999` + a leading `1` → `1999` reformats to `1.999`. Four digits are
      // left of the caret, so it belongs at the very end (offset 5), not at
      // the offset 4 it held before the dot appeared.
      final TextEditingValue result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '999',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextEditingValue(
          text: '1999',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );

      expect(result.text, '1.999');
      expect(result.selection.baseOffset, 5);
    });

    test('the field can still be cleared', () {
      // Formatting an empty field into "0" would make it impossible to empty.
      expect(type('').text, '');
    });

    test('discards anything that is not a digit', () {
      expect(type('1a0b0').text, '100');
      expect(type(r'$ 5.000').text, '5.000');
    });

    test('refuses an edit past the overflow guard', () {
      // 16 digits: the keystroke is rejected, so the field keeps its old value
      // rather than silently rendering an overflowed int.
      const TextEditingValue old = TextEditingValue(
        text: '999.999.999.999.999',
      );
      final TextEditingValue result = formatter.formatEditUpdate(
        old,
        const TextEditingValue(text: '9999999999999999'),
      );

      expect(result.text, old.text);
    });

    test('what the formatter shows, Money.tryParse reads back', () {
      // The round trip that matters: the field displays `100.000` and the save
      // path has to turn that back into 100000.
      expect(Money.tryParse(type('100000').text), 100000);
      expect(Money.tryParse(type('1234567').text), 1234567);
    });
  });

  group('AppDates', () {
    final DateTime now = DateTime(2026, 8, 25, 12);

    test('names the days a person thinks of by name', () {
      expect(
        AppDates.relativeDay(DateTime(2026, 8, 25, 23), now: now),
        'Today',
      );
      expect(
        AppDates.relativeDay(DateTime(2026, 8, 24, 1), now: now),
        'Yesterday',
      );
    });

    test('compares calendar days, not 24-hour blocks', () {
      // 23:00 yesterday and 01:00 today are two hours apart; they are still
      // different days, and `difference().inDays` alone would say 0.
      expect(
        AppDates.relativeDay(DateTime(2026, 8, 24, 23, 30), now: now),
        'Yesterday',
      );
    });

    test('drops the year only for dates in the current year', () {
      expect(AppDates.relativeDay(DateTime(2026, 3, 4), now: now), '4 Mar');
      expect(
        AppDates.relativeDay(DateTime(2025, 3, 4), now: now),
        '4 Mar 2025',
      );
    });
  });
}
