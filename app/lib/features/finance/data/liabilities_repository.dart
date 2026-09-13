import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';
import '../domain/liability.dart';

/// The only place in the app that touches `users/{uid}/liabilities`.
///
/// See `transactions_repository.dart` for the read/write split around
/// `withConverter`, and `savings_repository.dart` for why these three are
/// separate classes rather than one generic base.
class LiabilitiesRepository {
  LiabilitiesRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('liabilities');

  CollectionReference<Liability> get _collection =>
      _raw.withConverter<Liability>(
        fromFirestore:
            (
              DocumentSnapshot<Map<String, dynamic>> snapshot,
              SnapshotOptions? _,
            ) => Liability.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
        toFirestore: (Liability value, SetOptions? _) => value.toMap(),
      );

  /// Every liability, live, biggest debt first.
  ///
  /// Ordering by what is still owed puts the thing most worth looking at at the
  /// top, and moves a paid-off debt to the bottom on its own.
  Stream<List<Liability>> watchAll() {
    return _collection
        .orderBy(Liability.fieldRemainingAmount, descending: true)
        .snapshots()
        .map(
          (QuerySnapshot<Liability> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<Liability> doc) => doc.data())
              .toList(growable: false),
        );
  }

  Future<String> add(Liability liability) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _raw.doc();
      await doc.set(<String, Object?>{
        ...liability.toMap(),
        Liability.fieldCreatedAt: FieldValue.serverTimestamp(),
        Liability.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
      return doc.id;
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  Future<void> update(Liability liability) async {
    try {
      await _raw.doc(liability.id).update(<String, Object?>{
        ...liability.toMap(),
        // Optional fields cleared in the form must be deleted explicitly: an
        // omitted key in an `update` leaves the old value in place.
        if (liability.interestRate == null)
          Liability.fieldInterestRate: FieldValue.delete(),
        if (liability.dueDate == null)
          Liability.fieldDueDate: FieldValue.delete(),
        if (liability.minimumPayment == null)
          Liability.fieldMinimumPayment: FieldValue.delete(),
        Liability.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Records a payment against a debt.
  ///
  /// `FieldValue.increment` with a negative amount, for the same reason
  /// `SavingsRepository.contribute` uses it: the read-then-write alternative
  /// loses a payment when two devices act at once, because both read the same
  /// starting balance. The increment is applied atomically on the server and
  /// queues correctly while offline.
  ///
  /// **The balance is not floored at zero here.** It cannot be — `increment` is
  /// an instruction the server applies without reading anything back, so it has
  /// no way to clamp. Overpaying therefore produces a negative remaining
  /// amount, which the form prevents and the UI displays honestly if it ever
  /// happens. Enforcing a floor would mean a transaction (the batched-write
  /// kind), and that trades away the offline behaviour for a case that only
  /// arises from a typo.
  Future<void> recordPayment(String id, num amount) async {
    try {
      await _raw.doc(id).update(<String, Object?>{
        Liability.fieldRemainingAmount: FieldValue.increment(-amount),
        Liability.fieldUpdatedAt: FieldValue.serverTimestamp(),
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

  Future<void> restore(Liability liability) async {
    try {
      await _raw.doc(liability.id).set(<String, Object?>{
        ...liability.toMap(),
        Liability.fieldCreatedAt: FieldValue.serverTimestamp(),
        Liability.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That write was refused. Either you are signed out, or the liability '
            'does not match the security rules.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. The change is saved on this device and '
            'will sync when you are back online.',
      'not-found' => 'That liability no longer exists.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}
