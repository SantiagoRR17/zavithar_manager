import 'todo.dart';

/// Filtering and ordering for the todo list.
///
/// Pure functions over a list, with no Firebase anywhere — which is what lets
/// the ordering rules below be tested exhaustively in milliseconds. The stream
/// comes out of Firestore ordered by `createdAt`; everything a person actually
/// wants from a task list happens here.
abstract final class TodoQuery {
  /// Applies the category and status chips, then orders the result.
  ///
  /// A null filter means "all" rather than "none" — the chips are a way to
  /// narrow, and the unfiltered list is the default state.
  static List<Todo> apply(
    List<Todo> todos, {
    String? category,
    TodoStatus? status,
    DateTime? now,
  }) {
    final DateTime reference = now ?? DateTime.now();

    final List<Todo> filtered = todos
        .where(
          (Todo t) =>
              (category == null || t.category == category) &&
              (status == null || t.status == status),
        )
        .toList();

    filtered.sort((Todo a, Todo b) => _byUrgency(a, b, reference));
    return List<Todo>.unmodifiable(filtered);
  }

  /// The ordering, in priority order of the comparisons themselves.
  ///
  /// 1. **Unfinished before finished.** A completed task is a record, not a
  ///    task; leaving them interleaved by date means the thing you have to do
  ///    next can sit below three things you already did.
  /// 2. **Then by deadline, soonest first, with undated tasks last.** This is
  ///    the one that needs care: Dart cannot compare null, and the naive
  ///    "treat null as the epoch" trick sorts undated tasks to the *top*, where
  ///    they push everything urgent off the screen. Undated tasks are not
  ///    urgent; they are unscheduled, and they belong at the bottom.
  /// 3. **Then by priority**, high first — the tiebreak between two things due
  ///    the same day.
  /// 4. **Then newest first**, so the order is stable and matches the stream.
  ///
  /// Completed tasks are ordered among themselves by completion, most recent
  /// first: the useful question about finished work is "what did I just do",
  /// not "what was due longest ago".
  static int _byUrgency(Todo a, Todo b, DateTime now) {
    if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;

    if (a.isCompleted && b.isCompleted) {
      final int byCompletion = _compareNullableDesc(
        a.completedAt,
        b.completedAt,
      );
      if (byCompletion != 0) return byCompletion;
      return _compareNullableDesc(a.createdAt, b.createdAt);
    }

    final int byDeadline = _compareDeadlines(a.deadline, b.deadline);
    if (byDeadline != 0) return byDeadline;

    // `index` runs low → medium → high, so the higher priority is the larger
    // index and has to be reversed to come first.
    final int byPriority = b.priority.index.compareTo(a.priority.index);
    if (byPriority != 0) return byPriority;

    return _compareNullableDesc(a.createdAt, b.createdAt);
  }

  /// Soonest first, with null (no deadline) sorting *after* every real date.
  static int _compareDeadlines(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  /// Most recent first, with null last.
  ///
  /// Null is not padding here: `createdAt` is genuinely null for the few
  /// hundred milliseconds between a local write and the server stamping it
  /// (see `Todo.createdAt`), so a brand-new task hits this comparator with no
  /// timestamp on the device that made it. Sorting it last would make it
  /// appear at the bottom and then jump — so it sorts *first*, which is where
  /// it is about to land anyway.
  static int _compareNullableDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return b.compareTo(a);
  }

  /// How many tasks sit in each status, for the filter chips' counts.
  ///
  /// Counted over the *category-filtered* list, not the whole collection: with
  /// "Work" selected, a "Pending 3" chip has to mean three pending work tasks,
  /// or the number is answering a question nobody asked.
  static Map<TodoStatus, int> countsByStatus(
    List<Todo> todos, {
    String? category,
  }) {
    final Map<TodoStatus, int> counts = <TodoStatus, int>{
      for (final TodoStatus s in TodoStatus.values) s: 0,
    };
    for (final Todo todo in todos) {
      if (category != null && todo.category != category) continue;
      counts[todo.status] = counts[todo.status]! + 1;
    }
    return counts;
  }

  /// How many tasks sit in each category, over the *status-filtered* list —
  /// the mirror of [countsByStatus], for the same reason.
  static Map<String, int> countsByCategory(
    List<Todo> todos, {
    TodoStatus? status,
  }) {
    final Map<String, int> counts = <String, int>{
      for (final String c in TodoCategories.all) c: 0,
    };
    for (final Todo todo in todos) {
      if (status != null && todo.status != status) continue;
      // A category that is not in the fixed four — possible from the console,
      // or from a future user-editable list — is counted only if it is known,
      // rather than crashing on a missing key.
      if (counts.containsKey(todo.category)) {
        counts[todo.category] = counts[todo.category]! + 1;
      }
    }
    return counts;
  }
}
