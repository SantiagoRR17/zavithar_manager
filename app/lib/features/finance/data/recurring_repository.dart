import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';
import '../domain/recurring_rule.dart';

/// The only place in the app that touches `users/{uid}/recurring`.
class RecurringRepository {
  RecurringRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('recurring');

  CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('users').doc(uid).collection('transactions');

  CollectionReference<RecurringRule> get _collection =>
      _raw.withConverter<RecurringRule>(
        fromFirestore:
            (
              DocumentSnapshot<Map<String, dynamic>> snapshot,
              SnapshotOptions? _,
            ) => RecurringRule.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
        toFirestore: (RecurringRule value, SetOptions? _) => value.toMap(),
      );

  Stream<List<RecurringRule>> watchAll() {
    return _collection
        .orderBy(RecurringRule.fieldNextRunAt)
        .snapshots()
        .map(
          (QuerySnapshot<RecurringRule> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<RecurringRule> doc) => doc.data())
              .toList(growable: false),
        );
  }

  Future<String> add(RecurringRule rule) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _raw.doc();
      await doc.set(<String, Object?>{
        ...rule.toMap(),
        RecurringRule.fieldCreatedAt: FieldValue.serverTimestamp(),
        RecurringRule.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
      return doc.id;
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  Future<void> update(RecurringRule rule) async {
    try {
      await _raw.doc(rule.id).update(<String, Object?>{
        ...rule.toMap(),
        if (rule.description == null || rule.description!.trim().isEmpty)
          RecurringRule.fieldDescription: FieldValue.delete(),
        if (rule.account == null || rule.account!.trim().isEmpty)
          RecurringRule.fieldAccount: FieldValue.delete(),
        RecurringRule.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  Future<void> delete(String id) async {
    try {
      await _raw.doc(id).delete();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Writes the transactions a rule is due, then advances its schedule.
  ///
  /// **The whole batch is one atomic write**, occurrences and the new
  /// `nextRunAt` together. Creating three months of rent and then failing to
  /// record that they had been created would produce them all again on the next
  /// launch — and a duplicated rent charge is exactly the failure that would
  /// make someone stop trusting the app.
  ///
  /// Firestore batches cap at 500 operations; `RecurrenceSchedule.maxCatchUp`
  /// keeps this far below that, and does so for a better reason — an app opened
  /// after a year away should not silently write fifty-two transactions.
  Future<void> materialise(RecurrenceRun run) async {
    if (!run.hasWork && run.nextRunAt == run.rule.nextRunAt) return;

    try {
      final WriteBatch batch = _firestore.batch();

      for (final DateTime date in run.dates) {
        batch.set(_transactions.doc(), <String, Object?>{
          ...run.rule.transactionFor(date).toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.update(_raw.doc(run.rule.id), <String, Object?>{
        RecurringRule.fieldNextRunAt: Timestamp.fromDate(run.nextRunAt),
        if (run.hasWork)
          RecurringRule.fieldLastRunAt: Timestamp.fromDate(run.dates.last),
        RecurringRule.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That recurring rule was refused. Either you are signed out, or one of '
            'its occurrences falls in a month you have already closed.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. The change is saved on this device and '
            'will sync when you are back online.',
      'not-found' => 'That recurring rule no longer exists.',
      'resource-exhausted' => 'Firestore quota exceeded. Try again later.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}
