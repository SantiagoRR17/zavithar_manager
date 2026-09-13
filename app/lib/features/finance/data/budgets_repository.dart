import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';
import '../domain/budget.dart';

/// The only place in the app that touches `users/{uid}/budgets`.
///
/// The document ID is the category, so [save] is an upsert: setting a budget
/// for a category that already has one replaces it rather than creating a
/// second. That is the whole reason the ID is not random.
class BudgetsRepository {
  BudgetsRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('budgets');

  CollectionReference<Budget> get _collection => _raw.withConverter<Budget>(
    fromFirestore:
        (DocumentSnapshot<Map<String, dynamic>> snapshot, SnapshotOptions? _) =>
            Budget.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
    toFirestore: (Budget value, SetOptions? _) => value.toMap(),
  );

  /// Every budget, live.
  ///
  /// Ordered by category name rather than by amount: this is the raw list, and
  /// the screen sorts by urgency itself once it knows what has been spent —
  /// which Firestore cannot know.
  Stream<List<Budget>> watchAll() {
    return _collection
        .orderBy(Budget.fieldCategory)
        .snapshots()
        .map(
          (QuerySnapshot<Budget> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<Budget> doc) => doc.data())
              .toList(growable: false),
        );
  }

  /// Creates or replaces the budget for a category.
  ///
  /// `set` with `merge` off, but `createdAt` written only when the document is
  /// new: `FieldValue.serverTimestamp()` on every save would keep resetting
  /// when the budget was first set, which is the one thing that timestamp is
  /// for.
  Future<void> save(Budget budget) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _raw.doc(budget.id);
      final bool exists = (await doc.get()).exists;
      await doc.set(<String, Object?>{
        ...budget.toMap(),
        if (!exists) Budget.fieldCreatedAt: FieldValue.serverTimestamp(),
        Budget.fieldUpdatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: exists));
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  Future<void> delete(String category) async {
    try {
      await _raw.doc(category).delete();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That budget was refused. Either you are signed out, or the amount '
            'does not match the security rules.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. The change is saved on this device and '
            'will sync when you are back online.',
      'not-found' => 'That budget no longer exists.',
      'resource-exhausted' => 'Firestore quota exceeded. Try again later.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}
