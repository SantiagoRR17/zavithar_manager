import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/savings_goal.dart';

/// One savings goal: name, progress bar, amounts, and a button to add to it.
class SavingsGoalCard extends StatelessWidget {
  const SavingsGoalCard({
    required this.goal,
    required this.onContribute,
    this.onTap,
    super.key,
  });

  final SavingsGoal goal;
  final VoidCallback onContribute;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool complete = goal.isComplete;
    final Color accent = complete
        ? AppColors.statusGood
        : AppColors.brandPrimaryLight;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // The tick is what says "done" — the green is a reinforcement,
                  // never the only signal.
                  if (complete)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.check_circle,
                        size: 18,
                        color: AppColors.statusGood,
                      ),
                    ),
                  IconButton(
                    onPressed: onContribute,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add to this goal',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 8,
                  backgroundColor: AppColors.gridline,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '${Money.format(goal.currentAmount)} of '
                    '${Money.format(goal.targetAmount)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    complete
                        ? 'Goal reached'
                        : '${Money.format(goal.remaining)} to go',
                    style: TextStyle(
                      color: complete ? AppColors.statusGood : AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (goal.deadline != null) ...<Widget>[
                const SizedBox(height: 6),
                _DeadlineLine(deadline: goal.deadline!, complete: complete),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The deadline line, which turns into a warning once the date has passed on a
/// goal that is not met.
class _DeadlineLine extends StatelessWidget {
  const _DeadlineLine({required this.deadline, required this.complete});

  final DateTime deadline;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final bool overdue =
        !complete && deadline.isBefore(DateTime.now());

    return Row(
      children: <Widget>[
        Icon(
          overdue ? Icons.warning_amber_rounded : Icons.flag_outlined,
          size: 14,
          color: overdue ? AppColors.statusWarning : AppColors.muted,
        ),
        const SizedBox(width: 6),
        Text(
          overdue
              ? 'Deadline passed — ${AppDates.short(deadline)}'
              : 'By ${AppDates.short(deadline)}',
          style: TextStyle(
            color: overdue ? AppColors.statusWarning : AppColors.muted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
