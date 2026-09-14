import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/application/category_providers.dart';
import '../../categories/domain/user_category.dart';
import '../../auth/application/auth_providers.dart';
import '../data/todos_repository.dart';
import '../domain/todo.dart';
import '../domain/todo_filters.dart';

/// Riverpod providers for the todo feature.
///
/// The repository/stream pair is the same shape as `transaction_providers.dart`
/// — rebuilt on uid so that signing out disposes the old listener rather than
/// leaving it running against a still-valid token. That reasoning is written
/// out in the finance file and not repeated here.

final Provider<TodosRepository?> todosRepositoryProvider =
    Provider<TodosRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return TodosRepository(uid: user.uid);
    });

/// Every task, live and unfiltered. The filters are applied downstream, in
/// memory — see [TodosRepository.watchAll] for why that is the cheaper choice
/// for a list this size.
final StreamProvider<List<Todo>> todosStreamProvider =
    StreamProvider<List<Todo>>((Ref ref) {
      final TodosRepository? repository = ref.watch(todosRepositoryProvider);
      if (repository == null) return const Stream<List<Todo>>.empty();
      return repository.watchAll();
    });

/// The selected category chip, or null for "all".
///
/// A [Notifier] rather than the older `StateProvider`: the latter is on its way
/// out in Riverpod 3, and a named method reads better at the call site than an
/// anonymous `state = ...` mutation scattered through widgets.
class TodoCategoryFilter extends Notifier<String?> {
  @override
  String? build() => null;

  /// Tapping the selected chip clears it. Without this the only way back to
  /// "all" would be a separate All chip, and a filter you cannot switch off by
  /// tapping the thing you switched on is a small trap.
  void toggle(String category) {
    state = state == category ? null : category;
  }

  void clear() => state = null;
}

final NotifierProvider<TodoCategoryFilter, String?> todoCategoryFilterProvider =
    NotifierProvider<TodoCategoryFilter, String?>(TodoCategoryFilter.new);

/// The selected status chip, or null for "all".
class TodoStatusFilter extends Notifier<TodoStatus?> {
  @override
  TodoStatus? build() => null;

  void toggle(TodoStatus status) {
    state = state == status ? null : status;
  }

  void clear() => state = null;
}

final NotifierProvider<TodoStatusFilter, TodoStatus?> todoStatusFilterProvider =
    NotifierProvider<TodoStatusFilter, TodoStatus?>(TodoStatusFilter.new);

/// The list the screen actually renders: filtered by both chips and ordered by
/// urgency.
///
/// A plain [Provider] over the stream rather than a second [StreamProvider] —
/// there is no new stream here, only a synchronous transform of one that
/// already exists. Changing a filter re-runs this fold; it does not re-read a
/// single document from Firestore.
final Provider<AsyncValue<List<Todo>>> filteredTodosProvider =
    Provider<AsyncValue<List<Todo>>>((Ref ref) {
      final AsyncValue<List<Todo>> todos = ref.watch(todosStreamProvider);
      final String? category = ref.watch(todoCategoryFilterProvider);
      final TodoStatus? status = ref.watch(todoStatusFilterProvider);

      return todos.whenData(
        (List<Todo> list) =>
            TodoQuery.apply(list, category: category, status: status),
      );
    });

/// Counts for the status chips, narrowed by the category chip.
final Provider<Map<TodoStatus, int>> todoStatusCountsProvider =
    Provider<Map<TodoStatus, int>>((Ref ref) {
      final List<Todo> todos =
          ref.watch(todosStreamProvider).asData?.value ?? const <Todo>[];
      final String? category = ref.watch(todoCategoryFilterProvider);
      return TodoQuery.countsByStatus(todos, category: category);
    });

/// Counts for the category chips, narrowed by the status chip.
final Provider<Map<String, int>> todoCategoryCountsProvider =
    Provider<Map<String, int>>((Ref ref) {
      final List<Todo> todos =
          ref.watch(todosStreamProvider).asData?.value ?? const <Todo>[];
      final TodoStatus? status = ref.watch(todoStatusFilterProvider);
      return TodoQuery.countsByCategory(
        todos,
        status: status,
        categories: ref.watch(categorySetProvider(CategoryKind.todo)).keys,
      );
    });

/// Every task by ID, for resolving a follow-up's parent.
///
/// Built from the already-loaded list rather than by fetching the parent
/// document: it is in the same collection, so it is already on the device, and
/// a `doc().get()` per follow-up row would be a billed read for something
/// sitting in memory.
final Provider<Map<String, Todo>> todosByIdProvider =
    Provider<Map<String, Todo>>((Ref ref) {
      final List<Todo> todos =
          ref.watch(todosStreamProvider).asData?.value ?? const <Todo>[];
      return <String, Todo>{for (final Todo todo in todos) todo.id: todo};
    });
