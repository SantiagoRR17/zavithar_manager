// Unit tests for the backup format.
//
// Worth testing because of what this file is for: under ADR 0011 there are no
// Firestore backups, so an export is the only thing anyone could ever restore
// from. A backup that is subtly malformed is worse than no backup, because you
// find out at the one moment you cannot afford to.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/backup/domain/backup_document.dart';
import 'package:zavithar_manager/features/finance/domain/finance_transaction.dart';
import 'package:zavithar_manager/features/finance/domain/liability.dart';
import 'package:zavithar_manager/features/finance/domain/monthly_statement.dart';
import 'package:zavithar_manager/features/finance/domain/savings_goal.dart';
import 'package:zavithar_manager/features/finance/domain/statement_period.dart';
import 'package:zavithar_manager/features/todos/domain/todo.dart';

void main() {
  FinanceTransaction tx({
    String id = 't1',
    num amount = 12500,
    String category = 'groceries',
    String? description,
  }) {
    return FinanceTransaction(
      id: id,
      amount: amount,
      type: TransactionType.expense,
      category: category,
      description: description,
      date: DateTime.utc(2026, 9, 10, 12),
    );
  }

  String json({
    List<FinanceTransaction> transactions = const <FinanceTransaction>[],
    List<SavingsGoal> savings = const <SavingsGoal>[],
    List<Liability> liabilities = const <Liability>[],
    List<Todo> todos = const <Todo>[],
    List<MonthlyStatement> statements = const <MonthlyStatement>[],
  }) {
    return BackupDocument.toJson(
      transactions: transactions,
      savings: savings,
      liabilities: liabilities,
      todos: todos,
      statements: statements,
      exportedAt: DateTime.utc(2026, 9, 13, 22),
    );
  }

  group('JSON backup', () {
    test('is valid JSON and carries a format version', () {
      final Map<String, Object?> parsed =
          jsonDecode(json()) as Map<String, Object?>;

      expect(parsed['formatVersion'], BackupDocument.formatVersion);
      expect(parsed['exportedAt'], '2026-09-13T22:00:00.000Z');
    });

    test('records counts, so an empty export is visibly empty', () {
      // "It exported 0 documents" is the single most useful thing a backup can
      // tell you, and the easiest thing to miss without it.
      final Map<String, Object?> parsed = jsonDecode(
        json(transactions: <FinanceTransaction>[tx()]),
      ) as Map<String, Object?>;
      final Map<String, Object?> counts =
          parsed['counts']! as Map<String, Object?>;

      expect(counts['transactions'], 1);
      expect(counts['todos'], 0);
    });

    test('includes every collection even when empty', () {
      // A missing key and an empty list read very differently to whoever is
      // restoring: one says "nothing was saved", the other says "this part was
      // never exported".
      final Map<String, Object?> parsed =
          jsonDecode(json()) as Map<String, Object?>;

      for (final String key in <String>[
        'transactions',
        'savings',
        'liabilities',
        'todos',
        'statements',
      ]) {
        expect(parsed[key], isA<List<Object?>>(), reason: '$key missing');
      }
    });

    test('timestamps are ISO-8601 UTC, not epoch milliseconds', () {
      // The property that matters in ten years: openable in a text editor and
      // understandable without this app.
      final Map<String, Object?> parsed = jsonDecode(
        json(transactions: <FinanceTransaction>[tx()]),
      ) as Map<String, Object?>;
      final List<Object?> rows = parsed['transactions']! as List<Object?>;
      final Map<String, Object?> row = rows.single as Map<String, Object?>;

      expect(row['date'], '2026-09-10T12:00:00.000Z');
    });

    test('keeps a statement\'s nested category maps', () {
      // The exact thing CSV would flatten away, and the reason the JSON is the
      // real backup rather than a convenience.
      final MonthlyStatement statement = MonthlyStatement.from(
        period: const StatementPeriod(2026, 8),
        openingBalance: 0,
        transactions: <FinanceTransaction>[
          FinanceTransaction(
            id: 'a',
            amount: 13000,
            type: TransactionType.expense,
            category: 'entertainment',
            date: DateTime.utc(2026, 8, 25),
          ),
        ],
      );

      final Map<String, Object?> parsed = jsonDecode(
        json(statements: <MonthlyStatement>[statement]),
      ) as Map<String, Object?>;
      final Map<String, Object?> row =
          (parsed['statements']! as List<Object?>).single
              as Map<String, Object?>;
      final Map<String, Object?> byCategory =
          row['expenseByCategory']! as Map<String, Object?>;

      expect(byCategory['entertainment'], 13000);
      expect(row['closingBalance'], -13000);
    });
  });

  group('CSV', () {
    test('starts with a UTF-8 BOM so Excel does not mangle accents', () {
      // Without it, Excel on Windows reads a .csv in the system codepage and
      // "Alimentación" arrives as "AlimentaciÃ³n".
      final String csv = BackupDocument.transactionsToCsv(<FinanceTransaction>[
        tx(),
      ]);
      expect(csv.codeUnitAt(0), 0xFEFF);
    });

    test('has a header row and one line per transaction', () {
      final String csv = BackupDocument.transactionsToCsv(<FinanceTransaction>[
        tx(id: 'a'),
        tx(id: 'b'),
      ]);
      final List<String> lines = csv.trim().split('\n');

      expect(lines.length, 3);
      expect(lines.first, contains('date,type,amount'));
    });

    test('quotes a field containing a comma', () {
      // Unquoted, this one description would shift every later column on its
      // row — and a spreadsheet opens the mangled file without complaint.
      final String csv = BackupDocument.transactionsToCsv(<FinanceTransaction>[
        tx(description: 'rent, water and gas'),
      ]);

      expect(csv, contains('"rent, water and gas"'));
    });

    test('escapes a quote by doubling it, not with a backslash', () {
      // The rule everyone gets wrong. RFC 4180 doubles the quote.
      final String csv = BackupDocument.transactionsToCsv(<FinanceTransaction>[
        tx(description: 'paid "rent"'),
      ]);

      expect(csv, contains('"paid ""rent"""'));
      expect(csv, isNot(contains(r'\"')));
    });

    test('quotes a field containing a newline', () {
      final String csv = BackupDocument.transactionsToCsv(<FinanceTransaction>[
        tx(description: 'line one\nline two'),
      ]);

      expect(csv, contains('"line one\nline two"'));
    });

    test('leaves ordinary fields unquoted', () {
      final String csv = BackupDocument.transactionsToCsv(<FinanceTransaction>[
        tx(description: 'bread'),
      ]);

      expect(csv, contains(',bread,'));
      expect(csv, isNot(contains('"bread"')));
    });

    test('an absent description becomes an empty cell, not the word null', () {
      final String csv = BackupDocument.transactionsToCsv(<FinanceTransaction>[
        tx(),
      ]);

      expect(csv, isNot(contains('null')));
    });
  });

  group('file names', () {
    test('sort chronologically and carry the extension', () {
      final String name = BackupDocument.fileName(
        'json',
        now: DateTime(2026, 9, 13, 7, 5),
      );

      expect(name, 'zavithar-backup-2026-09-13-0705.json');
    });
  });
}
