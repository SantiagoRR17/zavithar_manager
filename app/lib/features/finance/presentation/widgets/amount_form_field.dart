import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/format/money.dart';

/// A money input: `$` prefix, numeric keyboard, thousands grouped as you type.
///
/// Extracted once all three finance forms needed it. The behaviour that must
/// not drift between them is the pairing of [ThousandsSeparatorInputFormatter]
/// with [Money.tryParse] — the formatter decides what the field *shows* and the
/// parser decides what gets *stored*, so a form that used one without the other
/// would save a different number from the one on screen.
class AmountFormField extends StatelessWidget {
  const AmountFormField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.optional = false,
    this.large = false,
    this.helperText,
    this.validator,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;

  /// When true an empty field is valid and parses to null. Used for
  /// `minimumPayment`, which nobody should be forced to invent.
  final bool optional;

  /// Bigger type, for the one field that is the point of the form.
  final bool large;

  final String? helperText;

  /// Extra validation on top of "is a positive number", e.g. a payment that
  /// cannot exceed the balance.
  final String? Function(num amount)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: const <TextInputFormatter>[
        ThousandsSeparatorInputFormatter(),
      ],
      style: TextStyle(
        fontSize: large ? 22 : 16,
        fontWeight: large ? FontWeight.w600 : FontWeight.w400,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixText: r'$ ',
        hintText: '0',
        helperText: helperText,
      ),
      validator: (String? value) {
        final num? amount = Money.tryParse(value ?? '');
        if (amount == null) return optional ? null : 'Enter an amount.';
        if (!optional && amount <= 0) {
          return 'Amount must be greater than zero.';
        }
        return validator?.call(amount);
      },
    );
  }
}

/// A tappable date row that can also be empty.
///
/// Every optional date in this feature — a savings deadline, a liability's due
/// date — needs the same three states: unset, set, and *clearable back to
/// unset*. That last one is the reason this widget exists rather than a plain
/// `showDatePicker` call at each site: the clear button is easy to leave out,
/// and without it a date set once can never be removed.
class OptionalDateField extends StatelessWidget {
  const OptionalDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final String label;
  final DateTime? value;

  /// Called with null when the date is cleared.
  final ValueChanged<DateTime?> onChanged;

  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final DateTime? current = value;

    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: current == null
              ? const Icon(Icons.calendar_today, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear date',
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          current == null ? 'Not set' : AppDates.short(current),
          style: TextStyle(
            color: current == null
                ? Theme.of(context).hintColor
                : Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: firstDate ?? DateTime(now.year - 5),
      lastDate: lastDate ?? DateTime(now.year + 20),
    );
    if (picked != null) onChanged(picked);
  }
}
