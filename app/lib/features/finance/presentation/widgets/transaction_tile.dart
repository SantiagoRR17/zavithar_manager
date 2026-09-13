import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/finance_accounts.dart';
import '../../domain/finance_categories.dart';
import '../../domain/finance_transaction.dart';

/// One row in the transaction list.
///
/// Note what carries the income/expense distinction here: an arrow icon, a `+`
/// or `−` sign, **and** colour. The project rule is that a status colour is
/// never the only signal (`CLAUDE.md` → Brand & UI tokens) — so this row still
/// reads correctly in greyscale, and to someone who cannot separate the green
/// from the white.
class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.transaction, this.onTap, super.key});

  final FinanceTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.type.isIncome;
    // The same two colours as the arrow avatar, so the icon and the number on
    // one row agree. Expense uses the *brand* red rather than
    // `statusCritical`: an ordinary expense is not a critical state, and if
    // every row is painted the alarm colour then the alarm colour stops meaning
    // anything when something genuinely is wrong.
    final Color amountColor = isIncome
        ? AppColors.statusGood
        : AppColors.brandPrimaryLight;

    final String? description = transaction.description?.trim();
    final bool hasDescription = description != null && description.isNotEmpty;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _TypeAvatar(isIncome: isIncome),
      title: Text(
        hasDescription
            ? description
            : FinanceCategories.label(transaction.category),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          // The category is only repeated in the subtitle when the title is
          // showing a description instead — otherwise the row would say
          // "Groceries / Groceries · Cash".
          <String>[
            if (hasDescription) FinanceCategories.label(transaction.category),
            FinanceAccounts.label(transaction.account),
            AppDates.relativeDay(transaction.date),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
      trailing: Text(
        Money.formatSigned(transaction.amount, isIncome: isIncome),
        style: TextStyle(
          color: amountColor,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          // Tabular figures so a column of amounts lines up digit-for-digit
          // instead of drifting with the width of each numeral.
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The circular income/expense indicator on the left of a row.
class _TypeAvatar extends StatelessWidget {
  const _TypeAvatar({required this.isIncome});

  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final Color color = isIncome
        ? AppColors.statusGood
        : AppColors.brandPrimaryLight;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // A tint of the signal colour rather than the colour itself: a solid
        // 40dp disc of red on every expense row would dominate the screen and
        // compete with the brand accent on the buttons.
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isIncome ? Icons.south_west : Icons.north_east,
        size: 20,
        color: color,
      ),
      // Arrows, not a plus/minus glyph: "in" and "out" is the mental model, and
      // the direction survives being seen at a glance.
    );
  }
}
