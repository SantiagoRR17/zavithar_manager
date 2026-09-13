import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_states.dart';
import '../application/todo_providers.dart';
import '../data/todos_repository.dart';
import '../domain/todo.dart';
import 'todo_form_sheet.dart';
import 'widgets/todo_filter_bar.dart';
import 'widgets/todo_tile.dart';

/// The todo list — Milestone 2.
class TodosScreen extends ConsumerWidget {
  const TodosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Todo>> todos = ref.watch(filteredTodosProvider);
    final bool filtered =
        ref.watch(todoCategoryFilterProvider) != null ||
        ref.watch(todoStatusFilterProvider) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTodoFormSheet(context),
        tooltip: 'New task',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          const SizedBox(height: 4),
          const TodoFilterBar(),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.gridline),
          Expanded(
            child: todos.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) => AppErrorState(
                title: 'Could not load your tasks',
                error: error,
              ),
              data: (List<Todo> items) {
                if (items.isEmpty) {
                  // Two different empty states. "No tasks at all" is an
                  // invitation; "no tasks match these filters" is a dead end
                  // the user can get out of — and showing the invitation there
                  // would be telling someone with forty tasks that they have
                  // none.
                  return filtered
                      ? const _NoMatchesState()
                      : const AppEmptyState(
                          icon: Icons.checklist_rtl,
                          title: 'Nothing on the list',
                          message:
                              'Tap + to add something. Give it a deadline and '
                              'a reminder and it will chase you.',
                        );
                }
                return _TodoList(items: items);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoList extends ConsumerWidget {
  const _TodoList({required this.items});

  final List<Todo> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, Todo> byId = ref.watch(todosByIdProvider);

    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      itemCount: items.length,
      separatorBuilder: (BuildContext context, int _) =>
          const Divider(height: 1, indent: 56, color: AppColors.gridline),
      itemBuilder: (BuildContext context, int index) {
        final Todo todo = items[index];
        return Dismissible(
          key: ValueKey<String>(todo.id),
          direction: DismissDirection.endToStart,
          background: const DeleteBackground(),
          onDismissed: (DismissDirection _) =>
              _deleteWithUndo(context, ref, todo),
          child: TodoTile(
            todo: todo,
            // Resolved from the list already in memory. A deleted parent
            // simply yields null and the link is omitted.
            parent: todo.followUpOf == null ? null : byId[todo.followUpOf],
            onToggleStatus: () => _advanceStatus(context, ref, todo),
            onTap: () => showTodoFormSheet(context, initial: todo),
          ),
        );
      },
    );
  }

  /// pending → in progress → completed → pending.
  Future<void> _advanceStatus(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
  ) async {
    final TodosRepository? repository = ref.read(todosRepositoryProvider);
    if (repository == null) return;

    final TodoStatus next = switch (todo.status) {
      TodoStatus.pending => TodoStatus.inProgress,
      TodoStatus.inProgress => TodoStatus.completed,
      TodoStatus.completed => TodoStatus.pending,
    };

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await repository.setStatus(todo, next);
    } on DataFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
  ) async {
    final TodosRepository? repository = ref.read(todosRepositoryProvider);
    if (repository == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await repository.delete(todo.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('"${todo.title}" deleted.'),
            action: SnackBarAction(
              label: 'Undo',
              // Restores under the original ID, so any follow-up pointing at
              // this task keeps pointing at it.
              onPressed: () => repository.restore(todo),
            ),
          ),
        );
    } on DataFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Shown when the filters match nothing — with the way out.
class _NoMatchesState extends ConsumerWidget {
  const _NoMatchesState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.filter_alt_off_outlined,
              size: 44,
              color: AppColors.muted,
            ),
            const SizedBox(height: 14),
            const Text(
              'Nothing matches those filters',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                ref.read(todoCategoryFilterProvider.notifier).clear();
                ref.read(todoStatusFilterProvider.notifier).clear();
              },
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}
