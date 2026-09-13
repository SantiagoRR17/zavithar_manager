import 'package:flutter/material.dart';

import '../format/money.dart';

/// A tappable field for a date that may be absent, with a clear button.
///
/// Moved out of `amount_form_field.dart` when todos needed it: nothing about
/// picking a date is specific to money, and a `todos -> finance` import to
/// reach it would have been a dependency that means nothing.
///
/// Set [withTime] for values where the hour matters. A reminder is the case
/// that forced it — "remind me on the 14th" with no time silently means
/// midnight, which is the one hour of the day a reminder is guaranteed to be
/// useless.
class OptionalDateField extends StatelessWidget {
  const OptionalDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.withTime = false,
    this.helperText,
    super.key,
  });

  final String label;
  final DateTime? value;

  /// Called with null when the value is cleared.
  final ValueChanged<DateTime?> onChanged;

  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool withTime;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final DateTime? current = value;

    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          suffixIcon: current == null
              ? Icon(withTime ? Icons.schedule : Icons.calendar_today, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear',
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          current == null
              ? 'Not set'
              : (withTime
                    ? AppDates.shortWithTime(current)
                    : AppDates.short(current)),
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
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: firstDate ?? DateTime(now.year - 5),
      lastDate: lastDate ?? DateTime(now.year + 20),
    );
    if (day == null) return;

    if (!withTime) {
      onChanged(day);
      return;
    }

    // `context` crosses an await, so it has to be re-checked before use —
    // the sheet can be dismissed while the picker is open.
    if (!context.mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      // Defaults to 9am rather than the current time: a reminder set for
      // "tomorrow" almost never means "tomorrow at 15:47".
      initialTime: value == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(value!),
    );

    // Cancelling the *time* picker keeps the date at the default hour rather
    // than throwing the whole choice away — backing out of the second step
    // should not undo the first.
    final TimeOfDay resolved = time ?? const TimeOfDay(hour: 9, minute: 0);
    onChanged(
      DateTime(day.year, day.month, day.day, resolved.hour, resolved.minute),
    );
  }
}
