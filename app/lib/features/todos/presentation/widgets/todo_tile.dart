import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../categories/application/category_providers.dart';
import '../../../categories/domain/user_category.dart';
import '../../domain/todo.dart';

/// One task in the list.
class TodoTile extends StatelessWidget {
  const TodoTile({
    required this.todo,
    required this.onToggleStatus,
    required this.onTap,
    this.parent,
    super.key,
  });

  final Todo todo;

  /// Advances the status. See [_StatusButton] for why it cycles rather than
  /// toggling.
  final VoidCallback onToggleStatus;

  final VoidCallback onTap;

  /// The task this one follows up on, if it is still around. Null either
  /// because this is not a follow-up or because the parent was deleted —
  /// Firestore has no referential integrity, so both are ordinary.
  final Todo? parent;

  @override
  Widget build(BuildContext context) {
    final bool overdue = todo.isOverdue();
    final bool dueToday = todo.isDueToday();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _StatusButton(status: todo.status, onPressed: onToggleStatus),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (parent != null) _FollowUpLine(parent: parent!),
                  Text(
                    todo.title,
                    style: TextStyle(
                      color: todo.isCompleted
                          ? AppColors.muted
                          : AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      // Struck through as well as dimmed. The project rule that
                      // colour is never the only signal applies to "done" too.
                      decoration: todo.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppColors.muted,
                    ),
                  ),
                  if (todo.notes != null &&
                      todo.notes!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      todo.notes!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _MetaRow(todo: todo, overdue: overdue, dueToday: dueToday),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The circle on the left, which **cycles** pending → in progress → completed
/// → pending.
///
/// A plain checkbox would only ever express two of the three statuses, leaving
/// "in progress" reachable exclusively through the edit sheet — which is three
/// taps for the single most common state change in a task list. Cycling puts
/// all three one tap apart, and the icon says which one you are in rather than
/// relying on the colour.
class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onPressed});

  final TodoStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      TodoStatus.pending => (Icons.radio_button_unchecked, AppColors.muted),
      TodoStatus.inProgress => (
        Icons.incomplete_circle,
        AppColors.statusWarning,
      ),
      TodoStatus.completed => (Icons.check_circle, AppColors.statusGood),
    };

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      // The tooltip carries the current state in words, which is what makes
      // the three-way cycle legible to a screen reader and to anyone who
      // cannot tell the icons apart at a glance.
      tooltip: '${status.label} — tap to advance',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

/// The parent task's title, shown above a follow-up's own title.
class _FollowUpLine extends StatelessWidget {
  const _FollowUpLine({required this.parent});

  final Todo parent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.subdirectory_arrow_right,
            size: 13,
            color: AppColors.muted,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              parent.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Category, deadline, reminder and priority, on one wrapping line.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.todo,
    required this.overdue,
    required this.dueToday,
  });

  final Todo todo;
  final bool overdue;
  final bool dueToday;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        CategoryPill(category: todo.category),
        if (todo.deadline != null)
          _MetaChip(
            icon: overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
            // "Overdue" in words, not just a red date — the same reason the
            // title is struck through as well as dimmed.
            label: overdue
                ? 'Overdue · ${AppDates.relativeDay(todo.deadline!)}'
                : AppDates.relativeDay(todo.deadline!),
            color: overdue
                ? AppColors.statusCritical
                : (dueToday ? AppColors.statusWarning : AppColors.muted),
          ),
        if (todo.reminderAt != null)
          _MetaChip(
            icon: Icons.notifications_none,
            label: AppDates.relativeDay(todo.reminderAt!),
            color: AppColors.muted,
          ),
        // Only `high` is shown. Medium is the default and labelling every
        // ordinary task "Medium" is noise that makes the genuinely urgent ones
        // harder to spot; low is information the list does not need to shout.
        if (todo.priority == TodoPriority.high && !todo.isCompleted)
          const _MetaChip(
            icon: Icons.priority_high,
            label: 'High',
            color: AppColors.statusSerious,
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

/// The category badge, in that category's fixed colour.
///
/// Shared with the filter chips so the colour of "Work" is drawn from one place
/// on both. [AppColors.onCategory] picks the text colour, because gold is light
/// enough that white on it fails contrast.
///
/// **A category the brand has no colour for falls back to the muted tone**,
/// which takes the same dark ink [AppColors.onCategory] gives every category.
/// The four category colours are fixed and never reassigned or cycled
/// (`CLAUDE.md` → Brand & UI tokens), so a fifth user-added todo category does
/// not get a generated hue — it gets the neutral one and leans on its label,
/// which is the same answer the dataviz rules give for a ninth series.
///
/// It reads the label from the user's own list, so renaming `work` to `Trabajo`
/// changes every badge in the app at once.
class CategoryPill extends ConsumerWidget {
  const CategoryPill({required this.category, this.dimmed = false, super.key});

  final String category;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color background =
        AppColors.categoryColors[category] ?? AppColors.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: dimmed ? background.withValues(alpha: 0.25) : background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        ref.watch(categorySetProvider(CategoryKind.todo)).label(category),
        style: TextStyle(
          color: dimmed
              ? AppColors.textSecondary
              : AppColors.onCategory(category),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
