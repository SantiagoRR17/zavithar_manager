import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/money.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../application/dashboard_providers.dart';
import '../domain/finance_summary.dart';
import 'widgets/stat_tile.dart';

/// The landing screen after sign-in: the state of the money, at a glance.
///
/// Every figure here is derived from the same three live Firestore streams the
/// Finance tab uses — nothing on this screen is stored, and nothing on it opens
/// a listener of its own. See [financeSummaryProvider].
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FinanceSummary> summary = ref.watch(
      financeSummaryProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            _DashboardError(error: error),
        data: (FinanceSummary data) =>
            data.isEmpty ? const _DashboardEmpty() : _DashboardBody(data: data),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final FinanceSummary data;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        _BalanceCard(balance: data.balance),
        const SizedBox(height: 20),
        _SectionLabel(AppDates.monthYear(now)),
        const SizedBox(height: 10),
        _TileGrid(
          children: <Widget>[
            StatTile(
              label: 'Income',
              value: Money.format(data.monthIncome),
              icon: Icons.arrow_downward,
              accent: AppColors.statusGood,
              valueColor: AppColors.statusGood,
              onTap: () => context.go(AppRoutes.finance),
            ),
            StatTile(
              label: 'Expense',
              value: Money.format(data.monthExpense),
              icon: Icons.arrow_upward,
              accent: AppColors.brandPrimaryLight,
              valueColor: AppColors.brandPrimaryLight,
              onTap: () => context.go(AppRoutes.finance),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _NetRow(net: data.monthNet),
        const SizedBox(height: 20),
        const _SectionLabel('Goals and debts'),
        const SizedBox(height: 10),
        _TileGrid(
          children: <Widget>[
            StatTile(
              label: 'Saved',
              value: Money.format(data.savedTotal),
              icon: Icons.savings_outlined,
              // Green, not the brand red. On this screen red already means
              // "expense" — the arrow on the tile two rows up — so a red piggy
              // bank made savings read as something to worry about, while the
              // amber debt tile beside it looked calmer. The thing you want
              // more of cannot look worse than the thing you want less of.
              // The palette across this screen is now: green is yours, amber
              // is owed, red is spent.
              accent: AppColors.statusGood,
              progress: data.savingsProgress,
              caption: data.goalCount == 0
                  ? 'No goals yet'
                  : 'of ${Money.format(data.savingsTarget)} across '
                        '${_plural(data.goalCount, 'goal')}',
              onTap: () => context.go(AppRoutes.finance),
            ),
            StatTile(
              label: 'Debt left',
              value: Money.format(data.debtRemaining),
              icon: Icons.account_balance_outlined,
              accent: AppColors.statusWarning,
              progress: data.debtProgress,
              caption: data.debtCount == 0
                  ? 'Nothing owed'
                  : '${(data.debtProgress * 100).round()}% repaid across '
                        '${_plural(data.debtCount, 'debt')}',
              onTap: () => context.go(AppRoutes.finance),
            ),
          ],
        ),
      ],
    );
  }

  static String _plural(int count, String noun) =>
      count == 1 ? '1 $noun' : '$count ${noun}s';
}

/// The headline number, given the whole width because it is the one figure
/// worth reading from across the room.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final num balance;

  @override
  Widget build(BuildContext context) {
    final bool negative = balance < 0;

    // Red for negative, green for positive — and the sign and the caption say
    // the same thing, because a colour is never the only signal here. The red
    // is `brandPrimaryLight`, matching the expense rows in the transactions
    // list, deliberately not `statusCritical`: being in the red is a state to
    // notice, not an emergency, and reserving the alarm colour means it still
    // means something when something is genuinely wrong.
    final Color tone = negative
        ? AppColors.brandPrimaryLight
        : AppColors.statusGood;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gridline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Balance',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              // U+2212 MINUS SIGN, the same character `Money.formatSigned`
              // uses, so a negative balance lines up with the amounts below it.
              '${negative ? '−' : ''}${Money.format(balance)}',
              maxLines: 1,
              style: TextStyle(
                color: tone,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(
                negative ? Icons.trending_down : Icons.trending_up,
                size: 15,
                color: tone,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  negative
                      ? 'Spent more than you have recorded coming in'
                      : 'All recorded income, minus all recorded expense',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// This month's net, under the income/expense pair that produces it.
class _NetRow extends StatelessWidget {
  const _NetRow({required this.net});

  final num net;

  @override
  Widget build(BuildContext context) {
    // Three states, not two. Treating zero as positive — the obvious
    // `net >= 0` — puts a green tick and a "+$0" on a month in which nothing
    // happened, which reads as approval of an achievement that does not exist.
    // A month with no activity is neither good nor bad news, and the row says
    // so by being neutral.
    final bool isZero = net == 0;
    final bool up = net > 0;

    final Color tone = isZero
        ? AppColors.muted
        : (up ? AppColors.statusGood : AppColors.brandPrimaryLight);

    final IconData icon = isZero
        ? Icons.remove_circle_outline
        : (up ? Icons.check_circle_outline : Icons.error_outline);

    // No sign on zero either: "+$0" implies a direction that $0 does not have.
    final String sign = isZero ? '' : (up ? '+' : '−');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Net this month',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Text(
            '$sign${Money.format(net)}',
            style: TextStyle(
              color: tone,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays tiles out two-up on a phone and four-up on a wide window.
///
/// A [Wrap] rather than a `GridView.count`, because a grid forces every cell to
/// one `childAspectRatio` and these tiles are not all the same height — the ones
/// with a progress bar and a two-line caption are taller. Pinning a ratio that
/// suits the tallest wastes space under the shortest, and one that suits the
/// shortest overflows. Wrap lets each tile size itself.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 12;
        // 720 is the same breakpoint `app_shell.dart` uses to swap the bottom
        // bar for a side rail, so the layout changes shape once, not twice.
        final int columns = constraints.maxWidth >= 720 ? 4 : 2;
        final double itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
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

/// What a brand-new account sees, instead of a grid of zeroes.
///
/// A dashboard of `$0` tiles looks like a screen that failed to load rather
/// than one with nothing to show yet, which is the same reasoning behind
/// `AppEmptyState` on the three finance tabs.
class _DashboardEmpty extends StatelessWidget {
  const _DashboardEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.insights_outlined,
              size: 48,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            const Text(
              'Nothing to summarise yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Record a transaction, a savings goal or a debt and it will be '
              'totalled here — on both your devices, straight away.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.finance),
              icon: const Icon(Icons.add),
              label: const Text('Go to Finance'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.statusCritical,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not build your summary',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
