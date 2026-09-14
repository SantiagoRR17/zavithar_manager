import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../finance/domain/finance_categories.dart';
import '../../domain/spending_insights.dart';

/// The one colour every data mark in these charts is filled with.
///
/// **Not `brandPrimary`.** The palette validator measured it at 2.52:1 against
/// `surface1`, below the 3:1 a solid fill needs to be distinguishable at all —
/// a fact invisible by eye on a dark screen, where a dark red on near-black
/// simply looks "moody". `brandPrimaryLight` measures 5.3:1.
///
/// It is also already the app's expense colour, which makes it the right
/// semantic choice for charts about spending rather than merely the legible
/// one.
const Color _markFill = AppColors.brandPrimaryLight;

/// Spending by category for the current month.
///
/// **One colour for every bar**, not a hue per category and not a ramp by size.
/// Two reasons, and both are rules rather than taste:
///
/// - The four category colours in `app_colors.dart` belong to the *todo*
///   categories and are never reassigned (`CLAUDE.md` → Brand & UI tokens).
///   Finance categories are a different set; borrowing those hues would make
///   "orange means work" false.
/// - Colouring nominal bars by magnitude is an anti-pattern: it double-encodes
///   length as hue, spending the only free channel on information the bar
///   already shows. Identity here is carried by the label beside each bar.
class CategorySpendChart extends StatelessWidget {
  const CategorySpendChart({required this.rows, super.key});

  final List<CategorySpend> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final num peak = rows.first.amount;
    if (peak <= 0) return const SizedBox.shrink();

    return _ChartFrame(
      title: 'Where it went',
      subtitle: 'This month, by category',
      child: Column(
        children: <Widget>[
          for (final CategorySpend row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CategoryBar(row: row, peak: peak),
            ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.row, required this.peak});

  final CategorySpend row;
  final num peak;

  @override
  Widget build(BuildContext context) {
    final double fraction = (row.amount / peak).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                FinanceCategories.label(row.category),
                style: const TextStyle(
                  // Text wears text tokens, never the mark's colour. The bar
                  // beside it carries the identity.
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              Money.format(row.amount),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: <Widget>[
                // A recessive track rather than gridlines: it shows the full
                // width each bar is measured against without adding rules
                // across the chart.
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.gridline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
                  width: constraints.maxWidth * fraction,
                  decoration: const BoxDecoration(
                    color: _markFill,
                    // Rounded only at the data end; square where it is
                    // anchored, so the baseline stays a straight line down the
                    // chart and lengths compare honestly.
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Net per month, above and below a zero line.
///
/// **Direction is the encoding.** Colour repeats it rather than carrying it,
/// which matters here more than usual: the palette validator puts this app's
/// green and red at ΔE 5.7 under deuteranopia — effectively the same colour to
/// a red-green colourblind reader. Above or below the line is unambiguous to
/// everyone, and the sign on the value says it a third time.
class MonthlyNetChart extends StatelessWidget {
  const MonthlyNetChart({required this.series, super.key});

  final List<MonthlyTotals> series;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) return const SizedBox.shrink();

    final num peak = SpendingInsights.peakNet(series);
    if (peak <= 0) return const SizedBox.shrink();

    // **The axis spans the data, not a symmetry the data does not have.**
    // Splitting the height evenly above and below zero reserves half the chart
    // for negative months that may not exist, and the marks lose half their
    // height to blank space. The two halves are sized by the actual extents
    // instead, so a run of profitable months uses the whole frame and a single
    // bad one opens the space it needs.
    num up = 0;
    num down = 0;
    for (final MonthlyTotals m in series) {
      if (m.net > up) up = m.net;
      if (-m.net > down) down = -m.net;
    }

    return _ChartFrame(
      title: 'Month by month',
      subtitle: 'Income minus expense',
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final MonthlyTotals m in series)
              Expanded(
                child: Padding(
                  // A 2px gap of surface between adjacent marks, so two bars
                  // never read as one.
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _NetColumn(month: m, peak: peak, up: up, down: down),
                ),
              ),
            // `Expanded` alone gives each bar an equal share of the width,
            // which with only two months is half the screen each — and a
            // mark that wide is a saturated block, not a bar. Capping the
            // width keeps the marks thin however few months there are.
          ],
        ),
      ),
    );
  }
}

class _NetColumn extends StatelessWidget {
  const _NetColumn({
    required this.month,
    required this.peak,
    required this.up,
    required this.down,
  });

