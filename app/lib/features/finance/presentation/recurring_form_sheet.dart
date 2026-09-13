import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/optional_date_field.dart';
import '../application/recurring_providers.dart';
import '../application/statement_providers.dart';
import '../data/recurring_repository.dart';
import '../domain/finance_accounts.dart';
import '../domain/finance_categories.dart';
import '../domain/finance_transaction.dart';
import '../domain/recurring_rule.dart';
import 'widgets/amount_form_field.dart';

/// Create or edit a recurring transaction. Pass [initial] to edit.
Future<void> showRecurringFormSheet(
  BuildContext context, {
  RecurringRule? initial,
}) {
  return showAppSheet(
    context,
    builder: (BuildContext context) => RecurringFormSheet(initial: initial),
  );
}

class RecurringFormSheet extends ConsumerStatefulWidget {
  const RecurringFormSheet({this.initial, super.key});

  final RecurringRule? initial;

  @override
  ConsumerState<RecurringFormSheet> createState() => _RecurringFormSheetState();
}

class _RecurringFormSheetState extends ConsumerState<RecurringFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;

  late TransactionType _type;
  late String _category;
  late Cadence _cadence;
  late DateTime _startDate;
  String? _account;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final RecurringRule? initial = widget.initial;

    _amountController = TextEditingController(
      text: initial == null ? '' : Money.grouped(initial.amount),
    );
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    _type = initial?.type ?? TransactionType.expense;
    _category = initial?.category ?? FinanceCategories.defaultFor(_type);
    _cadence = initial?.cadence ?? Cadence.monthly;
    _startDate = initial?.nextRunAt ?? DateTime.now();
    _account = initial?.account;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? openFrom = ref.watch(openPeriodStartProvider);

    return AppSheetBody(
      formKey: _formKey,
      title: _isEditing ? 'Edit recurring' : 'New recurring transaction',
      subtitle: _isEditing
          ? null
          : 'A template plus a schedule. It creates ordinary transactions — it '
                'does not move money by itself.',
      error: _error,
      saving: _saving,
      submitLabel: _isEditing ? 'Save changes' : 'Create',
      onSubmit: _save,
      children: <Widget>[
        _Segmented<TransactionType>(
          values: TransactionType.values,
          selected: _type,
          labelOf: (TransactionType t) => t.label,
          onSelected: (TransactionType t) => setState(() {
            _type = t;
            // A category that makes no sense for the new type is reset rather
            // than silently written — `groceries` is not a kind of income.
            if (!FinanceCategories.isValidFor(_category, t)) {
              _category = FinanceCategories.defaultFor(t);
            }
          }),
        ),
        const SizedBox(height: 16),
        AmountFormField(
          controller: _amountController,
          label: 'Amount',
          large: true,
        ),
        const SizedBox(height: 16),
        const _Label('Category'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String c in FinanceCategories.forType(_type))
              _Chip(
                label: FinanceCategories.label(c),
                selected: _category == c,
                onTap: () => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const _Label('Repeats'),
        const SizedBox(height: 8),
        _Segmented<Cadence>(
          values: Cadence.values,
          selected: _cadence,
          labelOf: (Cadence c) => c.label,
          onSelected: (Cadence c) => setState(() => _cadence = c),
        ),
        const SizedBox(height: 20),
        OptionalDateField(
          label: _isEditing ? 'Next occurrence' : 'First occurrence',
          value: _startDate,
          // Cannot be dated into a closed month, for the same reason an
          // ordinary transaction cannot (ADR 0012): the rules would refuse
          // every occurrence and the schedule would stall with no explanation.
          firstDate: openFrom,
          helperText: _cadenceHelp(),
          onChanged: (DateTime? value) {
            if (value != null) setState(() => _startDate = value);
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          maxLength: 200,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'Rent, salary, streaming…',
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: _account,
          decoration: const InputDecoration(labelText: 'Account (optional)'),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(child: Text('Not set')),
            for (final String a in FinanceAccounts.all)
              DropdownMenuItem<String>(
                value: a,
                child: Text(FinanceAccounts.label(a)),
              ),
          ],
          onChanged: (String? value) => setState(() => _account = value),
        ),
      ],
    );
  }

  /// Says in words what the schedule will actually do, because "monthly" and
  /// "the 31st" together have a non-obvious answer in February.
  String _cadenceHelp() {
    return switch (_cadence) {
      Cadence.weekly => 'Every 7 days from this date.',
      Cadence.monthly =>
        _startDate.day > 28
            ? 'The ${_startDate.day}th of each month, or the last day in shorter '
                  'months.'
            : 'The ${_startDate.day}th of each month.',
      Cadence.yearly => 'Once a year on this date.',
    };
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final RecurringRepository? repository = ref.read(
      recurringRepositoryProvider,
    );
    if (repository == null) {
      setState(() => _error = 'You are signed out.');
      return;
    }

    final num amount = Money.tryParse(_amountController.text)!;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await repository.update(
          widget.initial!.copyWith(
            amount: amount,
            type: _type,
            category: _category,
            description: _descriptionController.text,
            account: _account,
            cadence: _cadence,
            anchorDay: RecurrenceSchedule.anchorFor(_startDate, _cadence),
            nextRunAt: _startDate,
            clearDescription: _descriptionController.text.trim().isEmpty,
            clearAccount: _account == null,
          ),
        );
      } else {
        await repository.add(
          RecurringRule(
            id: '',
            amount: amount,
            type: _type,
            category: _category,
            description: _descriptionController.text,
            account: _account,
            cadence: _cadence,
            anchorDay: RecurrenceSchedule.anchorFor(_startDate, _cadence),
            nextRunAt: RecurrenceSchedule.firstRun(_startDate),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on DataFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final T v in values)
        _Chip(
          label: labelOf(v),
          selected: v == selected,
          onTap: () => onSelected(v),
        ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandPrimary : AppColors.surface2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.brandPrimary : AppColors.gridline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
