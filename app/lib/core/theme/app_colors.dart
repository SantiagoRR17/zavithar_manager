import 'package:flutter/material.dart';

/// The single source of truth for every colour in Zavithar Manager.
///
/// Why this file exists: the brand palette was settled during the mockup phase
/// (see `CLAUDE.md` → "Brand & UI tokens" and `claude/brand-guide.md`). If those
/// hex values are copied around the codebase they drift, and a palette change
/// turns into a find-and-replace across dozens of files. So the project rule is:
/// **hex literals appear here and nowhere else.** Everything else refers to
/// these constants, or better, to the [ThemeData] built from them in
/// `app_theme.dart`.
///
/// The values below are copied verbatim from the CSS custom properties used in
/// the HTML mockups, so the Flutter app and the prototype stay identical.
abstract final class AppColors {
  // --- Surfaces ---------------------------------------------------------

  /// The page background, behind everything else.
  static const Color page = Color(0xFF0D0D0D);

  /// Cards, screens, headers — the primary raised surface.
  static const Color surface1 = Color(0xFF1A1A19);

  /// Sidebar and secondary panels. Slightly *darker* than [surface1], which is
  /// deliberate: in this palette secondary chrome recedes rather than lifts.
  static const Color surface2 = Color(0xFF161413);

  /// Hairline borders, dividers, chart gridlines.
  static const Color gridline = Color(0xFF2C2C2A);

  // --- Text -------------------------------------------------------------

  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Body copy and labels. A warm off-white, not grey — it belongs to the same
  /// family as the brand red rather than fighting it.
  static const Color textSecondary = Color(0xFFC3C2B7);

  /// De-emphasised text: hints, timestamps, disabled states.
  static const Color muted = Color(0xFF898781);

  // --- Brand ------------------------------------------------------------

  /// Buttons, active nav/tabs, links.
  static const Color brandPrimary = Color(0xFFB3122B);

  /// Gradient highlight and hover state.
  static const Color brandPrimaryLight = Color(0xFFFF3B57);

  /// Gradient shadow and pressed state.
  static const Color brandPrimaryDark = Color(0xFF6E0D1A);

  // --- Todo categories --------------------------------------------------
  //
  // These four have a *fixed* order and a fixed meaning. They are never
  // reassigned or cycled through — "work is orange" has to stay true across
  // every screen, or the colour stops carrying information. See [categoryOrder].

  static const Color categoryWork = Color(0xFFD95926); // orange
  static const Color categoryHobbies = Color(0xFF199E70); // aqua/green
  static const Color categoryStudy = Color(0xFFC98500); // gold
  static const Color categoryHome = Color(0xFF9085E9); // violet

  /// Category colours keyed by the `category` field stored in Firestore
  /// (see `claude/data-model.md` → `users/{uid}/todos/{todoId}`).
  static const Map<String, Color> categoryColors = <String, Color>{
    'work': categoryWork,
    'hobbies': categoryHobbies,
    'study': categoryStudy,
    'home': categoryHome,
  };

  /// The canonical display order for categories. Anything that renders a list
  /// of categories walks this, so the order is the same everywhere.
  static const List<String> categoryOrder = <String>[
    'work',
    'hobbies',
    'study',
    'home',
  ];

  /// The ink to paint on a category colour.
  ///
  /// **Dark, on all four** — and measured, not guessed. The four category
  /// colours are saturated mid-tones, and white on them ranges from 3.07:1
  /// (gold) to 3.88:1 (orange): every one of them fails the 4.5:1 that an
  /// 11px pill label needs, not just the gold that was obviously wrong by
  /// eye. The page colour scores 5.00:1 to 6.33:1 on the same four.
  ///
  /// The colours themselves are untouched — the brand fixes those and they
  /// are never reassigned. This changes only what is written on them.
  ///
  /// A category the brand has no colour for is drawn on [muted], which takes
  /// the same dark ink at 5.41:1.
  static Color onCategory(String category) => page;

  // --- Status -----------------------------------------------------------
  //
  // Project rule: a status colour is *never* the only signal. It always ships
  // alongside an icon or a text label, so the meaning survives colour blindness
  // and greyscale screenshots.

  static const Color statusGood = Color(0xFF0CA30C);
  static const Color statusWarning = Color(0xFFFAB219);
  static const Color statusSerious = Color(0xFFEC835A);
  static const Color statusCritical = Color(0xFFE66767);
}
