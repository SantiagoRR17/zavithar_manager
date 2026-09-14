import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';
import '../domain/category_set.dart';
import '../domain/user_category.dart';

/// The only place in the app that touches `users/{uid}/categories`.
///
/// One collection for all three kinds — expense, income and todo — keyed by
/// `kind:key`, so a category cannot be duplicated within its kind and `home`
/// can exist as both an expense and a todo category.
class CategoriesRepository {
  CategoriesRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('categories');

  CollectionReference<UserCategory> get _collection =>
      _raw.withConverter<UserCategory>(
        fromFirestore:
            (
              DocumentSnapshot<Map<String, dynamic>> snapshot,
              SnapshotOptions? _,
            ) => UserCategory.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
        toFirestore: (UserCategory value, SetOptions? _) => value.toMap(),
      );

  /// Every category of every kind, live.
  ///
  /// One listener rather than three. The whole collection is a few dozen tiny
  /// documents, and three queries would be three listeners against the free
  /// tier's concurrent-connection budget for no benefit — the caller splits by
  /// kind in memory, which costs nothing.
  Stream<List<UserCategory>> watchAll() {
    return _collection
        .orderBy(UserCategory.fieldSortOrder)
        .snapshots()
        .map(
          (QuerySnapshot<UserCategory> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<UserCategory> doc) => doc.data())
              .toList(growable: false),
        );
  }

  /// Writes the built-in list for [kind] down as real documents.
  ///
  /// Called the first time the user opens the editor for a kind that has none.
  /// Until this runs the app uses the defaults from code, so an install that
  /// never touches the editor never writes a single document — the whole
  /// reason this feature needs no migration.
  ///
  /// A batch, so the list is never half-seeded: a failure halfway through
  /// would leave the editor showing three of seven categories and the user
  /// deleting the rest by accident.
  Future<void> seed(CategoryKind kind) async {
    try {
      final WriteBatch batch = _firestore.batch();
      for (final UserCategory c in CategorySet.defaults(kind).categories) {
        batch.set(_raw.doc(c.id), <String, Object?>{
          ...c.toMap(),
          UserCategory.fieldCreatedAt: FieldValue.serverTimestamp(),
          UserCategory.fieldUpdatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Creates a category, or fails if its key is already taken.
  ///
  /// The uniqueness is structural — the key is the document ID — so this only
  /// has to check that nothing is there. Two devices racing to add the same
  /// name cannot produce two documents; the second simply loses.
  Future<void> create(UserCategory category) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _raw.doc(category.id);
      if ((await doc.get()).exists) {
        throw const DataFailure('That category already exists.');
      }
      await doc.set(<String, Object?>{
        ...category.toMap(),
        UserCategory.fieldCreatedAt: FieldValue.serverTimestamp(),
        UserCategory.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Renames a category, or moves it in the list.
  ///
  /// **Never touches the key.** Every transaction and todo already written
  /// holds it, and there is no server-side way to rewrite them all — so the
  /// key is immutable here and in the security rules, and renaming changes
  /// only what is displayed.
  Future<void> update(UserCategory category) async {
    try {
      await _raw.doc(category.id).update(<String, Object?>{
        UserCategory.fieldLabel: category.label,
        UserCategory.fieldSortOrder: category.sortOrder,
        UserCategory.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Renumbers a whole kind in one batch.
  ///
  /// The fallback for when the sparse gap between two neighbours has closed
  /// and there is no integer left to insert between them. Rare enough to be
  /// worth handling badly-but-simply rather than with a fractional index.
  Future<void> renumber(List<UserCategory> ordered) async {
    try {
      final WriteBatch batch = _firestore.batch();
      for (int i = 0; i < ordered.length; i++) {
        batch.update(_raw.doc(ordered[i].id), <String, Object?>{
          UserCategory.fieldSortOrder: (i + 1) * UserCategory.orderGap,
          UserCategory.fieldUpdatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Removes a category from the offer list.
  ///
  /// Records that already use it are untouched and keep displaying it — see
  /// [CategorySet.label]. Deleting a category is not deleting history, and the
  /// editor says so.
  Future<void> delete(UserCategory category) async {
    try {
      await _raw.doc(category.id).delete();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That category was refused. Either you are signed out, or the name is '
            'longer than the security rules allow.',
      'not-found' => 'That category no longer exists.',
      'unavailable' || 'network-request-failed' =>
        'No connection. The change is saved locally and will sync.',
      _ => 'Could not save that category (${e.code}).',
    };
  }
}
