// Contrast tests for the dark palette — Milestone 4.
//
// **These compute the ratio; they do not assert a colour.** Reviewing a dark
// theme by eye is what let two real failures sit in the app unnoticed: white on
// the category colours measured 3.07:1 to 3.88:1, and the selected segment of
// a SegmentedButton measured 3.49:1. Neither looked wrong — on a dark screen
// a saturated fill reads as "vivid" long after its label has stopped being
// legible, and the one case that *was* obvious by eye (gold) was the only one
// anybody had fixed.
//
// The thresholds are WCAG 2.1: 4.5:1 for body text, 3:1 for text at 18px or
// 14px bold, and 3:1 for the boundary of a control that carries meaning.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zavithar_manager/core/theme/app_colors.dart';

/// Relative luminance, per WCAG 2.1.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// The WCAG contrast ratio between two opaque colours, 1.0 to 21.0.
double contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double lighter = math.max(la, lb);
  final double darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  /// Anything below this is unreadable as small text, whatever it looks like.
  const double bodyText = 4.5;

  /// Large or bold text, and the meaningful edges of a control.
  const double largeText = 3.0;

  group('contrast helper', () {
    test('is calibrated against the known extremes', () {
      expect(contrast(const Color(0xFFFFFFFF), const Color(0xFF000000)), 21.0);
      expect(contrast(AppColors.page, AppColors.page), 1.0);
    });
  });

  group('ink on surfaces', () {
    const Map<String, Color> surfaces = <String, Color>{
      'page': AppColors.page,
      'surface1': AppColors.surface1,
      'surface2': AppColors.surface2,
    };

    test('primary and secondary text are readable on every surface', () {
      for (final MapEntry<String, Color> s in surfaces.entries) {
        for (final Color ink in <Color>[
          AppColors.textPrimary,
          AppColors.textSecondary,
        ]) {
          expect(
            contrast(ink, s.value),
            greaterThanOrEqualTo(bodyText),
            reason: 'text on ${s.key}',
          );
        }
      }
    });

    test('**muted still clears the body-text floor**', () {
      // It sits at 4.85:1 against surface-1, which is a pass with very little
      // room. Any future darkening of this token breaks captions everywhere,
      // and that is exactly the change nobody would notice by eye.
      for (final MapEntry<String, Color> s in surfaces.entries) {
        expect(
          contrast(AppColors.muted, s.value),
          greaterThanOrEqualTo(bodyText),
          reason: 'muted on ${s.key}',
        );
      }
    });
  });

  group('status colours as text', () {
    test('every status reads on a card', () {
      const Map<String, Color> statuses = <String, Color>{
        'good': AppColors.statusGood,
        'warning': AppColors.statusWarning,
        'serious': AppColors.statusSerious,
        'critical': AppColors.statusCritical,
      };
      for (final MapEntry<String, Color> s in statuses.entries) {
        expect(
          contrast(s.value, AppColors.surface1),
          greaterThanOrEqualTo(bodyText),
          reason: '${s.key} on surface1',
        );
      }
    });
  });

  group('brand', () {
    test('**brandPrimary is a fill colour, never an ink one**', () {
      // 2.52:1 on surface-1. This is the finding the chart work turned up and
      // the reason the data marks use brandPrimaryLight. Pinned here so the
      // next person who reaches for "the brand red" for a label sees why not.
      expect(
        contrast(AppColors.brandPrimary, AppColors.surface1),
        lessThan(largeText),
      );
      // As a fill with white on it, though, it is comfortable — which is what
      // the primary button, the nav indicator and the selected segment use.
      expect(
        contrast(AppColors.textPrimary, AppColors.brandPrimary),
        greaterThanOrEqualTo(bodyText),
      );
    });

    test('brandPrimaryLight is the readable accent', () {
      expect(
        contrast(AppColors.brandPrimaryLight, AppColors.surface1),
        greaterThanOrEqualTo(bodyText),
      );
    });

    test('**white on brandPrimaryLight is not a usable pairing**', () {
      // 3.49:1. It was the Material default for a selected segment, and it is
      // why `segmentedButtonTheme` exists rather than being left to the
      // colour scheme.
      expect(
        contrast(AppColors.textPrimary, AppColors.brandPrimaryLight),
        lessThan(bodyText),
      );
    });
  });

  group('category pills', () {
    test('**every category label is readable on its own colour**', () {
      // The pill label is 11px, so the body-text floor applies to all four —
      // not only to the gold that happened to look wrong.
      for (final String category in AppColors.categoryOrder) {
        final Color background = AppColors.categoryColors[category]!;
        expect(
          contrast(AppColors.onCategory(category), background),
          greaterThanOrEqualTo(bodyText),
          reason: 'label on $category',
        );
      }
    });

    test('white would have failed on every one of them', () {
      // The record of why the ink is dark. If a category colour is ever
      // re-picked light enough for white to work, this test says so.
      for (final String category in AppColors.categoryOrder) {
        expect(
          contrast(AppColors.textPrimary, AppColors.categoryColors[category]!),
          lessThan(bodyText),
          reason: category,
        );
      }
    });

    test('a category with no brand colour is still readable', () {
      // A fifth user-added todo category is drawn on the muted tone.
      expect(
        contrast(AppColors.onCategory('errands'), AppColors.muted),
        greaterThanOrEqualTo(bodyText),
      );
    });

    test('the four colours are distinguishable from each other', () {
      // Not a WCAG rule — a chip that cannot be told from its neighbour is
      // useless whatever its label contrast, and the fixed order only means
      // something while the four are actually different.
      final List<Color> colours = AppColors.categoryOrder
          .map((String c) => AppColors.categoryColors[c]!)
          .toList();
      for (int i = 0; i < colours.length; i++) {
        for (int j = i + 1; j < colours.length; j++) {
          expect(colours[i].toARGB32(), isNot(colours[j].toARGB32()));
        }
      }
    });
  });
}
