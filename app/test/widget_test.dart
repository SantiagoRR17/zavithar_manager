// Widget tests for Zavithar Manager.
//
// The generated counter-app test was removed with the counter app. Real
// coverage arrives with the first feature that has logic worth testing
// (Milestone 1), per `claude/testing-plan.md`. What is here now is the smallest
// meaningful check: that the design tokens the whole UI depends on are intact.
//
// Note that widget-testing the app itself is not as simple as pumping
// `ZavitharManagerApp()`: it calls `Firebase.initializeApp` in `main`, so a test
// needs either a fake `AuthRepository` injected through a `ProviderScope`
// override, or the Firebase emulator. That is exactly what the repository layer
// was built for, and it is set up when the first such test is written.

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/core/theme/app_colors.dart';

void main() {
  group('AppColors', () {
    test('every todo category in the fixed order has a colour', () {
      for (final String category in AppColors.categoryOrder) {
        expect(
          AppColors.categoryColors[category],
          isNotNull,
          reason: 'Category "$category" is in categoryOrder but has no colour.',
        );
      }
      expect(
        AppColors.categoryColors.length,
        AppColors.categoryOrder.length,
        reason: 'categoryColors and categoryOrder have drifted apart.',
      );
    });

    test('category colours are distinct', () {
      final Set<int> values = AppColors.categoryColors.values
          .map((c) => c.toARGB32())
          .toSet();
      expect(values.length, AppColors.categoryColors.length);
    });

    test('every category takes dark ink', () {
      // It used to be gold only. Measuring the other three showed white
      // failing on all of them — see `test/theme/contrast_test.dart`, which
      // computes the ratios rather than asserting the colours by hand.
      for (final String category in AppColors.categoryOrder) {
        expect(AppColors.onCategory(category), AppColors.page);
      }
    });
  });
}
