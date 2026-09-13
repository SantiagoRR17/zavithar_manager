import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import '../application/budget_providers.dart';
import '../data/budgets_repository.dart';
import '../domain/budget.dart';
import '../domain/finance_categories.dart';
import 'widgets/amount_form_field.dart';

/// Set or change a monthly limit. Pass [initial] to edit.
Future<void> showBudgetFormSheet(BuildContext context, {Budget? initial}) {
  return showAppSheet(
    context,
    builder: (BuildContext context) => BudgetFormSheet(initial: initial),
  );
}

class BudgetFormSheet extends ConsumerStatefulWidget {
  const BudgetFormSheet({this.initial, super.key});

  final Budget? initial;

  @override
  ConsumerState<BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<BudgetFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _limitController;
  late String _category;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _limitController = TextEditingController(
      text: widget.initial == null
          ? ''
          : Money.grouped(widget.initial!.monthlyLimit),
    );
    _category = widget.initial?.category ?? '';
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Categories that already have a budget are not offered again — the
    // document ID is the category, so choosing one twice would silently
    // overwrite the first rather than adding a second.
    final Set<String> taken =
        ref
            .watch(budgetsStreamProvider)
            .asData
            ?.value
            .map((Budget b) => b.category)
            .toSet() ??
        <String>{};

    final List<String> available = <String>[
      for (final String c in FinanceCategories.expense)
        if (!taken.contains(c) || c == widget.initial?.category) c,
    ];

    // Pick a sensible default once the list is known, rather than leaving the
    // form in a state where Save is the first thing that tells you something
    // is missing.
    if (_category.isEmpty && available.isNotEmpty) {
      _category = available.first;
    }

    return AppSheetBody(
      formKey: _formKey,
      title: _isEditing ? 'Edit budget' : 'New budget',
      subtitle: 'A monthly cap on spending in one category. Income is ignored.',
      error: _error,
      saving: _saving,
      submitLabel: _isEditing ? 'Save changes' : 'Set budget',
      onSubmit: _save,
      children: <Widget>[
        if (available.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Every expense category already has a budget. Edit one of those '
              'instead.',
              style: TextStyle(color: AppColors.statusWarning, fontSize: 13),
            ),
          )
        else ...<Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Category',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String c in available)
                _CategoryChip(
                  label: FinanceCategories.label(c),
                  // Editing pins the category: changing it would mean deleting
                  // one budget and creating another, which is not what "edit"
                  // means to anyone.
                  selected: _category == c,
                  enabled: !_isEditing,
                  onTap: () => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 20),
          AmountFormField(
            controller: _limitController,
            label: 'Monthly limit',
            large: true,
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_category.isEmpty) {
      setState(() => _error = 'Choose a category.');
      return;
    }

    final BudgetsRepository? repository = ref.read(budgetsRepositoryProvider);
    if (repository == null) {
      setState(() => _error = 'You are signed out.');
      return;
    }

    final num limit = Money.tryParse(_limitController.text)!;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await repository.save(Budget(category: _category, monthlyLimit: limit));
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled || selected ? 1 : 0.35,
      child: Material(
        color: selected ? AppColors.brandPrimary : AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
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
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
