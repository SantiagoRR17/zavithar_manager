import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import '../application/statement_providers.dart';
import '../data/statements_repository.dart';
import '../domain/finance_categories.dart';
import '../domain/monthly_statement.dart';

/// The statement, in full: totals, category breakdown, and the two actions a
/// closed month supports — verify and reopen.
Future<void> showStatementDetailSheet(
  BuildContext context,
  MonthlyStatement statement,
) {
  return showAppSheet(
    context,
    builder: (BuildContext context) =>
        StatementDetailSheet(statement: statement),
  );
}

class StatementDetailSheet extends ConsumerStatefulWidget {
  const StatementDetailSheet({required this.statement, super.key});

  final MonthlyStatement statement;

  @override
  ConsumerState<StatementDetailSheet> createState() =>
      _StatementDetailSheetState();
}

class _StatementDetailSheetState extends ConsumerState<StatementDetailSheet> {
  bool _busy = false;
  StatementVerification? _verification;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final MonthlyStatement s = widget.statement;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                s.period.label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.closedAt == null
                    ? 'Closed'
                    : 'Closed ${AppDates.short(s.closedAt!)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),

              _Line('Opening balance', Money.format(s.openingBalance)),
              _Line(
                'Income',
                Money.format(s.totalIncome),
                color: AppColors.statusGood,
              ),
              _Line(
                'Expense',
                Money.format(s.totalExpense),
                color: AppColors.brandPrimaryLight,
              ),
              _Line(
                'Net',
                Money.formatSigned(s.net, isIncome: s.net >= 0),
                color: s.net >= 0
                    ? AppColors.statusGood
                    : AppColors.brandPrimaryLight,
                bold: true,
              ),
              const Divider(height: 22, color: AppColors.gridline),
              _Line(
                'Closing balance',
                Money.format(s.closingBalance),
                bold: true,
              ),

              if (s.expenseByCategory.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                const _Heading('Where it went'),
                const SizedBox(height: 6),
                ..._breakdown(s.expenseByCategory, s.totalExpense),
              ],
              if (s.incomeByCategory.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                const _Heading('Where it came from'),
                const SizedBox(height: 6),
                ..._breakdown(s.incomeByCategory, s.totalIncome),
              ],

              const SizedBox(height: 22),
              if (_verification != null) _VerificationResult(_verification!),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.statusCritical,
                    fontSize: 13,
                  ),
                ),
              ],

              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _verify,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Check against the transactions'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _confirmReopen,
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Reopen this month'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Reopening brings this month’s transactions back into the '
                'list so they can be edited. Nothing was ever deleted.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Category rows, largest first, each with its share of the total.
  ///
  /// Sorted by amount rather than by the fixed category order used elsewhere:
  /// the question a statement answers is "what did the money go on", and that
  /// is a ranking, not a list.
  List<Widget> _breakdown(Map<String, num> byCategory, num total) {
    final List<MapEntry<String, num>> entries = byCategory.entries.toList()
      ..sort(
        (MapEntry<String, num> a, MapEntry<String, num> b) =>
            b.value.compareTo(a.value),
      );

    return <Widget>[
      for (final MapEntry<String, num> e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  FinanceCategories.label(e.key),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              if (total > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    '${(e.value / total * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              Text(
                Money.format(e.value),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Future<void> _verify() async {
    final StatementsRepository? repository = ref.read(
      statementsRepositoryProvider,
    );
    if (repository == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _verification = null;
    });

    try {
      final StatementVerification result = await repository.verify(
        widget.statement,
      );
      if (mounted) setState(() => _verification = result);
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReopen() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            backgroundColor: AppColors.surface1,
            title: Text('Reopen ${widget.statement.period.label}?'),
            content: const Text(
              'The statement is deleted and the month’s transactions '
              'return to the list. You can close it again afterwards.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Reopen'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    final StatementsRepository? repository = ref.read(
      statementsRepositoryProvider,
    );
    if (repository == null) return;

    setState(() => _busy = true);
    try {
      await repository.reopen(widget.statement.period);
      if (mounted) Navigator.of(context).pop();
    } on DataFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }
}

/// What the check found.
///
/// A match is stated as plainly as a mismatch. "Checked, and it adds up" is the
/// result that makes the feature worth having — a verification that only ever
/// speaks up when something is wrong leaves you unable to tell it apart from
/// one that never ran.
class _VerificationResult extends StatelessWidget {
  const _VerificationResult(this.result);

  final StatementVerification result;

  @override
  Widget build(BuildContext context) {
    final bool ok = result.matches;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok ? AppColors.statusGood : AppColors.statusWarning,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            ok ? Icons.verified_outlined : Icons.report_problem_outlined,
            size: 18,
            color: ok ? AppColors.statusGood : AppColors.statusWarning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ok
                      ? 'Checked — the statement matches the transactions'
                      : 'The statement no longer matches the transactions',
                  style: TextStyle(
                    color: ok ? AppColors.statusGood : AppColors.statusWarning,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!ok) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${result.countDrift > 0 ? '+' : ''}'
                    '${result.countDrift} transactions, net off by '
                    '${Money.format(result.netDrift)}. Reopen and close the '
                    'month again to rebuild it.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
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
              color: color ?? AppColors.textPrimary,
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

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
