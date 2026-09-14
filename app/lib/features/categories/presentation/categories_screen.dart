import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../application/category_providers.dart';
import '../data/categories_repository.dart';
import '../domain/category_set.dart';
import '../domain/user_category.dart';

/// The category editor: three lists, one per kind.
///
/// Reachable from Settings rather than from the forms themselves. Editing the
/// list is a rare, deliberate act; offering it inside the picker every time a
/// transaction is recorded would put a destructive action one mis-tap from the
/// common one.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  static const String routeName = 'categories';
  static const String routePath = '/settings/categories';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<UserCategory>> stored = ref.watch(
      categoriesStreamProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: stored.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not read your categories: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.statusCritical),
            ),
          ),
        ),
        data: (List<UserCategory> _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: const <Widget>[
            _Preamble(),
            SizedBox(height: 16),
            _KindSection(
              kind: CategoryKind.expense,
              title: 'Expense categories',
            ),
            SizedBox(height: 24),
            _KindSection(kind: CategoryKind.income, title: 'Income categories'),
            SizedBox(height: 24),
            _KindSection(kind: CategoryKind.todo, title: 'Todo categories'),
          ],
        ),
      ),
    );
  }
}

class _Preamble extends StatelessWidget {
  const _Preamble();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gridline),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.history_edu, size: 18, color: AppColors.muted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Renaming a category only changes what you see — everything you '
              'already recorded keeps its category. Removing one takes it out '
              'of the list to choose from; it does not touch your history.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindSection extends ConsumerWidget {
  const _KindSection({required this.kind, required this.title});

  final CategoryKind kind;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CategorySet set = ref.watch(categorySetProvider(kind));
    final bool seeded = ref.watch(categoriesAreSeededProvider(kind));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _add(context, ref, set),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        if (kind == CategoryKind.todo && seeded)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'The first four keep their colours. Anything beyond them shows '
              'in grey — the app only defines four category colours.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        if (set.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No categories. Add one, or nothing can be recorded under this '
              'list.',
              style: TextStyle(color: AppColors.statusWarning, fontSize: 12),
            ),
          ),
        for (int i = 0; i < set.categories.length; i++)
          _CategoryRow(
            category: set.categories[i],
            set: set,
            index: i,
            seeded: seeded,
          ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    CategorySet set,
  ) async {
    final String? label = await _promptForLabel(context, title: 'New category');
    if (label == null || !context.mounted) return;

    final String key = UserCategory.keyFor(label);
    if (key.isEmpty) return;
    if (set.contains(key)) {
      _say(context, 'You already have a category called that.');
      return;
    }

    await _write(context, ref, (CategoriesRepository repo) async {
      // Seed first when this kind has never been written down: otherwise the
      // new category would be the *only* stored one and the defaults the user
      // can still see on screen would vanish the moment it saved.
      if (!ref.read(categoriesAreSeededProvider(kind))) {
        await repo.seed(kind);
      }
      await repo.create(
        UserCategory(
          kind: kind,
          key: key,
          label: label.trim(),
          sortOrder: UserCategory.nextOrder(
            ref.read(categorySetProvider(kind)).categories,
          ),
        ),
      );
    });
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({
    required this.category,
    required this.set,
    required this.index,
    required this.seeded,
  });

  final UserCategory category;
  final CategorySet set;
  final int index;
  final bool seeded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isFirst = index == 0;
    final bool isLast = index == set.categories.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gridline),
      ),
      child: Row(
        children: <Widget>[
          if (category.kind == CategoryKind.todo) ...<Widget>[
            _ColourDot(categoryKey: category.key),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              category.label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Move up',
            onPressed: isFirst ? null : () => _move(context, ref, up: true),
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          IconButton(
            tooltip: 'Move down',
            onPressed: isLast ? null : () => _move(context, ref, up: false),
            icon: const Icon(Icons.arrow_downward, size: 18),
          ),
          IconButton(
            tooltip: 'Rename',
            onPressed: () => _rename(context, ref),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => _remove(context, ref),
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.statusCritical,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final String? label = await _promptForLabel(
      context,
      title: 'Rename category',
      initial: category.label,
    );
    if (label == null || label.trim().isEmpty || !context.mounted) return;

    await _write(context, ref, (CategoriesRepository repo) async {
      if (!seeded) await repo.seed(category.kind);
      await repo.update(category.copyWith(label: label.trim()));
    });
  }

  /// Swaps this category with its neighbour.
  ///
  /// Two up/down buttons rather than drag-and-drop: the list is short, the
  /// rows carry four other controls already, and a drag handle inside a
  /// scrolling `ListView` fights the scroll on a phone.
  Future<void> _move(
    BuildContext context,
    WidgetRef ref, {
    required bool up,
  }) async {
    final int target = up ? index - 1 : index + 1;
    if (target < 0 || target >= set.categories.length) return;

    final List<UserCategory> reordered = List<UserCategory>.of(set.categories);
    final UserCategory moved = reordered.removeAt(index);
    reordered.insert(target, moved);

    final UserCategory? before = target == 0 ? null : reordered[target - 1];
    final UserCategory? after = target == reordered.length - 1
        ? null
        : reordered[target + 1];
    final int? order = UserCategory.orderBetween(before, after);

    await _write(context, ref, (CategoriesRepository repo) async {
      if (!seeded) await repo.seed(category.kind);
      if (order == null) {
        // The sparse gap has closed and there is no integer left between the
        // neighbours. Rare enough to answer with a full renumber rather than a
        // fractional index.
        await repo.renumber(reordered);
      } else {
        await repo.update(moved.copyWith(sortOrder: order));
      }
    });
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Remove ${category.label}?'),
        content: const Text(
          'It disappears from the list you choose from. Anything already '
          'recorded under it keeps it and still shows the same name.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await _write(context, ref, (CategoriesRepository repo) async {
      if (!seeded) await repo.seed(category.kind);
      await repo.delete(category);
    });
  }
}

/// The colour a todo category will actually be drawn in.
///
/// Shown so the consequence of adding a fifth is visible in the editor rather
/// than discovered later on the todo list: the brand defines four category
/// colours and they are never reassigned or cycled, so a fifth gets the muted
/// tone and leans entirely on its label.
class _ColourDot extends StatelessWidget {
  const _ColourDot({required this.categoryKey});

  final String categoryKey;

  @override
  Widget build(BuildContext context) {
    final Color? colour = AppColors.categoryColors[categoryKey];
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: colour ?? AppColors.muted,
        shape: BoxShape.circle,
      ),
    );
  }
}

Future<String?> _promptForLabel(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  final TextEditingController controller = TextEditingController(
    text: initial ?? '',
  );
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: UserCategory.maxLabelLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Runs a write against the repository and reports failure in one place.
Future<void> _write(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(CategoriesRepository repo) action,
) async {
  final CategoriesRepository? repo = ref.read(categoriesRepositoryProvider);
  if (repo == null) return;
  try {
    await action(repo);
  } on DataFailure catch (e) {
    if (context.mounted) _say(context, e.message);
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
