import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import '../application/statement_providers.dart';
import '../application/transaction_providers.dart';
import '../data/transactions_repository.dart';
import '../domain/finance_accounts.dart';
import '../../categories/application/category_providers.dart';
import '../../categories/domain/category_set.dart';
import '../domain/finance_categories.dart';
import '../domain/finance_transaction.dart';
import 'widgets/amount_form_field.dart';

/// Opens the create/edit sheet. Pass [initial] to edit, omit it to create.
///
/// A bottom sheet rather than a pushed route: NFR-7 asks for logging a
/// transaction in under ten seconds one-handed, and a sheet keeps the keyboard,
/// the fields and the save button inside thumb reach without a navigation
/// transition in the way.
Future<void> showTransactionFormSheet(
  BuildContext context, {
  FinanceTransaction? initial,
}) {
  return showAppSheet(
    context,
    builder: (BuildContext context) => TransactionFormSheet(initial: initial),
  );
}

/// The transaction form.
///
/// Client-side validation here is for *immediate feedback only*. The real
/// enforcement is in `firestore.rules`, which sees every write regardless of
/// which client made it — both layers, per `CLAUDE.md` → Engineering
/// conventions. Anything this form refuses, the rules must refuse too.
class TransactionFormSheet extends ConsumerStatefulWidget {
  const TransactionFormSheet({this.initial, super.key});

  final FinanceTransaction? initial;

  @override
  ConsumerState<TransactionFormSheet> createState() =>
      _TransactionFormSheetState();
}

