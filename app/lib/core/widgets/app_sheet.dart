import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Opens a finance bottom sheet with the settings all of them need.
///
/// `isScrollControlled` is the one that is not optional: without it the sheet is
/// capped at half the screen and the keyboard covers the save button.
Future<void> showAppSheet(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}

/// The chrome shared by every finance form sheet: grabber, title, scrolling
/// body, error line, and a submit button that shows a spinner while saving.
///
/// Extracted after the second form repeated it — the keyboard-inset padding and
/// the `mounted`-safe submit button are both easy to get subtly wrong, and
/// getting them wrong in only one of three sheets is the kind of inconsistency
/// nobody notices until it is annoying.
class AppSheetBody extends StatelessWidget {
  const AppSheetBody({
    required this.formKey,
    required this.title,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    required this.saving,
    this.subtitle,
    this.error,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String submitLabel;
  final VoidCallback onSubmit;
  final bool saving;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `viewInsets.bottom` is the keyboard's height; padding by it lifts the
      // sheet clear instead of letting the keyboard sit on top of it.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _SheetGrabber(),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ...children,
                if (error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: AppColors.statusCritical,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: saving ? null : onSubmit,
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(submitLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The handle at the top — the affordance that says this panel can be dragged
/// away.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.gridline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
