import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/data_failure.dart';
import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/async_states.dart';
import '../../application/recurring_providers.dart';
import '../../data/recurring_repository.dart';
import '../../domain/finance_categories.dart';
import '../../domain/recurring_rule.dart';
import '../recurring_form_sheet.dart';

/// Transactions that repeat, and the button that creates the ones now due.
class RecurringTab extends ConsumerWidget {
  const RecurringTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecurringRule>> rules = ref.watch(
      recurringStreamProvider,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showRecurringFormSheet(context),
        tooltip: 'New recurring transaction',
        child: const Icon(Icons.add),
      ),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => AppErrorState(
          title: 'Could not load your recurring transactions',
          error: error,
        ),
        data: (List<RecurringRule> items) {
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.repeat,
              title: 'Nothing repeats yet',
              message:
                  'Set up rent, a salary or a subscription once. When each one '
                  'comes due the app offers to create it — it never writes '
                  'anything without being asked.',
            );
          }
          return _RecurringList(rules: items);
        },
      ),
    );
  }
}

class _RecurringList extends ConsumerWidget {
  const _RecurringList({required this.rules});

  final List<RecurringRule> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: <Widget>[
        const PendingRecurrenceCard(),
        const SizedBox(height: 12),
        for (final RecurringRule rule in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Dismissible(
              key: ValueKey<String>(rule.id),
              direction: DismissDirection.endToStart,
              background: const DeleteBackground(),
              onDismissed: (DismissDirection _) =>
                  _deleteWithUndo(context, ref, rule),
              child: _RuleCard(rule: rule),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    RecurringRule rule,
  ) async {
    final RecurringRepository? repository = ref.read(
      recurringRepositoryProvider,
    );
    if (repository == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await repository.delete(rule.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Recurring transaction removed.'),
            action: SnackBarAction(
              label: 'Undo',
              // Deleting the rule never touches the transactions it already
              // created — those are ordinary rows with their own history.
              onPressed: () => repository.add(rule),
            ),
          ),
        );
    } on DataFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// What is due, and the button that creates it.
///
/// Shown on the Recurring tab and again above the transactions list, because
/// the transactions list is where a missing rent charge is actually noticed.
class PendingRecurrenceCard extends ConsumerStatefulWidget {
  const PendingRecurrenceCard({super.key});

  @override
  ConsumerState<PendingRecurrenceCard> createState() =>
      _PendingRecurrenceCardState();
}

class _PendingRecurrenceCardState extends ConsumerState<PendingRecurrenceCard> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final int due = ref.watch(pendingRecurrenceCountProvider);
    final int skipped = ref.watch(skippedRecurrenceCountProvider);

    if (due == 0 && skipped == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: due > 0 ? AppColors.brandPrimary : AppColors.statusWarning,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (due > 0) ...<Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.repeat,
                  size: 18,
                  color: AppColors.brandPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$due transaction${due == 1 ? '' : 's'} ready to create',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Nothing is written until you press this. Two devices opening '
              'the app at once could otherwise each decide the same rent was '
              'owed.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check, size: 18),
              label: Text('Create $due transaction${due == 1 ? '' : 's'}'),
            ),
          ],
          if (skipped > 0) ...<Widget>[
            if (due > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: AppColors.statusWarning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$skipped occurrence${skipped == 1 ? '' : 's'} fall in a '
                    'month you have already closed, so they cannot be created. '
                    'Reopen that month in Statements, or add them by hand.',
                    style: const TextStyle(
                      color: AppColors.statusWarning,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final int created = await ref.read(runRecurrenceProvider)();
    if (mounted) {
      setState(() => _running = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            created == 0
                ? 'Nothing was created.'
                : '$created transaction${created == 1 ? '' : 's'} created.',
          ),
        ),
      );
    }
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule});

  final RecurringRule rule;

  @override
  Widget build(BuildContext context) {
    final bool income = rule.type.isIncome;

    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showRecurringFormSheet(context, initial: rule),
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          // Paused rules stay visible and keep their schedule; they simply
          // create nothing. Deleting would lose the template, which is not
          // what anyone means by "cancel the subscription for now".
          opacity: rule.active ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        rule.description?.trim().isNotEmpty == true
                            ? rule.description!.trim()
                            : FinanceCategories.label(rule.category),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      Money.formatSigned(rule.amount, isIncome: income),
                      style: TextStyle(
                        color: income
                            ? AppColors.statusGood
                            : AppColors.brandPrimaryLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    const Icon(Icons.repeat, size: 13, color: AppColors.muted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        rule.active
                            ? '${rule.cadence.label} · next '
                                  '${AppDates.short(rule.nextRunAt)}'
                            : 'Paused',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      FinanceCategories.label(rule.category),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
