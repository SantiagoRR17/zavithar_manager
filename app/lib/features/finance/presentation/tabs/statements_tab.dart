import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/data_failure.dart';
import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/async_states.dart';
import '../../application/statement_providers.dart';
import '../../data/statements_repository.dart';
import '../../domain/monthly_statement.dart';
import '../../domain/statement_period.dart';
import '../statement_detail_sheet.dart';

/// The statements tab: close a finished month, then read it back like a bank
/// statement.
///
/// See [ADR 0012](../../../../../docs/adr/0012-monthly-statements.md).
class StatementsTab extends ConsumerWidget {
  const StatementsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MonthlyStatement>> statements = ref.watch(
      statementsStreamProvider,
    );

    return statements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) =>
          AppErrorState(title: 'Could not load your statements', error: error),
      data: (List<MonthlyStatement> items) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: <Widget>[
            const _CloseMonthCard(),
            if (items.isEmpty)
              const _NoStatementsYet()
            else ...<Widget>[
              const SizedBox(height: 20),
              const _SectionLabel('Closed months'),
              const SizedBox(height: 8),
              for (final MonthlyStatement s in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _StatementCard(statement: s),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// The card at the top: either an offer to close the next month, or an
/// explanation of why there is nothing to close.
class _CloseMonthCard extends ConsumerStatefulWidget {
  const _CloseMonthCard();

  @override
  ConsumerState<_CloseMonthCard> createState() => _CloseMonthCardState();
}

class _CloseMonthCardState extends ConsumerState<_CloseMonthCard> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final StatementPeriod? period = ref.watch(closablePeriodProvider);
    final MonthlyStatement? pending = ref.watch(pendingStatementProvider);

    if (period == null || pending == null) {
      return const _NothingToClose();
    }

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
              const Icon(
                Icons.event_available_outlined,
                size: 18,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'Ready to close ${period.label}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The preview is the whole point of showing this before acting: a
          // close is reversible, but a number you did not look at is one you
          // will never go back and check.
          _AmountRow(
            label: 'Income',
            value: Money.format(pending.totalIncome),
            color: AppColors.statusGood,
          ),
          _AmountRow(
            label: 'Expense',
            value: Money.format(pending.totalExpense),
            color: AppColors.brandPrimaryLight,
          ),
          _AmountRow(
            label: '${pending.transactionCount} transactions · net',
            value: Money.formatSigned(pending.net, isIncome: pending.net >= 0),
            color: pending.net >= 0
                ? AppColors.statusGood
                : AppColors.brandPrimaryLight,
            bold: true,
          ),
          const Divider(height: 20, color: AppColors.gridline),
          _AmountRow(
            label: 'Closing balance',
            value: Money.format(pending.closingBalance),
            color: AppColors.textPrimary,
            bold: true,
          ),
          const SizedBox(height: 14),
          Text(
            'Closing stops these transactions being loaded every time you open '
            'the app. Nothing is deleted — reopen the month and they come '
            'straight back.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _closing ? null : () => _close(pending),
            icon: _closing
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline, size: 18),
            label: Text('Close ${period.shortLabel}'),
          ),
        ],
      ),
    );
  }

  Future<void> _close(MonthlyStatement pending) async {
    final StatementsRepository? repository = ref.read(
      statementsRepositoryProvider,
    );
    if (repository == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _closing = true);

    try {
      await repository.close(pending);
      messenger.showSnackBar(
        SnackBar(content: Text('${pending.period.label} closed.')),
      );
    } on DataFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }
}

/// Why there is nothing to close — which is almost always "the month is still
/// running", and saying so is better than an empty space.
class _NothingToClose extends ConsumerWidget {
  const _NothingToClose();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StatementPeriod? lastClosed = ref.watch(lastClosedPeriodProvider);
    final StatementPeriod current = StatementPeriod.of(DateTime.now());

    final String message = lastClosed == null
        ? 'Once your first month is over you can close it here, and it will '
              'stop being loaded every time the app opens.'
        : '${current.label} is still running. It can be closed once it ends.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.schedule, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.statement});

  final MonthlyStatement statement;

  @override
  Widget build(BuildContext context) {
    final bool up = statement.net >= 0;

    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showStatementDetailSheet(context, statement),
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
                      statement.period.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    Money.formatSigned(statement.net, isIncome: up),
                    style: TextStyle(
                      color: up
                          ? AppColors.statusGood
                          : AppColors.brandPrimaryLight,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${statement.transactionCount} transactions · closing '
                '${Money.format(statement.closingBalance)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoStatementsYet extends StatelessWidget {
  const _NoStatementsYet();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40),
      child: AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No closed months yet',
        message:
            'A statement is a summary of one finished month — totals, a '
            'category breakdown, and the balance it left behind.',
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}
