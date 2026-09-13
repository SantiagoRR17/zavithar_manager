import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/data_failure.dart';
import '../domain/todo.dart';

/// The only place in the app that touches `users/{uid}/todos`.
///
/// The same shape as `TransactionsRepository`, and for the same reasons — read
/// that file first, the reasoning behind the raw/converted reference split and
/// the "a collection is a stream, not a table" framing is written out there.
class TodosRepository {
  TodosRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  /// Writes go here — they carry `FieldValue`s, which cannot come out of a
  /// model's `toMap`, so they cannot go through the converter.
  CollectionReference<Map<String, dynamic>> get _raw =>
      _firestore.collection('users').doc(uid).collection('todos');

  /// Reads go here, typed.
  CollectionReference<Todo> get _collection => _raw.withConverter<Todo>(
    fromFirestore:
        (DocumentSnapshot<Map<String, dynamic>> snapshot, SnapshotOptions? _) =>
            Todo.fromMap(
              snapshot.id,
              snapshot.data() ?? const <String, Object?>{},
            ),
    toFirestore: (Todo value, SetOptions? _) => value.toMap(),
  );

  /// Every task, newest first, live.
  ///
  /// **Deliberately unfiltered, with the category and status filters applied in
  /// memory.** The obvious alternative is a `where` clause per filter, and for
  /// a personal task list it is the worse trade:
  ///
  /// - `category` + `orderBy(deadline)` is two fields, so it needs a composite
  ///   index — and a different one for each combination the chips can produce.
  /// - Every filter change would re-run a query and re-read the documents.
  ///   Firestore bills per document read (NFR-5), so filtering server-side on a
  ///   list this size costs *more*, not less: one stream of a few hundred docs
  ///   versus a fresh read on every chip tap.
  /// - Offline, a `where` query is served from the cache anyway, so there is no
  ///   correctness gain either.
  ///
  /// This stops being true at a scale a single person's todo list will not
  /// reach. FR-6's transaction filters are the case that genuinely needs the
  /// index, because a ledger does grow without bound.
  ///
  /// Ordered by `createdAt` — a single field, so no composite index — rather
  /// than by `deadline`, which is optional: Firestore *omits documents missing
  /// the ordered field entirely*, so ordering by deadline would silently hide
  /// every task that does not have one. That is the kind of bug that looks like
  /// data loss.
  Stream<List<Todo>> watchAll() {
    return _collection
        .orderBy(Todo.fieldCreatedAt, descending: true)
        .snapshots()
        .map(
          (QuerySnapshot<Todo> snapshot) => snapshot.docs
              .map((QueryDocumentSnapshot<Todo> doc) => doc.data())
              .toList(growable: false),
        );
  }

  Future<String> add(Todo todo) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _raw.doc();
      await doc.set(<String, Object?>{
        ...todo.toMap(),
        // A task created as already-done is legitimate — ticking something off
        // you did before you wrote it down — so completedAt is derived here
        // too rather than assumed absent.
        if (todo.isCompleted)
          Todo.fieldCompletedAt: FieldValue.serverTimestamp(),
        Todo.fieldCreatedAt: FieldValue.serverTimestamp(),
        Todo.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
      return doc.id;
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Overwrites a task's editable fields.
  ///
  /// Every optional field needs an explicit `FieldValue.delete()` when it has
  /// been cleared: `toMap` omits an empty key, and an omitted key in an
  /// `update` leaves the old value in place — so clearing a deadline in the
  /// form would appear to do nothing.
  Future<void> update(Todo todo) async {
    try {
      await _raw.doc(todo.id).update(<String, Object?>{
        ...todo.toMap(),
        if (todo.notes == null || todo.notes!.trim().isEmpty)
          Todo.fieldNotes: FieldValue.delete(),
        if (todo.deadline == null) Todo.fieldDeadline: FieldValue.delete(),
        if (todo.reminderAt == null) Todo.fieldReminderAt: FieldValue.delete(),
        if (todo.followUpOf == null || todo.followUpOf!.isEmpty)
          Todo.fieldFollowUpOf: FieldValue.delete(),
        // `completedAt` is derived from `status`, never edited directly — two
        // fields that can disagree about whether a task is finished is a bug
        // waiting to happen. Re-opening a completed task must clear it, and a
        // task completed a week ago must keep its original timestamp rather
        // than having it bumped by an unrelated edit to the title.
        ...?_completionFields(todo),
        Todo.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Moves a task between statuses without touching anything else.
  ///
  /// Separate from [update] because this is what a tap on the checkbox does,
  /// and sending the whole document for a one-field change would overwrite
  /// anything edited on another device in between — last-write-wins over a
  /// field nobody meant to touch.
  Future<void> setStatus(Todo todo, TodoStatus status) async {
    try {
      await _raw.doc(todo.id).update(<String, Object?>{
        Todo.fieldStatus: status.wireName,
        ...?_completionFields(todo.copyWith(status: status)),
        Todo.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// What `completedAt` should do for [todo]'s current status.
  ///
  /// Null means "send nothing", which leaves an existing value untouched — the
  /// case where a task was already complete and stays complete.
  Map<String, Object?>? _completionFields(Todo todo) {
    if (!todo.isCompleted) {
      return <String, Object?>{Todo.fieldCompletedAt: FieldValue.delete()};
    }
    if (todo.completedAt == null) {
      return <String, Object?>{
        Todo.fieldCompletedAt: FieldValue.serverTimestamp(),
      };
    }
    return null;
  }

  Future<void> delete(String id) async {
    try {
      await _raw.doc(id).delete();
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  /// Puts a deleted task back under its **original ID**.
  ///
  /// The ID matters more here than it did for transactions: `followUpOf` refers
  /// to a task by ID, so restoring under a fresh ID would leave every follow-up
  /// pointing at nothing while the parent sat visibly on screen.
  Future<void> restore(Todo todo) async {
    try {
      await _raw.doc(todo.id).set(<String, Object?>{
        ...todo.toMap(),
        if (todo.isCompleted)
          Todo.fieldCompletedAt: FieldValue.serverTimestamp(),
        Todo.fieldCreatedAt: FieldValue.serverTimestamp(),
        Todo.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw DataFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' =>
        'That write was refused. Either you are signed out, or the task does '
            'not match the security rules.',
      'unavailable' || 'network-request-failed' =>
        'No connection to Firestore. The change is saved on this device and '
            'will sync when you are back online.',
      'not-found' => 'That task no longer exists.',
      'resource-exhausted' => 'Firestore quota exceeded. Try again later.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
}