class _TransactionFormSheetState extends ConsumerState<TransactionFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;

  late TransactionType _type;
  late String _category;
  late String _account;
  late DateTime _date;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final FinanceTransaction? initial = widget.initial;

    _type = initial?.type ?? TransactionType.expense;
    // An existing transaction keeps its category even if it has since been
    // removed from the list — `_categoryField` keeps the value on offer, so
    // editing the amount cannot silently recategorise the record.
    _category = initial?.category ?? _defaultCategoryFor(_type);
    // A document can hold an account this build does not offer — written by a
    // later version, or typed into the Firestore console. Selecting it in the
    // dropdown would throw, so an unknown value falls back to the default.
    _account = FinanceAccounts.isKnown(initial?.account)
        ? initial!.account!
        : FinanceAccounts.fallback;
    _date = initial?.date ?? DateTime.now();

    _amountController = TextEditingController(
      // `grouped`, not `format`: the field draws its own `$` as a prefix, so
      // the symbol here too would render `$ $12.500`.
      text: initial == null ? '' : Money.grouped(initial.amount),
    );
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
  }

  @override
  void dispose() {
    // Controllers hold native resources and a listener list; not disposing them
    // leaks both every time the sheet closes.
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      formKey: _formKey,
      title: _isEditing ? 'Edit transaction' : 'New transaction',
      error: _error,
      saving: _saving,
      submitLabel: _isEditing ? 'Save changes' : 'Add transaction',
      onSubmit: _save,
      children: <Widget>[
        _typeSelector(),
        const SizedBox(height: 16),
        _amountField(),
        const SizedBox(height: 12),
        _categoryField(),
        const SizedBox(height: 12),
        _accountField(),
        const SizedBox(height: 12),
        _dateField(),
        const SizedBox(height: 12),
        _descriptionField(),
      ],
    );
  }

  Widget _typeSelector() {
    return SegmentedButton<TransactionType>(
      segments: const <ButtonSegment<TransactionType>>[
        ButtonSegment<TransactionType>(
          value: TransactionType.expense,
          label: Text('Expense'),
          icon: Icon(Icons.north_east, size: 18),
        ),
        ButtonSegment<TransactionType>(
          value: TransactionType.income,
          label: Text('Income'),
          icon: Icon(Icons.south_west, size: 18),
        ),
      ],
      selected: <TransactionType>{_type},
      onSelectionChanged: (Set<TransactionType> selection) {
        setState(() {
          _type = selection.first;
          // `groceries` is not a kind of income. Flipping the type resets the
          // category rather than leaving a nonsense pairing that the user has
          // to notice and fix themselves.
          if (!_setFor(_type).contains(_category)) {
            _category = _defaultCategoryFor(_type);
          }
        });
      },
    );
  }

  Widget _amountField() {
    return AmountFormField(
      controller: _amountController,
      label: 'Amount',
      // Focused on open: the amount is the one field every transaction needs,
      // so the keyboard is already up and typing can start immediately.
      autofocus: !_isEditing,
      large: true,
    );
  }

  /// The user's list for a transaction type, read without subscribing.
  ///
  /// `read` rather than `watch` in the callbacks; the build method watches.
  CategorySet _setFor(TransactionType type) =>
      ref.read(categorySetProvider(type.categoryKind));

  /// Where a fresh form starts. Falls back to the built-in escape hatch when
  /// the user has deleted every category, so a transaction can still be
  /// recorded rather than the form opening with nothing selectable.
  String _defaultCategoryFor(TransactionType type) =>
      _setFor(type).defaultKey ?? FinanceCategories.fallback;

  Widget _categoryField() {
    final CategorySet set = ref.watch(categorySetProvider(_type.categoryKind));

    return DropdownButtonFormField<String>(
      initialValue: _category,
      decoration: const InputDecoration(labelText: 'Category'),
      dropdownColor: AppColors.surface1,
      items: set
          .keysIncluding(_category)
          .map(
            (String category) => DropdownMenuItem<String>(
              value: category,
              child: Text(set.label(category)),
            ),
          )
          .toList(),
      onChanged: (String? value) {
        if (value != null) setState(() => _category = value);
      },
    );
  }

  Widget _accountField() {
    return DropdownButtonFormField<String>(
      initialValue: _account,
      decoration: const InputDecoration(labelText: 'Account'),
      dropdownColor: AppColors.surface1,
      items: FinanceAccounts.all
          .map(
            (String account) => DropdownMenuItem<String>(
              value: account,
              child: Text(FinanceAccounts.label(account)),
            ),
          )
          .toList(),
      onChanged: (String? value) {
        if (value != null) setState(() => _account = value);
      },
    );
  }

  Widget _dateField() {
    final DateTime? openFrom = ref.watch(openPeriodStartProvider);

    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date',
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
          // Explains the greyed-out dates in the picker. Without it the floor
          // looks like a bug rather than a closed month.
          helperText: openFrom == null
              ? null
              : 'Months before ${AppDates.short(openFrom)} are closed',
        ),
        child: Text(
          AppDates.short(_date),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _descriptionField() {
    return TextFormField(
      controller: _descriptionController,
      // 200 is the limit in `claude/data-model.md`, and the same number the
      // security rules enforce. If one moves, both move.
      maxLength: 200,
      maxLines: 2,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'Description (optional)',
        hintText: 'What was it for?',
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();

    // **Backdating stops at the last closed month** (ADR 0012). A transaction
    // dated inside a closed period would sit before the streamed window and
    // outside the statement meant to account for it, and would disappear from
    // the balance without any error at all. The security rules reject such a
    // write; this is the half that means the date is never offered in the
    // first place, so the rule never has to fire.
    final DateTime? openFrom = ref.watch(openPeriodStartProvider);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(openFrom ?? _date) ? openFrom! : _date,
      // Otherwise a transaction can be backdated freely, but not logged in the
      // future — money that has not moved yet is a budget, which is Milestone 4.
      firstDate: openFrom ?? DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      // The picker returns midnight. Keeping the current time-of-day makes two
      // transactions logged on the same day sort in the order they happened.
      setState(() {
        _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          now.hour,
          now.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final TransactionsRepository? repository = ref.read(
      transactionsRepositoryProvider,
    );
    if (repository == null) {
      setState(() => _error = 'You are signed out.');
      return;
    }

    final num amount = Money.tryParse(_amountController.text)!;
    final String description = _descriptionController.text.trim();

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
            account: _account,
            date: _date,
            // `copyWith`'s null-means-unchanged convention cannot express
            // "clear this", so an emptied box is passed through as the empty
            // string; the repository turns that into a `FieldValue.delete()`.
            description: description,
          ),
        );
      } else {
        await repository.add(
          FinanceTransaction(
            id: '', // Assigned by Firestore in `add`.
            amount: amount,
            type: _type,
            category: _category,
            account: _account,
            date: _date,
            description: description.isEmpty ? null : description,
          ),
        );
      }

      // `mounted` because an await happened: the sheet can be dismissed while
      // the write is in flight, and using a dead BuildContext throws.
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
