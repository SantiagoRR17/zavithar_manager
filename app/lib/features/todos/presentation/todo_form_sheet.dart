import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/optional_date_field.dart';
import '../application/todo_providers.dart';
import '../data/todos_repository.dart';
import '../../categories/application/category_providers.dart';
import '../../categories/domain/user_category.dart';
import '../domain/todo.dart';
import 'widgets/todo_tile.dart' show CategoryPill;

/// Create or edit a task.
///
/// Pass [initial] to edit. Pass [followUpOf] to create a task linked to an
/// existing one — the two are mutually exclusive in practice, because a
/// follow-up is created fresh.
Future<void> showTodoFormSheet(
  BuildContext context, {
  Todo? initial,
  Todo? followUpOf,
}) {
  return showAppSheet(
    context,
    builder: (BuildContext context) =>
        TodoFormSheet(initial: initial, followUpOf: followUpOf),
  );
}

class TodoFormSheet extends ConsumerStatefulWidget {
  const TodoFormSheet({this.initial, this.followUpOf, super.key});

  final Todo? initial;
  final Todo? followUpOf;

  @override
  ConsumerState<TodoFormSheet> createState() => _TodoFormSheetState();
}

class _TodoFormSheetState extends ConsumerState<TodoFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  late String _category;
  late TodoStatus _status;
  late TodoPriority _priority;
  DateTime? _deadline;
  DateTime? _reminderAt;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final Todo? initial = widget.initial;

    _titleController = TextEditingController(text: initial?.title ?? '');
    _notesController = TextEditingController(text: initial?.notes ?? '');

    // A follow-up inherits its parent's category and priority. It is almost
    // always about the same thing, and re-picking both for every follow-up is
    // friction with no decision behind it.
    _category =
        initial?.category ??
        widget.followUpOf?.category ??
        ref.read(categorySetProvider(CategoryKind.todo)).defaultKey ??
        TodoCategories.fallback;
    _status = initial?.status ?? TodoStatus.pending;
    _priority =
        initial?.priority ?? widget.followUpOf?.priority ?? TodoPriority.medium;
    _deadline = initial?.deadline;
    _reminderAt = initial?.reminderAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Todo? parent = widget.followUpOf;

    return AppSheetBody(
      formKey: _formKey,
      title: _isEditing
          ? 'Edit task'
          : (parent == null ? 'New task' : 'Follow-up task'),
      subtitle: parent == null ? null : 'Follows up on "${parent.title}"',
      error: _error,
      saving: _saving,
      submitLabel: _isEditing ? 'Save changes' : 'Create task',
      onSubmit: _save,
      children: <Widget>[
        TextFormField(
          controller: _titleController,
          autofocus: !_isEditing,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 120, // The limit in the data model and in the rules.
          decoration: const InputDecoration(
            labelText: 'What needs doing?',
            hintText: 'Renew the passport',
          ),
          validator: (String? value) => (value == null || value.trim().isEmpty)
              ? 'Give the task a title.'
              : null,
        ),
        TextFormField(
          controller: _notesController,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          minLines: 1,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 4),
        const _FieldLabel('Category'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String c
                in ref
                    .watch(categorySetProvider(CategoryKind.todo))
                    .keysIncluding(_category))
              GestureDetector(
                onTap: () => setState(() => _category = c),
                child: Opacity(
                  // The unselected categories stay legible rather than being
                  // greyed out entirely: their colour *is* their identity, and
                  // washing it out makes picking one a reading exercise.
                  opacity: _category == c ? 1 : 0.45,
                  child: CategoryPill(category: c),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Priority'),
        const SizedBox(height: 8),
        _SegmentedRow<TodoPriority>(
          values: TodoPriority.values,
          selected: _priority,
          labelOf: (TodoPriority p) => p.label,
          onSelected: (TodoPriority p) => setState(() => _priority = p),
        ),
        if (_isEditing) ...<Widget>[
          const SizedBox(height: 20),
          const _FieldLabel('Status'),
          const SizedBox(height: 8),
          _SegmentedRow<TodoStatus>(
            values: TodoStatus.values,
            selected: _status,
            labelOf: (TodoStatus s) => s.label,
            onSelected: (TodoStatus s) => setState(() => _status = s),
          ),
        ],
        const SizedBox(height: 20),
        OptionalDateField(
          label: 'Deadline (optional)',
          value: _deadline,
          onChanged: (DateTime? value) => setState(() {
            _deadline = value;
            // Choosing a deadline with no reminder yet offers one for 9am on
            // the day itself. A deadline you are not reminded about is the
            // failure mode this app exists to prevent, and the alternative —
            // silently leaving the reminder unset — looks identical on screen
            // to having set one.
            if (value != null && _reminderAt == null) {
              _reminderAt = DateTime(value.year, value.month, value.day, 9);
            }
          }),
        ),
        const SizedBox(height: 12),
        OptionalDateField(
          label: 'Remind me (optional)',
          value: _reminderAt,
          withTime: true,
          helperText: 'Scheduled on this device. Milestone 3.',
          onChanged: (DateTime? value) => setState(() => _reminderAt = value),
        ),
        if (_isEditing) ...<Widget>[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _saving ? null : _createFollowUp,
            icon: const Icon(Icons.subdirectory_arrow_right, size: 18),
            label: const Text('Add a follow-up task'),
          ),
        ],
      ],
    );
  }

  /// Closes this sheet and opens a fresh one linked to the task being edited.
  ///
  /// Closing first is deliberate: stacking a second sheet on top of the first
  /// leaves an edit form open behind it holding unsaved changes that will be
  /// thrown away without ever being mentioned.
  void _createFollowUp() {
    final Todo? parent = widget.initial;
    if (parent == null) return;
    Navigator.of(context).pop();
    showTodoFormSheet(context, followUpOf: parent);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final TodosRepository? repository = ref.read(todosRepositoryProvider);
    if (repository == null) {
      setState(() => _error = 'You are signed out.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await repository.update(
          widget.initial!.copyWith(
            title: _titleController.text,
            notes: _notesController.text,
            category: _category,
            status: _status,
            priority: _priority,
            deadline: _deadline,
            reminderAt: _reminderAt,
            // Without these flags `copyWith`'s null-means-unchanged rule would
            // make every optional field permanent once set.
            clearNotes: _notesController.text.trim().isEmpty,
            clearDeadline: _deadline == null,
            clearReminderAt: _reminderAt == null,
          ),
        );
      } else {
        await repository.add(
          Todo(
            id: '', // Assigned by Firestore.
            title: _titleController.text,
            notes: _notesController.text,
            category: _category,
            status: _status,
            priority: _priority,
            deadline: _deadline,
            reminderAt: _reminderAt,
            followUpOf: widget.followUpOf?.id,
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
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
}

/// A row of mutually exclusive options.
///
/// Hand-rolled rather than `SegmentedButton` because that widget sizes every
/// segment to the widest label and, at three labels on a narrow phone,
/// overflows rather than wrapping.
class _SegmentedRow<T> extends StatelessWidget {
  const _SegmentedRow({
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
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final T value in values)
          Material(
            color: value == selected
                ? AppColors.brandPrimary
                : AppColors.surface2,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () => onSelected(value),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: value == selected
                        ? AppColors.brandPrimary
                        : AppColors.gridline,
                  ),
                ),
                child: Text(
                  labelOf(value),
                  style: TextStyle(
                    color: value == selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: value == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
