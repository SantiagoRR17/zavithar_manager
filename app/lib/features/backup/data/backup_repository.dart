import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';
import '../../finance/domain/finance_transaction.dart';
import '../../finance/domain/liability.dart';
import '../../finance/domain/monthly_statement.dart';
import '../../finance/domain/savings_goal.dart';
import '../../todos/domain/todo.dart';
import '../domain/backup_document.dart';

/// Everything in the account, read once.
///
/// **Deliberately not built on the app's streams.** Since
/// [ADR 0012](../../../../docs/adr/0012-monthly-statements.md) the transactions
/// stream carries only the open period, so a backup assembled from it would
/// quietly contain the current month and nothing else — and a partial backup is
/// worse than none, because it looks like one.
///
/// So this reads the full collections with one-shot `get()`s. That costs a read
/// per document, which is the point: a backup is an occasional, deliberate act,
/// and reading everything is exactly what it is for.
class BackupRepository {
  BackupRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _firestore.collection('users').doc(uid).collection(name);

  /// Reads every collection and renders both files.
  ///
  /// The five reads run concurrently — they do not depend on each other, and
  /// serialising them would make an export of a few thousand documents feel
  /// like a hang.
  Future<BackupBundle> build() async {
    try {
      final List<QuerySnapshot<Map<String, dynamic>>> snapshots =
          await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
            _collection('transactions')
                .orderBy(FinanceTransaction.fieldDate, descending: true)
                .get(),
            _collection('savings').get(),
            _collection('liabilities').get(),
            _collection('todos').get(),
            _collection('statements')
                .orderBy(MonthlyStatement.fieldPeriodStart, descending: true)
                .get(),
          ]);

      final List<FinanceTransaction> transactions = snapshots[0].docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                FinanceTransaction.fromMap(d.id, d.data()),
          )
          .toList(growable: false);

      final List<SavingsGoal> savings = snapshots[1].docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                SavingsGoal.fromMap(d.id, d.data()),
          )
          .toList(growable: false);

      final List<Liability> liabilities = snapshots[2].docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                Liability.fromMap(d.id, d.data()),
          )
          .toList(growable: false);

      final List<Todo> todos = snapshots[3].docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                Todo.fromMap(d.id, d.data()),
          )
          .toList(growable: false);

      final List<MonthlyStatement> statements = snapshots[4].docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                MonthlyStatement.fromMap(d.id, d.data()),
          )
          .toList(growable: false);

      return BackupBundle(
        json: BackupDocument.toJson(
          transactions: transactions,
          savings: savings,
          liabilities: liabilities,
          todos: todos,
          statements: statements,
        ),
        csv: BackupDocument.transactionsToCsv(transactions),
        documentCount:
            transactions.length +
            savings.length +
            liabilities.length +
            todos.length +
            statements.length,
        transactionCount: transactions.length,
      );
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' => 'The export was refused. You may be signed out.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. An export has to read everything from the '
            'server, so it cannot be done offline.',
      'resource-exhausted' =>
        'Firestore read quota exceeded. Try again after midnight US Pacific.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}

/// The rendered files, plus what they contain.
class BackupBundle {
  const BackupBundle({
    required this.json,
    required this.csv,
    required this.documentCount,
    required this.transactionCount,
  });

  final String json;
  final String csv;

  /// Reported back to the user after an export. A backup you cannot see the
  /// size of is one you have to take on trust, and "it exported 0 documents"
  /// is the single most useful thing this screen can tell you.
  final int documentCount;
  final int transactionCount;
}
