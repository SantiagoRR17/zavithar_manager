import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';

import '../domain/finance_transaction.dart';

/// The only place in the app that touches `users/{uid}/transactions`.
///
/// Same shape and same reasons as `features/auth/data/auth_repository.dart`:
/// UI never talks to Firestore directly (`CLAUDE.md` → Engineering
/// conventions), Firestore's exception types are translated before they reach a
/// widget, and the whole collection can be faked in one place for tests.
///
/// The idea worth holding on to here: **a Firestore collection is not a table
/// you query, it is a stream you subscribe to.** [watchAll] does not fetch a
/// list — it opens a listener that emits the current contents immediately and
/// again on every change, from this device or any other. That is the entire
/// mechanism behind Milestone 1's "appears on the other device within seconds",
/// and there is no polling or refresh anywhere in the app because of it.
class TransactionsRepository {
  TransactionsRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Whose transactions these are. Every path is built from it, which is what
  /// makes the security rules' single `request.auth.uid == userId` check
  /// sufficient — see `firestore.rules`.
  final String uid;

  final FirebaseFirestore _firestore;

  /// The raw collection. Writes go through this one.
  ///
  /// Writes deliberately bypass the converter below: every write has to carry
  /// `FieldValue.serverTimestamp()` for its audit fields, and a `FieldValue` is
  /// a *write instruction*, not a value — it has no place in a model object, so
  /// it cannot come out of `toFirestore`. Keeping writes on the raw reference
  /// makes that split explicit rather than hiding a half-populated converter.
  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('transactions');

  /// The collection, typed. Reads go through this one.
  ///
  /// `withConverter` is the piece that makes the rest of the app not know about
  /// Firestore: past this line, `snapshots()` yields `FinanceTransaction`
  /// objects rather than `Map<String, dynamic>`, and the parsing exists once
  /// here instead of being repeated at every call site — where one forgotten
  /// null check becomes a crash in a list row.
  CollectionReference<FinanceTransaction> get _collection =>
      _raw.withConverter<FinanceTransaction>(
        fromFirestore:
            (
              DocumentSnapshot<Map<String, dynamic>> snapshot,
              SnapshotOptions? _,
            ) => FinanceTransaction.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
        // Unused — see [_raw]. The converter API requires both directions, so
        // this is the honest inverse of `fromFirestore` and nothing calls it.
        toFirestore: (FinanceTransaction value, SetOptions? _) => value.toMap(),
      );

  /// Every transaction, newest first, as a live stream.
  ///
  /// `orderBy('date')` on a single field needs no composite index — Firestore
  /// maintains single-field indexes automatically, which is why
  /// `firestore.indexes.json` is still empty. The date-range and category
  /// filters from FR-6 will combine two fields and *will* need one; that is the
  /// point at which the console hands over a link to create it.
  ///
  /// `includeMetadataChanges` is left off: it would re-emit each snapshot a
  /// second time purely to flip `hasPendingWrites`, doubling rebuilds for
  /// information this screen does not show.
  ///
  /// ## [since] is what keeps this affordable forever
  ///
  /// Pass the start of the open period — the day after the last closed month —
  /// and everything older stops being read. Firestore bills only for documents
  /// a query *returns*, so a ledger with ten years of history costs the same as
  /// one with a month of it.
  ///
  /// That matters because this collection is the only one that grows without
  /// bound: unfiltered, a cold start would be reading ~18,000 documents by year
  /// five, which is 36% of the free tier's daily quota in one launch. See
  /// [ADR 0012](../../../../docs/adr/0012-monthly-statements.md).
  ///
  /// Null means no lower bound — the state before any month has been closed.
  ///
  /// A range filter and an `orderBy` on the **same** field need no composite
  /// index, which is why this one still costs nothing to deploy.
  Stream<List<FinanceTransaction>> watchAll({DateTime? since}) {
    Query<FinanceTransaction> query = _collection;
    if (since != null) {
      query = query.where(
        FinanceTransaction.fieldDate,
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );
    }

    return query
        .orderBy(FinanceTransaction.fieldDate, descending: true)
        .snapshots()
        .map(
          (QuerySnapshot<FinanceTransaction> snapshot) => snapshot.docs
              .map(
                (QueryDocumentSnapshot<FinanceTransaction> doc) => doc.data(),
              )
              .toList(growable: false),
        );
  }

  /// Creates a transaction and returns its new ID.
  ///
  /// The returned future completes when the *server* acknowledges the write.
  /// The document shows up in [watchAll] long before that — Firestore writes it
  /// to the local cache and fires listeners immediately (latency compensation),
  /// then reconciles. So the UI must not wait on this future before showing the
  /// row, and it does not: the list is driven by the stream, not by this call.
  ///
  /// Offline, this future simply does not complete until connectivity returns,
  /// while the row stays visible the whole time. That is FR-18 working as
  /// designed, and the reason `add` is fire-and-forget at the call site.
  Future<String> add(FinanceTransaction transaction) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _raw.doc();
      await doc.set(<String, Object?>{
        ...transaction.toMap(),
        FinanceTransaction.fieldCreatedAt: FieldValue.serverTimestamp(),
        FinanceTransaction.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
      return doc.id;
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Overwrites an existing transaction's editable fields.
  ///
  /// `update` rather than `set`: `set` would wipe `createdAt`, which the model
  /// does not carry and therefore cannot write back.
  Future<void> update(FinanceTransaction transaction) async {
    try {
      await _raw.doc(transaction.id).update(<String, Object?>{
        ...transaction.toMap(),
        // Optional fields cleared in the form have to be removed explicitly.
        // `toMap` omits an empty description entirely, and an omitted key in an
        // `update` leaves the old value in place — so clearing the text would
        // appear to do nothing without this.
        if (transaction.description == null ||
            transaction.description!.trim().isEmpty)
          FinanceTransaction.fieldDescription: FieldValue.delete(),
        if (transaction.account == null || transaction.account!.trim().isEmpty)
          FinanceTransaction.fieldAccount: FieldValue.delete(),
        FinanceTransaction.fieldUpdatedAt: FieldValue.serverTimestamp(),
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

  /// Puts a deleted transaction back under the same document ID.
  ///
  /// This is what makes the list's undo honest: recreating it with a fresh ID
  /// would look identical on screen but break anything that ever refers to a
  /// transaction by ID.
  ///
  /// `createdAt` is re-stamped to now — the rules require `request.time` on
  /// create, and the alternative (letting a client choose its own creation
  /// time) is exactly the hole those rules close.
  Future<void> restore(FinanceTransaction transaction) async {
    try {
      await _raw.doc(transaction.id).set(<String, Object?>{
        ...transaction.toMap(),
        FinanceTransaction.fieldCreatedAt: FieldValue.serverTimestamp(),
        FinanceTransaction.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Human-readable text for the failures that can actually happen here.
  ///
  /// `permission-denied` deserves special care: in development it almost always
  /// means the *rules* rejected the document's shape, not that the user is
  /// signed out — so the message points at the thing that is usually wrong.
  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That write was refused. Either you are signed out, or the '
            'transaction does not match the security rules.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. The change is saved on this device and '
            'will sync when you are back online.',
      'not-found' => 'That transaction no longer exists.',
      'resource-exhausted' => 'Firestore quota exceeded. Try again later.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}
