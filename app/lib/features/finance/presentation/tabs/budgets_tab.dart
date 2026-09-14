import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../categories/application/category_providers.dart';
import '../../../categories/domain/user_category.dart';
import '../../../../core/errors/data_failure.dart';
import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/async_states.dart';
import '../../application/budget_providers.dart';
import '../../data/budgets_repository.dart';
import '../../domain/budget.dart';
import '../budget_form_sheet.dart';

/// Monthly spending caps, measured against what has actually been spent.
class BudgetsTab extends ConsumerWidget {
  const BudgetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Budget>> budgets = ref.watch(budgetsStreamProvider);
    final List<BudgetStatus> statuses = ref.watch(budgetStatusProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showBudgetFormSheet(context),
        tooltip: 'New budget',
        child: const Icon(Icons.add),
      ),
      body: budgets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            AppErrorState(title: 'Could not load your budgets', error: error),
        data: (List<Budget> items) {
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.savings_outlined,
              title: 'No budgets set',
              message:
                  'Cap what you want to spend in a category each month. The '
                  'bar fills as you spend, and tells you whether you are ahead '
                  'of the month or behind it.',
            );
          }
          return _BudgetList(statuses: statuses);
        },
      ),
    );
  }
}

class _BudgetList extends ConsumerWidget {
  const _BudgetList({required this.statuses});

  final List<BudgetStatus> statuses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (num budgeted, num spent) = BudgetReport.totals(statuses);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: <Widget>[
        _MonthHeader(budgeted: budgeted, spent: spent),
        const SizedBox(height: 12),
        for (final BudgetStatus s in statuses)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Dismissible(
              key: ValueKey<String>(s.category),
              direction: DismissDirection.endToStart,
              background: const DeleteBackground(),
              onDismissed: (DismissDirection _) =>
                  _deleteWithUndo(context, ref, s.budget),
              child: _BudgetCard(status: s),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    Budget budget,
  ) async {
    final BudgetsRepository? repository = ref.read(budgetsRepositoryProvider);
    if (repository == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await repository.delete(budget.category);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${ref.read(categorySetProvider(CategoryKind.expense)).label(budget.category)} '
              'budget removed.',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repository.save(budget),
            ),
          ),
        );
    } on DataFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Where the month is, and the total across every budget.
///
/// The elapsed-month bar is the reference the individual bars are read
/// against: a budget 60% spent means nothing until you know whether the month
/// is 30% or 90% gone.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.budgeted, required this.spent});

  final num budgeted;
  final num spent;

  @override
  Widget build(BuildContext context) {
    final double elapsed = BudgetStatus.monthElapsed();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gridline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Spent this month',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${Money.format(spent)} of ${Money.format(budgeted)}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: elapsed,
              minHeight: 5,
              backgroundColor: AppColors.gridline,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.muted),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(elapsed * 100).round()}% of the month gone',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Three states, and the middle one is the whole point of the feature:
    // within budget but spending faster than the month is passing. A plain
    // percentage cannot say that, and by the time the bar is full it is too
    // late to act on.
    final (Color tone, String label, IconData icon) = status.isOver
        ? (
            AppColors.statusCritical,
            'Over by ${Money.format(status.overspend)}',
            Icons.error_outline,
          )
        : status.isOnTrack
        ? (
            AppColors.statusGood,
            '${Money.format(status.remaining)} left',
            Icons.check_circle_outline,
          )
        : (
            AppColors.statusWarning,
            'Ahead of pace · ${Money.format(status.remaining)} left',
            Icons.trending_up,
          );

    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showBudgetFormSheet(context, initial: status.budget),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ref
                          .watch(categorySetProvider(CategoryKind.expense))
                          .label(status.category),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${Money.format(status.spent)} / '
                    '${Money.format(status.limit)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: status.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.gridline,
                  valueColor: AlwaysStoppedAnimation<Color>(tone),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(icon, size: 14, color: tone),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(color: tone, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
