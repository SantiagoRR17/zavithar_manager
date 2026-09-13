import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// One number on the dashboard, with its label and an icon.
///
/// The icon is not decoration. The project rule is that a colour is never the
/// only signal — so a tile whose value is coloured (a negative balance in red,
/// a positive one in green) carries an icon and a label saying the same thing,
/// and the tile still reads correctly in greyscale or to a colour-blind eye.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.caption,
    this.accent,
    this.progress,
    this.onTap,
    super.key,
  });

  /// What the number is — "Balance", "Total debt".
  final String label;

  /// The number, already formatted. Tiles never format money themselves;
  /// that belongs to `core/format/money.dart` (ADR 0009).
  final String value;

  final IconData icon;

  /// Colour for [value]. Defaults to plain white — most numbers are not a
  /// judgement and colouring them all would leave no colour meaning anything.
  final Color? valueColor;

  /// An optional second line: "3 goals", "of $2.000.000".
  final String? caption;

  /// Tints the icon and the progress bar. Defaults to the brand red.
  final Color? accent;

  /// Draws a progress bar under the value when set. 0–1, already clamped by
  /// the caller.
  final double? progress;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = accent ?? AppColors.brandPrimary;

    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: tint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // A long amount shrinks rather than wrapping or clipping. COP
              // figures run to seven digits plus separators — "$1.250.000" —
              // and on a narrow phone in a two-column grid that overflows the
              // tile. Shrinking keeps the whole number readable, which is the
              // one thing a number tile cannot compromise on.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: valueColor ?? AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (progress != null) ...<Widget>[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.gridline,
                    valueColor: AlwaysStoppedAnimation<Color>(tint),
                  ),
                ),
              ],
              if (caption != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  caption!,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
