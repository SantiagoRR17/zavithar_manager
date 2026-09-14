// Widget tests for the charts.
//
// The palette validator checks colour; it cannot check geometry. These render
// the charts at real phone widths with awkward data — a very long category
// name, a huge number, a single dominant bar, a month with nothing in it — and
// fail on any overflow, which is how a chart breaks in practice.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/features/dashboard/domain/spending_insights.dart';
import 'package:zavithar_manager/features/dashboard/presentation/widgets/spending_charts.dart';
import 'package:zavithar_manager/features/finance/domain/statement_period.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {double width = 360}) {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // The category chart resolves its labels from the user's own list, so it
    // needs a container. With nothing stored it falls back to the built-in
    // defaults, which is exactly the state these tests assert against.
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  group('CategorySpendChart', () {
    test('nothing to plot is nothing drawn', () {
      // Checked here rather than in a pump: the widget short-circuits before
      // building, so there is no tree to inspect.
      expect(const CategorySpendChart(rows: <CategorySpend>[]).rows, isEmpty);
    });

    testWidgets('renders a full set of bars without overflowing', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        const CategorySpendChart(
          rows: <CategorySpend>[
            CategorySpend(category: 'rent', amount: 1800000),
            CategorySpend(category: 'groceries', amount: 640000),
            CategorySpend(category: 'eating out', amount: 310000),
            CategorySpend(category: 'transport', amount: 180000),
            CategorySpend(category: 'health', amount: 90000),
            CategorySpend(category: 'entertainment', amount: 45000),
            CategorySpend(category: 'other', amount: 12000),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Where it went'), findsOneWidget);
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text(r'$1.800.000'), findsOneWidget);
    });

    testWidgets('a long label is truncated rather than pushing the value off', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        const CategorySpendChart(
          rows: <CategorySpend>[
            CategorySpend(
              category: 'a category with an unreasonably long name indeed',
              amount: 100000,
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      // The amount survives; it is the label that gives way.
      expect(find.text(r'$100.000'), findsOneWidget);
    });

    testWidgets('survives a narrow phone', (WidgetTester tester) async {
      await pump(
        tester,
        const CategorySpendChart(
          rows: <CategorySpend>[
            CategorySpend(category: 'entertainment', amount: 12345678),
            CategorySpend(category: 'groceries', amount: 1),
          ],
        ),
        width: 320,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('MonthlyNetChart', () {
    MonthlyTotals month(
      int m, {
      num income = 0,
      num expense = 0,
      bool open = false,
    }) {
      return MonthlyTotals(
        period: StatementPeriod(2026, m),
        income: income,
        expense: expense,
        isOpen: open,
      );
    }

    testWidgets('draws positive and negative months without overflowing', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        MonthlyNetChart(
          series: <MonthlyTotals>[
            month(4, income: 3000000, expense: 2100000),
            month(5, income: 3000000, expense: 3400000),
            month(6, income: 3000000, expense: 1200000),
            month(7, income: 3000000, expense: 2900000),
            month(8, income: 3000000, expense: 2000000),
            month(9, income: 1000000, expense: 300000, open: true),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Month by month'), findsOneWidget);
      // One label per month, abbreviated.
      expect(find.text('Apr'), findsOneWidget);
      expect(find.text('Sep'), findsOneWidget);
    });

    testWidgets('a month with nothing in it still draws its label', (
      WidgetTester tester,
    ) async {
      // The open month is routinely empty on the 1st, and a chart that dropped
      // it would appear to end last month.
      await pump(
        tester,
        MonthlyNetChart(
          series: <MonthlyTotals>[
            month(8, income: 100000, expense: 20000),
            month(9, open: true),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sep'), findsOneWidget);
    });

    testWidgets('an all-positive series uses the whole frame height', (
      WidgetTester tester,
    ) async {
      // The axis spans the data. With no negative month there is nothing below
      // the zero line, so the tallest bar should fill nearly the whole 140px
      // frame rather than the ~70px an evenly split axis would leave it.
      await pump(
        tester,
        MonthlyNetChart(
          series: <MonthlyTotals>[
            month(8, income: 1000000),
            month(9, income: 500000, open: true),
          ],
        ),
      );

      final Size tallest = tester.getSize(
        find.byKey(const ValueKey<String>('net-bar-2026-08')),
      );
      expect(tallest.height, greaterThan(100));
      // Still measured against one shared scale: half the value, half the bar.
      final Size half = tester.getSize(
        find.byKey(const ValueKey<String>('net-bar-2026-09')),
      );
      expect(half.height, closeTo(tallest.height / 2, 4));
    });

    testWidgets('a negative month opens exactly the space it needs', (
      WidgetTester tester,
    ) async {
      // The loss here is a quarter of the peak, so the space below the line is
      // a quarter of what is above it — not the half an even split would give.
      await pump(
        tester,
        MonthlyNetChart(
          series: <MonthlyTotals>[
            month(8, income: 1000000),
            month(9, expense: 250000, open: true),
          ],
        ),
      );

      final double up = tester
          .getSize(find.byKey(const ValueKey<String>('net-bar-2026-08')))
          .height;
      final double down = tester
          .getSize(find.byKey(const ValueKey<String>('net-bar-2026-09')))
          .height;
      expect(down, closeTo(up / 4, 4));
    });

    testWidgets('a single month is not a chart', (WidgetTester tester) async {
      // One bar compared against nothing is a stat tile with extra steps, and
      // the dashboard already has those.
      await pump(
        tester,
        MonthlyNetChart(
          series: <MonthlyTotals>[month(9, income: 5, open: true)],
        ),
      );

      expect(find.text('Month by month'), findsNothing);
    });

    testWidgets('an all-zero series draws nothing rather than dividing by it', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        MonthlyNetChart(
          series: <MonthlyTotals>[month(8), month(9, open: true)],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Month by month'), findsNothing);
    });
  });
}
