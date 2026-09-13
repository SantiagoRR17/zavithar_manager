import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';
import '../domain/finance_transaction.dart';
import '../domain/monthly_statement.dart';
import '../domain/statement_period.dart';

/// The only place in the app that touches `users/{uid}/statements`.
///
/// See [ADR 0012](../../../../docs/adr/0012-monthly-statements.md). The shape is
/// the same as the other repositories with one deliberate difference: **there is
/// no `update`.** A statement is created or deleted, never edited, and the
/// security rules enforce that rather than trusting this class to be disciplined
/// about it. Correcting a month means reopening it — an explicit act, the way a
/// bank works.
class StatementsRepository {
  StatementsRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('statements');

  CollectionReference<MonthlyStatement> get _collection =>
      _raw.withConverter<MonthlyStatement>(
        fromFirestore:
            (
              DocumentSnapshot<Map<String, dynamic>> snapshot,
              SnapshotOptions? _,
            ) => MonthlyStatement.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
        toFirestore: (MonthlyStatement value, SetOptions? _) => value.toMap(),
      );

  /// Where the transactions collection lives. Statements are summaries *of*
  /// transactions, so this repository has to be able to read them — for closing
  /// a month and for verifying one afterwards.
  CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('users').doc(uid).collection('transactions');

  /// Every statement, newest first, live.
  ///
  /// Cheap without qualification: twelve documents a year, so even a decade of
  /// use is a smaller read than a single month of transactions. This is the
  /// collection the whole feature exists to trade *into*.
  Stream<List<MonthlyStatement>> watchAll() {
    return _collection
        .orderBy(MonthlyStatement.fieldPeriodStart, descending: true)
        .snapshots()
        .map(
          (QuerySnapshot<MonthlyStatement> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<MonthlyStatement> doc) => doc.data())
              .toList(growable: false),
        );
  }

  /// Writes a closed month.
  ///
  /// `set` on a known document ID rather than `add`, because the period *is*
  /// the identity — closing September twice must target the same document, not
  /// create a second one. The rules allow create and forbid update, so the
  /// second attempt fails with `permission-denied` instead of silently
  /// overwriting a statement someone may already have acted on. That refusal is
  /// the feature: a statement is a record, and records do not quietly change.
  Future<void> close(MonthlyStatement statement) async {
    try {
      await _raw.doc(statement.id).set(<String, Object?>{
        ...statement.toMap(),
        MonthlyStatement.fieldClosedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Reopens a month by deleting its statement.
  ///
  /// The transactions were never deleted (ADR 0012), so reopening restores the
  /// month to exactly the state it was in before the close — the open-period
  /// boundary moves back and its rows return to the stream. That reversibility
  /// is the entire payoff of not deleting.
  Future<void> reopen(StatementPeriod period) async {
    try {
      await _raw.doc(period.id).delete();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// One-shot read of the transactions belonging to [period].
  ///
  /// Deliberately a `get`, not a `snapshots` — this is for verifying a closed
  /// month, which is an occasional deliberate act, not something the UI should
  /// hold a listener open for. The read is billed once, per verification.
  ///
  /// The range is `>= start` and `< endExclusive`: a `<=` bound against the
  /// month's last instant would depend on `DateTime` resolution matching
  /// Firestore's, which is a comparison nobody should have to reason about.
  Future<List<FinanceTransaction>> transactionsIn(
    StatementPeriod period,
  ) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _transactions
          .where(
            FinanceTransaction.fieldDate,
            isGreaterThanOrEqualTo: Timestamp.fromDate(period.start),
          )
          .where(
            FinanceTransaction.fieldDate,
            isLessThan: Timestamp.fromDate(period.endExclusive),
          )
          .get();

      return snapshot.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                FinanceTransaction.fromMap(doc.id, doc.data()),
          )
          .toList(growable: false);
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Recomputes [statement] from the transactions still on record and reports
  /// the difference.
  ///
  /// This is what makes a stored derived value defensible (ADR 0012): the raw
  /// data was never deleted, so the summary is checkable rather than merely
  /// believable.
  Future<StatementVerification> verify(MonthlyStatement statement) async {
    final List<FinanceTransaction> actual = await transactionsIn(
      statement.period,
    );

    final MonthlyStatement recomputed = MonthlyStatement.from(
      period: statement.period,
      transactions: actual,
      openingBalance: statement.openingBalance,
    );

    return StatementVerification(
      stored: statement,
      recomputed: recomputed,
      // Anything the stored statement did not count. The rules reject
      // backdated writes into a closed month, so a non-zero number here means
      // the console, a client older than those rules, or a real bug.
      strayTransactions:
          recomputed.transactionCount - statement.transactionCount,
    );
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That statement was refused. A closed month cannot be edited — reopen '
            'it first, or it may already be closed.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. The change is saved on this device and '
            'will sync when you are back online.',
      'not-found' => 'That statement no longer exists.',
      'resource-exhausted' => 'Firestore quota exceeded. Try again later.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}
