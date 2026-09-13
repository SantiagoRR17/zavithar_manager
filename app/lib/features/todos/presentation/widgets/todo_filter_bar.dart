import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/todo_providers.dart';
import '../../domain/todo.dart';

/// The two rows of filter chips above the list: categories, then statuses.
///
/// Both are single-select-or-none. Tapping the chip that is already on turns it
/// off, so "all" is always one tap away from wherever you are — a filter you
/// can switch on but not off by tapping the same thing is a small, constant
/// irritation.
///
/// The counts are cross-filtered: the status counts respect the selected
/// category and vice versa, so "Pending 3" under a selected "Work" means three
/// pending *work* tasks. A count that ignored the other filter would be
/// answering a question nobody asked.
class TodoFilterBar extends ConsumerWidget {
  const TodoFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? category = ref.watch(todoCategoryFilterProvider);
    final TodoStatus? status = ref.watch(todoStatusFilterProvider);
    final Map<String, int> categoryCounts = ref.watch(
      todoCategoryCountsProvider,
    );
    final Map<TodoStatus, int> statusCounts = ref.watch(
      todoStatusCountsProvider,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              for (final String c in TodoCategories.all) ...<Widget>[
                _FilterChip(
                  label: TodoCategories.label(c),
                  count: categoryCounts[c] ?? 0,
                  selected: category == c,
                  // Selected, a category chip wears its own colour — the same
                  // one the pill on every row of that category wears. That is
                  // what ties the filter to the rows it produces without a
                  // legend.
                  selectedColor: AppColors.categoryColors[c],
                  onSelectedColor: AppColors.onCategory(c),
                  onTap: () =>
                      ref.read(todoCategoryFilterProvider.notifier).toggle(c),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              for (final TodoStatus s in TodoStatus.values) ...<Widget>[
                _FilterChip(
                  label: s.label,
                  count: statusCounts[s] ?? 0,
                  selected: status == s,
                  selectedColor: AppColors.brandPrimary,
                  onSelectedColor: AppColors.textPrimary,
                  onTap: () =>
                      ref.read(todoStatusFilterProvider.notifier).toggle(s),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.onSelectedColor,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? selectedColor;
  final Color? onSelectedColor;

  @override
  Widget build(BuildContext context) {
    final Color accent = selectedColor ?? AppColors.brandPrimary;
    final Color foreground = selected
        ? (onSelectedColor ?? AppColors.textPrimary)
        : AppColors.textSecondary;

    return Material(
      color: selected ? accent : AppColors.surface2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? accent : AppColors.gridline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  // Dimmed rather than hidden at zero: a chip that disappears
                  // when its count is zero makes the row jump around as you
                  // filter, and an empty category is worth knowing about.
                  color: selected
                      ? foreground
                      : (count == 0 ? AppColors.gridline : AppColors.muted),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
