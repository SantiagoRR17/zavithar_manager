import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/liability.dart';

/// One debt: name, how much is left, how much of it has been repaid, and a
/// button to record a payment.
class LiabilityCard extends StatelessWidget {
  const LiabilityCard({
    required this.liability,
    required this.onPay,
    this.onTap,
    super.key,
  });

  final Liability liability;
  final VoidCallback onPay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool paidOff = liability.isPaidOff;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          liability.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          LiabilityTypes.label(liability.type),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (paidOff)
                    const Padding(
                      padding: EdgeInsets.only(right: 8, top: 4),
                      child: Icon(
                        Icons.check_circle,
                        size: 18,
                        color: AppColors.statusGood,
                      ),
                    )
                  else
                    IconButton(
                      onPressed: onPay,
                      icon: const Icon(Icons.payments_outlined),
                      tooltip: 'Record a payment',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                paidOff ? 'Paid off' : Money.format(liability.remainingAmount),
                style: TextStyle(
                  color: paidOff
                      ? AppColors.statusGood
                      : AppColors.brandPrimaryLight,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              if (!paidOff) ...<Widget>[
                const SizedBox(height: 2),
                const Text(
                  'still owed',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  // Counts the debt *down*: a nearly-repaid liability shows a
                  // nearly-full bar. A bar that fills as you sink further into
                  // debt would be defensible and miserable.
                  value: liability.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.gridline,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.statusGood,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '${Money.format(liability.amountPaid)} of '
                    '${Money.format(liability.originalAmount)} repaid',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (liability.interestRate != null)
                    Text(
                      '${liability.interestRate}% a year',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              if (liability.dueDate != null) ...<Widget>[
                const SizedBox(height: 6),
                _DueDateLine(dueDate: liability.dueDate!, paidOff: paidOff),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The next-payment line, which warns once the date has passed.
class _DueDateLine extends StatelessWidget {
  const _DueDateLine({required this.dueDate, required this.paidOff});

  final DateTime dueDate;
  final bool paidOff;

  @override
  Widget build(BuildContext context) {
    final bool overdue = !paidOff && dueDate.isBefore(DateTime.now());

    return Row(
      children: <Widget>[
        Icon(
          overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
          size: 14,
          // The icon changes with the state, so the warning survives greyscale.
          color: overdue ? AppColors.statusSerious : AppColors.muted,
        ),
        const SizedBox(width: 6),
        Text(
          overdue
              ? 'Payment overdue — was due ${AppDates.short(dueDate)}'
              : 'Next payment ${AppDates.relativeDay(dueDate)}',
          style: TextStyle(
            color: overdue ? AppColors.statusSerious : AppColors.muted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
