import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/savings_goal.dart';
import 'transactions_repository.dart' show FinanceFailure;

/// The only place in the app that touches `users/{uid}/savings`.
///
/// Deliberately a near-copy of [TransactionsRepository] rather than a shared
/// generic base class. `CLAUDE.md`'s convention is a thin repository *per
/// collection*, and the collections diverge quickly — savings will grow a
/// "contribute" operation that transactions have no analogue for, and
/// liabilities a "record a payment". A generic `FirestoreRepository<T>` would
/// have to be unpicked at the first one of those.
///
/// See `transactions_repository.dart` for the reasoning behind the read/write
/// split around `withConverter`; it is written out there and not repeated.
class SavingsRepository {
  SavingsRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  /// Writes go here — server timestamps are `FieldValue`s and cannot travel
  /// through a converter.
  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('savings');

  /// Reads go here — typed, parsed in one place.
  CollectionReference<SavingsGoal> get _collection =>
      _raw.withConverter<SavingsGoal>(
        fromFirestore:
            (
              DocumentSnapshot<Map<String, dynamic>> snapshot,
              SnapshotOptions? _,
            ) => SavingsGoal.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
        toFirestore: (SavingsGoal value, SetOptions? _) => value.toMap(),
      );

  /// Every goal, live.
  ///
  /// Ordered by creation, oldest first, so the list does not reshuffle when a
  /// goal is contributed to. Ordering by progress would be more interesting and
  /// much worse to use: rows would jump position as you edit them.
  ///
  /// `createdAt` is null for a moment on the writing device (latency
  /// compensation), and Firestore sorts nulls first — so a brand-new goal
  /// appears at the top for an instant before settling into place. Harmless,
  /// and worth knowing before it looks like a bug.
  Stream<List<SavingsGoal>> watchAll() {
    return _collection
        .orderBy(SavingsGoal.fieldCreatedAt)
        .snapshots()
        .map(
          (QuerySnapshot<SavingsGoal> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<SavingsGoal> doc) => doc.data())
              .toList(growable: false),
        );
  }

  Future<String> add(SavingsGoal goal) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _raw.doc();
      await doc.set(<String, Object?>{
        ...goal.toMap(),
        SavingsGoal.fieldCreatedAt: FieldValue.serverTimestamp(),
        SavingsGoal.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
      return doc.id;
    } on FirebaseException catch (e) {
      throw FinanceFailure(_messageFor(e));
    }
  }

  Future<void> update(SavingsGoal goal) async {
    try {
      await _raw.doc(goal.id).update(<String, Object?>{
        ...goal.toMap(),
        // `toMap` omits an absent deadline, and an omitted key in an `update`
        // leaves the old value untouched — so clearing a deadline would appear
        // to do nothing without an explicit delete.
        if (goal.deadline == null)
          SavingsGoal.fieldDeadline: FieldValue.delete(),
        SavingsGoal.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw FinanceFailure(_messageFor(e));
    }
  }

  /// Adds [amount] to a goal's balance.
  ///
  /// `FieldValue.increment` rather than reading the current value and writing
  /// back a new one. The read-then-write version has a race: two devices that
  /// both read 50.000 and both add 10.000 write 60.000, and one contribution
  /// vanishes. `increment` is applied atomically **on the server**, so the
  /// result is 70.000 regardless of ordering.
  ///
  /// It also works offline — the increment is queued as an instruction, not as
  /// a value, so it composes correctly with whatever happened elsewhere while
  /// this device was away. That is the whole point of the API.
  ///
  /// Pass a negative [amount] to withdraw.
  Future<void> contribute(String id, num amount) async {
    try {
      await _raw.doc(id).update(<String, Object?>{
        SavingsGoal.fieldCurrentAmount: FieldValue.increment(amount),
        SavingsGoal.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw FinanceFailure(_messageFor(e));
    }
  }

  Future<void> delete(String id) async {
    try {
      await _raw.doc(id).delete();
    } on FirebaseException catch (e) {
      throw FinanceFailure(_messageFor(e));
    }
  }

  /// Puts a deleted goal back under its original ID — see the equivalent on
  /// [TransactionsRepository] for why the ID is preserved.
  Future<void> restore(SavingsGoal goal) async {
    try {
      await _raw.doc(goal.id).set(<String, Object?>{
        ...goal.toMap(),
        SavingsGoal.fieldCreatedAt: FieldValue.serverTimestamp(),
        SavingsGoal.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw FinanceFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That write was refused. Either you are signed out, or the goal does '
            'not match the security rules.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. The change is saved on this device and '
            'will sync when you are back online.',
      'not-found' => 'That savings goal no longer exists.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}
