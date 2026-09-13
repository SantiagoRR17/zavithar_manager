import 'dart:convert';

import '../../finance/domain/finance_transaction.dart';
import '../../finance/domain/liability.dart';
import '../../finance/domain/monthly_statement.dart';
import '../../finance/domain/savings_goal.dart';
import '../../todos/domain/todo.dart';

/// Turns the whole account into text you can keep somewhere else.
///
/// **This is the only backup this project can have.** Firestore's own backups
/// and point-in-time recovery require the Blaze plan, which
/// [ADR 0011](../../../../docs/adr/0011-free-tier-only.md) rules out. So if a
/// bug, a bad edit or a mistaken delete damages the data, there is nothing to
/// restore from except a file the owner exported on purpose.
///
/// Pure, and free of Firebase — the repository fetches, this builds strings,
/// and the result is testable without a network.
abstract final class BackupDocument {
  /// Bumped whenever the shape changes, so a future importer can tell what it
  /// is reading rather than guessing from the keys present.
  static const int formatVersion = 1;

  /// The complete, restorable backup.
  ///
  /// JSON rather than CSV, and the distinction matters more than it looks: a
  /// statement carries nested per-category maps and every collection has
  /// optional fields, and **CSV flattens both away**. A spreadsheet of
  /// transactions is useful for reading; it is not something you could rebuild
  /// the account from. This is.
  ///
  /// Timestamps are ISO-8601 UTC. Not the millisecond integers Firestore uses
  /// internally: those are unreadable in a text editor, and the one property a
  /// backup must have is that a human can open it in ten years and understand
  /// it without this app.
  static String toJson({
    required List<FinanceTransaction> transactions,
    required List<SavingsGoal> savings,
    required List<Liability> liabilities,
    required List<Todo> todos,
    required List<MonthlyStatement> statements,
    DateTime? exportedAt,
  }) {
    final Map<String, Object?> document = <String, Object?>{
      'formatVersion': formatVersion,
      'app': 'Zavithar Manager',
      'exportedAt': _iso(exportedAt ?? DateTime.now()),
      'counts': <String, int>{
        'transactions': transactions.length,
        'savings': savings.length,
        'liabilities': liabilities.length,
        'todos': todos.length,
        'statements': statements.length,
      },
      'transactions': <Map<String, Object?>>[
        for (final FinanceTransaction t in transactions)
          <String, Object?>{
            'id': t.id,
            'amount': t.amount,
            'type': t.type.wireName,
            'category': t.category,
            'description': t.description,
            'date': _iso(t.date),
            'account': t.account,
            'createdAt': _iso(t.createdAt),
            'updatedAt': _iso(t.updatedAt),
          },
      ],
      'savings': <Map<String, Object?>>[
        for (final SavingsGoal g in savings)
          <String, Object?>{
            'id': g.id,
            'name': g.name,
            'targetAmount': g.targetAmount,
            'currentAmount': g.currentAmount,
            'deadline': _iso(g.deadline),
            'createdAt': _iso(g.createdAt),
            'updatedAt': _iso(g.updatedAt),
          },
      ],
      'liabilities': <Map<String, Object?>>[
        for (final Liability l in liabilities)
          <String, Object?>{
            'id': l.id,
            'name': l.name,
            'type': l.type,
            'originalAmount': l.originalAmount,
            'remainingAmount': l.remainingAmount,
            'interestRate': l.interestRate,
            'dueDate': _iso(l.dueDate),
            'minimumPayment': l.minimumPayment,
            'createdAt': _iso(l.createdAt),
            'updatedAt': _iso(l.updatedAt),
          },
      ],
      'todos': <Map<String, Object?>>[
        for (final Todo t in todos)
          <String, Object?>{
            'id': t.id,
            'title': t.title,
            'notes': t.notes,
            'category': t.category,
            'status': t.status.wireName,
            'priority': t.priority.wireName,
            'deadline': _iso(t.deadline),
            'reminderAt': _iso(t.reminderAt),
            'followUpOf': t.followUpOf,
            'createdAt': _iso(t.createdAt),
            'updatedAt': _iso(t.updatedAt),
            'completedAt': _iso(t.completedAt),
          },
      ],
      'statements': <Map<String, Object?>>[
        for (final MonthlyStatement s in statements)
          <String, Object?>{
            'id': s.id,
            'periodStart': _iso(s.period.start),
            'periodEnd': _iso(s.period.endInclusive),
            'totalIncome': s.totalIncome,
            'totalExpense': s.totalExpense,
            'openingBalance': s.openingBalance,
            'closingBalance': s.closingBalance,
            'transactionCount': s.transactionCount,
            'incomeByCategory': s.incomeByCategory,
            'expenseByCategory': s.expenseByCategory,
            'closedAt': _iso(s.closedAt),
          },
      ],
    };

    // Indented on purpose. A backup is read by people far more often than by
    // programs, and the size difference is irrelevant next to being able to
    // scan it.
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// Transactions as a spreadsheet.
  ///
  /// The companion to the JSON, not a replacement for it: this is the one
  /// people actually want to open in Excel, and it is the collection that is
  /// genuinely tabular.
  static String transactionsToCsv(List<FinanceTransaction> transactions) {
    final StringBuffer out = StringBuffer();

    // A BOM, which is the difference between "works" and "á shows as Ã¡".
    // Excel on Windows assumes the system codepage for a .csv unless a UTF-8
    // byte-order mark tells it otherwise, and Colombian category names have
    // accents in them.
    out.write('﻿');
    out.writeln('date,type,amount,category,description,account,id');

    for (final FinanceTransaction t in transactions) {
      out.writeln(
        <String>[
          _iso(t.date) ?? '',
          t.type.wireName,
          t.amount.toString(),
          t.category,
          t.description ?? '',
          t.account ?? '',
          t.id,
        ].map(_csvCell).join(','),
      );
    }

    return out.toString();
  }

  /// Quotes a CSV cell when it has to be quoted, and never otherwise.
  ///
  /// The rule that trips people: a field containing a quote escapes it by
  /// **doubling** it, not with a backslash. Get that wrong and one transaction
  /// described as `paid "rent"` shifts every column after it on that row —
  /// silently, because a spreadsheet will happily open the mangled file.
  static String _csvCell(String value) {
    final bool needsQuotes =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// ISO-8601 in UTC, or null. `Z` rather than a local offset so two exports
  /// taken in different time zones still sort against each other.
  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

  /// `zavithar-backup-2026-09-13.json`
  static String fileName(String extension, {DateTime? now}) {
    final DateTime d = now ?? DateTime.now();
    final String stamp =
        '${d.year}-${_two(d.month)}-${_two(d.day)}-${_two(d.hour)}${_two(d.minute)}';
    return 'zavithar-backup-$stamp.$extension';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
