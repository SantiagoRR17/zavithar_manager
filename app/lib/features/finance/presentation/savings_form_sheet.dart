import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/optional_date_field.dart';
import '../application/transaction_providers.dart';
import '../data/savings_repository.dart';
import '../domain/savings_goal.dart';
import 'widgets/amount_form_field.dart';

/// Create or edit a savings goal. Pass [initial] to edit.
Future<void> showSavingsFormSheet(
  BuildContext context, {
  SavingsGoal? initial,
}) {
  return showAppSheet(
    context,
    builder: (BuildContext context) => SavingsFormSheet(initial: initial),
  );
}

class SavingsFormSheet extends ConsumerStatefulWidget {
  const SavingsFormSheet({this.initial, super.key});

  final SavingsGoal? initial;

  @override
  ConsumerState<SavingsFormSheet> createState() => _SavingsFormSheetState();
}

class _SavingsFormSheetState extends ConsumerState<SavingsFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  late final TextEditingController _currentController;

  DateTime? _deadline;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final SavingsGoal? initial = widget.initial;

    _nameController = TextEditingController(text: initial?.name ?? '');
    _targetController = TextEditingController(
      text: initial == null ? '' : Money.grouped(initial.targetAmount),
    );
    _currentController = TextEditingController(
      text: initial == null ? '' : Money.grouped(initial.currentAmount),
    );
    _deadline = initial?.deadline;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _currentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      formKey: _formKey,
      title: _isEditing ? 'Edit goal' : 'New savings goal',
      error: _error,
      saving: _saving,
      submitLabel: _isEditing ? 'Save changes' : 'Create goal',
      onSubmit: _save,
      children: <Widget>[
        TextFormField(
          controller: _nameController,
          autofocus: !_isEditing,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 80, // The limit in the data model and in the rules.
          decoration: const InputDecoration(
            labelText: 'What are you saving for?',
            hintText: 'New laptop',
          ),
          validator: (String? value) => (value == null || value.trim().isEmpty)
              ? 'Give it a name.'
              : null,
        ),
        AmountFormField(
          controller: _targetController,
          label: 'Target amount',
          large: true,
        ),
        const SizedBox(height: 12),
        AmountFormField(
          controller: _currentController,
          label: 'Saved so far',
          optional: true,
          helperText: 'Leave empty to start from zero.',
        ),
        const SizedBox(height: 12),
        OptionalDateField(
          label: 'Deadline (optional)',
          value: _deadline,
          // A savings deadline is a future thing by nature, but backdating is
          // allowed rather than blocked: a goal whose date has passed and is
          // still unmet is exactly the case worth being able to see.
          onChanged: (DateTime? value) => setState(() => _deadline = value),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final SavingsRepository? repository = ref.read(savingsRepositoryProvider);
    if (repository == null) {
      setState(() => _error = 'You are signed out.');
      return;
    }

    final num target = Money.tryParse(_targetController.text)!;
    final num current = Money.tryParse(_currentController.text) ?? 0;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await repository.update(
          widget.initial!.copyWith(
            name: _nameController.text,
            targetAmount: target,
            currentAmount: current,
            deadline: _deadline,
            // Without this flag, `copyWith`'s null-means-unchanged rule would
            // make a deadline permanent once set.
            clearDeadline: _deadline == null,
          ),
        );
      } else {
        await repository.add(
          SavingsGoal(
            id: '', // Assigned by Firestore.
            name: _nameController.text,
            targetAmount: target,
            currentAmount: current,
            deadline: _deadline,
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

/// The small sheet for adding to — or taking out of — a goal.
///
/// Separate from the edit form on purpose. Contributing is the frequent action
/// and it must be one number and one tap; opening the full editor to do
/// arithmetic on the "saved so far" field by hand would be both slower and
/// wrong, because it would overwrite the balance rather than adjust it (see
/// `SavingsRepository.contribute` on why that distinction matters).
Future<void> showContributeSheet(BuildContext context, SavingsGoal goal) {
  return showAppSheet(
    context,
    builder: (BuildContext context) => _ContributeSheet(goal: goal),
  );
}

class _ContributeSheet extends ConsumerStatefulWidget {
  const _ContributeSheet({required this.goal});

  final SavingsGoal goal;

  @override
  ConsumerState<_ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends ConsumerState<_ContributeSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();

  bool _withdrawing = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SavingsGoal goal = widget.goal;

    return AppSheetBody(
      formKey: _formKey,
      title: goal.name,
      subtitle:
          '${Money.format(goal.currentAmount)} of '
          '${Money.format(goal.targetAmount)} saved',
      error: _error,
      saving: _saving,
      submitLabel: _withdrawing ? 'Withdraw' : 'Add to goal',
      onSubmit: _save,
      children: <Widget>[
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              label: Text('Add'),
              icon: Icon(Icons.add, size: 18),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Withdraw'),
              icon: Icon(Icons.remove, size: 18),
            ),
          ],
          selected: <bool>{_withdrawing},
          onSelectionChanged: (Set<bool> selection) =>
              setState(() => _withdrawing = selection.first),
        ),
        const SizedBox(height: 16),
        AmountFormField(
          controller: _amountController,
          label: 'Amount',
          autofocus: true,
          large: true,
          validator: (num amount) {
            if (_withdrawing && amount > goal.currentAmount) {
              return 'There is only ${Money.format(goal.currentAmount)} in '
                  'this goal.';
            }
            return null;
          },
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final SavingsRepository? repository = ref.read(savingsRepositoryProvider);
    if (repository == null) return;

    final num amount = Money.tryParse(_amountController.text)!;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await repository.contribute(
        widget.goal.id,
        _withdrawing ? -amount : amount,
      );
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

/// Shown on a goal that has reached its target.
const Color kGoalCompleteColor = AppColors.statusGood;
