import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A deliberate "nothing here yet, and here's when there will be" panel.
///
/// Why this exists: Milestone 0's finish line is an *empty* app shell — real
/// navigation, real auth, no features. Leaving the tabs blank would make a
/// working shell look broken, so each unbuilt section says which milestone
/// fills it in (`claude/development-plan.md`). These get deleted as the
/// milestones land; if one is still here, that feature genuinely isn't built.
class MilestonePlaceholder extends StatelessWidget {
  const MilestonePlaceholder({
    required this.icon,
    required this.title,
    required this.milestone,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;

  /// e.g. `'Milestone 1'` — the one that replaces this screen.
  final String milestone;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 44, color: AppColors.muted),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.gridline),
                ),
                child: Text(
                  'Coming in $milestone',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