  final MonthlyTotals month;

  /// The largest magnitude anywhere in the series, in either direction.
  final num peak;

  /// The largest gain and the largest loss in the series. The two halves of
  /// the axis are sized in proportion to these, and each bar is then drawn as
  /// a fraction of its own half — so the composition still resolves to
  /// `net / peak` of the whole frame, and every column shares one scale.
  final num up;
  final num down;

  @override
  Widget build(BuildContext context) {
    final bool isUp = month.net >= 0;
    final num extent = isUp ? up : down;
    final double fraction = extent <= 0
        ? 0
        : (month.net.abs() / extent).clamp(0.0, 1.0).toDouble();

    final int upFlex = (up / peak * 1000).round().clamp(0, 1000);
    final int downFlex = (down / peak * 1000).round().clamp(0, 1000);

    return Column(
      children: <Widget>[
        // Each half collapses entirely when nothing goes that way; at least
        // one is always non-zero, since an all-zero series never gets here.
        if (upFlex > 0)
          Expanded(
            flex: upFlex,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (isUp)
                  Flexible(
                    flex: (fraction * 1000).round().clamp(1, 1000),
                    child: _bar(true),
                  ),
                Flexible(
                  flex: ((1 - fraction) * 1000).round().clamp(1, 1000),
                  child: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        // The zero line, hairline and recessive — it is a reference, not data.
        Container(height: 1, color: AppColors.gridline),
        // Reserving half the frame for negative months that have not happened
        // would cost every mark half its height.
        if (downFlex > 0)
          Expanded(
            flex: downFlex,
            child: Column(
              children: <Widget>[
                if (!isUp)
                  Flexible(
                    flex: (fraction * 1000).round().clamp(1, 1000),
                    child: _bar(false),
                  ),
                Flexible(
                  flex: ((1 - fraction) * 1000).round().clamp(1, 1000),
                  child: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          month.period.shortLabel.split(' ').first,
          textAlign: TextAlign.center,
          style: TextStyle(
            // The open month is dimmed and marked, because a short bar that is
            // short only because the month is young is the most misleading
            // thing this chart could say.
            color: month.isOpen ? AppColors.muted : AppColors.textSecondary,
            fontSize: 10,
            fontStyle: month.isOpen ? FontStyle.italic : FontStyle.normal,
          ),
          maxLines: 1,
        ),
      ],
    );
  }

  /// The mark itself, capped at [_maxBarWidth] and centred in its slot.
  ///
  /// Thin on purpose. A bar allowed to fill its share of the width becomes a
  /// saturated block as soon as there are only two or three months — loud,
  /// and harder to compare than a narrow mark, because the eye reads the
  /// rectangle's area rather than its height.
  static const double _maxBarWidth = 26;

  Widget _bar(bool up) {
    final Color tone = up ? AppColors.statusGood : _markFill;
    return Center(
      child: ConstrainedBox(
        key: ValueKey<String>('net-bar-${month.period.id}'),
        constraints: const BoxConstraints(maxWidth: _maxBarWidth),
        child: Opacity(
          opacity: month.isOpen ? 0.55 : 1,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(up ? 3 : 0),
                bottom: Radius.circular(up ? 0 : 3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared chrome: a title, a quiet subtitle, and generous padding.
class _ChartFrame extends StatelessWidget {
  const _ChartFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gridline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
