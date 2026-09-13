import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../application/transaction_providers.dart';
import '../data/liabilities_repository.dart';
import '../data/transactions_repository.dart' show FinanceFailure;
import '../domain/liability.dart';
import 'widgets/amount_form_field.dart';
import 'widgets/sheet_scaffold.dart';

/// Create or edit a liability. Pass [initial] to edit.
Future<void> showLiabilityFormSheet(
  BuildContext context, {
  Liability? initial,
}) {
  return showFinanceSheet(
    context,
    builder: (BuildContext context) => LiabilityFormSheet(initial: initial),
  );
}

class LiabilityFormSheet extends ConsumerStatefulWidget {
  const LiabilityFormSheet({this.initial, super.key});

  final Liability? initial;

  @override
  ConsumerState<LiabilityFormSheet> createState() => _LiabilityFormSheetState();
}

class _LiabilityFormSheetState extends ConsumerState<LiabilityFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _originalController;
  late final TextEditingController _remainingController;
  late final TextEditingController _interestController;
  late final TextEditingController _minimumController;

  late String _type;
  DateTime? _dueDate;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final Liability? initial = widget.initial;

    _nameController = TextEditingController(text: initial?.name ?? '');
    _originalController = TextEditingController(
      text: initial == null ? '' : Money.grouped(initial.originalAmount),
    );
    _remainingController = TextEditingController(
      text: initial == null ? '' : Money.grouped(initial.remainingAmount),
    );
    _interestController = TextEditingController(
      text: initial?.interestRate?.toString() ?? '',
    );
    _minimumController = TextEditingController(
      text: initial?.minimumPayment == null
          ? ''
          : Money.grouped(initial!.minimumPayment!),
    );
    // A stored type this build does not offer would throw when handed to the
    // dropdown — see FinanceAccounts.isKnown for the same guard.
    _type = LiabilityTypes.isKnown(initial?.type)
        ? initial!.type
        : LiabilityTypes.fallback;
    _dueDate = initial?.dueDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _originalController.dispose();
    _remainingController.dispose();
    _interestController.dispose();
    _minimumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FinanceSheetBody(
      formKey: _formKey,
      title: _isEditing ? 'Edit liability' : 'New liability',
      error: _error,
      saving: _saving,
      submitLabel: _isEditing ? 'Save changes' : 'Add liability',
      onSubmit: _save,
      children: <Widget>[
        TextFormField(
          controller: _nameController,
          autofocus: !_isEditing,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Car loan',
          ),
          validator: (String? value) =>
              (value == null || value.trim().isEmpty) ? 'Give it a name.' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: LiabilityTypes.all
              .map(
                (String type) => DropdownMenuItem<String>(
                  value: type,
                  child: Text(LiabilityTypes.label(type)),
                ),
              )
              .toList(),
          onChanged: (String? value) {
            if (value != null) setState(() => _type = value);
          },
        ),
        const SizedBox(height: 12),
        AmountFormField(
          controller: _originalController,
          label: 'Original amount',
          helperText: 'What was borrowed.',
        ),
        const SizedBox(height: 12),
        AmountFormField(
          controller: _remainingController,
          label: 'Still owed',
          large: true,
          // Deliberately not validated against the original amount: interest
          // and late fees make a debt genuinely exceed what was borrowed.
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _interestController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Interest rate (optional)',
            suffixText: '% a year',
          ),
          validator: (String? value) {
            final String text = (value ?? '').trim();
            if (text.isEmpty) return null;
            final num? rate = num.tryParse(text);
            // The same 0–100 range the security rules enforce.
            if (rate == null) return 'Enter a number, or leave it empty.';
            if (rate < 0 || rate > 100) return 'Must be between 0 and 100.';
            return null;
          },
        ),
        const SizedBox(height: 12),
        AmountFormField(
          controller: _minimumController,
          label: 'Minimum payment (optional)',
          optional: true,
        ),
        const SizedBox(height: 12),
        OptionalDateField(
          label: 'Next payment due (optional)',
          value: _dueDate,
          onChanged: (DateTime? value) => setState(() => _dueDate = value),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final LiabilitiesRepository? repository = ref.read(
      liabilitiesRepositoryProvider,
    );
    if (repository == null) {
      setState(() => _error = 'You are signed out.');
      return;
    }

    final num original = Money.tryParse(_originalController.text)!;
    final num remaining = Money.tryParse(_remainingController.text)!;
    final num? interest = num.tryParse(_interestController.text.trim());
    final num? minimum = Money.tryParse(_minimumController.text);

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await repository.update(
          widget.initial!.copyWith(
            name: _nameController.text,
            type: _type,
            originalAmount: original,
            remainingAmount: remaining,
            interestRate: interest,
            minimumPayment: minimum,
            dueDate: _dueDate,
            // Each optional field needs its own clear flag, or emptying the
            // box would leave the old value in the document untouched.
            clearInterestRate: interest == null,
            clearMinimumPayment: minimum == null,
            clearDueDate: _dueDate == null,
          ),
        );
      } else {
        await repository.add(
          Liability(
            id: '', // Assigned by Firestore.
            name: _nameController.text,
            type: _type,
            originalAmount: original,
            remainingAmount: remaining,
            interestRate: interest,
            minimumPayment: minimum,
            dueDate: _dueDate,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on FinanceFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }
}

/// The quick "I paid something" sheet — one number, one tap.
///
/// Separate from the edit form for the same reason contributing to a savings
/// goal is: this adjusts the balance atomically via `FieldValue.increment`,
/// whereas editing overwrites it. Doing the subtraction by hand in the editor
/// would lose a concurrent payment made on another device.
Future<void> showPaymentSheet(BuildContext context, Liability liability) {
  return showFinanceSheet(
    context,
    builder: (BuildContext context) => _PaymentSheet(liability: liability),
  );
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.liability});

  final Liability liability;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-filled with the minimum payment when there is one: it is the amount
    // most often paid, and having it already typed is the difference between
    // logging a payment and meaning to.
    final num? minimum = widget.liability.minimumPayment;
    _amountController = TextEditingController(
      text: minimum == null ? '' : Money.grouped(minimum),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Liability liability = widget.liability;

    return FinanceSheetBody(
      formKey: _formKey,
      title: 'Payment towards ${liability.name}',
      subtitle: '${Money.format(liability.remainingAmount)} still owed',
      error: _error,
      saving: _saving,
      submitLabel: 'Record payment',
      onSubmit: _save,
      children: <Widget>[
        AmountFormField(
          controller: _amountController,
          label: 'Amount paid',
          autofocus: true,
          large: true,
          validator: (num amount) {
            if (amount > liability.remainingAmount) {
              return 'That is more than the '
                  '${Money.format(liability.remainingAmount)} still owed.';
            }
            return null;
          },
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final LiabilitiesRepository? repository = ref.read(
      liabilitiesRepositoryProvider,
    );
    if (repository == null) return;

    final num amount = Money.tryParse(_amountController.text)!;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await repository.recordPayment(widget.liability.id, amount);
      if (mounted) Navigator.of(context).pop();
    } on FinanceFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }
}
