import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The empty state shared by all three finance tabs.
///
/// A bare spinner that resolves into nothing reads as a broken screen. On a
/// brand-new account this is the very first thing every tab displays, so it
/// gets to be an invitation rather than an absence.
class FinanceEmptyState extends StatelessWidget {
  const FinanceEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The error state shared by all three finance tabs.
///
/// In practice this is almost always a security rule refusing the read, or
/// Firestore being unreachable on a cold start with an empty cache. The raw
/// error is shown rather than hidden: this is a single-user app whose only user
/// is also its developer, and a generic "something went wrong" would cost more
/// than the polish is worth.
class FinanceErrorState extends StatelessWidget {
  const FinanceErrorState({
    required this.title,
    required this.error,
    super.key,
  });

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              size: 40,
              color: AppColors.statusCritical,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// The red panel revealed by swiping a row or card to the left.
class DeleteBackground extends StatelessWidget {
  const DeleteBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.brandPrimaryDark,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Icon(Icons.delete_outline, color: AppColors.textPrimary),
    );
  }
}
